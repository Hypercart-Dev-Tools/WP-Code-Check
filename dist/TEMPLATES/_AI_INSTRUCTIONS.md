# AI Agent Instructions: Template Completion

## Purpose
Complete project templates in `dist/TEMPLATES/` so users can run scans with `--project <name>`.

## Location (Important)
Templates **must** live in `dist/TEMPLATES/` (not `/TEMPLATES/`). The `REPO_ROOT` points to `dist/`.

## When This Applies
If a user creates a template file that only contains a path and asks you to complete it.

---

## Minimal Workflow

### 1) Read the user’s template file
- Find the absolute path line (starts with `/`).
- This becomes `PROJECT_PATH`.

### 2) Extract metadata
- Navigate to the path.
- For plugins: open the main PHP file (usually matches folder name) and read the plugin header.
- For themes: check `style.css` header.
- Map:
  - `Plugin/Theme Name` → `NAME`
  - `Version` → `VERSION`

### 3) Set project identifier
- `PROJECT_NAME` = template filename without `.txt`.

### 4) Fill template structure
- Use `dist/TEMPLATES/_TEMPLATE.txt`.
- Fill **BASIC CONFIGURATION** only:
  - `PROJECT_NAME`, `PROJECT_PATH`, `NAME`, `VERSION`.
- Leave **COMMON/ADVANCED OPTIONS** commented out.

### 5) If metadata lookup fails
- Still create the template.
- Fill `PROJECT_NAME` + `PROJECT_PATH`.
- Leave `NAME`/`VERSION` blank.
- Add at top:
  ```bash
  # WARNING: Could not auto-detect plugin/theme metadata.
  # Please fill in NAME and VERSION manually.
  ```
- Explain why (missing header, path invalid, etc.).

---

## Quick Notes (Do/Don’t)
- **Preserve** the user’s original path (don’t “fix” it).
- **Use template filename** for `PROJECT_NAME`.
- **Add timestamp**: `# Auto-generated on YYYY-MM-DD`.
- **Validate path exists** if possible.

---

## Output Format Rules (Scanning)
- Supported formats: `json` (default) and `text`.
- **No `--format html` option.** HTML is auto-generated **from JSON**.

### HTML Generation (auto)
- JSON logs: `dist/logs/*.json`
- HTML reports: `dist/reports/*.html`
- Generator: `dist/bin/json-to-html.py` (Python 3, no deps)

### Manual JSON → HTML
```bash
python3 /path/to/wp-code-check/dist/bin/json-to-html.py <input.json> <output.html>
```

---

## Running Templates on External Paths (Common Pitfall)
Always use **absolute paths** to WP Code Check scripts and ensure they’re executable.

**Recommended:**
```bash
WP_CODE_CHECK=/full/path/to/wp-code-check
chmod +x "$WP_CODE_CHECK/dist/bin/run" "$WP_CODE_CHECK/dist/bin/check-performance.sh"
"$WP_CODE_CHECK/dist/bin/run" my-plugin
```

If the install location is unknown, ask the user for it.

---

## Troubleshooting Cheatsheet
- `Permission denied` → `chmod +x <script>`
- `No such file` → wrong path, use absolute
- `Template not found` → verify `dist/TEMPLATES/<name>.txt`
- `python3: command not found` → HTML generation skipped; JSON still saved

---

## After a Scan
When asked to run a scan, summarize findings in a few bullet points and offer to generate a matching `.md` report for the HTML filename.
