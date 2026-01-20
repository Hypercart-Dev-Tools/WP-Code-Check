# Decision: Node.js/Headless WordPress Extraction Strategy

**Created:** 2026-01-06
**Status:** Awaiting Decision
**Priority:** Medium
**Branches Involved:**
- Current: `feature/switch-html-generator-python-2026-01-06` (4212 lines)
- Source: `origin/rules/nodejs-wp-headless-phase-2` (3920 lines)
- Diff: ~1150 lines of changes

## Context

We need to extract Node.js and Headless WordPress pattern detection from the `rules/nodejs-wp-headless-phase-2` branch. The BACKLOG.md lists this as the next major task.

## Two Approaches

### Option A: Extract JSON Files First, Rebuild Logic Later ✅ **RECOMMENDED**

**What we extract:**
1. **Pattern JSON files** (11 files) - Clean, no conflicts
   - `dist/patterns/headless/*.json` (6 files)
   - `dist/patterns/nodejs/*.json` (4 files)
   - `dist/patterns/js/*.json` (1 file)

2. **Test fixtures** (8 files) - Clean, no conflicts
   - `dist/tests/fixtures/headless/*.js` (4 files)
   - `dist/tests/fixtures/js/*.js` (4 files)

3. **Documentation** (2 files) - May need updates
   - `PROJECT/1-INBOX/PROJECT-NODEJS.md`
   - `dist/HOWTO-JAVASCRIPT-PATTERNS.md`

**Then rebuild:**
- Write new pattern loading logic from scratch
- Integrate with current Phase 1 safeguards (timeout, limits)
- Test incrementally with each pattern type
- Ensure compatibility with current architecture

**Pros:**
- ✅ **Safer** - No risk of breaking current functionality
- ✅ **Cleaner** - New code follows current best practices
- ✅ **Testable** - Can test each pattern type independently
- ✅ **Maintainable** - Code is written with current architecture in mind
- ✅ **No conflicts** - JSON files are in separate directories
- ✅ **Incremental** - Can add patterns one at a time
- ✅ **Phase 1 compliant** - Built with safeguards from the start

**Cons:**
- ⏱️ **More time** - Need to rewrite ~250 lines of logic
- 🔄 **Duplication** - Some logic may be similar to old branch
- 📝 **More testing** - Need to verify new implementation

**Estimated Effort:** 3-4 hours
- 30 min: Extract JSON files and fixtures
- 1 hour: Write pattern loading logic
- 1 hour: Integrate with main script
- 1 hour: Testing and validation

---

### Option B: Extract Node.js Logic First, Adapt to Current ⚠️ **RISKY**

**What we extract:**
1. All files from Option A
2. **Logic from check-performance.sh** (~250 lines)
   - JavaScript/Node.js pattern detection functions
   - File type detection (`.js`, `.jsx`, `.ts`, `.tsx`)
   - Node.js-specific validators

**Then adapt:**
- Resolve merge conflicts in check-performance.sh
- Retrofit Phase 1 safeguards into old code
- Update to match current architecture
- Fix any broken references

**Pros:**
- ⏱️ **Faster initial extraction** - Copy existing code
- 📋 **Complete feature** - All logic is already written
- 🧪 **Proven** - Code worked in original branch

**Cons:**
- ❌ **High conflict risk** - 1150 lines of diff in main script
- ❌ **Architecture mismatch** - Old code predates Phase 1 safeguards
- ❌ **Hard to test** - Large changes make debugging difficult
- ❌ **Regression risk** - Could break existing PHP patterns
- ❌ **Technical debt** - May not follow current best practices
- ❌ **All-or-nothing** - Hard to test incrementally

**Estimated Effort:** 4-6 hours
- 1 hour: Extract logic from old branch
- 2 hours: Resolve merge conflicts
- 1 hour: Retrofit Phase 1 safeguards
- 2 hours: Testing and debugging

---

## Analysis

### Current Branch Status
- **Current version:** v1.0.88 (4212 lines)
- **Node.js branch:** v1.0.82 (3920 lines)
- **Difference:** +292 lines in current (Phase 1-3 work)

