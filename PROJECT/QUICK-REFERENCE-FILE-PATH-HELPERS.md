# Quick Reference: File Path Helper Functions

**Location:** `dist/bin/lib/common-helpers.sh`  
**Version:** 1.0.77+  
**Last Updated:** 2026-01-02

---

## Overview

Centralized helper functions for handling file paths with spaces, special characters, and Unicode. Solves issues with:
- ✅ File iteration loops breaking on spaces
- ✅ Inconsistent URL encoding for `file://` links
- ✅ Duplicated HTML escaping logic
- ✅ Hard-to-maintain inline code

---

## Helper Functions

### 1. `safe_file_iterator()`

**Purpose:** Safely iterate over newline-separated file paths (handles spaces)

**Usage:**
```bash
FILES=$(grep -rln --include="*.php" "pattern" "$PATHS" 2>/dev/null || true)
safe_file_iterator "$FILES" | while IFS= read -r file; do
  echo "Processing: $file"
done
```

**Why:** Prevents `for file in $FILES` from splitting on spaces

**Example:**
```bash
# ❌ BROKEN (splits on spaces):
for file in $FILES; do
  # "/Users/noelsaw/Local Sites/..." becomes:
  # Token 1: /Users/noelsaw/Local
  # Token 2: Sites/...
done

# ✅ FIXED (preserves spaces):
safe_file_iterator "$FILES" | while IFS= read -r file; do
  # "/Users/noelsaw/Local Sites/..." stays intact
done
```

---

### 2. `url_encode_path()`

**Purpose:** URL-encode a file path for `file://` links (RFC 3986)

**Usage:**
```bash
encoded_path=$(url_encode_path "/path/with spaces/file.php")
# Returns: /path/with%20spaces/file.php
```

**Why:** Ensures `file://` links work in browsers

**Example:**
```bash
# ❌ BROKEN (spaces break links):
link="<a href=\"file://$path\">Link</a>"

# ✅ FIXED (spaces encoded):
encoded=$(url_encode_path "$path")
link="<a href=\"file://$encoded\">Link</a>"
```

---

### 3. `html_escape_string()`

**Purpose:** HTML-escape a string for safe display in HTML

**Usage:**
```bash
escaped_text=$(html_escape_string "Code with <tags> & \"quotes\"")
# Returns: Code with &lt;tags&gt; &amp; &quot;quotes&quot;
```

**Why:** Prevents HTML injection and broken markup

**Example:**
```bash
# ❌ BROKEN (breaks HTML):
echo "<div>$text</div>"

# ✅ FIXED (safe HTML):
escaped=$(html_escape_string "$text")
echo "<div>$escaped</div>"
```

---

### 4. `create_file_link()`

**Purpose:** Create a clickable `file://` link for HTML reports

**Usage:**
```bash
link=$(create_file_link "/path/to/file.php" "Optional Display Text")
# Returns: <a href="file:///path/to/file.php">Optional Display Text</a>
```

**Why:** Combines URL encoding + HTML escaping in one call

**Example:**
```bash
# ❌ BEFORE (complex, duplicated):
encoded=$(printf '%s' "$path" | jq -sRr @uri)
escaped=$(echo "$path" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g')
link="<a href=\"file://$encoded\">$escaped</a>"

# ✅ AFTER (simple, consistent):
link=$(create_file_link "$path")
```

---

### 5. `create_directory_link()`

**Purpose:** Create a clickable directory link for HTML reports

**Usage:**
```bash
link=$(create_directory_link "/path/to/directory" "Optional Display Text")
# Returns: <a href="file:///path/to/directory">Optional Display Text</a>
```

**Why:** Same as `create_file_link()` but with directory-specific styling

**Example:**
```bash
# ❌ BEFORE (complex, duplicated):
encoded=$(printf '%s' "$dir" | jq -sRr @uri)
escaped=$(echo "$dir" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g')
link="<a href=\"file://$encoded\" style=\"...\">$escaped</a>"

# ✅ AFTER (simple, consistent):
link=$(create_directory_link "$dir")
```

---

### 6. `validate_file_path()`

**Purpose:** Validate that a file path exists and is readable

**Usage:**
```bash
if validate_file_path "$file"; then
  echo "Valid file: $file"
else
  echo "Invalid file: $file"
fi
```

