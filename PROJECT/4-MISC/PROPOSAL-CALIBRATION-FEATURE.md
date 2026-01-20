# PROPOSAL: Calibration Feature - Pattern Sensitivity Adjustment

**Created:** 2026-01-12  
**Status:** Not Started  
**Priority:** MEDIUM  
**Estimated Effort:** 3-5 days  
**Target Version:** v1.1.0

---

## 📋 Problem Statement

Based on the Elementor v3.34.1 calibration test (1,273 files, 509 findings), we discovered:

- **93.5% of findings require manual review** (187 out of 200 AI-triaged findings)
- **Only 2% are confirmed issues** (4 out of 200)
- **Top 2 patterns account for 58% of findings** (superglobals: 150, missing cap checks: 146)
- **No way to adjust pattern strictness** based on use case (security audit vs. code review vs. CI/CD)

**User Pain Points:**

1. **Security auditors** want strict mode (all patterns, no downgrading)
2. **Developers** want balanced mode (guard detection, severity downgrading)
3. **CI/CD pipelines** want permissive mode (critical only, exclude vendored code)
4. **Large codebases** generate too many "needs review" findings (noise)

**Current Workaround:** Users must manually filter findings or use `--skip-rules` flag (tedious).

---

## 🎯 Proposed Solution

### Feature: Template-Based Calibration Modes

Allow users to configure pattern sensitivity via **template files** (simplest approach) or **CLI flags** (override).

### Three Calibration Modes

| Mode | Use Case | Severity Threshold | Guard Detection | Exclude Vendored |
|------|----------|-------------------|-----------------|------------------|
| **strict** | Security audit, compliance | All (INFO+) | ❌ Disabled | ❌ No |
| **balanced** | Code review, development | MEDIUM+ | ✅ Enabled | ❌ No |
| **permissive** | CI/CD, pre-commit hooks | CRITICAL only | ✅ Enabled | ✅ Yes |

---

## 💡 Implementation Options

### ✅ RECOMMENDED: Option C - Template-Based Calibration

**Rationale:**
- ✅ Simplest to implement (no new JSON config files)
- ✅ User-friendly (settings stored in existing template files)
- ✅ Backward compatible (defaults work without calibration settings)
- ✅ Flexible (can override per-scan with CLI flags)

**Usage:**

```bash
# Add to template file
echo "CALIBRATION_MODE=permissive" >> dist/TEMPLATES/elementor.txt
echo "EXCLUDE_VENDORED=true" >> dist/TEMPLATES/elementor.txt
echo "MIN_SEVERITY=CRITICAL" >> dist/TEMPLATES/elementor.txt

# Run scan with template
./check-performance.sh --template elementor
```

**CLI Override:**

```bash
# Override template settings
./check-performance.sh --template elementor --calibration strict

# One-off scan without template
./check-performance.sh --calibration permissive --exclude-vendored /path/to/plugin
```

---

## 🔧 Technical Implementation

### 1. Add Calibration Variables to Template Parser

**File:** `dist/bin/check-performance.sh`

**New Variables:**
```bash
CALIBRATION_MODE="balanced"  # strict | balanced | permissive
EXCLUDE_VENDORED=false       # true | false
MIN_SEVERITY="MEDIUM"        # INFO | LOW | MEDIUM | HIGH | CRITICAL
AI_TRIAGE_MAX_FINDINGS=200   # Number of findings to review
```

### 2. Add CLI Flags

**New Flags:**
```bash
--calibration <mode>         Set calibration mode (strict/balanced/permissive)
--exclude-vendored           Exclude vendored/minified code
--min-severity <level>       Minimum severity to report
--ai-triage-max <count>      Max findings for AI triage
```

### 3. Update Template File

**File:** `dist/TEMPLATES/_TEMPLATE.txt`

**New Section:**
```bash
# ============================================================
# CALIBRATION SETTINGS (Optional)
# ============================================================

# Calibration mode: strict | balanced | permissive
# - strict:      Security audit (all patterns, no downgrading)
# - balanced:    Code review (default, guard detection enabled)
# - permissive:  CI/CD (critical only, exclude vendored code)
# CALIBRATION_MODE=balanced

# Exclude vendored/minified code (node_modules, vendor, *.min.js)
# EXCLUDE_VENDORED=false

# Minimum severity to report (INFO | LOW | MEDIUM | HIGH | CRITICAL)
# MIN_SEVERITY=MEDIUM

# Maximum findings for AI triage (0 = unlimited)
# AI_TRIAGE_MAX_FINDINGS=200
```

### 4. Apply Calibration Logic

