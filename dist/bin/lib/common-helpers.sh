# shellcheck shell=bash
#!/usr/bin/env bash
#
# Neochrome WP Toolkit - Common Helper Functions
#
# Shared utility functions for bash-based tooling. Source this file rather
# than duplicating logic across scripts.

# Generate UTC timestamp for filenames (e.g., reports, logs)
# Usage: timestamp_filename
# Returns: 2025-12-30-164339-UTC
timestamp_filename() {
  date -u +"%Y-%m-%d-%H%M%S-UTC"
}

# Generate ISO 8601 UTC timestamp for JSON payloads
# Usage: timestamp_iso8601
# Returns: 2025-12-30T16:43:39Z
timestamp_iso8601() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Generate local timestamp with timezone for display/logs
# Usage: timestamp_local
# Returns: 2025-12-31 11:27:32 PST
timestamp_local() {
  date +"%Y-%m-%d %H:%M:%S %Z"
}
