# WP Code Check - Shell Quick Start Guide

**Fast, zero-dependency WordPress performance analyzer for terminal users**

---

## 🚀 Quick Install

### One-Line Install

```bash
git clone https://github.com/Hypercart-Dev-Tools/WP-Code-Check.git
cd WP-Code-Check
./install.sh
```

The installer will:
- ✅ Make scripts executable
- ✅ Offer to add `wp-check` alias to your shell
- ✅ Offer to enable tab completion
- ✅ Test the installation
- ✅ Show quick start examples

### Manual Install

```bash
# Clone the repository
git clone https://github.com/Hypercart-Dev-Tools/WP-Code-Check.git
cd WP-Code-Check

# Make scripts executable
chmod +x dist/bin/check-performance.sh
chmod +x dist/bin/json-to-html.py

# Add alias to your shell (bash)
echo "alias wp-check='$(pwd)/dist/bin/check-performance.sh --paths'" >> ~/.bashrc
source ~/.bashrc

# Or for zsh
echo "alias wp-check='$(pwd)/dist/bin/check-performance.sh --paths'" >> ~/.zshrc
source ~/.zshrc
```

---

---

## 🤖 Claude Code Integration

If you use **Claude Code** (the AI coding assistant), a global `/wpcc` skill is available
that lets any Claude session on this machine scan a plugin or theme without remembering flags:

```
/wpcc /path/to/your-plugin
/wpcc /path/to/your-plugin strict
/wpcc /path/to/your-plugin baseline
/wpcc /path/to/your-plugin triage
```

Or just say *"run wpcc on this plugin"* and Claude will invoke it automatically.

**One-time device install** (symlink — repo edits stay live):
```bash
mkdir -p ~/.claude/skills
ln -sfn "$(pwd)/skills/wpcc" ~/.claude/skills/wpcc
```

The skill resolves the scanner path automatically, summarises findings, and never dumps
raw JSON into the conversation. See [`skills/wpcc/SKILL.md`](skills/wpcc/SKILL.md) for details.

---

## ⚡ Special Commands

### Interactive Setup Wizard

```bash
# Run the setup wizard
wp-check init
```

Guides you through:
- Default scan path configuration
- Output format preference
- Shell alias creation
- Test scan

### Update WP Code Check

```bash
# Check for and install updates
wp-check update
```

Shows available updates and changelog before updating.

### Check Version

```bash
# Show current version
wp-check version
```

---

## 📖 Basic Usage

### Scan a Plugin or Theme

```bash
# Scan a WordPress plugin
wp-check ~/wp-content/plugins/my-plugin

# Scan a theme
wp-check ~/wp-content/themes/my-theme

# Scan current directory
wp-check .
```

### Common Options

```bash
# Strict mode - fail on warnings (great for CI/CD)
wp-check ~/my-plugin --strict

# Text output instead of HTML report
wp-check ~/my-plugin --format text

# Verbose mode - show all matches
wp-check ~/my-plugin --verbose

# Disable logging
wp-check ~/my-plugin --no-log
```

---

## 🎯 Common Workflows

### 1. Quick Health Check

```bash
wp-check ~/my-plugin
```

Opens an HTML report in your browser showing all issues.

### 2. CI/CD Integration

```bash
# In your CI pipeline
wp-check . --format json --strict --no-log

# Exit code 0 = pass, non-zero = fail
```

### 3. Legacy Code Baseline

```bash
# First, generate baseline (suppresses existing issues)
wp-check ~/legacy-plugin --generate-baseline

# Now only new issues will be reported
wp-check ~/legacy-plugin
```

### 4. Scan Multiple Projects

```bash
wp-check --paths "~/plugin1 ~/plugin2 ~/theme1"
```

### 5. Use Saved Templates

```bash
# Create a template file: dist/TEMPLATES/my-plugin.txt
# Then scan using the template
wp-check --project my-plugin
```

---

## 🔍 What It Detects

### 🔴 Critical Issues (Errors)

- **Unbound database queries** - Missing LIMIT clauses
- **SQL injection risks** - Unsafe `$wpdb` usage
- **Missing sanitization** - Direct `$_GET`/`$_POST` access
- **Missing nonce verification** - Unprotected forms
- **Unsafe file operations** - Security vulnerabilities

### 🟡 Performance Issues (Warnings)

- **N+1 query patterns** - Database queries in loops
- **Missing caching** - No transient usage
- **Inefficient queries** - Poor `WP_Query` usage
- **Large array operations** - Performance bottlenecks

### 🔵 Best Practices (Info)

- **Magic strings** - Hardcoded values
- **Function clones** - Duplicate code
- **Missing error handling** - No try/catch or checks

---

## 📊 Understanding Results

### HTML Report (Default)

```bash
wp-check ~/my-plugin
# Opens report in browser automatically
```

**Report sections:**
- Summary (total issues by severity)
- Critical issues (must fix)
- Warnings (should fix)
- Info (nice to fix)
- File-by-file breakdown

