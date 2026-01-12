#!/usr/bin/env bash
#
# False Positive Filters Library
# Version: 1.0.0
#
# Shared library for detecting and filtering false positive patterns
# in WordPress code scanning.
#
# This library provides heuristic functions to identify code patterns
# that should not be flagged as violations (comments, configuration, etc.)
#
# Usage:
#   source "path/to/false-positive-filters.sh"
#   if is_line_in_comment "$file" "$line_num"; then
#     # Skip this finding
#   fi

# ============================================================
# COMMENT DETECTION
# ============================================================

# Check if a line is inside a comment or docblock
#
# This function uses multiple heuristics to detect if a line is part of
# a comment rather than executable code:
# 1. Line starts with comment markers (after whitespace)
# 2. Line is inside a multi-line comment block (/* ... */)
# 3. Inline comments on the same line
#
# Known limitations:
# - May be fooled by comment markers inside string literals
# - Backscan window is limited to 100 lines
# - Does not parse PHP syntax trees (intentionally lightweight)
#
# Returns: 0 (true) if line is in comment, 1 (false) otherwise
# Usage: is_line_in_comment "$file" "$line_number"
is_line_in_comment() {
  local file="$1"
  local line_num="$2"

  # Get the actual line content
  local line_content
  line_content=$(sed -n "${line_num}p" "$file" 2>/dev/null || echo "")

  # Check if line starts with comment markers (after whitespace)
  # Matches: // comment, /* comment, * comment (docblock line), */
  if echo "$line_content" | grep -qE "^[[:space:]]*(//|/\\*|\\*[^/]|\\*/|^\\*)"; then
    return 0  # true - is in comment
  fi

  # Check for inline block comment: code(); /* comment */ more_code();
  # If the line contains both /* and */ it's likely an inline comment
  # We still check if the match is INSIDE the comment portion
  if echo "$line_content" | grep -qE "/\\*.*\\*/"; then
    # Extract the position of /* and */ to see if our match is between them
    # This is a heuristic - we'll be conservative and mark as comment
    # TODO: More sophisticated inline comment detection
    return 0  # true - likely inline comment
  fi

  # Check if line is inside a multi-line comment block
  # Look backward to find /* without matching */
  # Increased from 50 to 100 lines to catch larger docblocks
  local check_start=$((line_num - 100))
  [ "$check_start" -lt 1 ] && check_start=1

  # Extract lines from check_start to current line
  local context
  context=$(sed -n "${check_start},${line_num}p" "$file" 2>/dev/null || echo "")

  # IMPROVEMENT: Filter out string literals before counting
  # Remove single-quoted strings: 'anything'
  # Remove double-quoted strings: "anything"
  # This prevents echo "/* not a comment */" from being counted
  local context_no_strings
  context_no_strings=$(echo "$context" | sed -E "s/'[^']*'//g" | sed -E 's/"[^"]*"//g')

  # Count /* and */ to determine if we're inside a block comment
  local open_count
  local close_count
  open_count=$(echo "$context_no_strings" | grep -c "/\\*" 2>/dev/null || echo "0")
  close_count=$(echo "$context_no_strings" | grep -c "\\*/" 2>/dev/null || echo "0")
  
  # Remove any whitespace/newlines
  open_count=$(echo "$open_count" | tr -d '[:space:]')
  close_count=$(echo "$close_count" | tr -d '[:space:]')

  # If more /* than */, we're inside a comment block
  if [ "$open_count" -gt "$close_count" ]; then
    return 0  # true - is in comment block
  fi

  return 1  # false - not in comment
}

# ============================================================
# HTML & REST CONFIGURATION DETECTION
# ============================================================

# Check if code is HTML form declaration or REST route config
#
# This function detects patterns that are configuration rather than
# executable code that accesses superglobals or makes HTTP requests.
#
# Patterns detected:
# 1. HTML form method attributes: <form method="POST">
# 2. REST route method configs: 'methods' => 'POST'
#
# Returns: 0 (true) if it's a false positive pattern, 1 (false) otherwise
# Usage: is_html_or_rest_config "$code_line"
is_html_or_rest_config() {
  local code="$1"

  # Check for HTML form method attribute
  # Anchored pattern: <form ... method="POST"> or method='POST'
  # Case-insensitive to catch POST, post, Post, etc.
  if echo "$code" | grep -qiE "<form[^>]*\\bmethod\\s*=\\s*['\"]POST['\"]"; then
    return 0  # true - is HTML form
  fi

  # Also check for method attribute without <form on same line
  # (form tag might be on previous line)
  if echo "$code" | grep -qiE "^[[:space:]]*method\\s*=\\s*['\"]POST['\"]"; then
    return 0  # true - is HTML form attribute
  fi

  # Check for REST route methods config
  # Anchored pattern: 'methods' => 'POST' or "methods" => "POST"
  # Must have quotes around 'methods' key to avoid matching $methods variables
  if echo "$code" | grep -qiE "['\"]methods['\"][[:space:]]*=>.*POST"; then
    return 0  # true - is REST config
  fi

  return 1  # false - not a false positive pattern
}

# ============================================================
# LIBRARY METADATA
# ============================================================

# Export library version for debugging
FALSE_POSITIVE_FILTERS_VERSION="1.0.0"