**Pseudo-code:**
```bash
apply_calibration_mode() {
  case "$CALIBRATION_MODE" in
    strict)
      ENABLE_GUARD_DETECTION=false
      ENABLE_SEVERITY_DOWNGRADING=false
      MIN_SEVERITY="INFO"
      EXCLUDE_VENDORED=false
      ;;
    balanced)
      ENABLE_GUARD_DETECTION=true
      ENABLE_SEVERITY_DOWNGRADING=true
      MIN_SEVERITY="MEDIUM"
      EXCLUDE_VENDORED=false
      ;;
    permissive)
      ENABLE_GUARD_DETECTION=true
      ENABLE_SEVERITY_DOWNGRADING=true
      MIN_SEVERITY="CRITICAL"
      EXCLUDE_VENDORED=true
      ;;
  esac
}
```

### 5. Vendored Code Detection

**Auto-detect patterns:**
- `*.min.js`, `*.min.css`
- `/node_modules/`, `/vendor/`, `/lib/`, `/libraries/`
- `*bundle*.js`, `*webpack*.js`

**Implementation:**
```bash
if [ "$EXCLUDE_VENDORED" = "true" ]; then
  EXCLUDE_DIRS="$EXCLUDE_DIRS node_modules vendor lib libraries"
  EXCLUDE_FILES="$EXCLUDE_FILES *.min.js *.min.css *bundle*.js *webpack*.js"
fi
```

---

## 📊 Expected Outcomes

### Before (Current State)

- Elementor scan: 509 findings, 93.5% need manual review
- No way to filter by use case
- Users overwhelmed by noise in large codebases

### After (With Calibration)

| Mode | Expected Findings | Confirmed Issues | Noise Reduction |
|------|------------------|------------------|-----------------|
| **strict** | 509 (100%) | 4 (2%) | 0% (baseline) |
| **balanced** | ~250 (49%) | 4 (2%) | 51% reduction |
| **permissive** | ~50 (10%) | 4 (2%) | 90% reduction |

**Benefits:**

1. ✅ **Security auditors** get comprehensive coverage (strict mode)
2. ✅ **Developers** get actionable findings (balanced mode)
3. ✅ **CI/CD pipelines** get fast, critical-only checks (permissive mode)
4. ✅ **Large codebases** become manageable (exclude vendored code)

---

## 🧪 Testing Plan

### 1. Unit Tests (Fixture Validation)

- [ ] Add fixtures for each calibration mode
- [ ] Verify guard detection toggles correctly
- [ ] Verify severity downgrading toggles correctly
- [ ] Verify min severity filtering works

### 2. Integration Tests (Real Plugins)

- [ ] Test strict mode on Health Check (33 files)
- [ ] Test balanced mode on Elementor (1,273 files)
- [ ] Test permissive mode on WooCommerce (large codebase)
- [ ] Verify vendored code exclusion works

### 3. Regression Tests

- [ ] Ensure default behavior unchanged (backward compatibility)
- [ ] Verify template parsing doesn't break existing templates
- [ ] Confirm CLI flags override template settings

---

## 📂 Files to Modify

1. **`dist/bin/check-performance.sh`** - Add calibration logic, CLI flags, template parsing
2. **`dist/TEMPLATES/_TEMPLATE.txt`** - Add calibration section
3. **`dist/README.md`** - Document calibration feature
4. **`EXPERIMENTAL-README.md`** - Add calibration examples
5. **`CHANGELOG.md`** - Document feature in v1.1.0

---

## 🎯 Success Criteria

- [ ] Users can set calibration mode via template or CLI flag
- [ ] Strict mode disables guard detection and severity downgrading
- [ ] Balanced mode enables guard detection (default behavior)
- [ ] Permissive mode filters to CRITICAL only and excludes vendored code
- [ ] Vendored code auto-detection works (node_modules, vendor, *.min.js)
- [ ] Backward compatible (existing scans work without changes)
- [ ] Documentation updated with examples

---

## 🚀 Rollout Plan

### Phase 1: Core Implementation (2-3 days)
- [ ] Add calibration variables and CLI flags
- [ ] Implement calibration mode logic
- [ ] Add vendored code detection

### Phase 2: Testing & Validation (1-2 days)
- [ ] Create test fixtures
- [ ] Test on Health Check, Elementor, WooCommerce
- [ ] Verify backward compatibility

### Phase 3: Documentation (1 day)
- [ ] Update README.md with calibration examples
- [ ] Update EXPERIMENTAL-README.md
- [ ] Add to CHANGELOG.md

---

## 📚 References

- **Calibration Test:** `PROJECT/3-COMPLETED/CALIBRATION-ELEMENTOR-2026-01-12.md`
- **Calibration Plan:** `PROJECT/1-INBOX/NEXT-CALIBRATION.md`
- **Phase 2.1 Improvements:** `PROJECT/3-COMPLETED/PHASE2.1-QUALITY-IMPROVEMENTS.md`

---

**Status:** ⏳ Awaiting approval to move to `PROJECT/2-WORKING/`
