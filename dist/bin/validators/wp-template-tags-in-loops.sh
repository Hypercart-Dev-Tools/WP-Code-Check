#!/bin/bash
# Validator: WordPress Template Tags in Loops (N+1 Detection)
# 
# This script validates whether template tag calls inside loops are N+1 issues.
# 
# Exit codes:
#   0 = Confirmed N+1 issue (template tag with parameter in loop)
#   1 = False positive (template tag without parameter, or setup_postdata used)
#   2 = Needs manual review

FILE="$1"
LINE_NUMBER="$2"

# Validate inputs
if [ -z "$FILE" ] || [ -z "$LINE_NUMBER" ]; then
  echo "Usage: $0 <file> <line_number>" >&2
  exit 2
fi

if [ ! -f "$FILE" ]; then
  echo "File not found: $FILE" >&2
  exit 2
fi

# Extract context: 20 lines after the loop start
START_LINE=$LINE_NUMBER
END_LINE=$((LINE_NUMBER + 20))
CONTEXT=$(sed -n "${START_LINE},${END_LINE}p" "$FILE" 2>/dev/null)

if [ -z "$CONTEXT" ]; then
  exit 2
fi

# Template tags to detect (with parameters = N+1 issue)
TEMPLATE_TAGS=(
  "get_the_title"
  "get_the_content"
  "get_the_excerpt"
  "get_permalink"
  "get_the_author"
  "get_the_date"
  "get_the_time"
  "get_the_modified_date"
  "get_the_category"
  "get_the_tags"
  "get_post_thumbnail_id"
  "get_the_post_thumbnail"
  "get_the_post_thumbnail_url"
)

# Check if setup_postdata is used (FALSE POSITIVE - correct usage)
if echo "$CONTEXT" | grep -qE "setup_postdata[[:space:]]*\("; then
  exit 1  # False positive - proper post setup
fi

# Check if any template tag is called WITH a parameter (N+1 issue)
for tag in "${TEMPLATE_TAGS[@]}"; do
  # Match: get_the_title($var) or get_the_title( $var ) or get_the_title($obj->id)
  # Don't match: get_the_title() with no parameters
  if echo "$CONTEXT" | grep -qE "${tag}[[:space:]]*\([[:space:]]*\\\$[a-zA-Z_]"; then
    exit 0  # Confirmed N+1 issue
  fi
done

# Check for get_post() calls in loop (also N+1)
if echo "$CONTEXT" | grep -qE "get_post[[:space:]]*\([[:space:]]*\\\$"; then
  exit 0  # Confirmed N+1 issue
fi

# No template tags with parameters found
exit 1  # False positive

