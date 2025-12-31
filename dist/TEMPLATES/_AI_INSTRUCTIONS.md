# AI Agent Instructions: Template Completion

## Purpose
Help users complete WP Code Check project configuration templates.

## Context
Users create template files in `/TEMPLATES/` to store project configurations. This allows them to run performance checks with a simple command like `run acme` instead of typing long paths every time.

## Workflow
1. User creates a new `.txt` file in `/TEMPLATES/` (e.g., `acme.txt`)
2. User pastes an absolute path to a WordPress plugin/theme directory
3. User asks you to complete the template
4. You extract metadata and fill in the template using the structure from `_TEMPLATE.txt`

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
- Use the structure from `/TEMPLATES/_TEMPLATE.txt`
- Fill in the **BASIC CONFIGURATION** section:
  - `PROJECT_NAME` (from filename)
  - `PATH` (from user's pasted path)
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

**User creates `/TEMPLATES/acme.txt` with:**
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
# BASELINE=.neochrome-baseline

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

