#!/usr/bin/env bash
#
# Context Pattern Validator
# Checks if a specific pattern exists in the context window around a match
#
# Usage: context-pattern-check.sh <file> <line_number> <pattern> [context_lines] [direction]
#
# Exit codes:
#   0 = Pattern FOUND in context (issue confirmed)
#   1 = Pattern NOT found in context (false positive)
#   2 = Error (invalid input)
#
# Parameters:
#   file          - File path
#   line_number   - Line number of the match
#   pattern       - Extended regex pattern to search for
#   context_lines - Number of lines to check (default: 10)
#   direction     - "after", "before", or "both" (default: "after")
#
# Example:
#   context-pattern-check.sh file.js 42 "\.ajax|fetch\(" 5 after
#   Checks if .ajax or fetch( appears within 5 lines AFTER line 42

FILE="$1"
LINE_NUMBER="$2"
PATTERN="$3"
CONTEXT_LINES="${4:-10}"
DIRECTION="${5:-after}"

# Validate inputs
if [ -z "$FILE" ] || [ -z "$LINE_NUMBER" ] || [ -z "$PATTERN" ]; then
    echo "Error: Missing required arguments" >&2
    echo "Usage: $0 <file> <line_number> <pattern> [context_lines] [direction]" >&2
    exit 2
fi

if [ ! -f "$FILE" ]; then
    echo "Error: File not found: $FILE" >&2
    exit 2
fi

if ! [[ "$LINE_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "Error: Invalid line number: $LINE_NUMBER" >&2
    exit 2
fi

# Calculate context window based on direction
case "$DIRECTION" in
    after)
        start_line=$LINE_NUMBER
        end_line=$((LINE_NUMBER + CONTEXT_LINES))
        ;;
    before)
        start_line=$((LINE_NUMBER - CONTEXT_LINES))
        [ "$start_line" -lt 1 ] && start_line=1
        end_line=$LINE_NUMBER
        ;;
    both)
        start_line=$((LINE_NUMBER - CONTEXT_LINES))
        [ "$start_line" -lt 1 ] && start_line=1
        end_line=$((LINE_NUMBER + CONTEXT_LINES))
        ;;
    *)
        echo "Error: Invalid direction: $DIRECTION (must be 'after', 'before', or 'both')" >&2
        exit 2
        ;;
esac

# Extract context
context=$(sed -n "${start_line},${end_line}p" "$FILE" 2>/dev/null || true)

if [ -z "$context" ]; then
    echo "Error: Could not extract context from file" >&2
    exit 2
fi

# Check if pattern exists in context (case-insensitive)
if echo "$context" | grep -qiE "$PATTERN"; then
    # Pattern FOUND - this is an issue
    exit 0
else
    # Pattern NOT found - this is a false positive
    exit 1
fi

