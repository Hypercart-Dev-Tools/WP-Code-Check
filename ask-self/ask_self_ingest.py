"""Python ingest path for the ask-self RAG scaffold."""

from __future__ import annotations

import argparse
import array
import concurrent.futures
import json
import os
import re
import sqlite3
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import requests
import sqlite_vec

from wpdbtk.ask_self_helpers import (
    CHUNK_TARGET_CHARS,
    PRIORITY,
    chunk_changelog,
    chunk_code,
    chunk_text,
    classify_doc,
)

EMBED_MODEL = "gemini-embedding-001"
EMBED_DIM = 768
DEFAULT_PR_FETCH_LIMIT = 200

REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DB_PATH = REPO_ROOT / "temp" / "rag" / "wpdbtk-self-ask.sqlite"

INCLUDE_DOCS: tuple[re.Pattern[str], ...] = (
    re.compile(r"^[^/]+\.md$"),
    re.compile(r"^PROJECT/.+\.md$"),
)

EXCLUDE_PATHS: tuple[re.Pattern[str], ...] = (
    re.compile(r"^node_modules/"),
    re.compile(r"^\.git/"),
    re.compile(r"^data/"),
    re.compile(r"^temp/"),
    re.compile(r"^tests/"),
    re.compile(r"^scratch/"),
)

DEFAULT_DOC_EXTENSIONS: tuple[str, ...] = (".md",)

# --- Source-code corpus mode ---

INCLUDE_SOURCE: tuple[re.Pattern[str], ...] = (
    # Root-level wpdbtk-*.py CLI scripts
    re.compile(r"^wpdbtk-[^/]+\.py$"),
    # wpdbtk/ package modules (excluding __pycache__ etc.)
    re.compile(r"^wpdbtk/[^/]+\.py$"),
)

EXCLUDE_SOURCE_PATHS: tuple[re.Pattern[str], ...] = (
    re.compile(r"^\.git/"),
    re.compile(r"^\.venv/"),
    re.compile(r"^node_modules/"),
    re.compile(r"^mlx-embeddings/"),
    re.compile(r"^vector/"),
    re.compile(r"^spike/"),
    re.compile(r"^temp/"),
    re.compile(r"^scratch/"),
)

DEFAULT_SOURCE_EXTENSIONS: tuple[str, ...] = (".py",)

INGEST_MODES = ("docs", "code", "all")


@dataclass
class ChunkRow:
    source: str
    content: str
    path: str | None = None
    pr_number: int | None = None
    version: str | None = None
    priority: int = 1



def _vector_to_blob(values: list[float]) -> bytes:
    return array.array("f", values).tobytes()


def _compile_patterns(patterns: list[str] | tuple[str, ...] | None) -> list[re.Pattern[str]]:
    if not patterns:
        return []
    return [re.compile(pattern) for pattern in patterns]


def _normalize_extensions(extensions: list[str] | tuple[str, ...] | None) -> tuple[str, ...]:
    if not extensions:
        return DEFAULT_DOC_EXTENSIONS
    cleaned: list[str] = []
    for ext in extensions:
        text = str(ext).strip()
        if not text:
            continue
        if not text.startswith("."):
            text = "." + text
        cleaned.append(text.lower())
    if not cleaned:
        return DEFAULT_DOC_EXTENSIONS
    return tuple(dict.fromkeys(cleaned))


def walk_repo_files(
    repo_root: Path,
    *,
    include_patterns: list[re.Pattern[str]] | tuple[re.Pattern[str], ...] = INCLUDE_DOCS,
    exclude_patterns: list[re.Pattern[str]] | tuple[re.Pattern[str], ...] = EXCLUDE_PATHS,
    extensions: list[str] | tuple[str, ...] = DEFAULT_DOC_EXTENSIONS,
) -> list[Path]:
    ext_filter = _normalize_extensions(extensions)
    found: list[Path] = []
    for path in repo_root.rglob("*"):
        if not path.is_file():
            continue
        if path.suffix.lower() not in ext_filter:
            continue
        rel = path.relative_to(repo_root).as_posix()
        if any(rx.search(rel) for rx in exclude_patterns):
            continue
        if any(rx.search(rel) for rx in include_patterns):
            found.append(path)
    found.sort(key=lambda p: p.as_posix())
    return found


