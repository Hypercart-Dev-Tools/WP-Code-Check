# Fix CI Test Hang Issue

**Created:** 2026-01-10  
**Status:** In Progress  
**Priority:** High  
**Assigned Version:** v1.3.1

## Problem Statement

Test fixtures validation hangs in GitHub Actions CI environment but works locally and in CI emulation.

### Symptoms
- ✅ Tests pass locally (macOS): 10/10
- ✅ Tests pass in CI emulation (`run-tests-ci-mode.sh`): 10/10
- ❌ Tests hang in GitHub Actions Ubuntu environment
- ❌ Docker tests hang when running `check-performance.sh`

### Current Workaround
Temporarily disabled `validate-test-fixtures` job in `.github/workflows/ci.yml` (lines 123-181).

---

## Investigation Notes

### What We Know
1. **Local tests work** - All 10 tests pass on macOS with TTY
2. **CI emulation works** - Tests pass with `setsid`/`script` TTY detachment
3. **Docker hangs** - Tests hang when running in Ubuntu container
4. **Pattern library manager suspected** - Likely cause of hang

### What We've Tried
1. ✅ Added `jq` dependency to CI
2. ✅ Added TTY availability check in `check-performance.sh`
3. ✅ Created CI emulator script
4. ✅ Created Docker testing infrastructure
5. ❌ Docker tests still hang

### Likely Root Cause
The pattern library manager (`pattern-library-manager.sh`) is being called during each test run and may be:
- Waiting for input that never comes
- Stuck in an infinite loop
- Blocked on a file operation
- Hanging on a subprocess

---

## Next Steps

### Option 1: Skip Pattern Library Manager in Tests
Add a flag to `check-performance.sh` to skip pattern library updates during testing:

```bash
# In check-performance.sh
if [ "$SKIP_PATTERN_LIBRARY_UPDATE" = "true" ]; then
  # Skip pattern library manager
else
  # Run pattern library manager
fi
```

Then in test script:
```bash
export SKIP_PATTERN_LIBRARY_UPDATE=true
./bin/check-performance.sh --format json --paths "$fixture_file" --no-log
```

### Option 2: Debug Pattern Library Manager
Add trace logging to `pattern-library-manager.sh` to identify where it hangs:
- Add `set -x` at the top
- Log each major operation
- Identify blocking operation

### Option 3: Pre-generate Pattern Library
Generate pattern library once before tests, then skip updates:
```bash
# Before tests
./bin/pattern-library-manager.sh both

# During tests
export SKIP_PATTERN_LIBRARY_UPDATE=true
./tests/run-fixture-tests.sh
```

### Option 4: Timeout Pattern Library Manager
Add timeout to pattern library manager call:
```bash
timeout 10 bash "$SCRIPT_DIR/pattern-library-manager.sh" both > /dev/null 2>&1 || true
```

---

## Acceptance Criteria

- [ ] Tests pass 10/10 in GitHub Actions CI
- [ ] Tests complete in reasonable time (<5 minutes total)
- [ ] No hangs or timeouts
- [ ] JSON output is clean and valid
- [ ] Pattern library is still updated (or acceptable to skip during tests)

---

## Files to Modify

| File | Change Needed |
|------|---------------|
| `dist/bin/check-performance.sh` | Add `SKIP_PATTERN_LIBRARY_UPDATE` flag support |
| `dist/tests/run-fixture-tests.sh` | Set `SKIP_PATTERN_LIBRARY_UPDATE=true` |
| `.github/workflows/ci.yml` | Re-enable `validate-test-fixtures` job |
| `CHANGELOG.md` | Document fix |

---

## Testing Plan

1. **Local testing:**
   ```bash
   export SKIP_PATTERN_LIBRARY_UPDATE=true
   ./tests/run-fixture-tests.sh
   ```

2. **CI emulation:**
   ```bash
   export SKIP_PATTERN_LIBRARY_UPDATE=true
   ./tests/run-tests-ci-mode.sh
   ```

3. **Docker testing:**
   ```bash
   docker run --rm \
     -v "$(pwd):/workspace" \
     -w /workspace/dist \
     -e CI=true \
     -e SKIP_PATTERN_LIBRARY_UPDATE=true \
     ubuntu:24.04 \
     bash -c 'apt-get update >/dev/null 2>&1 && apt-get install -y jq perl >/dev/null 2>&1 && ./tests/run-fixture-tests.sh'
   ```

4. **GitHub Actions:**
   - Push to PR branch
   - Verify tests complete without hanging
   - Verify 10/10 tests pass

---

## Related

- **CI Workflow:** `.github/workflows/ci.yml`
- **Test Script:** `dist/tests/run-fixture-tests.sh`
- **Core Scanner:** `dist/bin/check-performance.sh`
- **Pattern Library Manager:** `dist/bin/pattern-library-manager.sh`
- **Previous Fix:** `PROJECT/3-COMPLETED/CI-JSON-PARSING-FIX.md`

---

## Notes

- Pattern library manager is useful for keeping patterns up-to-date
- During testing, we don't need to regenerate the pattern library every time
- Skipping pattern library updates during tests is acceptable
- Pattern library can still be updated manually or during normal scans

