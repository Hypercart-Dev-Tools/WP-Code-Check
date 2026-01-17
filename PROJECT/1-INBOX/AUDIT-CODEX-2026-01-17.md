# Codebase Audit - Codex Review (2026-01-17)

**Scope:** High-level scan of core scanner flow and registry loader. Focus on JSON output integrity, registry-backed loader, and pattern loading paths.

## Findings (Ordered by Severity)

### 1) JSON output can be corrupted in non-TTY environments
- **Severity:** High
- **Risk:** High (breaks JSON contract for CI/embedders; HTML regen/triage fails)
- **Fix effort:** Medium
- **Evidence:** `dist/bin/check-performance.sh` uses `/dev/tty` for JSON-mode chatter; when no TTY exists, shell errors can leak into logs and JSON output (observed in practice).
- **Code refs:** `dist/bin/check-performance.sh:5832`, `dist/bin/check-performance.sh:5866`, `dist/bin/check-performance.sh:5958`
- **Why it matters:** Any stderr emitted by failed `/dev/tty` redirections (or tools writing to stderr) contaminates JSON, causing downstream `jq`, HTML converter, and AI triage to fail.

- [ ] STATUS: Not Started

### 2) Registry cache parsing is not whitespace-safe
- **Severity:** High
- **Risk:** High (pattern search strings/args with spaces get truncated → false negatives or wrong behavior)
- **Fix effort:** Medium
- **Evidence:** The registry cache encodes key/value pairs in a space-delimited line; parsing splits on spaces, so `search_pattern` or `validator_args` containing spaces are broken.
- **Code refs:** `dist/lib/pattern-loader.sh:159`, `dist/lib/pattern-loader.sh:221`, `dist/lib/pattern-loader.sh:265`
- **Why it matters:** Many regex patterns and validator args contain spaces or escaped whitespace. Truncation changes detection logic silently.

- [ ] STATUS: Not Started

### 3) Registry cache temp files are never cleaned up
- **Severity:** Low
- **Risk:** Low (temp directory clutter; can accumulate on long-running or repeated scans)
- **Fix effort:** Low
- **Evidence:** Cache file created with `mktemp`, but never removed.
- **Code refs:** `dist/lib/pattern-loader.sh:147`, `dist/lib/pattern-loader.sh:248`
- **Why it matters:** Not a functional break, but it adds operational noise and can fill `/tmp` over time on automation nodes.

- [ ] STATUS: Not Started

### 4) Fallback JSON parsing is brittle and can misparse
- **Severity:** Medium
- **Risk:** Medium (missing/incorrect pattern metadata if registry unavailable or python missing)
- **Fix effort:** Medium
- **Evidence:** `grep`/`sed` parsing for JSON fields is sensitive to formatting/ordering and nested structures.
- **Code refs:** `dist/lib/pattern-loader.sh:329`, `dist/lib/pattern-loader.sh:336`
- **Why it matters:** In environments without Python or when registry is unavailable, detection behavior may silently diverge from intended rules.

- [ ] STATUS: Not Started

## Open Questions / Assumptions
- Assumed: JSON output is consumed by CI or external tooling and must remain a single valid JSON document.
- Assumed: Pattern `search_pattern` and `validator_args` may include whitespace (common for regex literals and CLI flags).

## Change Summary (No Changes Made)
- This audit is observational only; no files modified.
