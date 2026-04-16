"""Python query path for the ask-self RAG scaffold."""

from __future__ import annotations

import argparse
import array
import json
import os
import sqlite3
from pathlib import Path
from typing import Any

import requests
import sqlite_vec

from wpdbtk.ask_self_helpers import format_context

EMBED_MODEL = "gemini-embedding-001"
EMBED_DIM = 768
SYNTHESIS_MODEL = "gemini-pro-latest"
TOP_K = 20
PRIORITY_BOOST = 0.02
MAX_CONTEXT_CHARS = 80000

REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DB_PATH = REPO_ROOT / "temp" / "rag" / "wpdbtk-self-ask.sqlite"
DEFAULT_PROMPTS_PATH = REPO_ROOT / "ask-self" / "ask_self_prompts.json"

_DB_CONN: sqlite3.Connection | None = None
_PROMPTS: dict[str, Any] | None = None


class TenancyError(RuntimeError):
    """Raised when optional tenancy checks fail."""


def _vector_to_blob(values: list[float]) -> bytes:
    return array.array("f", values).tobytes()


def _get_db(db_path: Path) -> sqlite3.Connection:
    global _DB_CONN
    if _DB_CONN is not None:
        return _DB_CONN

    if not db_path.exists():
        raise RuntimeError(f"RAG index missing at {db_path}. Run: wpdbtk-ask-self-ingest.py")

    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    conn.enable_load_extension(True)
    sqlite_vec.load(conn)
    _DB_CONN = conn
    return conn


def _get_prompts(prompts_path: Path) -> dict[str, Any]:
    global _PROMPTS
    if _PROMPTS is not None:
        return _PROMPTS
    with prompts_path.open("r", encoding="utf-8") as fh:
        _PROMPTS = json.load(fh)
    return _PROMPTS


def assert_tenancy(team_id: str | None) -> None:
    """Optional tenant gate. If allowlist is unset, gate is disabled."""
    allowed = os.getenv("WPDBTK_SELF_ASK_TEAM_ID")
    if not allowed:
        return
    if not team_id:
        raise TenancyError("team_id argument required when WPDBTK_SELF_ASK_TEAM_ID is set")
    if team_id != allowed:
        raise TenancyError("team_id does not match allowlist")


def embed_query(query: str, api_key: str) -> bytes:
    endpoint = (
        "https://generativelanguage.googleapis.com/v1beta/models/"
        f"{EMBED_MODEL}:embedContent?key={api_key}"
    )
    payload = {
        "model": f"models/{EMBED_MODEL}",
        "content": {"parts": [{"text": query}]},
        "taskType": "RETRIEVAL_QUERY",
        "outputDimensionality": EMBED_DIM,
    }
    resp = requests.post(endpoint, json=payload, timeout=60)
    if not resp.ok:
        raise RuntimeError(f"Gemini embed {resp.status_code}: {resp.text[:300]}")

    data = resp.json()
    values = (data.get("embedding") or {}).get("values")
    if not isinstance(values, list) or len(values) != EMBED_DIM:
        got = len(values) if isinstance(values, list) else None
        raise RuntimeError(f"Gemini embed: unexpected shape, got {got} dims")
    return _vector_to_blob(values)


def knn_search(conn: sqlite3.Connection, query_vec: bytes, k: int = TOP_K) -> list[dict[str, Any]]:
    hits = conn.execute(
        "SELECT rowid, distance FROM chunks_vec WHERE embedding MATCH ? ORDER BY distance LIMIT ?",
        (query_vec, int(k)),
    ).fetchall()
    if not hits:
        return []

    ids = [int(h["rowid"]) for h in hits]
    placeholders = ",".join("?" for _ in ids)
    rows = conn.execute(
        (
            "SELECT id, source, path, pr_number, version, priority, content "
            f"FROM chunks WHERE id IN ({placeholders})"
        ),
        ids,
    ).fetchall()
    by_id = {int(r["id"]): dict(r) for r in rows}

    dropped: list[int] = []
    ranked: list[dict[str, Any]] = []
    for hit in hits:
        rowid = int(hit["rowid"])
        row = by_id.get(rowid)
        if row is None:
            dropped.append(rowid)
            continue
        score = float(hit["distance"]) - float(row.get("priority", 1) or 1) * PRIORITY_BOOST
        row["distance"] = float(hit["distance"])
        row["score"] = score
        ranked.append(row)

    if dropped:
        print(
            "[self-ask] knn_search: dropped"
            f" {len(dropped)} hit(s) with missing metadata rows"
            f" (rowids: {', '.join(str(x) for x in dropped)}).",
            flush=True,
        )

    ranked.sort(key=lambda x: x["score"])
    return ranked


