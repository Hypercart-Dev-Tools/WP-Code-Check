#!/usr/bin/env bash
#
# WP Code Check by Hypercart - Performance Analysis Script
# Version: 1.0.73
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
#   --severity-config <path> Use custom severity levels from JSON config file
#   --generate-baseline      Generate .hcc-baseline from current findings
#   --baseline <path>        Use custom baseline file path (default: .hcc-baseline)
#   --ignore-baseline        Ignore baseline file even if present
#   --help                   Show this help message

# Note: We intentionally do NOT use 'set -e' here because:
# 1. ((var++)) returns exit code 1 when var is 0, which would cause immediate exit
# 2. grep returning no matches (exit 1) is expected behavior we handle explicitly
# 3. We manage our own error tracking with ERRORS/WARNINGS counters

# Directories and shared libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
# REPO_ROOT points to dist/ directory (not repository root)
# This ensures templates are loaded from dist/TEMPLATES/ where they belong
# Changed from ../.. to .. on 2025-12-31 to fix template loading
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=dist/bin/lib/colors.sh
source "$LIB_DIR/colors.sh"
# shellcheck source=dist/bin/lib/common-helpers.sh
source "$LIB_DIR/common-helpers.sh"
# shellcheck source=dist/lib/pattern-loader.sh
source "$REPO_ROOT/lib/pattern-loader.sh"

# ============================================================
# VERSION - SINGLE SOURCE OF TRUTH
# ============================================================
# This is the ONLY place the version number should be defined.
# All other references (logs, JSON, banners) use this variable.
# Update this ONE line when bumping versions - never hardcode elsewhere.
SCRIPT_VERSION="1.0.73"

# Defaults
PATHS="."
STRICT=false
VERBOSE=false
ENABLE_LOGGING=true
OUTPUT_FORMAT="text"  # text or json
CONTEXT_LINES=3       # Number of lines to show before/after findings (0 to disable)
# Note: 'tests' exclusion is dynamically removed when --paths targets a tests directory
EXCLUDE_DIRS="vendor node_modules .git tests"

# Severity configuration
SEVERITY_CONFIG_FILE=""  # Path to custom severity config (empty = use factory defaults)
SEVERITY_CONFIG_LOADED=false  # Track if config has been loaded

# Baseline configuration
BASELINE_FILE=".hcc-baseline"
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

# DRY violations collection (aggregated patterns)
declare -a DRY_VIOLATIONS=()
DRY_VIOLATIONS_COUNT=0

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
    --severity-config)
      SEVERITY_CONFIG_FILE="$2"
      if [ ! -f "$SEVERITY_CONFIG_FILE" ]; then
        echo "Error: Severity config file not found: $SEVERITY_CONFIG_FILE"
        exit 1
      fi
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
    if [ -d "$scan_path" ]; then
      scan_path="$(cd "$scan_path" 2>/dev/null && pwd)" || scan_path="$scan_path"
    elif [ -f "$scan_path" ]; then
      # For files, resolve the directory and append the filename
      local dir_part=$(dirname "$scan_path")
      local file_part=$(basename "$scan_path")
      scan_path="$(cd "$dir_part" 2>/dev/null && pwd)/$file_part" || scan_path="$scan_path"
    fi
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
    elif echo "$scan_path" | grep -q "/tests/fixtures/\|/test-fixtures/"; then
      # Detect test fixture files
      project_type="fixture"
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

# ============================================================================
# Severity Configuration Functions
# ============================================================================

# Get severity level for a rule ID
# Returns custom level if set in config file, otherwise returns fallback
# This function queries the JSON config file directly (Bash 3.2 compatible)
get_severity() {
  local rule_id="$1"
  local fallback="${2:-MEDIUM}"  # Default fallback if not found
  local severity=""

  # If custom config is specified, try to get severity from it
  if [ -n "$SEVERITY_CONFIG_FILE" ] && [ -f "$SEVERITY_CONFIG_FILE" ]; then
    severity=$(jq -r ".severity_levels[\"$rule_id\"].level // empty" "$SEVERITY_CONFIG_FILE" 2>/dev/null)
  fi

  # If not found in custom config, try factory defaults
  if [ -z "$severity" ] && [ -f "$REPO_ROOT/config/severity-levels.json" ]; then
    severity=$(jq -r ".severity_levels[\"$rule_id\"].level // empty" "$REPO_ROOT/config/severity-levels.json" 2>/dev/null)
  fi

  # If still not found, use fallback
  if [ -z "$severity" ]; then
    severity="$fallback"
  fi

  echo "$severity"
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
        # Map project type to display label
        type_display_log="$PROJECT_TYPE_LOG"
        case "$PROJECT_TYPE_LOG" in
          plugin) type_display_log="WordPress Plugin" ;;
          theme) type_display_log="WordPress Theme" ;;
          fixture) type_display_log="Fixture Test" ;;
          unknown) type_display_log="Unknown" ;;
        esac
        echo "Type:             $type_display_log"
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
      echo "Local Time:      $(timestamp_local)"
        echo "Script Version:   $SCRIPT_VERSION"
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
      echo "Local Time:     $(timestamp_local)"
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

# Add a DRY violation to the collection
# Usage: add_dry_violation "pattern_title" "severity" "duplicated_string" "file_count" "total_count" "locations_json"
add_dry_violation() {
  local pattern_title="$1"
  local severity="$2"
  local duplicated_string="$3"
  local file_count="$4"
  local total_count="$5"
  local locations_json="$6"

  local violation=$(cat <<EOF
{"pattern":"$(json_escape "$pattern_title")","severity":"$severity","duplicated_string":"$(json_escape "$duplicated_string")","file_count":$file_count,"total_count":$total_count,"locations":$locations_json}
EOF
)
  DRY_VIOLATIONS+=("$violation")
  ((DRY_VIOLATIONS_COUNT++)) || true
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

  # Build DRY violations array
  local dry_violations_json=""
  first=true
  for violation in "${DRY_VIOLATIONS[@]}"; do
    if [ "$first" = true ]; then
      dry_violations_json="$violation"
      first=false
    else
      dry_violations_json="$dry_violations_json,$violation"
    fi
  done

    cat <<EOF
{
  "version": "$SCRIPT_VERSION",
  "timestamp": "$timestamp",
  "project": $project_info,
  "paths_scanned": "$(json_escape "$PATHS")",
  "strict_mode": $STRICT,
  "summary": {
    "total_errors": $ERRORS,
    "total_warnings": $WARNINGS,
    "dry_violations": $DRY_VIOLATIONS_COUNT,
    "files_analyzed": $files_analyzed,
    "lines_of_code": $lines_of_code,
    "baselined": $BASELINED,
    "stale_baseline": $STALE_ENTRIES,
    "exit_code": $exit_code
  },
  "fixture_validation": {
    "status": "$FIXTURE_VALIDATION_STATUS",
    "passed": $FIXTURE_VALIDATION_PASSED,
    "failed": $FIXTURE_VALIDATION_FAILED,
    "message": "Detection patterns verified against ${FIXTURE_VALIDATION_PASSED} test fixtures"
  },
  "findings": [$findings_json],
  "checks": [$checks_json],
  "dry_violations": [$dry_violations_json]
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
  local dry_violations_count=$(echo "$json_data" | jq '.dry_violations | length')

  # Extract fixture validation info
  local fixture_status=$(echo "$json_data" | jq -r '.fixture_validation.status // "not_run"')
  local fixture_passed=$(echo "$json_data" | jq -r '.fixture_validation.passed // 0')
  local fixture_failed=$(echo "$json_data" | jq -r '.fixture_validation.failed // 0')

  # Set fixture status class and text for HTML
  local fixture_status_class="skipped"
  local fixture_status_text="Fixtures: N/A"
  if [ "$fixture_status" = "passed" ]; then
    fixture_status_class="passed"
    fixture_status_text="✓ Detection Verified (${fixture_passed} fixtures)"
  elif [ "$fixture_status" = "failed" ]; then
    fixture_status_class="failed"
    fixture_status_text="⚠ Detection Warning (${fixture_failed}/${fixture_passed} failed)"
  elif [ "$fixture_status" = "skipped" ]; then
    fixture_status_class="skipped"
    fixture_status_text="○ Fixtures Skipped"
  fi

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
    # Map project type to display label
    local type_display="$project_type"
    case "$project_type" in
      plugin) type_display="WordPress Plugin" ;;
      theme) type_display="WordPress Theme" ;;
      fixture) type_display="Fixture Test" ;;
      unknown) type_display="Unknown" ;;
    esac

    project_info_html="<div style='font-size: 1.1em; font-weight: 600; margin-bottom: 5px;'>PROJECT INFORMATION</div>"
    project_info_html+="<div>Name: $project_name</div>"
    if [ -n "$project_version" ]; then
      project_info_html+="<div>Version: $project_version</div>"
    fi
    project_info_html+="<div>Type: $type_display</div>"
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

  # Generate DRY violations HTML
  local dry_violations_html=""
  if [ "$dry_violations_count" -gt 0 ]; then
    dry_violations_html=$(echo "$json_data" | jq -r '.dry_violations[] |
      "<div class=\"finding medium\">
        <div class=\"finding-header\">
          <div class=\"finding-title\">🔄 \(.duplicated_string)</div>
          <span class=\"badge medium\">MEDIUM</span>
        </div>
        <div class=\"finding-details\">
          <div style=\"margin-bottom: 10px;\">
            <strong>Pattern:</strong> \(.pattern)<br>
            <strong>Duplicated String:</strong> <code>\(.duplicated_string)</code><br>
            <strong>Files:</strong> \(.file_count) files | <strong>Total Occurrences:</strong> \(.total_count)
          </div>
          <div style=\"margin-top: 10px;\">
            <strong>Locations:</strong>
            <ul style=\"margin: 5px 0 0 20px; padding: 0;\">
              \(.locations | map("<li style=\"font-family: monospace; font-size: 0.9em;\">\(.file):\(.line)</li>") | join(""))
            </ul>
          </div>
        </div>
      </div>"' | tr '\n' ' ')
  else
    dry_violations_html="<p style='text-align: center; color: #6c757d; padding: 20px;'>No DRY violations detected. Great job! 🎉</p>"
  fi

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
  html_content="${html_content//\{\{DRY_VIOLATIONS_COUNT\}\}/$dry_violations_count}"
  html_content="${html_content//\{\{BASELINED\}\}/$baselined}"
  html_content="${html_content//\{\{STALE_BASELINE\}\}/$stale_baseline}"
  html_content="${html_content//\{\{EXIT_CODE\}\}/$exit_code}"
  html_content="${html_content//\{\{STRICT_MODE\}\}/$strict_mode}"
  html_content="${html_content//\{\{STATUS_CLASS\}\}/$status_class}"
  html_content="${html_content//\{\{STATUS_MESSAGE\}\}/$status_message}"
  html_content="${html_content//\{\{FINDINGS_COUNT\}\}/$findings_count}"
  html_content="${html_content//\{\{FINDINGS_HTML\}\}/$findings_html}"
  html_content="${html_content//\{\{DRY_VIOLATIONS_HTML\}\}/$dry_violations_html}"
  html_content="${html_content//\{\{CHECKS_HTML\}\}/$checks_html}"
  html_content="${html_content//\{\{FIXTURE_STATUS_CLASS\}\}/$fixture_status_class}"
  html_content="${html_content//\{\{FIXTURE_STATUS_TEXT\}\}/$fixture_status_text}"

  # Write to output file
  echo "$html_content" > "$output_file"

  return 0
}

# ============================================================
# Fixture Validation - Proof of Detection
# ============================================================
# Runs quick validation against built-in test fixtures to verify
# detection patterns are working correctly. This provides "proof
# of detection" in every report.

