# WP Code Check - Test Suite

This directory contains the test suite for WP Code Check, including fixture-based validation tests and CI environment emulation.

---

## Quick Start

### Run Tests Locally (with TTY)
```bash
./tests/run-fixture-tests.sh
```

### Run Tests in CI-Emulated Environment (no TTY)
```bash
./tests/run-tests-ci-mode.sh
```

### Run Tests with Trace Mode (detailed debugging)
```bash
./tests/run-fixture-tests.sh --trace
./tests/run-tests-ci-mode.sh --trace
```

---

## Test Scripts

### `run-fixture-tests.sh`
Main test runner that validates detection patterns against known-good/known-bad fixtures.

**Features:**
- ✅ Dependency validation (`jq`, `perl`)
- ✅ JSON parsing with error handling
- ✅ Trace mode for debugging
- ✅ Environment snapshot
- ✅ Numeric validation
- ✅ Clear pass/fail reporting

**Usage:**
```bash
# Normal mode
./tests/run-fixture-tests.sh

# Trace mode (detailed logging)
./tests/run-fixture-tests.sh --trace
```

**Expected Output:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Test Summary
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Tests Run:    10
  Passed:       10
  Failed:       0

✓ All fixture tests passed!
```

---

### `run-tests-ci-mode.sh`
CI environment emulator for testing without TTY access (simulates GitHub Actions).

**Features:**
- ✅ Removes TTY access (no `/dev/tty`)
- ✅ Sets CI environment variables
- ✅ Detaches from terminal (`setsid` or `script`)
- ✅ Validates dependencies
- ✅ Supports trace mode

**Usage:**
```bash
# Normal mode
./tests/run-tests-ci-mode.sh

# Trace mode
./tests/run-tests-ci-mode.sh --trace
```

**What It Does:**
1. Sets CI environment variables:
   - `TERM=dumb`
   - `CI=true`
   - `GITHUB_ACTIONS=true`
   - Unsets `TTY`
2. Checks for dependencies (`jq`, `perl`)
3. Detaches from TTY using:
   - `setsid` (Linux)
   - `script` (macOS fallback)
4. Runs `run-fixture-tests.sh` in detached mode
5. Reports results

**Why Use This:**
- Test CI fixes locally before pushing
- Reproduce CI failures on your machine
- Verify `/dev/tty` handling works correctly
- Ensure JSON output isn't corrupted by TTY errors

---

## Test Fixtures

Located in `./tests/fixtures/`, these files contain known patterns that should trigger specific detections:

| Fixture | Expected Errors | Expected Warnings | Tests |
|---------|----------------|-------------------|-------|
| `antipatterns.php` | 4 | 3-5 | Unbounded queries, SQL injection, ORDER BY RAND |
| `clean-code.php` | 1 | 0 | Proper pagination, prepared statements |
| `ajax-antipatterns.php` | 2 | 0-1 | Missing nonce validation |
| `ajax-antipatterns.js` | 0 | 1 | Unbounded AJAX polling |
| `ajax-safe.php` | 0 | 0 | Proper AJAX implementation |
| `cron-interval-validation.php` | 1 | 0 | Unvalidated cron intervals |
| `http-no-timeout.php` | 0 | 1 | HTTP requests without timeout |
| `transient-no-expiration.php` | 0 | 1 | Transients without expiration |
| `script-versioning-time.php` | 0 | 1 | Script versioning with `time()` |
| `file-get-contents-url.php` | 0 | 1 | `file_get_contents()` with URLs |

---

## Trace Mode

Enable detailed logging with `--trace` flag:

```bash
./tests/run-fixture-tests.sh --trace
```

**Trace Output Includes:**
- Timestamp for each operation
- Exit codes from `check-performance.sh`
- Output file sizes
- First 100 chars of JSON output
- JSON parsing method used
- Parsed values before validation
- Final validated counts

**Example Trace Output:**
```
[TRACE 21:11:57] Executing check-performance.sh for: ./tests/fixtures/antipatterns.php
[TRACE 21:11:57] check-performance.sh exit code: 0
[TRACE 21:11:57] Output file size:     12345 bytes
[TRACE 21:11:57] First 100 chars of clean output: {
[TRACE 21:11:57] Output is valid JSON, parsing with jq
[TRACE 21:11:57] Parsing JSON field: .summary.total_errors // 0
[TRACE 21:11:57] Parsed .summary.total_errors // 0 = 4
[TRACE 21:11:57] Final validated counts: errors=4, warnings=3
```

---

## Troubleshooting

### Tests Fail with "jq: command not found"
**Solution:** Install `jq`:
```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt-get install -y jq
```

### Tests Fail with "perl: command not found"
**Solution:** Install `perl`:
```bash
# macOS (usually pre-installed)
brew install perl

# Ubuntu/Debian
sudo apt-get install -y perl
```

### JSON Parsing Fails in CI
**Symptoms:**
```
[ERROR] Output is not valid JSON - cannot parse
```

**Possible Causes:**
1. `/dev/tty` errors corrupting JSON output
2. Pattern library manager output mixed with JSON
3. Bash errors in stderr captured by `2>&1`

**Solution:**
1. Run `./tests/run-tests-ci-mode.sh` locally to reproduce
2. Check `dist/bin/check-performance.sh` for `/dev/tty` usage
3. Ensure TTY availability check is in place (lines 5476-5491)

### Tests Pass Locally but Fail in CI
**Solution:** Use the CI emulator:
```bash
./tests/run-tests-ci-mode.sh --trace
```

This will show exactly what's different in the CI environment.

---

## Adding New Fixtures

1. Create fixture file in `./tests/fixtures/`
2. Add expected counts to `run-fixture-tests.sh`:
   ```bash
   # Expected counts for new-fixture.php
   NEW_FIXTURE_EXPECTED_ERRORS=2
   NEW_FIXTURE_EXPECTED_WARNINGS_MIN=1
   NEW_FIXTURE_EXPECTED_WARNINGS_MAX=1
   ```
3. Add test call:
   ```bash
   run_test "$FIXTURES_DIR/new-fixture.php" \
     "$NEW_FIXTURE_EXPECTED_ERRORS" \
     "$NEW_FIXTURE_EXPECTED_WARNINGS_MIN" \
     "$NEW_FIXTURE_EXPECTED_WARNINGS_MAX" || true
   ```
4. Run tests to verify:
   ```bash
   ./tests/run-fixture-tests.sh
   ```

---

## CI Integration

The test suite is integrated with GitHub Actions in `.github/workflows/test.yml`:

```yaml
- name: Install dependencies
  run: |
    sudo apt-get update
    sudo apt-get install -y jq

- name: Run fixture tests
  run: |
    cd dist
    ./tests/run-fixture-tests.sh
```

**CI Environment:**
- Ubuntu latest
- No TTY available
- `jq` installed explicitly
- JSON output validated

---

## Related Documentation

- **Main README:** `/README.md`
- **CHANGELOG:** `/CHANGELOG.md`
- **CI Fix Documentation:** `/PROJECT/3-COMPLETED/CI-JSON-PARSING-FIX.md`
- **Pattern Library:** `/dist/PATTERN-LIBRARY.md`

