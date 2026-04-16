"""Pure helper functions for the Python self-ask scaffold."""

from __future__ import annotations

import re
from typing import Any

CHUNK_TARGET_CHARS = 4800
CHUNK_OVERLAP_CHARS = 600

PRIORITY: dict[str, int] = {
    "feature_map": 10,
    "strategy": 5,
    "changelog_entry": 5,
    "module": 3,
    "script": 2,
    "doc": 1,
    "test": 1,
    "pr": 1,
}

# Source-code ingestion mode constants
CODE_CHUNK_TARGET_CHARS = 3200
CODE_CHUNK_OVERLAP_CHARS = 400


def chunk_text(
    text: str,
    *,
    target_chars: int = CHUNK_TARGET_CHARS,
    overlap: int = CHUNK_OVERLAP_CHARS,
) -> list[str]:
    """Split text into overlap-aware chunks."""
    if not isinstance(text, str):
        raise TypeError("chunk_text: text must be a string")
    if target_chars <= 0:
        raise ValueError("chunk_text: target_chars must be > 0")
    if overlap < 0 or overlap >= target_chars:
        raise ValueError("chunk_text: overlap must be >= 0 and < target_chars")
    if not text:
        return []
    if len(text) <= target_chars:
        return [text]

    chunks: list[str] = []
    start = 0
    while start < len(text):
        end = min(start + target_chars, len(text))
        chunks.append(text[start:end])
        if end >= len(text):
            break
        start = end - overlap
    return chunks


def chunk_changelog(text: str) -> list[dict[str, str | None]]:
    """Split a changelog by semver section headings."""
    if not isinstance(text, str):
        raise TypeError("chunk_changelog: text must be a string")

    parts = [
        p.strip()
        for p in re.split(r"(?=^##\s+(?:\[)?\d+\.\d+\.\d+(?:\])?)", text, flags=re.M)
        if p.strip()
    ]
    rows: list[dict[str, str | None]] = []
    for entry in parts:
        match = re.match(r"^##\s+(?:\[)?(\d+\.\d+\.\d+)(?:\])?", entry)
        rows.append({"version": match.group(1) if match else None, "content": entry})
    return rows


# Regex that matches a top-level (no leading whitespace) Python def or class line.
_TOP_LEVEL_DEF = re.compile(r"^(?:def |class |async def )", re.M)


def chunk_code(
    text: str,
    *,
    target_chars: int = CODE_CHUNK_TARGET_CHARS,
    overlap: int = CODE_CHUNK_OVERLAP_CHARS,
) -> list[str]:
    """Split Python source code into chunks on top-level def/class boundaries.

    Each chunk starts at a top-level ``def``, ``async def``, or ``class``
    declaration.  If a single definition block exceeds *target_chars*, it is
    further divided by :func:`chunk_text` so the embedding payload stays
    within the model's recommended size.

    A leading module-level preamble (imports, constants before the first
    top-level definition) is included as its own chunk when non-trivial.
    """
    if not isinstance(text, str):
        raise TypeError("chunk_code: text must be a string")
    if not text.strip():
        return []

    # Find all top-level def/class boundary positions.
    boundaries = [m.start() for m in _TOP_LEVEL_DEF.finditer(text)]

    if not boundaries:
        # No top-level definitions found — treat as plain text.
        safe_overlap = min(overlap, max(0, target_chars - 1))
        return chunk_text(text, target_chars=target_chars, overlap=safe_overlap)

    segments: list[str] = []

    # Preamble before the first definition.
    preamble = text[: boundaries[0]].strip()
    if len(preamble) > 50:  # only include non-trivial preambles
        segments.append(preamble)

    # Extract each top-level block.
    for i, start in enumerate(boundaries):
        end = boundaries[i + 1] if i + 1 < len(boundaries) else len(text)
        block = text[start:end].strip()
        if block:
            segments.append(block)

    # For each segment that exceeds target_chars, subdivide with chunk_text.
    # Clamp overlap so it stays < target_chars (guards against tiny target_chars
    # values used in tests or spike runs).
    safe_overlap = min(overlap, max(0, target_chars - 1))
    chunks: list[str] = []
    for seg in segments:
        if len(seg) <= target_chars:
            chunks.append(seg)
        else:
            chunks.extend(chunk_text(seg, target_chars=target_chars, overlap=safe_overlap))
    return chunks


def classify_doc(rel_path: str) -> dict[str, Any]:
    """Classify doc source type and retrieval priority from repo-relative path."""
    if not isinstance(rel_path, str) or not rel_path:
        raise TypeError("classify_doc: rel_path must be a non-empty string")

    if re.search(r"changelog\.md$", rel_path, flags=re.I):
        return {"source": "changelog", "priority": PRIORITY["changelog_entry"]}
    if re.search(r"strategy|product.*brief|moat|pmf|positioning", rel_path, flags=re.I):
        return {"source": "strategy", "priority": PRIORITY["strategy"]}

    # Source-code classifications
    if rel_path.endswith(".py"):
        if re.search(r"^tests/", rel_path):
            return {"source": "test", "priority": PRIORITY["test"]}
        if re.search(r"^wpdbtk/", rel_path):
            return {"source": "module", "priority": PRIORITY["module"]}
        # Root-level wpdbtk-*.py scripts
        if re.search(r"^wpdbtk-[^/]+\.py$", rel_path):
            return {"source": "script", "priority": PRIORITY["script"]}

    return {"source": "doc", "priority": PRIORITY["doc"]}


def format_context(hits: list[dict[str, Any]], max_context_chars: int = 80000) -> str:
    """Render retrieved hits into a bounded context payload for synthesis."""
    if not isinstance(hits, list):
        raise TypeError("format_context: hits must be a list")

    parts: list[str] = []
    total = 0
    for hit in hits:
        if not isinstance(hit, dict):
            continue
        content = hit.get("content")
        if not isinstance(content, str):
            continue

        source = hit.get("source")
        if source == "pr":
            header = f"[PR #{hit.get('pr_number')}]"
        elif source == "changelog":
            version = hit.get("version")
            header = f"[changelog.md — {version}]" if version else "[changelog.md]"
        elif source in ("module", "script", "test"):
            header = f"[{hit.get('path') or source}]"
        else:
            header = f"[{hit.get('path') or source or 'unknown'}]"

        block = f"=== {header} ===\n{content}\n"
        if total + len(block) > max_context_chars:
            break
        parts.append(block)
        total += len(block)

    return "\n".join(parts)
