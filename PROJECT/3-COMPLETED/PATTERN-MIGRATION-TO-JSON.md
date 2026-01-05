# Pattern Migration to JSON – Detailed Plan

**Created:** 2026-01-02  
**Status:** Planning  
**Owner:** Core maintainer  
**Related:** `PROJECT/BACKLOG.md` ("Migrate Inline Patterns to External JSON Rules"), `PATTERN-LIBRARY-SUMMARY.md`

---

## 1. Purpose

WP Code Check currently has a **hybrid rule definition model**:

- **Legacy rules** are defined inline in `dist/bin/check-performance.sh` as hard-coded `run_check` invocations with embedded `-E` grep patterns.
- **Newer rules** (especially DRY/aggregated patterns) use **external JSON definitions** under `dist/patterns/`, loaded by the pattern loader and executed via shared runners (e.g., `run_aggregated_pattern()`).

The goal of this document is to define a **concrete, step-by-step migration plan** so that **all production rules** are expressed as JSON patterns, with the Bash script acting as an engine/runner rather than a rule-definition file.

---

## 2. Target End State

### 2.1 Single Source of Truth

- All detection rules (IDs, severities, categories, descriptions, remediation hints, pattern expressions) live in **JSON files under `dist/patterns/`**.
- `check-performance.sh`:
  - Loads JSON files.
  - Dispatches rules to the appropriate runner (simple grep, aggregated, context-aware, clone detection, etc.).
  - Contains **no hard-coded `-E` patterns** for production rules (except for internal/debug checks if needed).

### 2.2 JSON Layout

- **Directory structure (initial proposal):**

  ```
  dist/patterns/
    core/
      performance.json       # Query performance, N+1, cron, timezone
      security.json          # Nonces, capabilities, unsafe serialization
      http.json              # HTTP no-timeout, external URLs, polling
      spo.json               # Security-Performance Overlap rules
    dry/
      duplicate-options.json
      duplicate-transients.json
      duplicate-capabilities.json
      duplicate-functions.json
  ```

- **Alternative:** One file per rule (e.g., `unbounded-posts-per-page.json`). This is left as an open question (see §9).

### 2.3 Execution Model

- Runners (existing + extended):
  - `run_simple_pattern_rule()` – basic `run_check`-style rules.
  - `run_aggregated_pattern()` – DRY/clone detection, threshold-based aggregation.
  - `run_context_check()` – context-aware rules (admin capabilities, HTTP timeout, etc.).

- Each JSON rule declares which runner it needs via `"detection.type"`, for example:

  ```json
  "detection": {
    "type": "simple",         // or "aggregated", "contextual", "clone_detection"
    "file_patterns": ["*.php"],
    "grep": {
      "include": ["-E pattern1", "-E pattern2"],
      "override_include": "--include=*.php --include=*.js"
    }
  }
  ```

---

## 3. Current State Inventory (What We Have)

### 3.1 External JSON Patterns (Already in Use)

- `dist/patterns/dry/*.json` (Magic String Detector patterns):
  - Duplicate option names
  - Duplicate transient keys
  - Duplicate capability strings
- Planned/partially implemented:
  - `duplicate-functions.json` – Type 1 clone detection.

These use the **aggregated detection schema** documented in:

- `PROJECT/NEXT-FIND-DRY.md`
- `PROJECT/1-INBOX/PROJECT-LOGIC-DUPLICATION.md`
- `PATTERN-JSON-COMPLETION-SUMMARY.md`

### 3.2 Inline Patterns (Legacy)

Still directly embedded in `dist/bin/check-performance.sh` (and related scripts):

- Query performance: unbounded queries (`posts_per_page => -1`, `wc_get_orders`, etc.).
- N+1 patterns (`get_post_meta`, `get_term_meta` in loops).
- Timezone checks (`current_time('timestamp')`, `date()` without suppression).
- HTTP/Network checks: `file_get_contents()` with URLs, HTTP no-timeout, unbounded polling.
- Security checks: missing nonces, missing capability checks, insecure deserialization.
- SPO rules and KISS PQS audit rules (currently authored as inline `run_check` in `KISS-PQS-FINDINGS-RULES.md`).

