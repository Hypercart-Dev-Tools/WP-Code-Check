# Project Stability Review (Main Script)

**Created:** 2026-01-05
**Status:** Not Started
**Priority:** High

## Problem/Request
Review stability risks in the main scanner script (`dist/bin/check-performance.sh`), focusing on:
- Inefficient grep patterns on large codebases
- Missing timeout handling
- Infinite loops in pattern matching

## Context
- Users run scans against very large WordPress codebases (plugins/themes + dependencies), often in paths with spaces.
- The script performs many recursive grep/find passes plus post-processing loops; a few “bad” patterns or edge-case inputs can lead to slow runs, hangs, or runaway logs.
- Recent debug additions can make long runs more visible but also risk adding noise/overhead.

## Acceptance Criteria
- [ ] Identify the top 5–10 highest-cost grep/find operations (by call site + why they are expensive).
- [ ] For each, document a safe optimization option that preserves behavior (e.g., narrower includes, precomputed file lists, fewer re-scans).
- [ ] Identify where timeouts should exist (external commands / scans) and define a standard approach compatible with macOS (Bash 3.2).
- [ ] Identify any loops that could become unbounded (while-read over generated lists, grouping loops, aggregation loops) and document the exact conditions that could cause non-termination.
- [ ] Produce a short “Stability Safeguards” proposal: minimal changes, highest value, lowest regression risk.
- [ ] Define a verification checklist (what to run, what to measure, what output must remain unchanged).

## Investigation Plan
### 1) Inefficient grep patterns on large codebases
- Inventory all recursive `grep -r` / `grep -rl` / `find ... -exec grep` call sites.
- Note whether:
  - `$PATHS` is a directory vs single file
  - includes/excludes are applied consistently
  - results are re-grepped multiple times (N× passes)
- Quick profiling approach:
  - Add optional timing wrapper around major sections (behind an env flag) to collect coarse section timings.
  - Run against a large real codebase and compare timings before/after proposed changes.

### 2) Missing timeout handling
- Identify operations that can stall:
  - recursive grep on networked/slow disks
  - `find ... -exec wc -l` on huge trees
  - `jq` / `python3` parsing on large payloads
- Decide on a portable timeout strategy:
  - Prefer `perl -e 'alarm ...'` wrapper or `python3` wrapper if GNU `timeout` is unavailable.
  - Ensure failure mode is graceful: emit warning + continue, or fail only if in strict mode.

### 3) Infinite loops in pattern matching
- Review `while read` loops that consume command output; ensure the producer can’t block indefinitely.
- Review aggregation logic:
  - grouping/unique extraction loops
  - any loop that re-processes the same growing file
- Confirm that pattern extraction and matching cannot feed itself (e.g., debug output being re-scanned).

## Deliverables
- A written report in this document with:
  - Findings table (call site → risk → proposed mitigation)
  - Recommended minimal patch list (no refactors)
  - Test/verification steps

## Notes
- Scope is intentionally limited to stability and performance guardrails; no feature additions.
- Preserve output formats (text/JSON/HTML) and baseline behavior.
