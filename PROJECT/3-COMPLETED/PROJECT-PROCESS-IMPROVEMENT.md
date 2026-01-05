# Process Improvement Recommendations

**Date:** January 2, 2026  
**Analyst:** GitHub Copilot (Claude 3.7 Sonnet)  
**Subject:** wp-code-check Development Process  
**Current Version:** 1.0.76  
**Analysis Period:** v1.0.41 → v1.0.76 (35 releases, ~2 weeks)

---

## Executive Summary

**Overall Assessment:** Process is **90% excellent** with room for 10% improvement in **shipping velocity** and **decision-making efficiency**.

**Key Finding:** Documentation thoroughness (a strength) has become a bottleneck. The developer is **documenting more than doing**, leading to delayed bug fixes and feature delivery.

**Evidence:** 
- 400-line implementation doc written but bug still unfixed
- Path-with-spaces bug persists since v1.0.67 across multiple versions
- 35 version bumps in 2 weeks (many could be batched)

**Recommendation:** Embrace "ship fast, document later" for non-critical paths while maintaining quality standards.

---

## Personality Profile Context

### Identified Type: **INTJ (Architect) with Strong ISTJ Tendencies**

**Core Strengths:**
- ✅ Perfectionist with zero-tolerance for technical debt
- ✅ Obsessive documentation & knowledge preservation
- ✅ Process-oriented & systematic thinker
- ✅ Production-first mentality
- ✅ False-positive paranoia (in a good way)

**Working Style:**
- 📝 Meticulous attention to detail
- 🎯 Long-term thinking with safeguards
- 🧪 Test-driven validation against production code
- 📚 Teaching through code and documentation
- 🔍 Pragmatic perfectionism

**Potential Risks:**
- ⚠️ Analysis paralysis from over-planning
- ⚠️ Documentation debt accumulation
- ⚠️ Scope creep from thoroughness
- ⚠️ Solo development echo chamber

---

## Process Improvement Areas

### 1. Documentation Overhead Reduction ⚡ **HIGH IMPACT**

#### Current State ❌
- Multiple overlapping documents (4 fixture docs, multiple PROJECT files)
- 400+ line implementation docs for ~100 lines of code changes
- Every small change requires updating CHANGELOG, version numbers, multiple docs

**Evidence:**
```
IMPLEMENTATION-FILE-PATH-HELPERS.md: 550+ lines
Actual code change needed: ~100 lines (4 loop fixes)
Documentation-to-code ratio: 5.5:1
```

#### Recommended State ✅

**A. Adopt Architecture Decision Records (ADRs)**

Create lightweight decision documents:

```markdown
# PROJECT/DECISIONS/ADR-001-centralized-path-helpers.md

## Status: Accepted

## Context
- 4 file iteration loops break with paths containing spaces
- URL encoding duplicated 3 times
- HTML escaping duplicated 3 times

## Decision
Create safe_file_iterator() in common-helpers.sh

## Consequences
- +100 LOC (new helpers)
- -4 bugs (space handling)
- -40 LOC (removed duplication)
```

**Benefits:**
- ⏱️ 80% less documentation time
- 🎯 Focus on decisions, not implementation details
- 📚 Easy to scan and reference

**B. Consolidate Project Documentation**

```
PROJECT/
├── ACTIVE/              # Current work (max 5 files)
│   ├── BUG-paths-with-spaces.md
│   └── FEATURE-dry-violations.md
├── DECISIONS/           # ADRs (permanent)
│   ├── ADR-001-path-helpers.md
│   └── ADR-002-json-patterns.md
├── GUIDES/              # Reusable patterns
│   └── testing-guide.md
└── ARCHIVE/            # Completed work (move after 30 days)
    └── 2025-12/
```

**C. Implement "Runbook" Pattern**

For implementation tasks:

```markdown
# BUG-paths-with-spaces.md

## Problem (1 paragraph)
File iteration loops split on spaces: `for file in $FILES`

## Solution (code diff)
```bash
-for file in $FILES; do
+while IFS= read -r file; do
```

## Test (3 commands)
```bash
mkdir -p "/tmp/test path"
echo '<?php get_terms();' > "/tmp/test path/test.php"
./check-performance.sh --paths "/tmp/test path"
```

## Done ✅
```