def synthesize(query: str, context: str, system_prompt: str, api_key: str) -> str:
    endpoint = (
        "https://generativelanguage.googleapis.com/v1beta/models/"
        f"{SYNTHESIS_MODEL}:generateContent?key={api_key}"
    )
    user_message = (
        "CONTEXT (retrieved from WP DB Toolkit corpus):\n\n"
        f"{context}\n\n---\n\nQUESTION: {query}"
    )
    payload = {
        "system_instruction": {"parts": [{"text": system_prompt}]},
        "contents": [{"role": "user", "parts": [{"text": user_message}]}],
        "generationConfig": {"temperature": 0.3, "maxOutputTokens": 1500},
    }
    resp = requests.post(endpoint, json=payload, timeout=90)
    if not resp.ok:
        raise RuntimeError(f"Gemini synthesis {resp.status_code}: {resp.text[:300]}")

    data = resp.json()
    candidates = data.get("candidates") or []
    if not candidates:
        raise RuntimeError("Gemini synthesis: empty response")
    parts = ((candidates[0].get("content") or {}).get("parts") or [])
    text = parts[0].get("text") if parts else None
    if not text:
        raise RuntimeError("Gemini synthesis: empty response")
    return text


def ask_self(
    query: str,
    *,
    team_id: str | None = None,
    db_path: Path = DEFAULT_DB_PATH,
    prompts_path: Path = DEFAULT_PROMPTS_PATH,
) -> str:
    """Answer a toolkit question grounded in the local self-ask index."""
    assert_tenancy(team_id)

    if not isinstance(query, str) or not query.strip():
        raise ValueError("query must be a non-empty string")

    api_key = os.getenv("GOOGLE_API_KEY")
    if not api_key:
        raise RuntimeError("GOOGLE_API_KEY not set")

    prompts = _get_prompts(prompts_path)
    conn = _get_db(db_path)
    query_vec = embed_query(query, api_key)
    hits = knn_search(conn, query_vec, TOP_K)
    if not hits:
        return "I could not find anything in the local index for that question."

    context = format_context(hits, MAX_CONTEXT_CHARS)
    system_prompt = prompts.get("orchestrator_system")
    if not isinstance(system_prompt, str) or not system_prompt.strip():
        raise RuntimeError("prompts.json is missing orchestrator_system")

    answer = synthesize(query, context, system_prompt, api_key)
    source_list: list[str] = []
    for hit in hits[:8]:
        label = f"PR #{hit.get('pr_number')}" if hit.get("source") == "pr" else (hit.get("path") or "unknown")
        if label not in source_list:
            source_list.append(label)

    return f"{answer}\n\nSources consulted: {', '.join(source_list)}"


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Query the local ask-self index (Python scaffold)")
    parser.add_argument("query", help="Question to ask against the local corpus")
    parser.add_argument("--team-id", default=None, help="Optional team id for allowlist checks")
    parser.add_argument("--db-path", default=str(DEFAULT_DB_PATH), help="Path to sqlite self-ask DB")
    parser.add_argument("--prompts-path", default=str(DEFAULT_PROMPTS_PATH), help="Path to prompts JSON")
    parser.add_argument("--json", action="store_true", help="Emit structured JSON output")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = _build_parser()
    args = parser.parse_args(argv)
    try:
        answer = ask_self(
            args.query,
            team_id=args.team_id,
            db_path=Path(args.db_path),
            prompts_path=Path(args.prompts_path),
        )
    except Exception as exc:  # noqa: BLE001
        if args.json:
            print(json.dumps({"ok": False, "error": str(exc)}))
        else:
            print(f"ERROR: {exc}")
        return 1

    if args.json:
        print(json.dumps({"ok": True, "answer": answer}, ensure_ascii=False))
    else:
        print(answer)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
