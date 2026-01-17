# Codebase Audit - Codex Review (2026-01-17)
**Status:** In Progress
**Priority:** P1 and lower

Attn LLMs: do not create new docs unless directed. Please update this doc with findings, plans, and status. Do not create summary docs unles specifically requested.

**Scope:** High-level scan of core scanner flow and registry loader. Focus on JSON output integrity, registry-backed loader, and pattern loading paths.

## Findings (Ordered by Severity)

### 1) JSON output can be corrupted in non-TTY environments
- **Severity:** High
- **Risk:** High (breaks JSON contract for CI/embedders; HTML regen/triage fails)
- **Priority:** P1
- **Fix effort:** Medium
- **Evidence:** `dist/bin/check-performance.sh` uses `/dev/tty` for JSON-mode chatter; when no TTY exists, shell errors can leak into logs and JSON output (observed in practice).
- **Code refs:** `dist/bin/check-performance.sh:5832`, `dist/bin/check-performance.sh:5866`, `dist/bin/check-performance.sh:5958`
- **Why it matters:** Any stderr emitted by failed `/dev/tty` redirections (or tools writing to stderr) contaminates JSON, causing downstream `jq`, HTML converter, and AI triage to fail.

- [ ] STATUS: In Progress

#### Patch Plan (JSON output / non-TTY)
- [ ] 1.1 Confirm all JSON-mode progress output is gated behind `OUTPUT_FORMAT = json` and does **not** write to stdout.
- [ ] 1.2 Tighten `/dev/tty` guards so we **never** attempt to write to `/dev/tty` if it is not available, and fall back to quiet `debug_echo` logging instead.
- [ ] 1.3 In JSON mode with `--no-log` (`ENABLE_LOGGING=false`), ensure there are **zero** non-JSON writes (no pattern-library-manager, no HTML hints, no progress banners).
- [ ] 1.4 Add/adjust a small CI-style sanity check that runs `--format json --no-log` and validates that stdout is a single valid JSON document (no preamble/noise).
- [ ] 1.5 Re-run WooCommerce/Beaver/ACF scans in JSON mode to confirm logs remain clean in both TTY and non-TTY scenarios.

### 2) Registry cache parsing is not whitespace-safe
- **Severity:** High
- **Risk:** High (pattern search strings/args with spaces get truncated → false negatives or wrong behavior)
- **Priority:** P1
- **Fix effort:** Medium
- **Evidence:** The registry cache encodes key/value pairs in a space-delimited line; parsing splits on spaces, so `search_pattern` or `validator_args` containing spaces are broken.
- **Code refs:** `dist/lib/pattern-loader.sh:159`, `dist/lib/pattern-loader.sh:221`, `dist/lib/pattern-loader.sh:265`
- **Why it matters:** Many regex patterns and validator args contain spaces or escaped whitespace. Truncation changes detection logic silently.

- [ ] STATUS: In Progress

#### Patch Plan (Registry cache whitespace safety)
- [ ] 2.1 Change the cache line encoding so that **values are safely delimited**, e.g. use a JSON or `key=<len>:<value>` style format instead of naive space splitting.
- [ ] 2.2 Update the Bash-side parser in `_load_pattern_from_registry()` to read each line as a whole record and parse fields without splitting on raw spaces.
- [ ] 2.3 Add at least one pattern in `PATTERN-LIBRARY.json` (or a temporary test pattern) whose `search_pattern` and `validator_args` contain spaces to validate round-trip encoding/decoding.
- [ ] 2.4 Verify that existing patterns still load correctly (file patterns, mitigation flags, severity_downgrade) and that registry hit/miss metrics remain accurate.
- [ ] 2.5 Run fixture tests and a real plugin scan (e.g., WooCommerce) to confirm detection behaviour is unchanged except where whitespace bugs previously caused silent truncation.

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
