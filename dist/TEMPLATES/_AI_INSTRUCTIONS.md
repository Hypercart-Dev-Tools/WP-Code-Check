# AI Agent Instructions for WP Code Check

## Overview

Complete end-to-end workflow:
1. **Phase 1a**: Check for existing templates in `dist/TEMPLATES/`
2. **Phase 1b**: Complete template if needed (extract metadata)
3. **Phase 1c**: Run scan using template or direct path
4. **Phase 2**: AI-assisted triage of findings

---

## Phase 1a: Check for Existing Templates

**ALWAYS start here.** Look for an existing template matching the plugin/theme name.

```bash
ls -1 /Users/noelsaw/Documents/GitHub\ Repos/wp-code-check/dist/TEMPLATES/*.txt
```

**Examples of template names:**
- `gravityforms.txt` → for Gravity Forms plugin
- `woocommerce.txt` → for WooCommerce plugin
- `twentytwentyfour.txt` → for Twenty Twenty-Four theme

If a template exists, skip to **Phase 1c: Running Scans**.

---

## Phase 1b: Template Completion (If Needed)

### When to Complete a Template

User creates a new `.txt` file in `dist/TEMPLATES/` with just a path, or asks you to complete one.

**Example only**: User creates `dist/TEMPLATES/gravityforms.txt` with:
```
/Users/noelsaw/Local Sites/my-site/app/public/wp-content/plugins/gravityforms
```

### Steps to Complete a Template

**Step 1: Read the user's file** to extract the path

**Step 2: Extract plugin/theme metadata**
- Navigate to the path
- Find the main PHP file (usually matches folder name, e.g., `gravityforms.php`)
- Parse the plugin header:
  ```php
  /**
   * Plugin Name: Gravity Forms
   * Version: 2.7.1
   * Description: ...
   */
  ```
- Extract `Plugin Name` and `Version`

**Step 3: Generate the template** using this structure:
```bash
# WP Code Check - Project Configuration Template
# Auto-generated on YYYY-MM-DD

# ============================================================
# BASIC CONFIGURATION
# ============================================================

PROJECT_NAME=gravityforms
PROJECT_PATH='/Users/noelsaw/Local Sites/my-site/app/public/wp-content/plugins/gravityforms'
NAME='Gravity Forms'
VERSION='2.7.1'

# ============================================================
# COMMON OPTIONS
# ============================================================

# SKIP_RULES=
# MAX_ERRORS=0
# MAX_WARNINGS=10

# ============================================================
# OUTPUT OPTIONS
# ============================================================

# FORMAT=json
# SHOW_FULL_PATHS=false

# ============================================================
# ADVANCED OPTIONS
# ============================================================

# BASELINE=.hcc-baseline
# LOG_DIR=./logs
# EXCLUDE_PATTERN=node_modules|vendor
# MAX_FILE_SIZE_KB=1000
# PARALLEL_JOBS=4
```

**Step 4: Handle errors gracefully**
- If you can't find the plugin file, create the template anyway
- Add a warning comment: `# WARNING: Could not auto-detect plugin metadata. Please fill in NAME and VERSION manually.`
- Explain what went wrong to the user

### Important Notes
- Always preserve the user's original path
- Don't uncomment optional settings unless asked
- Add timestamps in the header
- Validate the path exists before completing

---

## Phase 1c: Running Scans

### How Users Should Ask the AI Agent

Users can ask the AI agent to run a template in natural language:

**Examples of valid requests:**
- "Run the gravityforms template"
- "Scan gravityforms"
- "Run gravityforms scan"
- "Execute the gravityforms template"
- "Perform a scan on gravityforms"

### AI Agent: How to Run Templates

**Step 1: Determine the template name**
- User says: "Run the gravityforms template"
- Template name: `gravityforms`
- Template file: `dist/TEMPLATES/gravityforms.txt`

**Step 2: Try filename variations**
If the exact filename doesn't exist, try these variations:
1. Exact name: `gravityforms.txt`
2. With hyphens: `gravity-forms.txt`
3. With underscores: `gravity_forms.txt`
4. With spaces (escaped): `gravity\ forms.txt`

**Step 3: Run the template**
```bash
/Users/noelsaw/Documents/GitHub\ Repos/wp-code-check/dist/bin/run gravityforms
```

**Step 4: Wait for completion**
- Scans typically take 1-2 minutes for large plugins
- JSON log will be saved to `dist/logs/TIMESTAMP.json`
- HTML report will be auto-generated to `dist/reports/TIMESTAMP.html`