---

## 4. JSON Schema – Canonical Definition

We will treat DRY’s aggregated schema as the **starting point** and extend it slightly for simple/contextual rules.

### 4.1 Base Rule Structure

```json
{
  "id": "unbounded-posts-per-page",
  "version": "1.0.0",
  "enabled": true,
  "category": "performance",
  "severity": "CRITICAL",
  "title": "Unbounded posts_per_page",
  "description": "Detects WordPress queries that disable pagination and can crash large sites.",
  "rationale": "Unbounded queries can fetch all posts at once, leading to timeouts and memory exhaustion.",

  "detection": { /* see below */ },
  "aggregation": { /* optional, for DRY/clone rules */ },
  "remediation": { /* see below */ }
}
```

### 4.2 Detection Types

- `"simple"` – direct `run_check` equivalent.
- `"aggregated"` – DRY/clone rules (existing).
- `"contextual"` – needs window/context callbacks (admin capabilities, HTTP timeout, etc.).
- `"clone_detection"` – specialization of aggregated for function/code clone detection (can reuse `aggregated`).

**Example – simple rule:**

```json
"detection": {
  "type": "simple",
  "file_patterns": ["*.php"],
  "grep": {
    "include": [
      "-E posts_per_page[[:space:]]*=>[[:space:]]*-1"
    ],
    "override_include": "--include=*.php"
  }
}
```

**Example – aggregated rule (existing DRY pattern):**

```json
"detection": {
  "type": "aggregated",
  "file_patterns": ["*.php"],
  "search_pattern": "get_option\\(['\"]([a-z0-9_]+)['\"]\\)",
  "capture_group": 1
},
"aggregation": {
  "enabled": true,
  "group_by": "capture",
  "min_distinct_files": 3,
  "min_total_matches": 6,
  "top_k_groups": 15
}
```

**Example – contextual rule (outline):**

```json
"detection": {
  "type": "contextual",
  "file_patterns": ["*.php"],
  "grep": {
    "include": ["-E wp_ajax_", "-E add_menu_page"],
    "context_window": 20
  },
  "context_validator": "nonce_and_capability_check"
}
```

> Note: `context_validator` is a symbolic name; the Bash script maps it to a shell function that inspects lines around the match.

### 4.3 Remediation Block

```json
"remediation": {
  "summary": "Add pagination or a reasonable LIMIT to queries to avoid loading all records at once.",
  "examples": [
    {
      "bad": "WP_Query(['posts_per_page' => -1])",
      "good": "WP_Query(['posts_per_page' => 50, 'paged' => $paged])",
      "note": "Use paged queries and reasonable limits for production sites."
    }
  ]
}
```

---

## 5. Migration Phases (Detailed)

This expands on the high-level plan in `BACKLOG.md`.

### Phase 0 – Inventory & Classification (2–3 hours)

**Objective:** Get a complete, categorized list of existing rules.

**Tasks:**
- [ ] Scan `dist/bin/check-performance.sh` for `run_check` invocations.
- [ ] For each, record:
  - `id` (rule ID string)
  - `severity`
  - `message` / description
  - Pattern(s) (`-E ...` lines)
  - Any special behavior (context windows, OVERRIDE_GREP_INCLUDE, baseline quirks)
- [ ] Produce `PROJECT/PATTERN-LIBRARY-SUMMARY.md` table (already exists; extend with `source: inline/json`).
- [ ] Tag each rule as: `core`, `SPO`, `KISS`, `DRY`, `http`, `timezone`, `cron`, `security`.

**Deliverable:**
- Updated `PATTERN-LIBRARY-SUMMARY.md` with a column `Definition Source: inline/json`.

---

### Phase 1 – JSON-First for New Rules (Already in Progress)

