#!/usr/bin/env bash
#
# AI Triage Backend Orchestration
# Manages multiple LLM backends for AI triage analysis
#
# Supported backends:
#   - claude: Claude Code CLI (primary)
#   - fallback: Built-in ai-triage.py (always available)
#
# Usage:
#   source dist/bin/lib/ai-triage-backends.sh
#   run_ai_triage "$json_file" "claude" 300 200
#

# Detect available AI backends
detect_available_backends() {
  local available=()
  
  if command -v claude &>/dev/null; then
    available+=("claude")
  fi
  
  # fallback is always available (ai-triage.py)
  available+=("fallback")
  
  echo "${available[@]}"
}

# Get the best available backend (priority order)
get_best_backend() {
  local backends=($(detect_available_backends))
  echo "${backends[0]}"
}

# Main orchestration function
run_ai_triage() {
  local json_file="$1"
  local backend="${2:-auto}"
  local timeout="${3:-300}"
  local max_findings="${4:-200}"
  
  # Validate JSON file exists
  if [ ! -f "$json_file" ]; then
    echo "❌ JSON file not found: $json_file" >&2
    return 1
  fi
  
  # Auto-detect backend if not specified
  if [ "$backend" = "auto" ]; then
    backend=$(get_best_backend)
  fi
  
  # Validate backend
  case "$backend" in
    claude)
      run_claude_triage "$json_file" "$timeout" "$max_findings"
      ;;
    fallback)
      run_fallback_triage "$json_file" "$max_findings"
      ;;
    *)
      echo "❌ Unknown backend: $backend" >&2
      return 1
      ;;
  esac
}

# Check if Claude CLI is available
is_claude_available() {
  command -v claude &>/dev/null
}

# Export functions for use in check-performance.sh
export -f detect_available_backends
export -f get_best_backend
export -f run_ai_triage
export -f is_claude_available

