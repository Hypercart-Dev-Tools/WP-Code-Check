#!/usr/bin/env bash
#
# Claude Code AI Triage Implementation
# Integrates Claude Code CLI for intelligent finding analysis
#
# Usage:
#   source dist/bin/lib/claude-triage.sh
#   run_claude_triage "$json_file" 300 200
#

# Build the analysis prompt from JSON findings
build_claude_prompt() {
  local json_file="$1"
  local max_findings="${2:-200}"
  
  # Extract key information from JSON
  local project_name=$(jq -r '.project.name // "Unknown"' "$json_file" 2>/dev/null)
  local findings_count=$(jq '.findings | length' "$json_file" 2>/dev/null)
  local errors=$(jq '.summary.total_errors // 0' "$json_file" 2>/dev/null)
  local warnings=$(jq '.summary.total_warnings // 0' "$json_file" 2>/dev/null)
  
  # Build findings summary (limit to max_findings)
  local findings_json=$(jq ".findings | .[0:$max_findings]" "$json_file" 2>/dev/null)
  
  # Create structured prompt
  cat <<'PROMPT_END'
You are an expert WordPress security and performance auditor. Analyze the following code scan findings and provide AI triage classification.

For each finding, classify as:
- "Confirmed": Real issue that needs fixing
- "False Positive": Not actually a problem (explain why)
- "Needs Review": Unclear, requires human judgment

Return ONLY valid JSON with this structure:
{
  "triaged_findings": [
    {
      "finding_key": {"id": "...", "file": "...", "line": ...},
      "classification": "Confirmed|False Positive|Needs Review",
      "confidence": "high|medium|low",
      "rationale": "Brief explanation"
    }
  ],
  "summary": {
    "confirmed_issues": <number>,
    "false_positives": <number>,
    "needs_review": <number>,
    "confidence_level": "high|medium|low"
  },
  "recommendations": ["Priority 1: ...", "Priority 2: ..."]
}

FINDINGS TO ANALYZE:
PROMPT_END
  
  echo "$findings_json"
}

# Run Claude Code triage with timeout
run_claude_triage() {
  local json_file="$1"
  local timeout="${2:-300}"
  local max_findings="${3:-200}"
  
  echo "🤖 Starting Claude Code AI triage..." >&2
  echo "   Timeout: ${timeout}s | Max findings: ${max_findings}" >&2
  
  # Build prompt
  local prompt=$(build_claude_prompt "$json_file" "$max_findings")
  
  # Run Claude with timeout
  local claude_output
  local claude_exit_code
  
  if ! command -v timeout &>/dev/null; then
    # Fallback if timeout command not available
    claude_output=$(claude -p "$prompt" --output-format json 2>&1)
    claude_exit_code=$?
  else
    # Use timeout command
    claude_output=$(timeout "$timeout" claude -p "$prompt" --output-format json 2>&1)
    claude_exit_code=$?
  fi
  
  # Handle timeout
  if [ $claude_exit_code -eq 124 ]; then
    echo "⏱️  Claude triage timed out after ${timeout}s" >&2
    echo "   Falling back to built-in ai-triage.py" >&2
    run_fallback_triage "$json_file" "$max_findings"
    return $?
  fi
  
  # Handle other errors
  if [ $claude_exit_code -ne 0 ]; then
    echo "❌ Claude triage failed (exit code: $claude_exit_code)" >&2
    echo "   Falling back to built-in ai-triage.py" >&2
    run_fallback_triage "$json_file" "$max_findings"
    return $?
  fi
  
  # Validate JSON output
  if ! echo "$claude_output" | jq empty 2>/dev/null; then
    echo "❌ Claude output is not valid JSON" >&2
    echo "   Falling back to built-in ai-triage.py" >&2
    run_fallback_triage "$json_file" "$max_findings"
    return $?
  fi
  
  # Inject triage data into JSON
  inject_claude_triage "$json_file" "$claude_output"
}

# Inject Claude triage results into JSON
inject_claude_triage() {
  local json_file="$1"
  local claude_output="$2"
  
  echo "📝 Injecting Claude triage results..." >&2
  
  # Use jq to merge Claude output into ai_triage section
  local temp_file="${json_file}.tmp"
  
  jq --argjson claude_data "$claude_output" \
    '.ai_triage = {
      "performed": true,
      "status": "complete",
      "timestamp": (now | todate),
      "version": "1.0",
      "backend": "claude",
      "scope": {
        "max_findings_reviewed": ($claude_data.triaged_findings | length),
        "findings_reviewed": ($claude_data.triaged_findings | length)
      },
      "summary": $claude_data.summary,
      "recommendations": $claude_data.recommendations,
      "triaged_findings": $claude_data.triaged_findings
    }' "$json_file" > "$temp_file"
  
  if [ $? -eq 0 ]; then
    mv "$temp_file" "$json_file"
    echo "✅ Claude triage data injected successfully" >&2
    return 0
  else
    echo "❌ Failed to inject Claude triage data" >&2
    rm -f "$temp_file"
    return 1
  fi
}

# Fallback to built-in Python triage
run_fallback_triage() {
  local json_file="$1"
  local max_findings="${2:-200}"
  
  echo "🔄 Running built-in Python AI triage..." >&2
  
  local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  
  if [ ! -f "$script_dir/ai-triage.py" ]; then
    echo "❌ ai-triage.py not found at $script_dir/ai-triage.py" >&2
    return 1
  fi
  
  python3 "$script_dir/ai-triage.py" "$json_file" --max-findings "$max_findings"
}

# Export functions
export -f build_claude_prompt
export -f run_claude_triage
export -f inject_claude_triage
export -f run_fallback_triage

