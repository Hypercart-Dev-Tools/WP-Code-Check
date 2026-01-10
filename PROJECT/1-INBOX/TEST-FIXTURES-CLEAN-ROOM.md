I'll create a comprehensive plan for a clean-room rewrite of the test fixture system.

---

# Test Fixture Runner: Clean Room Rewrite Plan

## Executive Summary

A complete rewrite of `run-fixture-tests.sh` designed for guaranteed cross-platform compatibility (macOS local development, GitHub Actions Ubuntu CI), with first-class observability, explicit contracts, and zero silent failures.

---

## 1. Design Principles

### 1.1 Core Philosophy

| Principle | Implementation |
|-----------|----------------|
| **Fail fast, fail loud** | Every operation validates its result; no silent fallbacks |
| **Explicit over implicit** | All formats, dependencies, and paths are explicitly declared |
| **Environment-agnostic** | Same code path on macOS and Linux; no OS-specific branches |
| **Observable by default** | Structured logging that works for humans, agents, and CI |
| **Hermetic tests** | No reliance on ambient environment; script controls its context |

### 1.2 Non-Goals

- No interactive prompts or TTY-dependent features
- No color codes in CI mode (optional locally)
- No fallback parsing strategies (JSON only)
- No implicit dependency on shell-specific features (zsh, bash 5+, etc.)

---

## 2. Architecture

### 2.1 Component Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                     run-fixture-tests.sh                        │
├─────────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌────────────────────────┐ │
│  │   Precheck   │  │   Runner     │  │   Reporter             │ │
│  │              │  │              │  │                        │ │
│  │ • deps       │  │ • exec tests │  │ • JSON (CI)            │ │
│  │ • env        │  │ • capture    │  │ • Human (local)        │ │
│  │ • fixtures   │  │ • validate   │  │ • JUnit XML (optional) │ │
│  └──────────────┘  └──────────────┘  └────────────────────────┘ │
├─────────────────────────────────────────────────────────────────┤
│                        Shared Utilities                         │
│  • log() - structured logging                                   │
│  • assert_eq() - validation with context                        │
│  • parse_json() - single JSON extraction method                 │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 File Structure

```
dist/
├── tests/
│   ├── run-fixture-tests.sh      # Main entry point
│   ├── lib/
│   │   ├── precheck.sh           # Dependency & environment validation
│   │   ├── runner.sh             # Test execution engine
│   │   ├── reporter.sh           # Output formatting
│   │   └── utils.sh              # Shared utilities
│   ├── fixtures/
│   │   ├── antipatterns.php
│   │   ├── clean-code.php
│   │   └── ...
│   └── expected/
│       └── fixture-expectations.json   # Single source of truth for expected counts
```

---

## 3. Implementation Guidelines

### 3.1 Shell Compatibility

```bash
#!/usr/bin/env bash

# Require Bash 4+ for associative arrays (macOS ships 3.2, but brew bash is 5+)
# Alternative: Avoid associative arrays entirely for maximum compatibility

# POSIX-safe minimum
set -o pipefail    # Catch pipeline failures
shopt -s nullglob  # Empty glob returns empty, not literal

# Explicitly DO NOT use:
# - set -e (we need granular error handling)
# - set -u (we handle unset vars explicitly)
# - Bash 4+ features unless checked
```

### 3.2 Dependency Declaration

Create `lib/precheck.sh`:

```bash
#!/usr/bin/env bash

# Required dependencies with minimum versions
declare -A REQUIRED_DEPS=(
  [jq]="1.5"
  [perl]="5.0"
  [bash]="3.2"
)

# Optional dependencies (enhance but not required)
declare -a OPTIONAL_DEPS=(
  "unbuffer"  # Better output capture
  "timeout"   # Test timeouts
)

precheck_dependencies() {
  local missing=()
  local outdated=()

  for dep in "${!REQUIRED_DEPS[@]}"; do
    if ! command -v "$dep" >/dev/null 2>&1; then
      missing+=("$dep")
    fi
  done

  if [ ${#missing[@]} -gt 0 ]; then
    log ERROR "Missing required dependencies: ${missing[*]}"
    log INFO "Install with:"
    log INFO "  Ubuntu: sudo apt-get install -y ${missing[*]}"
    log INFO "  macOS:  brew install ${missing[*]}"
    return 1
  fi

  # Log versions for debugging
  log DEBUG "jq version: $(jq --version 2>&1)"
  log DEBUG "perl version: $(perl -v 2>&1 | grep version | head -1)"
  log DEBUG "bash version: $BASH_VERSION"

  return 0
}

precheck_environment() {
  # Detect and normalize environment
  export CI="${CI:-false}"
  export TERM="${TERM:-dumb}"
  
  # Disable colors in CI or dumb terminal
  if [ "$CI" = "true" ] || [ "$TERM" = "dumb" ]; then
    export NO_COLOR=1
  fi

  # Warn about TTY absence (informational, not fatal)
  if [ ! -e /dev/tty ]; then
    log DEBUG "No /dev/tty available (CI environment detected)"
  fi

  # Validate working directory
  if [ ! -f "./bin/check-performance.sh" ]; then
    log ERROR "Must run from dist/ directory"
    log ERROR "Current directory: $(pwd)"
    return 1
  fi

  return 0
}

precheck_fixtures() {
  local fixtures_dir="$1"
  local expectations_file="$2"
  local missing=()

  # Validate expectations file exists
  if [ ! -f "$expectations_file" ]; then
    log ERROR "Expectations file not found: $expectations_file"
    return 1
  fi

  # Validate each fixture referenced in expectations exists
  while IFS= read -r fixture; do
    if [ ! -f "$fixtures_dir/$fixture" ]; then
      missing+=("$fixture")
    fi
  done < <(jq -r 'keys[]' "$expectations_file")

  if [ ${#missing[@]} -gt 0 ]; then
    log ERROR "Missing fixture files: ${missing[*]}"
    return 1
  fi

  return 0
}
```

### 3.3 Structured Logging

Create `lib/utils.sh`:

```bash
#!/usr/bin/env bash

# Log levels
declare -A LOG_LEVELS=(
  [ERROR]=0
  [WARN]=1
  [INFO]=2
  [DEBUG]=3
  [TRACE]=4
)

# Default log level (override with --verbose, --trace, or LOG_LEVEL env)
LOG_LEVEL="${LOG_LEVEL:-INFO}"

# Output format: "human" or "json"
LOG_FORMAT="${LOG_FORMAT:-human}"

log() {
  local level="$1"
  shift
  local message="$*"
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Check if we should output this level
  local level_num="${LOG_LEVELS[$level]:-2}"
  local current_level_num="${LOG_LEVELS[$LOG_LEVEL]:-2}"

  if [ "$level_num" -gt "$current_level_num" ]; then
    return 0
  fi

  if [ "$LOG_FORMAT" = "json" ]; then
    # Structured JSON logging (great for CI log aggregation)
    printf '{"timestamp":"%s","level":"%s","message":"%s"}\n' \
      "$timestamp" "$level" "$message" >&2
  else
    # Human-readable with optional colors
    local color=""
    local reset=""

    if [ -z "${NO_COLOR:-}" ]; then
      case "$level" in
        ERROR) color='\033[0;31m' ;;
        WARN)  color='\033[1;33m' ;;
        INFO)  color='\033[0;32m' ;;
        DEBUG) color='\033[0;34m' ;;
        TRACE) color='\033[0;90m' ;;
      esac
      reset='\033[0m'
    fi

    printf "${color}[%s] %s${reset}\n" "$level" "$message" >&2
  fi
}

# Assertion helper with context
assert_eq() {
  local name="$1"
  local expected="$2"
  local actual="$3"
  local context="${4:-}"

  if [ "$expected" = "$actual" ]; then
    log DEBUG "PASS: $name (expected=$expected, actual=$actual)"
    return 0
  else
    log ERROR "FAIL: $name"
    log ERROR "  Expected: $expected"
    log ERROR "  Actual:   $actual"
    [ -n "$context" ] && log ERROR "  Context:  $context"
    return 1
  fi
}

# Safe JSON extraction (single method, no fallbacks)
parse_json() {
  local json="$1"
  local path="$2"
  local default="${3:-0}"
  local result

  # Validate input is JSON
  if ! echo "$json" | jq empty 2>/dev/null; then
    log ERROR "parse_json: Input is not valid JSON"
    log DEBUG "parse_json: First 100 chars: ${json:0:100}"
    echo "$default"
    return 1
  fi

  result=$(echo "$json" | jq -r "$path // \"$default\"" 2>/dev/null)

  if [ -z "$result" ] || [ "$result" = "null" ]; then
    echo "$default"
  else
    echo "$result"
  fi
}
```

