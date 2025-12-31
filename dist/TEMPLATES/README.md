# Project Templates

Save scan configurations for frequently-checked WordPress plugins and themes.

---

## 🎯 Why Use Templates?

Instead of typing this every time:
```bash
./dist/bin/check-performance.sh --paths /Users/noelsaw/Local\ Sites/my-site/wp-content/plugins/my-plugin
```

Create a template and run this:
```bash
./dist/bin/run my-plugin
```

---

## 🚀 Quick Start

### 1. Create a Template File

```bash
# Create a new template file (use any name you want)
touch dist/TEMPLATES/my-plugin.txt
```

### 2. Add Your Plugin Path

Edit the file and paste the absolute path to your plugin:
```
/Users/noelsaw/Local Sites/my-site/wp-content/plugins/my-plugin
```

### 3. Let AI Complete It (Optional)

If you're using an AI assistant (like Augment, Cursor, or GitHub Copilot):

> "Complete the template for my-plugin.txt"

The AI will:
- Extract plugin name and version from the plugin header
- Fill in the complete template structure
- Leave optional settings commented out

### 4. Run Your Template

```bash
./dist/bin/run my-plugin
```

---

## 📝 Manual Template Creation

If you prefer to create templates manually, copy `_TEMPLATE.txt`:

```bash
cp dist/TEMPLATES/_TEMPLATE.txt dist/TEMPLATES/my-plugin.txt
```

Then edit and fill in:
- `PROJECT_NAME` - Template identifier (e.g., `my-plugin`)
- `PROJECT_PATH` - Absolute path to your plugin/theme
- `NAME` - Plugin/theme name (optional)
- `VERSION` - Current version (optional)

---

## ⚙️ Template Options

Templates support all command-line options:

### Common Options

```bash
# Skip specific checks
SKIP_RULES=nonce-check,n-plus-one

# Set error/warning thresholds
MAX_ERRORS=0
MAX_WARNINGS=10

# Change output format
FORMAT=json
```

### Advanced Options

```bash
# Use a baseline file
BASELINE=.neochrome-baseline

# Custom log directory
LOG_DIR=./custom-logs

# Exclude patterns
EXCLUDE_PATTERN=node_modules|vendor|tests
```

See `_TEMPLATE.txt` for all available options.

---

## 📂 Example Templates

### WordPress Plugin

```bash
# WP Code Check - Project Configuration
PROJECT_NAME=acme-plugin
PROJECT_PATH='/Users/noelsaw/Sites/acme/wp-content/plugins/acme-plugin'
NAME='ACME Plugin'
VERSION='2.1.3'

# Skip N+1 warnings (legacy code)
# SKIP_RULES=n-plus-one

# Fail on any errors
# MAX_ERRORS=0
```

### WordPress Theme

```bash
# WP Code Check - Project Configuration
PROJECT_NAME=acme-theme
PROJECT_PATH='/Users/noelsaw/Sites/acme/wp-content/themes/acme-theme'
NAME='ACME Theme'
VERSION='1.5.0'

# Generate JSON for CI/CD
# FORMAT=json
```

---

## 🔒 Privacy & Security

**Templates are NOT committed to Git** by default.

The `.gitignore` file excludes:
- ✅ All `.txt` files in `TEMPLATES/` (except `_TEMPLATE.txt`)
- ✅ Protects your local file paths
- ✅ Prevents accidental exposure of project structure

**Safe to commit:**
- `_TEMPLATE.txt` - Reference template
- `_AI_INSTRUCTIONS.md` - AI completion guide
- `README.md` - This file

---

## 🤖 AI-Assisted Template Completion

If you're using an AI coding assistant, see **[_AI_INSTRUCTIONS.md](_AI_INSTRUCTIONS.md)** for:

- How AI agents should complete templates
- Metadata extraction from plugin headers
- Error handling and fallbacks
- Example workflows

---

## 💡 Tips & Tricks

### Multiple Projects

Create templates for all your projects:
```
TEMPLATES/
├── client-a-plugin.txt
├── client-b-theme.txt
├── my-plugin.txt
└── staging-site.txt
```

Run any project instantly:
```bash
./dist/bin/run client-a-plugin
./dist/bin/run client-b-theme
```

### CI/CD Integration

Use templates in CI/CD pipelines:
```yaml
# .github/workflows/test.yml
- name: Run WP Code Check
  run: ./dist/bin/run my-plugin --format json
```

### Baseline Workflow

1. Generate baseline for legacy code:
   ```bash
   ./dist/bin/run my-plugin --generate-baseline
   ```

2. Add baseline to template:
   ```bash
   # In my-plugin.txt
   BASELINE=.neochrome-baseline
   ```

3. Future scans only report NEW issues

---

## 📚 Related Documentation

- **[HOWTO-TEMPLATES.md](../HOWTO-TEMPLATES.md)** - Detailed template guide
- **[README.md](../README.md)** - Main documentation
- **[_TEMPLATE.txt](_TEMPLATE.txt)** - Reference template

---

## ❓ Troubleshooting

### Template not found

```bash
Error: Template 'my-plugin' not found
```

**Solution:** Make sure the file exists at `dist/TEMPLATES/my-plugin.txt`

### Path doesn't exist

```bash
Error: Path '/path/to/plugin' does not exist
```

**Solution:** Verify the `PROJECT_PATH` in your template is correct

### Permission denied

```bash
Error: Permission denied
```

**Solution:** Make sure the `run` script is executable:
```bash
chmod +x dist/bin/run
```

---

**Happy scanning!** 🚀

