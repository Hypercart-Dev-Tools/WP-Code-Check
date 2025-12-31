# AI Agent Quick Reference - Running WP Code Check Templates

**For:** Gemini, Cursor, GitHub Copilot, Augment, and other AI coding assistants

---

## 🚨 Common Problem

User says: *"Run the template for my-plugin"*

You try: `./dist/bin/run my-plugin`

**Result:** ❌ Permission denied / Script not found

**Why?** The template points to a path **outside** the WP Code Check directory, and you're using relative paths.

---

## ✅ The Solution (3 Steps)

### Step 1: Ask for WP Code Check Location

```
"Where is WP Code Check installed? (e.g., /Users/noelsaw/Sites/wp-code-check)"
```

### Step 2: Make Scripts Executable

```bash
chmod +x /path/to/wp-code-check/dist/bin/run
chmod +x /path/to/wp-code-check/dist/bin/check-performance.sh
```

### Step 3: Use Absolute Path

```bash
/path/to/wp-code-check/dist/bin/run my-plugin
```

---

## 📋 Complete Example

```bash
# User wants to scan a plugin at: /Users/noelsaw/Sites/my-plugin
# WP Code Check is at: /Users/noelsaw/Tools/wp-code-check
# Template file: /Users/noelsaw/Tools/wp-code-check/dist/TEMPLATES/my-plugin.txt

# Step 1: Set WP Code Check path
WP_CODE_CHECK="/Users/noelsaw/Tools/wp-code-check"

# Step 2: Make executable
chmod +x "$WP_CODE_CHECK/dist/bin/run"

# Step 3: Run template
"$WP_CODE_CHECK/dist/bin/run" my-plugin
```

---

## 🔧 Troubleshooting Checklist

Before running any template:

- [ ] Do you know where WP Code Check is installed?
- [ ] Does the template file exist? (`ls $WP_CODE_CHECK/dist/TEMPLATES/my-plugin.txt`)
- [ ] Is the `run` script executable? (`ls -lh $WP_CODE_CHECK/dist/bin/run`)
- [ ] Are you using an absolute path to the script?

---

## 🎯 Quick Commands

### Find WP Code Check installation:
```bash
find ~ -name "check-performance.sh" -path "*/wp-code-check/dist/bin/*" 2>/dev/null | head -1
```

### List available templates:
```bash
ls -1 /path/to/wp-code-check/dist/TEMPLATES/*.txt | xargs -n1 basename
```

### Make all scripts executable:
```bash
chmod +x /path/to/wp-code-check/dist/bin/*
```

### Test if script works:
```bash
/path/to/wp-code-check/dist/bin/check-performance.sh --help
```

---

## ❌ Common Mistakes

### Mistake 1: Using Relative Paths
```bash
# ❌ DON'T
./dist/bin/run my-plugin

# ✅ DO
/full/path/to/wp-code-check/dist/bin/run my-plugin
```

### Mistake 2: Assuming Current Directory
```bash
# ❌ DON'T assume WP Code Check is in current directory
cd /Users/noelsaw/Sites/my-plugin
./dist/bin/run my-plugin  # This won't work!

# ✅ DO use absolute path
/Users/noelsaw/Tools/wp-code-check/dist/bin/run my-plugin
```

### Mistake 3: Ignoring Permissions
```bash
# ❌ DON'T just run without checking
/path/to/run my-plugin

# ✅ DO check and fix permissions first
chmod +x /path/to/run
/path/to/run my-plugin
```

---

## 🤖 AI Agent Template

Copy this workflow for running templates:

```bash
#!/bin/bash
# AI Agent Workflow for Running WP Code Check Templates

# Configuration
TEMPLATE_NAME="$1"  # e.g., "my-plugin"
WP_CODE_CHECK="${WP_CODE_CHECK:-/path/to/wp-code-check}"  # Ask user if not set

# Validation
if [ -z "$TEMPLATE_NAME" ]; then
  echo "❌ Error: Please specify a template name"
  echo "Usage: run-template <template-name>"
  exit 1
fi

if [ ! -d "$WP_CODE_CHECK" ]; then
  echo "❌ Error: WP Code Check not found at: $WP_CODE_CHECK"
  echo "Please set WP_CODE_CHECK environment variable or provide the path"
  exit 1
fi

# Check template exists
TEMPLATE_FILE="$WP_CODE_CHECK/dist/TEMPLATES/${TEMPLATE_NAME}.txt"
if [ ! -f "$TEMPLATE_FILE" ]; then
  echo "❌ Error: Template not found: $TEMPLATE_FILE"
  echo ""
  echo "Available templates:"
  ls -1 "$WP_CODE_CHECK/dist/TEMPLATES/"*.txt 2>/dev/null | xargs -n1 basename | sed 's/\.txt$//'
  exit 1
fi

# Make executable
chmod +x "$WP_CODE_CHECK/dist/bin/run" 2>/dev/null
chmod +x "$WP_CODE_CHECK/dist/bin/check-performance.sh" 2>/dev/null

# Run
echo "🚀 Running WP Code Check template: $TEMPLATE_NAME"
"$WP_CODE_CHECK/dist/bin/run" "$TEMPLATE_NAME"
```

---

## 📚 Full Documentation

For complete details, see:
- **[_AI_INSTRUCTIONS.md](_AI_INSTRUCTIONS.md)** - Complete AI agent guide
- **[README.md](README.md)** - User documentation

---

## 💡 Pro Tips

1. **Always ask the user** where WP Code Check is installed
2. **Verify paths exist** before running commands
3. **Check permissions** before executing scripts
4. **Use absolute paths** for everything
5. **Provide helpful error messages** when things fail

---

**Remember:** WP Code Check can be installed anywhere, and templates can point to paths anywhere. Never assume relative paths will work!