### 3.4 Test Expectations as Data

Create `tests/expected/fixture-expectations.json`:

```json
{
  "_meta": {
    "version": "1.0.0",
    "updated": "2026-01-10",
    "description": "Expected error/warning counts for fixture files"
  },
  "antipatterns.php": {
    "errors": 9,
    "warnings": { "min": 4, "max": 4 },
    "description": "Intentional antipatterns for detection validation"
  },
  "clean-code.php": {
    "errors": 1,
    "warnings": { "min": 0, "max": 0 },
    "description": "Clean code with minimal issues"
  },
  "ajax-antipatterns.php": {
    "errors": 1,
    "warnings": { "min": 1, "max": 1 },
    "description": "REST/AJAX antipatterns"
  },
  "ajax-antipatterns.js": {
    "errors": 2,
    "warnings": { "min": 0, "max": 0 },
    "description": "JavaScript polling antipatterns"
  },
  "ajax-safe.php": {
    "errors": 0,
    "warnings": { "min": 0, "max": 0 },
    "description": "Safe AJAX patterns (negative test)"
  },
  "file-get-contents-url.php": {
    "errors": 1,
    "warnings": { "min": 0, "max": 0 },
    "description": "file_get_contents() with URLs"
  },
  "http-no-timeout.php": {
    "errors": 0,
    "warnings": { "min": 1, "max": 1 },
    "description": "HTTP requests without timeout"
  },
  "cron-interval-validation.php": {
    "errors": 1,
    "warnings": { "min": 0, "max": 0 },
    "description": "Unvalidated cron intervals"
  }
}
```

### 3.5 Test Runner

Create `lib/runner.sh`:

```bash
#!/usr/bin/env bash

# Run a single fixture test
# Returns: 0 = pass, 1 = fail
run_single_test() {
  local fixture_path="$1"
  local expected_errors="$2"
  local expected_warnings_min="$3"
  local expected_warnings_max="$4"
  local fixture_name
  fixture_name=$(basename "$fixture_path")

  log INFO "Testing: $fixture_name"
  log DEBUG "Expected: errors=$expected_errors, warnings=$expected_warnings_min-$expected_warnings_max"

  # Create temp file for output capture
  local tmp_output
  tmp_output=$(mktemp)
  trap "rm -f '$tmp_output'" RETURN

  # Execute scanner with EXPLICIT format
  # - --format json: Explicit contract, not relying on default
  # - --no-log: Suppress log file creation
  # - 2>&1: Capture stderr (but we expect clean JSON on stdout)
  local scanner_cmd="./bin/check-performance.sh --paths \"$fixture_path\" --format json --no-log"
  log DEBUG "Executing: $scanner_cmd"

  # Run with timeout to prevent hangs
  if command -v timeout >/dev/null 2>&1; then
    timeout 30 bash -c "$scanner_cmd" > "$tmp_output" 2>&1
  else
    bash -c "$scanner_cmd" > "$tmp_output" 2>&1
  fi
  local exit_code=$?

  log DEBUG "Scanner exit code: $exit_code"
  log TRACE "Output size: $(wc -c < "$tmp_output") bytes"

  # Read and clean output (strip any ANSI codes that leaked through)
  local raw_output
  raw_output=$(cat "$tmp_output")

  local clean_output
  clean_output=$(echo "$raw_output" | perl -pe 's/\e\[[0-9;]*m//g' 2>/dev/null || echo "$raw_output")

  # Validate output is JSON
  if ! echo "$clean_output" | jq empty 2>/dev/null; then
    log ERROR "Scanner output is not valid JSON"
    log ERROR "First 200 chars: ${clean_output:0:200}"
    log DEBUG "Full output saved to: $tmp_output"

    # Check for common issues
    if echo "$clean_output" | grep -q "/dev/tty"; then
      log ERROR "TTY-related error detected - scanner may be writing to /dev/tty"
    fi

    return 1
  fi

  # Extract counts using single parsing method
  local actual_errors
  local actual_warnings
  actual_errors=$(parse_json "$clean_output" '.summary.total_errors')
  actual_warnings=$(parse_json "$clean_output" '.summary.total_warnings')

  log DEBUG "Parsed: errors=$actual_errors, warnings=$actual_warnings"

  # Validate counts
  local errors_ok=false
  local warnings_ok=false

  [ "$actual_errors" -eq "$expected_errors" ] && errors_ok=true
  [ "$actual_warnings" -ge "$expected_warnings_min" ] && \
  [ "$actual_warnings" -le "$expected_warnings_max" ] && warnings_ok=true

  if [ "$errors_ok" = true ] && [ "$warnings_ok" = true ]; then
    log INFO "PASS: $fixture_name"
    return 0
  else
    log ERROR "FAIL: $fixture_name"
    [ "$errors_ok" = false ] && \
      log ERROR "  Errors: expected $expected_errors, got $actual_errors"
    [ "$warnings_ok" = false ] && \
      log ERROR "  Warnings: expected $expected_warnings_min-$expected_warnings_max, got $actual_warnings"
    return 1
  fi
}

# Run all fixtures from expectations file
run_all_tests() {
  local fixtures_dir="$1"
  local expectations_file="$2"

  local total=0
  local passed=0
  local failed=0

  # Iterate through expectations file
  while IFS= read -r fixture; do
    # Skip meta key
    [ "$fixture" = "_meta" ] && continue

    local expected_errors
    local expected_warnings_min
    local expected_warnings_max

    expected_errors=$(jq -r ".[\"$fixture\"].errors" "$expectations_file")
    expected_warnings_min=$(jq -r ".[\"$fixture\"].warnings.min" "$expectations_file")
    expected_warnings_max=$(jq -r ".[\"$fixture\"].warnings.max" "$expectations_file")

    ((total++))

    if run_single_test "$fixtures_dir/$fixture" \
        "$expected_errors" "$expected_warnings_min" "$expected_warnings_max"; then
      ((passed++))
    else
      ((failed++))
    fi

  done < <(jq -r 'keys[]' "$expectations_file")

  # Return results as JSON for structured reporting
  printf '{"total":%d,"passed":%d,"failed":%d}' "$total" "$passed" "$failed"

  [ "$failed" -eq 0 ]
}
```

### 3.6 Main Entry Point

Create new `run-fixture-tests.sh`:

```bash
#!/usr/bin/env bash
#
# WP Code Check - Fixture Validation Tests
# Version: 2.0.0
#
# Cross-platform test runner for macOS and GitHub Actions Ubuntu.
# Designed for observability, explicit contracts, and zero silent failures.
#
# Usage:
#   ./tests/run-fixture-tests.sh [OPTIONS]
#
# Options:
#   --ci          Force CI mode (no colors, structured logging)
#   --verbose     Show DEBUG level logs
#   --trace       Show TRACE level logs (very verbose)
#   --json        Output results as JSON
#   --help        Show this help
#
# Environment Variables:
#   CI=true           Auto-detected in GitHub Actions
#   LOG_LEVEL=DEBUG   Set logging verbosity
#   NO_COLOR=1        Disable colored output
#

set -o pipefail

# Script directory resolution (works with symlinks)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="$(dirname "$SCRIPT_DIR")"

# Source libraries
source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/precheck.sh"
source "$SCRIPT_DIR/lib/runner.sh"

# Configuration
FIXTURES_DIR="$SCRIPT_DIR/fixtures"
EXPECTATIONS_FILE="$SCRIPT_DIR/expected/fixture-expectations.json"

# Parse arguments
parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --ci)
        export CI=true
        export NO_COLOR=1
        export LOG_FORMAT=json
        ;;
      --verbose)
        export LOG_LEVEL=DEBUG
        ;;
      --trace)
        export LOG_LEVEL=TRACE
        ;;
      --json)
        export OUTPUT_FORMAT=json
        ;;
      --help)
        grep '^#' "$0" | grep -v '!/usr/bin' | cut -c3-
        exit 0
        ;;
      *)
        log WARN "Unknown argument: $1"
        ;;
    esac
    shift
  done
}

main() {
  parse_args "$@"

  log INFO "WP Code Check - Fixture Validation Tests v2.0.0"
  log INFO "================================================"

  # Change to dist directory
  cd "$DIST_DIR" || {
    log ERROR "Failed to change to dist directory: $DIST_DIR"
    exit 1
  }
  log DEBUG "Working directory: $(pwd)"

  # Pre-flight checks
  log INFO "Running pre-flight checks..."

  if ! precheck_dependencies; then
    log ERROR "Dependency check failed"
    exit 1
  fi

  if ! precheck_environment; then
    log ERROR "Environment check failed"
    exit 1
  fi

  if ! precheck_fixtures "$FIXTURES_DIR" "$EXPECTATIONS_FILE"; then
    log ERROR "Fixture check failed"
    exit 1
  fi

  log INFO "Pre-flight checks passed"
  log INFO ""

  # Run tests
  log INFO "Running fixture tests..."
  local results
  results=$(run_all_tests "$FIXTURES_DIR" "$EXPECTATIONS_FILE")
  local test_exit=$?

  # Parse results
  local total passed failed
  total=$(echo "$results" | jq -r '.total')
  passed=$(echo "$results" | jq -r '.passed')
  failed=$(echo "$results" | jq -r '.failed')

  # Output summary
  log INFO ""
  log INFO "================================================"
  log INFO "Test Summary"
  log INFO "================================================"
  log INFO "Total:  $total"
  log INFO "Passed: $passed"
  log INFO "Failed: $failed"

  if [ "$test_exit" -eq 0 ]; then
    log INFO "All tests passed!"
    exit 0
  else
    log ERROR "$failed test(s) failed"
    exit 1
  fi
}

main "$@"
```

---

## 4. CI Integration

### 4.1 GitHub Actions Workflow

```yaml
name: CI

on:
  pull_request:
    branches: [main, development]
  workflow_dispatch:

jobs:
  test-fixtures:
    name: Fixture Tests
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Install dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y jq perl
          echo "jq version: $(jq --version)"
          echo "perl version: $(perl -v | head -2)"

      - name: Run fixture tests
        run: |
          cd dist
          ./tests/run-fixture-tests.sh --ci --verbose
        env:
          CI: true

      - name: Upload test output
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: test-output
          path: /tmp/test-*.log
          retention-days: 7
```

### 4.2 Local Testing Commands

Add to `Makefile`:

```makefile
.PHONY: test test-ci test-docker test-verbose

# Standard local test
test:
	cd dist && ./tests/run-fixture-tests.sh

# CI emulation mode
test-ci:
	cd dist && ./tests/run-fixture-tests.sh --ci --verbose

# Verbose debugging
test-verbose:
	cd dist && ./tests/run-fixture-tests.sh --trace

# Full Docker-based Linux test
test-docker:
	docker run --rm \
		-v "$(PWD):/workspace" \
		-w /workspace/dist \
		-e CI=true \
		-e NO_COLOR=1 \
		ubuntu:24.04 \
		bash -c 'apt-get update >/dev/null && apt-get install -y jq perl >/dev/null && ./tests/run-fixture-tests.sh --ci --verbose' \
		2>&1 | tee /tmp/docker-test.log
```

---

## 5. Testing the Test Runner

### 5.1 Validation Checklist

| Test | macOS | Ubuntu CI | Docker |
|------|-------|-----------|--------|
| Dependencies detected | ☐ | ☐ | ☐ |
| Missing jq fails fast | ☐ | ☐ | ☐ |
| All fixtures pass | ☐ | ☐ | ☐ |
| JSON output valid | ☐ | ☐ | ☐ |
| --ci flag works | ☐ | ☐ | ☐ |
| --trace shows debug | ☐ | ☐ | ☐ |
| No TTY errors | ☐ | ☐ | ☐ |
| Colors disabled in CI | ☐ | ☐ | ☐ |

### 5.2 Regression Tests for the Runner Itself

```bash
# Test 1: Verify missing dependency detection
(
  PATH=/usr/bin  # Remove jq from path
  ./tests/run-fixture-tests.sh 2>&1 | grep -q "Missing required dependencies"
) && echo "PASS: Missing dep detection" || echo "FAIL: Missing dep detection"

# Test 2: Verify CI mode disables colors
OUTPUT=$(CI=true ./tests/run-fixture-tests.sh --ci 2>&1 | head -5)
if echo "$OUTPUT" | grep -q $'\033'; then
  echo "FAIL: Colors present in CI mode"
else
  echo "PASS: No colors in CI mode"
fi

# Test 3: Verify JSON parsing failure is detected
echo "not json" | parse_json - '.foo' 2>&1 | grep -q "not valid JSON" && \
  echo "PASS: Invalid JSON detected" || echo "FAIL: Invalid JSON not detected"
```

---

## 6. Migration Path

### 6.1 Parallel Running Period

1. Keep existing `run-fixture-tests.sh` as `run-fixture-tests-legacy.sh`
2. Deploy new version as `run-fixture-tests.sh`
3. Run both in CI for 1-2 weeks to validate parity
4. Remove legacy version once confident

### 6.2 Rollback Plan

```bash
# If new version fails in CI:
git checkout HEAD~1 -- dist/tests/run-fixture-tests.sh
```

---

## 7. Documentation Updates

Update `README.md` in tests directory:

```markdown
## Running Tests

### Quick Start
```bash
cd dist
./tests/run-fixture-tests.sh
```

### CI Emulation (recommended before PR)
```bash
./tests/run-fixture-tests.sh --ci --verbose
```

### Full Linux Emulation
```bash
make test-docker
```

### Updating Expected Counts
Edit `tests/expected/fixture-expectations.json` when adding new patterns.

### Debugging Failures
```bash
./tests/run-fixture-tests.sh --trace 2>&1 | tee debug.log
```
```

---

## 8. Success Criteria

- [ ] All 10 fixture tests pass on macOS (local)
- [ ] All 10 fixture tests pass on Ubuntu (GitHub Actions)
- [ ] All 10 fixture tests pass in Docker (local Linux emulation)
- [ ] `--ci` flag produces no color codes
- [ ] `--trace` flag produces detailed debugging output
- [ ] Missing `jq` fails immediately with actionable message
- [ ] Invalid JSON from scanner fails with clear error
- [ ] No `/dev/tty` related errors in any environment
- [ ] Test expectations are data-driven (single JSON file)
- [ ] CHANGELOG accurately reflects architecture

---

This plan provides a solid foundation for a robust, cross-platform test runner. Want me to start implementing any specific section?