**Why:** Centralized validation logic with clear return codes

**Example:**
```bash
# ❌ BEFORE (scattered validation):
if [ -f "$file" ] && [ -r "$file" ]; then
  # ... processing
fi

# ✅ AFTER (centralized validation):
if validate_file_path "$file"; then
  # ... processing
fi
```

---

## Common Patterns

### Pattern 1: File Iteration with grep

```bash
# Find files matching pattern
FILES=$(grep -rln $EXCLUDE_ARGS --include="*.php" -e "pattern" "$PATHS" 2>/dev/null || true)

# Iterate safely (handles spaces)
if [ -n "$FILES" ]; then
  safe_file_iterator "$FILES" | while IFS= read -r file; do
    # Process file
    echo "Processing: $file"
  done
fi
```

**Used in:**
- Line 2374: AJAX handlers
- Line 2577: get_terms()
- Line 2618: pre_get_posts
- Line 2720: Cron interval

---

### Pattern 2: HTML Report Links

```bash
# Create clickable file link
file_link=$(create_file_link "$file_path" "$display_text")
echo "<div>File: $file_link</div>"

# Create clickable directory link
dir_link=$(create_directory_link "$dir_path" "$display_text")
echo "<div>Directory: $dir_link</div>"
```

**Used in:**
- Line 783-784: Paths link
- Line 789-791: JSON log link
- Line 875: Finding file path

---

### Pattern 3: Manual Encoding/Escaping

```bash
# URL encode a path
encoded=$(url_encode_path "$path")

# HTML escape text
escaped=$(html_escape_string "$text")

# Use in HTML
echo "<a href=\"file://$encoded\">$escaped</a>"
```

**Used in:**
- Line 779: Path encoding
- Line 783: Path escaping
- Line 789: Log path encoding
- Line 790: Log path escaping

---

## Migration Guide

### Step 1: Replace File Iteration Loops

**Before:**
```bash
for file in $FILES; do
  # ... processing
done
```

**After:**
```bash
safe_file_iterator "$FILES" | while IFS= read -r file; do
  # ... processing
done
```

---

### Step 2: Replace URL Encoding

**Before:**
```bash
encoded=$(printf '%s' "$path" | jq -sRr @uri)
```

**After:**
```bash
encoded=$(url_encode_path "$path")
```

---

### Step 3: Replace HTML Escaping

**Before:**
```bash
escaped=$(echo "$text" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g')
```

**After:**
```bash
escaped=$(html_escape_string "$text")
```

---

### Step 4: Replace Link Creation

**Before:**
```bash
encoded=$(printf '%s' "$path" | jq -sRr @uri)
escaped=$(echo "$path" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g')
link="<a href=\"file://$encoded\">$escaped</a>"
```

**After:**
```bash
link=$(create_file_link "$path")
```

---

## Testing

### Test with Spaces

```bash
mkdir -p "/tmp/test path with spaces"
cat > "/tmp/test path with spaces/test.php" << 'EOF'
<?php
$terms = get_terms('category');
EOF

./bin/check-performance.sh --paths "/tmp/test path with spaces" --format json
```

**Expected:** Line numbers accurate, links work

---

### Test with Special Characters

```bash
mkdir -p "/tmp/test&path<with>special\"chars"
cat > "/tmp/test&path<with>special\"chars/test.php" << 'EOF'
<?php
$terms = get_terms('category');
EOF

./bin/check-performance.sh --paths "/tmp/test&path<with>special\"chars" --format json
```

**Expected:** HTML not broken, links work

---

## Troubleshooting

### Issue: "command not found: safe_file_iterator"

**Cause:** `common-helpers.sh` not sourced

**Fix:** Add to script:
```bash
source "$LIB_DIR/common-helpers.sh"
```

---

### Issue: Links don't work in browser

**Cause:** Path not URL-encoded

**Fix:** Use `url_encode_path()` or `create_file_link()`

---

### Issue: HTML markup broken

**Cause:** Special characters not escaped

**Fix:** Use `html_escape_string()` or `create_file_link()`

---

**Quick Reference Created:** 2026-01-02  
**For Full Implementation Guide:** See `IMPLEMENTATION-FILE-PATH-HELPERS.md`

