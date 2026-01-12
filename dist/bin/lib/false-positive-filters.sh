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
# GUARD DETECTION (Phase 2)
# ============================================================

# Detect security guards (nonce checks, capability checks) near a line
#
# This function scans backward from a given line to detect WordPress
# security guards that protect superglobal access:
# - Nonce verification: wp_verify_nonce, check_ajax_referer, check_admin_referer
# - Capability checks: current_user_can, user_can
#
# Returns: Space-separated list of detected guards (empty if none)
# Usage: guards=$(detect_guards "$file" "$line_number" "$scan_lines")
detect_guards() {
  local file="$1"
  local line_num="$2"
  local scan_lines="${3:-20}"  # Default: scan 20 lines backward

  local guards=""

  # Calculate scan range
  local start_line=$((line_num - scan_lines))
  [ "$start_line" -lt 1 ] && start_line=1

  # Get context
  local context
  context=$(sed -n "${start_line},${line_num}p" "$file" 2>/dev/null || echo "")

  # Detect nonce checks
  if echo "$context" | grep -qE "wp_verify_nonce[[:space:]]*\\("; then
    guards="${guards}wp_verify_nonce "
  fi

  if echo "$context" | grep -qE "check_ajax_referer[[:space:]]*\\("; then
    guards="${guards}check_ajax_referer "
  fi

  if echo "$context" | grep -qE "check_admin_referer[[:space:]]*\\("; then
    guards="${guards}check_admin_referer "
  fi

  # Detect capability checks
  if echo "$context" | grep -qE "current_user_can[[:space:]]*\\("; then
    guards="${guards}current_user_can "
  fi

  if echo "$context" | grep -qE "user_can[[:space:]]*\\("; then
    guards="${guards}user_can "
  fi

  # Trim trailing space
  guards=$(echo "$guards" | sed 's/[[:space:]]*$//')

  echo "$guards"
}

# ============================================================
# SANITIZER DETECTION (Phase 2)
# ============================================================

# Detect sanitizers wrapping superglobal access
#
# This function checks if a code line contains WordPress sanitization
# functions wrapping superglobal reads ($_GET, $_POST, $_REQUEST, $_COOKIE).
#
# Common sanitizers detected:
# - sanitize_text_field, sanitize_email, sanitize_key, sanitize_url
# - esc_url_raw, esc_url, esc_html, esc_attr
# - absint, intval, floatval
# - wp_unslash, stripslashes_deep
# - wc_clean (WooCommerce)
#
# Returns: Space-separated list of detected sanitizers (empty if none)
# Usage: sanitizers=$(detect_sanitizers "$code_line")
detect_sanitizers() {
  local code="$1"
  local sanitizers=""

  # Check if code contains superglobal access
  if ! echo "$code" | grep -qE '\$_(GET|POST|REQUEST|COOKIE)\['; then
    # No superglobal access, return empty
    echo ""
    return
  fi

  # Detect sanitize_* functions
  if echo "$code" | grep -qE "sanitize_text_field[[:space:]]*\\([^)]*\\\$_(GET|POST|REQUEST|COOKIE)\\["; then
    sanitizers="${sanitizers}sanitize_text_field "
  fi

  if echo "$code" | grep -qE "sanitize_email[[:space:]]*\\([^)]*\\\$_(GET|POST|REQUEST|COOKIE)\\["; then
    sanitizers="${sanitizers}sanitize_email "
  fi

  if echo "$code" | grep -qE "sanitize_key[[:space:]]*\\([^)]*\\\$_(GET|POST|REQUEST|COOKIE)\\["; then
    sanitizers="${sanitizers}sanitize_key "
  fi

  if echo "$code" | grep -qE "sanitize_url[[:space:]]*\\([^)]*\\\$_(GET|POST|REQUEST|COOKIE)\\["; then
    sanitizers="${sanitizers}sanitize_url "
  fi

  # Detect esc_* functions
  if echo "$code" | grep -qE "esc_url_raw[[:space:]]*\\([^)]*\\\$_(GET|POST|REQUEST|COOKIE)\\["; then
    sanitizers="${sanitizers}esc_url_raw "
  fi

  if echo "$code" | grep -qE "esc_url[[:space:]]*\\([^)]*\\\$_(GET|POST|REQUEST|COOKIE)\\["; then
    sanitizers="${sanitizers}esc_url "
  fi

  if echo "$code" | grep -qE "esc_html[[:space:]]*\\([^)]*\\\$_(GET|POST|REQUEST|COOKIE)\\["; then
    sanitizers="${sanitizers}esc_html "
  fi

  if echo "$code" | grep -qE "esc_attr[[:space:]]*\\([^)]*\\\$_(GET|POST|REQUEST|COOKIE)\\["; then
    sanitizers="${sanitizers}esc_attr "
  fi

  # Detect type casters
  if echo "$code" | grep -qE "absint[[:space:]]*\\([^)]*\\\$_(GET|POST|REQUEST|COOKIE)\\["; then
    sanitizers="${sanitizers}absint "
  fi

  if echo "$code" | grep -qE "intval[[:space:]]*\\([^)]*\\\$_(GET|POST|REQUEST|COOKIE)\\["; then
    sanitizers="${sanitizers}intval "
  fi

  if echo "$code" | grep -qE "floatval[[:space:]]*\\([^)]*\\\$_(GET|POST|REQUEST|COOKIE)\\["; then
    sanitizers="${sanitizers}floatval "
  fi

  # Detect wp_unslash and stripslashes
  if echo "$code" | grep -qE "wp_unslash[[:space:]]*\\([^)]*\\\$_(GET|POST|REQUEST|COOKIE)\\["; then
    sanitizers="${sanitizers}wp_unslash "
  fi

  if echo "$code" | grep -qE "stripslashes_deep[[:space:]]*\\([^)]*\\\$_(GET|POST|REQUEST|COOKIE)\\["; then
    sanitizers="${sanitizers}stripslashes_deep "
  fi

  # Detect WooCommerce sanitizer
  if echo "$code" | grep -qE "wc_clean[[:space:]]*\\([^)]*\\\$_(GET|POST|REQUEST|COOKIE)\\["; then
    sanitizers="${sanitizers}wc_clean "
  fi

  # Trim trailing space
  sanitizers=$(echo "$sanitizers" | sed 's/[[:space:]]*$//')

  echo "$sanitizers"
}

