# Backlog - Future Work

This backlog intentionally contains **only pending work**. Completed items belong in `CHANGELOG.md` and `PROJECT/3-COMPLETED/`.

## 🚧 In Progress

### Enhanced Context Detection (False Positive Reduction)
- [ ] Audit remaining ±N context windows and convert high-value checks to “same function/method” scoping where it reduces false positives.
- [ ] Validate on 1–2 real repos and capture outcomes (false positives, baseline suppression UX, AST need).

## ⏭️ Next Up

### Calibration Feature - Pattern Sensitivity Adjustment (NEW)
**Priority:** MEDIUM
**Effort:** 3–5 days
**Target Version:** v1.1.0
**Proposal:** `PROJECT/1-INBOX/PROPOSAL-CALIBRATION-FEATURE.md`

**Problem:** Elementor calibration test (1,273 files, 509 findings) revealed 93.5% of findings require manual review. No way to adjust pattern strictness based on use case (security audit vs. code review vs. CI/CD).

**Solution:** Template-based calibration modes (strict/balanced/permissive) with vendored code exclusion.

- [ ] Add calibration variables to template parser (CALIBRATION_MODE, EXCLUDE_VENDORED, MIN_SEVERITY)
- [ ] Add CLI flags (--calibration, --exclude-vendored, --min-severity)
- [ ] Implement calibration mode logic (strict/balanced/permissive)
- [ ] Add vendored code auto-detection (node_modules, vendor, *.min.js)
- [ ] Update template file with calibration section
- [ ] Test on Health Check, Elementor, WooCommerce
- [ ] Update documentation (README.md, EXPERIMENTAL-README.md)

**Expected Outcome:**
- Strict mode: 509 findings (100% - security audit)
- Balanced mode: ~250 findings (49% - code review, default)
- Permissive mode: ~50 findings (10% - CI/CD, critical only)

**Rationale for Priority:** Medium priority because it directly addresses user pain points from real-world testing (Elementor scan). Should be implemented after OOM pattern hardening but before AST integration. Provides immediate value for large codebases and different use cases.

---

### OOM / Memory Pattern Hardening (from PATTERN-MEMORY.md)
**Priority:** HIGH
**Effort:** 1–2 days

- [ ] Add “valid” fixtures (false-positive guards) for OOM rules.
- [ ] Tune heuristics for `limit-multiplier-from-count` and `array-merge-in-loop`.
- [ ] Add suppression guidance + confirm severities.
- [ ] Real-world calibration pass on 3–5 plugins/themes.

### N+1 Context Detection (from NEXT-CALIBRATION.md)
**Priority:** MEDIUM
**Effort:** 3–4 days

- [ ] Reduce metabox-related false positives using filename/function/loop context.
- [ ] Add a context-aware N+1 rule (or refactor existing logic) without adding dependencies.

### Admin Notice Capability Checks (docs)
**Priority:** LOW
**Effort:** 1 day

- [ ] Add documentation explaining why missing capability checks in admin notices matter and how to fix.

### Migrate Inline Rules to JSON (Single Source of Truth)
**Priority:** HIGH
**Effort:** Multi-day (phased)

- [ ] Inventory all inline `run_check` rules still embedded in `dist/bin/check-performance.sh`.
- [ ] Migrate highest-impact inline rules to `dist/patterns/*.json` first (keep behavior identical).
- [ ] Update docs to prefer JSON rule definitions for new work.
