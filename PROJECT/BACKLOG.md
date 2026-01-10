# Backlog - Future Work

This backlog intentionally contains **only pending work**. Completed items belong in `CHANGELOG.md` and `PROJECT/3-COMPLETED/`.

## 🚧 In Progress

### Enhanced Context Detection (False Positive Reduction)
- [ ] Audit remaining ±N context windows and convert high-value checks to “same function/method” scoping where it reduces false positives.
- [ ] Validate on 1–2 real repos and capture outcomes (false positives, baseline suppression UX, AST need).

## ⏭️ Next Up

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