### What's in Current Branch (Not in Node.js Branch)
- ✅ Phase 1: Timeout detection, file limits, loop bounds
- ✅ Phase 2: Performance profiling (`PROFILE=1`)
- ✅ Phase 3: Clone detection optimization (`--skip-clone-detection`)
- ✅ Smart N+1 detection with cache awareness
- ✅ Python HTML generator
- ✅ JSON output bug fixes

### What's in Node.js Branch (Not in Current)
- 📦 11 pattern JSON files (headless, nodejs, js)
- 🧪 8 test fixture files
- 📝 2 documentation files
- 🔧 ~250 lines of pattern loading logic

### Risk Assessment

| Risk Factor | Option A (JSON First) | Option B (Logic First) |
|-------------|----------------------|------------------------|
| **Breaking existing patterns** | Low | High |
| **Merge conflicts** | None | Severe (1150 lines) |
| **Testing complexity** | Low (incremental) | High (all-at-once) |
| **Regression risk** | Low | High |
| **Architecture mismatch** | None (new code) | High (old code) |
| **Debugging difficulty** | Low | High |
| **Rollback difficulty** | Easy | Hard |

---

## Recommendation: Option A (JSON First) ✅

### Why Option A is Safer

1. **Zero Conflict Risk**
   - JSON files are in separate directories (`headless/`, `nodejs/`, `js/`)
   - No overlap with existing PHP patterns
   - Can extract with simple `git checkout`

2. **Incremental Development**
   - Add headless patterns first
   - Then nodejs patterns
   - Then js patterns
   - Test each type independently

3. **Phase 1 Compliance**
   - New code built with safeguards from the start
   - Timeout wrappers for all grep operations
   - File count limits for all pattern types
   - Loop iteration limits for aggregation

4. **Better Architecture**
   - Can use current helper functions
   - Follows current naming conventions
   - Integrates with current error handling
   - Uses current logging format

5. **Easier Testing**
   - Test one pattern at a time
   - Verify fixtures work correctly
   - Ensure no impact on PHP patterns
   - Can rollback individual patterns

### Implementation Plan (Option A)

**Phase 1: Extract Files (30 min)**
```bash
# Extract pattern JSON files
git checkout origin/rules/nodejs-wp-headless-phase-2 -- dist/patterns/headless/
git checkout origin/rules/nodejs-wp-headless-phase-2 -- dist/patterns/nodejs/
git checkout origin/rules/nodejs-wp-headless-phase-2 -- dist/patterns/js/

# Extract test fixtures
git checkout origin/rules/nodejs-wp-headless-phase-2 -- dist/tests/fixtures/headless/
git checkout origin/rules/nodejs-wp-headless-phase-2 -- dist/tests/fixtures/js/

# Extract documentation
git checkout origin/rules/nodejs-wp-headless-phase-2 -- dist/HOWTO-JAVASCRIPT-PATTERNS.md
```

**Phase 2: Write Pattern Loading Logic (1 hour)**
- Create `load_javascript_pattern()` function
- Add file type detection (`.js`, `.jsx`, `.ts`, `.tsx`)
- Integrate with existing `load_pattern()` architecture
- Add timeout wrappers for grep operations

**Phase 3: Integrate with Main Script (1 hour)**
- Add JavaScript pattern discovery
- Update pattern execution loop
- Add Node.js validator support
- Update help text and documentation

**Phase 4: Testing (1 hour)**
- Test each pattern type independently
- Verify fixtures pass validation
- Ensure no impact on PHP patterns
- Run full scan on test project

---

## Decision Needed

**Question:** Which approach do you prefer?

- **Option A:** Extract JSON files first, rebuild logic (safer, cleaner, 3-4 hours)
- **Option B:** Extract logic first, adapt to current (riskier, faster initial, 4-6 hours)

**My recommendation:** Option A - The extra 30-60 minutes of development time is worth the reduced risk and cleaner architecture.

