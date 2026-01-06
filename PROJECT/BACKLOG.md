# Backlog - Future Work

Retrieve following from other branch that were not merged.

## 🍒 Cherry-Pick Tasks (from `fix/split-off-html-generator` branch)

### 1. Python HTML Report Generator ✅ **COMPLETED**
**Branch:** `fix/split-off-html-generator`
**Commit:** `713e903` - "Convert HTML generation to Python"
**Priority:** Medium
**Effort:** 1-2 hours (includes testing)
**Completed:** 2026-01-06
**Version:** v1.0.87

**What it adds:**
- `dist/bin/json-to-html.py` - Python script to convert JSON reports to HTML
- `dist/bin/json-to-html.sh` - Bash wrapper for the Python generator
- `dist/bin/templates/report-template.html` - HTML template for report generation
- More maintainable than current bash-based HTML generation
- Can generate HTML from existing JSON files (useful for re-generating reports)

**Files modified:**
- `AGENTS.md` (+44 lines) - Added JSON to HTML conversion documentation
- `dist/TEMPLATES/_AI_INSTRUCTIONS.md` (+119 lines) - Updated with Python generator guidance
- `dist/bin/check-performance.sh` (+21 lines) - Switches to Python generator
- `CHANGELOG.md` - Documented v1.0.87 changes

**Resolution:**
- ✅ Cherry-picked successfully with `--no-commit`
- ✅ No conflicts - auto-merged cleanly
- ✅ Added missing template file from commit
- ✅ Tested with clean JSON - works perfectly
- ✅ Updated version to 1.0.87
- ✅ Committed to `feature/switch-html-generator-python-2026-01-06` branch

**Testing:**
- ✅ Python generator tested with `dist/logs/test-clean.json`
- ✅ HTML report generated successfully (18.2K)
- ✅ Auto-opens in browser
- ✅ Shows detailed progress and file size

- [x] Status: **Complete** (commit 1a9b40b)

---

### 2. Node.js/JavaScript/Headless WordPress Pattern Detection
**Branch:** `fix/split-off-html-generator`
**Commits:** `2653c59`, `7180f97`, `f6b1664` - "Phase 1 & 2 completed"
**Priority:** Low (unless users request it)
**Effort:** 2-4 hours (includes testing and integration)

**What it adds:**

#### **Headless WordPress Patterns (10 patterns):**
- `dist/patterns/headless/api-key-exposure.json` - API keys exposed in client-side code
- `dist/patterns/headless/fetch-no-error-handling.json` - Missing error handling in fetch()
- `dist/patterns/headless/graphql-no-error-handling.json` - GraphQL without error handling
- `dist/patterns/headless/hardcoded-wordpress-url.json` - Hardcoded WP URLs (should use env vars)
- `dist/patterns/headless/missing-auth-headers.json` - Missing authentication headers
- `dist/patterns/headless/nextjs-missing-revalidate.json` - Next.js ISR without revalidation

#### **Node.js Security Patterns (4 patterns):**
- `dist/patterns/nodejs/command-injection.json` - Command injection vulnerabilities
- `dist/patterns/nodejs/eval-injection.json` - eval() usage (XSS risk)
- `dist/patterns/nodejs/path-traversal.json` - Path traversal vulnerabilities
- `dist/patterns/nodejs/unhandled-promise.json` - Unhandled promise rejections

#### **JavaScript DRY Violations (1 pattern):**
- `dist/patterns/js/duplicate-storage-keys.json` - Duplicate localStorage/sessionStorage keys

#### **JavaScript Validators (6 files):**
- `dist/tests/fixtures/headless/api-key-exposure-violations.js`
- `dist/tests/fixtures/headless/fetch-antipatterns.js`
- `dist/tests/fixtures/headless/graphql-antipatterns.js`
- `dist/tests/fixtures/headless/nextjs-antipatterns.js`
- `dist/tests/fixtures/js/command-injection-violations.js`
- `dist/tests/fixtures/js/eval-violations.js`
- `dist/tests/fixtures/js/promise-antipatterns.js`
- `dist/tests/fixtures/js/security-antipatterns.js`

#### **Documentation:**
- `PROJECT/1-INBOX/PROJECT-NODEJS.md` - Planning doc
- `dist/HOWTO-JAVASCRIPT-PATTERNS.md` - Guide for JavaScript pattern detection

**Files modified:**
- `dist/bin/check-performance.sh` - Adds ~250 lines for Node.js pattern loading and execution
- `dist/patterns/duplicate-functions.json` - Updated for JavaScript function detection
- `CHANGELOG.md` - Documents the feature

**Conflicts to resolve:**
- `dist/bin/check-performance.sh` - Major conflict (both branches modified heavily)
- Will need to manually integrate Node.js pattern checks into current version
- Need to ensure Node.js patterns work with Phase 1 safeguards (timeout, limits)

**Dependencies:**
- Requires `node` to be installed (for running JavaScript validators)
- Adds ~3,400 lines of code (significant scope increase)

**When to do this:**
- If users request JavaScript/Node.js security scanning
- If we need to scan headless WordPress projects (Next.js, Nuxt, etc.)
- After Phase 2-3 stability work is complete
- Only if there's actual demand for this feature

**Can we cherry-pick cleanly?**
- ✅ **YES** - Pattern files are in separate directories (`headless/`, `nodejs/`, `js/`)
- ✅ **YES** - Validator files are in separate test fixture directories
- ⚠️ **PARTIAL** - `check-performance.sh` modifications will need manual merge
- ⚠️ **PARTIAL** - Need to test that Node.js patterns respect Phase 1 safeguards

- [ ] Status: **Not started**

---

## 📋 Notes

**Recommendation:** Cherry-pick in this order:
1. **First:** Complete Phase 2-3 stability work (profiling & optimization)
2. **Then:** Cherry-pick Python HTML generator (smaller, cleaner)
3. **Finally:** Cherry-pick Node.js patterns (only if users request it)

**Why this order:**
- Stability work is higher priority (affects all users)
- Python HTML generator is low-risk, high-maintainability
- Node.js patterns are a separate feature with limited user demand (PHP-focused tool)

**Alternative approach:**
- Wait for user feedback before adding Node.js patterns
- Focus on core PHP/WordPress scanning excellence first
- Add JavaScript support only if there's proven demand
