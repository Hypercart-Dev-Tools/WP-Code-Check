#!/usr/bin/env bash
#
# WP Code Check by Hypercart - Performance Analysis Script
# Version: 1.0.94
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
#   --format text|json       Output format (default: json, generates HTML report)
#   --strict                 Fail on warnings (N+1 patterns)
#   --verbose                Show all matches, not just first occurrence
#   --no-log                 Disable logging to file
#   --no-context             Disable context lines around findings
#   --context-lines N        Number of context lines to show (default: 3)
#   --severity-config <path> Use custom severity levels from JSON config file
#   --generate-baseline      Generate .hcc-baseline from current findings
#   --baseline <path>        Use custom baseline file path (default: .hcc-baseline)
#   --ignore-baseline        Ignore baseline file even if present
#   --skip-clone-detection   Skip function clone detection (faster scans)
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

# DEBUG: Enable tracing (only in text mode to avoid corrupting JSON output)
DEBUG_TRACE="${DEBUG_TRACE:-0}"
# Note: Debug output is deferred until after OUTPUT_FORMAT is determined
# to prevent stderr pollution of JSON output (see Issue #1 from 2026-01-05)

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
SCRIPT_VERSION="1.0.97"

# Get the start/end line range for the enclosing function/method.
#
# We intentionally keep this heuristic and dependency-free (no AST). It is used
# to prevent context checks from leaking across adjacent functions/methods.
#
# Supports common PHP method declarations such as:
# - function foo() {}
# - public function foo() {}
# - private static function foo() {}
# - final protected function foo() {}
#
# Usage: get_function_scope_range "$file" "$lineno" [fallback_lines]
# Output: "start:end"
get_function_scope_range() {
  local file="$1"
  local lineno="$2"
  local fallback_lines="${3:-20}"

  # Match function/method declarations at the start of a line.
  # Note: We deliberately require whitespace after the 'function' keyword.
  local decl_regex='^[[:space:]]*([[:alnum:]_]+[[:space:]]+)*function[[:space:]]+'

  local start end
  start=$(awk -v line="$lineno" -v fallback="$fallback_lines" -v re="$decl_regex" '
    NR <= line && $0 ~ re { s=NR }
    END {
      if (s) { print s; exit }
      if (line > fallback) { print line - fallback } else { print 1 }
    }
  ' "$file")

  end=$(awk -v line="$lineno" -v re="$decl_regex" '
    NR > line && $0 ~ re { print NR-1; found=1; exit }
    END { if (!found) print NR }
  ' "$file")

  # Safety: ensure numeric bounds.
  if ! [[ "$start" =~ ^[0-9]+$ ]]; then start=1; fi
  if ! [[ "$end" =~ ^[0-9]+$ ]]; then end="$lineno"; fi
  if [ "$start" -lt 1 ]; then start=1; fi
  if [ "$end" -lt "$start" ]; then end="$start"; fi

  echo "${start}:${end}"
}

# Defaults
PATHS="."
STRICT=false
VERBOSE=false
ENABLE_LOGGING=true
OUTPUT_FORMAT="json"  # text or json (default: json for HTML reports)
CONTEXT_LINES=3       # Number of lines to show before/after findings (0 to disable)
# Note: 'tests' exclusion is dynamically removed when --paths targets a tests directory
EXCLUDE_DIRS="vendor node_modules .git tests .next dist build"
EXCLUDE_FILES="*.min.js *bundle*.js *.min.css"
DEFAULT_FIXTURE_VALIDATION_COUNT=20  # Number of fixtures to validate by default (can be overridden)
SKIP_CLONE_DETECTION=false  # Skip clone detection for faster scans

# ============================================================
# PHASE 1 STABILITY SAFEGUARDS (v1.0.82)
# ============================================================
# These limits prevent catastrophic hangs and runaway scans.
# Override via environment variables if needed.

# Maximum time (seconds) for a single pattern scan (0 = no limit)
MAX_SCAN_TIME="${MAX_SCAN_TIME:-300}"  # 5 minutes default

# Maximum files to process in aggregation/clone detection (0 = no limit)
MAX_FILES="${MAX_FILES:-10000}"  # 10k files default

# Maximum iterations in aggregation loops (0 = no limit)
MAX_LOOP_ITERATIONS="${MAX_LOOP_ITERATIONS:-50000}"  # 50k iterations default

# Maximum files for clone detection (0 = no limit)
# Clone detection has O(n²) complexity, so we limit it separately
MAX_CLONE_FILES="${MAX_CLONE_FILES:-100}"  # 100 files default (prevents timeouts)

# ============================================================
# PHASE 2 PERFORMANCE PROFILING (v1.0.83)
# ============================================================
# Enable with PROFILE=1 environment variable
# Outputs timing data for major operations to help identify bottlenecks

PROFILE="${PROFILE:-0}"  # Set to 1 to enable profiling
PROFILE_DATA=()          # Array to store timing data: "operation_name:duration_ms"
PROFILE_START_TIME=0     # Global start time for entire script

# ============================================================
# PHASE 3 PRIORITY 2: PROGRESS TRACKING (v1.0.85)
# ============================================================
# Track current section and display elapsed time for better UX

CURRENT_SECTION=""       # Name of currently running section
SECTION_START_TIME=0     # Start time of current section (seconds since epoch)

# Start profiling timer for a named operation
# Usage: profile_start "operation_name"
profile_start() {
  if [ "$PROFILE" = "1" ]; then
    PROFILE_SECTION_NAME="$1"
    PROFILE_SECTION_START=$(date +%s%N 2>/dev/null || echo "0")
  fi
}

# End profiling timer and record duration
# Usage: profile_end "operation_name"
profile_end() {
  if [ "$PROFILE" = "1" ]; then
    local end_time=$(date +%s%N 2>/dev/null || echo "0")
    if [ "$PROFILE_SECTION_START" != "0" ] && [ "$end_time" != "0" ]; then
      local duration_ns=$((end_time - PROFILE_SECTION_START))
      local duration_ms=$((duration_ns / 1000000))
      PROFILE_DATA+=("$1:${duration_ms}ms")
    fi
    PROFILE_SECTION_START=0
  fi
}

# Start tracking a section (shows section name and starts timer)
# Usage: section_start "Section Name"
section_start() {
  local section_name="$1"
  CURRENT_SECTION="$section_name"
  SECTION_START_TIME=$(date +%s 2>/dev/null || echo "0")

  # Display section name
  text_echo "${BLUE}→ Starting: ${section_name}${NC}"
}

# Display elapsed time for current section
# Usage: section_progress (call periodically during long operations)
section_progress() {
  if [ "$SECTION_START_TIME" != "0" ] && [ -n "$CURRENT_SECTION" ]; then
    local current_time=$(date +%s 2>/dev/null || echo "0")
    if [ "$current_time" != "0" ]; then
      local elapsed=$((current_time - SECTION_START_TIME))
      if [ "$elapsed" -gt 0 ]; then
        text_echo "  ${BLUE}⏱  ${CURRENT_SECTION}: ${elapsed}s elapsed...${NC}"
      fi
    fi
  fi
}

# End section tracking
# Usage: section_end
section_end() {
  CURRENT_SECTION=""
  SECTION_START_TIME=0
}

# Print profiling report at end of script
# Usage: profile_report
profile_report() {
  if [ "$PROFILE" = "1" ] && [ ${#PROFILE_DATA[@]} -gt 0 ]; then
    echo "" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "  PERFORMANCE PROFILE" >&2
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
    echo "" >&2

    # Sort by duration (descending) and display
    printf "%s\n" "${PROFILE_DATA[@]}" | \
      awk -F: '{
        gsub(/ms$/, "", $2);
        print $2 "\t" $1
      }' | \
      sort -rn | \
      awk '{
        duration = $1;
        $1 = "";
        operation = substr($0, 2);
        printf "  %6d ms  %s\n", duration, operation
      }' >&2

    echo "" >&2

    # Calculate total time
    if [ "$PROFILE_START_TIME" != "0" ]; then
      local end_time=$(date +%s%N 2>/dev/null || echo "0")
      if [ "$end_time" != "0" ]; then
        local total_ns=$((end_time - PROFILE_START_TIME))
        local total_ms=$((total_ns / 1000000))
        local total_sec=$((total_ms / 1000))
        echo "  Total scan time: ${total_sec}s (${total_ms}ms)" >&2
      fi
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
  fi
}

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

# Magic string violations collection (aggregated patterns)
# Note: Variable names kept as DRY_VIOLATIONS for backward compatibility
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
    --skip-clone-detection)
      SKIP_CLONE_DETECTION=true
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

# Safe debug output helper - only outputs in text mode to avoid JSON corruption
# Usage: debug_echo "message"
debug_echo() {
  if [ "$DEBUG_TRACE" = "1" ] && [ "$OUTPUT_FORMAT" = "text" ]; then
    echo "[DEBUG] $*" >&2
  fi
}

debug_echo "Arguments parsed. PATHS=$PATHS"
debug_echo "OUTPUT_FORMAT=$OUTPUT_FORMAT"
debug_echo "ENABLE_LOGGING=$ENABLE_LOGGING"

# If scanning a tests directory, remove 'tests' from exclusions
# Use portable method (no \b word boundary which is GNU-specific)
if echo "$PATHS" | grep -q "tests"; then
  EXCLUDE_DIRS="vendor node_modules .git .next dist build"
fi

# Build exclude arguments
EXCLUDE_ARGS=""
for dir in $EXCLUDE_DIRS; do
  EXCLUDE_ARGS="$EXCLUDE_ARGS --exclude-dir=$dir"
done
for file in $EXCLUDE_FILES; do
  EXCLUDE_ARGS="$EXCLUDE_ARGS --exclude=$file"
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

# SAFEGUARD: url_encode() function removed in v1.0.77
# Use url_encode_path() from common-helpers.sh instead
# This ensures consistent URL encoding across all file path handling

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
# Phase 1 Stability Functions
# ============================================================================

# Portable timeout wrapper (macOS Bash 3.2 compatible)
# Usage: run_with_timeout <seconds> <command> [args...]
# Returns: 0 if command succeeded, 124 if timeout, command's exit code otherwise
run_with_timeout() {
  local timeout_seconds="$1"
  shift

  # If timeout is 0 or MAX_SCAN_TIME is 0, run without timeout
  if [ "$timeout_seconds" -eq 0 ] || [ "$MAX_SCAN_TIME" -eq 0 ]; then
    "$@"
    return $?
  fi

  # Use Perl for portable timeout (available on macOS and Linux)
  perl -e '
    use strict;
    use warnings;

    my $timeout = shift @ARGV;
    my $pid = fork();

    if (!defined $pid) {
      die "Fork failed: $!\n";
    }

    if ($pid == 0) {
      # Child: exec the command
      exec @ARGV or die "Exec failed: $!\n";
    }

    # Parent: set alarm and wait
    eval {
      local $SIG{ALRM} = sub { die "timeout\n" };
      alarm $timeout;
      waitpid($pid, 0);
      alarm 0;
    };

    if ($@ eq "timeout\n") {
      kill 9, $pid;
      exit 124;  # GNU timeout exit code
    }

    exit($? >> 8);
  ' "$timeout_seconds" "$@"

  return $?
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

# Add a magic string violation to the collection
# Usage: add_dry_violation "pattern_title" "severity" "duplicated_string" "file_count" "total_count" "locations_json"
# Note: Function name kept as add_dry_violation for backward compatibility
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

  # Build magic string violations array
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
    "magic_string_violations": $DRY_VIOLATIONS_COUNT,
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
  "magic_string_violations": [$dry_violations_json]
}
EOF
}

# Generate HTML report from JSON output
# Usage: generate_html_report "json_string" "output_file" "log_file_path"
generate_html_report() {
  local json_data="$1"
  local output_file="$2"
  local log_file_path="${3:-}"
  local template_file="$SCRIPT_DIR/report-templates/report-template.html"

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
  local dry_violations_count=$(echo "$json_data" | jq '.magic_string_violations | length')

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
  # Note: For now, we assume a single path (most common case)
  # TODO: Handle multiple paths properly if needed in the future
  local paths_link=""
  local abs_path

  if [[ "$paths" = /* ]]; then
    abs_path="$paths"
  else
    # Use realpath for robust absolute path conversion
    abs_path=$(realpath "$paths" 2>/dev/null || echo "$paths")
  fi

  # SAFEGUARD: Use create_directory_link() instead of manual encoding/escaping
  # This ensures consistent handling of file paths with spaces and special characters (see common-helpers.sh)
  paths_link=$(create_directory_link "$abs_path")

  # Create clickable link for JSON log file if provided
  local json_log_link=""
  if [ -n "$log_file_path" ] && [ -f "$log_file_path" ]; then
    # SAFEGUARD: Use create_file_link() instead of manual encoding/escaping
    # This ensures consistent handling of file paths with spaces and special characters (see common-helpers.sh)
    local log_link=$(create_file_link "$log_file_path")
    json_log_link="<div style=\"margin-top: 8px;\">JSON Log: $log_link <button class=\"copy-btn\" onclick=\"copyLogPath()\" title=\"Copy JSON log path to clipboard\">📋 Copy Path</button></div>"
  fi

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
      local encoded_file_path=$(url_encode_path "$abs_file_path")

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

  # Generate Magic String violations HTML
  local dry_violations_html=""
  if [ "$dry_violations_count" -gt 0 ]; then
    dry_violations_html=$(echo "$json_data" | jq -r '.magic_string_violations[] |
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
    dry_violations_html="<p style='text-align: center; color: #6c757d; padding: 20px;'>No magic strings detected. Great job! 🎉</p>"
  fi

  # Read template and replace placeholders
  local html_content
  html_content=$(cat "$template_file")

  # Escape paths for JavaScript (escape backslashes, quotes, and newlines)
  local js_abs_path=$(echo "$abs_path" | sed "s/\\\\/\\\\\\\\/g; s/'/\\\'/g; s/\"/\\\\\"/g")
  local js_log_path=""
  if [ -n "$log_file_path" ] && [ -f "$log_file_path" ]; then
    js_log_path=$(echo "$log_file_path" | sed "s/\\\\/\\\\\\\\/g; s/'/\\\'/g; s/\"/\\\\\"/g")
  fi

  # Replace all placeholders
  html_content="${html_content//\{\{PROJECT_INFO\}\}/$project_info_html}"
  html_content="${html_content//\{\{VERSION\}\}/$version}"
  html_content="${html_content//\{\{TIMESTAMP\}\}/$timestamp}"
  html_content="${html_content//\{\{PATHS_SCANNED\}\}/$paths_link}"
  html_content="${html_content//\{\{JSON_LOG_LINK\}\}/$json_log_link}"
  html_content="${html_content//\{\{JS_FOLDER_PATH\}\}/$js_abs_path}"
  html_content="${html_content//\{\{JS_LOG_PATH\}\}/$js_log_path}"
  html_content="${html_content//\{\{TOTAL_ERRORS\}\}/$total_errors}"
  html_content="${html_content//\{\{TOTAL_WARNINGS\}\}/$total_warnings}"
  html_content="${html_content//\{\{MAGIC_STRING_VIOLATIONS_COUNT\}\}/$dry_violations_count}"
  html_content="${html_content//\{\{BASELINED\}\}/$baselined}"
  html_content="${html_content//\{\{STALE_BASELINE\}\}/$stale_baseline}"
  html_content="${html_content//\{\{EXIT_CODE\}\}/$exit_code}"
  html_content="${html_content//\{\{STRICT_MODE\}\}/$strict_mode}"
  html_content="${html_content//\{\{STATUS_CLASS\}\}/$status_class}"
  html_content="${html_content//\{\{STATUS_MESSAGE\}\}/$status_message}"
  html_content="${html_content//\{\{FINDINGS_COUNT\}\}/$findings_count}"
  html_content="${html_content//\{\{FINDINGS_HTML\}\}/$findings_html}"
  html_content="${html_content//\{\{MAGIC_STRING_VIOLATIONS_HTML\}\}/$dry_violations_html}"
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
  # Use fixed-string matching to avoid regex escaping issues in patterns.
  # IMPORTANT: Do NOT append "|| echo 0" here, because grep -c prints "0" even
  # when it exits with status 1 (no matches). Adding a fallback creates "0\n0"
  # which breaks integer comparisons.
  actual_count=$(grep -cF "$pattern" "$fixture_file" 2>/dev/null)
  actual_count=${actual_count:-0}

  [ "${NEOCHROME_DEBUG:-}" = "1" ] && echo "[DEBUG] $fixture_file: pattern='$pattern' expected=$expected_count actual=$actual_count" >&2

  if [ "$actual_count" -ge "$expected_count" ]; then
    return 0  # Passed
  else
    return 1  # Failed
  fi
}

# Validate mitigation-based severity adjustment for a known-bad fixture.
# This asserts that get_adjusted_severity() returns the expected adjusted severity
# and includes required mitigation tags.
#
# Format tokens are comma-separated (e.g., "caching,ids-only,admin-only").
#
# Usage:
#   validate_mitigation_adjustment \
#     "fixture_file" "line_pattern" "base_severity" "expected_severity" "required_tokens_csv"
validate_mitigation_adjustment() {
  local fixture_file="$1"
  local line_pattern="$2"
  local base_severity="$3"
  local expected_severity="$4"
  local required_tokens_csv="$5"

  local lineno
  lineno=$(grep -nF "$line_pattern" "$fixture_file" 2>/dev/null | head -1 | cut -d: -f1)
  if ! [[ "$lineno" =~ ^[0-9]+$ ]]; then
    [ "${NEOCHROME_DEBUG:-}" = "1" ] && echo "[DEBUG] mitigation: unable to locate line_pattern='$line_pattern' in $fixture_file" >&2
    return 1
  fi

  local mitigation_result adjusted_severity mitigations
  mitigation_result=$(get_adjusted_severity "$fixture_file" "$lineno" "$base_severity")
  adjusted_severity=$(echo "$mitigation_result" | cut -d'|' -f1)
  mitigations=$(echo "$mitigation_result" | cut -d'|' -f2)

  if [ "$adjusted_severity" != "$expected_severity" ]; then
    [ "${NEOCHROME_DEBUG:-}" = "1" ] && echo "[DEBUG] mitigation: expected='$expected_severity' actual='$adjusted_severity' mitigations='$mitigations' file=$fixture_file:$lineno" >&2
    return 1
  fi

  local token
  local IFS=','
  for token in $required_tokens_csv; do
    # Ensure exact token match within comma-separated list.
    if ! echo ",${mitigations}," | grep -q ",${token},"; then
      [ "${NEOCHROME_DEBUG:-}" = "1" ] && echo "[DEBUG] mitigation: missing token='$token' mitigations='$mitigations' file=$fixture_file:$lineno" >&2
      return 1
    fi
  done

  return 0
}

# Run fixture validation suite
# Uses direct pattern matching (no subprocesses) to verify detection works
# Returns: Sets FIXTURE_VALIDATION_PASSED, FIXTURE_VALIDATION_FAILED, FIXTURE_VALIDATION_STATUS
run_fixture_validation() {
  local fixtures_dir="$SCRIPT_DIR/../tests/fixtures"
  local default_fixture_count="${DEFAULT_FIXTURE_VALIDATION_COUNT:-8}"

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
    # ajax-antipatterns.php should register REST routes without pagination
    "ajax-antipatterns.php:register_rest_route:1"
    # ajax-antipatterns.php should include AJAX handlers without nonce validation
    "ajax-antipatterns.php:wp_ajax_nopriv_npt_load_feed:1"
    # admin-no-capability.php should register admin menus without capability checks
    "admin-no-capability.php:add_menu_page:1"
    # wpdb-no-prepare.php should include direct wpdb queries without prepare()
    "wpdb-no-prepare.php:wpdb->get_var:1"

    # OOM / memory fixtures
    "unbounded-wc-get-orders.php:wc_get_orders:1"
    "unbounded-wc-get-products.php:wc_get_products:1"
    "wp-query-unbounded.php:posts_per_page:1"
    "MITIGATION:wp-query-unbounded-mitigated.php:new WP_Query:CRITICAL:LOW:caching,ids-only,admin-only"
    "MITIGATION:wp-query-unbounded-mitigated-1.php:new WP_Query:CRITICAL:HIGH:caching"
    "MITIGATION:wp-query-unbounded-mitigated-2.php:new WP_Query:CRITICAL:MEDIUM:caching,admin-only"
    "MITIGATION:wp-query-unbounded-class-method-scope.php:new WP_Query:CRITICAL:CRITICAL:"
    "MITIGATION:wp-query-unbounded-private-static-method-scope.php:new WP_Query:CRITICAL:CRITICAL:"
    "MITIGATION:wp-query-unbounded-admin-only-class-method.php:new WP_Query:CRITICAL:HIGH:admin-only"
    "wp-user-query-meta-bloat.php:new WP_User_Query:1"
    "limit-multiplier-from-count.php:count( \$user_ids ):1"
    "array-merge-in-loop.php:array_merge:1"
  )

  local fixture_count="$default_fixture_count"

  # Template override
  if [ -n "${FIXTURE_COUNT:-}" ]; then
    fixture_count="$FIXTURE_COUNT"
  fi

  # Environment variable override
  if [ -n "${FIXTURE_VALIDATION_COUNT:-}" ]; then
    fixture_count="$FIXTURE_VALIDATION_COUNT"
  fi

  # Validate fixture_count (must be non-negative integer)
  if ! [[ "$fixture_count" =~ ^[0-9]+$ ]]; then
    fixture_count="$default_fixture_count"
  fi

  if [ "$fixture_count" -le 0 ]; then
    FIXTURE_VALIDATION_STATUS="skipped"
    return 0
  fi

  local max_checks=${#checks[@]}
  if [ "$fixture_count" -gt "$max_checks" ]; then
    fixture_count="$max_checks"
  fi

  local checks_to_run=("${checks[@]:0:${fixture_count}}")

  for check_spec in "${checks_to_run[@]}"; do
    local field1 field2 field3 field4 field5 field6
    IFS=':' read -r field1 field2 field3 field4 field5 field6 <<< "$check_spec"

    if [ "$field1" = "MITIGATION" ]; then
      local fixture_file line_pattern base_severity expected_severity required_tokens
      fixture_file="$field2"
      line_pattern="$field3"
      base_severity="$field4"
      expected_severity="$field5"
      required_tokens="$field6"

      if [ -f "$fixtures_dir/$fixture_file" ]; then
        if validate_mitigation_adjustment "$fixtures_dir/$fixture_file" "$line_pattern" "$base_severity" "$expected_severity" "$required_tokens"; then
          ((FIXTURE_VALIDATION_PASSED++))
        else
          ((FIXTURE_VALIDATION_FAILED++))
        fi
      fi
    else
      local fixture_file pattern expected_count
      fixture_file="$field1"
      pattern="$field2"
      expected_count="$field3"

      if [ -f "$fixtures_dir/$fixture_file" ]; then
        if validate_single_fixture "$fixtures_dir/$fixture_file" "$pattern" "$expected_count"; then
          ((FIXTURE_VALIDATION_PASSED++))
        else
          ((FIXTURE_VALIDATION_FAILED++))
        fi
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

# ============================================================
# Context-Aware Detection Helpers
# ============================================================

# Find callback function in same file and check for capability checks
# Usage: find_callback_capability_check "file.php" "callback_function_name"
# Returns: 0 if capability check found, 1 if not found
find_callback_capability_check() {
  local file="$1"
  local callback_name="$2"

  # Sanitize callback name (remove quotes, whitespace)
  callback_name=$(echo "$callback_name" | sed "s/['\"]//g" | tr -d '[:space:]')

  # Skip if callback is empty or looks like a variable/array
  if [ -z "$callback_name" ] || [[ "$callback_name" =~ ^\$ ]] || [[ "$callback_name" =~ \[ ]]; then
    return 1
  fi

  # Find function definition line number
  # Match: function callback_name( or function callback_name (
  local func_line
  func_line=$(grep -n "^[[:space:]]*function[[:space:]]\+${callback_name}[[:space:]]*(" "$file" 2>/dev/null | head -1 | cut -d: -f1)

  # If not found, try method definition: public/private/protected [static] function callback_name(
  if [ -z "$func_line" ]; then
    func_line=$(grep -n "^[[:space:]]*\(public\|private\|protected\)[[:space:]]\+\(static[[:space:]]\+\)\?function[[:space:]]\+${callback_name}[[:space:]]*(" "$file" 2>/dev/null | head -1 | cut -d: -f1)
  fi

  # If still not found, callback is not in this file
  if [ -z "$func_line" ]; then
    return 1
  fi

  # Check next 50 lines of function body for capability check
  local end_line=$((func_line + 50))
  local func_body
  func_body=$(sed -n "${func_line},${end_line}p" "$file" 2>/dev/null)

  # Look for capability check patterns
  if echo "$func_body" | grep -qE "current_user_can[[:space:]]*\\(|user_can[[:space:]]*\\(|is_super_admin[[:space:]]*\\("; then
    return 0  # Capability check found
  fi

  # Also check for WordPress menu functions with capability parameter
  if echo "$func_body" | grep -qE "add_(menu|submenu|options|management|theme|plugins|users|dashboard|posts|media|pages|comments|tools)_page[[:space:]]*\\(" && \
     echo "$func_body" | grep -qE "'(manage_options|edit_posts|edit_pages|edit_published_posts|publish_posts|read|delete_posts|administrator|editor|author|contributor|subscriber)'"; then
    return 0  # Capability enforced via menu function
  fi

  return 1  # No capability check found
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

# Process aggregated pattern (Magic String Detector)
# Usage: process_aggregated_pattern "pattern_file"
#
# PERFORMANCE NOTE: Aggregated patterns are the most expensive operations in the scanner.
# They perform multiple passes over the codebase:
# 1. Initial grep to find all matches (can be 1000s of results)
# 2. Extract and aggregate by captured group (nested loops)
# 3. Build JSON structures for each unique violation
#
# Typical performance on large codebases:
# - Magic string detection: 10-60s (depends on string count)
# - Clone detection: 30-120s (depends on function count)
#
# Phase 1 safeguards applied:
# - MAX_SCAN_TIME timeout on initial grep
# - MAX_FILES limit on file processing
# - MAX_LOOP_ITERATIONS limit on aggregation loops
process_aggregated_pattern() {
  local pattern_file="$1"

  # Load pattern metadata
  if ! load_pattern "$pattern_file"; then
    debug_echo "Failed to load pattern: $pattern_file"
    return 1
  fi

  # Debug: Log loaded pattern info
  debug_echo "==========================================="
  debug_echo "Processing pattern: $pattern_file"
  debug_echo "Pattern ID: $pattern_id"
  debug_echo "Pattern Title: $pattern_title"
  debug_echo "Pattern Enabled: $pattern_enabled"
  debug_echo "Pattern Search (length=${#pattern_search}): [$pattern_search]"
  debug_echo "==========================================="

  # Skip if pattern is disabled
  if [ "$pattern_enabled" != "true" ]; then
    debug_echo "Pattern disabled, skipping"
    return 0
  fi

  # Check if pattern_search is empty
  if [ -z "$pattern_search" ]; then
    debug_echo "ERROR: pattern_search is EMPTY!"
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

  debug_echo "Aggregation settings: min_files=$min_files, min_matches=$min_matches, capture_group=$capture_group"

  # Create temp files for aggregation
  local temp_matches=$(mktemp)

  # Run grep to find all matches using the pattern's search pattern
  # Note: pattern_search is set by load_pattern
  # SAFEGUARD: "$PATHS" MUST be quoted - paths with spaces will break otherwise
  # PERFORMANCE: Wrap grep in timeout to prevent hangs on large codebases
  debug_echo "Running grep with pattern: $pattern_search"
  debug_echo "Paths: $PATHS"
  debug_echo "File patterns: $pattern_file_patterns"

  # Build --include flags from pattern_file_patterns (supports PHP, JS, TS, etc.)
  local include_args=""
  for ext in $pattern_file_patterns; do
    include_args="$include_args --include=$ext"
  done

  # Run grep with timeout (don't use || true here - it swallows exit codes)
  local matches
  local grep_exit_code=0
  matches=$(run_with_timeout "$MAX_SCAN_TIME" grep -rHn $EXCLUDE_ARGS $include_args -E "$pattern_search" "$PATHS" 2>/dev/null) || grep_exit_code=$?

  # Check for timeout (exit code 124)
  if [ "$grep_exit_code" -eq 124 ]; then
    text_echo "  ${RED}⚠ Scan timeout after ${MAX_SCAN_TIME}s - skipping pattern${NC}"
    rm -f "$temp_matches"
    return 1
  fi
  # Exit codes 1-2 from grep are normal (no matches or errors), continue processing

  # Count matches (grep -c returns 0 if no matches, so no need for || echo "0")
  local match_count=$(echo "$matches" | grep -c . 2>/dev/null)
  # Ensure match_count is a valid integer (default to 0 if empty/invalid)
  match_count=${match_count:-0}
  debug_echo "Found $match_count raw matches"

  # SAFETY: Check if match count exceeds file limit (rough proxy for file count)
  if [ "$MAX_FILES" -gt 0 ] && [ "$match_count" -gt "$((MAX_FILES * 10))" ]; then
    text_echo "  ${RED}⚠ Match count ($match_count) suggests excessive file processing - skipping pattern${NC}"
    rm -f "$temp_matches"
    return 1
  fi

  # Extract captured groups and aggregate
  if [ -n "$matches" ]; then
    local iteration=0
    while IFS= read -r match; do
      [ -z "$match" ] && continue

      # SAFETY: Prevent infinite loops
      iteration=$((iteration + 1))
      if [ "$MAX_LOOP_ITERATIONS" -gt 0 ] && [ "$iteration" -gt "$MAX_LOOP_ITERATIONS" ]; then
        text_echo "  ${RED}⚠ Max iterations ($MAX_LOOP_ITERATIONS) reached - truncating results${NC}"
        break
      fi

      local file=$(echo "$match" | cut -d: -f1)
      local line=$(echo "$match" | cut -d: -f2)
      local code=$(echo "$match" | cut -d: -f3-)

      # Extract the captured string using grep and sed
      # We use a simplified sed pattern that extracts the content between quotes
      # This works for most magic string patterns which capture string literals
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

      local string_iteration=0
      while IFS= read -r string; do
        [ -z "$string" ] && continue

        # SAFETY: Prevent infinite loops in aggregation
        string_iteration=$((string_iteration + 1))
        if [ "$MAX_LOOP_ITERATIONS" -gt 0 ] && [ "$string_iteration" -gt "$MAX_LOOP_ITERATIONS" ]; then
          text_echo "  ${RED}⚠ Max string aggregation iterations ($MAX_LOOP_ITERATIONS) reached - truncating results${NC}"
          break
        fi

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

          # Add to magic string violations
          add_dry_violation "$pattern_title" "$pattern_severity" "$unescaped_string" "$file_count" "$total_count" "$locations_json"
        fi
      done <<< "$unique_strings"
    fi
  fi

  # Cleanup
  rm -f "$temp_matches"
}

# Process clone detection pattern (Function Clone Detector)
# Usage: process_clone_detection "pattern_file"
process_clone_detection() {
  local pattern_file="$1"

  # Load pattern metadata
  if ! load_pattern "$pattern_file"; then
    debug_echo "Failed to load pattern: $pattern_file"
    return 1
  fi

  # Skip if pattern is disabled
  if [ "$pattern_enabled" != "true" ]; then
    debug_echo "Pattern disabled, skipping"
    return 0
  fi

  # Extract settings from JSON
  local min_files=$(grep '"min_distinct_files"' "$pattern_file" | sed 's/.*:[[:space:]]*\([0-9]*\).*/\1/')
  local min_matches=$(grep '"min_total_matches"' "$pattern_file" | sed 's/.*:[[:space:]]*\([0-9]*\).*/\1/')
  local min_lines=$(grep '"min_lines"' "$pattern_file" | sed 's/.*:[[:space:]]*\([0-9]*\).*/\1/')
  local max_lines=$(grep '"max_lines"' "$pattern_file" | sed 's/.*:[[:space:]]*\([0-9]*\).*/\1/')

  # Defaults
  [ -z "$min_files" ] && min_files=2
  [ -z "$min_matches" ] && min_matches=2
  [ -z "$min_lines" ] && min_lines=5
  [ -z "$max_lines" ] && max_lines=500

  debug_echo "Clone detection settings: min_files=$min_files, min_matches=$min_matches, min_lines=$min_lines, max_lines=$max_lines"

  # Create temp files
  local temp_functions=$(mktemp)
  local temp_hashes=$(mktemp)

  # Find all PHP files
  # SAFEGUARD: Handle both single files and directories
  local php_files=""
  if [ -f "$PATHS" ]; then
    # Single file provided
    php_files="$PATHS"
  else
    # Directory provided - find all PHP files
    # PERFORMANCE: Wrap find in timeout to prevent hangs
    local find_exit_code=0
    php_files=$(run_with_timeout "$MAX_SCAN_TIME" find "$PATHS" -name "*.php" -type f 2>/dev/null | grep -v '/vendor/' | grep -v '/node_modules/') || find_exit_code=$?

    # Check for timeout (exit code 124)
    if [ "$find_exit_code" -eq 124 ]; then
      text_echo "  ${RED}⚠ File scan timeout after ${MAX_SCAN_TIME}s - skipping pattern${NC}"
      rm -f "$temp_functions" "$temp_hashes"
      return 1
    fi
    # Other exit codes (no files found, etc.) are OK, continue
  fi

  if [ -z "$php_files" ]; then
    debug_echo "No PHP files found in: $PATHS"
    rm -f "$temp_functions" "$temp_hashes"
    return 0
  fi

  local file_count=$(echo "$php_files" | wc -l | tr -d ' ')
  debug_echo "PHP files to scan: $file_count files"

  # SAFETY: Check file count limit (use MAX_CLONE_FILES for clone detection)
  if [ "$MAX_CLONE_FILES" -gt 0 ] && [ "$file_count" -gt "$MAX_CLONE_FILES" ]; then
    text_echo "  ${YELLOW}⚠ File count ($file_count) exceeds clone detection limit ($MAX_CLONE_FILES)${NC}"
    text_echo "  ${YELLOW}  Skipping clone detection to prevent timeout. Set MAX_CLONE_FILES=0 to disable limit.${NC}"
    rm -f "$temp_functions" "$temp_hashes"
    return 1
  fi

  # Show warning if approaching limit
  if [ "$MAX_CLONE_FILES" -gt 0 ] && [ "$file_count" -gt $((MAX_CLONE_FILES * 80 / 100)) ]; then
    text_echo "  ${YELLOW}⚠ Processing $file_count files (limit: $MAX_CLONE_FILES) - this may take a while...${NC}"
  fi

  # Extract all functions and compute hashes
  debug_echo "Extracting functions from PHP files..."

  local file_iteration=0
  local last_progress_time=$(date +%s 2>/dev/null || echo "0")

  safe_file_iterator "$php_files" | while IFS= read -r file; do
    [ -z "$file" ] && continue

    # SAFETY: Track file processing iterations (use MAX_CLONE_FILES for clone detection)
    file_iteration=$((file_iteration + 1))
    if [ "$MAX_CLONE_FILES" -gt 0 ] && [ "$file_iteration" -gt "$MAX_CLONE_FILES" ]; then
      debug_echo "Max clone file limit reached, stopping extraction"
      break
    fi

    # PROGRESS: Show progress every 10 seconds
    local current_time=$(date +%s 2>/dev/null || echo "0")
    if [ "$current_time" != "0" ] && [ "$last_progress_time" != "0" ]; then
      local time_diff=$((current_time - last_progress_time))
      if [ "$time_diff" -ge 10 ]; then
        section_progress
        text_echo "  ${BLUE}  Processing file $file_iteration of $file_count...${NC}"
        last_progress_time=$current_time
      fi
    fi

    # Extract functions using grep with Perl regex
    # Pattern matches: function name(...) { ... }
    grep -n 'function[[:space:]]\+[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*(' "$file" 2>/dev/null | while IFS=: read -r start_line func_header; do
      # Extract function name
      local func_name=$(echo "$func_header" | sed -E 's/.*function[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*).*/\1/')

      # Skip magic methods and test methods
      if echo "$func_name" | grep -qE '^(__construct|__destruct|__get|__set|__call|__toString|test_|setUp|tearDown)'; then
        continue
      fi

      # Extract function body (simplified: from function line to next function or end of file)
      # This is a heuristic - we'll grab the next 100 lines and look for the closing brace
      local func_body=$(tail -n +$start_line "$file" | head -n 100)

      # Count lines in function body (rough estimate)
      local line_count=$(echo "$func_body" | wc -l | tr -d ' ')

      # Skip if too short or too long
      if [ "$line_count" -lt "$min_lines" ] || [ "$line_count" -gt "$max_lines" ]; then
        continue
      fi

      # Normalize function body:
      # 1. Remove inline comments (// ...)
      # 2. Remove block comments (/* ... */)
      # 3. Normalize whitespace (multiple spaces -> single space)
      # 4. Remove empty lines
      local normalized=$(echo "$func_body" | \
        sed 's|//.*$||g' | \
        sed 's|/\*.*\*/||g' | \
        sed 's/[[:space:]]\+/ /g' | \
        sed '/^[[:space:]]*$/d')

      # Compute hash
      local hash=$(echo "$normalized" | md5sum | cut -d' ' -f1)

      # Store: hash|file|function_name|line_number|line_count
      echo "$hash|$file|$func_name|$start_line|$line_count" >> "$temp_functions"
    done
  done

  # Check if we found any functions
  if [ ! -s "$temp_functions" ]; then
    debug_echo "No functions found"
    rm -f "$temp_functions" "$temp_hashes"
    return 0
  fi

  # Aggregate by hash
  debug_echo "Aggregating by hash..."
  local unique_hashes=$(cut -d'|' -f1 "$temp_functions" | sort -u)
  local total_hashes=$(echo "$unique_hashes" | wc -l | tr -d ' ')

  local hash_iteration=0
  local last_hash_progress_time=$(date +%s 2>/dev/null || echo "0")

  while IFS= read -r hash; do
    [ -z "$hash" ] && continue

    # SAFETY: Prevent infinite loops in hash aggregation
    hash_iteration=$((hash_iteration + 1))
    if [ "$MAX_LOOP_ITERATIONS" -gt 0 ] && [ "$hash_iteration" -gt "$MAX_LOOP_ITERATIONS" ]; then
      text_echo "  ${RED}⚠ Max hash aggregation iterations ($MAX_LOOP_ITERATIONS) reached - truncating results${NC}"
      break
    fi

    # PROGRESS: Show progress every 10 seconds during hash aggregation
    local current_time=$(date +%s 2>/dev/null || echo "0")
    if [ "$current_time" != "0" ] && [ "$last_hash_progress_time" != "0" ]; then
      local time_diff=$((current_time - last_hash_progress_time))
      if [ "$time_diff" -ge 10 ]; then
        section_progress
        text_echo "  ${BLUE}  Analyzing hash $hash_iteration of $total_hashes...${NC}"
        last_hash_progress_time=$current_time
      fi
    fi

    # Count files and total occurrences for this hash
    local file_count=$(grep "^$hash|" "$temp_functions" | cut -d'|' -f2 | sort -u | wc -l | tr -d ' ')
    local total_count=$(grep "^$hash|" "$temp_functions" | wc -l | tr -d ' ')

    # Apply thresholds
    if [ "$file_count" -ge "$min_files" ] && [ "$total_count" -ge "$min_matches" ]; then
      # Get function name and line count from first occurrence
      local first_occurrence=$(grep "^$hash|" "$temp_functions" | head -1)
      local func_name=$(echo "$first_occurrence" | cut -d'|' -f3)
      local line_count=$(echo "$first_occurrence" | cut -d'|' -f5)

      # Build locations JSON array
      local locations_json="["
      local first_loc=true
      while IFS='|' read -r h file fname line lc; do
        if [ "$h" = "$hash" ]; then
          if [ "$first_loc" = false ]; then
            locations_json+=","
          fi
          locations_json+="{\"file\":\"$(json_escape "$file")\",\"line\":$line,\"function\":\"$(json_escape "$fname")\"}"
          first_loc=false
        fi
      done < "$temp_functions"
      locations_json+="]"

      # Add to violations with function name as the "duplicated_string"
      add_dry_violation "$pattern_title" "$pattern_severity" "$func_name (${line_count} lines)" "$file_count" "$total_count" "$locations_json"
    fi
  done <<< "$unique_hashes"

  # Cleanup
  rm -f "$temp_functions" "$temp_hashes"
}

# ============================================================================
# Main Script Output
# ============================================================================

debug_echo "Starting main script execution"
debug_echo "PATHS=$PATHS"
debug_echo "OUTPUT_FORMAT=$OUTPUT_FORMAT"

# Load existing baseline (if any) before running checks
debug_echo "Loading baseline..."
load_baseline
debug_echo "Baseline loaded"

# Detect project info for display
# Preserve full path even if it contains spaces
FIRST_PATH="$PATHS"
debug_echo "Detecting project info..."
PROJECT_INFO_JSON=$(detect_project_info "$FIRST_PATH")
debug_echo "Project info detected"
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

text_echo "Scanning paths: $PATHS"
text_echo "Strict mode: $STRICT"
if [ "$ENABLE_LOGGING" = true ] && [ "$OUTPUT_FORMAT" = "text" ]; then
	text_echo "Logging to: $LOG_FILE"
fi
text_echo ""

debug_echo "Starting checks..."

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
#
# PERFORMANCE NOTE: This function performs recursive grep operations which can be expensive
# on large codebases. Each call scans all PHP files matching the pattern. On a typical
# WordPress installation with plugins:
# - Small (< 100 files): < 1s per check
# - Medium (100-1000 files): 1-5s per check
# - Large (> 1000 files): 5-30s per check
# - Very large (> 10000 files): May hit MAX_SCAN_TIME timeout
#
# Optimization opportunities (Phase 2-3):
# - Cache file list across checks (currently rescans for each pattern)
# - Parallelize independent checks
# - Use ripgrep/ag if available (10-100x faster than grep)
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

# ============================================================
# START PROFILING
# ============================================================
if [ "$PROFILE" = "1" ]; then
  PROFILE_START_TIME=$(date +%s%N 2>/dev/null || echo "0")
fi

profile_start "CRITICAL_CHECKS"
section_start "Critical Checks"
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
# Enhancement v1.0.93: Add nonce verification detection to reduce false positives
SUPERGLOBAL_SEVERITY=$(get_severity "spo-002-superglobals" "HIGH")
SUPERGLOBAL_COLOR="${YELLOW}"
if [ "$SUPERGLOBAL_SEVERITY" = "CRITICAL" ] || [ "$SUPERGLOBAL_SEVERITY" = "HIGH" ]; then SUPERGLOBAL_COLOR="${RED}"; fi
text_echo "${BLUE}▸ Direct superglobal manipulation ${SUPERGLOBAL_COLOR}[$SUPERGLOBAL_SEVERITY]${NC}"
SUPERGLOBAL_FAILED=false
SUPERGLOBAL_FINDING_COUNT=0
SUPERGLOBAL_VISIBLE=""

# Find all superglobal manipulation patterns
SUPERGLOBAL_MATCHES=$(grep -rHn $EXCLUDE_ARGS --include="*.php" -E "unset\\(\\$_(GET|POST|REQUEST|COOKIE)\\[|\\$_(GET|POST|REQUEST)[[:space:]]*=|\\$_(GET|POST|REQUEST|COOKIE)\\[[^]]*\\][[:space:]]*=" "$PATHS" 2>/dev/null | \
  grep -v '//.*\$_' || true)

if [ -n "$SUPERGLOBAL_MATCHES" ]; then
  while IFS= read -r match; do
    [ -z "$match" ] && continue
    file=$(echo "$match" | cut -d: -f1)
    lineno=$(echo "$match" | cut -d: -f2)
    code=$(echo "$match" | cut -d: -f3-)

    if ! [[ "$lineno" =~ ^[0-9]+$ ]]; then
      continue
    fi

    # FALSE POSITIVE REDUCTION: Check for nonce verification near the match,
    # clamped to the current function/method to avoid cross-function leakage.
    range=$(get_function_scope_range "$file" "$lineno" 30)
    function_start=${range%%:*}
    start_line=$((lineno - 20))
    [ "$start_line" -lt "$function_start" ] && start_line="$function_start"
    [ "$start_line" -lt 1 ] && start_line=1
    context=$(sed -n "${start_line},${lineno}p" "$file" 2>/dev/null || true)

    # If nonce verification exists, suppress this finding (it's protected)
    if echo "$context" | grep -qE "wp_verify_nonce[[:space:]]*\\(|check_admin_referer[[:space:]]*\\(|wp_nonce_field[[:space:]]*\\("; then
      continue
    fi

    if should_suppress_finding "spo-002-superglobals" "$file"; then
      continue
    fi

    SUPERGLOBAL_FAILED=true
    ((SUPERGLOBAL_FINDING_COUNT++))
    add_json_finding "spo-002-superglobals" "error" "$SUPERGLOBAL_SEVERITY" "$file" "$lineno" "Direct superglobal manipulation" "$code"

    if [ -z "$SUPERGLOBAL_VISIBLE" ]; then
      SUPERGLOBAL_VISIBLE="$match"
    else
      SUPERGLOBAL_VISIBLE="${SUPERGLOBAL_VISIBLE}
$match"
    fi
  done <<< "$SUPERGLOBAL_MATCHES"
fi

if [ "$SUPERGLOBAL_FAILED" = true ]; then
  if [ "$SUPERGLOBAL_SEVERITY" = "CRITICAL" ] || [ "$SUPERGLOBAL_SEVERITY" = "HIGH" ]; then
    text_echo "${RED}  ✗ FAILED${NC}"
    ((ERRORS++))
  else
    text_echo "${YELLOW}  ⚠ WARNING${NC}"
    ((WARNINGS++))
  fi
  if [ "$OUTPUT_FORMAT" = "text" ] && [ -n "$SUPERGLOBAL_VISIBLE" ]; then
    while IFS= read -r match; do
      [ -z "$match" ] && continue
      format_finding "$match"
    done <<< "$(echo "$SUPERGLOBAL_VISIBLE" | head -5)"
  fi
  add_json_check "Direct superglobal manipulation" "$SUPERGLOBAL_SEVERITY" "failed" "$SUPERGLOBAL_FINDING_COUNT"
else
  text_echo "${GREEN}  ✓ Passed${NC}"
  add_json_check "Direct superglobal manipulation" "$SUPERGLOBAL_SEVERITY" "passed" 0
fi
text_echo ""

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
# Exclude lines with: sanitize_*, esc_*, absint, intval, floatval, wc_clean, wp_unslash, $allowed_keys
# Note: We do NOT exclude isset/empty here because they don't sanitize - they only check existence
# We'll filter those out in a more sophisticated way below
# SAFEGUARD: "$PATHS" MUST be quoted - paths with spaces will break otherwise (see SAFEGUARDS.md)
UNSANITIZED_MATCHES=$(grep -rHn $EXCLUDE_ARGS --include="*.php" -E '\$_(GET|POST|REQUEST)\[' "$PATHS" 2>/dev/null | \
  grep -v 'sanitize_' | \
  grep -v 'esc_' | \
  grep -v 'absint' | \
  grep -v 'intval' | \
  grep -v 'floatval' | \
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

    range=$(get_function_scope_range "$file" "$lineno" 30)
    function_start=${range%%:*}

    # CONTEXT-AWARE DETECTION: Check for nonce verification in previous 10 lines
    # If nonce check found AND superglobal is sanitized, skip this finding
    # Also skip if $_POST is used WITHIN nonce verification function itself
    # Enhancement v1.0.93: Also detect strict comparison to literals as implicit sanitization
    has_nonce_protection=false

    # Special case: $_POST used inside nonce verification function is SAFE
    # Example: wp_verify_nonce( $_POST['nonce'], 'action' )
    if echo "$code" | grep -qE "(check_ajax_referer|wp_verify_nonce|check_admin_referer)[[:space:]]*\([^)]*\\\$_(GET|POST|REQUEST)\["; then
      has_nonce_protection=true
    fi

    # FALSE POSITIVE REDUCTION: Detect strict comparison to literals (boolean flags)
    # Pattern: isset( $_POST['key'] ) && $_POST['key'] === '1'
    # This is safe for boolean flags - value is constrained to literal
    if echo "$code" | grep -qE "\\\$_(GET|POST|REQUEST)\[[^]]*\][[:space:]]*===[[:space:]]*['\"][^'\"]*['\"]"; then
      # Check if nonce verification exists near this usage, clamped to function scope
      start_line=$((lineno - 20))
      [ "$start_line" -lt "$function_start" ] && start_line="$function_start"
      [ "$start_line" -lt 1 ] && start_line=1
      context=$(sed -n "${start_line},${lineno}p" "$file" 2>/dev/null || true)

      if echo "$context" | grep -qE "check_ajax_referer[[:space:]]*\(|wp_verify_nonce[[:space:]]*\(|check_admin_referer[[:space:]]*\("; then
        # Strict comparison to literal + nonce verification = SAFE
        has_nonce_protection=true
      fi
    fi

    if [ "$has_nonce_protection" = false ]; then
      start_line=$((lineno - 10))
      [ "$start_line" -lt "$function_start" ] && start_line="$function_start"
      [ "$start_line" -lt 1 ] && start_line=1

      # Get context (10 lines before current line)
      context=$(sed -n "${start_line},${lineno}p" "$file" 2>/dev/null || true)

      # Check for nonce verification functions
      if echo "$context" | grep -qE "check_ajax_referer[[:space:]]*\(|wp_verify_nonce[[:space:]]*\(|check_admin_referer[[:space:]]*\("; then
        # Nonce check found - now verify the current line has sanitization
        if echo "$code" | grep -qE "sanitize_|esc_|absint|intval|floatval|wc_clean"; then
          # This is SAFE: nonce verified AND sanitized
          has_nonce_protection=true
        fi
      fi
    fi

    # Skip if protected by nonce + sanitization
    if [ "$has_nonce_protection" = true ]; then
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
# Enhancement v1.0.93: Add variable tracking to detect prepared variables
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

    # FALSE POSITIVE REDUCTION: Check for nested prepare pattern
    # Pattern: $wpdb->query( $wpdb->prepare(...) )
    if echo "$code" | grep -qE '\$wpdb->(query|get_var|get_row|get_results|get_col)[[:space:]]*\([[:space:]]*\$wpdb->prepare'; then
      # Nested prepare detected - skip this finding
      continue
    fi

    # FALSE POSITIVE REDUCTION: Check if variable was prepared in previous lines
    # Pattern: $sql = $wpdb->prepare(...); ... $wpdb->get_col( $sql );
    # Extract variable name from $wpdb->get_*( $var )
    var_name=$(echo "$code" | sed -n 's/.*\$wpdb->[a-z_]*[[:space:]]*([[:space:]]*\(\$[a-zA-Z_][a-zA-Z0-9_]*\).*/\1/p')

    if [ -n "$var_name" ]; then
      range=$(get_function_scope_range "$file" "$lineno" 30)
      function_start=${range%%:*}

      # Check if this variable was assigned from $wpdb->prepare() within previous 20 lines
      # Increased from 10 to 20 to catch multi-line prepare statements (v1.0.94)
      start_line=$((lineno - 20))
      [ "$start_line" -lt "$function_start" ] && start_line="$function_start"
      [ "$start_line" -lt 1 ] && start_line=1
      context=$(sed -n "${start_line},${lineno}p" "$file" 2>/dev/null || true)

      # Escape $ for grep
      var_escaped=$(echo "$var_name" | sed 's/\$/\\$/g')

      # Check for pattern: $var = $wpdb->prepare(...)
      if echo "$context" | grep -qE "${var_escaped}[[:space:]]*=[[:space:]]*\\\$wpdb->prepare[[:space:]]*\("; then
        # Variable was prepared - skip this finding
        continue
      fi
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

    # First check: Look for capability check in immediate context (next 10 lines)
    # This includes:
    # - current_user_can() / user_can() / is_super_admin()
    # - WordPress menu functions with capability parameter (add_menu_page, add_submenu_page, etc.)
    if echo "$context" | grep -qE "current_user_can[[:space:]]*\\(|user_can[[:space:]]*\\(|is_super_admin[[:space:]]*\\("; then
      continue
    fi

    # Enhancement v1.0.93: Parse capability parameter from add_*_page() functions
    # add_submenu_page() 4th parameter is capability
    # add_menu_page() 4th parameter is capability
    # add_options_page() 3rd parameter is capability
    # Pattern: add_*_page(..., 'capability', ...)
    if echo "$context" | grep -qE "add_(menu|submenu|options|management|theme|plugins|users|dashboard|posts|media|pages|comments|tools)_page[[:space:]]*\\("; then
      # Extract the full function call (may span multiple lines)
      full_call=$(sed -n "${start_line},${end_line}p" "$file" 2>/dev/null | tr '\n' ' ')

      # Check for common WordPress capabilities in the function call
      # This includes: manage_options, manage_woocommerce, edit_posts, etc.
      if echo "$full_call" | grep -qE "'(manage_options|manage_woocommerce|edit_posts|edit_pages|edit_published_posts|publish_posts|read|delete_posts|edit_users|list_users|promote_users|create_users|delete_users|administrator|editor|author|contributor|subscriber)'"; then
        continue
      fi
    fi

    # Second check: If this is an add_action/add_filter with a callback, look up the callback function
    # Extract callback name from patterns like: add_action('hook', 'callback_name')
    callback_name=""
    if echo "$code" | grep -qE "add_action|add_filter|add_menu_page|add_submenu_page|add_options_page|add_management_page"; then
      # Try to extract callback from common patterns:
      # Pattern 1: add_action( 'hook', 'callback' )
      callback_name=$(echo "$code" | sed -n "s/.*add_[a-z_]*[[:space:]]*([^,]*,[[:space:]]*['\"]\\([^'\"]*\\)['\"].*/\\1/p" | head -1)

      # Pattern 2: add_action( 'hook', [ $this, 'callback' ] ) or [ __CLASS__, 'callback' ]
      if [ -z "$callback_name" ]; then
        callback_name=$(echo "$code" | sed -n "s/.*\\[[^,]*,[[:space:]]*['\"]\\([^'\"]*\\)['\"].*/\\1/p" | head -1)
      fi

      # Pattern 3: add_action( 'hook', array( $this, 'callback' ) )
      if [ -z "$callback_name" ]; then
        callback_name=$(echo "$code" | sed -n "s/.*array[[:space:]]*([^,]*,[[:space:]]*['\"]\\([^'\"]*\\)['\"].*/\\1/p" | head -1)
      fi

      # If we found a callback name, check if it has capability checks
      if [ -n "$callback_name" ] && find_callback_capability_check "$file" "$callback_name"; then
        continue
      fi
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
  # SAFEGUARD: Use safe_file_iterator() instead of "for file in $AJAX_FILES"
  # File paths with spaces will break the loop without this helper (see common-helpers.sh)
  safe_file_iterator "$AJAX_FILES" | while IFS= read -r file; do
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

# ============================================================================
# Helper Functions: Mitigation Detection for Unbounded Queries
# ============================================================================
# These functions detect mitigating factors that reduce the real-world impact
# of unbounded queries, allowing us to reduce false positive rates while
# maintaining detection of genuine performance issues.
#
# Mitigating factors:
# 1. Caching - Results are cached, reducing database load
# 2. Parent scoping - Query is limited to children of a single parent
# 3. IDs only - Query returns only IDs, not full objects (lower memory)
# 4. Admin context - Query only runs in admin area (lower traffic)
# ============================================================================

# Note: get_function_scope_range() is defined near the top of this script.

# Check if query results are cached (transients or object cache)
# Usage: has_caching_mitigation "$file" "$line_number"
# Returns: 0 if caching detected, 1 otherwise
has_caching_mitigation() {
  local file="$1"
  local lineno="$2"

  local range function_start function_end
  range=$(get_function_scope_range "$file" "$lineno" 30)
  function_start=${range%%:*}
  function_end=${range##*:}

  # Get context within the same function/method (or fallback window if boundaries not found)
  local context=$(sed -n "${function_start},${function_end}p" "$file" 2>/dev/null || true)

  # Check for WordPress caching patterns in the same function
  # Look for both cache reads (get_transient, wp_cache_get) and writes (set_transient, wp_cache_set)
  if echo "$context" | grep -q -E "(get_transient|set_transient|wp_cache_get|wp_cache_set|wp_cache_add)\s*\("; then
    return 0
  fi

  return 1
}

# Check if query is scoped to a parent (e.g., variations of a single product)
# Usage: has_parent_scope_mitigation "$file" "$line_number"
# Returns: 0 if parent scoping detected, 1 otherwise
has_parent_scope_mitigation() {
  local file="$1"
  local lineno="$2"

  local range function_start function_end
  range=$(get_function_scope_range "$file" "$lineno" 20)
  function_start=${range%%:*}
  function_end=${range##*:}

  local context=$(sed -n "${function_start},${function_end}p" "$file" 2>/dev/null || true)

  # Check for parent parameter in query args
  if echo "$context" | grep -q -E "('|\")parent('|\")\s*=>"; then
    return 0
  fi

  return 1
}

# Check if query returns only IDs (not full objects)
# Usage: has_ids_only_mitigation "$file" "$line_number"
# Returns: 0 if IDs-only detected, 1 otherwise
has_ids_only_mitigation() {
  local file="$1"
  local lineno="$2"

  local range function_start function_end
  range=$(get_function_scope_range "$file" "$lineno" 20)
  function_start=${range%%:*}
  function_end=${range##*:}

  local context=$(sed -n "${function_start},${function_end}p" "$file" 2>/dev/null || true)

  # Check for 'return' => 'ids' or 'fields' => 'ids'
  if echo "$context" | grep -q -E "('|\")return('|\")\s*=>\s*('|\")ids('|\")"; then
    return 0
  fi
  if echo "$context" | grep -q -E "('|\")fields('|\")\s*=>\s*('|\")ids('|\")"; then
    return 0
  fi

  return 1
}

# Check if query is in admin context only
# Usage: has_admin_context_mitigation "$file" "$line_number"
# Returns: 0 if admin context detected, 1 otherwise
has_admin_context_mitigation() {
  local file="$1"
  local lineno="$2"

  local range function_start
  range=$(get_function_scope_range "$file" "$lineno" 30)
  function_start=${range%%:*}

  # Admin gates should appear before the query within the same scope.
  local context=$(sed -n "${function_start},${lineno}p" "$file" 2>/dev/null || true)

  # Check for admin checks before the query
  if echo "$context" | grep -q -E "(is_admin\(\)|current_user_can\(|if\s*\(\s*!\s*is_admin)"; then
    return 0
  fi

  return 1
}

# Calculate adjusted severity based on mitigating factors
# Usage: get_adjusted_severity "$file" "$line_number" "$base_severity"
# Returns: Adjusted severity level and mitigation reasons
get_adjusted_severity() {
  local file="$1"
  local lineno="$2"
  local base_severity="$3"
  local mitigations=""
  local mitigation_count=0

  # Check each mitigation factor
  if has_caching_mitigation "$file" "$lineno"; then
    mitigations="${mitigations}caching,"
    ((mitigation_count++))
  fi

  if has_parent_scope_mitigation "$file" "$lineno"; then
    mitigations="${mitigations}parent-scoped,"
    ((mitigation_count++))
  fi

  if has_ids_only_mitigation "$file" "$lineno"; then
    mitigations="${mitigations}ids-only,"
    ((mitigation_count++))
  fi

  if has_admin_context_mitigation "$file" "$lineno"; then
    mitigations="${mitigations}admin-only,"
    ((mitigation_count++))
  fi

  # Remove trailing comma
  mitigations="${mitigations%,}"

  # Adjust severity based on mitigation count
  local adjusted_severity="$base_severity"

  if [ "$mitigation_count" -ge 3 ]; then
    # 3+ mitigations: CRITICAL → LOW, HIGH → LOW, MEDIUM → LOW
    adjusted_severity="LOW"
  elif [ "$mitigation_count" -ge 2 ]; then
    # 2 mitigations: CRITICAL → MEDIUM, HIGH → MEDIUM, MEDIUM → LOW
    case "$base_severity" in
      CRITICAL) adjusted_severity="MEDIUM" ;;
      HIGH) adjusted_severity="MEDIUM" ;;
      MEDIUM) adjusted_severity="LOW" ;;
    esac
  elif [ "$mitigation_count" -ge 1 ]; then
    # 1 mitigation: CRITICAL → HIGH, HIGH → MEDIUM
    case "$base_severity" in
      CRITICAL) adjusted_severity="HIGH" ;;
      HIGH) adjusted_severity="MEDIUM" ;;
    esac
  fi

  # Return both severity and mitigations
  echo "${adjusted_severity}|${mitigations}"
}

# Run fixture validation (proof of detection)
# This runs before checks and sets global variables used by the summary.
debug_echo "Running fixture validation..."
run_fixture_validation
debug_echo "Fixture validation complete"

run_check "ERROR" "$(get_severity "unbounded-posts-per-page" "CRITICAL")" "Unbounded posts_per_page" "unbounded-posts-per-page" \
  "-e posts_per_page[[:space:]]*=>[[:space:]]*-1"

run_check "ERROR" "$(get_severity "unbounded-numberposts" "CRITICAL")" "Unbounded numberposts" "unbounded-numberposts" \
  "-e numberposts[[:space:]]*=>[[:space:]]*-1"

run_check "ERROR" "$(get_severity "nopaging-true" "CRITICAL")" "nopaging => true" "nopaging-true" \
  "-e nopaging[[:space:]]*=>[[:space:]]*true"

# Unbounded WooCommerce queries with mitigation detection
WC_UNBOUNDED_SEVERITY=$(get_severity "unbounded-wc-get-orders" "CRITICAL")
WC_UNBOUNDED_COLOR="${YELLOW}"
if [ "$WC_UNBOUNDED_SEVERITY" = "CRITICAL" ] || [ "$WC_UNBOUNDED_SEVERITY" = "HIGH" ]; then WC_UNBOUNDED_COLOR="${RED}"; fi
text_echo "${BLUE}▸ Unbounded wc_get_orders/wc_get_products limit ${WC_UNBOUNDED_COLOR}[$WC_UNBOUNDED_SEVERITY]${NC}"
WC_UNBOUNDED_FAILED=false
WC_UNBOUNDED_FINDING_COUNT=0
WC_UNBOUNDED_VISIBLE=""

# Find all unbounded WooCommerce queries
WC_UNBOUNDED_MATCHES=$(grep -rHn $EXCLUDE_ARGS --include="*.php" -E "'limit'[[:space:]]*=>[[:space:]]*-1" "$PATHS" 2>/dev/null || true)

if [ -n "$WC_UNBOUNDED_MATCHES" ]; then
  while IFS= read -r match; do
    [ -z "$match" ] && continue
    file=$(echo "$match" | cut -d: -f1)
    lineno=$(echo "$match" | cut -d: -f2)
    code=$(echo "$match" | cut -d: -f3-)

    if ! [[ "$lineno" =~ ^[0-9]+$ ]]; then
      continue
    fi

    # Get adjusted severity based on mitigating factors
    mitigation_result=$(get_adjusted_severity "$file" "$lineno" "$WC_UNBOUNDED_SEVERITY")
    adjusted_severity=$(echo "$mitigation_result" | cut -d'|' -f1)
    mitigations=$(echo "$mitigation_result" | cut -d'|' -f2)

    # Apply baseline suppression
    if ! should_suppress_finding "unbounded-wc-get-orders" "$file"; then
      WC_UNBOUNDED_FAILED=true
      ((WC_UNBOUNDED_FINDING_COUNT++))

      # Build message with mitigation info
      message="Unbounded WooCommerce query (limit => -1)"
      if [ -n "$mitigations" ]; then
        message="$message [Mitigated by: $mitigations]"
      fi

      match_output="${file}:${lineno}:${code}"
      if [ -z "$WC_UNBOUNDED_VISIBLE" ]; then
        WC_UNBOUNDED_VISIBLE="$match_output"
      else
        WC_UNBOUNDED_VISIBLE="${WC_UNBOUNDED_VISIBLE}
$match_output"
      fi

      # Add to JSON with adjusted severity
      add_json_finding "unbounded-wc-get-orders" "error" "$adjusted_severity" "$file" "$lineno" "$message" "$code"
    fi
  done <<< "$WC_UNBOUNDED_MATCHES"
fi

if [ "$WC_UNBOUNDED_FAILED" = true ]; then
  # Use the base severity for error/warning counting (not adjusted)
  if [ "$WC_UNBOUNDED_SEVERITY" = "CRITICAL" ] || [ "$WC_UNBOUNDED_SEVERITY" = "HIGH" ]; then
    text_echo "${RED}  ✗ FAILED${NC}"
    ((ERRORS++))
  else
    text_echo "${YELLOW}  ⚠ WARNING${NC}"
    ((WARNINGS++))
  fi
  if [ "$OUTPUT_FORMAT" = "text" ] && [ -n "$WC_UNBOUNDED_VISIBLE" ]; then
    while IFS= read -r match; do
      [ -z "$match" ] && continue
      format_finding "$match"
    done <<< "$(echo "$WC_UNBOUNDED_VISIBLE" | head -10)"
  fi
  add_json_check "Unbounded wc_get_orders/wc_get_products limit" "$WC_UNBOUNDED_SEVERITY" "failed" "$WC_UNBOUNDED_FINDING_COUNT"
else
  text_echo "${GREEN}  ✓ Passed${NC}"
  add_json_check "Unbounded wc_get_orders/wc_get_products limit" "$WC_UNBOUNDED_SEVERITY" "passed" 0
fi
text_echo ""

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

    # Check if THIS specific get_users() call has 'number' parameter within ±10 lines
    # Look both before and after because the array might be defined before the call
    start_line=$((lineno - 10))
    [ "$start_line" -lt 1 ] && start_line=1
    end_line=$((lineno + 10))
    context=$(sed -n "${start_line},${end_line}p" "$file" 2>/dev/null || true)

    # Check if 'number' parameter exists in this specific call's context
    if ! echo "$context" | grep -q -e "'number'" -e '"number"'; then
      # Apply baseline suppression per finding
      if ! should_suppress_finding "unbounded-get-users" "$file"; then
        USERS_UNBOUNDED=true
        ((USERS_FINDING_COUNT++))

        # Get adjusted severity based on mitigating factors
        mitigation_result=$(get_adjusted_severity "$file" "$lineno" "$USERS_SEVERITY")
        adjusted_severity=$(echo "$mitigation_result" | cut -d'|' -f1)
        mitigations=$(echo "$mitigation_result" | cut -d'|' -f2)

        # Build message with mitigation info
        message="get_users() without 'number' limit can fetch ALL users"
        if [ -n "$mitigations" ]; then
          message="$message [Mitigated by: $mitigations]"
        fi

        match_output="${file}:${lineno}:${code}"
        if [ -z "$USERS_VISIBLE" ]; then
          USERS_VISIBLE="$match_output"
        else
          USERS_VISIBLE="${USERS_VISIBLE}
$match_output"
        fi

        # Add to JSON with adjusted severity
        add_json_finding "get-users-no-limit" "error" "$adjusted_severity" "$file" "$lineno" "$message" "$code"
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
  # SAFEGUARD: Use safe_file_iterator() instead of "for file in $TERMS_FILES"
  # File paths with spaces will break the loop without this helper (see common-helpers.sh)
  safe_file_iterator "$TERMS_FILES" | while IFS= read -r file; do
    # Check if file has get_terms without 'number' or "number" nearby (within 5 lines)
    # Support both single and double quotes
	    if ! grep -A5 "get_terms[[:space:]]*(" "$file" 2>/dev/null | grep -q -e "'number'" -e '"number"'; then
	      # Apply baseline suppression per file
	      if ! should_suppress_finding "get-terms-no-limit" "$file"; then
	        # Get line number for JSON
	        lineno=$(grep -n "get_terms[[:space:]]*(" "$file" 2>/dev/null | head -1 | cut -d: -f1)
	        lineno=${lineno:-0}

	        # Get adjusted severity based on mitigating factors
	        mitigation_result=$(get_adjusted_severity "$file" "$lineno" "$TERMS_SEVERITY")
	        adjusted_severity=$(echo "$mitigation_result" | cut -d'|' -f1)
	        mitigations=$(echo "$mitigation_result" | cut -d'|' -f2)

	        # Build message with mitigation info
	        message="get_terms() may be missing 'number' parameter"
	        if [ -n "$mitigations" ]; then
	          message="$message [Mitigated by: $mitigations]"
	        fi

	        text_echo "  $file: $message"

	        # Add to JSON with adjusted severity
	        add_json_finding "get-terms-no-limit" "error" "$adjusted_severity" "$file" "$lineno" "$message" "get_terms("
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
  # SAFEGUARD: Use safe_file_iterator() instead of "for file in $PRE_GET_POSTS_FILES"
  # File paths with spaces will break the loop without this helper (see common-helpers.sh)
  safe_file_iterator "$PRE_GET_POSTS_FILES" | while IFS= read -r file; do
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
text_echo ""

# Unbounded wc_get_orders check (explicit limit -1)
WC_ORDERS_SEVERITY=$(get_severity "unbounded-wc-get-orders" "CRITICAL")
WC_ORDERS_COLOR="${YELLOW}"
if [ "$WC_ORDERS_SEVERITY" = "CRITICAL" ] || [ "$WC_ORDERS_SEVERITY" = "HIGH" ]; then WC_ORDERS_COLOR="${RED}"; fi
text_echo "${BLUE}▸ Unbounded wc_get_orders() calls ${WC_ORDERS_COLOR}[$WC_ORDERS_SEVERITY]${NC}"
WC_ORDERS_UNBOUNDED=false
WC_ORDERS_FINDING_COUNT=0
WC_ORDERS_VISIBLE=""

# SAFEGUARD: "$PATHS" MUST be quoted
WC_ORDERS_MATCHES=$(grep -rHn $EXCLUDE_ARGS --include="*.php" "wc_get_orders" "$PATHS" 2>/dev/null || true)
if [ -n "$WC_ORDERS_MATCHES" ]; then
  while IFS= read -r match; do
    [ -z "$match" ] && continue
    file=$(echo "$match" | cut -d: -f1)
    lineno=$(echo "$match" | cut -d: -f2)
    code=$(echo "$match" | cut -d: -f3-)

    if ! [[ "$lineno" =~ ^[0-9]+$ ]]; then continue; fi

    # Check context for skip limit or limit -1
    start_line=$((lineno - 2))
    [ "$start_line" -lt 1 ] && start_line=1
    end_line=$((lineno + 15))
    context=$(sed -n "${start_line},${end_line}p" "$file" 2>/dev/null || true)

    if echo "$context" | grep -E -q "[\"']limit[\"']\s*=>\s*-1"; then
      if ! should_suppress_finding "unbounded-wc-get-orders" "$file"; then
        WC_ORDERS_UNBOUNDED=true
        ((WC_ORDERS_FINDING_COUNT++))
        add_json_finding "unbounded-wc-get-orders" "error" "$WC_ORDERS_SEVERITY" "$file" "$lineno" "wc_get_orders() with limit => -1 causes OOM" "$code"
        
        match_output="$file:$lineno:$code"
        if [ -z "$WC_ORDERS_VISIBLE" ]; then WC_ORDERS_VISIBLE="$match_output"; else WC_ORDERS_VISIBLE="${WC_ORDERS_VISIBLE}\n$match_output"; fi
      fi
    fi
  done <<< "$WC_ORDERS_MATCHES"
fi

if [ "$WC_ORDERS_UNBOUNDED" = true ]; then
  if [ "$WC_ORDERS_SEVERITY" = "CRITICAL" ] || [ "$WC_ORDERS_SEVERITY" = "HIGH" ]; then
    text_echo "${RED}  ✗ FAILED${NC}"
    ((ERRORS++))
  else
    text_echo "${YELLOW}  ⚠ WARNING${NC}"
    ((WARNINGS++))
  fi
  if [ "$OUTPUT_FORMAT" = "text" ] && [ -n "$WC_ORDERS_VISIBLE" ]; then
     echo -e "$WC_ORDERS_VISIBLE" | head -5 | while read -r line; do text_echo "  $line"; done
  fi
  add_json_check "Unbounded wc_get_orders()" "$WC_ORDERS_SEVERITY" "failed" "$WC_ORDERS_FINDING_COUNT"
else
  text_echo "${GREEN}  ✓ Passed${NC}"
  add_json_check "Unbounded wc_get_orders()" "$WC_ORDERS_SEVERITY" "passed" 0
fi
text_echo ""

# Unbounded wc_get_products check
WC_PROD_SEVERITY=$(get_severity "unbounded-wc-get-products" "CRITICAL")
WC_PROD_COLOR="${YELLOW}"
if [ "$WC_PROD_SEVERITY" = "CRITICAL" ] || [ "$WC_PROD_SEVERITY" = "HIGH" ]; then WC_PROD_COLOR="${RED}"; fi
text_echo "${BLUE}▸ Unbounded wc_get_products() calls ${WC_PROD_COLOR}[$WC_PROD_SEVERITY]${NC}"
WC_PROD_UNBOUNDED=false
WC_PROD_FINDING_COUNT=0
WC_PROD_VISIBLE=""

WC_PROD_MATCHES=$(grep -rHn $EXCLUDE_ARGS --include="*.php" "wc_get_products" "$PATHS" 2>/dev/null || true)
if [ -n "$WC_PROD_MATCHES" ]; then
  while IFS= read -r match; do
    [ -z "$match" ] && continue
    file=$(echo "$match" | cut -d: -f1)
    lineno=$(echo "$match" | cut -d: -f2)
    code=$(echo "$match" | cut -d: -f3-)

    if ! [[ "$lineno" =~ ^[0-9]+$ ]]; then continue; fi

    start_line=$((lineno - 2))
    [ "$start_line" -lt 1 ] && start_line=1
    end_line=$((lineno + 15))
    context=$(sed -n "${start_line},${end_line}p" "$file" 2>/dev/null || true)

    if echo "$context" | grep -E -q "[\"']limit[\"']\s*=>\s*-1"; then
      if ! should_suppress_finding "unbounded-wc-get-products" "$file"; then
        WC_PROD_UNBOUNDED=true
        ((WC_PROD_FINDING_COUNT++))
        add_json_finding "unbounded-wc-get-products" "error" "$WC_PROD_SEVERITY" "$file" "$lineno" "wc_get_products() with limit => -1" "$code"
        match_output="$file:$lineno:$code"
        if [ -z "$WC_PROD_VISIBLE" ]; then WC_PROD_VISIBLE="$match_output"; else WC_PROD_VISIBLE="${WC_PROD_VISIBLE}\n$match_output"; fi
      fi
    fi
  done <<< "$WC_PROD_MATCHES"
fi

if [ "$WC_PROD_UNBOUNDED" = true ]; then
  if [ "$WC_PROD_SEVERITY" = "CRITICAL" ] || [ "$WC_PROD_SEVERITY" = "HIGH" ]; then
    text_echo "${RED}  ✗ FAILED${NC}"
    ((ERRORS++))
  else
    text_echo "${YELLOW}  ⚠ WARNING${NC}"
    ((WARNINGS++))
  fi
  if [ "$OUTPUT_FORMAT" = "text" ] && [ -n "$WC_PROD_VISIBLE" ]; then
     echo -e "$WC_PROD_VISIBLE" | head -5 | while read -r line; do text_echo "  $line"; done
  fi
  add_json_check "Unbounded wc_get_products()" "$WC_PROD_SEVERITY" "failed" "$WC_PROD_FINDING_COUNT"
else
  text_echo "${GREEN}  ✓ Passed${NC}"
  add_json_check "Unbounded wc_get_products()" "$WC_PROD_SEVERITY" "passed" 0
fi
text_echo ""

# Unbounded WP_Query check
WPQ_SEVERITY=$(get_severity "wp-query-unbounded" "CRITICAL")
WPQ_COLOR="${YELLOW}"
if [ "$WPQ_SEVERITY" = "CRITICAL" ] || [ "$WPQ_SEVERITY" = "HIGH" ]; then WPQ_COLOR="${RED}"; fi
text_echo "${BLUE}▸ Unbounded WP_Query/get_posts calls ${WPQ_COLOR}[$WPQ_SEVERITY]${NC}"
WPQ_UNBOUNDED=false
WPQ_FINDING_COUNT=0
WPQ_VISIBLE=""

WPQ_MATCHES=$(grep -rHn $EXCLUDE_ARGS --include="*.php" -E "new WP_Query|get_posts" "$PATHS" 2>/dev/null || true)
if [ -n "$WPQ_MATCHES" ]; then
  while IFS= read -r match; do
    [ -z "$match" ] && continue
    file=$(echo "$match" | cut -d: -f1)
    lineno=$(echo "$match" | cut -d: -f2)
    code=$(echo "$match" | cut -d: -f3-)

    if ! [[ "$lineno" =~ ^[0-9]+$ ]]; then continue; fi

    start_line=$((lineno - 2))
    [ "$start_line" -lt 1 ] && start_line=1
    end_line=$((lineno + 15))
    context=$(sed -n "${start_line},${end_line}p" "$file" 2>/dev/null || true)

    if echo "$context" | grep -E -q "[\"']posts_per_page[\"']\s*=>\s*-1|[\"']nopaging[\"']\s*=>\s*true|[\"']numberposts[\"']\s*=>\s*-1"; then
      if ! should_suppress_finding "wp-query-unbounded" "$file"; then
        WPQ_UNBOUNDED=true
        ((WPQ_FINDING_COUNT++))

        mitigation_result=$(get_adjusted_severity "$file" "$lineno" "$WPQ_SEVERITY")
        adjusted_severity=$(echo "$mitigation_result" | cut -d'|' -f1)
        mitigations=$(echo "$mitigation_result" | cut -d'|' -f2)

        message="WP_Query/get_posts with -1 limit or nopaging"
        if [ -n "$mitigations" ]; then
          message="$message [Mitigated by: $mitigations]"
        fi

        add_json_finding "wp-query-unbounded" "error" "$adjusted_severity" "$file" "$lineno" "$message" "$code"
        match_output="$file:$lineno:$code"
        if [ -n "$mitigations" ]; then
          match_output="$match_output [Mitigated by: $mitigations]"
        fi
        if [ -z "$WPQ_VISIBLE" ]; then WPQ_VISIBLE="$match_output"; else WPQ_VISIBLE="${WPQ_VISIBLE}\n$match_output"; fi
      fi
    fi
  done <<< "$WPQ_MATCHES"
fi

if [ "$WPQ_UNBOUNDED" = true ]; then
  if [ "$WPQ_SEVERITY" = "CRITICAL" ] || [ "$WPQ_SEVERITY" = "HIGH" ]; then
    text_echo "${RED}  ✗ FAILED${NC}"
    ((ERRORS++))
  else
    text_echo "${YELLOW}  ⚠ WARNING${NC}"
    ((WARNINGS++))
  fi
  if [ "$OUTPUT_FORMAT" = "text" ] && [ -n "$WPQ_VISIBLE" ]; then
     echo -e "$WPQ_VISIBLE" | head -5 | while read -r line; do text_echo "  $line"; done
  fi
  add_json_check "Unbounded WP_Query/get_posts" "$WPQ_SEVERITY" "failed" "$WPQ_FINDING_COUNT"
else
  text_echo "${GREEN}  ✓ Passed${NC}"
  add_json_check "Unbounded WP_Query/get_posts" "$WPQ_SEVERITY" "passed" 0
fi
text_echo ""

# WP_User_Query meta bloat check
WUQ_SEVERITY=$(get_severity "wp-user-query-meta-bloat" "CRITICAL")
WUQ_COLOR="${YELLOW}"
if [ "$WUQ_SEVERITY" = "CRITICAL" ] || [ "$WUQ_SEVERITY" = "HIGH" ]; then WUQ_COLOR="${RED}"; fi
text_echo "${BLUE}▸ WP_User_Query without meta caching disabled ${WUQ_COLOR}[$WUQ_SEVERITY]${NC}"
WUQ_UNBOUNDED=false
WUQ_FINDING_COUNT=0
WUQ_VISIBLE=""

WUQ_MATCHES=$(grep -rHn $EXCLUDE_ARGS --include="*.php" "new WP_User_Query" "$PATHS" 2>/dev/null || true)
if [ -n "$WUQ_MATCHES" ]; then
  while IFS= read -r match; do
    [ -z "$match" ] && continue
    file=$(echo "$match" | cut -d: -f1)
    lineno=$(echo "$match" | cut -d: -f2)
    code=$(echo "$match" | cut -d: -f3-)

    if ! [[ "$lineno" =~ ^[0-9]+$ ]]; then continue; fi

    start_line=$((lineno - 2))
    [ "$start_line" -lt 1 ] && start_line=1
    end_line=$((lineno + 15))
    context=$(sed -n "${start_line},${end_line}p" "$file" 2>/dev/null || true)

    # Allow if 'update_user_meta_cache' => false is present
    if ! echo "$context" | grep -q "update_user_meta_cache.*false"; then
       if ! should_suppress_finding "wp-user-query-meta-bloat" "$file"; then
         WUQ_UNBOUNDED=true
         ((WUQ_FINDING_COUNT++))

         mitigation_result=$(get_adjusted_severity "$file" "$lineno" "$WUQ_SEVERITY")
         adjusted_severity=$(echo "$mitigation_result" | cut -d'|' -f1)
         mitigations=$(echo "$mitigation_result" | cut -d'|' -f2)

         message="WP_User_Query missing update_user_meta_cache => false"
         if [ -n "$mitigations" ]; then
           message="$message [Mitigated by: $mitigations]"
         fi

         add_json_finding "wp-user-query-meta-bloat" "error" "$adjusted_severity" "$file" "$lineno" "$message" "$code"
         match_output="$file:$lineno:$code"
         if [ -n "$mitigations" ]; then
           match_output="$match_output [Mitigated by: $mitigations]"
         fi
         if [ -z "$WUQ_VISIBLE" ]; then WUQ_VISIBLE="$match_output"; else WUQ_VISIBLE="${WUQ_VISIBLE}\n$match_output"; fi
       fi
    fi
  done <<< "$WUQ_MATCHES"
fi

if [ "$WUQ_UNBOUNDED" = true ]; then
  if [ "$WUQ_SEVERITY" = "CRITICAL" ] || [ "$WUQ_SEVERITY" = "HIGH" ]; then
    text_echo "${RED}  ✗ FAILED${NC}"
    ((ERRORS++))
  else
    text_echo "${YELLOW}  ⚠ WARNING${NC}"
    ((WARNINGS++))
  fi
  if [ "$OUTPUT_FORMAT" = "text" ] && [ -n "$WUQ_VISIBLE" ]; then
     echo -e "$WUQ_VISIBLE" | head -5 | while read -r line; do text_echo "  $line"; done
  fi
  add_json_check "WP_User_Query meta bloat" "$WUQ_SEVERITY" "failed" "$WUQ_FINDING_COUNT"
else
  text_echo "${GREEN}  ✓ Passed${NC}"
  add_json_check "WP_User_Query meta bloat" "$WUQ_SEVERITY" "passed" 0
fi

text_echo ""

# Heuristic: query limit multipliers derived from count()
# Example: $candidate_limit = count( $user_ids ) * 10 * 5;
# This can balloon result sets and trigger OOM when combined with object hydration.
# Enhancement v1.0.93: Detect hard caps (min(..., N)) and downgrade severity
MULT_SEVERITY=$(get_severity "limit-multiplier-from-count" "MEDIUM")
MULT_COLOR="${YELLOW}"
if [ "$MULT_SEVERITY" = "CRITICAL" ] || [ "$MULT_SEVERITY" = "HIGH" ]; then MULT_COLOR="${RED}"; fi
text_echo "${BLUE}▸ Potential query limit multipliers (count() * N) ${MULT_COLOR}[$MULT_SEVERITY]${NC}"
MULT_FOUND=false
MULT_FINDING_COUNT=0
MULT_VISIBLE=""

# SAFEGUARD: "$PATHS" MUST be quoted
MULT_MATCHES=$(grep -rHn $EXCLUDE_ARGS --include="*.php" -E "count\([^)]*\)[[:space:]]*\*[[:space:]]*[0-9]{1,}" "$PATHS" 2>/dev/null || true)
if [ -n "$MULT_MATCHES" ]; then
  while IFS= read -r match; do
    [ -z "$match" ] && continue
    file=$(echo "$match" | cut -d: -f1)
    lineno=$(echo "$match" | cut -d: -f2)
    code=$(echo "$match" | cut -d: -f3-)

    if ! [[ "$lineno" =~ ^[0-9]+$ ]]; then
      continue
    fi

    if should_suppress_finding "limit-multiplier-from-count" "$file"; then
      continue
    fi

    # FALSE POSITIVE REDUCTION: Check if hard cap exists (min(..., N) pattern)
    adjusted_severity="$MULT_SEVERITY"
    message="Potential multiplier: count(...) * N (review for runaway limits)"

    if echo "$code" | grep -qE "min[[:space:]]*\("; then
      # Extract the hard cap value from min(..., N)
      hard_cap=$(echo "$code" | sed -n 's/.*min[[:space:]]*([^,]*,[[:space:]]*\([0-9]\{1,\}\).*/\1/p')
      if [ -n "$hard_cap" ]; then
        # Downgrade severity: MEDIUM → LOW when hard cap exists
        adjusted_severity="LOW"
        message="Potential multiplier: count(...) * N [Mitigated by: hard cap of $hard_cap]"
      fi
    fi

    MULT_FOUND=true
    ((MULT_FINDING_COUNT++))
    add_json_finding "limit-multiplier-from-count" "warning" "$adjusted_severity" "$file" "$lineno" "$message" "$code"

    match_output="$file:$lineno:$code"
    if [ -z "$MULT_VISIBLE" ]; then
      MULT_VISIBLE="$match_output"
    else
      MULT_VISIBLE="${MULT_VISIBLE}
$match_output"
    fi
  done <<< "$MULT_MATCHES"
fi

if [ "$MULT_FOUND" = true ]; then
  text_echo "${YELLOW}  ⚠ WARNING${NC}"
  ((WARNINGS++))
  if [ "$OUTPUT_FORMAT" = "text" ] && [ -n "$MULT_VISIBLE" ]; then
    echo -e "$MULT_VISIBLE" | head -5 | while IFS= read -r line; do
      [ -z "$line" ] && continue
      text_echo "  $line"
    done
  fi
  add_json_check "Potential query limit multipliers (count() * N)" "$MULT_SEVERITY" "failed" "$MULT_FINDING_COUNT"
else
  text_echo "${GREEN}  ✓ Passed${NC}"
  add_json_check "Potential query limit multipliers (count() * N)" "$MULT_SEVERITY" "passed" 0
fi

text_echo ""

# Heuristic: array_merge inside loops (can cause quadratic memory usage)
ARRAY_MERGE_SEVERITY=$(get_severity "array-merge-in-loop" "LOW")
ARRAY_MERGE_COLOR="${YELLOW}"
if [ "$ARRAY_MERGE_SEVERITY" = "CRITICAL" ] || [ "$ARRAY_MERGE_SEVERITY" = "HIGH" ]; then ARRAY_MERGE_COLOR="${RED}"; fi
text_echo "${BLUE}▸ array_merge() inside loops (heuristic) ${ARRAY_MERGE_COLOR}[$ARRAY_MERGE_SEVERITY]${NC}"
ARRAY_MERGE_FOUND=false
ARRAY_MERGE_FINDING_COUNT=0
ARRAY_MERGE_VISIBLE=""

# Target the expensive form: $x = array_merge($x, ...)
ARRAY_MERGE_MATCHES=$(grep -rHn $EXCLUDE_ARGS --include="*.php" -E "\$[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*=[[:space:]]*array_merge\([[:space:]]*\$[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*," "$PATHS" 2>/dev/null || true)
if [ -n "$ARRAY_MERGE_MATCHES" ]; then
  while IFS= read -r match; do
    [ -z "$match" ] && continue
    file=$(echo "$match" | cut -d: -f1)
    lineno=$(echo "$match" | cut -d: -f2)
    code=$(echo "$match" | cut -d: -f3-)

    if ! [[ "$lineno" =~ ^[0-9]+$ ]]; then
      continue
    fi

    # Only flag when we see a loop keyword nearby.
    start_line=$((lineno - 15))
    [ "$start_line" -lt 1 ] && start_line=1
    end_line=$((lineno + 2))
    context=$(sed -n "${start_line},${end_line}p" "$file" 2>/dev/null || true)

    if ! echo "$context" | grep -q -E "\b(foreach|for|while)\b"; then
      continue
    fi

    if should_suppress_finding "array-merge-in-loop" "$file"; then
      continue
    fi

    ARRAY_MERGE_FOUND=true
    ((ARRAY_MERGE_FINDING_COUNT++))
    add_json_finding "array-merge-in-loop" "warning" "$ARRAY_MERGE_SEVERITY" "$file" "$lineno" "array_merge() inside loop can balloon memory; prefer [] append or preallocation" "$code"

    match_output="$file:$lineno:$code"
    if [ -z "$ARRAY_MERGE_VISIBLE" ]; then
      ARRAY_MERGE_VISIBLE="$match_output"
    else
      ARRAY_MERGE_VISIBLE="${ARRAY_MERGE_VISIBLE}
$match_output"
    fi
  done <<< "$ARRAY_MERGE_MATCHES"
fi

if [ "$ARRAY_MERGE_FOUND" = true ]; then
  text_echo "${YELLOW}  ⚠ WARNING${NC}"
  ((WARNINGS++))
  if [ "$OUTPUT_FORMAT" = "text" ] && [ -n "$ARRAY_MERGE_VISIBLE" ]; then
    echo -e "$ARRAY_MERGE_VISIBLE" | head -5 | while IFS= read -r line; do
      [ -z "$line" ] && continue
      text_echo "  $line"
    done
  fi
  add_json_check "array_merge() inside loops (heuristic)" "$ARRAY_MERGE_SEVERITY" "failed" "$ARRAY_MERGE_FINDING_COUNT"
else
  text_echo "${GREEN}  ✓ Passed${NC}"
  add_json_check "array_merge() inside loops (heuristic)" "$ARRAY_MERGE_SEVERITY" "passed" 0
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
  # SAFEGUARD: Use safe_file_iterator() instead of "for file in $CRON_FILES"
  # File paths with spaces will break the loop without this helper (see common-helpers.sh)
  # Use temp file to communicate findings from subshell (pipe creates subshell that can't modify parent vars)
  CRON_TEMP_FILE=$(mktemp)
  safe_file_iterator "$CRON_FILES" | while IFS= read -r file; do
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
        range=$(get_function_scope_range "$file" "$lineno" 30)
        function_start=${range%%:*}
        [ "$start_line" -lt "$function_start" ] && start_line="$function_start"
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
            # Write to temp file (subshell can't modify parent vars)
            echo "FAIL" >> "$CRON_TEMP_FILE"

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

  # Read findings from temp file (subshell workaround)
  if [ -f "$CRON_TEMP_FILE" ]; then
    CRON_INTERVAL_FINDING_COUNT=$(wc -l < "$CRON_TEMP_FILE" | tr -d ' ')
    if [ "$CRON_INTERVAL_FINDING_COUNT" -gt 0 ]; then
      CRON_INTERVAL_FAIL=true
    fi
    rm -f "$CRON_TEMP_FILE"
  fi
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

section_end
profile_end "CRITICAL_CHECKS"
profile_start "WARNING_CHECKS"
section_start "Warning Checks"

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

# Helper: Check if file uses WordPress meta caching APIs
# Returns 0 (true) if file contains update_meta_cache() or similar functions
has_meta_cache_optimization() {
	local file="$1"
	grep -qE "update_meta_cache|update_postmeta_cache|update_termmeta_cache" "$file" 2>/dev/null
}

# N+1 pattern check (simplified) - includes post, term, and user meta
# Smart detection: Downgrades severity to INFO if update_meta_cache() is detected
N1_SEVERITY=$(get_severity "n-plus-one-pattern" "MEDIUM")
N1_COLOR="${YELLOW}"
if [ "$N1_SEVERITY" = "CRITICAL" ]; then N1_COLOR="${RED}"; fi
text_echo "${BLUE}▸ Potential N+1 patterns (meta in loops) ${N1_COLOR}[$N1_SEVERITY]${NC}"
	# SAFEGUARD: "$PATHS" MUST be quoted - paths with spaces will break otherwise (see SAFEGUARDS.md)
	N1_FILES=$(grep -rl $EXCLUDE_ARGS --include="*.php" -e "get_post_meta\|get_term_meta\|get_user_meta" "$PATHS" 2>/dev/null | \
	           xargs -I{} grep -l "foreach\|while[[:space:]]*(" {} 2>/dev/null | head -5 || true)
	N1_FINDING_COUNT=0
	N1_OPTIMIZED_COUNT=0
	VISIBLE_N1_FILES=""
	VISIBLE_N1_OPTIMIZED=""
	if [ -n "$N1_FILES" ]; then
	  # Collect findings, applying baseline per file
	  while IFS= read -r f; do
	    [ -z "$f" ] && continue
	    if ! should_suppress_finding "n-plus-1-pattern" "$f"; then
	      # Smart detection: Check if file uses meta caching
	      if has_meta_cache_optimization "$f"; then
	        # File uses update_meta_cache() - likely optimized, downgrade to INFO
	        VISIBLE_N1_OPTIMIZED="${VISIBLE_N1_OPTIMIZED}${f}"$'\n'
	        add_json_finding "n-plus-1-pattern" "info" "LOW" "$f" "0" "File contains get_*_meta in loops but uses update_meta_cache() - verify optimization" ""
	        ((N1_OPTIMIZED_COUNT++)) || true
	      else
	        # No caching detected - standard warning
	        VISIBLE_N1_FILES="${VISIBLE_N1_FILES}${f}"$'\n'
	        add_json_finding "n-plus-1-pattern" "warning" "$N1_SEVERITY" "$f" "0" "File may contain N+1 query pattern (meta in loops)" ""
	        ((N1_FINDING_COUNT++)) || true
	      fi
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
	  elif [ "$N1_OPTIMIZED_COUNT" -gt 0 ]; then
	    text_echo "${GREEN}  ✓ Passed${NC} ${BLUE}(${N1_OPTIMIZED_COUNT} file(s) use meta caching - likely optimized)${NC}"
	    add_json_check "Potential N+1 patterns (meta in loops)" "$N1_SEVERITY" "passed" 0
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

section_end
profile_end "WARNING_CHECKS"
profile_start "MAGIC_STRING_DETECTOR"
section_start "Magic String Detector"

# ============================================================================
# Direct Pattern Detection (JavaScript/Node.js/Headless WordPress)
# ============================================================================
# Process patterns with detection_type: "direct" from JSON files
# These are typically single-file checks (not aggregated across files)

# Find all direct patterns from headless/, nodejs/, and js/ subdirectories
DIRECT_PATTERNS=$(find "$REPO_ROOT/patterns/headless" "$REPO_ROOT/patterns/nodejs" "$REPO_ROOT/patterns/js" -name "*.json" -type f 2>/dev/null | while read -r pattern_file; do
  detection_type=$(grep '"detection_type"' "$pattern_file" | head -1 | sed 's/.*"detection_type"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
  if [ "$detection_type" = "direct" ]; then
    echo "$pattern_file"
  fi
done)

if [ -n "$DIRECT_PATTERNS" ]; then
  text_echo "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  text_echo "${BLUE}  JAVASCRIPT/NODE.JS/HEADLESS WORDPRESS CHECKS${NC}"
  text_echo "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  text_echo ""

  # Process each direct pattern
  while IFS= read -r pattern_file; do
    [ -z "$pattern_file" ] && continue

    # Load pattern metadata
    if load_pattern "$pattern_file"; then
      # Get severity with fallback
      check_severity=$(get_severity "$pattern_id" "$pattern_severity")
      check_color="${YELLOW}"
      if [ "$check_severity" = "CRITICAL" ] || [ "$check_severity" = "HIGH" ]; then check_color="${RED}"; fi

      text_echo "${BLUE}▸ $pattern_title ${check_color}[$check_severity]${NC}"

      # Build --include flags from pattern_file_patterns
      include_args=""
      for ext in $pattern_file_patterns; do
        include_args="$include_args --include=$ext"
      done

      # Run grep with the pattern
      matches=""
      match_count=0
      matches=$(grep -rHn $EXCLUDE_ARGS $include_args -E "$pattern_search" "$PATHS" 2>/dev/null || true)

      if [ -n "$matches" ]; then
        match_count=$(echo "$matches" | grep -c . 2>/dev/null)
        match_count=${match_count:-0}
      fi

      if [ "$match_count" -gt 0 ]; then
        text_echo "${check_color}  ⚠ Found $match_count violation(s)${NC}"

        # Increment error/warning counters
        if [ "$check_severity" = "CRITICAL" ] || [ "$check_severity" = "HIGH" ]; then
          ((ERRORS++))
        else
          ((WARNINGS++))
        fi

        # Add to findings for JSON output
        while IFS= read -r match; do
          [ -z "$match" ] && continue

          file=$(echo "$match" | cut -d: -f1)
          line=$(echo "$match" | cut -d: -f2)
          code=$(echo "$match" | cut -d: -f3-)

          # Add to JSON findings (using same format as run_check)
          FINDINGS_JSON="$FINDINGS_JSON
  {\"id\":\"$pattern_id\",\"severity\":\"error\",\"impact\":\"$check_severity\",\"file\":\"$file\",\"line\":$line,\"message\":\"$pattern_title\",\"code\":$(echo "$code" | jq -Rs .)},"

          # Show in text output if not too many
          if [ "$match_count" -le 10 ]; then
            text_echo "  ${check_color}→ $file:$line${NC}"
            if [ "$CONTEXT_LINES" -gt 0 ]; then
              text_echo "    ${code:0:100}"
            fi
          fi
        done <<< "$matches"

        if [ "$match_count" -gt 10 ]; then
          text_echo "  ${check_color}  (showing first 10 of $match_count violations)${NC}"
        fi

        # Add to JSON checks summary
        add_json_check "$pattern_title" "$check_severity" "failed" "$match_count"
      else
        text_echo "${GREEN}  ✓ Passed${NC}"
        add_json_check "$pattern_title" "$check_severity" "passed" 0
      fi
      text_echo ""
    fi
  done <<< "$DIRECT_PATTERNS"
fi

# ============================================================================
# Magic String Detector ("DRY") - Aggregated Patterns
# ============================================================================

text_echo "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
text_echo "${BLUE}  MAGIC STRING DETECTOR (\"DRY\")${NC}"
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
  text_echo "${BLUE}No aggregated patterns found. Skipping magic string checks.${NC}"
  text_echo ""
else
  # Debug: Log aggregated patterns found
  debug_echo "Aggregated patterns found: $(echo "$AGGREGATED_PATTERNS" | wc -l | tr -d ' ') patterns"

  # Process each aggregated pattern
  while IFS= read -r pattern_file; do
    [ -z "$pattern_file" ] && continue

    # Load pattern to get title
    if load_pattern "$pattern_file"; then
      text_echo "${BLUE}▸ $pattern_title${NC}"

      # Only show pattern regex in verbose mode or debug mode
      if [ "$VERBOSE" = "true" ]; then
        text_echo "  ${BLUE}→ Pattern: $pattern_search${NC}"
      fi

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

section_end
profile_end "MAGIC_STRING_DETECTOR"
profile_start "FUNCTION_CLONE_DETECTOR"
section_start "Function Clone Detector"

# ============================================================================
# Function Clone Detector - Clone Detection Patterns
# ============================================================================

# Find all clone detection patterns
CLONE_PATTERNS=$(find "$REPO_ROOT/patterns" -name "*.json" -type f | while read -r pattern_file; do
  detection_type=$(grep '"detection_type"' "$pattern_file" | head -1 | sed 's/.*"detection_type"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
  if [ "$detection_type" = "clone_detection" ]; then
    echo "$pattern_file"
  fi
done)

if [ -n "$CLONE_PATTERNS" ]; then
  # Check if clone detection should be skipped
  if [ "$SKIP_CLONE_DETECTION" = "true" ]; then
    text_echo "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    text_echo "${BLUE}  FUNCTION CLONE DETECTOR${NC}"
    text_echo "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    text_echo ""
    text_echo "${YELLOW}  ○ Skipped (use --enable-clone-detection to run)${NC}"
    text_echo ""
  else
    text_echo "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    text_echo "${BLUE}  FUNCTION CLONE DETECTOR${NC}"
    text_echo "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    text_echo ""

    # Debug: Log clone patterns found
    debug_echo "Clone detection patterns found: $(echo "$CLONE_PATTERNS" | wc -l | tr -d ' ') patterns"

    # Process each clone detection pattern
    while IFS= read -r pattern_file; do
      [ -z "$pattern_file" ] && continue

      # Load pattern to get title
      if load_pattern "$pattern_file"; then
        text_echo "${BLUE}▸ $pattern_title${NC}"

        # Store current violation count
        violations_before=$DRY_VIOLATIONS_COUNT

        # Process clone detection (timeout is handled inside the function)
        process_clone_detection "$pattern_file"

        # Check if new violations were added
        violations_after=$DRY_VIOLATIONS_COUNT
        new_violations=$((violations_after - violations_before))

        if [ "$new_violations" -gt 0 ]; then
          text_echo "${YELLOW}  ⚠ Found $new_violations duplicate function(s)${NC}"
        else
          text_echo "${GREEN}  ✓ No duplicates found${NC}"
        fi
        text_echo ""
      fi
    done <<< "$CLONE_PATTERNS"
  fi
fi

	# Evaluate baseline entries for staleness before computing exit code / JSON
	check_stale_entries

	# Generate baseline file if requested
	generate_baseline_file

debug_echo "All checks complete. ERRORS=$ERRORS, WARNINGS=$WARNINGS"

	# Determine exit code
EXIT_CODE=0
if [ "$ERRORS" -gt 0 ]; then
  EXIT_CODE=1
elif [ "$STRICT" = "true" ] && [ "$WARNINGS" -gt 0 ]; then
  EXIT_CODE=1
fi

debug_echo "Generating output (format=$OUTPUT_FORMAT)..."

# Output based on format
if [ "$OUTPUT_FORMAT" = "json" ]; then
  debug_echo "Generating JSON output..."
  JSON_OUTPUT=$(output_json "$EXIT_CODE")
  debug_echo "JSON output generated, echoing..."
  echo "$JSON_OUTPUT"
  debug_echo "JSON output echoed"

  # Generate HTML report if running locally (not in GitHub Actions)
  if [ -z "$GITHUB_ACTIONS" ]; then
    # Create reports directory if it doesn't exist
    REPORTS_DIR="$PLUGIN_DIR/reports"
    mkdir -p "$REPORTS_DIR"

    # Generate timestamped HTML report filename
    REPORT_TIMESTAMP=$(timestamp_filename)
    HTML_REPORT="$REPORTS_DIR/$REPORT_TIMESTAMP.html"

    # Generate the HTML report using standalone Python converter
    # This is more reliable than the inline bash function
    # IMPORTANT: Redirect to /dev/tty to prevent output from being captured in JSON log
    if command -v python3 &> /dev/null; then
      if "$SCRIPT_DIR/json-to-html.py" "$LOG_FILE" "$HTML_REPORT" > /dev/tty 2>&1; then
        echo "" > /dev/tty
        echo "📊 HTML Report: $HTML_REPORT" > /dev/tty
      else
        echo "⚠ HTML report generation failed (Python converter error)" > /dev/tty
      fi
    else
      echo "⚠ HTML report generation skipped (python3 not found)" > /dev/tty
      echo "   Install Python 3 to enable HTML reports" > /dev/tty
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

# ============================================================
# PROFILING REPORT
# ============================================================
section_end
profile_end "FUNCTION_CLONE_DETECTOR"
profile_report

# ============================================================================
# Pattern Library Manager (Auto-Update Registry)
# ============================================================================
# Run pattern library manager to update canonical registry after each scan
# This ensures PATTERN-LIBRARY.json and PATTERN-LIBRARY.md stay in sync
#
# IMPORTANT: In JSON mode, redirect output to /dev/tty to prevent console
# output from being appended to the JSON log file (see Issue #2 from 2026-01-08)

if [ -f "$SCRIPT_DIR/pattern-library-manager.sh" ]; then
  if [ "$OUTPUT_FORMAT" = "json" ]; then
    # In JSON mode, send output to terminal only (not to log file)
    bash "$SCRIPT_DIR/pattern-library-manager.sh" both > /dev/tty 2>&1 || {
      echo "⚠️  Pattern library manager failed (non-fatal)" > /dev/tty
    }
  else
    # In text mode, output goes to log file normally
    echo ""
    echo "🔄 Updating pattern library registry..."
    bash "$SCRIPT_DIR/pattern-library-manager.sh" both 2>/dev/null || {
      echo "⚠️  Pattern library manager failed (non-fatal)"
    }
  fi
fi

exit $EXIT_CODE