def embed_one(text: str, api_key: str, *, task_type: str = "RETRIEVAL_DOCUMENT") -> list[float]:
    endpoint = (
        "https://generativelanguage.googleapis.com/v1beta/models/"
        f"{EMBED_MODEL}:embedContent?key={api_key}"
    )
    payload = {
        "model": f"models/{EMBED_MODEL}",
        "content": {"parts": [{"text": text}]},
        "taskType": task_type,
        "outputDimensionality": EMBED_DIM,
    }
    resp = requests.post(endpoint, json=payload, timeout=60)
    if not resp.ok:
        raise RuntimeError(f"Gemini embed {resp.status_code}: {resp.text[:400]}")
    data = resp.json()
    values = (data.get("embedding") or {}).get("values")
    if not isinstance(values, list) or len(values) != EMBED_DIM:
        got = len(values) if isinstance(values, list) else None
        raise RuntimeError(f"Gemini embed: unexpected shape, got {got} dims")
    return [float(v) for v in values]


def embed_batch(texts: list[str], api_key: str, *, concurrency: int = 4) -> list[list[float]]:
    out: list[list[float] | None] = [None] * len(texts)

    def work(idx: int) -> None:
        attempt = 0
        while True:
            try:
                out[idx] = embed_one(texts[idx], api_key)
                return
            except Exception:
                attempt += 1
                if attempt >= 3:
                    raise
                time.sleep(0.5 * attempt)

    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, concurrency)) as pool:
        futures = [pool.submit(work, i) for i in range(len(texts))]
        for fut in futures:
            fut.result()

    return [v for v in out if v is not None]


def fetch_merged_prs(
    *,
    owner: str,
    repo: str,
    token: str | None,
    limit: int = DEFAULT_PR_FETCH_LIMIT,
) -> list[dict[str, Any]]:
    if not token:
        return []

    url = f"https://api.github.com/repos/{owner}/{repo}/pulls"
    headers = {
        "Accept": "application/vnd.github+json",
        "Authorization": f"Bearer {token}",
        "X-GitHub-Api-Version": "2022-11-28",
    }

    page = 1
    merged: list[dict[str, Any]] = []
    while len(merged) < limit:
        resp = requests.get(
            url,
            headers=headers,
            params={
                "state": "closed",
                "sort": "updated",
                "direction": "desc",
                "per_page": 100,
                "page": page,
            },
            timeout=30,
        )
        if not resp.ok:
            raise RuntimeError(f"GitHub PR fetch failed {resp.status_code}: {resp.text[:300]}")

        rows = resp.json()
        if not rows:
            break
        for pr in rows:
            if pr.get("merged_at"):
                merged.append(pr)
                if len(merged) >= limit:
                    break
        page += 1

    return merged[:limit]


def open_db(db_path: Path) -> sqlite3.Connection:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    if db_path.exists():
        db_path.unlink()

    conn = sqlite3.connect(str(db_path))
    conn.enable_load_extension(True)
    sqlite_vec.load(conn)
    conn.execute(
        """
        CREATE TABLE chunks (
          id INTEGER PRIMARY KEY,
          source TEXT NOT NULL,
          path TEXT,
          pr_number INTEGER,
          version TEXT,
          priority INTEGER NOT NULL DEFAULT 1,
          content TEXT NOT NULL,
          created_at TEXT NOT NULL DEFAULT (datetime('now'))
        )
        """
    )
    conn.execute(f"CREATE VIRTUAL TABLE chunks_vec USING vec0(embedding float[{EMBED_DIM}])")
    conn.commit()
    return conn


def insert_chunk(conn: sqlite3.Connection, row: ChunkRow, embedding: list[float]) -> None:
    cur = conn.execute(
        (
            "INSERT INTO chunks (source, path, pr_number, version, priority, content) "
            "VALUES (?, ?, ?, ?, ?, ?)"
        ),
        (row.source, row.path, row.pr_number, row.version, row.priority, row.content),
    )
    rowid = int(cur.lastrowid)
    conn.execute(
        "INSERT INTO chunks_vec(rowid, embedding) VALUES (?, ?)",
        (rowid, _vector_to_blob(embedding)),
    )


