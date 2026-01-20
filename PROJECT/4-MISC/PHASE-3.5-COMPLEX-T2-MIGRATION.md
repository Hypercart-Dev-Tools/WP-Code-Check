# Phase 3.5: Complex T2 Pattern Migration

**Created:** 2026-01-15  
**Status:** In Progress  
**Related:** `PHASE-3.4-MITIGATION-INFRASTRUCTURE.md`, `PHASE-3.3-SIMPLE-T2-MIGRATION.md`

---

## Objective

Migrate the final 3 complex T2 patterns to JSON format using existing infrastructure:
- Scripted validator framework (Phase 3.1-3.3)
- Mitigation detection framework (Phase 3.4)
- Multi-step detection (grep pipelines + validators)

---

## Patterns to Migrate

### 1. pre-get-posts-unbounded (Lines 3908-3947)

**Current Implementation:**
- 2-step detection:
  1. Find files with `add_action.*pre_get_posts` or `add_filter.*pre_get_posts`
  2. Check if those files set `posts_per_page => -1` or `nopaging => true`

**Migration Strategy:**
- **Detection type:** `scripted`
- **Search pattern:** `add_action.*pre_get_posts|add_filter.*pre_get_posts`
- **Validator:** New validator `validators/pre-get-posts-unbounded-check.sh`
  - Check context for `set(...'posts_per_page'...-1)` or `set(...'nopaging'...true)`
- **Mitigation:** Optional - detect admin-only context, capability checks

**Complexity:** Medium (2-step detection)

---

### 2. query-limit-multiplier (Lines 4202-4272)

**Current Implementation:**
- Detects: `count(...) * N` patterns
- Mitigation: Checks for `min(..., N)` hard cap
- Severity downgrade: MEDIUM → LOW when hard cap found

**Migration Strategy:**
- **Detection type:** `scripted`
- **Search pattern:** `count\([^)]*\)[[:space:]]*\*[[:space:]]*[0-9]{1,}`
- **Validator:** New validator `validators/hard-cap-check.sh`
  - Check for `min(..., N)` pattern in same line
  - Extract hard cap value
- **Mitigation detection:** YES
  - `mitigation_detection.enabled: true`
  - `mitigation_detection.validator_script: validators/hard-cap-check.sh`
  - `severity_downgrade: { "MEDIUM": "LOW" }`

**Complexity:** Medium (mitigation detection)

---

### 3. n1-meta-in-loop (Lines 4449-4505)

**Current Implementation:**
- Detects: `get_post_meta|get_term_meta|get_user_meta` + `foreach|while`
- Mitigation: Checks for `update_meta_cache()` usage
- Severity downgrade: MEDIUM → LOW (INFO) when caching detected

**Migration Strategy:**
- **Detection type:** `scripted`
- **Search pattern:** `get_post_meta|get_term_meta|get_user_meta`
- **Validator:** Reuse `validators/loop-context-check.sh` (already exists)
- **Mitigation detection:** YES
  - `mitigation_detection.enabled: true`
  - `mitigation_detection.validator_script: validators/meta-cache-check.sh` (new)
  - Check for `update_meta_cache|update_postmeta_cache|update_termmeta_cache|update_usermeta_cache`
  - `severity_downgrade: { "MEDIUM": "LOW", "HIGH": "MEDIUM" }`

**Complexity:** Medium (mitigation detection + loop context)

---

## Implementation Checklist

### Pattern 1: pre-get-posts-unbounded ✅ COMPLETE
- [x] Create `dist/patterns/pre-get-posts-unbounded.json`
- [x] Create `dist/validators/pre-get-posts-unbounded-check.sh`
- [x] Create test fixture `dist/tests/fixtures/pre-get-posts-unbounded.php`
- [x] Test with fixture file (4 detections working correctly)
- [x] Remove inline code (lines 3908-3947, replaced with migration comment)
- [x] Update pattern count (51 → 52)
- [x] Update version (1.3.17 → 1.3.18)
- [x] Update CHANGELOG.md

### Pattern 2: query-limit-multiplier
- [ ] Create `dist/patterns/query-limit-multiplier.json`
- [ ] Create `dist/validators/hard-cap-check.sh`
- [ ] Add mitigation detection configuration
- [ ] Test with `dist/tests/fixtures/limit-multiplier-from-count.php`
- [ ] Remove inline code (lines 4202-4272)
- [ ] Update pattern count

### Pattern 3: n1-meta-in-loop
- [ ] Create `dist/patterns/n1-meta-in-loop.json`
- [ ] Create `dist/validators/meta-cache-check.sh`
- [ ] Add mitigation detection configuration
- [ ] Test with existing fixtures
- [ ] Remove inline code (lines 4449-4505)
- [ ] Update pattern count

---

## Success Criteria

- [ ] All 3 patterns migrated to JSON
- [ ] All validators created and tested
- [ ] Mitigation detection working correctly
- [ ] All existing tests passing
- [ ] Inline code removed (~200 lines)
- [ ] Pattern count: 51 → 54 (+3)
- [ ] No regressions in scan results

---

## Estimated Effort

- Pattern 1: 30 minutes (new validator)
- Pattern 2: 25 minutes (mitigation detection)
- Pattern 3: 25 minutes (mitigation detection)
- Testing: 20 minutes
- **Total: ~2 hours**

---

## Notes

- All 3 patterns can use **existing infrastructure** (no new framework needed)
- Mitigation detection framework from Phase 3.4 is perfect for patterns 2 & 3
- This completes the T2 pattern migration (19/19 patterns)

