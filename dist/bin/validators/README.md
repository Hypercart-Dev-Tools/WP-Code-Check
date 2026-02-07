# Pattern Validators

Validators are scripts that perform context-aware analysis to reduce false positives in pattern detection.

## Overview

When a pattern uses `"detection_type": "validated"`, the scanner will:
1. Run the initial grep/pattern match
2. For each finding, call the validator script
3. Filter results based on validator exit codes

## Validator API

### Input Parameters
Validators receive two positional arguments:
```bash
validator.sh <file_path> <line_number>
```

- `file_path`: Absolute path to the file containing the finding
- `line_number`: Line number where the pattern was matched

### Exit Codes
Validators must return one of these exit codes:

| Exit Code | Meaning | Action |
|-----------|---------|--------|
| `0` | **Confirmed Issue** | Include finding in report |
| `1` | **False Positive** | Filter out finding |
| `2` | **Needs Review** | Flag for manual inspection |

### Example Validator Structure
```bash
#!/usr/bin/env bash
set -euo pipefail

FILE="$1"
LINE_NUMBER="$2"

# Validate inputs
if [ ! -f "$FILE" ]; then
  echo "ERROR: File not found: $FILE" >&2
  exit 2
fi

# Perform context analysis
# ... your validation logic here ...

# Return appropriate exit code
if [ condition_for_confirmed_issue ]; then
  exit 0  # Confirmed issue
elif [ condition_for_false_positive ]; then
  exit 1  # False positive
else
  exit 2  # Needs manual review
fi
```

## Existing Validators

### 1. `wc-coupon-thankyou-context-validator.sh`
**Pattern**: `wc-coupon-in-thankyou`  
**Purpose**: Validates that coupon operations are in thank-you context, not checkout hooks  
**Checks**:
- Whether hook registration is commented out (dead code)
- Actual hook name the function is registered to
- Whether hook is in safe list (checkout) or problematic list (thank-you)

**Example Usage**:
```bash
./wc-coupon-thankyou-context-validator.sh functions.php 42
# Exit 0 = Coupon in thank-you hook (issue)
# Exit 1 = Coupon in checkout hook (false positive)
# Exit 2 = Could not determine context (needs review)
```

### 2. `context-pattern-check.sh`
**Pattern**: Generic context validator  
**Purpose**: Checks if a pattern exists within N lines of a match  
**Usage**:
```bash
./context-pattern-check.sh <file> <line> <pattern> [context_lines] [direction]
```

**Parameters**:
- `pattern`: Extended regex to search for
- `context_lines`: Number of lines to check (default: 10)
- `direction`: `"after"`, `"before"`, or `"both"` (default: `"after"`)

**Example**:
```bash
# Check if fetch() appears within 5 lines after line 42
./context-pattern-check.sh app.js 42 "fetch\(" 5 after
```

## Adding a Validator to a Pattern

### Step 1: Create the Validator Script
```bash
# Create validator in dist/bin/validators/
touch dist/bin/validators/my-pattern-validator.sh
chmod +x dist/bin/validators/my-pattern-validator.sh
```

### Step 2: Implement Validation Logic
See "Example Validator Structure" above.

### Step 3: Create Test Fixtures
```bash
# Create test fixtures in dist/bin/fixtures/
touch dist/bin/fixtures/my-pattern-true-positive.php
touch dist/bin/fixtures/my-pattern-false-positive.php
```

### Step 4: Write Tests
```bash
# Create test suite
touch dist/bin/test-my-pattern-validator.sh
chmod +x dist/bin/test-my-pattern-validator.sh
```

See `test-wc-coupon-validator.sh` for example test structure.

### Step 5: Update Pattern JSON
```json
{
  "id": "my-pattern",
  "detection_type": "validated",
  "validator": "dist/bin/validators/my-pattern-validator.sh",
  ...
}
```

### Step 6: Run Tests
```bash
./dist/bin/test-my-pattern-validator.sh
```

## Best Practices

### Performance
- ✅ Use `grep` instead of loops when possible
- ✅ Extract context once, then analyze in memory
- ✅ Limit search scope (e.g., 100 lines before/after)
- ❌ Avoid reading entire file multiple times
- ❌ Avoid nested loops over file contents

### Reliability
- ✅ Validate all inputs (file exists, line number is numeric)
- ✅ Handle edge cases (file boundaries, empty files)
- ✅ Use `set -euo pipefail` for error handling
- ✅ Return exit code 2 when uncertain
- ❌ Don't assume file structure or formatting

### Maintainability
- ✅ Add comments explaining validation logic
- ✅ Use descriptive variable names
- ✅ Create comprehensive test fixtures
- ✅ Document expected behavior in pattern JSON
- ❌ Don't hardcode file paths or line numbers

## Testing Validators

### Manual Testing
```bash
# Test with specific file and line
./dist/bin/validators/my-validator.sh path/to/file.php 42
echo "Exit code: $?"
```

### Automated Testing
```bash
# Run test suite
./dist/bin/test-my-validator.sh
```

### Integration Testing
```bash
# Run full scan with validator
./dist/bin/check-performance.sh path/to/project
```

## Troubleshooting

### Validator Not Being Called
- Check `detection_type` is set to `"validated"` in pattern JSON
- Verify `validator` path is correct and file is executable
- Check scanner logs for validator errors

### Validator Always Returns Exit 2
- Add debug output: `bash -x ./validator.sh file.php 42`
- Check if validation logic is too strict
- Verify input parameters are being parsed correctly

### Performance Issues
- Profile with `time ./validator.sh file.php 42`
- Check for unnecessary file reads or loops
- Consider caching results for repeated calls

## Future Improvements

- [ ] Add validator result caching
- [ ] Support for multi-file context analysis
- [ ] Validator performance metrics in reports
- [ ] Validator API versioning
- [ ] Shared validator library functions

