---
description: >
  Run WP Code Check (WPCC) — a fast WordPress performance and security scanner — against a
  plugin, theme, or project directory. Use when the user says "scan this plugin", "run wpcc",
  "check for performance issues", "run wp code check", "scan for security vulnerabilities",
  "check this theme for antipatterns", "check this WP code", or similar.
when_to_use: >
  Also fire when working in a WordPress plugin or theme directory and the user asks for a code
  quality scan, security review, antipattern check, or any WPCC-related scan — even without
  naming the tool explicitly. Recognises modifier keywords in $ARGUMENTS: "strict" (fail on
  warnings too), "baseline" (snapshot current state), "triage" (AI-powered explanation of
  findings), "verbose" (full output), "no-log" (suppress log file).
argument-hint: "[path] [strict|baseline|triage|verbose]"
allowed-tools:
  - Bash
---

# WP Code Check (WPCC)

Scan a WordPress plugin, theme, or project directory for performance antipatterns, security
issues, debug code, and other quality problems. Report a concise summary with the full report
path — never dump raw JSON into the conversation.

---

## Step 1 — Resolve the scanner

Run this resolver in order; use the first path that passes `-x`:

```bash
# 1. $WPCC_HOME env var (set this to move the repo without updating the skill)
SCANNER="${WPCC_HOME:+$WPCC_HOME/dist/bin/check-performance.sh}"

# 2. Canonical install location on this device
if [ -z "$SCANNER" ] || [ ! -x "$SCANNER" ]; then
  SCANNER="/Users/noelsaw/Documents/GH Repos/wp-code-check/dist/bin/check-performance.sh"
fi

# 3. Real PATH executable only (not a shell alias — aliases are invisible here)
if [ ! -x "$SCANNER" ]; then
  _candidate=$(command -v wpcc 2>/dev/null)
  # Accept only if it's a real file, not a function/alias
  if [ -n "$_candidate" ] && [ -f "$_candidate" ] && [ -x "$_candidate" ]; then
    SCANNER="$_candidate"
  fi
fi

# 4. Fail loud
if [ ! -x "$SCANNER" ]; then
  echo "WPCC scanner not found. Tried:"
  echo "  1. \$WPCC_HOME/dist/bin/check-performance.sh"
  echo "  2. /Users/noelsaw/Documents/GH Repos/wp-code-check/dist/bin/check-performance.sh"
  echo "  3. \$(command -v wpcc)"
  echo ""
  echo "Fix: run ./install.sh in the WP-Code-Check repo, or set WPCC_HOME to its location."
  exit 1
fi
```

If the scanner is found but not executable: `chmod +x "$SCANNER"`.

---

## Step 2 — Determine the target

Parse `$ARGUMENTS`. The first token that looks like a path (contains `/`, `~`, or `.`) or is
an existing directory is the **target**. Remaining tokens are **modifier keywords** (see Step 3).

```bash
TARGET=""
MODIFIERS=""

for arg in $ARGUMENTS; do
  if [ -z "$TARGET" ] && { [[ "$arg" == */* ]] || [[ "$arg" == .* ]] || [ -d "$arg" ]; }; then
    TARGET="$arg"
  else
    MODIFIERS="$MODIFIERS $arg"
  fi
done

# Fall back to session cwd if no target given
if [ -z "$TARGET" ]; then
  TARGET="$(pwd)"
  echo "No path given — scanning current directory: $TARGET"
fi

# Expand ~ manually (Bash doesn't expand inside variables)
TARGET="${TARGET/#\~/$HOME}"

if [ ! -d "$TARGET" ]; then
  echo "Target not found: $TARGET"
  exit 1
fi
```

If the target doesn't look like a WP project (no `*.php` files, no `wp-content`, no
`functions.php`), warn the user but proceed — they may be scanning a subdirectory.

---

## Step 3 — Build the command

Map modifier keywords to flags:

| Keyword in $ARGUMENTS | Flag added      | What it does |
|---|---|---|
| `strict`              | `--strict`      | Promotes warnings (e.g. N+1) to non-zero exit; errors always fail without it |
| `baseline`            | `--generate-baseline` | Snapshot current findings; future runs suppress baselined items |
| `triage`              | `--ai-triage`   | AI-powered explanation of findings (requires API key) |
| `verbose`             | `--verbose`     | Show all check output |
| `no-log`              | `--no-log`      | Suppress writing the JSON log file |

Build the full command:

```bash
FLAGS="--format json"
[[ "$MODIFIERS" == *strict*   ]] && FLAGS="$FLAGS --strict"
[[ "$MODIFIERS" == *baseline* ]] && FLAGS="$FLAGS --generate-baseline"
[[ "$MODIFIERS" == *triage*   ]] && FLAGS="$FLAGS --ai-triage"
[[ "$MODIFIERS" == *verbose*  ]] && FLAGS="$FLAGS --verbose"
[[ "$MODIFIERS" == *no-log*   ]] && FLAGS="$FLAGS --no-log"

CMD="\"$SCANNER\" --paths \"$TARGET\" $FLAGS"
```

