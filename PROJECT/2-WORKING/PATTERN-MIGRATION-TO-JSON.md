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

### 4.2.1 Pattern Complexity Tiers

Not all patterns can be expressed as pure regex. Define tiers to guide migration strategy:

| Tier | Detection Type | Expressiveness | Example |
|------|----------------|----------------|---------|
| T1 | `simple` | Single/multi regex, file filter | `posts_per_page => -1` |
| T2 | `aggregated` | Grouping, thresholds, dedup | DRY option name detection |
| T3 | `contextual` | Window-based, multi-condition | Nonce + capability in same function |
| T4 | `scripted` | Custom validator callback | Complex CFG-like checks |

**T4 "Scripted" Escape Hatch:**

For patterns that exceed JSON expressiveness, allow a hybrid approach:

```json
"detection": {
  "type": "scripted",
  "file_patterns": ["*.php"],
  "validator_script": "validators/admin-capability-check.sh",
  "validator_args": ["--context-lines", "20"]
}
```

- Validator scripts live in `dist/bin/validators/`.
- They receive: file path, line number, matched text, context lines.
- They return: `0` (confirmed issue), `1` (false positive), `2` (needs review).

**Migration Strategy for T3/T4 Patterns:**

1. **Phase 0:** During inventory, tag each inline rule as T1/T2/T3/T4.
2. **Phase 2.5:** Write validator scripts for T3/T4 patterns BEFORE removing inline code.
3. **Phase 3:** Migrate remaining T1/T2 patterns after T3/T4 validators are tested.

This ensures complex patterns don't lose fidelity when moved to JSON.

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

### Phase 0 – Inventory & Classification (COMPLETE)

**Objective:** Get a complete, categorized list of existing rules.

**Tasks:**
- [x] Scan `dist/bin/check-performance.sh` for `run_check` invocations.
- [x] For each, record:
  - `id` (rule ID string)
  - `severity`
  - `message` / description
  - Pattern(s) (`-E ...` lines)
  - Any special behavior (context windows, OVERRIDE_GREP_INCLUDE, baseline quirks)
- [x] Produce `PROJECT/2-WORKING/PATTERN-INVENTORY.md` table with full rule list, tiers, and migration notes.
- [x] Tag each rule by tier (T1/T2/T3/T4) and priority (P1/P2/P3).

**Deliverable:**
- `PROJECT/2-WORKING/PATTERN-INVENTORY.md` with complete inventory.

**STATUS:** ✅ COMPLETE (2026-01-15)

**Inventory Results:**
- **Total inline rules:** 46
- **Already migrated to JSON:** 7 rules (15%)
- **Needs migration:** 39 rules (85%)
- **Tier breakdown:**
  - T1 (Simple): 11 rules (24%) - ~55 min effort
  - T2 (Moderate): 24 rules (52%) - ~6 hours effort
  - T3 (Complex): 11 rules (24%) - ~8 hours effort
  - T4 (Very Complex): 0 rules (0%)
- **Priority breakdown:**
  - P1 (High - Security/SPO): 13 rules (28%) - 7 already JSON, 6 need migration
  - P2 (Medium - Performance): 26 rules (57%)
  - P3 (Low - Heuristics): 7 rules (15%)
- **Estimated total migration effort:** 14-16 hours (2 full work days)

---

### Phase 1 – JSON-First for New Rules (COMPLETE)

**Objective:** Ensure that **all new rules** are added only via JSON.

**Tasks:**
- [x] DRY patterns in `dist/patterns/dry/*.json`.
- [x] Update `CONTRIBUTING.md` examples:
  - Replace inline `run_check` example with JSON rule definition + pointer to the loader.
- [x] Add a small developer note to `dist/README.md`:
  - "All new rules MUST be defined in `dist/patterns/*.json`. Inline rules are legacy and will be removed."

**Deliverable:**
- CONTRIBUTING + dist/README both show JSON-based rule authoring.

**STATUS:** ✅ COMPLETE (2026-01-15)

**Completed Changes:**
- Updated `CONTRIBUTING.md` with comprehensive JSON rule authoring guide
  - Added JSON structure example with all detection types
  - Documented file organization by category
  - Deprecated inline `run_check` format with clear warning
  - Added reference to migration plan document
