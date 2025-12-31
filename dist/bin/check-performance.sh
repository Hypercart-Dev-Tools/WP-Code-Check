#!/usr/bin/env bash
#
# WP Code Check by Hypercart - Performance Analysis Script
# Version: 1.0.58
#
# Fast, zero-dependency WordPress performance analyzer
# Catches critical issues before they crash your site
#
# Usage:
#   ./bin/check-performance.sh [options]
#
# Options:
#   --project <name>         Load configuration from TEMPLATES/<name>.txt
#   --paths "dir1 dir2"      Paths to scan (default: current directory)
#   --format text|json       Output format (default: text)
#   --strict                 Fail on warnings (N+1 patterns)
#   --verbose                Show all matches, not just first occurrence
#   --no-log                 Disable logging to file
#   --no-context             Disable context lines around findings
#   --context-lines N        Number of context lines to show (default: 3)
#   --generate-baseline      Generate .neochrome-baseline from current findings
#   --baseline <path>        Use custom baseline file path (default: .neochrome-baseline)
#   --ignore-baseline        Ignore baseline file even if present
#   --help                   Show this help message

# Note: We intentionally do NOT use 'set -e' here because:
# 1. ((var++)) returns exit code 1 when var is 0, which would cause immediate exit
# 2. grep returning no matches (exit 1) is expected behavior we handle explicitly
# 3. We manage our own error tracking with ERRORS/WARNINGS counters

# Directories and shared libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=dist/bin/lib/colors.sh
source "$LIB_DIR/colors.sh"
# shellcheck source=dist/bin/lib/common-helpers.sh
source "$LIB_DIR/common-helpers.sh"

# Defaults
PATHS="."
STRICT=false
VERBOSE=false
ENABLE_LOGGING=true
OUTPUT_FORMAT="text"  # text or json
CONTEXT_LINES=3       # Number of lines to show before/after findings (0 to disable)
# Note: 'tests' exclusion is dynamically removed when --paths targets a tests directory
EXCLUDE_DIRS="vendor node_modules .git tests"

# Baseline configuration
BASELINE_FILE=".neochrome-baseline"
GENERATE_BASELINE=false
IGNORE_BASELINE=false
BASELINE_ENABLED=false
BASELINED=0        # Total suppressed findings (covered by baseline)
STALE_ENTRIES=0    # Baseline entries with fewer matches than allowed

# Baseline storage (simple parallel arrays for broad Bash compatibility)
BASELINE_KEYS=()       # rule|file
BASELINE_ALLOWED=()    # allowed count per key
BASELINE_FOUND=()      # runtime count per key

# New baseline being generated (--generate-baseline)
NEW_BASELINE_KEYS=()
NEW_BASELINE_COUNTS=()

# JSON findings collection (initialized as empty)
declare -a JSON_FINDINGS=()
declare -a JSON_CHECKS=()

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --project)
      PROJECT_NAME="$2"
      TEMPLATE_FILE="$REPO_ROOT/TEMPLATES/${PROJECT_NAME}.txt"

      if [ ! -f "$TEMPLATE_FILE" ]; then
        echo "Error: Template '$PROJECT_NAME' not found at $TEMPLATE_FILE"
        echo "Available templates:"
        for template in "$REPO_ROOT/TEMPLATES"/*.txt; do
          if [ -f "$template" ] && [[ "$(basename "$template")" != _* ]]; then
            echo "  - $(basename "$template" .txt)"
          fi
        done
        exit 1
      fi

      # Load template variables
      # shellcheck disable=SC1090
      source "$TEMPLATE_FILE"

      # Apply template variables (can be overridden by subsequent flags)
      if [ -n "${PROJECT_PATH:-}" ]; then
        PATHS="$PROJECT_PATH"
      fi
      if [ -n "${FORMAT:-}" ]; then
        OUTPUT_FORMAT="$FORMAT"
      fi
      if [ -n "${BASELINE:-}" ]; then
        BASELINE_FILE="$BASELINE"
      fi

      shift 2
      ;;
    --paths)
      PATHS="$2"
      shift 2
      ;;
    --format)
      OUTPUT_FORMAT="$2"
      if [[ "$OUTPUT_FORMAT" != "text" && "$OUTPUT_FORMAT" != "json" ]]; then
        echo "Error: --format must be 'text' or 'json'"
        exit 1
      fi
      shift 2
      ;;
    --strict)
      STRICT=true
      shift
      ;;
    --verbose)
      VERBOSE=true
      shift
      ;;
    --no-log)
      ENABLE_LOGGING=false
      shift
      ;;
    --generate-baseline)
      GENERATE_BASELINE=true
      shift
      ;;
    --baseline)
      BASELINE_FILE="$2"
      shift 2
      ;;
    --ignore-baseline)
      IGNORE_BASELINE=true
      shift
      ;;
    --no-context)
      CONTEXT_LINES=0
      shift
      ;;
    --context-lines)
      CONTEXT_LINES="$2"
      shift 2
      ;;
    --help)
      head -30 "$0" | tail -25
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# If scanning a tests directory, remove 'tests' from exclusions
# Use portable method (no \b word boundary which is GNU-specific)
if echo "$PATHS" | grep -q "tests"; then
  EXCLUDE_DIRS="vendor node_modules .git"
fi

# Build exclude arguments
EXCLUDE_ARGS=""
for dir in $EXCLUDE_DIRS; do
  EXCLUDE_ARGS="$EXCLUDE_ARGS --exclude-dir=$dir"
done

# ============================================================================
# Helper Functions (must be defined before logging setup)
# ============================================================================

# Escape string for JSON (handles quotes, backslashes, newlines)
json_escape() {
  local str="$1"
  str="${str//\\/\\\\}"      # Escape backslashes first
  str="${str//\"/\\\"}"      # Escape double quotes
  str="${str//$'\n'/\\n}"    # Escape newlines
  str="${str//$'\r'/\\r}"    # Escape carriage returns
  str="${str//$'\t'/\\t}"    # Escape tabs
  printf '%s' "$str"
}

# URL-encode a string for file:// links
url_encode() {
  local str="$1"
  # Use jq's @uri filter for robust RFC 3986 encoding
  str=$(printf '%s' "$str" | jq -sRr @uri)
  printf '%s' "$str"
}

# Count PHP files in scan path
count_analyzed_files() {
  local scan_path="$1"
  find "$scan_path" -name "*.php" -type f 2>/dev/null | wc -l | tr -d '[:space:]'
}

# Count total lines of code in PHP files
count_lines_of_code() {
  local scan_path="$1"
  local total_lines=0
  
  # Use find + wc for efficient line counting
  if command -v find &> /dev/null && command -v wc &> /dev/null; then
    # Count lines in all PHP files, sum the results
    total_lines=$(find "$scan_path" -name "*.php" -type f -exec wc -l {} + 2>/dev/null | tail -1 | awk '{print $1}' 2>/dev/null || echo "0")
  fi
  
  # Ensure we return a number
  if ! [[ "$total_lines" =~ ^[0-9]+$ ]]; then
    total_lines=0
  fi
  
  echo "$total_lines"
}

# Get local timestamp for user-friendly display
get_local_timestamp() {
  date +"%Y-%m-%d %H:%M:%S %Z"
}

# Detect WordPress plugin or theme information
# Returns JSON object with project metadata including file/LOC counts
detect_project_info() {
  local scan_path="$1"
  local project_type="unknown"
  local project_name="Unknown"
  local project_version=""
  local project_description=""
  local project_author=""
  local main_file=""

  # Convert relative path to absolute for consistent detection
  if [[ "$scan_path" != /* ]]; then
    scan_path="$(cd "$scan_path" 2>/dev/null && pwd)" || scan_path="$scan_path"
  fi

  # Look for plugin main file (*.php with Plugin Name header)
  # Check current directory and one level up (in case scanning src/ or includes/)
  for search_dir in "$scan_path" "$(dirname "$scan_path")"; do
    if [ -d "$search_dir" ]; then
      # Find PHP files with "Plugin Name:" header
      while IFS= read -r php_file; do
        if [ -f "$php_file" ] && head -30 "$php_file" 2>/dev/null | grep -qi "Plugin Name:"; then
          project_type="plugin"
          main_file="$php_file"

          # Extract plugin metadata from headers
          project_name=$(grep -i "Plugin Name:" "$php_file" | head -1 | sed 's/.*Plugin Name:[[:space:]]*//' | sed 's/[[:space:]]*$//' | tr -d '\r')
          project_version=$(grep -i "Version:" "$php_file" | head -1 | sed 's/.*Version:[[:space:]]*//' | sed 's/[[:space:]]*$//' | tr -d '\r')
          project_description=$(grep -i "Description:" "$php_file" | head -1 | sed 's/.*Description:[[:space:]]*//' | sed 's/[[:space:]]*$//' | tr -d '\r')
          project_author=$(grep -i "Author:" "$php_file" | head -1 | sed 's/.*Author:[[:space:]]*//' | sed 's/[[:space:]]*$//' | tr -d '\r')
          break 2
        fi
      done < <(find "$search_dir" -maxdepth 1 -name "*.php" -type f 2>/dev/null)
    fi
  done

  # Look for theme style.css
  if [ "$project_type" = "unknown" ]; then
    for search_dir in "$scan_path" "$(dirname "$scan_path")"; do
      if [ -f "$search_dir/style.css" ]; then
        if head -30 "$search_dir/style.css" 2>/dev/null | grep -qi "Theme Name:"; then
          project_type="theme"
          main_file="$search_dir/style.css"

          # Extract theme metadata from style.css
          project_name=$(grep -i "Theme Name:" "$main_file" | head -1 | sed 's/.*Theme Name:[[:space:]]*//' | sed 's/[[:space:]]*$//' | tr -d '\r')
          project_version=$(grep -i "Version:" "$main_file" | head -1 | sed 's/.*Version:[[:space:]]*//' | sed 's/[[:space:]]*$//' | tr -d '\r')
          project_description=$(grep -i "Description:" "$main_file" | head -1 | sed 's/.*Description:[[:space:]]*//' | sed 's/[[:space:]]*$//' | tr -d '\r')
          project_author=$(grep -i "Author:" "$main_file" | head -1 | sed 's/.*Author:[[:space:]]*//' | sed 's/[[:space:]]*$//' | tr -d '\r')
          break
        fi
      fi
    done
  fi

  # If still unknown, try to infer from path
  if [ "$project_type" = "unknown" ]; then
    if echo "$scan_path" | grep -q "/wp-content/plugins/"; then
      project_type="plugin"
      project_name=$(basename "$scan_path")
    elif echo "$scan_path" | grep -q "/wp-content/themes/"; then
      project_type="theme"
      project_name=$(basename "$scan_path")
    else
      # Generic project
      project_name=$(basename "$scan_path")
    fi
  fi

  # Count files and lines of code
  local files_analyzed=$(count_analyzed_files "$scan_path")
  local lines_of_code=$(count_lines_of_code "$scan_path")

  # Build JSON object (escape special characters)
  local name_escaped=$(json_escape "$project_name")
  local version_escaped=$(json_escape "$project_version")
  local description_escaped=$(json_escape "$project_description")
  local author_escaped=$(json_escape "$project_author")
  local path_escaped=$(json_escape "$scan_path")

  cat <<EOF
{
    "type": "$project_type",
    "name": "$name_escaped",
    "version": "$version_escaped",
    "description": "$description_escaped",
    "author": "$author_escaped",
    "path": "$path_escaped",
    "files_analyzed": $files_analyzed,
    "lines_of_code": $lines_of_code
  }
EOF
}

# Setup logging
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$PLUGIN_DIR/logs"
LOG_FILE=""