**Objective:** Ensure that **all new rules** are added only via JSON.

**Tasks:**
- [x] DRY patterns in `dist/patterns/dry/*.json`.
- [ ] Update `CONTRIBUTING.md` examples:
  - Replace inline `run_check` example with JSON rule definition + pointer to the loader.
- [ ] Add a small developer note to `dist/README.md`:
  - "All new rules MUST be defined in `dist/patterns/*.json`. Inline rules are legacy and will be removed."

**Deliverable:**
- CONTRIBUTING + dist/README both show JSON-based rule authoring.

---

### Phase 2 – Migrate High-Impact Rules (1–2 days)

**Objective:** Move the most important and complex rules first, where JSON benefits are largest.

**Target rule families:**
- SPO rules (security-performance overlap).
- KISS PQS rules (from `KISS-PQS-FINDINGS-RULES.md`).
- Admin capability checks.
- Nonce/CSRF-related rules.
- HTTP timeout and external URL checks.

**Tasks:**
1. **Design JSON entries** for each target rule family.
2. **Implement JSON definitions** under appropriate files, e.g.:
   - `dist/patterns/core/security.json`
   - `dist/patterns/core/http.json`
3. **Extend runners if needed:**
   - Add support for `contextual` rules (if not already present) with `context_validator` mapping.
4. **Wire loading order:**
   - Ensure the pattern loader reads all `dist/patterns/core/*.json` and `dist/patterns/dry/*.json` before any inline rules.
5. **Paritization & testing:**
   - Run `dist/tests/run-fixture-tests.sh` before/after.
   - Compare JSON outputs for representative real-world projects.

**Success criteria:**
- No change in fixture error/warning counts.
- No change in rule IDs, severities, or messages.

---

### Phase 3 – Migrate Remaining Legacy Rules (2–3 days)

**Objective:** Move all remaining query, timezone, cron, and misc rules to JSON.

**Target rule families:**
- Query performance (unbounded queries, raw SQL LIMIT, etc.).
- N+1 meta patterns.
- Timezone checks.
- Cron interval validation.
- Miscellaneous performance/security patterns.

**Tasks:**
1. **JSON definition:** For each family, add entries to `performance.json` / `security.json` as appropriate.
2. **Runners:** Most of these can use `type: "simple"`.
3. **Baseline integration:** Ensure the baseline engine continues to operate identically (baseline keyed by rule ID + file + line, unchanged).
4. **Clean up inline code:** Once a family is migrated and verified, remove the corresponding `run_check` blocks from `check-performance.sh`.

**Success criteria:**
- Only internal/debug patterns remain inline (if any).
- All production rules listed in `PATTERN-LIBRARY-SUMMARY.md` show `Definition Source: json`.

---

### Phase 4 – Cleanup, Docs, and Tooling (1 day)

**Objective:** Solidify JSON as the canonical model and update documentation/tooling.

**Tasks:**
- [ ] Remove any dead code paths that assumed inline pattern definitions.
- [ ] Update:
  - `CONTRIBUTING.md` – JSON-only examples.
  - `dist/README.md` – section "How Rules are Defined".
  - `PATTERN-LIBRARY-SUMMARY.md` – mark migration complete.
- [ ] Optionally, add a small script `dist/bin/list-rules.sh` that prints all rules by reading JSON.

---

## 6. Testing & Regression Strategy

To avoid breaking behavior while refactoring:

### 6.1 Fixture Tests

- Always run `dist/tests/run-fixture-tests.sh` **before and after** each migration phase.
- Expected results must remain identical:
  - Same error/warning counts per fixture.
  - Same rule IDs and severities.

### 6.2 Real-World Projects

- Maintain a small set of reference projects (e.g., PTT-MKII, Woo All Products for Subscriptions).
- Run:

  ```bash
  ./dist/bin/check-performance.sh --paths /path/to/project --format json > before.json
  # After migration
  ./dist/bin/check-performance.sh --paths /path/to/project --format json > after.json
  jq -S . before.json > before.norm.json
  jq -S . after.json > after.norm.json
  diff before.norm.json after.norm.json
  ```