- Updated `dist/README.md` with new "How Rules Are Defined" section
  - Explained benefits of JSON-based rules (data-driven, self-documenting, testable, extensible)
  - Provided complete rule structure example
  - Documented pattern categories and detection types
  - Added contributor guidance
- Verified DRY patterns are functional:
  - `duplicate-option-names.json` ✓
  - `duplicate-transient-keys.json` ✓
  - `duplicate-capability-strings.json` ✓
  - Pattern loader (`dist/lib/pattern-loader.sh`) confirmed working
  - Aggregated pattern processing confirmed in `check-performance.sh` (lines 5268-5314)


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


**STATUS:** ✅ PHASE 2.1 COMPLETE (2026-01-15)

**Completed Migrations (Phase 2.1 - T1 Performance Rules):**

✅ **JSON Patterns Migrated (4 rules):**
1. `unbounded-posts-per-page.json` - Detects `posts_per_page => -1`
2. `unbounded-numberposts.json` - Detects `numberposts => -1`
3. `nopaging-true.json` - Detects `'nopaging' => true`
4. `order-by-rand.json` - Detects `ORDER BY RAND()` and `'orderby' => 'rand'`

**Implementation Summary:**
- ✅ Simple Pattern Runner implemented (lines 5659-5820 in `check-performance.sh`)
- ✅ Inline code removed (previously lines 3850-3862, 4854-4864)
- ✅ All fixture tests pass (10/10) with 0 regressions
- ✅ Baseline suppression works correctly
- ✅ JSON findings integrate with existing infrastructure

**Implementation Details:**

1. **Simple Pattern Runner** (lines 5659-5820)
   - Uses Python JSON parser for robust metadata extraction
   - Supports file pattern filtering (`pattern_file_patterns`)
   - Applies baseline suppression per finding
   - Integrates with `add_json_finding()` and `add_json_check()`
   - Handles severity-based error/warning classification

2. **Inline Code Removed**
   - Replaced with migration markers pointing to JSON patterns
   - Lines 3850-3852: Migration marker for unbounded query patterns
   - Lines 4844-4850: Migration marker for order-by-rand pattern

3. **Validation Results**
   - All 10 fixture tests pass
   - `antipatterns.php`: 10 errors, 3 warnings (expected)
   - New simple patterns detect violations correctly
   - No false positives or false negatives

**Effort:** 2.5 hours actual (vs 2-3 hours estimated)

---

**Next Steps:**
- Continue with remaining 7 T1 rules
- OR tackle P1 security rules (5 remaining, all T2/T3)



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

**STATUS:** NOT STARTED


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

**STATUS:** NOT STARTED


---

## 6. Testing & Regression Strategy

To avoid breaking behavior while refactoring:

### 6.1 Fixture Tests

- Always run `dist/tests/run-fixture-tests.sh` **before and after** each migration phase.
- Expected results must remain identical:
  - Same error/warning counts per fixture.
  - Same rule IDs and severities.

**STATUS:** NOT STARTED

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


**STATUS:** NOT STARTED



### 6.4 Golden Output Test Suite

Create a set of "golden" reference outputs from production scans to catch drift that fixtures might miss:

**Setup:**
```bash
# Generate golden outputs for reference projects
./dist/bin/check-performance.sh --paths /path/to/ptt-mkii --format json \
  | jq -S 'del(.metadata.scan_id, .metadata.timestamp)' > dist/tests/golden/ptt-mkii.json
```

**CI Check:**
```bash
# Compare current output to golden
./dist/bin/check-performance.sh --paths /path/to/ptt-mkii --format json \
  | jq -S 'del(.metadata.scan_id, .metadata.timestamp)' > /tmp/current.json
diff dist/tests/golden/ptt-mkii.json /tmp/current.json
```

**Golden Projects (minimum 3):**
- [ ] PTT-MKII (complex real-world plugin)
- [ ] WooCommerce All Products for Subscriptions (moderate complexity)
- [ ] A minimal "canary" plugin with 1 instance of every rule type


**STATUS:** NOT STARTED



### 6.5 Pattern Coverage Metrics

Track which patterns are exercised by tests to ensure no rule ships untested:

**Coverage Report Script:**
```bash
# Generate coverage report: which rule IDs fired in test runs
jq -r '.issues[].rule_id' dist/tests/outputs/*.json | sort | uniq -c | sort -rn
```

**Minimum Coverage Requirement:**
- Before marking Phase 3 complete, every JSON-defined rule must appear in at least one fixture or golden test.
- Add `dist/tests/coverage-check.sh` that fails if any rule ID has zero test coverage.

### 6.6 Differential Testing During Migration

For each rule migrated from inline to JSON, verify identical behavior:

1. Run scan with inline rule only (disable JSON loader for that rule).
2. Run scan with JSON rule only (remove inline rule).
3. Diff outputs – must be identical.

**Script stub:**
```bash
# dist/bin/test-rule-migration.sh <rule_id>
# Validates that inline and JSON definitions produce identical results
```

This per-rule differential approach catches subtle behavior changes that aggregate tests might miss.

**STATUS:** NOT STARTED


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

**STATUS:** NOT STARTED

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


**STATUS:** NOT STARTED



### 7.3 Backward Compatibility

- During migration, keep a flag or environment variable (e.g., `HCC_USE_JSON_RULES_ONLY=0/1`) for emergency rollback **during development only**. Final state should not require such a flag.


**STATUS:** NOT STARTED



---

## 8. Risks & Mitigations

### 8.1 Risk: Behavior Drift

- **Mitigation:** Fixture tests + before/after JSON diffs for reference projects.


**STATUS:** NOT STARTED



### 8.2 Risk: JSON Schema Changes Mid-Migration

- **Mitigation:** Freeze a minimal viable schema before Phase 2 and avoid breaking changes until migration is complete.


**STATUS:** NOT STARTED


### 8.3 Risk: Developer Confusion During Transition

- **Mitigation:**
  - Update `CONTRIBUTING.md` immediately to say "New rules must use JSON".
  - Comment legacy inline blocks as `LEGACY_RULE_DEF` with pointers to this migration doc.

**STATUS:** NOT STARTED

### 8.4 Risk: Complex Pattern Loss of Fidelity

- **Description:** Some legacy rules rely on advanced Bash logic (context windows, custom validators, multi-condition checks). Migrating these to JSON may oversimplify or lose expressiveness.
- **Mitigation:**
  - Use the T1–T4 complexity tier system (§4.2.1) to identify high-risk patterns early.
  - Implement the `scripted` detection type escape hatch for T4 patterns.
  - Write and test validator scripts BEFORE removing inline code (Phase 2.5).
  - Use differential testing (§6.6) to verify per-rule behavior parity.

**STATUS:** NOT STARTED


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
- [ ] Tag each inline rule as T1/T2/T3/T4 complexity tier.

**JSON-First Authoring**
- [ ] Update `CONTRIBUTING.md` to prefer JSON-based rules.
- [ ] Update `dist/README.md` with JSON rule authoring guidance.

**Complex Pattern Handling**
- [ ] Audit inline rules, identify all T3/T4 patterns.
- [ ] Write validator scripts for T3/T4 patterns (in `dist/bin/validators/`).
- [ ] Test validator scripts in isolation before wiring to JSON.

**Migration Execution**
- [ ] Phase 2 – Migrate high-impact rules to JSON (SPO, KISS, security, HTTP).
- [ ] Phase 2.5 – Migrate T3/T4 patterns with validator scripts.
- [ ] Phase 3 – Migrate remaining legacy rules (query, timezone, cron, misc).

**Testing Robustness**
- [ ] Generate golden outputs for 3+ reference projects.
- [ ] Add `dist/tests/coverage-check.sh` to CI.
- [ ] Run differential testing for each migrated rule.

**Verification & Cleanup**
- [ ] Ensure all fixture tests pass unchanged.
- [ ] Confirm baseline behavior unchanged.
- [ ] Remove legacy inline rule definitions.
- [ ] Add CHANGELOG entry summarizing the migration.
- [ ] Confirm `PATTERN-LIBRARY-SUMMARY.md` shows `Definition Source: json` for all rules.

Once all boxes are checked, **pattern definitions are fully data-driven**, and `check-performance.sh` can focus on orchestration, not rule authoring.