# ============================================================
# SQL SAFETY DETECTION (Phase 2)
# ============================================================

# Detect if SQL query is a safe literal vs potentially tainted
#
# This function analyzes SQL code to determine if it's:
# 1. A literal string with only safe identifiers ($wpdb->prefix, $wpdb->options, etc.)
# 2. Concatenated with user input (superglobals, variables)
#
# Safe patterns:
# - "SELECT * FROM {$wpdb->posts} WHERE post_type = 'page'"
# - "DELETE FROM {$wpdb->options} WHERE option_name = 'my_option'"
#
# Unsafe patterns:
# - "SELECT * FROM {$wpdb->posts} WHERE ID = " . $_GET['id']
# - "SELECT * FROM {$wpdb->posts} WHERE title LIKE '%" . $search . "%'"
#
# Returns: "safe" or "unsafe"
# Usage: safety=$(detect_sql_safety "$code_line")
detect_sql_safety() {
  local code="$1"

  # Check for superglobal concatenation (definitely unsafe)
  if echo "$code" | grep -qE '\$_(GET|POST|REQUEST|COOKIE)\['; then
    echo "unsafe"
    return
  fi

  # Check for string concatenation with variables (potentially unsafe)
  # Pattern: . $var or . "$var" or . '$var'
  if echo "$code" | grep -qE '\.[[:space:]]*\$[a-zA-Z_]'; then
    # Check if it's ONLY concatenating safe wpdb identifiers
    # Safe: . $wpdb->prefix or . $wpdb->posts or {$wpdb->options}
    if echo "$code" | grep -qE '\.[[:space:]]*\$wpdb->(prefix|posts|postmeta|users|usermeta|options|terms|term_taxonomy|term_relationships|comments|commentmeta|links)'; then
      # Still check if there are OTHER variables being concatenated
      # Remove wpdb identifiers and check if any $ remains
      local code_no_wpdb
      code_no_wpdb=$(echo "$code" | sed -E 's/\$wpdb->(prefix|posts|postmeta|users|usermeta|options|terms|term_taxonomy|term_relationships|comments|commentmeta|links)//g')

      if echo "$code_no_wpdb" | grep -qE '\.[[:space:]]*\$[a-zA-Z_]'; then
        # Other variables found - unsafe
        echo "unsafe"
        return
      fi
    else
      # Concatenating non-wpdb variables - unsafe
      echo "unsafe"
      return
    fi
  fi

  # Check for variable interpolation in double-quoted strings
  # Safe: "{$wpdb->posts}"
  # Unsafe: "$user_input" or "${search_term}"
  if echo "$code" | grep -qE '"[^"]*\$[a-zA-Z_]'; then
    # Check if it's ONLY wpdb identifiers
    local interpolated_vars
    interpolated_vars=$(echo "$code" | grep -oE '\$[a-zA-Z_][a-zA-Z0-9_]*(->[a-zA-Z_][a-zA-Z0-9_]*)?' | grep -v '\$wpdb->' || true)

    if [ -n "$interpolated_vars" ]; then
      # Non-wpdb variables interpolated - unsafe
      echo "unsafe"
      return
    fi
  fi

  # If we got here, it's likely a safe literal query
  echo "safe"
}

# ============================================================
# LIBRARY METADATA
# ============================================================

# Export library version for debugging
FALSE_POSITIVE_FILTERS_VERSION="1.2.0"