**Echo the command before running it** so the user can audit it:

```
Running: "<SCANNER>" --paths "<TARGET>" <FLAGS>
```

---

## Step 4 — Run and capture output

Use the Bash tool with a generous timeout (scanner default is 300 s; allow 360 s):

```bash
REPORT_JSON=$(mktemp /tmp/wpcc-XXXXXX.json)
eval "$CMD" > "$REPORT_JSON" 2>&1
EXIT_CODE=$?
```

The scanner in JSON mode also auto-writes a timestamped log to
`<scanner-repo>/dist/logs/<timestamp>.json`. The last line of stdout contains the HTML
report path, e.g. `📊 HTML Report: /path/to/report.html`.

---

## Step 5 — Parse and summarise

**Exit-code decision rule (do not skip):**

- If `$REPORT_JSON` exists and parses as valid JSON → summarise findings (non-zero exit is
  expected when errors or, with `--strict`, warnings are found).
- If the file is empty or not valid JSON → scanner crashed; show the raw stderr instead.
- Exit code 124 → timeout; tell the user to narrow `--paths` to a subdirectory.

```bash
if [ ! -s "$REPORT_JSON" ] || ! jq empty "$REPORT_JSON" 2>/dev/null; then
  echo "Scanner failed (exit $EXIT_CODE). Output:"
  cat "$REPORT_JSON"
  exit $EXIT_CODE
fi

if [ "$EXIT_CODE" -eq 124 ]; then
  echo "Scanner timed out (300 s). Try scoping --paths to a smaller subdirectory."
  exit 124
fi

# Extract summary fields
TOTAL_ERRORS=$(jq -r '.summary.total_errors // 0' "$REPORT_JSON")
TOTAL_WARNINGS=$(jq -r '.summary.total_warnings // 0' "$REPORT_JSON")
FILES_ANALYZED=$(jq -r '.summary.files_analyzed // 0' "$REPORT_JSON")
SCAN_EXIT=$(jq -r '.summary.exit_code // 0' "$REPORT_JSON")

# Extract HTML report path from the last line of the raw output (outside the JSON)
HTML_REPORT=$(grep -o '📊 HTML Report: .*' "$REPORT_JSON" 2>/dev/null | sed 's/📊 HTML Report: //' || echo "")

# Top findings (up to 10, errors first)
TOP_FINDINGS=$(jq -r '
  .findings
  | sort_by(if .severity == "error" then 0 else 1 end)
  | .[:10][]
  | "  [\(.impact)] \(.id)  \(.file):\(.line)  — \(.message)"
' "$REPORT_JSON" 2>/dev/null)

# Failed checks
FAILED_CHECKS=$(jq -r '
  .checks[] | select(.status == "failed")
  | "  \(.name) (\(.impact), \(.findings_count) finding\(if .findings_count == 1 then "" else "s" end))"
' "$REPORT_JSON" 2>/dev/null)
```

---

## Step 6 — Report to the user

Present this summary — no raw JSON in the conversation:

```
WPCC Scan — <TARGET>
────────────────────────────────────────────
Errors:    <TOTAL_ERRORS>
Warnings:  <TOTAL_WARNINGS>
Files:     <FILES_ANALYZED>
Exit code: <SCAN_EXIT>  (<0 = clean | 1 = findings | 124 = timeout>)

Top findings:
<TOP_FINDINGS — or "None" if clean>

Failed checks:
<FAILED_CHECKS — or "None" if clean>

Full report: <HTML_REPORT or path to REPORT_JSON>
```

If `TOTAL_ERRORS == 0 && TOTAL_WARNINGS == 0`: report "No findings — scan is clean."

Offer next steps based on what was found:
- Errors present → "Run with `triage` to get an AI explanation of each finding."
- Many warnings → "Run with `strict` to see if any block a clean exit."
- First scan → "Run with `baseline` to snapshot this state and suppress in future runs."

Clean up: `rm -f "$REPORT_JSON"` after reporting.

---

## Install / update

This file lives at:
  `<wp-code-check repo>/skills/wpcc/SKILL.md`  ← **source of truth (git-tracked)**
  `~/.claude/skills/wpcc/SKILL.md`              ← device copy (symlink)

Install (one-time):
```bash
mkdir -p ~/.claude/skills
ln -sfn "/Users/noelsaw/Documents/GH Repos/wp-code-check/skills/wpcc" ~/.claude/skills/wpcc
```

With the symlink in place, edits to this file are live immediately — no re-copy needed.
If you ever need a real copy instead: `cp -R skills/wpcc ~/.claude/skills/wpcc`
