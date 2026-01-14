# Marketing Home Page Edits - 2026-01-14

**Status:** Not Started  
**Priority:** Medium  
**Created:** 2026-01-14

---

## Problem

Current marketing claims don't match actual implementation:
- Claims "30+" patterns but codebase has **29 patterns**
- Doesn't clarify that competitor "100+" includes style rules, not just performance/security
- Misses opportunity to highlight actual competitive advantages

---

## Recommended Changes

### 1. **Update Pattern Count Claims**

**Current:**
```
Performance & security rules: 30+
WordPress-specific patterns: 30+
Production antipatterns: 15+
WooCommerce-specific checks: 6+
```

**Recommended:**
```
Performance & security rules: 29 (9 CRITICAL + 10 HIGH)
WordPress-specific patterns: 18 (PHP/WordPress focused)
Production antipatterns: 15+ (competitors: 0-5)
WooCommerce-specific checks: 6+ (competitors: 0)
```

### 2. **Clarify Competitor Comparison**

**Add footnote:**
> *PHPCS/WPCS "100+" includes style/formatting rules. WP Code Check focuses on performance & security only.*

### 3. **Emphasize Real Advantages**

Replace generic "30+" claims with specific strengths:
- ✅ **Zero dependencies** - Bash + grep only (competitors require PHP/Composer)
- ✅ **Speed** - Scans 10K files in <5 seconds
- ✅ **Production-focused** - 15+ antipatterns competitors miss
- ✅ **WooCommerce-native** - 6 WC-specific checks (competitors: 0)
- ✅ **Baseline tracking** - Manage legacy code without refactoring

### 4. **Add Accuracy Metrics**

Include from `dist/PATTERN-LIBRARY.md`:
- **19 definitive patterns** (65.5%) - High confidence
- **10 heuristic patterns** (34.5%) - Code quality insights
- **4 patterns with AI mitigation** - 60-70% fewer false positives

### 5. **Breakdown by Severity**

Show distribution:
| Severity | Count | Impact |
|----------|-------|--------|
| CRITICAL | 9 | OOM, security crashes |
| HIGH | 10 | Performance degradation |
| MEDIUM | 7 | Code quality issues |
| LOW | 3 | Best practices |

---

## Files to Update

- [ ] `README.md` - Update comparison table
- [ ] `dist/reports/index.html` (if exists) - Update marketing section
- [ ] Website homepage (if separate) - Update feature claims
- [ ] `FAQS.md` - Add "How many checks?" section

---

## Acceptance Criteria

- [ ] All "30+" claims updated to "29" or specific breakdown
- [ ] Competitor comparison includes footnote about style rules
- [ ] Real advantages highlighted (zero deps, speed, WC-native)
- [ ] Accuracy metrics included (definitive vs heuristic)
- [ ] Severity breakdown visible to users

---

## Notes

This maintains honesty while emphasizing actual competitive advantages. Users care more about **what problems we solve** than inflated pattern counts.

