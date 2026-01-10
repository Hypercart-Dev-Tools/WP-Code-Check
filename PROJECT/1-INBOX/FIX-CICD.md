# FIX-CICD: CI fixture tests failing on Ubuntu (jq missing)

**Created:** 2026-01-09
**Status:** Not Started
**Priority:** High

## Problem/Request
GitHub Actions CI was failing (9/10 fixture tests failing on Ubuntu) while passing locally on macOS.

## Root Cause (confirmed)
The fixture test runner [dist/tests/run-fixture-tests.sh](../../dist/tests/run-fixture-tests.sh) parses scanner output as JSON using `jq`.

- In GitHub Actions Ubuntu runners, `jq` is not guaranteed to be present.
- When `jq` is missing, the script’s JSON-parse branch fails and it falls back to *text* parsing.
- Because [dist/bin/check-performance.sh](../../dist/bin/check-performance.sh) defaults to JSON output (`OUTPUT_FORMAT="json"`), the text parsing fallback fails too.

## Code Review Findings

### ✅ What’s good
- **Correct fix direction:** Installing `jq` in CI aligns with a JSON-first architecture and also supports Slack/report tooling in [ .github/workflows/ci.yml](../../.github/workflows/ci.yml).
- **Avoids weakening tests:** Not forcing `--format text` keeps parsing stable and avoids brittle greps for human output.
- **Script already has some resilience:** The fixture runner strips ANSI codes and captures output to temp files, which helps keep parsing deterministic.

### ⚠️ Correctness / Robustness gaps
1. **`jq` absence triggers the wrong fallback path**
   - In [dist/tests/run-fixture-tests.sh](../../dist/tests/run-fixture-tests.sh), the decision boundary is “can I run `jq empty`?” rather than “is the output JSON?”.
   - Result: if output *is* JSON but `jq` is missing, the script attempts text parsing, which is structurally incapable of working.

2. **Implicit reliance on default output format**
   - `run_test()` calls `check-performance.sh` without `--format json`, relying on its default.
   - That’s currently stable (default is documented as JSON), but making it explicit would strengthen the contract between the test runner and the scanner.

3. **CHANGELOG inconsistency / mixed narrative**
   - In [CHANGELOG.md](../../CHANGELOG.md) under **Unreleased → Fixed → Test Suite**, it claims:
     - “Fixed JSON parsing in test script to use grep-based parsing (no jq dependency)”
   - But the current script is `jq`-primary and CI explicitly installs `jq`.
   - The entry also says both “All 10 fixture tests now pass” and later “(9/10 tests passing)”, which reads as contradictory.

4. **Duplication in CI dependency installation**
   - [ .github/workflows/ci.yml](../../.github/workflows/ci.yml) installs `jq` in both jobs separately.
   - This is fine, but it’s repeated maintenance surface.

## Recommendations (no code changes requested)

### 1) Make jq a declared prerequisite *or* make JSON parsing dependency-free
Pick one and make it consistent across CI + docs:

- **Option A (declare jq required):**
  - Treat `jq` as a hard dependency of the fixture runner.
  - In CI, keep installing it.
  - In local/dev, add a clear early check like `command -v jq` and fail with an actionable error message.

- **Option B (remove jq dependency):**
  - Replace the `jq` parsing path in `run_test()` with a dependency-free JSON extraction (e.g., minimal grep extraction, or `python3 -c` JSON parsing).
  - This matches the existing “no jq dependency” statements in the changelog.

### 2) Don’t use “text parsing” as a fallback for “jq missing”
If you keep a fallback:
- First detect whether output is JSON (e.g., begins with `{` after stripping ANSI).
- If output is JSON but `jq` is missing, either:
  - fail with a clear message, or
  - use a dependency-free JSON parser fallback.

### 3) Make format explicit in tests
Even if the scanner default remains JSON:
- Have the fixture tests call `check-performance.sh --format json` consistently.
- This prevents future surprises if the scanner’s default changes.

### 4) Clarify and reconcile CHANGELOG statements
Update the Unreleased entry so it matches reality:
- If CI installs `jq` and tests rely on it, remove/adjust the “no jq dependency” claim.
- Fix the “All 10 pass” vs “9/10 pass” inconsistency.

### 5) CI hardening (optional)
- Print `jq --version` after install for easier diagnosis.
- Consider using `sudo apt-get install -y jq` (with update) as you already do; it’s fine.
- If apt install is a concern, failing the job is acceptable because tests can’t run correctly without `jq` under the current design.

## Edge Cases / Risks to watch
- **Runner image changes:** `ubuntu-latest` can change; explicit installation avoids surprises.
- **JSON schema changes:** Tests assume `.summary.total_errors` and `.summary.total_warnings` exist.
  - If the JSON schema changes, the tests should fail loudly (ideally with a clear schema mismatch message).
- **Non-JSON noise:** Any stderr logging mixed into JSON output will break parsing.
  - Scanner already has safeguards to avoid corrupting JSON; ensure future debug logging stays format-aware.

## Acceptance Criteria
- [ ] CI passes fixture validation on `ubuntu-latest` reliably.
- [ ] Fixture tests either (A) explicitly require `jq` with a clear error, or (B) remain dependency-free.
- [ ] CHANGELOG entry accurately describes the final architecture and outcome (10/10 passing).
