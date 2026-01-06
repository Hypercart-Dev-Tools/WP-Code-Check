# AI Agent Instructions: Template Completion

## Purpose
Help users complete WP Code Check project configuration templates.

## Context
Users create template files in `dist/TEMPLATES/` to store project configurations. This allows them to run performance checks with a simple command like `--project acme` instead of typing long paths every time.

**IMPORTANT:** Templates must be stored in `dist/TEMPLATES/` (not repository root `/TEMPLATES/`). The bash script's `REPO_ROOT` variable was updated on 2025-12-31 to point to the `dist/` directory to ensure templates load correctly from `dist/TEMPLATES/`.

## Workflow
1. User creates a new `.txt` file in `dist/TEMPLATES/` (e.g., `acme.txt`)
2. User pastes an absolute path to a WordPress plugin/theme directory
3. User asks you to complete the template
4. You extract metadata and fill in the template using the structure from `dist/TEMPLATES/_TEMPLATE.txt`

---

## Steps to Complete a Template

### 1. Read the User's File
- Look for a line containing an absolute path (starts with `/`)
- Example: `/Users/noelsaw/Local Sites/bloomzhemp-10-24-25/app/public/wp-content/plugins/acme-plugin`
- This is the `PATH` value

### 2. Extract Plugin/Theme Metadata
- Navigate to the path provided
- Look for the main PHP file (usually matches the folder name, e.g., `acme-plugin.php`)
- Parse the plugin/theme header comment block:
  ```php
  /**
   * Plugin Name: ACME Plugin
   * Version: 2.1.3
   * Description: Advanced content management
   * Author: ACME Corp
   */
  ```
- Extract:
  - `Plugin Name` → becomes `NAME`
  - `Version` → becomes `VERSION`

### 3. Determine Project Identifier
- Use the template filename (without `.txt`) as `PROJECT_NAME`
- Example: `acme.txt` → `PROJECT_NAME=acme`

