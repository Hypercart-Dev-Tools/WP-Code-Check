# Proof of Concept: IRL Examples + Pattern Library Separation

**Date:** 2026-01-01  
**Version:** 1.0.68 (POC)  
**Status:** ✅ Complete - Ready for User Review

---

## 🎯 Objectives

1. **IRL Examples System** - Collect real-world anti-patterns from production code
2. **Pattern Library Separation** - Decouple pattern definitions from scanner logic
3. **Baby Steps Approach** - Prove concept without major refactoring

---

## ✅ What We Built

### 1. IRL (In Real Life) Examples System

**Location:** `dist/tests/irl/`

**Structure:**
```
dist/tests/irl/
├── README.md                                    # User guide
├── _AI_AUDIT_INSTRUCTIONS.md                    # AI agent workflow
└── woocommerce-all-products-for-subscriptions/
    └── class-wcs-att-admin-irl.php              # First IRL example
```

**Key Features:**
- ✅ Filename convention: `-irl` suffix (e.g., `filename-irl.php`)
- ✅ Inline annotations (no separate AUDIT.md files)
- ✅ File header summary + inline comments at each issue
- ✅ Detection status tracking (✅ detected / ❌ not detected)
- ✅ Pattern ID references for cross-linking

**Example Annotation:**
```php
// Line 58
// ANTI-PATTERN: unsanitized-superglobal-isset-bypass
// SEVERITY: HIGH
// DETECTED: ✅ Yes (v1.0.67)
// WHY: isset() only checks existence, doesn't sanitize
// FIX: Use sanitize_text_field( wp_unslash( $_GET['tab'] ) )
// PATTERN_ID: unsanitized-superglobal-isset-bypass
} elseif ( isset( $_GET['tab'] ) && $_GET['tab'] === 'subscriptions' ) {
```

**Verification:**
```bash
./dist/bin/check-performance.sh --paths "dist/tests/irl/.../class-wcs-att-admin-irl.php"
# ✅ Successfully detected the anti-pattern!
```

---

### 2. Pattern Library Separation (POC)

**Location:** `dist/patterns/` and `dist/lib/`

**Files Created:**
1. `dist/patterns/unsanitized-superglobal-isset-bypass.json` - Pattern definition
2. `dist/lib/pattern-loader.sh` - Bash library to load patterns

**Pattern JSON Schema:**
```json
{
  "id": "pattern-id",
  "version": "1.0.0",
  "enabled": true,
  "category": "security",
  "severity": "HIGH",
  "title": "Human-readable title",
  "description": "What this pattern detects",
  "rationale": "Why it matters",
  "detection": {
    "type": "grep",
    "search_pattern": "regex",
    "exclude_patterns": ["safe", "patterns"],
    "post_process": { "function_name": "filter_function" }
  },
  "test_fixture": {
    "path": "dist/tests/fixtures/test.php",
    "expected_violations": 5
  },
  "irl_examples": [
    {
      "file": "dist/tests/irl/plugin/file-irl.php",
      "line": 123,
      "code": "vulnerable code"
    }
  ],
  "remediation": {
    "summary": "How to fix",
    "examples": [{"bad": "...", "good": "..."}]
  }
}
```

**Pattern Loader Test:**
```bash
source dist/lib/pattern-loader.sh
load_pattern "dist/patterns/unsanitized-superglobal-isset-bypass.json"
echo "Pattern ID: $pattern_id"
# ✅ Output: Pattern ID: unsanitized-superglobal-isset-bypass
```

**Status:** ✅ POC works - NOT yet integrated into main scanner

---

## 📊 Benefits Demonstrated

### IRL Examples System

| Benefit | How It Helps |
|---------|--------------|
| **Validation** | Proves patterns exist in real production code |
| **Discovery** | Users can find new anti-patterns scanner misses |
| **Documentation** | Real examples are better than synthetic tests |
| **Single File** | No separate AUDIT.md to maintain |
| **Syntax Highlighting** | `-irl.php` files still highlight correctly |
| **Scannable** | Can run scanner against IRL files to verify detection |

### Pattern Library Separation

