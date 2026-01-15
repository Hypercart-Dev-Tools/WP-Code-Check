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

  # Try new format first (detection.type), then fall back to old format (detection_type at root)
  pattern_detection_type=$(grep -A2 '"detection"' "$pattern_file" | grep '"type"' | head -1 | sed 's/.*"type"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
  if [ -z "$pattern_detection_type" ]; then
    pattern_detection_type=$(grep '"detection_type"' "$pattern_file" | head -1 | sed 's/.*"detection_type"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
  fi

  pattern_category=$(grep '"category"' "$pattern_file" | head -1 | sed 's/.*"category"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
  pattern_severity=$(grep '"severity"' "$pattern_file" | head -1 | sed 's/.*"severity"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
  pattern_title=$(grep '"title"' "$pattern_file" | head -1 | sed 's/.*"title"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')

  # Extract search_pattern using Python for reliable JSON parsing
  # Supports both single search_pattern and patterns array
  if command -v python3 &> /dev/null; then
    pattern_search=$(python3 <<EOFPYTHON 2>/dev/null
import json
import sys
try:
    with open('$pattern_file', 'r') as f:
        data = json.load(f)
        detection = data.get('detection', {})

        # Check for single search_pattern first (backward compatibility)
        if 'search_pattern' in detection:
            print(detection['search_pattern'])
        # Then check for patterns array (new format for multi-pattern rules)
        elif 'patterns' in detection and isinstance(detection['patterns'], list):
            # Combine all patterns with OR (|)
            patterns = [p.get('pattern', '') for p in detection['patterns'] if 'pattern' in p]
            if patterns:
                # Join patterns with | for grep -E
                print('|'.join(patterns))
        else:
            sys.stderr.write('No search_pattern or patterns found\\n')
            sys.exit(1)
except Exception as e:
    sys.stderr.write(str(e) + '\\n')
    sys.exit(1)
EOFPYTHON
)
  elif command -v python &> /dev/null; then
    pattern_search=$(python <<EOFPYTHON 2>/dev/null
import json
import sys
try:
    with open('$pattern_file', 'r') as f:
        data = json.load(f)
        detection = data.get('detection', {})

        if 'search_pattern' in detection:
            print detection['search_pattern']
        elif 'patterns' in detection and isinstance(detection['patterns'], list):
            patterns = [p.get('pattern', '') for p in detection['patterns'] if 'pattern' in p]
            if patterns:
                print '|'.join(patterns)
        else:
            print >> sys.stderr, 'No search_pattern or patterns found'
            sys.exit(1)
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

  # Extract file_patterns array from JSON (for JavaScript/TypeScript support)
  # Use Python for reliable JSON array parsing
  if command -v python3 &> /dev/null; then
    pattern_file_patterns=$(python3 <<EOFPYTHON 2>/dev/null
import json
try:
    with open('$pattern_file', 'r') as f:
        data = json.load(f)
        file_patterns = data.get('detection', {}).get('file_patterns', [])
        if file_patterns:
            print(' '.join(file_patterns))
        else:
            print('*.php')  # Default to PHP for backward compatibility
except Exception:
    print('*.php')  # Fallback to PHP on error
EOFPYTHON
)
  else
    # Fallback: default to PHP if Python not available
    pattern_file_patterns="*.php"
  fi

  # Extract validator_script path for scripted detection type
  if [ "$pattern_detection_type" = "scripted" ]; then
    if command -v python3 &> /dev/null; then
      pattern_validator_script=$(python3 <<EOFPYTHON 2>/dev/null
import json
try:
    with open('$pattern_file', 'r') as f:
        data = json.load(f)
        validator = data.get('detection', {}).get('validator_script', '')
        print(validator)
except Exception:
    print('')
EOFPYTHON
)
    else
      # Fallback to grep/sed
      pattern_validator_script=$(grep '"validator_script"' "$pattern_file" | head -1 | cut -d'"' -f4)
    fi
  else
    pattern_validator_script=""
  fi

  # Export for use in calling script
  export pattern_id pattern_enabled pattern_detection_type pattern_category pattern_severity pattern_title pattern_search pattern_file_patterns pattern_validator_script

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