### JSON Output

```bash
wp-check ~/my-plugin --format json
```

**Use cases:**
- CI/CD pipelines
- Custom reporting tools
- Automated workflows
- Integration with other tools

### Text Output

```bash
wp-check ~/my-plugin --format text
```

**Use cases:**
- Quick terminal review
- Grep/search through results
- Lightweight output

---

## 🛠️ Advanced Features

### Tab Completion

**Enable tab completion for faster command entry:**

```bash
# Manual installation (if not done by install.sh)
echo "source ~/WP-Code-Check/dist/bin/wp-check-completion.bash" >> ~/.bashrc
source ~/.bashrc

# Or for zsh
echo "source ~/WP-Code-Check/dist/bin/wp-check-completion.bash" >> ~/.zshrc
source ~/.zshrc
```

**Usage:**

```bash
# Press TAB to complete options
wp-check --<TAB>
# Shows: --paths --format --strict --verbose --baseline --help ...

# Press TAB to complete format values
wp-check --format <TAB>
# Shows: text json

# Press TAB to complete template names
wp-check --project <TAB>
# Shows: my-plugin woocommerce-subscriptions ...
```

### Baseline Management

**Problem:** Legacy code has 100+ existing issues, you only want to catch NEW issues.

**Solution:**

```bash
# Generate baseline from current state
wp-check ~/legacy-plugin --generate-baseline

# Creates .hcc-baseline file
# Future scans only show NEW issues
wp-check ~/legacy-plugin
```

**Custom baseline location:**

```bash
wp-check ~/plugin --baseline ~/baselines/plugin-v1.0.baseline
```

**Ignore baseline:**

```bash
wp-check ~/plugin --ignore-baseline
```

### Template System

**Problem:** Scanning the same plugin repeatedly with same options.

**Solution:** Create a template file.

```bash
# Create: dist/TEMPLATES/my-plugin.txt
PROJECT_NAME="My Plugin"
PROJECT_VERSION="1.0.0"
PROJECT_PATH="~/wp-content/plugins/my-plugin"
FORMAT="json"
BASELINE="~/baselines/my-plugin.baseline"

# Then scan with:
wp-check --project my-plugin
```

See `dist/HOWTO-TEMPLATES.md` for full template guide.

---

## 🔧 Troubleshooting

### "Command not found: wp-check"

**Solution:** Alias not loaded. Run:

```bash
source ~/.bashrc  # or ~/.zshrc
```

Or use full path:

```bash
~/WP-Code-Check/dist/bin/check-performance.sh --paths ~/my-plugin
```

### "Permission denied"

**Solution:** Make scripts executable:

```bash
chmod +x dist/bin/check-performance.sh
chmod +x dist/bin/json-to-html.py
```

### HTML report doesn't open

**Solution:** Manually open the report:

```bash
# Find latest report
ls -lt dist/reports/*.html | head -1

# Open manually
open dist/reports/latest-report.html  # macOS
xdg-open dist/reports/latest-report.html  # Linux
```

### "No such file or directory" errors

**Solution:** Check paths are correct:

```bash
# Use absolute paths
wp-check ~/wp-content/plugins/my-plugin

# Or relative to current directory
cd ~/wp-content/plugins
wp-check my-plugin
```

---

## 📚 More Documentation

- **Full User Guide:** `dist/README.md`
- **Template Guide:** `dist/HOWTO-TEMPLATES.md`
- **Changelog:** `CHANGELOG.md`
- **FAQ:** `FAQS.md`

---

## 🆘 Getting Help

```bash
# Show help
wp-check --help

# Check version
grep "SCRIPT_VERSION=" dist/bin/check-performance.sh
```

**Support:**
- GitHub Issues: https://github.com/Hypercart-Dev-Tools/WP-Code-Check/issues
- Documentation: https://github.com/Hypercart-Dev-Tools/WP-Code-Check

---

## 🎓 Tips & Tricks

### Create Project-Specific Aliases

```bash
# Add to ~/.bashrc or ~/.zshrc
alias check-woo='wp-check ~/wp-content/plugins/woocommerce'
alias check-theme='wp-check ~/wp-content/themes/my-theme'
```

### Scan on Git Commit

```bash
# Add to .git/hooks/pre-commit
#!/bin/bash
wp-check . --strict --no-log || exit 1
```

### Watch for Changes

```bash
# Using fswatch (macOS)
fswatch -o ~/my-plugin | xargs -n1 -I{} wp-check ~/my-plugin

# Using inotifywait (Linux)
while inotifywait -r ~/my-plugin; do
  wp-check ~/my-plugin
done
```

### Combine with Other Tools

```bash
# Scan and save results
wp-check ~/plugin --format json > results.json

# Count critical issues
jq '[.findings[] | select(.severity=="error")] | length' results.json

# Extract file paths with issues
jq -r '.findings[].file' results.json | sort -u
```

---

**Happy scanning! 🚀**