- Expect **no semantic diffs** (only allowed differences would be ordering if downstream tools don’t rely on it).

### 6.3 Baseline Behavior

- Validate `.hcc-baseline` handling is unchanged:
  - Same `summary.baselined` and `summary.stale_baseline` metrics.
  - No new drift in baseline files.

---

## 7. Implementation Notes (Engine Side)

### 7.1 Loader

- Centralize JSON loading in a helper (already present in pattern loader):

  ```bash
  load_patterns_from_dir() {
      local dir="$1"
      # find "$dir" -name "*.json" ... | jq ...
  }
  ```

- Ensure deterministic loading order (e.g., sort filenames) to keep JSON output stable.

### 7.2 Runner Selection

- In pseudocode:

  ```bash
  for rule in "$PATTERN_SET"; do
    case "$rule_detection_type" in
      simple)
        run_simple_pattern_rule "$rule" ;;
      aggregated)
        run_aggregated_pattern "$rule" ;;
      contextual)
        run_context_check "$rule" ;;
      *)
        echo "[WARN] Unknown detection type for $rule_id" >&2 ;;
    esac
  done
  ```

### 7.3 Backward Compatibility

- During migration, keep a flag or environment variable (e.g., `HCC_USE_JSON_RULES_ONLY=0/1`) for emergency rollback **during development only**. Final state should not require such a flag.

---

## 8. Risks & Mitigations

### 8.1 Risk: Behavior Drift

- **Mitigation:** Fixture tests + before/after JSON diffs for reference projects.

### 8.2 Risk: JSON Schema Changes Mid-Migration

- **Mitigation:** Freeze a minimal viable schema before Phase 2 and avoid breaking changes until migration is complete.

### 8.3 Risk: Developer Confusion During Transition

- **Mitigation:**
  - Update `CONTRIBUTING.md` immediately to say "New rules must use JSON".
  - Comment legacy inline blocks as `LEGACY_RULE_DEF` with pointers to this migration doc.

---

## 9. Open Design Questions

1. **File Granularity**
   - One JSON per rule (fine-grained, easier diffing) vs grouped files per category (fewer files, easier batch edits).
   - Current DRY patterns lean toward *grouped by domain* (e.g., `dry/*.json`).

2. **Remediation Storage**
   - Keep remediation text solely in JSON vs referencing external docs (e.g., `HOWTO-TEMPLATES.md`, `PATTERN-LIBRARY-SUMMARY.md`).
   - Recommendation: Store at least a short `summary` + 1–2 examples in JSON for self-contained UIs.

3. **Generated Catalog**
   - Option to auto-generate `PATTERN-LIBRARY-SUMMARY.md` and/or an HTML catalog from JSON.
   - Could be a future task once migration is complete.

---

## 10. Checklist Summary

**Planning & Inventory**
- [ ] Complete Phase 0 inventory and update `PATTERN-LIBRARY-SUMMARY.md`.

**JSON-First Authoring**
- [ ] Update `CONTRIBUTING.md` to prefer JSON-based rules.
- [ ] Update `dist/README.md` with JSON rule authoring guidance.

**Migration Execution**
- [ ] Phase 2 – Migrate high-impact rules to JSON (SPO, KISS, security, HTTP).
- [ ] Phase 3 – Migrate remaining legacy rules (query, timezone, cron, misc).

**Verification & Cleanup**
- [ ] Ensure all fixture tests pass unchanged.
- [ ] Confirm baseline behavior unchanged.
- [ ] Remove legacy inline rule definitions.
- [ ] Add CHANGELOG entry summarizing the migration.
- [ ] Confirm `PATTERN-LIBRARY-SUMMARY.md` shows `Definition Source: json` for all rules.

Once all boxes are checked, **pattern definitions are fully data-driven**, and `check-performance.sh` can focus on orchestration, not rule authoring.