### Using Direct Paths (If No Template Exists)
```bash
/Users/noelsaw/Documents/GitHub\ Repos/wp-code-check/dist/bin/check-performance.sh --paths /path/to/plugin --format json
```

### Output Locations
- **JSON logs**: `dist/logs/TIMESTAMP.json`
- **HTML reports**: `dist/reports/TIMESTAMP.html` (auto-generated from JSON)

---

## Phase 2: AI-Assisted Triage (Manual, v1.1 POC)

After HTML report is generated, perform a 2nd pass AI triage to identify false positives and provide an overall assessment.

### When to Use
- User explicitly asks: "Run AI triage on this report"
- User wants to validate false positives before publishing
- User needs an executive summary of findings

### HTML Report Layout

**Phase 2 section appears at the TOP of the HTML report** (TL;DR format):
- Summary stats grid (Reviewed, Confirmed, False Positives, Needs Review, Confidence)
- Overall narrative (3-5 paragraphs) covering:
  - Overview of findings and confirmed issues
  - False positives explanation with percentage
  - Items needing manual review
  - Recommendations list
  - Next steps guidance

Users see the summary immediately without scrolling.

### Workflow Steps

**Step 1: Read the JSON log**
```bash
cat dist/logs/TIMESTAMP.json | jq '.findings[] | {id, severity, file, line}'
```

**Step 2: Analyze findings** for false positives
- Check for `phpcs:ignore` comments with justification
- Verify nonce/capability checks nearby
- Look for adjacent sanitization functions
- Identify string literal matches vs actual superglobal access

**Step 3: Update the JSON** with triage summary and recommendations
```python
import json
from datetime import datetime

# Read existing JSON
with open('dist/logs/TIMESTAMP.json', 'r') as f:
    data = json.load(f)

# Inject ai_triage data (overall summary format)
data['ai_triage'] = {
    'performed': True,
    'status': 'complete',
    'timestamp': datetime.utcnow().isoformat() + 'Z',
    'version': '1.0',
    'summary': {
        'findings_reviewed': 10,
        'confirmed_issues': 2,
        'false_positives': 7,
        'needs_review': 1,
        'confidence_level': 'high'
    },
    'recommendations': [
        'Priority 1: Fix unsafe RegExp in repeater.js (line 126)',
        'Priority 2: Review minified JS source for obfuscation',
        'Consider adding baseline file to suppress known false positives'
    ]
}

# Write updated JSON
with open('dist/logs/TIMESTAMP.json', 'w') as f:
    json.dump(data, f, indent=2)
```

**Step 4: Re-generate HTML**
```bash
python3 dist/bin/json-to-html.py dist/logs/TIMESTAMP.json dist/reports/TIMESTAMP.html
```

The HTML report will now show:
- Summary stats at top
- Overall narrative explaining the findings
- Detailed findings section below for reference

### Summary Stats

| Stat | Meaning |
|------|---------|
| **Reviewed** | Total findings analyzed |
| **Confirmed** | Real issues requiring action (green) |
| **False Positives** | Safe to ignore, have safeguards (gray) |
| **Needs Review** | Ambiguous, require human judgment (yellow) |
| **Confidence** | Overall confidence level of analysis |

### Confidence Levels

| Level | Meaning |
|-------|---------|
| `high` | 90%+ confident in this assessment |
| `medium` | 60-89% confident |
| `low` | <60% confident, needs human review |

---

## Common False Positive Patterns

| Rule ID | Common False Positive Reason |
|---------|------------------------------|
| `spo-002-superglobals` | Has `phpcs:ignore` with nonce verification elsewhere in function |
| `rest-no-pagination` | Endpoint returns single item, not collection (e.g., `/item/{id}`) |
| `get-users-no-limit` | Args passed through `apply_filters()` hook that adds limit |
| `direct-db-query` | Query uses `$wpdb->prepare()` on adjacent line (multi-line query) |
| `admin-no-cap-check` | Function is only called from another function that has cap check |
| `n-plus-1-pattern` | File has "meta" in variable name but not actual meta query in loop |

---

## Manual JSON to HTML Conversion

If HTML generation fails during a scan:

```bash
# Find latest JSON log
latest_json=$(ls -t dist/logs/*.json | head -1)

# Convert to HTML
python3 dist/bin/json-to-html.py "$latest_json" dist/reports/manual-report.html
```

---

## Troubleshooting

| Error | Solution |
|-------|----------|
| `Permission denied` | `chmod +x /path/to/script.sh` |
| `No such file or directory` | Use absolute path, verify file exists |
| `python3: command not found` | Install Python 3 |
| `Invalid JSON` | Validate with: `jq empty dist/logs/your-file.json` |

---