def build_doc_rows(
    repo_root: Path,
    *,
    max_doc_files: int | None = None,
    include_patterns: list[str] | tuple[str, ...] | None = None,
    exclude_patterns: list[str] | tuple[str, ...] | None = None,
    doc_extensions: list[str] | tuple[str, ...] | None = None,
    source_allowlist: list[str] | tuple[str, ...] | None = None,
    mode: str = "docs",
) -> list[ChunkRow]:
    """Build ChunkRows from the repository corpus.

    *mode* controls which default patterns are applied when *include_patterns*,
    *exclude_patterns*, and *doc_extensions* are not explicitly overridden:

    - ``"docs"``  — Markdown documentation (default).
    - ``"code"``  — Python source files under ``wpdbtk/`` and root-level
      ``wpdbtk-*.py`` scripts.
    - ``"all"``   — Both docs and code combined.
    """
    if mode not in INGEST_MODES:
        raise ValueError(f"build_doc_rows: mode must be one of {INGEST_MODES}")

    # Resolve effective defaults based on mode when caller didn't override.
    if include_patterns is not None:
        inc_rx = _compile_patterns(list(include_patterns))
    elif mode == "code":
        inc_rx = list(INCLUDE_SOURCE)
    elif mode == "all":
        inc_rx = list(INCLUDE_DOCS) + list(INCLUDE_SOURCE)
    else:  # "docs"
        inc_rx = list(INCLUDE_DOCS)

    if exclude_patterns is not None:
        exc_rx = _compile_patterns(list(exclude_patterns))
    elif mode == "code":
        exc_rx = list(EXCLUDE_SOURCE_PATHS)
    elif mode == "all":
        # Union: keep a path only if it passes both sets.
        exc_rx = list(EXCLUDE_PATHS) + [p for p in EXCLUDE_SOURCE_PATHS if p not in EXCLUDE_PATHS]
    else:
        exc_rx = list(EXCLUDE_PATHS)

    if doc_extensions is not None:
        ext_list: list[str] = list(doc_extensions)
    elif mode == "code":
        ext_list = list(DEFAULT_SOURCE_EXTENSIONS)
    elif mode == "all":
        ext_list = list(DEFAULT_DOC_EXTENSIONS) + list(DEFAULT_SOURCE_EXTENSIONS)
    else:
        ext_list = list(DEFAULT_DOC_EXTENSIONS)

    files = walk_repo_files(
        repo_root,
        include_patterns=inc_rx,
        exclude_patterns=exc_rx,
        extensions=ext_list,
    )
    if max_doc_files is not None:
        files = files[: max(0, max_doc_files)]

    allowed_sources = {str(s).strip() for s in (source_allowlist or []) if str(s).strip()}

    rows: list[ChunkRow] = []
    for file_path in files:
        rel = file_path.relative_to(repo_root).as_posix()
        text = file_path.read_text(encoding="utf-8", errors="replace")
        doc_class = classify_doc(rel)
        source = str(doc_class["source"])
        priority = int(doc_class["priority"])

        if allowed_sources and source not in allowed_sources:
            continue

        if source == "changelog":
            for entry in chunk_changelog(text):
                rows.append(
                    ChunkRow(
                        source="changelog",
                        path=rel,
                        version=entry["version"],
                        priority=priority,
                        content=str(entry["content"]),
                    )
                )
        elif source in ("module", "script", "test"):
            for chunk in chunk_code(text):
                rows.append(
                    ChunkRow(
                        source=source,
                        path=rel,
                        priority=priority,
                        content=chunk,
                    )
                )
        else:
            for chunk in chunk_text(text):
                rows.append(
                    ChunkRow(
                        source=source,
                        path=rel,
                        priority=priority,
                        content=chunk,
                    )
                )

    return rows


def build_pr_rows(prs: list[dict[str, Any]]) -> list[ChunkRow]:
    rows: list[ChunkRow] = []
    for pr in prs:
        pr_num = pr.get("number")
        body = pr.get("body") or ""
        text = (
            f"PR #{pr_num}: {pr.get('title')}\n"
            f"Merged: {pr.get('merged_at')} by {(pr.get('user') or {}).get('login', 'unknown')}\n\n"
            f"{body}"
        )
        rows.append(
            ChunkRow(
                source="pr",
                path=f"PR #{pr_num}",
                pr_number=int(pr_num),
                priority=PRIORITY["pr"],
                content=text[: CHUNK_TARGET_CHARS * 2],
            )
        )
    return rows