| Benefit | How It Helps |
|---------|--------------|
| **Modularity** | Add patterns without touching 3,100-line bash script |
| **Versioning** | Track when patterns were added/modified |
| **Metadata** | Pattern info is self-documenting |
| **Testing** | Each pattern links to test fixture + IRL examples |
| **Community** | Users can contribute JSON (easier than bash) |
| **No Dependencies** | Pattern loader uses only grep/sed (no jq required) |

---

## 🚀 Next Steps (User Decision)

### Option A: Keep POC As-Is (Low Risk)
- ✅ IRL system is ready to use NOW
- ✅ Pattern JSON documents existing patterns
- ⚠️ Main scanner still uses hardcoded patterns
- **Use Case:** Start collecting IRL examples, document patterns

### Option B: Integrate Pattern Loader (Medium Risk)
- Modify main scanner to load ONE pattern from JSON
- Keep all other patterns hardcoded
- Verify no performance regression
- **Timeline:** 1-2 hours
- **Risk:** Low (only affects one pattern)

### Option C: Full Migration (High Risk)
- Convert all 33 patterns to JSON
- Refactor scanner to use pattern loader
- Extract pattern engine to separate library
- **Timeline:** 8-12 hours
- **Risk:** Medium (major refactoring)

---

## 💡 Recommended Approach

**Start with Option A:**
1. Use IRL system immediately to collect real examples
2. Document patterns in JSON as you find them
3. Build confidence in the approach
4. Migrate to Option B when you have 5-10 patterns documented

**Why?**
- ✅ Immediate value (IRL examples)
- ✅ Low risk (no scanner changes)
- ✅ Validates approach before big refactor
- ✅ Builds pattern library organically

---

## 📁 Files Created/Modified

### New Files (7)
1. `dist/tests/irl/README.md` - User guide for IRL system
2. `dist/tests/irl/_AI_AUDIT_INSTRUCTIONS.md` - AI agent workflow
3. `dist/tests/irl/woocommerce-all-products-for-subscriptions/class-wcs-att-admin-irl.php` - First IRL example
4. `dist/patterns/unsanitized-superglobal-isset-bypass.json` - Pattern definition
5. `dist/lib/pattern-loader.sh` - Pattern loading library
6. `PROJECT/PROOF-OF-CONCEPT-SUMMARY.md` - This file
7. `SAFEGUARDS.md` - Critical implementation safeguards (from v1.0.67)

### Modified Files (2)
1. `CHANGELOG.md` - Added v1.0.68 entry
2. `dist/patterns/unsanitized-superglobal-isset-bypass.json` - Added IRL example reference

---

## 🧪 Verification

### Test 1: IRL File Detection
```bash
./dist/bin/check-performance.sh --paths "dist/tests/irl/woocommerce-all-products-for-subscriptions/class-wcs-att-admin-irl.php"
```
**Result:** ✅ Detected anti-pattern on line 60

### Test 2: Pattern Loader
```bash
source dist/lib/pattern-loader.sh
load_pattern "dist/patterns/unsanitized-superglobal-isset-bypass.json"
echo "$pattern_id | $pattern_severity | $pattern_title"
```
**Result:** ✅ Loaded pattern metadata successfully

### Test 3: Main Scanner Still Works
```bash
./dist/bin/check-performance.sh --project woocommerce-all-products-for-subscriptions
```
**Result:** ✅ Still detects 7 errors + 1 warning (no regression)

---

## 🎓 What We Learned

1. **Inline annotations > separate files** - Easier to maintain, better syntax highlighting
2. **`-irl` suffix works great** - Clear, scannable, editor-friendly
3. **JSON without jq is viable** - Simple grep/sed parser works for basic JSON
4. **Baby steps validate approach** - POC proves concept before big refactor
5. **IRL examples are valuable NOW** - Don't need full migration to get value

---

## 📝 User Feedback Needed

1. **IRL filename convention:** Is `-irl.php` suffix OK? Or prefer something else?
2. **Annotation format:** Is inline format clear? Too verbose?
3. **Pattern JSON schema:** Missing any important fields?
4. **Next priority:** Collect more IRL examples? Or integrate pattern loader?

---

**Status:** ✅ POC Complete - Awaiting User Decision on Next Steps

