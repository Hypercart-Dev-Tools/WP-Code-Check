#!/usr/bin/env bash
#
# Test Pattern Loading
#

# Source the pattern loader
source dist/lib/pattern-loader.sh

# Test loading the duplicate-option-names pattern
PATTERN_FILE="dist/patterns/duplicate-option-names.json"

echo "Testing pattern load from: $PATTERN_FILE"
echo ""

if [ ! -f "$PATTERN_FILE" ]; then
  echo "ERROR: Pattern file not found!"
  exit 1
fi

# Load the pattern
if load_pattern "$PATTERN_FILE"; then
  echo "✓ Pattern loaded successfully"
  echo ""
  echo "Pattern Metadata:"
  echo "  ID: $pattern_id"
  echo "  Enabled: $pattern_enabled"
  echo "  Detection Type: $pattern_detection_type"
  echo "  Category: $pattern_category"
  echo "  Severity: $pattern_severity"
  echo "  Title: $pattern_title"
  echo ""
  echo "Search Pattern:"
  echo "  Length: ${#pattern_search} characters"
  echo "  Value: [$pattern_search]"
  echo ""
  
  if [ -z "$pattern_search" ]; then
    echo "❌ ERROR: pattern_search is EMPTY!"
    echo ""
    echo "Attempting manual extraction with Python..."
    python3 -c "import json; f=open('$PATTERN_FILE'); d=json.load(f); print('Pattern from JSON:', d['detection']['search_pattern']); f.close()"
    echo ""
    echo "Attempting manual extraction with grep/sed..."
    grep '"search_pattern"' "$PATTERN_FILE" | head -1
  else
    echo "✓ pattern_search is populated"
    echo ""
    echo "Testing grep with this pattern..."
    echo "Command: grep -rHn --include=\"*.php\" -E \"\$pattern_search\" dist/tests/fixtures/dry"
    echo ""
    matches=$(grep -rHn --include="*.php" -E "$pattern_search" dist/tests/fixtures/dry 2>&1)
    match_count=$(echo "$matches" | grep -c . || echo "0")
    echo "Found $match_count matches"
    if [ "$match_count" -gt 0 ]; then
      echo ""
      echo "First 5 matches:"
      echo "$matches" | head -5
    fi
  fi
else
  echo "❌ Failed to load pattern"
  exit 1
fi