def ingest(
    *,
    repo_root: Path = REPO_ROOT,
    db_path: Path = DEFAULT_DB_PATH,
    include_prs: bool = True,
    github_owner: str = "Hypercart-Dev-Tools",
    github_repo: str = "WP-DB-Toolkit",
    pr_fetch_limit: int = DEFAULT_PR_FETCH_LIMIT,
    max_doc_files: int | None = None,
    max_rows: int | None = None,
    concurrency: int = 4,
    include_patterns: list[str] | None = None,
    exclude_patterns: list[str] | None = None,
    doc_extensions: list[str] | None = None,
    source_allowlist: list[str] | None = None,
    mode: str = "docs",
) -> dict[str, Any]:
    api_key = os.getenv("GOOGLE_API_KEY")
    if not api_key:
        raise RuntimeError("GOOGLE_API_KEY not set")

    t0 = time.time()
    doc_rows = build_doc_rows(
        repo_root,
        max_doc_files=max_doc_files,
        include_patterns=include_patterns,
        exclude_patterns=exclude_patterns,
        doc_extensions=doc_extensions,
        source_allowlist=source_allowlist,
        mode=mode,
    )
    prs: list[dict[str, Any]] = []
    if include_prs:
        token = os.getenv("SLEUTH_RAG_GITHUB_PAT") or os.getenv("GITHUB_TOKEN")
        prs = fetch_merged_prs(
            owner=github_owner,
            repo=github_repo,
            token=token,
            limit=pr_fetch_limit,
        )

    all_rows = doc_rows + build_pr_rows(prs)
    if max_rows is not None:
        all_rows = all_rows[: max(0, max_rows)]

    embeddings = embed_batch([row.content for row in all_rows], api_key, concurrency=concurrency)

    conn = open_db(db_path)
    try:
        with conn:
            for row, embedding in zip(all_rows, embeddings):
                insert_chunk(conn, row, embedding)

        total = conn.execute("SELECT COUNT(*) FROM chunks").fetchone()[0]
        by_source_rows = conn.execute(
            "SELECT source, COUNT(*) AS c FROM chunks GROUP BY source ORDER BY c DESC"
        ).fetchall()
    finally:
        conn.close()

    return {
        "db_path": str(db_path),
        "total_chunks": int(total),
        "by_source": {str(source): int(count) for source, count in by_source_rows},
        "corpus_policy": {
            "mode": mode,
            "include_patterns": include_patterns or [r.pattern for r in INCLUDE_DOCS],
            "exclude_patterns": exclude_patterns or [r.pattern for r in EXCLUDE_PATHS],
            "doc_extensions": doc_extensions or list(DEFAULT_DOC_EXTENSIONS),
            "source_allowlist": source_allowlist or [],
        },
        "elapsed_seconds": round(time.time() - t0, 2),
    }


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Build local ask-self sqlite index (Python scaffold)")
    parser.add_argument("--db-path", default=str(DEFAULT_DB_PATH), help="Output sqlite DB path")
    parser.add_argument("--repo-root", default=str(REPO_ROOT), help="Repo root to ingest")
    parser.add_argument("--no-prs", action="store_true", help="Skip GitHub PR ingestion")
    parser.add_argument("--github-owner", default="Hypercart-Dev-Tools", help="GitHub owner/org")
    parser.add_argument("--github-repo", default="WP-DB-Toolkit", help="GitHub repository")
    parser.add_argument("--pr-fetch-limit", type=int, default=DEFAULT_PR_FETCH_LIMIT, help="Max merged PRs")
    parser.add_argument("--max-doc-files", type=int, default=None, help="Limit markdown files for quick spikes")
    parser.add_argument("--max-rows", type=int, default=None, help="Limit total chunks for quick spikes")
    parser.add_argument("--concurrency", type=int, default=4, help="Embedding concurrency")
    parser.add_argument(
        "--include-pattern",
        action="append",
        dest="include_patterns",
        default=None,
        help="Regex to include repo-relative docs (repeatable)",
    )
    parser.add_argument(
        "--exclude-pattern",
        action="append",
        dest="exclude_patterns",
        default=None,
        help="Regex to exclude repo-relative docs (repeatable)",
    )
    parser.add_argument(
        "--doc-ext",
        action="append",
        dest="doc_extensions",
        default=None,
        help="Document extension to ingest (repeatable, e.g. md)",
    )
    parser.add_argument(
        "--source",
        action="append",
        dest="source_allowlist",
        default=None,
        help="Allow only classified source(s): doc, changelog, strategy (repeatable)",
    )
    parser.add_argument("--json", action="store_true", help="Emit JSON summary")
    parser.add_argument(
        "--mode",
        choices=list(INGEST_MODES),
        default="docs",
        help="Corpus mode: docs (default), code (Python source), or all",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = _build_parser()
    args = parser.parse_args(argv)

    try:
        summary = ingest(
            repo_root=Path(args.repo_root),
            db_path=Path(args.db_path),
            include_prs=not args.no_prs,
            github_owner=args.github_owner,
            github_repo=args.github_repo,
            pr_fetch_limit=args.pr_fetch_limit,
            max_doc_files=args.max_doc_files,
            max_rows=args.max_rows,
            concurrency=max(1, args.concurrency),
            include_patterns=args.include_patterns,
            exclude_patterns=args.exclude_patterns,
            doc_extensions=args.doc_extensions,
            source_allowlist=args.source_allowlist,
            mode=args.mode,
        )
    except Exception as exc:  # noqa: BLE001
        if args.json:
            print(json.dumps({"ok": False, "error": str(exc)}))
        else:
            print(f"ERROR: {exc}")
        return 1

    if args.json:
        print(json.dumps({"ok": True, **summary}, ensure_ascii=False, indent=2))
    else:
        print("Ingest complete")
        print(f"  DB: {summary['db_path']}")
        print(f"  Total chunks: {summary['total_chunks']}")
        print(f"  By source: {summary['by_source']}")
        print(f"  Elapsed: {summary['elapsed_seconds']}s")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
