# GitHub Issue Creation Feature - Implementation Plan

**Created:** 2026-01-13  
**Status:** In Progress  
**Target Version:** v1.0.91

---

## 🎯 Goal

Automate creation of GitHub issues from WP Code Check scan results using the concise issue template format.

---

## 📋 Requirements

### Inputs
- JSON scan log (e.g., `dist/logs/2026-01-12-155649-UTC.json`)
- Template file with `GITHUB_REPO` field (e.g., `dist/TEMPLATES/universal-child-theme-oct-2024.txt`)
- GitHub CLI authenticated and ready

### Outputs
- Parent GitHub issue with summary and checkboxes
- Issue number returned for reference
- Optional: Auto-create sub-issues for each finding

---

## 🏗️ Architecture

### Script: `dist/bin/create-github-issue.sh`

**Purpose:** Standalone script to create GitHub issues from scan results

**Usage:**
```bash
# Create issue from latest scan
./dist/bin/create-github-issue.sh --scan-id 2026-01-12-155649-UTC

# Create issue with specific repo
./dist/bin/create-github-issue.sh --scan-id 2026-01-12-155649-UTC --repo owner/repo

# Create issue with sub-issues
./dist/bin/create-github-issue.sh --scan-id 2026-01-12-155649-UTC --create-sub-issues
```

**Workflow:**
1. Read JSON scan log
2. Extract AI triage results (confirmed issues)
3. Read template file to get GITHUB_REPO
4. Generate issue body using concise template
5. Create GitHub issue via `gh issue create`
6. Return issue number

---

## 📝 Issue Template Format

Based on `PROJECT/EXAMPLES/GITHUB-ISSUE-PROTOTYPE.md`:

**Parent Issue:**
- Title: `WP Code Check Review - [UTC timestamp]`
- Body: Scan metadata + confirmed issues + unconfirmed issues + links
- Labels: `automated-scan`, `security`, `performance`

**Sub-Issues (optional):**
- Title: Short description from finding
- Body: File location + fix + test checklist
- Labels: Based on severity (critical, high, medium, low)
- Parent: Link back to parent issue

---

## 🔧 Implementation Steps

### Step 1: Create `create-github-issue.sh`
- Parse command-line arguments
- Read JSON scan log
- Extract metadata (plugin name, version, timestamp)
- Extract AI triage results

### Step 2: Generate Issue Body
- Use concise template format
- Convert UTC timestamp to local time
- Format confirmed issues as checkboxes
- Format unconfirmed issues as checkboxes
- Add links to HTML/JSON reports

### Step 3: Create GitHub Issue
- Use `gh issue create --title "..." --body "..." --repo owner/repo`
- Add labels: `automated-scan`, `security`, `performance`
- Capture issue number from output

### Step 4: (Optional) Create Sub-Issues
- Parse each confirmed finding
- Generate sub-issue body
- Create with `gh issue create` and link to parent

### Step 5: Integration with `check-performance.sh`
- Add `--create-github-issue` flag
- After scan completes, call `create-github-issue.sh`
- Pass scan ID and template info

---

## 🧪 Testing Plan

1. **Test with real scan results** (Elementor or Binoid theme)
2. **Verify issue format** matches prototype
3. **Test with missing GITHUB_REPO** (should fail gracefully)
4. **Test sub-issue creation** (optional feature)
5. **Test with different repositories** (not just wp-code-check)

---

## 📚 Documentation Updates

- Update `README.md` with GitHub issue creation feature
- Update `dist/TEMPLATES/_AI_INSTRUCTIONS.md` with Phase 3 details
- Add examples to `EXAMPLES/` directory

---

## 🚀 Next Steps

1. Create `dist/bin/create-github-issue.sh` script
2. Test with existing scan results
3. Integrate with main scanner
4. Update documentation

