#!/usr/bin/env bash
#
# Pattern Loader Library
# Version: 1.0.0
#
# Loads pattern definitions from JSON files and makes them available to the scanner
#

# Load a single pattern from JSON file
# Usage: load_pattern "path/to/pattern.json"
# Returns: Sets global variables with pattern_ prefix
load_pattern() {
  local pattern_file="$1"
  
  if [ ! -f "$pattern_file" ]; then
    echo "ERROR: Pattern file not found: $pattern_file" >&2
    return 1
  fi
  
  # Extract key fields using grep/sed (no jq dependency)
  # This is a simple parser - only handles basic JSON structure

  pattern_id=$(grep '"id"' "$pattern_file" | head -1 | sed 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
  pattern_enabled=$(grep '"enabled"' "$pattern_file" | head -1 | sed 's/.*"enabled"[[:space:]]*:[[:space:]]*\([^,]*\).*/\1/' | tr -d ' ')
  pattern_detection_type=$(grep '"detection_type"' "$pattern_file" | head -1 | sed 's/.*"detection_type"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
  pattern_category=$(grep '"category"' "$pattern_file" | head -1 | sed 's/.*"category"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
  pattern_severity=$(grep '"severity"' "$pattern_file" | head -1 | sed 's/.*"severity"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
  pattern_title=$(grep '"title"' "$pattern_file" | head -1 | sed 's/.*"title"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')

  # Extract search_pattern using Python for reliable JSON parsing
  # Use stdin to avoid issues with special characters in filenames
  if command -v python3 &> /dev/null; then
    pattern_search=$(python3 <<EOFPYTHON 2>/dev/null
import json
import sys
try:
    with open('$pattern_file', 'r') as f:
        data = json.load(f)
        print(data['detection']['search_pattern'])
except Exception as e:
    sys.stderr.write(str(e))
    sys.exit(1)
EOFPYTHON
)
  elif command -v python &> /dev/null; then
    pattern_search=$(python <<EOFPYTHON 2>/dev/null
import json
try:
    with open('$pattern_file', 'r') as f:
        data = json.load(f)
        print data['detection']['search_pattern']
except Exception as e:
    print >> sys.stderr, str(e)
    sys.exit(1)
EOFPYTHON
)
  else
    # Fallback to grep/sed (less reliable for complex patterns)
    pattern_search=$(grep '"search_pattern"' "$pattern_file" | head -1 | cut -d'"' -f4 | sed 's/\\\\/\\/g')
  fi

  # Default to "direct" if not specified (backward compatibility)
  if [ -z "$pattern_detection_type" ]; then
    pattern_detection_type="direct"
  fi

  # Export for use in calling script
  export pattern_id pattern_enabled pattern_detection_type pattern_category pattern_severity pattern_title pattern_search
  
  return 0
}

# List all available patterns
# Usage: list_patterns "dist/patterns/"
list_patterns() {
  local patterns_dir="$1"
  
  if [ ! -d "$patterns_dir" ]; then
    echo "ERROR: Patterns directory not found: $patterns_dir" >&2
    return 1
  fi
  
  find "$patterns_dir" -name "*.json" -type f | sort
}

# Check if pattern is enabled
# Usage: is_pattern_enabled "path/to/pattern.json"
is_pattern_enabled() {
  local pattern_file="$1"
  local enabled=$(grep '"enabled"' "$pattern_file" | head -1 | sed 's/.*"enabled"[[:space:]]*:[[:space:]]*\([^,]*\).*/\1/' | tr -d ' ')
  
  if [ "$enabled" = "true" ]; then
    return 0
  else
    return 1
  fi
}

# Get pattern metadata as key=value pairs
# Usage: get_pattern_metadata "path/to/pattern.json"
get_pattern_metadata() {
  local pattern_file="$1"
  local detection_type=$(grep '"detection_type"' "$pattern_file" | head -1 | sed 's/.*"detection_type"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')

  # Default to "direct" if not specified
  if [ -z "$detection_type" ]; then
    detection_type="direct"
  fi

  echo "id=$(grep '"id"' "$pattern_file" | head -1 | sed 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
  echo "enabled=$(grep '"enabled"' "$pattern_file" | head -1 | sed 's/.*"enabled"[[:space:]]*:[[:space:]]*\([^,]*\).*/\1/' | tr -d ' ')"
  echo "detection_type=$detection_type"
  echo "category=$(grep '"category"' "$pattern_file" | head -1 | sed 's/.*"category"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
  echo "severity=$(grep '"severity"' "$pattern_file" | head -1 | sed 's/.*"severity"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
  echo "title=$(grep '"title"' "$pattern_file" | head -1 | sed 's/.*"title"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
}

# Example usage (commented out):
# load_pattern "dist/patterns/unsanitized-superglobal-isset-bypass.json"
# echo "Pattern ID: $pattern_id"
# echo "Enabled: $pattern_enabled"
# echo "Severity: $pattern_severity"