**Impact:** Reduce documentation overhead by 60%, ship 2x faster.

---

### 2. Combat Over-Engineering 🔧 **HIGH IMPACT**

#### Current State ❌

**Example:** File path helpers create 6 functions for 2 use cases

```bash
# Proposed (125 lines):
safe_file_iterator()      # Used 4 times ✅
url_encode_path()         # Used 3 times ✅
html_escape_string()      # Used 3 times ✅
create_file_link()        # Used 1 time ⚠️
create_directory_link()   # Used 1 time ⚠️
validate_file_path()      # Used 0 times ❌
```

#### Recommended State ✅

**Apply YAGNI (You Aren't Gonna Need It) Principle:**

```bash
# Minimal viable solution (40 lines):
safe_file_iterator()      # Fixes critical bug
html_encode()            # Combines URL + HTML escaping
```

**Decision Tree:**
```
Is the bug critical?          → YES → Fix now
Used 3+ times?                → NO  → Wait
Common across projects?       → NO  → Keep inline
```

**Refactoring Rule:**
> Create abstractions on the **third occurrence**, not the first.

**Example Application:**

```bash
# First occurrence: Inline solution
encoded=$(printf '%s' "$path" | jq -sRr @uri)

# Second occurrence: Copy-paste with comment
# TODO: If this appears a third time, extract to helper

# Third occurrence: Extract to function
url_encode_path() { ... }
```

**Impact:** Reduce code by 50%, maintain flexibility, avoid premature abstraction.

---

### 3. Test-First for Critical Bugs 🧪 **CRITICAL**

#### Current State ❌

Path-with-spaces bug exists since v1.0.67 (fixed 16 grep commands), yet appears again in 4 different loops.

**Evidence:**
```
v1.0.67: Fixed 16 grep commands with quotes
v1.0.77: Same bug in 4 file iteration loops
Pattern: Regression not caught by test suite
```

#### Recommended State ✅

**A. Create Critical Patterns Test Suite**

```bash
# dist/tests/test-critical-paths.sh

#!/usr/bin/env bash
set -euo pipefail

# Test 1: Paths with spaces
test_paths_with_spaces() {
  local test_dir="/tmp/wp-test path with spaces"
  mkdir -p "$test_dir"
  echo '<?php get_terms("category");' > "$test_dir/test.php"
  
  local output=$("$SCRIPT_DIR/../bin/check-performance.sh" --paths "$test_dir" --format json)
  
  # Assert: No line number = 0 (indicates path was split)
  local zero_lines=$(echo "$output" | jq -r '.findings[] | select(.line == 0) | .line' | wc -l)
  if [ "$zero_lines" -gt 0 ]; then
    echo "FAIL: Found findings with line=0 (path splitting bug)"
    exit 1
  fi
  
  # Assert: File path is complete (not truncated at space)
  local truncated=$(echo "$output" | jq -r '.findings[] | select(.file | contains("/tmp/wp-test") and (contains(" path") | not))' | wc -l)
  if [ "$truncated" -gt 0 ]; then
    echo "FAIL: File paths truncated at space"
    exit 1
  fi
  
  echo "PASS: Paths with spaces handled correctly"
  rm -rf "$test_dir"
}

# Test 2: Special characters
test_special_characters() {
  # Similar pattern for &, <, >, ", '
}

# Run all tests
test_paths_with_spaces
test_special_characters
```

**B. Add to CI Pipeline**

```yaml
# .github/workflows/ci.yml
- name: Critical path tests
  run: |
    chmod +x ./dist/tests/test-critical-paths.sh
    ./dist/tests/test-critical-paths.sh
```

**C. Update SAFEGUARDS.md**

```markdown
## Critical Pattern: File Iteration

### ✅ CORRECT
```bash
while IFS= read -r file; do
  # ... process file
done < <(printf '%s\n' "$FILES")
```

### ❌ NEVER USE
```bash
for file in $FILES; do  # Splits on spaces!
  # ... process file
done
```

### Test
`./dist/tests/test-critical-paths.sh`

### Verification
All 16 grep commands + 4 file iteration loops must use correct pattern.
```

**Impact:** Catch regressions immediately instead of 10 versions later.

---

### 4. Batch Version Releases ⚡ **MEDIUM IMPACT**

#### Current State ❌

35 versions in ~2 weeks, many for minor fixes:

```
v1.0.44 - Improved error display formatting
v1.0.43 - Updated PROJECT.md documentation
v1.0.42 - Reflected feedback into BACKLOG.md
```

#### Recommended State ✅

**A. Semantic Versioning with Intent**

```
MAJOR (2.0.0):  Breaking changes
MINOR (1.1.0):  New features (user-facing)
PATCH (1.0.1):  Bug fixes + refactors (batched weekly)
```

**B. Branch Versioning Strategy**

```
main:            v1.0.76 (stable, tagged)
develop:         v1.0.77-dev (daily work, not tagged)
release/1.1.0:   Feature branches (weekly)
hotfix/critical: Emergency fixes (immediate)
```

**C. Weekly Release Cadence**

```
Monday:    Cut release branch from develop
           Run full test suite
           
Wednesday: Staging validation
           Update CHANGELOG
           
Friday:    Merge to main
           Tag version
           Deploy
```

**D. CHANGELOG Consolidation**

**Before:**
```markdown
## [1.0.44] - 2025-12-29
- Improved error display formatting

## [1.0.43] - 2025-12-29
- Updated documentation
```

**After:**
```markdown
## [1.0.44] - 2025-12-29

### Changed
- Improved error display formatting
- Updated PROJECT.md documentation
- Reflected feedback into BACKLOG.md

### Fixed
- Path variable quoting in 16 grep commands
```

**Impact:** Cleaner CHANGELOG, easier for users to track meaningful updates, reduce release overhead.

---

### 5. Time-Box Decisions ⏱️ **HIGH IMPACT**

#### Current State ❌

Analysis paralysis: 400-line doc written, bug still unfixed.

**Evidence:**
```
IMPLEMENTATION-FILE-PATH-HELPERS.md created
Estimated Effort: 2-3 hours
Status: Not yet implemented
Bug: Still affecting users
```

#### Recommended State ✅

**A. Decision Velocity Framework**

```
Critical bugs:     Fix in 30 minutes or escalate
Features:          2-hour spike, then go/no-go
Refactors:         Must show 3x ROI or defer
Documentation:     Write after shipping, not before
```

**B. "Fix First, Refactor Later" for Bugs**

**Option 1: Quick Fix (5 minutes) → Ship today**
```bash
while IFS= read -r file; do
  # ... existing logic
done < <(printf '%s\n' "$FILES")
```

**Option 2: Perfect Abstraction (2 hours) → Ship when you hit this 3x**
```bash
safe_file_iterator "$FILES" | while IFS= read -r file; do
  # ... existing logic
done
```

**Decision Rule:**
> Ship Option 1 immediately. Document tech debt. Refactor when you encounter the pattern three times.

**C. Use GitHub Issues for Prioritization**

```
Labels:
  bug/critical      → Fix within 1 day
  bug/high          → Fix this sprint (1 week)
  refactor/debt     → Backlog (review quarterly)
  docs/improve      → As time permits
```

**Example:**
```markdown
## Issue: Paths with spaces break file iteration

**Priority:** `bug/critical`
**Effort:** 30 minutes
**Fix:** Replace `for` with `while read`
**Tech Debt:** Extract to helper on 3rd occurrence

---

✅ Fixed in 15 minutes
📝 Tech debt logged: "Extract safe_file_iterator() if seen 2+ more times"
```

**Impact:** Ship 2x faster, maintain quality, reduce WIP.

---

### 6. Establish Feedback Loops 🔄 **MEDIUM IMPACT**

#### Current State ❌

Solo development → Echo chamber:
- No one to challenge "do we need 6 functions?"
- No one to say "ship the bug fix now"
- Decisions documented but not debated

**Evidence:**
```
IMPLEMENTATION-FILE-PATH-HELPERS.md: 550 lines
Audience: Self (future reference)
Review: None (pre-emptive documentation)
```

#### Recommended State ✅

**A. Find a Code Review Partner**

```
Weekly 30-minute sessions:
  - Review 1-2 PRs each
  - Focus: "Is this necessary?" not "Is this perfect?"
  - Time-box discussions: 5 min per decision
```

**Partner Selection:**
- Another WordPress developer
- Different skill level (fresh perspective)
- Shared values (quality, pragmatism)

**B. Open Source Community Engagement**

```markdown
## RFC: Centralized Path Helpers

I'm refactoring file path handling into reusable helpers.

**Problem:** 4 loops break with spaces in paths
**Proposed:** 6 helper functions in common-helpers.sh

**Question:** Would you use these helpers in your scripts?

Options:
A. Ship all 6 functions
B. Ship minimal fix (1 function)
C. Different approach?

Vote by reacting: 👍 = A, 🎉 = B, 🤔 = C
```

**Platforms:**
- WordPress.org forums
- Reddit r/webdev or r/programming
- Hacker News (Show HN)

**C. Rubber Duck Documentation**

**Rule:** If you can't explain it in 3 sentences, it's too complex.

**Before:**
```markdown
# 550 lines of implementation details
```

**After:**
```markdown
Problem: Paths with spaces break 4 loops
Fix: Use `while read` instead of `for`
Test: Create path with spaces, run scanner
```

**Impact:** Faster decisions, external validation, avoid over-engineering.

---

### 7. Add Performance Benchmarks 📊 **MEDIUM IMPACT**

#### Current State ❌

Tool scans production code but has no performance metrics.

**Missing:**
```
How much overhead do 6 helper functions add?
Is the refactor worth the performance cost?
```

#### Recommended State ✅

**A. Create Benchmark Suite**

```bash
# dist/tests/benchmark.sh

#!/usr/bin/env bash

BENCHMARK_PLUGIN="/path/to/large/plugin"  # 500+ files
ITERATIONS=5

echo "Running performance benchmarks..."

# Baseline
total=0
for i in $(seq 1 $ITERATIONS); do
  start=$(date +%s.%N)
  ./bin/check-performance.sh --paths "$BENCHMARK_PLUGIN" --no-log > /dev/null 2>&1
  end=$(date +%s.%N)
  duration=$(echo "$end - $start" | bc)
  total=$(echo "$total + $duration" | bc)
done

average=$(echo "$total / $ITERATIONS" | bc -l)
printf "Average scan time: %.2f seconds\n" "$average"

# Save baseline
echo "$average" > benchmark-results.txt
```

**B. Track in CI**

```yaml
- name: Performance regression check
  run: |
    BEFORE=$(cat benchmark-results.txt)
    AFTER=$(./dist/tests/benchmark.sh | grep "Average" | awk '{print $4}')
    THRESHOLD=$(echo "$BEFORE * 1.10" | bc)  # 10% tolerance
    
    if (( $(echo "$AFTER > $THRESHOLD" | bc -l) )); then
      echo "⚠️  Performance regression detected"
      echo "Before: ${BEFORE}s"
      echo "After: ${AFTER}s"
      echo "Threshold: ${THRESHOLD}s"
      exit 1
    fi
```

**C. Document Trade-offs**

```markdown
## Performance Impact: Path Helpers

**Baseline:** 5.2s for 500-file scan
**With helpers:** 5.4s (+3.8%)
**Threshold:** <10% acceptable

**Trade-off Analysis:**
- Cost: +200ms scan time
- Benefit: Prevents 4 bug classes
- Verdict: ✅ Acceptable (bugs > 200ms)
```

**Impact:** Data-driven decisions, catch performance regressions early.

---

### 8. Define "Done" Explicitly ✅ **HIGH IMPACT**

#### Current State ❌

When is a feature actually complete?

**Evidence:**
```
IMPLEMENTATION-FILE-PATH-HELPERS.md lists 10 files to modify
But no "Definition of Done" checklist
Unclear when to stop documenting and start coding
```

#### Recommended State ✅

**A. Create Checklist Template**

```markdown
# PROJECT/ACTIVE/BUG-paths-with-spaces.md

## Definition of Done

### Code
- [ ] Bug reproducer test added
- [ ] Fix implemented and verified
- [ ] No new warnings or errors
- [ ] Code reviewed (self or peer)

### Testing
- [ ] Unit tests passing
- [ ] Integration tests passing
- [ ] Manual test with paths containing spaces
- [ ] Regression test with normal paths

### Documentation
- [ ] CHANGELOG entry written
- [ ] Version bumped (if releasing)
- [ ] SAFEGUARDS.md updated (if critical pattern)
- [ ] Inline comments added for tricky code

### CI/CD
- [ ] All CI checks passing
- [ ] Branch merged to develop
- [ ] Tagged (if releasing to main)

### Cleanup
- [ ] Branch deleted
- [ ] Issue closed
- [ ] Doc moved to ARCHIVE (if >30 days old)
```

**B. Use Git Hooks**

```bash
# .git/hooks/pre-commit

#!/usr/bin/env bash

# Check CHANGELOG updated
if ! grep -q "## \[.*\].*$(date +%Y-%m-%d)" CHANGELOG.md; then
  echo "⚠️  CHANGELOG not updated for today's date"
  echo "Add entry before committing"
  exit 1
fi

# Check no TODO comments in critical files
if grep -rn "TODO" dist/bin/check-performance.sh | grep -q "FIXME\|HACK\|XXX"; then
  echo "⚠️  Found TODO/FIXME/HACK/XXX comments in critical file"
  echo "Resolve before committing or add to backlog"
  exit 1
fi
```

**C. GitHub Issue Templates**

```yaml
# .github/ISSUE_TEMPLATE/bug-fix.yml

name: Bug Fix
description: Report a bug with definition of done checklist
body:
  - type: textarea
    label: Bug Description
    
  - type: textarea
    label: Steps to Reproduce
    
  - type: checkboxes
    label: Definition of Done
    options:
      - label: Test case added
      - label: Fix verified
      - label: CHANGELOG updated
      - label: CI passing
      - label: SAFEGUARDS.md updated (if critical)
```

**Impact:** Clear completion criteria, avoid "90% done" limbo, ship faster.

---

## Implementation Roadmap

### Phase 1: Quick Wins (Week 1) ⚡

**Focus:** High-impact, low-effort improvements

| Action | Effort | Impact | Priority |
|--------|--------|--------|----------|
| Create ADR template | 30 min | HIGH | 1 |
| Add "Definition of Done" checklist | 30 min | HIGH | 2 |
| Implement time-boxing rules | 15 min | HIGH | 3 |
| Create critical paths test | 2 hours | CRITICAL | 4 |
| Batch version bumps | 30 min | MEDIUM | 5 |

**Total:** ~4 hours  
**Expected ROI:** 2x shipping velocity

---

### Phase 2: Process Changes (Week 2-3) 🔧

**Focus:** Sustainable process improvements

| Action | Effort | Impact | Priority |
|--------|--------|--------|----------|
| Reorganize PROJECT folder | 1 hour | HIGH | 1 |
| Create benchmark suite | 2 hours | MEDIUM | 2 |
| Set up weekly release cadence | 1 hour | MEDIUM | 3 |
| Write "Guides" for common patterns | 2 hours | MEDIUM | 4 |
| Add performance CI checks | 2 hours | MEDIUM | 5 |

**Total:** ~8 hours  
**Expected ROI:** Sustainable velocity, reduced tech debt

---

### Phase 3: Culture Shift (Month 2) 🌱

**Focus:** Long-term behavioral changes

| Action | Effort | Impact | Priority |
|--------|--------|--------|----------|
| Find code review partner | 2 hours | HIGH | 1 |
| Post RFC to community | 1 hour | MEDIUM | 2 |
| Establish YAGNI decision tree | 1 hour | HIGH | 3 |
| Create rubber duck template | 30 min | MEDIUM | 4 |
| Quarterly tech debt review | 2 hours | MEDIUM | 5 |

**Total:** ~7 hours  
**Expected ROI:** External feedback, reduced echo chamber

---

## Measuring Success

### Key Metrics

**Velocity Metrics:**
```
Current:  1 feature per 2-3 days (with docs)
Target:   1 feature per day (fix fast, doc later)
Measure:  Time from issue creation to merge
```

**Quality Metrics:**
```
Current:  0 false positives (excellent)
Target:   Maintain 0 false positives
Measure:  User reports + test suite
```

**Documentation Efficiency:**
```
Current:  5.5:1 doc-to-code ratio
Target:   1:1 doc-to-code ratio
Measure:  Lines of docs per feature
```

**Regression Prevention:**
```
Current:  Path bug regression (v1.0.67 → v1.0.77)
Target:   0 regressions in critical patterns
Measure:  CI test failures on known bugs
```

---

### Success Criteria (3 Months)

**Must Have:**
- [ ] Ship features 2x faster (without sacrificing quality)
- [ ] Zero regressions in critical patterns
- [ ] CHANGELOG readable by users (not just developers)
- [ ] All critical bugs caught by test suite

**Should Have:**
- [ ] Documentation overhead reduced 60%
- [ ] Performance tracked and stable (<10% variance)
- [ ] Weekly release cadence established
- [ ] Code review partnership active

**Nice to Have:**
- [ ] Community engagement (1+ RFC posted)
- [ ] Tech debt reduced by 25%
- [ ] Contributor guidelines established
- [ ] Performance benchmarks public

---

## Anti-Patterns to Avoid

### 1. ❌ Don't Swing Too Far

**Risk:** Over-correcting from "document everything" to "document nothing"

**Balance:**
- ✅ Critical patterns: Document before coding
- ✅ Refactors: Code first, doc after
- ✅ Bugs: Fix immediately, minimal docs

---

### 2. ❌ Don't Skip Tests

**Risk:** Shipping faster by cutting quality corners

**Safeguard:**
```
Speed ≠ Skipping tests
Speed = Smaller batches + faster feedback
```

**Always:**
- [ ] Add test for every bug
- [ ] Run full suite before merge
- [ ] CI must pass

---

### 3. ❌ Don't Ignore Tech Debt

**Risk:** "We'll refactor later" becomes "We'll never refactor"

**Rule:**
```
Log tech debt immediately
Review quarterly
Refactor when pain > 3x cost
```

**Example:**
```markdown
## Tech Debt Log

1. **Path iteration pattern** (logged v1.0.77)
   - Pain: 4 occurrences, 1 regression
   - Cost: 2 hours to create helper
   - Status: ✅ Refactored (pain 4x > cost 2h)

2. **URL encoding duplication** (logged v1.0.77)
   - Pain: 3 occurrences, no regressions
   - Cost: 1 hour to centralize
   - Status: ⏸️ Defer (not yet 3x pain)
```

---

### 4. ❌ Don't Lose the Craftsmanship

**Risk:** "Ship fast" becomes "ship sloppy"

**Maintain:**
- ✅ Zero false positives
- ✅ Thoughtful architecture
- ✅ User empathy
- ✅ Long-term thinking

**Quote to Remember:**
> "Fast is slow, smooth is fast. Ship small, ship often, ship right."

---

## Conclusion

### The Core Message

**You're an excellent developer.** The process improvements aren't about fixing broken things—they're about **removing friction** so your skills can shine through faster.

**Current State:**
```
Idea → [2 hours docs] → [30 min code] → [1 hour testing] → Ship
```

**Improved State:**
```
Idea → [30 min code] → [1 hour testing] → Ship → [30 min docs]
```

**Same quality. Half the time. More impact.**

---

### Three Questions to Ask Daily

1. **"Am I documenting or doing?"**
   - If documenting > 50% of time → Stop, code first

2. **"Will this matter in 6 months?"**
   - If no → Ship the simple version
   - If yes → Document the decision (ADR)

3. **"Can this wait until the third occurrence?"**
   - If yes → Add TODO, ship now
   - If no → Critical pattern, fix properly

---

### Final Recommendation

**Start Here (This Week):**

1. ✅ Create `PROJECT/DECISIONS/` folder for ADRs
2. ✅ Add "Definition of Done" template
3. ✅ Fix paths-with-spaces bug (30 min fix, not 2-hour refactor)
4. ✅ Add critical paths test to CI
5. ✅ Batch next 3 version bumps into one release

**Time Investment:** 4 hours  
**Expected Return:** 2x velocity within 2 weeks

---

**Remember:** Perfect is the enemy of shipped. Your users need the bug fix today, not the perfect abstraction next week.

---

## Appendix A: Templates

### ADR Template

```markdown
# ADR-XXX: [Title]

## Status
[Proposed | Accepted | Rejected | Deprecated | Superseded]

## Context
[What problem are we solving? Why now?]

## Decision
[What are we doing? Be specific.]

## Consequences
### Positive
- [Benefit 1]
- [Benefit 2]

### Negative
- [Trade-off 1]
- [Trade-off 2]

### Neutral
- [Other change 1]

## Implementation
- [ ] Task 1
- [ ] Task 2

## Alternatives Considered
### Option A: [Name]
- Pros: ...
- Cons: ...
- Verdict: Rejected because...

## References
- Issue: #123
- Related ADR: ADR-001
- Docs: link
```

---

### Runbook Template

```markdown
# [Issue Type]: [Brief Title]

**Priority:** [Critical | High | Medium | Low]  
**Estimated Effort:** [30min | 2h | 1 day | 1 week]

## Problem (1-2 sentences)
[What's broken? Why does it matter?]

## Solution (code snippet)
```bash
# Before
[broken code]

# After
[fixed code]
```

## Test (3 commands)
```bash
[test setup]
[run command]
[verify result]
```

## Done
- [ ] Code changed
- [ ] Test passing
- [ ] CHANGELOG updated
- [ ] Merged

---

**Implemented:** [Date]  
**Version:** [x.x.x]
```

---

### Definition of Done Checklist

```markdown
## Definition of Done

### Before Coding
- [ ] Issue exists with clear description
- [ ] Acceptance criteria defined
- [ ] Estimated effort < 1 day (or break into smaller tasks)

### During Development
- [ ] Code follows project style
- [ ] No new warnings or errors
- [ ] Passes local tests
- [ ] Self-reviewed (read your own diff)

### Before Commit
- [ ] Test case added (for bugs)
- [ ] All tests passing locally
- [ ] CHANGELOG entry written
- [ ] Commit message descriptive

### Before Merge
- [ ] CI checks passing
- [ ] Code reviewed (if available)
- [ ] No merge conflicts
- [ ] Branch up to date with main

### After Merge
- [ ] Issue closed
- [ ] Branch deleted
- [ ] Monitor for issues (24 hours)
- [ ] Move docs to ARCHIVE (if applicable)
```

---

## Appendix B: Decision Frameworks

### Time-Boxing Framework

```
Decision Type          | Time Limit | Action if Exceeded
--------------------- | ---------- | ------------------
Critical bug fix      | 30 minutes | Escalate or ship minimal fix
Feature spike         | 2 hours    | Go/No-Go decision
Refactoring           | 1 day      | Prove 3x ROI or defer
Documentation         | 1 hour     | Ship code, doc later
Research              | 4 hours    | Write ADR, get feedback
```

### YAGNI Decision Tree

```
┌─ Is it critical? ──────────────────┐
│  YES: Fix now                      │
│  NO:  Continue...                  │
└────────────────────────────────────┘
         │
         ▼
┌─ Used 3+ times? ───────────────────┐
│  YES: Abstract it                  │
│  NO:  Continue...                  │
└────────────────────────────────────┘
         │
         ▼
┌─ Common pattern across projects? ──┐
│  YES: Extract to library           │
│  NO:  Keep inline, add TODO        │
└────────────────────────────────────┘
```

### Refactoring ROI Calculator

```
Pain Score = (Occurrences × Complexity × Regression_Risk)
Cost = (Hours_to_refactor × 2)  # Include testing & docs

If Pain > 3 × Cost:
  → Refactor now
Else:
  → Log tech debt, defer
```

**Example:**
```
Path iteration bug:
  Occurrences: 4
  Complexity: 3/10
  Regression_Risk: 9/10
  Pain = 4 × 3 × 9 = 108

  Cost = 2 hours × 2 = 4
  Threshold = 3 × 4 = 12

  108 > 12 → Refactor immediately ✅
```

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-01-02 | GitHub Copilot (Claude 3.7 Sonnet) | Initial analysis |

---

**End of Report**