### 4. Generate the Full Template
- Use the structure from `dist/TEMPLATES/_TEMPLATE.txt`
- Fill in the **BASIC CONFIGURATION** section:
  - `PROJECT_NAME` (from filename)
  - `PROJECT_PATH` (from user's pasted path)
  - `NAME` (from plugin header)
  - `VERSION` (from plugin header)
- Leave all **COMMON OPTIONS** and **ADVANCED OPTIONS** commented out (user can enable as needed)

### 5. Handle Errors Gracefully
If you can't find the plugin file or extract metadata:
- Create the template anyway with the full structure
- Fill in `PATH` and `PROJECT_NAME`
- Leave `NAME` and `VERSION` blank
- Add a comment at the top:
  ```bash
  # WARNING: Could not auto-detect plugin metadata.
  # Please fill in NAME and VERSION manually.
  ```
- Explain to the user what went wrong and suggest fixes:
  - "I couldn't find a plugin file matching the folder name"
  - "Please verify the path exists and contains a WordPress plugin"
  - "You can manually fill in the NAME and VERSION fields"

---

## Example Interaction

**User creates `dist/TEMPLATES/acme.txt` with:**
```
/Users/noelsaw/Local Sites/bloomzhemp-10-24-25/app/public/wp-content/plugins/acme-plugin
```

**User asks:**
> "Complete the template for acme.txt"

**You respond:**
> "I'll complete the template for you. Let me extract the plugin metadata..."
>
> [You read the plugin file and extract metadata]
>
> "✓ Template completed! Detected: ACME Plugin v2.1.3"

**Completed template:**
```bash
# WP Code Check - Project Configuration Template
# Auto-generated on 2025-12-30

# ============================================================
# BASIC CONFIGURATION
# ============================================================

# Project identifier (used with 'run' command)
PROJECT_NAME=acme

# Project path (REQUIRED)
PROJECT_PATH='/Users/noelsaw/Local Sites/bloomzhemp-10-24-25/app/public/wp-content/plugins/acme-plugin'

# Auto-detected metadata
NAME='ACME Plugin'
VERSION='2.1.3'

# ============================================================
# COMMON OPTIONS
# ============================================================

# Skip specific rules (comma-separated)
# Available rules: nonce-check, sql-injection, n-plus-one, direct-db-query,
#                  unescaped-output, transient-expiration, file-get-contents-url,
#                  http-no-timeout, cron-interval-validation
# Example: SKIP_RULES=nonce-check,n-plus-one
# SKIP_RULES=

# Error/warning thresholds (fail if exceeded)
# MAX_ERRORS=0
# MAX_WARNINGS=10

# ============================================================
# OUTPUT OPTIONS
# ============================================================

# Output format: text, json, html
# FORMAT=text

# Show full file paths (vs relative paths)
# SHOW_FULL_PATHS=false

# ============================================================
# ADVANCED OPTIONS
# (Modify these settings only if you understand their impact)
# ============================================================

# Baseline file for suppressing known issues
# BASELINE=.hcc-baseline

# Custom log directory
# LOG_DIR=./logs

# Include/exclude file patterns (grep-compatible regex)
# INCLUDE_PATTERN=
# EXCLUDE_PATTERN=node_modules|vendor

# Performance tuning
# MAX_FILE_SIZE_KB=1000
# PARALLEL_JOBS=4
```

---

## Important Notes

- **Always preserve the user's original path** - don't modify or "fix" it
- **Don't uncomment optional settings** unless the user specifically asks
- **Be helpful when metadata extraction fails** - explain what went wrong and how to fix it
- **Use the template filename for PROJECT_NAME** - this keeps things consistent
- **Add timestamps** - include "Auto-generated on YYYY-MM-DD" in the header
- **Validate the path exists** before completing the template (if possible)

---

## Common Issues & Solutions

**Issue:** Can't find the main plugin file
- **Solution:** Look for any `.php` file with a plugin header comment
- **Fallback:** Ask user which file is the main plugin file

**Issue:** Multiple plugin files found
- **Solution:** Choose the one that matches the folder name
- **Fallback:** Choose the first one alphabetically

**Issue:** Path doesn't exist
- **Solution:** Warn the user, but still create the template (they might be setting it up for later)

**Issue:** Not a WordPress plugin (no plugin header)
- **Solution:** Check if it's a theme (look for `style.css` with theme header)
- **Fallback:** Create template with blank NAME/VERSION and warn user

---

## Understanding Output Formats and Report Generation

### Important: How Output Formats Work

**The script supports TWO output formats:**
- `--format json` - JSON output (default) + auto-generates an HTML report locally
- `--format text` - Console output (no HTML report)

**There is NO `--format html` option.** HTML reports are automatically generated from JSON output.

### How HTML Reports Are Generated

When you run with `--format json` (or omit `--format`, since JSON is the default):

1. The script outputs JSON to a log file in `dist/logs/`
2. The script automatically calls the **Python-based HTML converter** (`dist/bin/json-to-html.py`)
3. The HTML report is saved to `dist/reports/` with a timestamp
4. On macOS/Linux, the report auto-opens in the default browser

**Example:**
```bash
# This generates BOTH JSON log AND HTML report
/path/to/wp-code-check/dist/bin/check-performance.sh --paths /path/to/theme --format json

# Equivalent (JSON is the default):
/path/to/wp-code-check/dist/bin/check-performance.sh --paths /path/to/theme

# Output locations:
# - JSON: dist/logs/2025-12-31-035126-UTC.json
# - HTML: dist/reports/2025-12-31-035126-UTC.html (auto-generated from JSON)
```

**Technical Details:**
- HTML generation uses a **standalone Python 3 script** for reliability
- The converter is fast (< 1 second for 100+ findings)
- No external dependencies required (uses Python 3 standard library)
- If Python 3 is not available, JSON will still be saved (HTML generation skipped)

### Finding Generated Reports

After running a scan, check these directories:
- **JSON logs**: `dist/logs/` (timestamped `.json` files)
- **HTML reports**: `dist/reports/` (timestamped `.html` files)

The most recent file in each directory is the latest scan result.

### Manually Converting JSON to HTML

If HTML generation fails during a scan, or if you need to regenerate an HTML report from an existing JSON log, use the standalone converter:

**Basic Usage:**
```bash
python3 /path/to/wp-code-check/dist/bin/json-to-html.py <input.json> <output.html>
```

**Example:**
```bash
# Convert a specific JSON log to HTML
python3 /path/to/wp-code-check/dist/bin/json-to-html.py \
  /path/to/wp-code-check/dist/logs/2026-01-05-032317-UTC.json \
  /path/to/wp-code-check/dist/reports/my-report.html

# Find and convert the latest JSON log
latest_json=$(ls -t /path/to/wp-code-check/dist/logs/*.json | head -1)
python3 /path/to/wp-code-check/dist/bin/json-to-html.py \
  "$latest_json" \
  /path/to/wp-code-check/dist/reports/latest-report.html
```

**When to Use Manual Conversion:**
- The main scan completed but HTML generation hung or timed out
- You want to regenerate an HTML report with updated styling
- You need to create multiple HTML reports from the same JSON data
- You're troubleshooting HTML generation issues

**Converter Features:**
- ✅ Fast & reliable (Python-based, no bash subprocess issues)
- ✅ Standalone (works independently of main scanner)
- ✅ Auto-opens report in browser (macOS/Linux)
- ✅ No external dependencies (Python 3 standard library only)
- ✅ Detailed progress output

**Troubleshooting:**
```bash
# Check Python 3 is installed
python3 --version

# Verify JSON file is valid
jq empty /path/to/wp-code-check/dist/logs/your-file.json

# Check template exists
ls -lh /path/to/wp-code-check/dist/bin/templates/report-template.html
```

---

## Running Scans on External Paths (Critical for AI Agents)

### The Problem

When users create templates that point to paths **outside** the WP Code Check directory, AI agents may encounter permission or execution issues:

```bash
# Template points to external path
PROJECT_PATH='/Users/noelsaw/Sites/my-plugin'

# But WP Code Check is installed here
/Users/noelsaw/Sites/wp-code-check/
```

### Common Errors

**Error 1: Permission Denied**
```
bash: ./dist/bin/check-performance.sh: Permission denied
```

**Error 2: Script Not Found**
```
bash: dist/bin/check-performance.sh: No such file or directory
```

**Error 3: Relative Path Issues**
```
Error: Cannot find check-performance.sh
```

---

## Solutions for AI Agents

### 1. Always Use Absolute Paths

**❌ DON'T do this:**
```bash
./dist/bin/check-performance.sh --paths /external/path
```

**✅ DO this instead:**
```bash
/full/path/to/wp-code-check/dist/bin/check-performance.sh --paths /external/path
```

### 2. Check Script Permissions First

Before running any script, verify it's executable:

```bash
# Check if executable
if [ ! -x "/path/to/wp-code-check/dist/bin/check-performance.sh" ]; then
  chmod +x /path/to/wp-code-check/dist/bin/check-performance.sh
fi

# Then run it
/path/to/wp-code-check/dist/bin/check-performance.sh --paths /external/path
```

### 3. Use the `run` Script with Absolute Path

The `run` script is designed to handle templates:

```bash
# Find WP Code Check installation
WP_CODE_CHECK_DIR="/path/to/wp-code-check"

# Make sure run script is executable
chmod +x "$WP_CODE_CHECK_DIR/dist/bin/run"

# Run the template
"$WP_CODE_CHECK_DIR/dist/bin/run" my-plugin
```

### 4. Determine WP Code Check Location

If you don't know where WP Code Check is installed, help the user find it:

```bash
# Ask the user
echo "Where is WP Code Check installed?"
echo "Common locations:"
echo "  - ~/Sites/wp-code-check"
echo "  - ~/Projects/wp-code-check"
echo "  - /usr/local/wp-code-check"

# Or search for it (if user gives permission)
find ~ -name "check-performance.sh" -path "*/wp-code-check/dist/bin/*" 2>/dev/null
```

### 5. Working Directory Matters

The script should be run from **any directory**, but you need the full path:

```bash
# User is here
cd /Users/noelsaw/Sites/my-plugin

# But script is here
/Users/noelsaw/Tools/wp-code-check/dist/bin/check-performance.sh --paths .

# The script will scan the current directory (my-plugin)
```

---

## Step-by-Step Workflow for AI Agents

### When User Says: "Run the template for my-plugin"

**Step 1: Locate WP Code Check**
```bash
# Check common locations or ask user
WP_CODE_CHECK="/path/to/wp-code-check"
```

**Step 2: Verify Template Exists**
```bash
TEMPLATE_FILE="$WP_CODE_CHECK/dist/TEMPLATES/my-plugin.txt"
if [ ! -f "$TEMPLATE_FILE" ]; then
  echo "Error: Template not found at $TEMPLATE_FILE"
  exit 1
fi
```

**Step 3: Make Scripts Executable**
```bash
chmod +x "$WP_CODE_CHECK/dist/bin/run"
chmod +x "$WP_CODE_CHECK/dist/bin/check-performance.sh"
```

**Step 4: Run the Template**
```bash
"$WP_CODE_CHECK/dist/bin/run" my-plugin
```

---

## Example: Complete AI Agent Workflow

```bash
#!/bin/bash

# User wants to run template "acme-plugin"
TEMPLATE_NAME="acme-plugin"

# Step 1: Find WP Code Check (ask user if needed)
WP_CODE_CHECK="/Users/noelsaw/Tools/wp-code-check"

# Step 2: Verify installation
if [ ! -d "$WP_CODE_CHECK/dist/bin" ]; then
  echo "❌ WP Code Check not found at: $WP_CODE_CHECK"
  echo "Please provide the correct path to WP Code Check installation"
  exit 1
fi

# Step 3: Verify template exists
TEMPLATE_FILE="$WP_CODE_CHECK/dist/TEMPLATES/${TEMPLATE_NAME}.txt"
if [ ! -f "$TEMPLATE_FILE" ]; then
  echo "❌ Template not found: $TEMPLATE_FILE"
  echo "Available templates:"
  ls -1 "$WP_CODE_CHECK/dist/TEMPLATES/"*.txt 2>/dev/null | xargs -n1 basename
  exit 1
fi

# Step 4: Make scripts executable
chmod +x "$WP_CODE_CHECK/dist/bin/run" 2>/dev/null
chmod +x "$WP_CODE_CHECK/dist/bin/check-performance.sh" 2>/dev/null

# Step 5: Run the scan
echo "🚀 Running WP Code Check for: $TEMPLATE_NAME"
"$WP_CODE_CHECK/dist/bin/run" "$TEMPLATE_NAME"
```

---

## Quick Reference for AI Agents

### ✅ DO:
- Use absolute paths to WP Code Check scripts
- Check and set execute permissions before running
- Verify template files exist before running
- Ask user for WP Code Check location if unknown
- Handle errors gracefully with helpful messages

### ❌ DON'T:
- Assume relative paths will work
- Run scripts without checking permissions
- Assume WP Code Check is in current directory
- Give up on first error - try fixing permissions

---

## Debugging Commands for AI Agents

### Check if script exists and is executable:
```bash
ls -lh /path/to/wp-code-check/dist/bin/check-performance.sh
```

### Make script executable:
```bash
chmod +x /path/to/wp-code-check/dist/bin/check-performance.sh
```

### Test script runs:
```bash
/path/to/wp-code-check/dist/bin/check-performance.sh --help
```

### List available templates:
```bash
ls -1 /path/to/wp-code-check/dist/TEMPLATES/*.txt
```

### Read template content:
```bash
cat /path/to/wp-code-check/dist/TEMPLATES/my-plugin.txt
```

### Convert JSON log to HTML manually:
```bash
# Find latest JSON log
latest_json=$(ls -t /path/to/wp-code-check/dist/logs/*.json | head -1)

# Convert to HTML
python3 /path/to/wp-code-check/dist/bin/json-to-html.py \
  "$latest_json" \
  /path/to/wp-code-check/dist/reports/manual-report.html
```

### Check Python 3 is available:
```bash
python3 --version
```

### Validate JSON log file:
```bash
jq empty /path/to/wp-code-check/dist/logs/your-file.json
```

---

## Error Messages to Watch For

| Error | Cause | Solution |
|-------|-------|----------|
| `Permission denied` | Script not executable | `chmod +x script.sh` |
| `No such file or directory` | Wrong path or script doesn't exist | Use absolute path, verify file exists |
| `Template not found` | Template file doesn't exist | Check `TEMPLATES/` directory |
| `command not found: run` | Script not in PATH | Use absolute path to `run` script |
| `Path does not exist` | Template points to non-existent path | Verify `PROJECT_PATH` in template |
| `python3: command not found` | Python 3 not installed | Install Python 3 or skip HTML generation |
| `HTML template not found` | Missing report template | Verify `dist/bin/templates/report-template.html` exists |
| `Invalid JSON` | Corrupted JSON log file | Check JSON syntax with `jq` |

---

**Key Takeaway for AI Agents:**

When running WP Code Check on external paths, **always use absolute paths** to the WP Code Check installation and **verify permissions** before executing scripts. Don't assume the current working directory contains WP Code Check.

---

## Troubleshooting: What Happened on 2025-12-31

### The Issue

When running `run universal-child-theme-oct-2024 --format html`, the script appeared to hang with no output. This was confusing because:

1. The command seemed to run but produced no visible output
2. No HTML file appeared in the expected location
3. The process appeared to complete but silently

### Root Cause

**The `--format html` option does not exist.** The script only supports:
- `--format json` (default, JSON output + auto-generated HTML)
- `--format text` (console output)

When an invalid format is passed, the script validation should catch it, but the error handling wasn't immediately visible in the terminal.

### The Solution

**Use JSON output to generate HTML reports** (and avoid `--format html`):

```bash
# ✅ CORRECT - Generates HTML report (via Python converter)
/path/to/wp-code-check/dist/bin/check-performance.sh --paths /path/to/theme --format json

# ✅ ALSO CORRECT - JSON is the default (unless a template overrides FORMAT)
/path/to/wp-code-check/dist/bin/check-performance.sh --paths /path/to/theme

# ❌ WRONG - No such format exists
/path/to/wp-code-check/dist/bin/check-performance.sh --paths /path/to/theme --format html
```

### How to Find the Generated Report

After running with `--format json`:

1. Check the `dist/reports/` directory
2. Look for the most recent `.html` file (sorted by timestamp)
3. Open it in a browser

**Example workflow:**
```bash
# Run the scan (automatically generates HTML via Python converter)
/path/to/wp-code-check/dist/bin/check-performance.sh --paths /path/to/theme --format json

# Find the latest report
ls -lh /path/to/wp-code-check/dist/reports/ | tail -1

# Open it (macOS)
open /path/to/wp-code-check/dist/reports/2025-12-31-035126-UTC.html
```

### If HTML Generation Fails

If the scan completes but HTML generation hangs or fails:

1. **JSON is still saved** - Check `dist/logs/` for the JSON file
2. **Manually convert to HTML** using the standalone converter:

```bash
# Find the latest JSON log
latest_json=$(ls -t /path/to/wp-code-check/dist/logs/*.json | head -1)

# Convert to HTML
python3 /path/to/wp-code-check/dist/bin/json-to-html.py \
  "$latest_json" \
  /path/to/wp-code-check/dist/reports/manual-report.html
```

3. **Report the issue** so the integration can be improved

### For Future AI Agents

When a user asks to "run a template and output to HTML":

1. **Use JSON output** (not `--format html`)
  - Prefer being explicit with `--format json`, because templates can override `FORMAT`.
2. **Wait for the scan to complete** (large themes/plugins may take 1-2 minutes)
3. **Check `dist/reports/`** for the generated HTML file
4. **If HTML generation fails**, manually convert the JSON using the Python converter
5. **Open the latest `.html` file** in the browser

The script will automatically:
- Generate JSON output to `dist/logs/`
- Call the Python-based HTML converter (`dist/bin/json-to-html.py`)
- Save the HTML report to `dist/reports/` with matching timestamp
- Auto-open the HTML in the browser (on macOS/Linux)

**If HTML generation hangs or fails:**
- The JSON log is still saved and valid
- Use the standalone Python converter to generate HTML manually
- See "Manually Converting JSON to HTML" section above for details