# Global fixture validation results
FIXTURE_VALIDATION_PASSED=0
FIXTURE_VALIDATION_FAILED=0
FIXTURE_VALIDATION_STATUS="not_run"

# Validate a single fixture file using direct pattern matching
# This is a lightweight check - just verifies key patterns are detected
# Usage: validate_single_fixture "fixture_file" "pattern" expected_count
validate_single_fixture() {
  local fixture_file="$1"
  local pattern="$2"
  local expected_count="$3"

  # Count matches using grep
  local actual_count
  actual_count=$(grep -c "$pattern" "$fixture_file" 2>/dev/null || echo "0")

  [ "${NEOCHROME_DEBUG:-}" = "1" ] && echo "[DEBUG] $fixture_file: pattern='$pattern' expected=$expected_count actual=$actual_count" >&2

  if [ "$actual_count" -ge "$expected_count" ]; then
    return 0  # Passed
  else
    return 1  # Failed
  fi
}

# Run fixture validation suite
# Uses direct pattern matching (no subprocesses) to verify detection works
# Returns: Sets FIXTURE_VALIDATION_PASSED, FIXTURE_VALIDATION_FAILED, FIXTURE_VALIDATION_STATUS
run_fixture_validation() {
  local fixtures_dir="$SCRIPT_DIR/../tests/fixtures"

  # Check if fixtures directory exists
  if [ ! -d "$fixtures_dir" ]; then
    FIXTURE_VALIDATION_STATUS="skipped"
    return 0
  fi

  FIXTURE_VALIDATION_PASSED=0
  FIXTURE_VALIDATION_FAILED=0

  # Quick pattern checks against fixtures
  # Format: fixture_file:pattern:expected_min_count
  # These verify that our detection patterns actually find issues in known-bad code
  local -a checks=(
    # antipatterns.php should have unbounded queries (SELECT without LIMIT)
    "antipatterns.php:get_results:1"
    # antipatterns.php should have N+1 query patterns (get_post_meta in loop)
    "antipatterns.php:get_post_meta:1"
    # file-get-contents-url.php should have external URL calls
    "file-get-contents-url.php:file_get_contents:1"
    # clean-code.php should have bounded queries (posts_per_page set)
    "clean-code.php:posts_per_page:1"
  )

  for check_spec in "${checks[@]}"; do
    local fixture_file pattern expected_count
    IFS=':' read -r fixture_file pattern expected_count <<< "$check_spec"

    if [ -f "$fixtures_dir/$fixture_file" ]; then
      if validate_single_fixture "$fixtures_dir/$fixture_file" "$pattern" "$expected_count"; then
        ((FIXTURE_VALIDATION_PASSED++))
      else
        ((FIXTURE_VALIDATION_FAILED++))
      fi
    fi
  done

  # Set overall status
  if [ "$FIXTURE_VALIDATION_FAILED" -eq 0 ] && [ "$FIXTURE_VALIDATION_PASSED" -gt 0 ]; then
    FIXTURE_VALIDATION_STATUS="passed"
  elif [ "$FIXTURE_VALIDATION_PASSED" -eq 0 ] && [ "$FIXTURE_VALIDATION_FAILED" -eq 0 ]; then
    FIXTURE_VALIDATION_STATUS="skipped"
  else
    FIXTURE_VALIDATION_STATUS="failed"
  fi
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

  # Validate lineno is numeric (skip binary file matches, etc.)
  if ! [[ "$lineno" =~ ^[0-9]+$ ]]; then
    echo -e "${BOLD}${match}${NC}"
    return
  fi

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
	tmp="$(mktemp 2>/dev/null || echo "/tmp/hcc-baseline.$$")"

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
		echo "# .hcc-baseline"
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

# Process aggregated pattern (DRY violations)
# Usage: process_aggregated_pattern "pattern_file"
process_aggregated_pattern() {
  local pattern_file="$1"
  local debug_log="/tmp/wp-code-check-debug.log"

  # Load pattern metadata
  if ! load_pattern "$pattern_file"; then
    echo "[DEBUG] Failed to load pattern: $pattern_file" >> "$debug_log"
    return 1
  fi

  # Debug: Log loaded pattern info
  echo "[DEBUG] ===========================================" >> "$debug_log"
  echo "[DEBUG] Processing pattern: $pattern_file" >> "$debug_log"
  echo "[DEBUG] Pattern ID: $pattern_id" >> "$debug_log"
  echo "[DEBUG] Pattern Title: $pattern_title" >> "$debug_log"
  echo "[DEBUG] Pattern Enabled: $pattern_enabled" >> "$debug_log"
  echo "[DEBUG] Pattern Search (length=${#pattern_search}): [$pattern_search]" >> "$debug_log"
  echo "[DEBUG] ===========================================" >> "$debug_log"

  # Skip if pattern is disabled
  if [ "$pattern_enabled" != "true" ]; then
    echo "[DEBUG] Pattern disabled, skipping" >> "$debug_log"
    return 0
  fi

  # Check if pattern_search is empty
  if [ -z "$pattern_search" ]; then
    echo "[DEBUG] ERROR: pattern_search is EMPTY!" >> "$debug_log"
    text_echo "  ${RED}→ Pattern: ${NC}"
    text_echo "  ${RED}→ Found 0${NC}"
    text_echo "${RED}0 raw matches${NC}"
    return 1
  fi

  # Extract aggregation settings from JSON
  local min_files=$(grep '"min_distinct_files"' "$pattern_file" | sed 's/.*:[[:space:]]*\([0-9]*\).*/\1/')
  local min_matches=$(grep '"min_total_matches"' "$pattern_file" | sed 's/.*:[[:space:]]*\([0-9]*\).*/\1/')
  local capture_group=$(grep '"capture_group"' "$pattern_file" | sed 's/.*:[[:space:]]*\([0-9]*\).*/\1/')

  # Defaults
  [ -z "$min_files" ] && min_files=3
  [ -z "$min_matches" ] && min_matches=6
  [ -z "$capture_group" ] && capture_group=2

  echo "[DEBUG] Aggregation settings: min_files=$min_files, min_matches=$min_matches, capture_group=$capture_group" >> "$debug_log"

  # Create temp files for aggregation
  local temp_matches=$(mktemp)

  # Run grep to find all matches using the pattern's search pattern
  # Note: pattern_search is set by load_pattern
  # SAFEGUARD: "$PATHS" MUST be quoted - paths with spaces will break otherwise
  echo "[DEBUG] Running grep with pattern: $pattern_search" >> "$debug_log"
  echo "[DEBUG] Paths: $PATHS" >> "$debug_log"
  local matches=$(grep -rHn $EXCLUDE_ARGS --include="*.php" -E "$pattern_search" "$PATHS" 2>/dev/null || true)
  local match_count=$(echo "$matches" | grep -c . || echo "0")
  echo "[DEBUG] Found $match_count raw matches" >> "$debug_log"

  # Extract captured groups and aggregate
  if [ -n "$matches" ]; then
    while IFS= read -r match; do
      [ -z "$match" ] && continue

      local file=$(echo "$match" | cut -d: -f1)
      local line=$(echo "$match" | cut -d: -f2)
      local code=$(echo "$match" | cut -d: -f3-)

      # Extract the captured string using grep and sed
      # We use a simplified sed pattern that extracts the content between quotes
      # This works for most DRY patterns which capture string literals
      local captured=$(echo "$code" | grep -oE "$pattern_search" | sed -E "s/.*['\"]([a-z0-9_]+)['\"].*/\1/" | head -1)

      if [ -n "$captured" ]; then
        # Escape pipe characters in the captured string for safe storage
        local escaped_captured=$(echo "$captured" | sed 's/|/\\|/g')
        echo "$escaped_captured|$file|$line" >> "$temp_matches"
      fi
    done <<< "$matches"

    # Aggregate by captured string
    if [ -f "$temp_matches" ] && [ -s "$temp_matches" ]; then
      local unique_strings=$(cut -d'|' -f1 "$temp_matches" | sort -u)

      while IFS= read -r string; do
        [ -z "$string" ] && continue

        # Unescape the string for comparison
        local unescaped_string=$(echo "$string" | sed 's/\\|/|/g')

        # Count files and total occurrences (need to escape for grep)
        local grep_pattern="^$(echo "$string" | sed 's/\[/\\[/g; s/\]/\\]/g; s/\./\\./g')|"
        local file_count=$(grep "$grep_pattern" "$temp_matches" | cut -d'|' -f2 | sort -u | wc -l | tr -d ' ')
        local total_count=$(grep "$grep_pattern" "$temp_matches" | wc -l | tr -d ' ')

        # Apply thresholds
        if [ "$file_count" -ge "$min_files" ] && [ "$total_count" -ge "$min_matches" ]; then
          # Build locations JSON array
          local locations_json="["
          local first_loc=true
          while IFS='|' read -r str file line; do
            if [ "$str" = "$string" ]; then
              if [ "$first_loc" = false ]; then
                locations_json+=","
              fi
              locations_json+="{\"file\":\"$(json_escape "$file")\",\"line\":$line}"
              first_loc=false
            fi
          done < "$temp_matches"
          locations_json+="]"

          # Add to DRY violations
          add_dry_violation "$pattern_title" "$pattern_severity" "$unescaped_string" "$file_count" "$total_count" "$locations_json"
        fi
      done <<< "$unique_strings"
    fi
  fi

  # Cleanup
  rm -f "$temp_matches"
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
			text_echo "${BLUE}  WP Code Check by Hypercart - Performance Analyzer v$SCRIPT_VERSION${NC}"
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

# Run fixture validation (proof of detection)
# This runs quietly in the background and sets global variables
run_fixture_validation

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

  # Validate lineno is numeric before arithmetic operations
  if ! [[ "$lineno" =~ ^[0-9]+$ ]]; then
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

  # SAFEGUARD: "$PATHS" MUST be quoted - paths with spaces will break otherwise (see SAFEGUARDS.md)
  if result=$(grep -rHn $EXCLUDE_ARGS $include_args $patterns "$PATHS" 2>/dev/null); then
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

	      # Validate lineno is numeric (skip binary file matches, etc.)
	      if ! [[ "$lineno" =~ ^[0-9]+$ ]]; then
	        continue
	      fi

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
run_check "ERROR" "$(get_severity "spo-001-debug-code" "CRITICAL")" "Debug code in production" "spo-001-debug-code" \
  "-E console\\.(log|error|warn)[[:space:]]*\\(" \
  "-e debugger;" \
  "-E alert[[:space:]]*\\(" \
  "-E var_dump[[:space:]]*\\(" \
  "-E print_r[[:space:]]*\\(" \
  "-E error_log[[:space:]]*\\("
unset OVERRIDE_GREP_INCLUDE
text_echo ""

# ============================================================================
# HCC RULES - High-Confidence Checks from KISS Plugin Quick Search Audit
# Based on: AUDIT-2025-12-31.md findings
# ============================================================================

# HCC-001: Sensitive data in localStorage/sessionStorage
# Detects when sensitive plugin/user/admin data is stored in browser storage
# that is accessible to front-end scripts via browser console.
# This catches patterns like: localStorage.setItem('pqs_plugin_cache', ...)
OVERRIDE_GREP_INCLUDE="--include=*.js --include=*.jsx --include=*.ts --include=*.tsx"
run_check "ERROR" "$(get_severity "hcc-001-localstorage-exposure" "CRITICAL")" "Sensitive data in localStorage/sessionStorage" "hcc-001-localstorage-exposure" \
  "-E localStorage\\.setItem[[:space:]]*\\([^)]*plugin" \
  "-E localStorage\\.setItem[[:space:]]*\\([^)]*cache" \
  "-E localStorage\\.setItem[[:space:]]*\\([^)]*user" \
  "-E localStorage\\.setItem[[:space:]]*\\([^)]*admin" \
  "-E localStorage\\.setItem[[:space:]]*\\([^)]*settings" \
  "-E sessionStorage\\.setItem[[:space:]]*\\([^)]*plugin" \
  "-E sessionStorage\\.setItem[[:space:]]*\\([^)]*cache" \
  "-E sessionStorage\\.setItem[[:space:]]*\\([^)]*user" \
  "-E sessionStorage\\.setItem[[:space:]]*\\([^)]*admin" \
  "-E sessionStorage\\.setItem[[:space:]]*\\([^)]*settings"
unset OVERRIDE_GREP_INCLUDE

# HCC-002: Serialization of sensitive objects to client storage
# Detects when objects are being serialized (JSON.stringify) and stored in
# browser storage, which often contains sensitive metadata (versions, paths, settings).
# This catches patterns like: localStorage.setItem('key', JSON.stringify(obj))
OVERRIDE_GREP_INCLUDE="--include=*.js --include=*.jsx --include=*.ts --include=*.tsx"
run_check "ERROR" "$(get_severity "hcc-002-client-serialization" "CRITICAL")" "Serialization of objects to client storage" "hcc-002-client-serialization" \
  "-E localStorage\\.setItem[[:space:]]*\\([^)]*JSON\\.stringify" \
  "-E sessionStorage\\.setItem[[:space:]]*\\([^)]*JSON\\.stringify" \
  "-E localStorage\\[[^]]*\\][[:space:]]*=[[:space:]]*JSON\\.stringify"
unset OVERRIDE_GREP_INCLUDE
text_echo ""

# HCC-008: Unsafe RegExp construction with user input
# Detects RegExp constructors that concatenate variables (likely user input) without escaping.
# This can lead to ReDoS attacks or unexpected regex behavior.
# Catches patterns like: new RegExp('\\b' + query + '\\b') or RegExp(`pattern${userInput}`)
# Note: Uses single -E with alternation (|) for BSD grep compatibility
OVERRIDE_GREP_INCLUDE="--include=*.js --include=*.jsx --include=*.ts --include=*.tsx --include=*.php"
run_check "ERROR" "$(get_severity "hcc-008-unsafe-regexp" "MEDIUM")" "User input in RegExp without escaping (HCC-008)" "hcc-008-unsafe-regexp" \
  "-E ((new[[:space:]]+)?RegExp[[:space:]]*\\([^)]*[[:space:]]\\+[[:space:]])|((new[[:space:]]+)?RegExp.*\\$\\{)"
unset OVERRIDE_GREP_INCLUDE
text_echo ""

# Direct superglobal manipulation (assignment)
run_check "ERROR" "$(get_severity "spo-002-superglobals" "HIGH")" "Direct superglobal manipulation" "spo-002-superglobals" \
  "-E unset\\(\\$_(GET|POST|REQUEST|COOKIE)\\[" \
  "-E \\$_(GET|POST|REQUEST)[[:space:]]*=" \
  "-E \\$_(GET|POST|REQUEST|COOKIE)\\[[^]]*\\][[:space:]]*="

# Unsanitized superglobal read (reading $_GET/$_POST without sanitization)
# PATTERN LIBRARY: Load from JSON (v1.0.68 - first pattern to use JSON)
text_echo ""
PATTERN_FILE="$REPO_ROOT/patterns/unsanitized-superglobal-isset-bypass.json"
if [ -f "$PATTERN_FILE" ] && load_pattern "$PATTERN_FILE"; then
  # Use pattern metadata from JSON
  UNSANITIZED_SEVERITY=$(get_severity "$pattern_id" "$pattern_severity")
  UNSANITIZED_TITLE="$pattern_title"
else
  # Fallback to hardcoded values if JSON not found
  UNSANITIZED_SEVERITY=$(get_severity "unsanitized-superglobal-read" "HIGH")
  UNSANITIZED_TITLE="Unsanitized superglobal read (\$_GET/\$_POST)"
fi
UNSANITIZED_COLOR="${YELLOW}"
if [ "$UNSANITIZED_SEVERITY" = "CRITICAL" ] || [ "$UNSANITIZED_SEVERITY" = "HIGH" ]; then UNSANITIZED_COLOR="${RED}"; fi
text_echo "${BLUE}▸ ${UNSANITIZED_TITLE} ${UNSANITIZED_COLOR}[$UNSANITIZED_SEVERITY]${NC}"
UNSANITIZED_FAILED=false
UNSANITIZED_FINDING_COUNT=0
UNSANITIZED_VISIBLE=""

# Find all $_GET/$_POST/$_REQUEST access that doesn't have sanitization
# Exclude lines with: sanitize_*, esc_*, absint, intval, wc_clean, wp_unslash, $allowed_keys
# Note: We do NOT exclude isset/empty here because they don't sanitize - they only check existence
# We'll filter those out in a more sophisticated way below
# SAFEGUARD: "$PATHS" MUST be quoted - paths with spaces will break otherwise (see SAFEGUARDS.md)
UNSANITIZED_MATCHES=$(grep -rHn $EXCLUDE_ARGS --include="*.php" -E '\$_(GET|POST|REQUEST)\[' "$PATHS" 2>/dev/null | \
  grep -v 'sanitize_' | \
  grep -v 'esc_' | \
  grep -v 'absint' | \
  grep -v 'intval' | \
  grep -v 'wc_clean' | \
  grep -v 'wp_unslash' | \
  grep -v '\$allowed_keys' | \
  grep -v '//.*\$_' || true)

# Now filter out lines where isset/empty is used ONLY to check existence (not followed by usage)
# Pattern: isset($_GET['x']) ) { ... } with no further $_GET['x'] on the same line
# This is a more nuanced filter that allows isset() checks but catches isset() + direct usage
UNSANITIZED_MATCHES=$(echo "$UNSANITIZED_MATCHES" | while IFS= read -r line; do
  [ -z "$line" ] && continue

  # Extract the code part (after line number)
  code=$(echo "$line" | cut -d: -f3-)

  # Count how many times $_GET/$_POST/$_REQUEST appears in this line
  superglobal_count=$(echo "$code" | grep -o '\$_\(GET\|POST\|REQUEST\)\[' | wc -l | tr -d ' ')

  # If isset/empty is present AND superglobal appears only once, it's likely just a check
  # Example: if ( isset( $_GET['x'] ) ) { ... }
  if echo "$code" | grep -q 'isset\|empty'; then
    if [ "$superglobal_count" -eq 1 ]; then
      # This is likely just an existence check - skip it
      continue
    fi
  fi

  # Otherwise, output the line (it's a potential violation)
  echo "$line"
done || true)

if [ -n "$UNSANITIZED_MATCHES" ]; then
  while IFS= read -r match; do
    [ -z "$match" ] && continue
    file=$(echo "$match" | cut -d: -f1)
    lineno=$(echo "$match" | cut -d: -f2)
    code=$(echo "$match" | cut -d: -f3-)

    if ! [[ "$lineno" =~ ^[0-9]+$ ]]; then
      continue
    fi

    if should_suppress_finding "unsanitized-superglobal-read" "$file"; then
      continue
    fi

    UNSANITIZED_FAILED=true
    ((UNSANITIZED_FINDING_COUNT++))
    add_json_finding "unsanitized-superglobal-read" "error" "$UNSANITIZED_SEVERITY" "$file" "$lineno" "Unsanitized superglobal access" "$code"

    if [ -z "$UNSANITIZED_VISIBLE" ]; then
      UNSANITIZED_VISIBLE="$match"
    else
      UNSANITIZED_VISIBLE="${UNSANITIZED_VISIBLE}
$match"
    fi
  done <<< "$UNSANITIZED_MATCHES"
fi

if [ "$UNSANITIZED_FAILED" = true ]; then
  if [ "$UNSANITIZED_SEVERITY" = "CRITICAL" ] || [ "$UNSANITIZED_SEVERITY" = "HIGH" ]; then
    text_echo "${RED}  ✗ FAILED${NC}"
    ((ERRORS++))
  else
    text_echo "${YELLOW}  ⚠ WARNING${NC}"
    ((WARNINGS++))
  fi
  if [ "$OUTPUT_FORMAT" = "text" ] && [ -n "$UNSANITIZED_VISIBLE" ]; then
    while IFS= read -r match; do
      [ -z "$match" ] && continue
      format_finding "$match"
    done <<< "$(echo "$UNSANITIZED_VISIBLE" | head -5)"
  fi
  add_json_check "$UNSANITIZED_TITLE" "$UNSANITIZED_SEVERITY" "failed" "$UNSANITIZED_FINDING_COUNT"
else
  text_echo "${GREEN}  ✓ Passed${NC}"
  add_json_check "$UNSANITIZED_TITLE" "$UNSANITIZED_SEVERITY" "passed" 0
fi
text_echo ""

# Insecure data deserialization
run_check "ERROR" "$(get_severity "spo-003-insecure-deserialization" "CRITICAL")" "Insecure data deserialization" "spo-003-insecure-deserialization" \
  "-E unserialize[[:space:]]*\\(\\$_" \
  "-E base64_decode[[:space:]]*\\(\\$_" \
  "-E json_decode[[:space:]]*\\(\\$_" \
  "-E maybe_unserialize[[:space:]]*\\(\\$_"

# Direct database queries without $wpdb->prepare() (SQL injection risk)
# Note: This check requires custom implementation because we need to filter out lines
# that contain $wpdb->prepare in the same statement (grep -v after initial match)
text_echo ""
WPDB_SEVERITY=$(get_severity "wpdb-query-no-prepare" "CRITICAL")
WPDB_COLOR="${YELLOW}"
if [ "$WPDB_SEVERITY" = "CRITICAL" ] || [ "$WPDB_SEVERITY" = "HIGH" ]; then WPDB_COLOR="${RED}"; fi
text_echo "${BLUE}▸ Direct database queries without \$wpdb->prepare() ${WPDB_COLOR}[$WPDB_SEVERITY]${NC}"
WPDB_FAILED=false
WPDB_FINDING_COUNT=0
WPDB_VISIBLE=""

# Find all $wpdb->query, $wpdb->get_var, $wpdb->get_row, $wpdb->get_results, $wpdb->get_col
# that don't have $wpdb->prepare in the same statement
# SAFEGUARD: "$PATHS" MUST be quoted - paths with spaces will break otherwise (see SAFEGUARDS.md)
WPDB_MATCHES=$(grep -rHn $EXCLUDE_ARGS --include="*.php" -E '\$wpdb->(query|get_var|get_row|get_results|get_col)[[:space:]]*\(' "$PATHS" 2>/dev/null | \
  grep -v '\$wpdb->prepare' | \
  grep -v '//.*\$wpdb->' || true)

if [ -n "$WPDB_MATCHES" ]; then
  while IFS= read -r match; do
    [ -z "$match" ] && continue
    file=$(echo "$match" | cut -d: -f1)
    lineno=$(echo "$match" | cut -d: -f2)
    code=$(echo "$match" | cut -d: -f3-)

    if ! [[ "$lineno" =~ ^[0-9]+$ ]]; then
      continue
    fi

    if should_suppress_finding "wpdb-query-no-prepare" "$file"; then
      continue
    fi

    WPDB_FAILED=true
    ((WPDB_FINDING_COUNT++))
    add_json_finding "wpdb-query-no-prepare" "error" "$WPDB_SEVERITY" "$file" "$lineno" "Direct database query without \$wpdb->prepare()" "$code"

    if [ -z "$WPDB_VISIBLE" ]; then
      WPDB_VISIBLE="$match"
    else
      WPDB_VISIBLE="${WPDB_VISIBLE}
$match"
    fi
  done <<< "$WPDB_MATCHES"
fi

if [ "$WPDB_FAILED" = true ]; then
  if [ "$WPDB_SEVERITY" = "CRITICAL" ] || [ "$WPDB_SEVERITY" = "HIGH" ]; then
    text_echo "${RED}  ✗ FAILED${NC}"
    ((ERRORS++))
  else
    text_echo "${YELLOW}  ⚠ WARNING${NC}"
    ((WARNINGS++))
  fi
  if [ "$OUTPUT_FORMAT" = "text" ] && [ -n "$WPDB_VISIBLE" ]; then
    while IFS= read -r match; do
      [ -z "$match" ] && continue
      format_finding "$match"
    done <<< "$(echo "$WPDB_VISIBLE" | head -5)"
  fi
  add_json_check "Direct database queries without \$wpdb->prepare()" "$WPDB_SEVERITY" "failed" "$WPDB_FINDING_COUNT"
else
  text_echo "${GREEN}  ✓ Passed${NC}"
  add_json_check "Direct database queries without \$wpdb->prepare()" "$WPDB_SEVERITY" "passed" 0
fi
text_echo ""

# Missing capability checks in admin functions
ADMIN_CAP_SEVERITY=$(get_severity "admin-no-capability-check" "HIGH")
ADMIN_CAP_COLOR="${YELLOW}"
if [ "$ADMIN_CAP_SEVERITY" = "CRITICAL" ] || [ "$ADMIN_CAP_SEVERITY" = "HIGH" ]; then ADMIN_CAP_COLOR="${RED}"; fi
text_echo "${BLUE}▸ Admin functions without capability checks ${ADMIN_CAP_COLOR}[$ADMIN_CAP_SEVERITY]${NC}"
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

# SAFEGUARD: "$PATHS" MUST be quoted - paths with spaces will break otherwise (see SAFEGUARDS.md)
ADMIN_MATCHES=$(grep -rHn $EXCLUDE_ARGS --include="*.php" -E "function[[:space:]]+[a-zA-Z0-9_]*admin[a-zA-Z0-9_]*[[:space:]]*\\(|add_action[[:space:]]*\\([^)]*admin|add_menu_page[[:space:]]*\\(|add_submenu_page[[:space:]]*\\(|add_options_page[[:space:]]*\\(|add_management_page[[:space:]]*\\(" "$PATHS" 2>/dev/null || true)
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
    group_and_add_finding "spo-004-missing-cap-check" "error" "$ADMIN_CAP_SEVERITY" "$file" "$lineno" "$code" "Admin function/hook missing capability check near admin context"
  done <<< "$ADMIN_MATCHES"

  # Flush final group
  group_and_add_finding "spo-004-missing-cap-check" "error" "$ADMIN_CAP_SEVERITY" "" "" "" "Admin function/hook missing capability check near admin context" "true"
fi

if [ "$ADMIN_CAP_MISSING" = true ]; then
  if [ "$ADMIN_CAP_SEVERITY" = "CRITICAL" ] || [ "$ADMIN_CAP_SEVERITY" = "HIGH" ]; then
    text_echo "${RED}  ✗ FAILED${NC}"
    ((ERRORS++))
  else
    text_echo "${YELLOW}  ⚠ WARNING${NC}"
    ((WARNINGS++))
  fi
  if [ "$OUTPUT_FORMAT" = "text" ] && [ -n "$ADMIN_CAP_VISIBLE" ]; then
    while IFS= read -r match; do
      [ -z "$match" ] && continue
      format_finding "$match"
    done <<< "$(echo "$ADMIN_CAP_VISIBLE" | head -5)"
  fi
  add_json_check "Admin functions without capability checks" "$ADMIN_CAP_SEVERITY" "failed" "$ADMIN_CAP_FINDING_COUNT"
else
  text_echo "${GREEN}  ✓ Passed${NC}"
  add_json_check "Admin functions without capability checks" "$ADMIN_CAP_SEVERITY" "passed" 0
fi
text_echo ""

AJAX_POLLING_SEVERITY=$(get_severity "ajax-polling-unbounded" "HIGH")
AJAX_POLLING_COLOR="${YELLOW}"
if [ "$AJAX_POLLING_SEVERITY" = "CRITICAL" ] || [ "$AJAX_POLLING_SEVERITY" = "HIGH" ]; then AJAX_POLLING_COLOR="${RED}"; fi
text_echo "${BLUE}▸ Unbounded AJAX polling (setInterval + fetch/ajax) ${AJAX_POLLING_COLOR}[$AJAX_POLLING_SEVERITY]${NC}"
AJAX_POLLING=false
AJAX_POLLING_FINDING_COUNT=0
AJAX_POLLING_VISIBLE=""
# SAFEGUARD: "$PATHS" MUST be quoted - paths with spaces will break otherwise (see SAFEGUARDS.md)
POLLING_MATCHES=$(grep -rHn $EXCLUDE_ARGS --include="*.js" -E "setInterval[[:space:]]*\\(" "$PATHS" 2>/dev/null || true)
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
      add_json_finding "ajax-polling-unbounded" "error" "$AJAX_POLLING_SEVERITY" "$file" "${lineno:-0}" "AJAX polling via setInterval without rate limits" "$code"
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
  if [ "$AJAX_POLLING_SEVERITY" = "CRITICAL" ] || [ "$AJAX_POLLING_SEVERITY" = "HIGH" ]; then
    text_echo "${RED}  ✗ FAILED${NC}"
    ((ERRORS++))
  else
    text_echo "${YELLOW}  ⚠ WARNING${NC}"
    ((WARNINGS++))
  fi
  if [ "$OUTPUT_FORMAT" = "text" ] && [ -n "$AJAX_POLLING_VISIBLE" ]; then
    while IFS= read -r match; do
      [ -z "$match" ] && continue
      format_finding "$match"
    done <<< "$(echo "$AJAX_POLLING_VISIBLE" | head -5)"
  fi
  add_json_check "Unbounded AJAX polling (setInterval + fetch/ajax)" "$AJAX_POLLING_SEVERITY" "failed" "$AJAX_POLLING_FINDING_COUNT"
else
  text_echo "${GREEN}  ✓ Passed${NC}"
  add_json_check "Unbounded AJAX polling (setInterval + fetch/ajax)" "$AJAX_POLLING_SEVERITY" "passed" 0
fi
text_echo ""

# HCC-005: Expensive WordPress functions in polling intervals
HCC005_SEVERITY=$(get_severity "hcc-005-expensive-polling" "HIGH")
HCC005_COLOR="${YELLOW}"
if [ "$HCC005_SEVERITY" = "CRITICAL" ] || [ "$HCC005_SEVERITY" = "HIGH" ]; then HCC005_COLOR="${RED}"; fi
text_echo "${BLUE}▸ Expensive WP functions in polling intervals (HCC-005) ${HCC005_COLOR}[$HCC005_SEVERITY]${NC}"
EXPENSIVE_POLLING=false
EXPENSIVE_POLLING_FINDING_COUNT=0
EXPENSIVE_POLLING_VISIBLE=""
# Scan both JS and PHP files for setInterval (PHP files may have inline <script> tags)
# SAFEGUARD: "$PATHS" MUST be quoted - paths with spaces will break otherwise (see SAFEGUARDS.md)
POLLING_MATCHES_HCC005=$(grep -rHn $EXCLUDE_ARGS --include="*.js" --include="*.php" -E "setInterval[[:space:]]*\\(" "$PATHS" 2>/dev/null || true)
if [ -n "$POLLING_MATCHES_HCC005" ]; then
  while IFS= read -r match; do
    [ -z "$match" ] && continue
    file=$(echo "$match" | cut -d: -f1)
    lineno=$(echo "$match" | cut -d: -f2)
    code=$(echo "$match" | cut -d: -f3-)

    if ! [[ "$lineno" =~ ^[0-9][0-9]*$ ]]; then
      continue
    fi

    # Check for expensive WP functions in a wider context (20 lines after setInterval)
    start_line=$lineno
    end_line=$((lineno + 20))
    context=$(sed -n "${start_line},${end_line}p" "$file" 2>/dev/null)

    # Detect expensive WordPress functions
    if echo "$context" | grep -qE "get_plugins\\(|get_themes\\(|get_posts\\(|WP_Query|get_users\\(|wp_get_recent_posts\\(|get_categories\\(|get_terms\\("; then
      if should_suppress_finding "hcc-005-expensive-polling" "$file"; then
        continue
      fi

      EXPENSIVE_POLLING=true
      ((EXPENSIVE_POLLING_FINDING_COUNT++))
      add_json_finding "hcc-005-expensive-polling" "error" "$HCC005_SEVERITY" "$file" "${lineno:-0}" "Expensive WordPress function called in polling interval" "$code"
      if [ -z "$EXPENSIVE_POLLING_VISIBLE" ]; then
        EXPENSIVE_POLLING_VISIBLE="$match"
      else
        EXPENSIVE_POLLING_VISIBLE="${EXPENSIVE_POLLING_VISIBLE}
$match"
      fi
    fi
  done <<< "$POLLING_MATCHES_HCC005"
fi
if [ "$EXPENSIVE_POLLING" = true ]; then
  if [ "$HCC005_SEVERITY" = "CRITICAL" ] || [ "$HCC005_SEVERITY" = "HIGH" ]; then
    text_echo "${RED}  ✗ FAILED${NC}"
    ((ERRORS++))
  else
    text_echo "${YELLOW}  ⚠ WARNING${NC}"
    ((WARNINGS++))
  fi
  if [ "$OUTPUT_FORMAT" = "text" ] && [ -n "$EXPENSIVE_POLLING_VISIBLE" ]; then
    while IFS= read -r match; do
      [ -z "$match" ] && continue
      format_finding "$match"
    done <<< "$(echo "$EXPENSIVE_POLLING_VISIBLE" | head -5)"
  fi
  add_json_check "Expensive WP functions in polling intervals (HCC-005)" "$HCC005_SEVERITY" "failed" "$EXPENSIVE_POLLING_FINDING_COUNT"
else
  text_echo "${GREEN}  ✓ Passed${NC}"
  add_json_check "Expensive WP functions in polling intervals (HCC-005)" "$HCC005_SEVERITY" "passed" 0
fi
text_echo ""

REST_SEVERITY=$(get_severity "rest-no-pagination" "CRITICAL")
REST_COLOR="${YELLOW}"
if [ "$REST_SEVERITY" = "CRITICAL" ] || [ "$REST_SEVERITY" = "HIGH" ]; then REST_COLOR="${RED}"; fi
text_echo "${BLUE}▸ REST endpoints without pagination/limits ${REST_COLOR}[$REST_SEVERITY]${NC}"
REST_UNBOUNDED=false
REST_FINDING_COUNT=0
REST_VISIBLE=""
# SAFEGUARD: "$PATHS" MUST be quoted - paths with spaces will break otherwise (see SAFEGUARDS.md)
REST_MATCHES=$(grep -rHn $EXCLUDE_ARGS --include="*.php" -E "register_rest_route[[:space:]]*\\(" "$PATHS" 2>/dev/null || true)
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
      add_json_finding "rest-no-pagination" "error" "$REST_SEVERITY" "$file" "${lineno:-0}" "register_rest_route without per_page/limit pagination guard" "$code"
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
  if [ "$REST_SEVERITY" = "CRITICAL" ] || [ "$REST_SEVERITY" = "HIGH" ]; then
    text_echo "${RED}  ✗ FAILED${NC}"
    ((ERRORS++))
  else
    text_echo "${YELLOW}  ⚠ WARNING${NC}"
    ((WARNINGS++))
  fi
  if [ "$OUTPUT_FORMAT" = "text" ] && [ -n "$REST_VISIBLE" ]; then
    while IFS= read -r match; do
      [ -z "$match" ] && continue
      format_finding "$match"
    done <<< "$(echo "$REST_VISIBLE" | head -5)"
  fi
  add_json_check "REST endpoints without pagination/limits" "$REST_SEVERITY" "failed" "$REST_FINDING_COUNT"
else
  text_echo "${GREEN}  ✓ Passed${NC}"
  add_json_check "REST endpoints without pagination/limits" "$REST_SEVERITY" "passed" 0
fi
text_echo ""

AJAX_NONCE_SEVERITY=$(get_severity "ajax-no-nonce" "HIGH")
AJAX_NONCE_COLOR="${YELLOW}"
if [ "$AJAX_NONCE_SEVERITY" = "CRITICAL" ] || [ "$AJAX_NONCE_SEVERITY" = "HIGH" ]; then AJAX_NONCE_COLOR="${RED}"; fi
text_echo "${BLUE}▸ wp_ajax handlers without nonce validation ${AJAX_NONCE_COLOR}[$AJAX_NONCE_SEVERITY]${NC}"
AJAX_NONCE_FAIL=false
AJAX_NONCE_FINDING_COUNT=0
# SAFEGUARD: "$PATHS" MUST be quoted - paths with spaces will break otherwise (see SAFEGUARDS.md)
AJAX_FILES=$(grep -rln $EXCLUDE_ARGS --include="*.php" -e "wp_ajax" "$PATHS" 2>/dev/null || true)
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
    add_json_finding "ajax-no-nonce" "error" "$AJAX_NONCE_SEVERITY" "$file" "${lineno:-0}" "wp_ajax handler missing nonce validation" "$code"
    AJAX_NONCE_FAIL=true
    ((AJAX_NONCE_FINDING_COUNT++))
  done
fi
if [ "$AJAX_NONCE_FAIL" = true ]; then
  if [ "$AJAX_NONCE_SEVERITY" = "CRITICAL" ] || [ "$AJAX_NONCE_SEVERITY" = "HIGH" ]; then
    text_echo "${RED}  ✗ FAILED${NC}"
    ((ERRORS++))
  else
    text_echo "${YELLOW}  ⚠ WARNING${NC}"
    ((WARNINGS++))
  fi
  add_json_check "wp_ajax handlers without nonce validation" "$AJAX_NONCE_SEVERITY" "failed" "$AJAX_NONCE_FINDING_COUNT"
else
  text_echo "${GREEN}  ✓ Passed${NC}"
  add_json_check "wp_ajax handlers without nonce validation" "$AJAX_NONCE_SEVERITY" "passed" 0
fi
text_echo ""

run_check "ERROR" "$(get_severity "unbounded-posts-per-page" "CRITICAL")" "Unbounded posts_per_page" "unbounded-posts-per-page" \
  "-e posts_per_page[[:space:]]*=>[[:space:]]*-1"

run_check "ERROR" "$(get_severity "unbounded-numberposts" "CRITICAL")" "Unbounded numberposts" "unbounded-numberposts" \
  "-e numberposts[[:space:]]*=>[[:space:]]*-1"

run_check "ERROR" "$(get_severity "nopaging-true" "CRITICAL")" "nopaging => true" "nopaging-true" \
  "-e nopaging[[:space:]]*=>[[:space:]]*true"

run_check "ERROR" "$(get_severity "unbounded-wc-get-orders" "CRITICAL")" "Unbounded wc_get_orders limit" "unbounded-wc-get-orders" \
  "-e 'limit'[[:space:]]*=>[[:space:]]*-1"

# WooCommerce Subscriptions queries without limits
text_echo ""
WCS_SEVERITY=$(get_severity "wcs-get-subscriptions-no-limit" "MEDIUM")
WCS_COLOR="${YELLOW}"
if [ "$WCS_SEVERITY" = "CRITICAL" ] || [ "$WCS_SEVERITY" = "HIGH" ]; then WCS_COLOR="${RED}"; fi
text_echo "${BLUE}▸ WooCommerce Subscriptions queries without limits ${WCS_COLOR}[$WCS_SEVERITY]${NC}"
WCS_FAILED=false
WCS_FINDING_COUNT=0
WCS_VISIBLE=""

# Find wcs_get_subscriptions* functions called without 'limit' parameter
# SAFEGUARD: "$PATHS" MUST be quoted - paths with spaces will break otherwise (see SAFEGUARDS.md)
WCS_MATCHES=$(grep -rHn $EXCLUDE_ARGS --include="*.php" -E "wcs_get_subscriptions[a-zA-Z_]*[[:space:]]*\\(" "$PATHS" 2>/dev/null | \
  grep -v "'limit'" | \
  grep -v '"limit"' | \
  grep -v '//.*wcs_get_subscriptions' || true)

if [ -n "$WCS_MATCHES" ]; then
  while IFS= read -r match; do
    [ -z "$match" ] && continue
    file=$(echo "$match" | cut -d: -f1)
    lineno=$(echo "$match" | cut -d: -f2)
    code=$(echo "$match" | cut -d: -f3-)

    if ! [[ "$lineno" =~ ^[0-9]+$ ]]; then
      continue
    fi

    if should_suppress_finding "wcs-get-subscriptions-no-limit" "$file"; then
      continue
    fi

    WCS_FAILED=true
    ((WCS_FINDING_COUNT++))
    add_json_finding "wcs-get-subscriptions-no-limit" "warning" "$WCS_SEVERITY" "$file" "$lineno" "WooCommerce Subscriptions query without limit parameter" "$code"

    if [ -z "$WCS_VISIBLE" ]; then
      WCS_VISIBLE="$match"
    else
      WCS_VISIBLE="${WCS_VISIBLE}
$match"
    fi
  done <<< "$WCS_MATCHES"
fi

if [ "$WCS_FAILED" = true ]; then
  if [ "$WCS_SEVERITY" = "CRITICAL" ] || [ "$WCS_SEVERITY" = "HIGH" ]; then
    text_echo "${RED}  ✗ FAILED${NC}"
    ((ERRORS++))
  else
    text_echo "${YELLOW}  ⚠ WARNING${NC}"
    ((WARNINGS++))
  fi
  if [ "$OUTPUT_FORMAT" = "text" ] && [ -n "$WCS_VISIBLE" ]; then
    while IFS= read -r match; do
      [ -z "$match" ] && continue
      format_finding "$match"
    done <<< "$(echo "$WCS_VISIBLE" | head -5)"
  fi
  add_json_check "WooCommerce Subscriptions queries without limits" "$WCS_SEVERITY" "failed" "$WCS_FINDING_COUNT"
else
  text_echo "${GREEN}  ✓ Passed${NC}"
  add_json_check "WooCommerce Subscriptions queries without limits" "$WCS_SEVERITY" "passed" 0
fi
text_echo ""

# get_users check - unbounded user queries (can crash sites with many users)
USERS_SEVERITY=$(get_severity "get-users-no-limit" "CRITICAL")
USERS_COLOR="${YELLOW}"
if [ "$USERS_SEVERITY" = "CRITICAL" ] || [ "$USERS_SEVERITY" = "HIGH" ]; then USERS_COLOR="${RED}"; fi
text_echo "${BLUE}▸ get_users without number limit ${USERS_COLOR}[$USERS_SEVERITY]${NC}"
USERS_UNBOUNDED=false
USERS_FINDING_COUNT=0
USERS_VISIBLE=""

# Find all get_users() calls with line numbers
# SAFEGUARD: "$PATHS" MUST be quoted - paths with spaces will break otherwise (see SAFEGUARDS.md)
USERS_MATCHES=$(grep -rHn $EXCLUDE_ARGS --include="*.php" -e "get_users[[:space:]]*(" "$PATHS" 2>/dev/null || true)

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
        
        add_json_finding "get-users-no-limit" "error" "$USERS_SEVERITY" "$file" "$lineno" "get_users() without 'number' limit can fetch ALL users" "$code"
      fi
    fi
  done <<< "$USERS_MATCHES"
fi

if [ "$USERS_UNBOUNDED" = true ]; then
  if [ "$USERS_SEVERITY" = "CRITICAL" ] || [ "$USERS_SEVERITY" = "HIGH" ]; then
    text_echo "${RED}  ✗ FAILED${NC}"
    ((ERRORS++))
  else
    text_echo "${YELLOW}  ⚠ WARNING${NC}"
    ((WARNINGS++))
  fi
  if [ "$OUTPUT_FORMAT" = "text" ] && [ -n "$USERS_VISIBLE" ]; then
    while IFS= read -r match; do
      [ -z "$match" ] && continue
      format_finding "$match"
    done <<< "$(echo "$USERS_VISIBLE" | head -10)"
  fi
  add_json_check "get_users without number limit" "$USERS_SEVERITY" "failed" "$USERS_FINDING_COUNT"
else
  text_echo "${GREEN}  ✓ Passed${NC}"
  add_json_check "get_users without number limit" "$USERS_SEVERITY" "passed" 0
fi
text_echo ""

# get_terms check - more complex, needs context analysis
TERMS_SEVERITY=$(get_severity "get-terms-no-limit" "CRITICAL")
TERMS_COLOR="${YELLOW}"
if [ "$TERMS_SEVERITY" = "CRITICAL" ] || [ "$TERMS_SEVERITY" = "HIGH" ]; then TERMS_COLOR="${RED}"; fi
text_echo "${BLUE}▸ get_terms without number limit ${TERMS_COLOR}[$TERMS_SEVERITY]${NC}"
# SAFEGUARD: "$PATHS" MUST be quoted - paths with spaces will break otherwise (see SAFEGUARDS.md)
TERMS_FILES=$(grep -rln $EXCLUDE_ARGS --include="*.php" -e "get_terms[[:space:]]*(" "$PATHS" 2>/dev/null || true)
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
	        add_json_finding "get-terms-no-limit" "error" "$TERMS_SEVERITY" "$file" "${lineno:-0}" "get_terms() may be missing 'number' parameter" "get_terms("
	        TERMS_UNBOUNDED=true
	        ((TERMS_FINDING_COUNT++))
	      fi
	    fi
  done
fi
if [ "$TERMS_UNBOUNDED" = true ]; then
  if [ "$TERMS_SEVERITY" = "CRITICAL" ] || [ "$TERMS_SEVERITY" = "HIGH" ]; then
    text_echo "${RED}  ✗ FAILED${NC}"
    ((ERRORS++))
  else
    text_echo "${YELLOW}  ⚠ WARNING${NC}"
    ((WARNINGS++))
  fi
  add_json_check "get_terms without number limit" "$TERMS_SEVERITY" "failed" "$TERMS_FINDING_COUNT"
else
  text_echo "${GREEN}  ✓ Passed${NC}"
  add_json_check "get_terms without number limit" "$TERMS_SEVERITY" "passed" 0
fi
text_echo ""

# pre_get_posts unbounded check - files that hook pre_get_posts and set unbounded queries
PRE_GET_POSTS_SEVERITY=$(get_severity "pre-get-posts-unbounded" "CRITICAL")
PRE_GET_POSTS_COLOR="${YELLOW}"
if [ "$PRE_GET_POSTS_SEVERITY" = "CRITICAL" ] || [ "$PRE_GET_POSTS_SEVERITY" = "HIGH" ]; then PRE_GET_POSTS_COLOR="${RED}"; fi
text_echo "${BLUE}▸ pre_get_posts forcing unbounded queries ${PRE_GET_POSTS_COLOR}[$PRE_GET_POSTS_SEVERITY]${NC}"
PRE_GET_POSTS_UNBOUNDED=false
PRE_GET_POSTS_FINDING_COUNT=0
# SAFEGUARD: "$PATHS" MUST be quoted - paths with spaces will break otherwise (see SAFEGUARDS.md)
PRE_GET_POSTS_FILES=$(grep -rln $EXCLUDE_ARGS --include="*.php" -e "add_action.*pre_get_posts\|add_filter.*pre_get_posts" "$PATHS" 2>/dev/null || true)
if [ -n "$PRE_GET_POSTS_FILES" ]; then
  for file in $PRE_GET_POSTS_FILES; do
    # Check if file sets posts_per_page to -1 or nopaging to true
	    if grep -q "set[[:space:]]*([[:space:]]*['\"]posts_per_page['\"][[:space:]]*,[[:space:]]*-1" "$file" 2>/dev/null || \
	       grep -q "set[[:space:]]*([[:space:]]*['\"]nopaging['\"][[:space:]]*,[[:space:]]*true" "$file" 2>/dev/null; then
	      if ! should_suppress_finding "pre-get-posts-unbounded" "$file"; then
	        text_echo "  $file: pre_get_posts hook sets unbounded query"
	        lineno=$(grep -n "pre_get_posts" "$file" 2>/dev/null | head -1 | cut -d: -f1)
	        add_json_finding "pre-get-posts-unbounded" "error" "$PRE_GET_POSTS_SEVERITY" "$file" "${lineno:-0}" "pre_get_posts hook sets unbounded query" "pre_get_posts"
	        PRE_GET_POSTS_UNBOUNDED=true
	        ((PRE_GET_POSTS_FINDING_COUNT++))
	      fi
	    fi
  done
fi
if [ "$PRE_GET_POSTS_UNBOUNDED" = true ]; then
  if [ "$PRE_GET_POSTS_SEVERITY" = "CRITICAL" ] || [ "$PRE_GET_POSTS_SEVERITY" = "HIGH" ]; then
    text_echo "${RED}  ✗ FAILED${NC}"
    ((ERRORS++))
  else
    text_echo "${YELLOW}  ⚠ WARNING${NC}"
    ((WARNINGS++))
  fi
  add_json_check "pre_get_posts forcing unbounded queries" "$PRE_GET_POSTS_SEVERITY" "failed" "$PRE_GET_POSTS_FINDING_COUNT"
else
  text_echo "${GREEN}  ✓ Passed${NC}"
  add_json_check "pre_get_posts forcing unbounded queries" "$PRE_GET_POSTS_SEVERITY" "passed" 0
fi
text_echo ""

# Unbounded direct SQL on terms tables
# Look for lines with wpdb->terms or wpdb->term_taxonomy that don't have LIMIT on the same line
TERMS_SQL_SEVERITY=$(get_severity "unbounded-sql-terms" "HIGH")
TERMS_SQL_COLOR="${YELLOW}"
if [ "$TERMS_SQL_SEVERITY" = "CRITICAL" ] || [ "$TERMS_SQL_SEVERITY" = "HIGH" ]; then TERMS_SQL_COLOR="${RED}"; fi
text_echo "${BLUE}▸ Unbounded SQL on wp_terms/wp_term_taxonomy ${TERMS_SQL_COLOR}[$TERMS_SQL_SEVERITY]${NC}"
TERMS_SQL_UNBOUNDED=false
TERMS_SQL_FINDING_COUNT=0
# Find lines referencing terms tables in SQL context
# SAFEGUARD: "$PATHS" MUST be quoted - paths with spaces will break otherwise (see SAFEGUARDS.md)
TERMS_SQL_MATCHES=$(grep -rHn $EXCLUDE_ARGS --include="*.php" -E '\$wpdb->(terms|term_taxonomy)' "$PATHS" 2>/dev/null || true)
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
	        add_json_finding "unbounded-sql-terms" "error" "$TERMS_SQL_SEVERITY" "$_file" "${_lineno:-0}" "Unbounded SQL on wp_terms/wp_term_taxonomy" "$_code"
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
  if [ "$TERMS_SQL_SEVERITY" = "CRITICAL" ] || [ "$TERMS_SQL_SEVERITY" = "HIGH" ]; then
    text_echo "${RED}  ✗ FAILED${NC}"
    ((ERRORS++))
  else
    text_echo "${YELLOW}  ⚠ WARNING${NC}"
    ((WARNINGS++))
  fi
  add_json_check "Unbounded SQL on wp_terms/wp_term_taxonomy" "$TERMS_SQL_SEVERITY" "failed" "$TERMS_SQL_FINDING_COUNT"
else
  text_echo "${GREEN}  ✓ Passed${NC}"
  add_json_check "Unbounded SQL on wp_terms/wp_term_taxonomy" "$TERMS_SQL_SEVERITY" "passed" 0
fi

# Unvalidated cron intervals - can cause infinite loops or silent failures
CRON_SEVERITY=$(get_severity "cron-interval-unvalidated" "HIGH")
CRON_COLOR="${YELLOW}"
if [ "$CRON_SEVERITY" = "CRITICAL" ] || [ "$CRON_SEVERITY" = "HIGH" ]; then CRON_COLOR="${RED}"; fi
text_echo "${BLUE}▸ Unvalidated cron intervals ${CRON_COLOR}[$CRON_SEVERITY]${NC}"
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

            add_json_finding "cron-interval-unvalidated" "error" "$CRON_SEVERITY" "$file" "$lineno" \
              "Unvalidated cron interval - use absint() and bounds checking (1-1440 minutes) to prevent corrupt data from causing 0-second intervals or infinite loops" \
              "$code"
          fi
        fi
      done <<< "$INTERVAL_MATCHES"
    fi
  done
fi

if [ "$CRON_INTERVAL_FAIL" = true ]; then
  if [ "$CRON_SEVERITY" = "CRITICAL" ] || [ "$CRON_SEVERITY" = "HIGH" ]; then
    text_echo "${RED}  ✗ FAILED${NC}"
    ((ERRORS++))
  else
    text_echo "${YELLOW}  ⚠ WARNING${NC}"
    ((WARNINGS++))
  fi
  add_json_check "Unvalidated cron intervals" "$CRON_SEVERITY" "failed" "$CRON_INTERVAL_FINDING_COUNT"
else
  text_echo "${GREEN}  ✓ Passed${NC}"
  add_json_check "Unvalidated cron intervals" "$CRON_SEVERITY" "passed" 0
fi
text_echo ""

text_echo "${YELLOW}━━━ WARNING CHECKS (review recommended) ━━━${NC}"
text_echo ""

# Enhanced timezone check - skip lines with phpcs:ignore comments
# Note: Only flags date() (timezone-dependent), not gmdate() (timezone-safe, always UTC)
TZ_SEVERITY=$(get_severity "timezone-sensitive-code" "LOW")
TZ_COLOR="${YELLOW}"
if [ "$TZ_SEVERITY" = "CRITICAL" ] || [ "$TZ_SEVERITY" = "HIGH" ]; then TZ_COLOR="${RED}"; fi
text_echo "${BLUE}▸ Timezone-sensitive patterns (current_time/date) ${TZ_COLOR}[$TZ_SEVERITY]${NC}"
TZ_WARNINGS=0
TZ_FINDING_COUNT=0
TZ_MATCHES=$(grep -rHn $EXCLUDE_ARGS --include="*.php" \
  -E "current_time[[:space:]]*\([[:space:]]*['\"]timestamp" \
  $PATHS 2>/dev/null || true)
# Add date() matches but exclude gmdate() (which is timezone-safe, always UTC)
TZ_MATCHES="${TZ_MATCHES}"$'\n'$(grep -rHn $EXCLUDE_ARGS --include="*.php" \
  -E "[^a-zA-Z_]date[[:space:]]*\(" \
  $PATHS 2>/dev/null | grep -v "gmdate" || true)

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
	        add_json_finding "timezone-sensitive-code" "warning" "$TZ_SEVERITY" "$file" "$line_num" "Timezone-sensitive pattern without phpcs:ignore" "$code"
	        ((TZ_WARNINGS++)) || true
	        ((TZ_FINDING_COUNT++)) || true
	      fi
	    fi
  done <<< "$TZ_MATCHES"

  if [ "$TZ_WARNINGS" -gt 0 ]; then
    if [ "$TZ_SEVERITY" = "CRITICAL" ] || [ "$TZ_SEVERITY" = "HIGH" ]; then
      text_echo "${RED}  ✗ FAILED ($TZ_WARNINGS occurrence(s) without phpcs:ignore)${NC}"
      ((ERRORS++))
    else
      text_echo "${YELLOW}  ⚠ WARNING ($TZ_WARNINGS occurrence(s) without phpcs:ignore)${NC}"
      ((WARNINGS++))
    fi
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
    add_json_check "Timezone-sensitive patterns (current_time/date)" "$TZ_SEVERITY" "failed" "$TZ_FINDING_COUNT"
  else
    text_echo "${GREEN}  ✓ Passed (all occurrences have phpcs:ignore)${NC}"
    add_json_check "Timezone-sensitive patterns (current_time/date)" "$TZ_SEVERITY" "passed" 0
  fi
else
  text_echo "${GREEN}  ✓ Passed${NC}"
  add_json_check "Timezone-sensitive patterns (current_time/date)" "$TZ_SEVERITY" "passed" 0
fi
text_echo ""

run_check "WARNING" "$(get_severity "order-by-rand" "HIGH")" "Randomized ordering (ORDER BY RAND)" "order-by-rand" \
  "-e orderby[[:space:]]*=>[[:space:]]*['\"]rand['\"]" \
  "-E ORDER[[:space:]]+BY[[:space:]]+RAND\("

# LIKE queries with leading wildcards
LIKE_SEVERITY=$(get_severity "like-leading-wildcard" "MEDIUM")
LIKE_COLOR="${YELLOW}"
if [ "$LIKE_SEVERITY" = "CRITICAL" ] || [ "$LIKE_SEVERITY" = "HIGH" ]; then LIKE_COLOR="${RED}"; fi
text_echo "${BLUE}▸ LIKE queries with leading wildcards ${LIKE_COLOR}[$LIKE_SEVERITY]${NC}"
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
	        add_json_finding "like-leading-wildcard" "warning" "$LIKE_SEVERITY" "$file" "$line_num" "LIKE query with leading wildcard prevents index use" "$code"
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
	      add_json_finding "like-leading-wildcard" "warning" "$LIKE_SEVERITY" "$file" "$line_num" "LIKE query with leading wildcard prevents index use" "$code"
	      ((LIKE_WARNINGS++)) || true
	      ((LIKE_FINDING_COUNT++)) || true
	    fi
	  done <<< "$SQL_LIKE"
	fi

if [ "$LIKE_WARNINGS" -gt 0 ]; then
  if [ "$LIKE_SEVERITY" = "CRITICAL" ] || [ "$LIKE_SEVERITY" = "HIGH" ]; then
    text_echo "${RED}  ✗ FAILED - LIKE queries with leading wildcards prevent index use:${NC}"
    ((ERRORS++))
  else
    text_echo "${YELLOW}  ⚠ WARNING - LIKE queries with leading wildcards prevent index use:${NC}"
    ((WARNINGS++))
  fi
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
  add_json_check "LIKE queries with leading wildcards" "$LIKE_SEVERITY" "failed" "$LIKE_FINDING_COUNT"
else
  text_echo "${GREEN}  ✓ Passed${NC}"
  add_json_check "LIKE queries with leading wildcards" "$LIKE_SEVERITY" "passed" 0
fi
text_echo ""

# N+1 pattern check (simplified) - includes post, term, and user meta
N1_SEVERITY=$(get_severity "n-plus-one-pattern" "MEDIUM")
N1_COLOR="${YELLOW}"
if [ "$N1_SEVERITY" = "CRITICAL" ]; then N1_COLOR="${RED}"; fi
text_echo "${BLUE}▸ Potential N+1 patterns (meta in loops) ${N1_COLOR}[$N1_SEVERITY]${NC}"
	# SAFEGUARD: "$PATHS" MUST be quoted - paths with spaces will break otherwise (see SAFEGUARDS.md)
	N1_FILES=$(grep -rl $EXCLUDE_ARGS --include="*.php" -e "get_post_meta\|get_term_meta\|get_user_meta" "$PATHS" 2>/dev/null | \
	           xargs -I{} grep -l "foreach\|while[[:space:]]*(" {} 2>/dev/null | head -5 || true)
	N1_FINDING_COUNT=0
	VISIBLE_N1_FILES=""
	if [ -n "$N1_FILES" ]; then
	  # Collect findings, applying baseline per file
	  while IFS= read -r f; do
	    [ -z "$f" ] && continue
	    if ! should_suppress_finding "n-plus-1-pattern" "$f"; then
	      VISIBLE_N1_FILES="${VISIBLE_N1_FILES}${f}"$'\n'
	      add_json_finding "n-plus-1-pattern" "warning" "$N1_SEVERITY" "$f" "0" "File may contain N+1 query pattern (meta in loops)" ""
	      ((N1_FINDING_COUNT++)) || true
	    fi
	  done <<< "$N1_FILES"

	  if [ "$N1_FINDING_COUNT" -gt 0 ]; then
	    if [ "$N1_SEVERITY" = "CRITICAL" ] || [ "$N1_SEVERITY" = "HIGH" ]; then
	      text_echo "${RED}  ✗ FAILED${NC}"
	      ((ERRORS++))
	    else
	      text_echo "${YELLOW}  ⚠ Files with potential N+1 patterns:${NC}"
	      ((WARNINGS++))
	    fi
	    if [ "$OUTPUT_FORMAT" = "text" ]; then
	      echo "$VISIBLE_N1_FILES" | while read f; do [ -n "$f" ] && echo "    - $f"; done
	    fi
	    add_json_check "Potential N+1 patterns (meta in loops)" "$N1_SEVERITY" "failed" "$N1_FINDING_COUNT"
	  else
	    text_echo "${GREEN}  ✓ No obvious N+1 patterns${NC}"
	    add_json_check "Potential N+1 patterns (meta in loops)" "$N1_SEVERITY" "passed" 0
	  fi
	else
	  text_echo "${GREEN}  ✓ No obvious N+1 patterns${NC}"
	  add_json_check "Potential N+1 patterns (meta in loops)" "$N1_SEVERITY" "passed" 0
	fi
text_echo ""

# WooCommerce N+1 pattern check - WC-specific functions in loops
WC_N1_SEVERITY=$(get_severity "wc-n-plus-one-pattern" "HIGH")
WC_N1_COLOR="${YELLOW}"
if [ "$WC_N1_SEVERITY" = "CRITICAL" ] || [ "$WC_N1_SEVERITY" = "HIGH" ]; then WC_N1_COLOR="${RED}"; fi
text_echo "${BLUE}▸ WooCommerce N+1 patterns (WC functions in loops) ${WC_N1_COLOR}[$WC_N1_SEVERITY]${NC}"
WC_N1_FAILED=false
WC_N1_FINDING_COUNT=0
WC_N1_VISIBLE=""

# Find files with WC-specific N+1 patterns
# Strategy: Find foreach/while loops, then check if loop body contains WC N+1 patterns
# SAFEGUARD: "$PATHS" MUST be quoted - paths with spaces will break otherwise (see SAFEGUARDS.md)
WC_N1_MATCHES=$(grep -rHn $EXCLUDE_ARGS --include="*.php" -E "foreach[[:space:]]*\\(|while[[:space:]]*\\(" "$PATHS" 2>/dev/null | \
  while IFS= read -r match; do
    [ -z "$match" ] && continue
    file=$(echo "$match" | cut -d: -f1)
    lineno=$(echo "$match" | cut -d: -f2)
    code=$(echo "$match" | cut -d: -f3-)

    # Check if this is a WC-related loop by looking at context (previous 5 lines + current line)
    context_start=$((lineno - 5))
    if [ $context_start -lt 1 ]; then context_start=1; fi
    pre_context=$(sed -n "${context_start},${lineno}p" "$file" 2>/dev/null || true)

    # Skip if not a WC-related loop (orders, products, etc.)
    if ! echo "$pre_context" | grep -qE "wc_get_orders|wc_get_products|shop_order|product|order_id|product_id|\\\$orders|\\\$products"; then
      continue
    fi

    # Check if the loop body (next 20 lines) contains WC N+1 patterns
    start_line=$lineno
    end_line=$((lineno + 20))
    context=$(sed -n "${start_line},${end_line}p" "$file" 2>/dev/null || true)

    # Look for N+1 patterns in the loop body
    if echo "$context" | grep -qE "wc_get_order[[:space:]]*\\(|wc_get_product[[:space:]]*\\(|get_post_meta[[:space:]]*\\(|get_user_meta[[:space:]]*\\(|->get_meta[[:space:]]*\\("; then
      echo "$match"
    fi
  done || true)

if [ -n "$WC_N1_MATCHES" ]; then
  while IFS= read -r match; do
    [ -z "$match" ] && continue
    file=$(echo "$match" | cut -d: -f1)
    lineno=$(echo "$match" | cut -d: -f2)
    code=$(echo "$match" | cut -d: -f3-)

    if ! [[ "$lineno" =~ ^[0-9]+$ ]]; then
      continue
    fi

    if should_suppress_finding "wc-n-plus-one-pattern" "$file"; then
      continue
    fi

    WC_N1_FAILED=true
    ((WC_N1_FINDING_COUNT++))
    add_json_finding "wc-n-plus-one-pattern" "warning" "$WC_N1_SEVERITY" "$file" "$lineno" "WooCommerce N+1 pattern: WC function calls in loop over orders/products" "$code"

    if [ -z "$WC_N1_VISIBLE" ]; then
      WC_N1_VISIBLE="$match"
    else
      WC_N1_VISIBLE="${WC_N1_VISIBLE}
$match"
    fi
  done <<< "$WC_N1_MATCHES"
fi

if [ "$WC_N1_FAILED" = true ]; then
  if [ "$WC_N1_SEVERITY" = "CRITICAL" ] || [ "$WC_N1_SEVERITY" = "HIGH" ]; then
    text_echo "${RED}  ✗ FAILED${NC}"
    ((ERRORS++))
  else
    text_echo "${YELLOW}  ⚠ WARNING${NC}"
    ((WARNINGS++))
  fi
  if [ "$OUTPUT_FORMAT" = "text" ] && [ -n "$WC_N1_VISIBLE" ]; then
    while IFS= read -r match; do
      [ -z "$match" ] && continue
      format_finding "$match"
    done <<< "$(echo "$WC_N1_VISIBLE" | head -5)"
  fi
  add_json_check "WooCommerce N+1 patterns (WC functions in loops)" "$WC_N1_SEVERITY" "failed" "$WC_N1_FINDING_COUNT"
else
  text_echo "${GREEN}  ✓ Passed${NC}"
  add_json_check "WooCommerce N+1 patterns (WC functions in loops)" "$WC_N1_SEVERITY" "passed" 0
fi
text_echo ""

# Transient abuse check - transients without expiration
TRANSIENT_SEVERITY=$(get_severity "transient-no-expiration" "MEDIUM")
TRANSIENT_COLOR="${YELLOW}"
if [ "$TRANSIENT_SEVERITY" = "CRITICAL" ] || [ "$TRANSIENT_SEVERITY" = "HIGH" ]; then TRANSIENT_COLOR="${RED}"; fi
text_echo "${BLUE}▸ Transients without expiration ${TRANSIENT_COLOR}[$TRANSIENT_SEVERITY]${NC}"
# SAFEGUARD: "$PATHS" MUST be quoted - paths with spaces will break otherwise (see SAFEGUARDS.md)
TRANSIENT_MATCHES=$(grep -rHn $EXCLUDE_ARGS --include="*.php" -E "set_transient[[:space:]]*\(" "$PATHS" 2>/dev/null || true)
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
	        add_json_finding "transient-no-expiration" "warning" "$TRANSIENT_SEVERITY" "$file" "$line_num" "Transient may be missing expiration parameter" "$code"
	        TRANSIENT_ABUSE=true
	        ((TRANSIENT_FINDING_COUNT++)) || true
	      fi
	    fi
  done <<< "$TRANSIENT_MATCHES"
fi

if [ "$TRANSIENT_ABUSE" = true ]; then
  if [ "$TRANSIENT_SEVERITY" = "CRITICAL" ] || [ "$TRANSIENT_SEVERITY" = "HIGH" ]; then
    text_echo "${RED}  ✗ FAILED - Transients may be missing expiration parameter:${NC}"
    ((ERRORS++))
  else
    text_echo "${YELLOW}  ⚠ WARNING - Transients may be missing expiration parameter:${NC}"
    ((WARNINGS++))
  fi
  if [ "$OUTPUT_FORMAT" = "text" ]; then
    echo "$TRANSIENT_ISSUES" | head -5
  fi
  add_json_check "Transients without expiration" "$TRANSIENT_SEVERITY" "failed" "$TRANSIENT_FINDING_COUNT"
else
  text_echo "${GREEN}  ✓ Passed${NC}"
  add_json_check "Transients without expiration" "$TRANSIENT_SEVERITY" "passed" 0
fi
text_echo ""

# Script/style versioning with time() - prevents browser caching
SCRIPT_TIME_SEVERITY=$(get_severity "asset-version-time" "MEDIUM")
SCRIPT_TIME_COLOR="${YELLOW}"
if [ "$SCRIPT_TIME_SEVERITY" = "CRITICAL" ] || [ "$SCRIPT_TIME_SEVERITY" = "HIGH" ]; then SCRIPT_TIME_COLOR="${RED}"; fi
text_echo "${BLUE}▸ Script/style versioning with time() ${SCRIPT_TIME_COLOR}[$SCRIPT_TIME_SEVERITY]${NC}"
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
      add_json_finding "asset-version-time" "warning" "$SCRIPT_TIME_SEVERITY" "$file" "$line_num" "Using time() as script/style version prevents browser caching - use plugin version instead" "$code"
      SCRIPT_TIME_ISSUES=true
      ((SCRIPT_TIME_FINDING_COUNT++)) || true
    fi
  done <<< "$SCRIPT_TIME_MATCHES"
fi

if [ "$SCRIPT_TIME_ISSUES" = true ]; then
  if [ "$SCRIPT_TIME_SEVERITY" = "CRITICAL" ] || [ "$SCRIPT_TIME_SEVERITY" = "HIGH" ]; then
    text_echo "${RED}  ✗ FAILED - Scripts/styles using time() as version:${NC}"
    ((ERRORS++))
  else
    text_echo "${YELLOW}  ⚠ WARNING - Scripts/styles using time() as version:${NC}"
    ((WARNINGS++))
  fi
  add_json_check "Script/style versioning with time()" "$SCRIPT_TIME_SEVERITY" "failed" "$SCRIPT_TIME_FINDING_COUNT"
else
  text_echo "${GREEN}  ✓ Passed${NC}"
  add_json_check "Script/style versioning with time()" "$SCRIPT_TIME_SEVERITY" "passed" 0
fi
text_echo ""

# file_get_contents() for external URLs - Security & Performance Issue
FILE_GET_CONTENTS_SEVERITY=$(get_severity "file-get-contents-url" "HIGH")
FILE_GET_CONTENTS_COLOR="${YELLOW}"
if [ "$FILE_GET_CONTENTS_SEVERITY" = "CRITICAL" ] || [ "$FILE_GET_CONTENTS_SEVERITY" = "HIGH" ]; then FILE_GET_CONTENTS_COLOR="${RED}"; fi
text_echo "${BLUE}▸ file_get_contents() with external URLs ${FILE_GET_CONTENTS_COLOR}[$FILE_GET_CONTENTS_SEVERITY]${NC}"
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
      add_json_finding "file-get-contents-url" "error" "$FILE_GET_CONTENTS_SEVERITY" "$file" "$line_num" "file_get_contents() with URL is insecure and slow - use wp_remote_get() instead" "$code"
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
        add_json_finding "file-get-contents-url" "error" "$FILE_GET_CONTENTS_SEVERITY" "$file" "$line_num" "file_get_contents() with potential URL variable - use wp_remote_get() instead" "$code"
        ((FILE_GET_CONTENTS_FINDING_COUNT++)) || true
      fi
    fi
  done <<< "$FILE_GET_CONTENTS_VAR"
fi

if [ "$FILE_GET_CONTENTS_FINDING_COUNT" -gt 0 ]; then
  if [ "$FILE_GET_CONTENTS_SEVERITY" = "CRITICAL" ] || [ "$FILE_GET_CONTENTS_SEVERITY" = "HIGH" ]; then
    text_echo "${RED}  ✗ FAILED - file_get_contents() used for external URLs:${NC}"
    ((ERRORS++))
  else
    text_echo "${YELLOW}  ⚠ WARNING - file_get_contents() used for external URLs:${NC}"
    ((WARNINGS++))
  fi
  if [ "$OUTPUT_FORMAT" = "text" ] && [ -n "$FILE_GET_CONTENTS_ISSUES" ]; then
    echo "$FILE_GET_CONTENTS_ISSUES" | head -5
  fi
  add_json_check "file_get_contents with external URLs" "$FILE_GET_CONTENTS_SEVERITY" "failed" "$FILE_GET_CONTENTS_FINDING_COUNT"
else
  text_echo "${GREEN}  ✓ Passed${NC}"
  add_json_check "file_get_contents with external URLs" "$FILE_GET_CONTENTS_SEVERITY" "passed" 0
fi
text_echo ""

# HTTP requests without timeout - Can hang entire site
HTTP_TIMEOUT_SEVERITY=$(get_severity "http-no-timeout" "MEDIUM")
HTTP_TIMEOUT_COLOR="${YELLOW}"
if [ "$HTTP_TIMEOUT_SEVERITY" = "CRITICAL" ] || [ "$HTTP_TIMEOUT_SEVERITY" = "HIGH" ]; then HTTP_TIMEOUT_COLOR="${RED}"; fi
text_echo "${BLUE}▸ HTTP requests without timeout ${HTTP_TIMEOUT_COLOR}[$HTTP_TIMEOUT_SEVERITY]${NC}"
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
        add_json_finding "http-no-timeout" "warning" "$HTTP_TIMEOUT_SEVERITY" "$file" "$line_num" "HTTP request without explicit timeout can hang site if remote server doesn't respond" "$code"
        ((HTTP_NO_TIMEOUT_FINDING_COUNT++)) || true
      fi
    fi
  done <<< "$HTTP_NO_TIMEOUT_MATCHES"
fi

if [ "$HTTP_NO_TIMEOUT_FINDING_COUNT" -gt 0 ]; then
  if [ "$HTTP_TIMEOUT_SEVERITY" = "CRITICAL" ] || [ "$HTTP_TIMEOUT_SEVERITY" = "HIGH" ]; then
    text_echo "${RED}  ✗ FAILED - HTTP requests without timeout:${NC}"
    ((ERRORS++))
  else
    text_echo "${YELLOW}  ⚠ WARNING - HTTP requests without timeout:${NC}"
    ((WARNINGS++))
  fi
  if [ "$OUTPUT_FORMAT" = "text" ] && [ -n "$HTTP_NO_TIMEOUT_ISSUES" ]; then
    echo "$HTTP_NO_TIMEOUT_ISSUES" | head -5
  fi
  add_json_check "HTTP requests without timeout" "$HTTP_TIMEOUT_SEVERITY" "failed" "$HTTP_NO_TIMEOUT_FINDING_COUNT"
else
  text_echo "${GREEN}  ✓ Passed${NC}"
  add_json_check "HTTP requests without timeout" "$HTTP_TIMEOUT_SEVERITY" "passed" 0
fi
text_echo ""

# Disallowed PHP short tags - WordPress Coding Standards violation
PHP_SHORT_TAGS_SEVERITY=$(get_severity "disallowed-php-short-tags" "MEDIUM")
PHP_SHORT_TAGS_COLOR="${YELLOW}"
if [ "$PHP_SHORT_TAGS_SEVERITY" = "CRITICAL" ] || [ "$PHP_SHORT_TAGS_SEVERITY" = "HIGH" ]; then PHP_SHORT_TAGS_COLOR="${RED}"; fi
text_echo "${BLUE}▸ Disallowed PHP short tags ${PHP_SHORT_TAGS_COLOR}[$PHP_SHORT_TAGS_SEVERITY]${NC}"

# Find short echo tags (<?=)
SHORT_ECHO_MATCHES=$(grep -rHn $EXCLUDE_ARGS --include="*.php" \
  -F "<?=" \
  $PATHS 2>/dev/null || true)

# Find short open tags (<? followed by space/tab/newline, but not <?php or <?xml)
# We'll use a simple approach: find all "<? " and filter out "<?php" and "<?xml"
SHORT_OPEN_MATCHES=$(grep -rHn $EXCLUDE_ARGS --include="*.php" \
  -E "<\?[[:space:]]" \
  $PATHS 2>/dev/null | grep -v "<?php" | grep -v "<?xml" || true)

PHP_SHORT_TAGS_ISSUES=""
PHP_SHORT_TAGS_FINDING_COUNT=0

# Process short echo tags (<?=)
if [ -n "$SHORT_ECHO_MATCHES" ]; then
  while IFS= read -r match; do
    [ -z "$match" ] && continue
    file=$(echo "$match" | cut -d: -f1)
    line_num=$(echo "$match" | cut -d: -f2)
    code=$(echo "$match" | cut -d: -f3-)
    if ! should_suppress_finding "disallowed-php-short-tags" "$file"; then
      PHP_SHORT_TAGS_ISSUES="${PHP_SHORT_TAGS_ISSUES}${match}"$'\n'
      add_json_finding "disallowed-php-short-tags" "warning" "$PHP_SHORT_TAGS_SEVERITY" "$file" "$line_num" "PHP short echo tag (<?=) used - WordPress requires full <?php tags" "$code"
      ((PHP_SHORT_TAGS_FINDING_COUNT++)) || true
    fi
  done <<< "$SHORT_ECHO_MATCHES"
fi

# Process short open tags (<? )
if [ -n "$SHORT_OPEN_MATCHES" ]; then
  while IFS= read -r match; do
    [ -z "$match" ] && continue
    file=$(echo "$match" | cut -d: -f1)
    line_num=$(echo "$match" | cut -d: -f2)
    code=$(echo "$match" | cut -d: -f3-)
    if ! should_suppress_finding "disallowed-php-short-tags" "$file"; then
      PHP_SHORT_TAGS_ISSUES="${PHP_SHORT_TAGS_ISSUES}${match}"$'\n'
      add_json_finding "disallowed-php-short-tags" "warning" "$PHP_SHORT_TAGS_SEVERITY" "$file" "$line_num" "PHP short open tag (<? ) used - WordPress requires full <?php tags" "$code"
      ((PHP_SHORT_TAGS_FINDING_COUNT++)) || true
    fi
  done <<< "$SHORT_OPEN_MATCHES"
fi

if [ "$PHP_SHORT_TAGS_FINDING_COUNT" -gt 0 ]; then
  if [ "$PHP_SHORT_TAGS_SEVERITY" = "CRITICAL" ] || [ "$PHP_SHORT_TAGS_SEVERITY" = "HIGH" ]; then
    text_echo "${RED}  ✗ FAILED - PHP short tags found:${NC}"
    ((ERRORS++))
  else
    text_echo "${YELLOW}  ⚠ WARNING - PHP short tags found:${NC}"
    ((WARNINGS++))
  fi
  if [ "$OUTPUT_FORMAT" = "text" ] && [ -n "$PHP_SHORT_TAGS_ISSUES" ]; then
    echo "$PHP_SHORT_TAGS_ISSUES" | head -5
  fi
  add_json_check "Disallowed PHP short tags" "$PHP_SHORT_TAGS_SEVERITY" "failed" "$PHP_SHORT_TAGS_FINDING_COUNT"
else
  text_echo "${GREEN}  ✓ Passed${NC}"
  add_json_check "Disallowed PHP short tags" "$PHP_SHORT_TAGS_SEVERITY" "passed" 0
fi
text_echo ""

# ============================================================================
# DRY Violation Detection (Aggregated Patterns)
# ============================================================================

text_echo "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
text_echo "${BLUE}  DRY VIOLATION DETECTION${NC}"
text_echo "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
text_echo ""

# Find all aggregated patterns
AGGREGATED_PATTERNS=$(find "$REPO_ROOT/patterns" -name "*.json" -type f | while read -r pattern_file; do
  detection_type=$(grep '"detection_type"' "$pattern_file" | head -1 | sed 's/.*"detection_type"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
  if [ "$detection_type" = "aggregated" ]; then
    echo "$pattern_file"
  fi
done)

if [ -z "$AGGREGATED_PATTERNS" ]; then
  text_echo "${BLUE}No aggregated patterns found. Skipping DRY checks.${NC}"
  text_echo ""
else
  # Debug: Log aggregated patterns found
  echo "[DEBUG] Aggregated patterns found:" >> /tmp/wp-code-check-debug.log
  echo "$AGGREGATED_PATTERNS" >> /tmp/wp-code-check-debug.log

  # Process each aggregated pattern
  while IFS= read -r pattern_file; do
    [ -z "$pattern_file" ] && continue

    # Load pattern to get title
    if load_pattern "$pattern_file"; then
      text_echo "${BLUE}▸ $pattern_title${NC}"

      # Debug: Show pattern info in output
      text_echo "  ${BLUE}→ Pattern: $pattern_search${NC}"

      # Store current violation count
      violations_before=$DRY_VIOLATIONS_COUNT

      process_aggregated_pattern "$pattern_file"

      # Check if new violations were added
      violations_after=$DRY_VIOLATIONS_COUNT
      new_violations=$((violations_after - violations_before))

      if [ "$new_violations" -gt 0 ]; then
        text_echo "${YELLOW}  ⚠ Found $new_violations violation(s)${NC}"
      else
        text_echo "${GREEN}  ✓ No violations${NC}"
      fi
      text_echo ""
    fi
  done <<< "$AGGREGATED_PATTERNS"
fi

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

  # Fixture validation status (proof of detection)
  text_echo ""
  if [ "$FIXTURE_VALIDATION_STATUS" = "passed" ]; then
    text_echo "${GREEN}✓ Detection verified: ${FIXTURE_VALIDATION_PASSED} test fixtures passed${NC}"
  elif [ "$FIXTURE_VALIDATION_STATUS" = "failed" ]; then
    text_echo "${RED}⚠ Detection warning: ${FIXTURE_VALIDATION_FAILED}/${FIXTURE_VALIDATION_PASSED} fixtures failed${NC}"
  elif [ "$FIXTURE_VALIDATION_STATUS" = "skipped" ]; then
    text_echo "${YELLOW}○ Fixture validation skipped (fixtures not found)${NC}"
  fi
fi

exit $EXIT_CODE
