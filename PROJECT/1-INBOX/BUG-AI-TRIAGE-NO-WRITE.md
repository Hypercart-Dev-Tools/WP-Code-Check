# Bug Report: `ai-triage.py` Runs But Does Not Persist `ai_triage` Into JSON

**Date:** 2026-01-08
**Status:** ✅ FIXED
**Severity:** Medium (Phase 2 output silently missing)
**Area:** Phase 2 / AI triage injector

---

## Summary

Running the Phase 2 triage injector (`dist/bin/ai-triage.py`) would exit successfully but **did not persist** the expected top-level `ai_triage` object back into the target JSON log.

This made it appear as if triage had run (and the HTML generator printed “Processing AI triage data…”), but the JSON remained unchanged and the report continued to show “Not performed yet”.

---

## Expected Behavior

After running:

- `python3 dist/bin/ai-triage.py dist/logs/<TIMESTAMP>.json --max-findings 250`

The JSON log should contain a top-level object:

- `ai_triage.performed = true`
- `ai_triage.summary` populated
- `ai_triage.triaged_findings` populated

---

## Actual Behavior

- Script execution returned exit code `0`.
- The JSON log **did not** contain `ai_triage` after execution.
- Re-running produced the same result.

---

## Reproduction

1. Ensure you have a valid scan log with findings, e.g.:
   - `dist/logs/2026-01-08-020031-UTC.json`
2. Run triage:
   - `python3 dist/bin/ai-triage.py dist/logs/2026-01-08-020031-UTC.json --max-findings 250`
3. Verify:
   - `jq 'has("ai_triage")' dist/logs/2026-01-08-020031-UTC.json`

Observed: returns `false`.

---

## Root Cause

The script used a `@dataclass` (`TriageDecision`). In this environment (Python 3.9), importing/executing the module in some contexts triggers a `dataclasses` failure:

- `AttributeError: 'NoneType' object has no attribute '__dict__'`

This prevented the triage logic from being safely usable/reliable and resulted in the injection step not persisting.

---

## Fix

Replaced the `@dataclass` with a lightweight standard-library type:

- `TriageDecision(NamedTuple)`

After the change:

- `ai_triage` is written successfully.
- `triaged_findings` count matches the requested max.

Example verification output after fix:

- `has_ai_triage True`
- `triaged 250`
- `summary {'confirmed_issues': 4, 'false_positives': 20, 'needs_review': 226, 'confidence_level': 'medium'}`

---

## Files

- Fixed: `dist/bin/ai-triage.py`
- Typical inputs: `dist/logs/*.json`
- Report generator consuming output: `dist/bin/json-to-html.py`

---

## Suggested Follow-Ups (Optional)

- Add explicit logging to `ai-triage.py` (e.g., print counts + output path) so “silent no-op” is obvious.
- Add a post-write verification step in `ai-triage.py` (re-open JSON and assert `ai_triage` exists).
- Add a small regression test / smoke test script that runs triage on a known fixture log.