if [ "$ENABLE_LOGGING" = true ]; then
  # Create logs directory if it doesn't exist
  mkdir -p "$LOG_DIR"

  # Generate timestamp in UTC (YYYY-MM-DD-HHMMSS-UTC format)
  TIMESTAMP=$(timestamp_filename)

  # Use appropriate file extension based on format
  if [ "$OUTPUT_FORMAT" = "json" ]; then
    LOG_FILE="$LOG_DIR/$TIMESTAMP.json"
    # For JSON mode, no header - just redirect output to log file
    exec > >(tee "$LOG_FILE")
    exec 2>&1
  else
    LOG_FILE="$LOG_DIR/$TIMESTAMP.log"

    # Write log header with metadata (text mode only)
    {
      echo "========================================================================"
      echo "WP Code Check by Hypercart - Performance Analysis Log"
      echo "========================================================================"
      echo ""

      # Detect and display project info
      # Use parameter expansion to get first path (before first space, if multiple paths)
      # But preserve the full path even if it contains spaces
      FIRST_PATH_LOG="$PATHS"
      PROJECT_INFO_LOG=$(detect_project_info "$FIRST_PATH_LOG")
      PROJECT_TYPE_LOG=$(echo "$PROJECT_INFO_LOG" | grep -o '"type": "[^"]*"' | cut -d'"' -f4)
      PROJECT_NAME_LOG=$(echo "$PROJECT_INFO_LOG" | grep -o '"name": "[^"]*"' | cut -d'"' -f4)
      PROJECT_VERSION_LOG=$(echo "$PROJECT_INFO_LOG" | grep -o '"version": "[^"]*"' | cut -d'"' -f4)
      PROJECT_AUTHOR_LOG=$(echo "$PROJECT_INFO_LOG" | grep -o '"author": "[^"]*"' | cut -d'"' -f4)
      PROJECT_FILES_LOG=$(echo "$PROJECT_INFO_LOG" | grep -o '"files_analyzed": [0-9]*' | cut -d':' -f2 | tr -d '[:space:]')
      PROJECT_LOC_LOG=$(echo "$PROJECT_INFO_LOG" | grep -o '"lines_of_code": [0-9]*' | cut -d':' -f2 | tr -d '[:space:]')

      if [ "$PROJECT_NAME_LOG" != "Unknown" ] && [ -n "$PROJECT_NAME_LOG" ]; then
        echo "PROJECT INFORMATION"
        echo "-------------------"
        echo "Name:             $PROJECT_NAME_LOG"
        if [ -n "$PROJECT_VERSION_LOG" ]; then
          echo "Version:          $PROJECT_VERSION_LOG"
        fi
        echo "Type:             $PROJECT_TYPE_LOG"
        if [ -n "$PROJECT_AUTHOR_LOG" ]; then
          echo "Author:           $PROJECT_AUTHOR_LOG"
        fi
        if [ -n "$PROJECT_FILES_LOG" ] && [ "$PROJECT_FILES_LOG" != "0" ]; then
          echo "Files Analyzed:   $PROJECT_FILES_LOG PHP files"
        fi
        if [ -n "$PROJECT_LOC_LOG" ] && [ "$PROJECT_LOC_LOG" != "0" ]; then
          echo "Lines Reviewed:   $(printf "%'d" "$PROJECT_LOC_LOG" 2>/dev/null || echo "$PROJECT_LOC_LOG") lines of code"
        fi
        echo ""
      fi

      echo "Generated (UTC):  $(date -u +"%Y-%m-%d %H:%M:%S")"
      echo "Local Time:      $(get_local_timestamp)"
        echo "Script Version:   1.0.57"
      echo "Paths Scanned:    $PATHS"
      echo "Strict Mode:      $STRICT"
      echo "Verbose Mode:     $VERBOSE"
      echo "Exclude Dirs:     $EXCLUDE_DIRS"

      # Try to get git commit hash if available
      # Only show git info if scanning within the current repository
      if command -v git &> /dev/null && git rev-parse --git-dir > /dev/null 2>&1; then
        # Get the git root directory
        GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
        # Check if the scan path is within the git repository
        # Convert scan path to absolute path for comparison
        SCAN_PATH_ABS="$PATHS"
        if [[ "$SCAN_PATH_ABS" != /* ]]; then
          SCAN_PATH_ABS="$(cd "$SCAN_PATH_ABS" 2>/dev/null && pwd)" || SCAN_PATH_ABS="$SCAN_PATH_ABS"
        fi

        # Only show git info if scan path starts with git root
        if [[ "$SCAN_PATH_ABS" == "$GIT_ROOT"* ]]; then
          GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "N/A")
          GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "N/A")
          echo "Git Commit:       $GIT_COMMIT"
          echo "Git Branch:       $GIT_BRANCH"
        fi
      fi

      echo ""
      echo "========================================================================"
      echo ""
    } > "$LOG_FILE"

    # Redirect all output to both terminal and log file
    # We'll use process substitution to tee output
    exec > >(tee -a "$LOG_FILE")
    exec 2>&1
  fi
fi

# Function to log exit (defined early so trap can use it)
log_exit() {
  local exit_code=$1
  # Only write footer for text mode logs
  if [ "$ENABLE_LOGGING" = true ] && [ -n "$LOG_FILE" ] && [ "$OUTPUT_FORMAT" = "text" ]; then
    {
      echo ""
      echo "========================================================================"
      echo "Completed (UTC): $(date -u +"%Y-%m-%d %H:%M:%S")"
      echo "Local Time:     $(get_local_timestamp)"
      echo "Exit Code:      $exit_code"
      echo "========================================================================"
    } >> "$LOG_FILE"
  fi
}

# Trap to ensure log footer is written even on unexpected exit or interrupt
if [ "$ENABLE_LOGGING" = true ]; then
  trap 'log_exit $?' EXIT
  trap 'exit 130' INT  # Ctrl+C
  trap 'exit 143' TERM # kill
fi

# ============================================================================
# JSON Output Helpers
# ============================================================================

# Add a finding to the JSON findings array
# Usage: add_json_finding "rule-id" "error|warning" "CRITICAL|HIGH|MEDIUM|LOW" "file" "line" "message" "code_snippet"
add_json_finding() {
  local rule_id="$1"
  local severity="$2"
  local impact="$3"
  local file="$4"
  local line="$5"
  local message="$6"
  local code="$7"

  # Truncate code snippet to 200 characters for display
  local truncated_code="$code"
  if [ ${#code} -gt 200 ]; then
    truncated_code="${code:0:200}..."
  fi

  # Build context array if enabled
  local context_json="[]"
  if [ "$CONTEXT_LINES" -gt 0 ] && [ -f "$file" ]; then
    local start_line=$((line - CONTEXT_LINES))
    local end_line=$((line + CONTEXT_LINES))

    # Ensure start_line is at least 1
    if [ "$start_line" -lt 1 ]; then
      start_line=1
    fi

    # Build context lines array
    local context_items=()
    local current_line=$start_line
    while [ "$current_line" -le "$end_line" ]; do
      if [ "$current_line" -ne "$line" ]; then
        local context_code=$(sed -n "${current_line}p" "$file" 2>/dev/null)
        if [ -n "$context_code" ]; then
          # Truncate context lines too
          if [ ${#context_code} -gt 200 ]; then
            context_code="${context_code:0:200}..."
          fi
          context_items+=("{\"line\":$current_line,\"code\":\"$(json_escape "$context_code")\"}")
        fi
      fi
      current_line=$((current_line + 1))
    done

    # Join context items
    if [ ${#context_items[@]} -gt 0 ]; then
      local first=true
      context_json="["
      for item in "${context_items[@]}"; do
        if [ "$first" = true ]; then
          context_json="${context_json}${item}"
          first=false
        else
          context_json="${context_json},${item}"
        fi
      done
      context_json="${context_json}]"
    fi
  fi

  local finding=$(cat <<EOF
{"id":"$(json_escape "$rule_id")","severity":"$severity","impact":"$impact","file":"$(json_escape "$file")","line":$line,"message":"$(json_escape "$message")","code":"$(json_escape "$truncated_code")","context":$context_json}
EOF
)
  JSON_FINDINGS+=("$finding")
}

# Add a check result to the JSON checks array
# Usage: add_json_check "Check Name" "CRITICAL|HIGH|MEDIUM|LOW" "passed|failed" count
add_json_check() {
  local name="$1"
  local impact="$2"
  local status="$3"
  local count="$4"

  local check=$(cat <<EOF
{"name":"$(json_escape "$name")","impact":"$impact","status":"$status","findings_count":$count}
EOF
)
  JSON_CHECKS+=("$check")
}

# Output final JSON
output_json() {
  local exit_code="$1"
  local timestamp=$(timestamp_iso8601)

  # Detect project info from first path
  # Preserve full path even if it contains spaces
  local first_path="$PATHS"
  local project_info=$(detect_project_info "$first_path")
  
  # Extract file count and LOC for summary
  local files_analyzed=$(echo "$project_info" | grep -o '"files_analyzed": [0-9]*' | cut -d':' -f2 | tr -d '[:space:]')
  local lines_of_code=$(echo "$project_info" | grep -o '"lines_of_code": [0-9]*' | cut -d':' -f2 | tr -d '[:space:]')
  
  # Default to 0 if not found
  [ -z "$files_analyzed" ] && files_analyzed=0
  [ -z "$lines_of_code" ] && lines_of_code=0

  # Build findings array
  local findings_json=""
  local first=true
  for finding in "${JSON_FINDINGS[@]}"; do
    if [ "$first" = true ]; then
      findings_json="$finding"
      first=false
    else
      findings_json="$findings_json,$finding"
    fi
  done

  # Build checks array
  local checks_json=""
  first=true
  for check in "${JSON_CHECKS[@]}"; do
    if [ "$first" = true ]; then
      checks_json="$check"
      first=false
    else
      checks_json="$checks_json,$check"
    fi
   done

    cat <<EOF
{
   "version": "1.0.57",
  "timestamp": "$timestamp",
  "project": $project_info,
  "paths_scanned": "$(json_escape "$PATHS")",
  "strict_mode": $STRICT,
  "summary": {
    "total_errors": $ERRORS,
    "total_warnings": $WARNINGS,
    "files_analyzed": $files_analyzed,
    "lines_of_code": $lines_of_code,
    "baselined": $BASELINED,
    "stale_baseline": $STALE_ENTRIES,
    "exit_code": $exit_code
  },
  "findings": [$findings_json],
  "checks": [$checks_json]
}
EOF
}

# Generate HTML report from JSON output
# Usage: generate_html_report "json_string" "output_file"
generate_html_report() {
  local json_data="$1"
  local output_file="$2"
  local template_file="$SCRIPT_DIR/templates/report-template.html"

  # Check if template exists
  if [ ! -f "$template_file" ]; then
    echo "Warning: HTML template not found at $template_file" >&2
    return 1
  fi

  # Check if jq is available
  if ! command -v jq &> /dev/null; then
    echo "Warning: jq is required for HTML report generation" >&2
    return 1
  fi

  # Extract data from JSON using jq
  local version=$(echo "$json_data" | jq -r '.version // "Unknown"')
  local timestamp=$(echo "$json_data" | jq -r '.timestamp // "Unknown"')
  local paths=$(echo "$json_data" | jq -r '.paths_scanned // "."')
  local total_errors=$(echo "$json_data" | jq -r '.summary.total_errors // 0')
  local total_warnings=$(echo "$json_data" | jq -r '.summary.total_warnings // 0')
  local baselined=$(echo "$json_data" | jq -r '.summary.baselined // 0')
  local stale_baseline=$(echo "$json_data" | jq -r '.summary.stale_baseline // 0')
  local exit_code=$(echo "$json_data" | jq -r '.summary.exit_code // 0')
  local strict_mode=$(echo "$json_data" | jq -r '.strict_mode // false')
  local findings_count=$(echo "$json_data" | jq '.findings | length')

  # Create clickable links for each scanned path
  local paths_link=""
  local first_path=true
  for path in $paths; do
    local abs_path
    if [[ "$path" = /* ]]; then
      abs_path="$path"
    else
      # Use realpath for robust absolute path conversion
      abs_path=$(realpath "$path" 2>/dev/null || echo "$path")
    fi
    local encoded_path=$(url_encode "$abs_path")

    if [ "$first_path" = false ]; then
      paths_link+=", "
    fi
    # Display the absolute path (not the original relative path like ".")
    paths_link+="<a href=\"file://$encoded_path\" style=\"color: #fff; text-decoration: underline;\" title=\"Click to open directory\">$abs_path</a>"
    first_path=false
  done

  # Extract project information
  local project_type=$(echo "$json_data" | jq -r '.project.type // "unknown"')
  local project_name=$(echo "$json_data" | jq -r '.project.name // ""')
  local project_version=$(echo "$json_data" | jq -r '.project.version // ""')
  local project_author=$(echo "$json_data" | jq -r '.project.author // ""')
  local files_analyzed=$(echo "$json_data" | jq -r '.project.files_analyzed // 0')
  local lines_of_code=$(echo "$json_data" | jq -r '.project.lines_of_code // 0')

  # Build project info HTML (matching the text output format)
  local project_info_html=""
  if [ -n "$project_name" ] && [ "$project_name" != "Unknown" ]; then
    project_info_html="<div style='font-size: 1.1em; font-weight: 600; margin-bottom: 5px;'>PROJECT INFORMATION</div>"
    project_info_html+="<div>Name: $project_name</div>"
    if [ -n "$project_version" ]; then
      project_info_html+="<div>Version: $project_version</div>"
    fi
    project_info_html+="<div>Type: $project_type</div>"
    if [ -n "$project_author" ]; then
      project_info_html+="<div>Author: $project_author</div>"
    fi
    if [ "$files_analyzed" != "0" ]; then
      project_info_html+="<div>Files Analyzed: $files_analyzed PHP files</div>"
    fi
    if [ "$lines_of_code" != "0" ]; then
      # Format with commas for readability
      local formatted_loc=$(printf "%'d" "$lines_of_code" 2>/dev/null || echo "$lines_of_code")
      project_info_html+="<div>Lines Reviewed: $formatted_loc lines of code</div>"
    fi
  fi

  # Determine status
  local status_class="pass"
  local status_message="✓ All critical checks passed!"
  if [ "$exit_code" -ne 0 ]; then
    status_class="fail"
    if [ "$total_errors" -gt 0 ]; then
      status_message="✗ Check failed with $total_errors error type(s)"
    elif [ "$strict_mode" = "true" ] && [ "$total_warnings" -gt 0 ]; then
      status_message="✗ Check failed in strict mode with $total_warnings warning type(s)"
    fi
  fi

  # Generate findings HTML with clickable file links
  local findings_html=""
  if [ "$findings_count" -gt 0 ]; then
    # Process each finding and convert relative paths to absolute
    findings_html=""
    while IFS= read -r finding_json; do
      local file_path=$(echo "$finding_json" | jq -r '.file // ""')
      local abs_file_path

      # Convert to absolute path if relative
      if [ -n "$file_path" ]; then
        if [[ "$file_path" != /* ]]; then
            # Use realpath for robust conversion
            abs_file_path=$(realpath "$file_path" 2>/dev/null || echo "$file_path")
        else
            abs_file_path="$file_path"
        fi
      fi

      # URL-encode the path for robust file links
      local encoded_file_path=$(url_encode "$abs_file_path")

      # Generate HTML for this finding, ensuring '&' is escaped first
      local finding_html=$(echo "$finding_json" | jq -r --arg abs_path "$encoded_file_path" '
        "<div class=\"finding \(.impact // "MEDIUM" | ascii_downcase)\">
          <div class=\"finding-header\">
            <div class=\"finding-title\">\(.message // .id)</div>
            <span class=\"badge \(.impact // "MEDIUM" | ascii_downcase)\">\(.impact // "MEDIUM")</span>
          </div>
          <div class=\"finding-details\">
            <div class=\"file-path\"><a href=\"file://\($abs_path)\" style=\"color: #667eea; text-decoration: none;\" title=\"Click to open file\">\(.file // "")</a>:\(.line // "")</div>
            <div class=\"code-snippet\">\(.code // "" | gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;"))</div>
          </div>
        </div>"')

      findings_html="$findings_html $finding_html"
    done < <(echo "$json_data" | jq -c '.findings[]')
  else
    findings_html="<p style='text-align: center; color: #6c757d; padding: 20px;'>No findings detected. Great job! 🎉</p>"
  fi

  # Generate checks HTML
  local checks_html=$(echo "$json_data" | jq -r '.checks[] |
    "<div class=\"finding \(if .status == "passed" then "low" else (.impact | ascii_downcase) end)\">
      <div class=\"finding-header\">
        <div class=\"finding-title\">\(.name)</div>
        <span class=\"badge \(if .status == "passed" then "low" else (.impact | ascii_downcase) end)\">\(.status | ascii_upcase)</span>
      </div>
      <div class=\"finding-details\">Findings: \(.findings_count)</div>
    </div>"' | tr '\n' ' ')

  # Read template and replace placeholders
  local html_content
  html_content=$(cat "$template_file")

  # Replace all placeholders
  html_content="${html_content//\{\{PROJECT_INFO\}\}/$project_info_html}"
  html_content="${html_content//\{\{VERSION\}\}/$version}"
  html_content="${html_content//\{\{TIMESTAMP\}\}/$timestamp}"
  html_content="${html_content//\{\{PATHS_SCANNED\}\}/$paths_link}"
  html_content="${html_content//\{\{TOTAL_ERRORS\}\}/$total_errors}"
  html_content="${html_content//\{\{TOTAL_WARNINGS\}\}/$total_warnings}"
  html_content="${html_content//\{\{BASELINED\}\}/$baselined}"
  html_content="${html_content//\{\{STALE_BASELINE\}\}/$stale_baseline}"
  html_content="${html_content//\{\{EXIT_CODE\}\}/$exit_code}"
  html_content="${html_content//\{\{STRICT_MODE\}\}/$strict_mode}"
  html_content="${html_content//\{\{STATUS_CLASS\}\}/$status_class}"
  html_content="${html_content//\{\{STATUS_MESSAGE\}\}/$status_message}"
  html_content="${html_content//\{\{FINDINGS_COUNT\}\}/$findings_count}"
  html_content="${html_content//\{\{FINDINGS_HTML\}\}/$findings_html}"
  html_content="${html_content//\{\{CHECKS_HTML\}\}/$checks_html}"

  # Write to output file
  echo "$html_content" > "$output_file"

  return 0
}

# Conditional echo - only outputs in text mode
text_echo() {
	if [ "$OUTPUT_FORMAT" = "text" ]; then
	  	echo -e "$@"
	fi
}

# Format a finding for text output with bold filename and truncated code
# Usage: format_finding "file:line:code"
format_finding() {
  local match="$1"
  local file=$(echo "$match" | cut -d: -f1)
  local lineno=$(echo "$match" | cut -d: -f2)
  local code=$(echo "$match" | cut -d: -f3-)

  # Truncate code to 200 characters
  if [ ${#code} -gt 200 ]; then
    code="${code:0:200}..."
  fi

  # Output with bold filename
  echo -e "${BOLD}${file}:${lineno}${NC}:${code}"

  # Show context lines if enabled
  if [ "$CONTEXT_LINES" -gt 0 ] && [ -f "$file" ]; then
    local start_line=$((lineno - CONTEXT_LINES))
    local end_line=$((lineno + CONTEXT_LINES))

    # Ensure start_line is at least 1
    if [ "$start_line" -lt 1 ]; then
      start_line=1
    fi

    # Extract context lines
    local current_line=$start_line
    while [ "$current_line" -le "$end_line" ]; do
      if [ "$current_line" -ne "$lineno" ]; then
        local context_code=$(sed -n "${current_line}p" "$file" 2>/dev/null)
        if [ -n "$context_code" ]; then
          # Truncate context lines too
          if [ ${#context_code} -gt 200 ]; then
            context_code="${context_code:0:200}..."
          fi
          # Indent context lines
          echo -e "  ${current_line}: ${context_code}"
        fi
      fi
      current_line=$((current_line + 1))
    done
  fi
}

# ============================================================================
# Baseline Helpers
# ============================================================================

# Normalize file paths used for baseline matching.
# This keeps baseline entries generated on one platform (e.g. macOS with
# leading "./" paths) compatible with runtime findings on another (e.g.
# Linux where grep omits the leading "./").
normalize_baseline_path() {
	local p="$1"
	case "$p" in
		./*) p="${p#./}" ;;
	esac
	printf '%s\n' "$p"
}

# Find index of a baseline key (rule|file) in BASELINE_KEYS, or -1 if not present
baseline_index() {
	local search="$1"
	local i
	for i in "${!BASELINE_KEYS[@]}"; do
		if [ "${BASELINE_KEYS[$i]}" = "$search" ]; then
			echo "$i"
			return
		fi
	done
	echo "-1"
}

# Find index of a new-baseline key (rule|file) in NEW_BASELINE_KEYS, or -1 if not present
new_baseline_index() {
	local search="$1"
	local i
	for i in "${!NEW_BASELINE_KEYS[@]}"; do
		if [ "${NEW_BASELINE_KEYS[$i]}" = "$search" ]; then
			echo "$i"
			return
		fi
	done
	echo "-1"
}

load_baseline() {
	# Skip if explicitly ignored or if generating a new baseline
	if [ "$IGNORE_BASELINE" = true ] || [ "$GENERATE_BASELINE" = true ]; then
		return
	fi

	if [ ! -f "$BASELINE_FILE" ]; then
		return
	fi

	BASELINE_ENABLED=true

	while IFS='|' read -r rule file line count hash; do
		# Skip comments and empty lines
		case "$rule" in
			"#"*|"") continue ;;
		esac

		# Basic validation
		if [ -z "$rule" ] || [ -z "$file" ] || [ -z "$count" ]; then
			continue
		fi

			# Normalize path so baseline entries are portable across environments
			file="$(normalize_baseline_path "$file")"
			local key="$rule|$file"
		BASELINE_KEYS+=("$key")
		BASELINE_ALLOWED+=("$count")
		BASELINE_FOUND+=(0)
	done < "$BASELINE_FILE"
}

# Record a hit for baseline application; returns 0 if suppressed, 1 if not suppressed
record_runtime_hit() {
	local rule="$1"
	local file="$2"
		file="$(normalize_baseline_path "$file")"
	local key="$rule|$file"

	local idx
	idx="$(baseline_index "$key")"
	if [ "$idx" -lt 0 ]; then
		return 1
	fi

	local current="${BASELINE_FOUND[$idx]}"
	[ -z "$current" ] && current=0
	current=$((current + 1))
	BASELINE_FOUND[$idx]="$current"

	local allowed="${BASELINE_ALLOWED[$idx]}"
	[ -z "$allowed" ] && allowed=0

	if [ "$current" -le "$allowed" ]; then
		BASELINED=$((BASELINED + 1))
		return 0  # suppressed
	fi

	return 1  # new finding (above baseline)
}

# Record a hit while generating a new baseline
record_new_baseline_hit() {
	local rule="$1"
	local file="$2"
		file="$(normalize_baseline_path "$file")"
	local key="$rule|$file"

	local idx
	idx="$(new_baseline_index "$key")"
	if [ "$idx" -lt 0 ]; then
		NEW_BASELINE_KEYS+=("$key")
		NEW_BASELINE_COUNTS+=(1)
		return
	fi

	local current="${NEW_BASELINE_COUNTS[$idx]}"
	[ -z "$current" ] && current=0
	current=$((current + 1))
	NEW_BASELINE_COUNTS[$idx]="$current"
}

# Returns 0 if this finding should be suppressed by baseline, 1 otherwise
should_suppress_finding() {
	local rule="$1"
	local file="$2"

	# When generating baseline we never suppress, but we do record counts
	if [ "$GENERATE_BASELINE" = true ]; then
		record_new_baseline_hit "$rule" "$file"
		return 1
	fi

	# When baseline is ignored or not enabled, do not suppress
	if [ "$IGNORE_BASELINE" = true ] || [ "$BASELINE_ENABLED" = false ]; then
		return 1
	fi

	# Apply existing baseline
	if record_runtime_hit "$rule" "$file"; then
		return 0
	fi

	return 1
}

check_stale_entries() {
	# Only meaningful when a baseline is loaded and not ignored
	if [ "$BASELINE_ENABLED" = false ] || [ "$IGNORE_BASELINE" = true ]; then
		return
	fi

	local i
	for i in "${!BASELINE_KEYS[@]}"; do
		local key="${BASELINE_KEYS[$i]}"
		local allowed="${BASELINE_ALLOWED[$i]}"
		local found="${BASELINE_FOUND[$i]}"

		[ -z "$allowed" ] && allowed=0
		[ -z "$found" ] && found=0

		if [ "$found" -lt "$allowed" ]; then
			STALE_ENTRIES=$((STALE_ENTRIES + 1))
			# Hint to help maintainers clean up the baseline over time
			text_echo "  \u2139 Baseline can be reduced: ${key} (allowed: ${allowed}, found: ${found})"
		fi
	done
}

generate_baseline_file() {
	if [ "$GENERATE_BASELINE" != true ]; then
		return
	fi

	# Ensure directory exists
	local dir
	dir="$(dirname "$BASELINE_FILE")"
	if [ ! -d "$dir" ]; then
		mkdir -p "$dir" 2>/dev/null || true
	fi

	local total=0
	local i
	for i in "${!NEW_BASELINE_KEYS[@]}"; do
		local count="${NEW_BASELINE_COUNTS[$i]}"
		[ -z "$count" ] && count=0
		total=$((total + count))
	done

	local tmp
	tmp="$(mktemp 2>/dev/null || echo "/tmp/neochrome-baseline.$$")"

	for i in "${!NEW_BASELINE_KEYS[@]}"; do
		local key="${NEW_BASELINE_KEYS[$i]}"
		local count="${NEW_BASELINE_COUNTS[$i]}"
		[ -z "$count" ] && count=0

		local rule="${key%%|*}"
		local file="${key#*|}"
		# line and snippet_hash are placeholders for now; matching is done on rule+file only
		echo "${rule}|${file}|0|${count}|*" >> "$tmp"
	done

	{
		echo "# .neochrome-baseline"
		echo "# Generated: $(date '+%Y-%m-%d %H:%M:%S')"
		echo "# Tool: WP Code Check by Hypercart $(grep -m1 'Version:' "$0" 2>/dev/null | sed 's/^# Version: //')"
		echo "# Total baselined: ${total}"
		echo "#"
		echo "# Format: rule|file|line|count|snippet_hash"
		echo
		sort "$tmp"
	} > "$BASELINE_FILE"

	rm -f "$tmp" 2>/dev/null || true

	text_echo "${GREEN}Baseline file written to ${BASELINE_FILE} (${total} total findings).${NC}"
}

# ============================================================================
# Main Script Output
# ============================================================================

# Load existing baseline (if any) before running checks
load_baseline

# Detect project info for display
# Preserve full path even if it contains spaces
FIRST_PATH="$PATHS"
PROJECT_INFO_JSON=$(detect_project_info "$FIRST_PATH")
PROJECT_TYPE=$(echo "$PROJECT_INFO_JSON" | grep -o '"type": "[^"]*"' | cut -d'"' -f4)
PROJECT_NAME=$(echo "$PROJECT_INFO_JSON" | grep -o '"name": "[^"]*"' | cut -d'"' -f4)
PROJECT_VERSION=$(echo "$PROJECT_INFO_JSON" | grep -o '"version": "[^"]*"' | cut -d'"' -f4)

			text_echo "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
			text_echo "${BLUE}  WP Code Check by Hypercart - Performance Analyzer v1.0.58${NC}"
		text_echo "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
text_echo ""

# Display project info if detected
if [ "$PROJECT_NAME" != "Unknown" ] && [ -n "$PROJECT_NAME" ]; then
  if [ -n "$PROJECT_VERSION" ]; then
    text_echo "${BOLD}Project:${NC} $PROJECT_NAME v$PROJECT_VERSION ${BLUE}[$PROJECT_TYPE]${NC}"
  else
    text_echo "${BOLD}Project:${NC} $PROJECT_NAME ${BLUE}[$PROJECT_TYPE]${NC}"
  fi
  text_echo ""
fi

text_echo "Scanning paths: $PATHS"
text_echo "Strict mode: $STRICT"
if [ "$ENABLE_LOGGING" = true ] && [ "$OUTPUT_FORMAT" = "text" ]; then
	text_echo "Logging to: $LOG_FILE"
fi
text_echo ""

ERRORS=0
WARNINGS=0

# Helper function to group findings by proximity
# Groups findings that are in the same file and within N lines of each other
# Usage: group_and_add_finding rule_id severity impact file lineno code check_name
#   Maintains state across calls via global variables:
#   - last_file, last_line, group_start_line, group_count, group_first_code, group_threshold
#   Call with flush=true to output the final group
group_and_add_finding() {
  local rule_id="$1"
  local severity="$2"
  local impact="$3"
  local file="$4"
  local lineno="$5"
  local code="$6"
  local check_name="$7"
  local flush="${8:-false}"  # Optional: set to "true" to flush final group

  # If flush mode, output the final group and return
  if [ "$flush" = "true" ]; then
    if [ "${group_count:-0}" -gt 0 ]; then
      local message="$check_name"
      if [ "$group_count" -gt 1 ]; then
        local end_line=$last_line
        message="$check_name ($group_count occurrences in lines $group_start_line-$end_line)"
      fi
      add_json_finding "$rule_id" "$severity" "$impact" "$last_file" "$group_start_line" "$message" "$group_first_code"
    fi
    return
  fi

  # Group consecutive findings in the same file
  if [ "$file" = "$last_file" ] && [ $((lineno - last_line)) -le ${group_threshold:-10} ]; then
    # Same group - increment count
    group_count=$((group_count + 1))
  else
    # New group - output previous group if exists
    if [ "${group_count:-0}" -gt 0 ]; then
      local message="$check_name"
      if [ "$group_count" -gt 1 ]; then
        local end_line=$last_line
        message="$check_name ($group_count occurrences in lines $group_start_line-$end_line)"
      fi
      add_json_finding "$rule_id" "$severity" "$impact" "$last_file" "$group_start_line" "$message" "$group_first_code"
    fi

    # Start new group
    last_file="$file"
    group_start_line=$lineno
    group_first_code="$code"
    group_count=1
  fi

  last_line=$lineno
}

# Function to run a check with impact scoring
# Usage: run_check "ERROR|WARNING" "CRITICAL|HIGH|MEDIUM|LOW" "Check name" "rule-id" patterns...
run_check() {
  local level="$1"    # ERROR or WARNING
  local impact="$2"   # CRITICAL, HIGH, MEDIUM, or LOW
  local name="$3"     # Check name
  local rule_id="$4"  # Rule ID for JSON output
  shift 4             # Remove first four args, rest are patterns
  local patterns="$@" # All remaining args are grep patterns

  # Allow callers to override which files are scanned (e.g., add JS/TS)
  local include_args="${OVERRIDE_GREP_INCLUDE:-"--include=*.php"}"

  # Format impact badge
  local impact_badge=""
  case $impact in
    CRITICAL) impact_badge="${RED}[CRITICAL]${NC}" ;;
    HIGH)     impact_badge="${RED}[HIGH]${NC}" ;;
    MEDIUM)   impact_badge="${YELLOW}[MEDIUM]${NC}" ;;
    LOW)      impact_badge="${BLUE}[LOW]${NC}" ;;
  esac

  text_echo "${BLUE}▸ $name ${impact_badge}${NC}"

   # Run grep with all patterns
   local result
   local finding_count=0
   local severity="error"
   [ "$level" = "WARNING" ] && severity="warning"

  if result=$(grep -rHn $EXCLUDE_ARGS $include_args $patterns $PATHS 2>/dev/null); then
	    local visible_result=""
	    local visible_count=0

	    # Initialize grouping state variables
	    last_file=""
	    last_line=0
	    group_start_line=0
	    group_count=0
	    group_first_code=""
	    group_threshold=10  # Lines within this range are grouped

	    # Collect findings for JSON output, applying baseline suppression per match
	    while IFS= read -r line; do
	      [ -z "$line" ] && continue
	      # Parse grep output: file:line:code
	      local file=$(echo "$line" | cut -d: -f1)
	      local lineno=$(echo "$line" | cut -d: -f2)
	      local code=$(echo "$line" | cut -d: -f3-)

	      local suppress=1
	      if should_suppress_finding "$rule_id" "$file"; then
	        suppress=0
	      fi

	      if [ "$suppress" -ne 0 ]; then
	        # Not covered by baseline - include in output and JSON
	        if [ -z "$visible_result" ]; then
	          visible_result="$line"
	        else
	          visible_result="${visible_result}
$line"
	        fi
	        visible_count=$((visible_count + 1))

	        # Use helper function to group findings
	        group_and_add_finding "$rule_id" "$severity" "$impact" "$file" "$lineno" "$code" "$name"
	      fi
	    done <<< "$result"

	    # Flush final group
	    group_and_add_finding "$rule_id" "$severity" "$impact" "" "" "" "$name" "true"

	    finding_count=$visible_count

	    if [ "$finding_count" -gt 0 ]; then
	      if [ "$level" = "ERROR" ]; then
	        text_echo "${RED}  ✗ FAILED${NC}"
	        if [ "$OUTPUT_FORMAT" = "text" ]; then
	          while IFS= read -r match; do
	            [ -z "$match" ] && continue
	            format_finding "$match"
	          done <<< "$(echo "$visible_result" | head -10)"
	          if [ "$VERBOSE" = "false" ] && [ "$finding_count" -gt 10 ]; then
	            echo "  ... and more (use --verbose to see all)"
	          fi
	        fi
	        ((ERRORS++))
	      else
	        text_echo "${YELLOW}  ⚠ WARNING${NC}"
	        if [ "$OUTPUT_FORMAT" = "text" ]; then
	          while IFS= read -r match; do
	            [ -z "$match" ] && continue
	            format_finding "$match"
	          done <<< "$(echo "$visible_result" | head -5)"
	        fi
	        ((WARNINGS++))
	      fi
	      add_json_check "$name" "$impact" "failed" "$finding_count"
	    else
	      # All matches were covered by the baseline
	      text_echo "${GREEN}  ✓ Passed (all issues covered by baseline)${NC}"
	      add_json_check "$name" "$impact" "passed" 0
	    fi
	  else
	    text_echo "${GREEN}  ✓ Passed${NC}"
	    add_json_check "$name" "$impact" "passed" 0
	  fi
	  text_echo ""
}

text_echo "${RED}━━━ CRITICAL CHECKS (will fail build) ━━━${NC}"
text_echo ""

# Debug code in production (JS + PHP)
OVERRIDE_GREP_INCLUDE="--include=*.php --include=*.js --include=*.jsx --include=*.ts --include=*.tsx"
run_check "ERROR" "CRITICAL" "Debug code in production" "spo-001-debug-code" \
  "-E console\\.(log|error|warn)[[:space:]]*\\(" \
  "-e debugger;" \
  "-E alert[[:space:]]*\\(" \
  "-E var_dump[[:space:]]*\\(" \
  "-E print_r[[:space:]]*\\(" \
  "-E error_log[[:space:]]*\\("
unset OVERRIDE_GREP_INCLUDE
text_echo ""

# Direct superglobal manipulation
run_check "ERROR" "HIGH" "Direct superglobal manipulation" "spo-002-superglobals" \
  "-E unset\\(\\$_(GET|POST|REQUEST|COOKIE)\\[" \
  "-E \\$_(GET|POST|REQUEST)[[:space:]]*=" \
  "-E \\$_(GET|POST|REQUEST|COOKIE)\\[[^]]*\\][[:space:]]*="

# Insecure data deserialization
run_check "ERROR" "CRITICAL" "Insecure data deserialization" "spo-003-insecure-deserialization" \
  "-E unserialize[[:space:]]*\\(\\$_" \
  "-E base64_decode[[:space:]]*\\(\\$_" \
  "-E json_decode[[:space:]]*\\(\\$_" \
  "-E maybe_unserialize[[:space:]]*\\(\\$_"

# Missing capability checks in admin functions
text_echo "${BLUE}▸ Admin functions without capability checks ${RED}[HIGH]${NC}"
ADMIN_CAP_MISSING=false
ADMIN_CAP_FINDING_COUNT=0
ADMIN_CAP_VISIBLE=""
ADMIN_SEEN_KEYS="|"

# Initialize grouping state variables
last_file=""
last_line=0
group_start_line=0
group_count=0
group_first_code=""
group_threshold=10

ADMIN_MATCHES=$(grep -rHn $EXCLUDE_ARGS --include="*.php" -E "function[[:space:]]+[a-zA-Z0-9_]*admin[a-zA-Z0-9_]*[[:space:]]*\\(|add_action[[:space:]]*\\([^)]*admin" $PATHS 2>/dev/null || true)
if [ -n "$ADMIN_MATCHES" ]; then
  while IFS= read -r match; do
    [ -z "$match" ] && continue
    file=$(echo "$match" | cut -d: -f1)
    lineno=$(echo "$match" | cut -d: -f2)
    code=$(echo "$match" | cut -d: -f3-)

    if ! [[ "$lineno" =~ ^[0-9]+$ ]]; then
      continue
    fi

    key="|${file}:${lineno}|"
    if echo "$ADMIN_SEEN_KEYS" | grep -F -q "$key"; then
      continue
    fi

    start_line=$lineno
    end_line=$((lineno + 10))
    context=$(sed -n "${start_line},${end_line}p" "$file" 2>/dev/null || true)

    if echo "$context" | grep -qE "current_user_can[[:space:]]*\\(|user_can[[:space:]]*\\("; then
      continue
    fi

    ADMIN_SEEN_KEYS="${ADMIN_SEEN_KEYS}${key}"

    if should_suppress_finding "spo-004-missing-cap-check" "$file"; then
      continue
    fi

    ADMIN_CAP_MISSING=true
    ((ADMIN_CAP_FINDING_COUNT++))

    match_output="${file}:${lineno}:${code}"
    if [ -z "$ADMIN_CAP_VISIBLE" ]; then
      ADMIN_CAP_VISIBLE="$match_output"
    else
      ADMIN_CAP_VISIBLE="${ADMIN_CAP_VISIBLE}
$match_output"
    fi

    # Use helper function to group findings
    group_and_add_finding "spo-004-missing-cap-check" "error" "HIGH" "$file" "$lineno" "$code" "Admin function/hook missing capability check near admin context"
  done <<< "$ADMIN_MATCHES"

  # Flush final group
  group_and_add_finding "spo-004-missing-cap-check" "error" "HIGH" "" "" "" "Admin function/hook missing capability check near admin context" "true"
fi

if [ "$ADMIN_CAP_MISSING" = true ]; then
  text_echo "${RED}  ✗ FAILED${NC}"
  if [ "$OUTPUT_FORMAT" = "text" ] && [ -n "$ADMIN_CAP_VISIBLE" ]; then
    while IFS= read -r match; do
      [ -z "$match" ] && continue
      format_finding "$match"
    done <<< "$(echo "$ADMIN_CAP_VISIBLE" | head -5)"
  fi
  ((ERRORS++))
  add_json_check "Admin functions without capability checks" "HIGH" "failed" "$ADMIN_CAP_FINDING_COUNT"
else
  text_echo "${GREEN}  ✓ Passed${NC}"
  add_json_check "Admin functions without capability checks" "HIGH" "passed" 0
fi
text_echo ""

text_echo "${BLUE}▸ Unbounded AJAX polling (setInterval + fetch/ajax) ${RED}[HIGH]${NC}"
AJAX_POLLING=false
AJAX_POLLING_FINDING_COUNT=0
AJAX_POLLING_VISIBLE=""
POLLING_MATCHES=$(grep -rHn $EXCLUDE_ARGS --include="*.js" -E "setInterval[[:space:]]*\\(" $PATHS 2>/dev/null || true)
if [ -n "$POLLING_MATCHES" ]; then
  while IFS= read -r match; do
    [ -z "$match" ] && continue
    file=$(echo "$match" | cut -d: -f1)
    lineno=$(echo "$match" | cut -d: -f2)
    code=$(echo "$match" | cut -d: -f3-)

    if ! [[ "$lineno" =~ ^[0-9][0-9]*$ ]]; then
      continue
    fi

    start_line=$lineno
    end_line=$((lineno + 5))
    context=$(sed -n "${start_line},${end_line}p" "$file" 2>/dev/null)

    if echo "$context" | grep -qiE "\\.ajax|fetch\\(|axios\\(|XMLHttpRequest|wp\\.apiFetch"; then
      if should_suppress_finding "ajax-polling-setinterval" "$file"; then
        continue
      fi

      AJAX_POLLING=true
      ((AJAX_POLLING_FINDING_COUNT++))
      add_json_finding "ajax-polling-setinterval" "error" "HIGH" "$file" "${lineno:-0}" "AJAX polling via setInterval without rate limits" "$code"
      if [ -z "$AJAX_POLLING_VISIBLE" ]; then
        AJAX_POLLING_VISIBLE="$match"
      else
        AJAX_POLLING_VISIBLE="${AJAX_POLLING_VISIBLE}
$match"
      fi
    fi
  done <<< "$POLLING_MATCHES"
fi
if [ "$AJAX_POLLING" = true ]; then
  text_echo "${RED}  ✗ FAILED${NC}"
  if [ "$OUTPUT_FORMAT" = "text" ] && [ -n "$AJAX_POLLING_VISIBLE" ]; then
    while IFS= read -r match; do
      [ -z "$match" ] && continue
      format_finding "$match"
    done <<< "$(echo "$AJAX_POLLING_VISIBLE" | head -5)"
  fi
  ((ERRORS++))
  add_json_check "Unbounded AJAX polling (setInterval + fetch/ajax)" "HIGH" "failed" "$AJAX_POLLING_FINDING_COUNT"
else
  text_echo "${GREEN}  ✓ Passed${NC}"
  add_json_check "Unbounded AJAX polling (setInterval + fetch/ajax)" "HIGH" "passed" 0
fi
text_echo ""

text_echo "${BLUE}▸ REST endpoints without pagination/limits ${RED}[CRITICAL]${NC}"
REST_UNBOUNDED=false
REST_FINDING_COUNT=0
REST_VISIBLE=""
REST_MATCHES=$(grep -rHn $EXCLUDE_ARGS --include="*.php" -E "register_rest_route[[:space:]]*\\(" $PATHS 2>/dev/null || true)
if [ -n "$REST_MATCHES" ]; then
  while IFS= read -r match; do
    [ -z "$match" ] && continue
    file=$(echo "$match" | cut -d: -f1)
    lineno=$(echo "$match" | cut -d: -f2)
    code=$(echo "$match" | cut -d: -f3-)

    if ! [[ "$lineno" =~ ^[0-9][0-9]*$ ]]; then
      continue
    fi

    start_line=$lineno
    end_line=$((lineno + 15))
    context=$(sed -n "${start_line},${end_line}p" "$file" 2>/dev/null)

    if ! echo "$context" | grep -qiE "'per_page'|\"per_page\"|'page'|\"page\"|'limit'|\"limit\"|pagination|paged|per_page"; then
      if should_suppress_finding "rest-endpoint-unbounded" "$file"; then
        continue
      fi

      REST_UNBOUNDED=true
      ((REST_FINDING_COUNT++))
      add_json_finding "rest-endpoint-unbounded" "error" "CRITICAL" "$file" "${lineno:-0}" "register_rest_route without per_page/limit pagination guard" "$code"
      if [ -z "$REST_VISIBLE" ]; then
        REST_VISIBLE="$match"
      else
        REST_VISIBLE="${REST_VISIBLE}
$match"
      fi
    fi
  done <<< "$REST_MATCHES"
fi
if [ "$REST_UNBOUNDED" = true ]; then
  text_echo "${RED}  ✗ FAILED${NC}"
  if [ "$OUTPUT_FORMAT" = "text" ] && [ -n "$REST_VISIBLE" ]; then
    while IFS= read -r match; do
      [ -z "$match" ] && continue
      format_finding "$match"
    done <<< "$(echo "$REST_VISIBLE" | head -5)"
  fi
  ((ERRORS++))
  add_json_check "REST endpoints without pagination/limits" "CRITICAL" "failed" "$REST_FINDING_COUNT"
else
  text_echo "${GREEN}  ✓ Passed${NC}"
  add_json_check "REST endpoints without pagination/limits" "CRITICAL" "passed" 0
fi
text_echo ""

text_echo "${BLUE}▸ wp_ajax handlers without nonce validation ${RED}[HIGH]${NC}"
AJAX_NONCE_FAIL=false
AJAX_NONCE_FINDING_COUNT=0
AJAX_FILES=$(grep -rln $EXCLUDE_ARGS --include="*.php" -e "wp_ajax" $PATHS 2>/dev/null || true)
if [ -n "$AJAX_FILES" ]; then
  for file in $AJAX_FILES; do
    hook_count=$(grep -E "wp_ajax" "$file" 2>/dev/null | wc -l | tr -d '[:space:]')
    nonce_count=$(grep -E "check_ajax_referer[[:space:]]*\\(|wp_verify_nonce[[:space:]]*\\(" "$file" 2>/dev/null | wc -l | tr -d '[:space:]')

    if [ -z "$hook_count" ] || [ "$hook_count" -eq 0 ]; then
      continue
    fi

	    # Require at least one nonce validation somewhere in the file
	    # if any wp_ajax hook is present. This avoids false positives in
	    # common patterns like shared handlers for wp_ajax_/wp_ajax_nopriv_
	    # while still flagging completely unprotected files.
	    if [ -z "$nonce_count" ] || [ "$nonce_count" -eq 0 ]; then
	      :
	    else
	      continue
	    fi
    if should_suppress_finding "wp-ajax-no-nonce" "$file"; then
      continue
    fi

    lineno=$(grep -n "wp_ajax" "$file" 2>/dev/null | head -1 | cut -d: -f1)
    code=$(grep -n "wp_ajax" "$file" 2>/dev/null | head -1 | cut -d: -f2-)
    text_echo "  $file: wp_ajax handler missing nonce validation"
    add_json_finding "wp-ajax-no-nonce" "error" "HIGH" "$file" "${lineno:-0}" "wp_ajax handler missing nonce validation" "$code"
    AJAX_NONCE_FAIL=true
    ((AJAX_NONCE_FINDING_COUNT++))
  done
fi
if [ "$AJAX_NONCE_FAIL" = true ]; then
  text_echo "${RED}  ✗ FAILED${NC}"
  ((ERRORS++))
  add_json_check "wp_ajax handlers without nonce validation" "HIGH" "failed" "$AJAX_NONCE_FINDING_COUNT"
else
  text_echo "${GREEN}  ✓ Passed${NC}"
  add_json_check "wp_ajax handlers without nonce validation" "HIGH" "passed" 0
fi
text_echo ""

run_check "ERROR" "CRITICAL" "Unbounded posts_per_page" "unbounded-posts-per-page" \
  "-e posts_per_page[[:space:]]*=>[[:space:]]*-1"

run_check "ERROR" "CRITICAL" "Unbounded numberposts" "unbounded-numberposts" \
  "-e numberposts[[:space:]]*=>[[:space:]]*-1"

run_check "ERROR" "CRITICAL" "nopaging => true" "nopaging-true" \
  "-e nopaging[[:space:]]*=>[[:space:]]*true"

run_check "ERROR" "CRITICAL" "Unbounded wc_get_orders limit" "unbounded-wc-get-orders" \
  "-e 'limit'[[:space:]]*=>[[:space:]]*-1"

# get_users check - unbounded user queries (can crash sites with many users)
text_echo "${BLUE}▸ get_users without number limit ${RED}[CRITICAL]${NC}"
USERS_UNBOUNDED=false
USERS_FINDING_COUNT=0
USERS_VISIBLE=""

# Find all get_users() calls with line numbers
USERS_MATCHES=$(grep -rHn $EXCLUDE_ARGS --include="*.php" -e "get_users[[:space:]]*(" $PATHS 2>/dev/null || true)

if [ -n "$USERS_MATCHES" ]; then
  while IFS= read -r match; do
    [ -z "$match" ] && continue
    file=$(echo "$match" | cut -d: -f1)
    lineno=$(echo "$match" | cut -d: -f2)
    code=$(echo "$match" | cut -d: -f3-)

    if ! [[ "$lineno" =~ ^[0-9]+$ ]]; then
      continue
    fi

    # Check if THIS specific get_users() call has 'number' parameter within next 5 lines
    start_line=$lineno
    end_line=$((lineno + 5))
    context=$(sed -n "${start_line},${end_line}p" "$file" 2>/dev/null || true)

    # Check if 'number' parameter exists in this specific call's context
    if ! echo "$context" | grep -q -e "'number'" -e '"number"'; then
      # Apply baseline suppression per finding
      if ! should_suppress_finding "unbounded-get-users" "$file"; then
        USERS_UNBOUNDED=true
        ((USERS_FINDING_COUNT++))
        
        match_output="${file}:${lineno}:${code}"
        if [ -z "$USERS_VISIBLE" ]; then
          USERS_VISIBLE="$match_output"
        else
          USERS_VISIBLE="${USERS_VISIBLE}
$match_output"
        fi
        
        add_json_finding "unbounded-get-users" "error" "CRITICAL" "$file" "$lineno" "get_users() without 'number' limit can fetch ALL users" "$code"
      fi
    fi
  done <<< "$USERS_MATCHES"
fi

if [ "$USERS_UNBOUNDED" = true ]; then
  text_echo "${RED}  ✗ FAILED${NC}"
  if [ "$OUTPUT_FORMAT" = "text" ] && [ -n "$USERS_VISIBLE" ]; then
    while IFS= read -r match; do
      [ -z "$match" ] && continue
      format_finding "$match"
    done <<< "$(echo "$USERS_VISIBLE" | head -10)"
  fi
  ((ERRORS++))
  add_json_check "get_users without number limit" "CRITICAL" "failed" "$USERS_FINDING_COUNT"
else
  text_echo "${GREEN}  ✓ Passed${NC}"
  add_json_check "get_users without number limit" "CRITICAL" "passed" 0
fi
text_echo ""

# get_terms check - more complex, needs context analysis
text_echo "${BLUE}▸ get_terms without number limit ${RED}[CRITICAL]${NC}"
TERMS_FILES=$(grep -rln $EXCLUDE_ARGS --include="*.php" -e "get_terms[[:space:]]*(" $PATHS 2>/dev/null || true)
TERMS_UNBOUNDED=false
TERMS_FINDING_COUNT=0
if [ -n "$TERMS_FILES" ]; then
  for file in $TERMS_FILES; do
    # Check if file has get_terms without 'number' or "number" nearby (within 5 lines)
    # Support both single and double quotes
	    if ! grep -A5 "get_terms[[:space:]]*(" "$file" 2>/dev/null | grep -q -e "'number'" -e '"number"'; then
	      # Apply baseline suppression per file
	      if ! should_suppress_finding "get-terms-no-limit" "$file"; then
	        text_echo "  $file: get_terms() may be missing 'number' parameter"
	        # Get line number for JSON
	        lineno=$(grep -n "get_terms[[:space:]]*(" "$file" 2>/dev/null | head -1 | cut -d: -f1)
	        add_json_finding "get-terms-no-limit" "error" "CRITICAL" "$file" "${lineno:-0}" "get_terms() may be missing 'number' parameter" "get_terms("
	        TERMS_UNBOUNDED=true
	        ((TERMS_FINDING_COUNT++))
	      fi
	    fi
  done
fi
if [ "$TERMS_UNBOUNDED" = true ]; then
  text_echo "${RED}  ✗ FAILED${NC}"
  ((ERRORS++))
  add_json_check "get_terms without number limit" "CRITICAL" "failed" "$TERMS_FINDING_COUNT"
else
  text_echo "${GREEN}  ✓ Passed${NC}"
  add_json_check "get_terms without number limit" "CRITICAL" "passed" 0
fi
text_echo ""

# pre_get_posts unbounded check - files that hook pre_get_posts and set unbounded queries
text_echo "${BLUE}▸ pre_get_posts forcing unbounded queries ${RED}[CRITICAL]${NC}"
PRE_GET_POSTS_UNBOUNDED=false
PRE_GET_POSTS_FINDING_COUNT=0
PRE_GET_POSTS_FILES=$(grep -rln $EXCLUDE_ARGS --include="*.php" -e "add_action.*pre_get_posts\|add_filter.*pre_get_posts" $PATHS 2>/dev/null || true)
if [ -n "$PRE_GET_POSTS_FILES" ]; then
  for file in $PRE_GET_POSTS_FILES; do
    # Check if file sets posts_per_page to -1 or nopaging to true
	    if grep -q "set[[:space:]]*([[:space:]]*['\"]posts_per_page['\"][[:space:]]*,[[:space:]]*-1" "$file" 2>/dev/null || \
	       grep -q "set[[:space:]]*([[:space:]]*['\"]nopaging['\"][[:space:]]*,[[:space:]]*true" "$file" 2>/dev/null; then
	      if ! should_suppress_finding "pre-get-posts-unbounded" "$file"; then
	        text_echo "  $file: pre_get_posts hook sets unbounded query"
	        lineno=$(grep -n "pre_get_posts" "$file" 2>/dev/null | head -1 | cut -d: -f1)
	        add_json_finding "pre-get-posts-unbounded" "error" "CRITICAL" "$file" "${lineno:-0}" "pre_get_posts hook sets unbounded query" "pre_get_posts"
	        PRE_GET_POSTS_UNBOUNDED=true
	        ((PRE_GET_POSTS_FINDING_COUNT++))
	      fi
	    fi
  done
fi
if [ "$PRE_GET_POSTS_UNBOUNDED" = true ]; then
  text_echo "${RED}  ✗ FAILED${NC}"
  ((ERRORS++))
  add_json_check "pre_get_posts forcing unbounded queries" "CRITICAL" "failed" "$PRE_GET_POSTS_FINDING_COUNT"
else
  text_echo "${GREEN}  ✓ Passed${NC}"
  add_json_check "pre_get_posts forcing unbounded queries" "CRITICAL" "passed" 0
fi
text_echo ""

# Unbounded direct SQL on terms tables
# Look for lines with wpdb->terms or wpdb->term_taxonomy that don't have LIMIT on the same line
text_echo "${BLUE}▸ Unbounded SQL on wp_terms/wp_term_taxonomy ${RED}[HIGH]${NC}"
TERMS_SQL_UNBOUNDED=false
TERMS_SQL_FINDING_COUNT=0
# Find lines referencing terms tables in SQL context
TERMS_SQL_MATCHES=$(grep -rHn $EXCLUDE_ARGS --include="*.php" -E '\$wpdb->(terms|term_taxonomy)' $PATHS 2>/dev/null || true)
	if [ -n "$TERMS_SQL_MATCHES" ]; then
	  # Filter out lines that have LIMIT (case-insensitive to catch both 'LIMIT' and 'limit')
	  UNBOUNDED_MATCHES=$(echo "$TERMS_SQL_MATCHES" | grep -vi "LIMIT" || true)
	  if [ -n "$UNBOUNDED_MATCHES" ]; then
	    VISIBLE_MATCHES=""
	    while IFS= read -r line; do
	      [ -z "$line" ] && continue
	      _file=$(echo "$line" | cut -d: -f1)
	      _lineno=$(echo "$line" | cut -d: -f2)
	      _code=$(echo "$line" | cut -d: -f3-)

	      if ! should_suppress_finding "unbounded-terms-sql" "$_file"; then
	        TERMS_SQL_UNBOUNDED=true
	        ((TERMS_SQL_FINDING_COUNT++))
	        add_json_finding "unbounded-terms-sql" "error" "HIGH" "$_file" "${_lineno:-0}" "Unbounded SQL on wp_terms/wp_term_taxonomy" "$_code"
	        if [ -z "$VISIBLE_MATCHES" ]; then
	          VISIBLE_MATCHES="$line"
	        else
	          VISIBLE_MATCHES="${VISIBLE_MATCHES}
$line"
	        fi
	      fi
	    done <<< "$UNBOUNDED_MATCHES"

	    if [ "$TERMS_SQL_UNBOUNDED" = true ] && [ "$OUTPUT_FORMAT" = "text" ]; then
	      while IFS= read -r match; do
	        [ -z "$match" ] && continue
	        echo "  $(format_finding "$match")"
	      done <<< "$(echo "$VISIBLE_MATCHES" | head -5)"
	    fi
	  fi
	fi
if [ "$TERMS_SQL_UNBOUNDED" = true ]; then
  text_echo "${RED}  ✗ FAILED${NC}"
  ((ERRORS++))
  add_json_check "Unbounded SQL on wp_terms/wp_term_taxonomy" "HIGH" "failed" "$TERMS_SQL_FINDING_COUNT"
else
  text_echo "${GREEN}  ✓ Passed${NC}"
  add_json_check "Unbounded SQL on wp_terms/wp_term_taxonomy" "HIGH" "passed" 0
fi

# Unvalidated cron intervals - can cause infinite loops or silent failures
text_echo "${BLUE}▸ Unvalidated cron intervals ${RED}[HIGH]${NC}"
CRON_INTERVAL_FAIL=false
CRON_INTERVAL_FINDING_COUNT=0

# Find files with cron_schedules filter or wp_schedule_event
CRON_FILES=$(grep -rln $EXCLUDE_ARGS --include="*.php" \
  -e "cron_schedules" \
  -e "wp_schedule_event" \
  -e "wp_schedule_single_event" \
  $PATHS 2>/dev/null || true)

if [ -n "$CRON_FILES" ]; then
  for file in $CRON_FILES; do
    # Look for 'interval' => $variable * 60 or $variable * MINUTE_IN_SECONDS patterns
    # Pattern: 'interval' => $var * (60|MINUTE_IN_SECONDS)
    # Use single quotes to avoid shell escaping issues with $ and *
    INTERVAL_MATCHES=$(grep -Hn -E \
      '\$[a-zA-Z_0-9]+[[:space:]]*\*[[:space:]]*(60|MINUTE_IN_SECONDS)' \
      "$file" 2>/dev/null | grep -E "'interval'[[:space:]]*=>" || true)

    if [ -n "$INTERVAL_MATCHES" ]; then
      # For each match, check if it's validated
      while IFS= read -r match; do
        [ -z "$match" ] && continue

        # Parse grep -Hn output: filename:lineno:code
        # Extract filename, line number, and code
        match_file=$(echo "$match" | cut -d: -f1)
        lineno=$(echo "$match" | cut -d: -f2)
        code=$(echo "$match" | cut -d: -f3-)

        # Validate lineno is numeric
        if ! [[ "$lineno" =~ ^[0-9]+$ ]]; then
          continue
        fi

        # Extract the variable name that's being multiplied (not the first variable in the line)
        # Look for the pattern: $var * 60 or $var * MINUTE_IN_SECONDS
        var_name=$(echo "$code" | grep -oE '\$[a-zA-Z_0-9]+[[:space:]]*\*[[:space:]]*(60|MINUTE_IN_SECONDS)' | grep -oE '\$[a-zA-Z_0-9]+' | head -1)

        # Skip if we couldn't extract a variable name
        if [ -z "$var_name" ]; then
          continue
        fi

        # Escape the $ for use in regex patterns
        var_escaped=$(echo "$var_name" | sed 's/\$/\\$/g')

        # Check if absint() is used on this variable within 10 lines before
        # or if there's bounds checking (< 1 or > with a number)
        has_validation=false

        # Check 10 lines before for absint($var_name) or bounds checking
        start_line=$((lineno - 10))
        [ "$start_line" -lt 1 ] && start_line=1

        # Get context lines
        context=$(sed -n "${start_line},${lineno}p" "$file" 2>/dev/null || true)

        # Check for absint() - either wrapping the variable or assigned to it
        # Pattern 1: $var = absint(...)
        # Pattern 2: absint($var)
        if echo "$context" | grep -qE "${var_escaped}[[:space:]]*=[[:space:]]*absint[[:space:]]*\("; then
          has_validation=true
        fi

        if echo "$context" | grep -qE "absint[[:space:]]*\([[:space:]]*${var_escaped}"; then
          has_validation=true
        fi

        # Check for bounds validation: if ($var < 1 || $var > number)
        if echo "$context" | grep -qE "${var_escaped}[[:space:]]*[<>]=?[[:space:]]*[0-9]"; then
          has_validation=true
        fi

        if [ "$has_validation" = false ]; then
          if ! should_suppress_finding "unvalidated-cron-interval" "$file"; then
            CRON_INTERVAL_FAIL=true
            ((CRON_INTERVAL_FINDING_COUNT++))

            # Format the finding for display
            if [ "$OUTPUT_FORMAT" = "text" ]; then
              text_echo "  ${file}:${lineno}: ${code}"
              text_echo "    ${YELLOW}→ Use: ${var_name} = absint(${var_name}); if (${var_name} < 1 || ${var_name} > 1440) ${var_name} = 15;${NC}"
            fi

            add_json_finding "unvalidated-cron-interval" "error" "HIGH" "$file" "$lineno" \
              "Unvalidated cron interval - use absint() and bounds checking (1-1440 minutes) to prevent corrupt data from causing 0-second intervals or infinite loops" \
              "$code"
          fi
        fi
      done <<< "$INTERVAL_MATCHES"
    fi
  done
fi

if [ "$CRON_INTERVAL_FAIL" = true ]; then
  text_echo "${RED}  ✗ FAILED${NC}"
  ((ERRORS++))
  add_json_check "Unvalidated cron intervals" "HIGH" "failed" "$CRON_INTERVAL_FINDING_COUNT"
else
  text_echo "${GREEN}  ✓ Passed${NC}"
  add_json_check "Unvalidated cron intervals" "HIGH" "passed" 0
fi
text_echo ""

text_echo "${YELLOW}━━━ WARNING CHECKS (review recommended) ━━━${NC}"
text_echo ""

# Enhanced timezone check - skip lines with phpcs:ignore comments
text_echo "${BLUE}▸ Timezone-sensitive patterns (current_time/date) ${YELLOW}[LOW]${NC}"
TZ_WARNINGS=0
TZ_FINDING_COUNT=0
TZ_MATCHES=$(grep -rHn $EXCLUDE_ARGS --include="*.php" \
  -e "current_time[[:space:]]*([[:space:]]*['\"]timestamp" \
  -e "date[[:space:]]*([[:space:]]*['\"][YmdHis-]*['\"]" \
  $PATHS 2>/dev/null || true)

if [ -n "$TZ_MATCHES" ]; then
  # Filter out lines that have phpcs:ignore nearby (check line before)
  FILTERED_MATCHES=""
  while IFS= read -r match; do
    file_line=$(echo "$match" | cut -d: -f1-2)
    file=$(echo "$match" | cut -d: -f1)
    line_num=$(echo "$match" | cut -d: -f2)
    code=$(echo "$match" | cut -d: -f3-)

	    # Defensive: ensure line number is numeric before doing arithmetic.
	    # On some platforms/tools, unexpected grep output can sneak in here
	    # (e.g. warnings or lines without the usual file:line:code format),
	    # which would make "$line_num" non-numeric and break $((...)).
	    if ! [[ "$line_num" =~ ^[0-9][0-9]*$ ]]; then
	      if [ "${NEOCHROME_DEBUG:-}" = "1" ] && [ "$OUTPUT_FORMAT" = "text" ]; then
	        text_echo "  [DEBUG] Skipping non-numeric timezone match: $match"
	      fi
	      continue
	    fi

    # Check if there's a phpcs:ignore comment on the line before or same line
    prev_line=$((line_num - 1))
    has_ignore=false

    # Check if current line or previous line has phpcs:ignore
    if sed -n "${prev_line}p;${line_num}p" "$file" 2>/dev/null | grep -q "phpcs:ignore"; then
      has_ignore=true
    fi

	    if [ "$has_ignore" = false ]; then
	      if ! should_suppress_finding "timezone-sensitive-pattern" "$file"; then
	        FILTERED_MATCHES="${FILTERED_MATCHES}${match}"$'\n'
	        add_json_finding "timezone-sensitive-pattern" "warning" "LOW" "$file" "$line_num" "Timezone-sensitive pattern without phpcs:ignore" "$code"
	        ((TZ_WARNINGS++)) || true
	        ((TZ_FINDING_COUNT++)) || true
	      fi
	    fi
  done <<< "$TZ_MATCHES"

  if [ "$TZ_WARNINGS" -gt 0 ]; then
    text_echo "${YELLOW}  ⚠ WARNING ($TZ_WARNINGS occurrence(s) without phpcs:ignore)${NC}"
    if [ "$OUTPUT_FORMAT" = "text" ]; then
      if [ "$VERBOSE" = "true" ]; then
        echo "$FILTERED_MATCHES"
      else
        echo "$FILTERED_MATCHES" | head -5
        if [ "$TZ_WARNINGS" -gt 5 ]; then
          echo "  ... and $((TZ_WARNINGS - 5)) more (use --verbose to see all)"
        fi
      fi
    fi
    ((WARNINGS++))
    add_json_check "Timezone-sensitive patterns (current_time/date)" "LOW" "failed" "$TZ_FINDING_COUNT"
  else
    text_echo "${GREEN}  ✓ Passed (all occurrences have phpcs:ignore)${NC}"
    add_json_check "Timezone-sensitive patterns (current_time/date)" "LOW" "passed" 0
  fi
else
  text_echo "${GREEN}  ✓ Passed${NC}"
  add_json_check "Timezone-sensitive patterns (current_time/date)" "LOW" "passed" 0
fi
text_echo ""

run_check "WARNING" "HIGH" "Randomized ordering (ORDER BY RAND)" "order-by-rand" \
  "-e orderby[[:space:]]*=>[[:space:]]*['\"]rand['\"]" \
  "-E ORDER[[:space:]]+BY[[:space:]]+RAND\("

# LIKE queries with leading wildcards
text_echo "${BLUE}▸ LIKE queries with leading wildcards ${YELLOW}[MEDIUM]${NC}"
LIKE_WARNINGS=0
LIKE_ISSUES=""
LIKE_FINDING_COUNT=0

# Pattern 1: WP_Query meta_query with compare => 'LIKE' and value starting with %
# Look for 'compare' => 'LIKE' patterns in meta_query context
META_LIKE=$(grep -rHn $EXCLUDE_ARGS --include="*.php" \
  -E "'compare'[[:space:]]*=>[[:space:]]*['\"]LIKE['\"]" \
  $PATHS 2>/dev/null || true)

	if [ -n "$META_LIKE" ]; then
	  # Check each match for nearby % wildcard at start of value
	  while IFS= read -r match; do
	    [ -z "$match" ] && continue
	    file=$(echo "$match" | cut -d: -f1)
	      line_num=$(echo "$match" | cut -d: -f2)
	      code=$(echo "$match" | cut -d: -f3-)

	      # Defensive: ensure line number is numeric before doing arithmetic.
	      # On some platforms/tools, unexpected grep output can sneak in here,
	      # which would make "$line_num" non-numeric and break $((...)).
	      if ! [[ "$line_num" =~ ^[0-9][0-9]*$ ]]; then
	        if [ "${NEOCHROME_DEBUG:-}" = "1" ] && [ "$OUTPUT_FORMAT" = "text" ]; then
	          text_echo "  [DEBUG] Skipping non-numeric LIKE match: $match"
	        fi
	        continue
	      fi

	      # Look at surrounding lines (5 before and after) for value starting with %
	      start_line=$((line_num - 5))
	      [ "$start_line" -lt 1 ] && start_line=1
	      end_line=$((line_num + 5))

	    # Check for 'value' => '%... pattern nearby
	    if sed -n "${start_line},${end_line}p" "$file" 2>/dev/null | grep -qE "'value'[[:space:]]*=>[[:space:]]*['\"]%"; then
	      if ! should_suppress_finding "like-leading-wildcard" "$file"; then
	        LIKE_ISSUES="${LIKE_ISSUES}${match}"$'\n'
	        add_json_finding "like-leading-wildcard" "warning" "MEDIUM" "$file" "$line_num" "LIKE query with leading wildcard prevents index use" "$code"
	        ((LIKE_WARNINGS++)) || true
	        ((LIKE_FINDING_COUNT++)) || true
	      fi
	    fi
	  done <<< "$META_LIKE"
	fi

# Pattern 2: Raw SQL with LIKE '%... (leading wildcard)
# Only match actual code, not comments (lines starting with * or //)
SQL_LIKE=$(grep -rHn $EXCLUDE_ARGS --include="*.php" \
  -E "LIKE[[:space:]]+['\"]%" \
  $PATHS 2>/dev/null | grep -v "^[^:]*:[0-9]*:[[:space:]]*//" | grep -v "^[^:]*:[0-9]*:[[:space:]]*\*" || true)

	if [ -n "$SQL_LIKE" ]; then
	  while IFS= read -r match; do
	    [ -z "$match" ] && continue
	    file=$(echo "$match" | cut -d: -f1)
	    line_num=$(echo "$match" | cut -d: -f2)
	    code=$(echo "$match" | cut -d: -f3-)
	    if ! should_suppress_finding "like-leading-wildcard" "$file"; then
	      LIKE_ISSUES="${LIKE_ISSUES}${match}"$'\n'
	      add_json_finding "like-leading-wildcard" "warning" "MEDIUM" "$file" "$line_num" "LIKE query with leading wildcard prevents index use" "$code"
	      ((LIKE_WARNINGS++)) || true
	      ((LIKE_FINDING_COUNT++)) || true
	    fi
	  done <<< "$SQL_LIKE"
	fi

if [ "$LIKE_WARNINGS" -gt 0 ]; then
  text_echo "${YELLOW}  ⚠ WARNING - LIKE queries with leading wildcards prevent index use:${NC}"
  if [ "$OUTPUT_FORMAT" = "text" ]; then
    if [ "$VERBOSE" = "true" ]; then
      echo "$LIKE_ISSUES"
    else
      echo "$LIKE_ISSUES" | head -5
      if [ "$LIKE_WARNINGS" -gt 5 ]; then
        echo "  ... and $((LIKE_WARNINGS - 5)) more (use --verbose to see all)"
      fi
    fi
  fi
  ((WARNINGS++))
  add_json_check "LIKE queries with leading wildcards" "MEDIUM" "failed" "$LIKE_FINDING_COUNT"
else
  text_echo "${GREEN}  ✓ Passed${NC}"
  add_json_check "LIKE queries with leading wildcards" "MEDIUM" "passed" 0
fi
text_echo ""

# N+1 pattern check (simplified) - includes post, term, and user meta
text_echo "${BLUE}▸ Potential N+1 patterns (meta in loops) ${YELLOW}[MEDIUM]${NC}"
	N1_FILES=$(grep -rl $EXCLUDE_ARGS --include="*.php" -e "get_post_meta\|get_term_meta\|get_user_meta" $PATHS 2>/dev/null | \
	           xargs -I{} grep -l "foreach\|while[[:space:]]*(" {} 2>/dev/null | head -5 || true)
	N1_FINDING_COUNT=0
	VISIBLE_N1_FILES=""
	if [ -n "$N1_FILES" ]; then
	  # Collect findings, applying baseline per file
	  while IFS= read -r f; do
	    [ -z "$f" ] && continue
	    if ! should_suppress_finding "n-plus-1-pattern" "$f"; then
	      VISIBLE_N1_FILES="${VISIBLE_N1_FILES}${f}"$'\n'
	      add_json_finding "n-plus-1-pattern" "warning" "MEDIUM" "$f" "0" "File may contain N+1 query pattern (meta in loops)" ""
	      ((N1_FINDING_COUNT++)) || true
	    fi
	  done <<< "$N1_FILES"

	  if [ "$N1_FINDING_COUNT" -gt 0 ]; then
	    text_echo "${YELLOW}  ⚠ Files with potential N+1 patterns:${NC}"
	    if [ "$OUTPUT_FORMAT" = "text" ]; then
	      echo "$VISIBLE_N1_FILES" | while read f; do [ -n "$f" ] && echo "    - $f"; done
	    fi
	    ((WARNINGS++))
	    add_json_check "Potential N+1 patterns (meta in loops)" "MEDIUM" "failed" "$N1_FINDING_COUNT"
	  else
	    text_echo "${GREEN}  ✓ No obvious N+1 patterns${NC}"
	    add_json_check "Potential N+1 patterns (meta in loops)" "MEDIUM" "passed" 0
	  fi
	else
	  text_echo "${GREEN}  ✓ No obvious N+1 patterns${NC}"
	  add_json_check "Potential N+1 patterns (meta in loops)" "MEDIUM" "passed" 0
	fi
text_echo ""

# Transient abuse check - transients without expiration
text_echo "${BLUE}▸ Transients without expiration ${YELLOW}[MEDIUM]${NC}"
TRANSIENT_MATCHES=$(grep -rHn $EXCLUDE_ARGS --include="*.php" -E "set_transient[[:space:]]*\(" $PATHS 2>/dev/null || true)
TRANSIENT_ABUSE=false
TRANSIENT_ISSUES=""
TRANSIENT_FINDING_COUNT=0

if [ -n "$TRANSIENT_MATCHES" ]; then
  while IFS= read -r match; do
    # Check if line contains a third parameter (expiration)
    # set_transient( $key, $value, $expiration ) - needs 3 params
    # Count commas in the line - should have at least 2 for proper usage
    comma_count=$(echo "$match" | tr -cd ',' | wc -c)
	    if [ "$comma_count" -lt 2 ]; then
	      file=$(echo "$match" | cut -d: -f1)
	      line_num=$(echo "$match" | cut -d: -f2)
	      code=$(echo "$match" | cut -d: -f3-)
	      if ! should_suppress_finding "transient-no-expiration" "$file"; then
	        TRANSIENT_ISSUES="${TRANSIENT_ISSUES}${match}"$'\n'
	        add_json_finding "transient-no-expiration" "warning" "MEDIUM" "$file" "$line_num" "Transient may be missing expiration parameter" "$code"
	        TRANSIENT_ABUSE=true
	        ((TRANSIENT_FINDING_COUNT++)) || true
	      fi
	    fi
  done <<< "$TRANSIENT_MATCHES"
fi

if [ "$TRANSIENT_ABUSE" = true ]; then
  text_echo "${YELLOW}  ⚠ WARNING - Transients may be missing expiration parameter:${NC}"
  if [ "$OUTPUT_FORMAT" = "text" ]; then
    echo "$TRANSIENT_ISSUES" | head -5
  fi
  ((WARNINGS++))
  add_json_check "Transients without expiration" "MEDIUM" "failed" "$TRANSIENT_FINDING_COUNT"
else
  text_echo "${GREEN}  ✓ Passed${NC}"
  add_json_check "Transients without expiration" "MEDIUM" "passed" 0
fi
text_echo ""

# Script/style versioning with time() - prevents browser caching
text_echo "${BLUE}▸ Script/style versioning with time() ${YELLOW}[MEDIUM]${NC}"
SCRIPT_TIME_MATCHES=$(grep -rHn $EXCLUDE_ARGS --include="*.php" \
  -E "wp_(register|enqueue)_(script|style)[[:space:]]*\([^)]*,[[:space:]]*time[[:space:]]*\(" \
  $PATHS 2>/dev/null || true)
SCRIPT_TIME_ISSUES=false
SCRIPT_TIME_FINDING_COUNT=0

if [ -n "$SCRIPT_TIME_MATCHES" ]; then
  while IFS= read -r match; do
    [ -z "$match" ] && continue
    file=$(echo "$match" | cut -d: -f1)
    line_num=$(echo "$match" | cut -d: -f2)
    code=$(echo "$match" | cut -d: -f3-)
    if ! should_suppress_finding "script-versioning-time" "$file"; then
      text_echo "  $file:$line_num - using time() as version"
      add_json_finding "script-versioning-time" "warning" "MEDIUM" "$file" "$line_num" "Using time() as script/style version prevents browser caching - use plugin version instead" "$code"
      SCRIPT_TIME_ISSUES=true
      ((SCRIPT_TIME_FINDING_COUNT++)) || true
    fi
  done <<< "$SCRIPT_TIME_MATCHES"
fi

if [ "$SCRIPT_TIME_ISSUES" = true ]; then
  text_echo "${YELLOW}  ⚠ WARNING - Scripts/styles using time() as version:${NC}"
  ((WARNINGS++))
  add_json_check "Script/style versioning with time()" "MEDIUM" "failed" "$SCRIPT_TIME_FINDING_COUNT"
else
  text_echo "${GREEN}  ✓ Passed${NC}"
  add_json_check "Script/style versioning with time()" "MEDIUM" "passed" 0
fi
text_echo ""

# file_get_contents() for external URLs - Security & Performance Issue
text_echo "${BLUE}▸ file_get_contents() with external URLs ${RED}[HIGH]${NC}"
FILE_GET_CONTENTS_MATCHES=$(grep -rHn $EXCLUDE_ARGS --include="*.php" \
  -E "file_get_contents[[:space:]]*\([[:space:]]*['\"]https?://" \
  $PATHS 2>/dev/null || true)

# Also check for file_get_contents with variables (potential URLs)
FILE_GET_CONTENTS_VAR=$(grep -rHn $EXCLUDE_ARGS --include="*.php" \
  -E "file_get_contents[[:space:]]*\([[:space:]]*\\\$" \
  $PATHS 2>/dev/null || true)

FILE_GET_CONTENTS_ISSUES=""
FILE_GET_CONTENTS_FINDING_COUNT=0

# Check direct URL usage
if [ -n "$FILE_GET_CONTENTS_MATCHES" ]; then
  while IFS= read -r match; do
    [ -z "$match" ] && continue
    file=$(echo "$match" | cut -d: -f1)
    line_num=$(echo "$match" | cut -d: -f2)
    code=$(echo "$match" | cut -d: -f3-)
    if ! should_suppress_finding "file-get-contents-url" "$file"; then
      FILE_GET_CONTENTS_ISSUES="${FILE_GET_CONTENTS_ISSUES}${match}"$'\n'
      add_json_finding "file-get-contents-url" "error" "HIGH" "$file" "$line_num" "file_get_contents() with URL is insecure and slow - use wp_remote_get() instead" "$code"
      ((ERRORS++)) || true
      ((FILE_GET_CONTENTS_FINDING_COUNT++)) || true
    fi
  done <<< "$FILE_GET_CONTENTS_MATCHES"
fi

# Check variable usage (potential URLs)
if [ -n "$FILE_GET_CONTENTS_VAR" ]; then
  while IFS= read -r match; do
    [ -z "$match" ] && continue
    file=$(echo "$match" | cut -d: -f1)
    line_num=$(echo "$match" | cut -d: -f2)
    code=$(echo "$match" | cut -d: -f3-)

    # Check if this looks like a URL variable (contains 'url', 'uri', 'endpoint', 'api')
    if echo "$code" | grep -qiE '\$(url|uri|endpoint|api|remote|external|http)'; then
      if ! should_suppress_finding "file-get-contents-url" "$file"; then
        FILE_GET_CONTENTS_ISSUES="${FILE_GET_CONTENTS_ISSUES}${match}"$'\n'
        add_json_finding "file-get-contents-url" "error" "HIGH" "$file" "$line_num" "file_get_contents() with potential URL variable - use wp_remote_get() instead" "$code"
        ((ERRORS++)) || true
        ((FILE_GET_CONTENTS_FINDING_COUNT++)) || true
      fi
    fi
  done <<< "$FILE_GET_CONTENTS_VAR"
fi

if [ "$FILE_GET_CONTENTS_FINDING_COUNT" -gt 0 ]; then
  text_echo "${RED}  ✗ FAILED - file_get_contents() used for external URLs:${NC}"
  if [ "$OUTPUT_FORMAT" = "text" ] && [ -n "$FILE_GET_CONTENTS_ISSUES" ]; then
    echo "$FILE_GET_CONTENTS_ISSUES" | head -5
  fi
  add_json_check "file_get_contents with external URLs" "HIGH" "failed" "$FILE_GET_CONTENTS_FINDING_COUNT"
else
  text_echo "${GREEN}  ✓ Passed${NC}"
  add_json_check "file_get_contents with external URLs" "HIGH" "passed" 0
fi
text_echo ""

# HTTP requests without timeout - Can hang entire site
text_echo "${BLUE}▸ HTTP requests without timeout ${YELLOW}[MEDIUM]${NC}"
HTTP_NO_TIMEOUT_MATCHES=$(grep -rHn $EXCLUDE_ARGS --include="*.php" \
  -E "wp_remote_(get|post|request|head)[[:space:]]*\(" \
  $PATHS 2>/dev/null || true)

HTTP_NO_TIMEOUT_ISSUES=""
HTTP_NO_TIMEOUT_FINDING_COUNT=0

if [ -n "$HTTP_NO_TIMEOUT_MATCHES" ]; then
  while IFS= read -r match; do
    [ -z "$match" ] && continue
    file=$(echo "$match" | cut -d: -f1)
    line_num=$(echo "$match" | cut -d: -f2)
    code=$(echo "$match" | cut -d: -f3-)

    # Check if line number is numeric
    if ! [[ "$line_num" =~ ^[0-9]+$ ]]; then
      continue
    fi

    # Look at next 5 lines for 'timeout' parameter (inline args)
    # But only within the same statement (until we hit a semicolon)
    start_line=$line_num
    end_line=$((line_num + 5))
    has_timeout=false

    # Extract the statement (until semicolon) from next 5 lines
    statement=$(sed -n "${start_line},${end_line}p" "$file" 2>/dev/null | \
                awk '/;/{print; exit} {print}')

    # Check if timeout is present in THIS statement only
    if echo "$statement" | grep -qE "'timeout'|\"timeout\""; then
      has_timeout=true
    fi

    # If not found inline, check if using $args variable and look backward for its definition
    if [ "$has_timeout" = false ]; then
      # Check if the call uses a variable (e.g., $args, $options, $params)
      if echo "$code" | grep -qE '\$[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\)'; then
        # Extract variable name (e.g., $args from "wp_remote_get($url, $args)")
        var_name=$(echo "$code" | grep -oE '\$[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\)' | sed 's/[[:space:]]*)//' | head -1)

        if [ -n "$var_name" ]; then
          # Look backward up to 20 lines for variable definition with timeout
          backward_start=$((line_num - 20))
          [ "$backward_start" -lt 1 ] && backward_start=1

          # Check if variable is defined with 'timeout' in previous lines
          if sed -n "${backward_start},${line_num}p" "$file" 2>/dev/null | \
             grep -A 10 "^[[:space:]]*${var_name}[[:space:]]*=" | \
             grep -qE "'timeout'|\"timeout\""; then
            has_timeout=true
          fi
        fi
      fi
    fi

    # Only flag if no timeout found (inline or in variable definition)
    if [ "$has_timeout" = false ]; then
      if ! should_suppress_finding "http-no-timeout" "$file"; then
        HTTP_NO_TIMEOUT_ISSUES="${HTTP_NO_TIMEOUT_ISSUES}${match}"$'\n'
        add_json_finding "http-no-timeout" "warning" "MEDIUM" "$file" "$line_num" "HTTP request without explicit timeout can hang site if remote server doesn't respond" "$code"
        ((WARNINGS++)) || true
        ((HTTP_NO_TIMEOUT_FINDING_COUNT++)) || true
      fi
    fi
  done <<< "$HTTP_NO_TIMEOUT_MATCHES"
fi

if [ "$HTTP_NO_TIMEOUT_FINDING_COUNT" -gt 0 ]; then
  text_echo "${YELLOW}  ⚠ WARNING - HTTP requests without timeout:${NC}"
  if [ "$OUTPUT_FORMAT" = "text" ] && [ -n "$HTTP_NO_TIMEOUT_ISSUES" ]; then
    echo "$HTTP_NO_TIMEOUT_ISSUES" | head -5
  fi
  add_json_check "HTTP requests without timeout" "MEDIUM" "failed" "$HTTP_NO_TIMEOUT_FINDING_COUNT"
else
  text_echo "${GREEN}  ✓ Passed${NC}"
  add_json_check "HTTP requests without timeout" "MEDIUM" "passed" 0
fi
text_echo ""

	# Evaluate baseline entries for staleness before computing exit code / JSON
	check_stale_entries

	# Generate baseline file if requested
	generate_baseline_file

	# Determine exit code
EXIT_CODE=0
if [ "$ERRORS" -gt 0 ]; then
  EXIT_CODE=1
elif [ "$STRICT" = "true" ] && [ "$WARNINGS" -gt 0 ]; then
  EXIT_CODE=1
fi

# Output based on format
if [ "$OUTPUT_FORMAT" = "json" ]; then
  JSON_OUTPUT=$(output_json "$EXIT_CODE")
  echo "$JSON_OUTPUT"

  # Generate HTML report if running locally (not in GitHub Actions)
  if [ -z "$GITHUB_ACTIONS" ]; then
    # Create reports directory if it doesn't exist
    REPORTS_DIR="$PLUGIN_DIR/reports"
    mkdir -p "$REPORTS_DIR"

    # Generate timestamped HTML report filename
    REPORT_TIMESTAMP=$(timestamp_filename)
    HTML_REPORT="$REPORTS_DIR/$REPORT_TIMESTAMP.html"

    # Generate the HTML report
    if generate_html_report "$JSON_OUTPUT" "$HTML_REPORT"; then
      echo "" >&2
      echo "📊 HTML Report: $HTML_REPORT" >&2

      # Auto-open in browser (macOS/Linux)
      if command -v open &> /dev/null; then
        open "$HTML_REPORT" 2>/dev/null || true
      elif command -v xdg-open &> /dev/null; then
        xdg-open "$HTML_REPORT" 2>/dev/null || true
      fi
    fi
  fi
else
  # Summary (text mode)
  text_echo "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  text_echo "${BLUE}  SUMMARY${NC}"
  text_echo "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  text_echo ""
  text_echo "  Errors:   ${RED}$ERRORS${NC}"
  text_echo "  Warnings: ${YELLOW}$WARNINGS${NC}"
  text_echo ""

  if [ "$ERRORS" -gt 0 ]; then
    text_echo "${RED}✗ Check failed with $ERRORS error type(s)${NC}"
  elif [ "$STRICT" = "true" ] && [ "$WARNINGS" -gt 0 ]; then
    text_echo "${YELLOW}✗ Check failed in strict mode with $WARNINGS warning type(s)${NC}"
  else
    text_echo "${GREEN}✓ All critical checks passed!${NC}"
  fi
fi

exit $EXIT_CODE
