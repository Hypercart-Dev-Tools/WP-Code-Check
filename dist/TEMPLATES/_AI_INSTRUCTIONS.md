# AI Agent Instructions: Template Completion

## Purpose
Complete WP Code Check project templates for users.

## Location & Context
- Templates live in `dist/TEMPLATES/` (not `/TEMPLATES/`).
- The scripts load templates from `dist/` via `REPO_ROOT` (updated 2025-12-31).

## Template Completion (Required)
1. **Read user file**: single absolute path line (starts with `/`).
2. **Find metadata**:
   - Plugin: main PHP file with header block.
   - Theme: `style.css` header.
   - Extract **Name** and **Version**.
3. **PROJECT_NAME**: template filename without `.txt`.
4. **Fill `dist/TEMPLATES/_TEMPLATE.txt`**:
   - `PROJECT_NAME`, `PROJECT_PATH`, `NAME`, `VERSION`.
   - Keep all other options commented.
5. **If metadata fails**:
   - Still generate full template.
   - Leave `NAME`/`VERSION` blank.
   - Add header warning:
     ```bash
     # WARNING: Could not auto-detect plugin/theme metadata.
     # Please fill in NAME and VERSION manually.
     ```
   - Explain what was missing (path, header, main file) and suggest fixes.

## Output Formats & HTML Reports
- **Valid formats**: `json` (default) and `text`. **No `html` format.**
- JSON runs **auto-generate HTML** via `dist/bin/json-to-html.py` into `dist/reports/`.
- If HTML generation fails, manually run:
  ```bash
  python3 /path/to/wp-code-check/dist/bin/json-to-html.py <input.json> <output.html>
  ```
- JSON logs are in `dist/logs/`.

## Running Scans on External Paths (Critical)
When templates point outside the repo, **use absolute paths** to scripts.

**✅ Correct:**
```bash
/full/path/to/wp-code-check/dist/bin/check-performance.sh --paths /external/path
```

**Checklist:**
- Verify script is executable (`chmod +x`).
- Verify template exists in `dist/TEMPLATES/`.
- If location is unknown, ask user for WP Code Check install path.

## Quick Do/Don’t
**Do**
- Preserve user path exactly.
- Use absolute paths to scripts.
- Keep optional settings commented unless user asks.

**Don’t**
- Use `--format html`.
- Assume relative paths work.
- Skip permission checks when errors occur.

## Common Errors (Short)
- **Permission denied** → `chmod +x <script>`
- **No such file or directory** → use absolute path, verify install
- **Template not found** → check `dist/TEMPLATES/*.txt`
- **Invalid JSON / missing HTML template** → validate JSON, ensure `dist/bin/templates/report-template.html` exists
