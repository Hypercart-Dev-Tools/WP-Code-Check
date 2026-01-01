# AI Agent Instructions: IRL File Audit

**Version:** 1.0.0  
**Last Updated:** 2026-01-01

## When to Use This

User says one of:
- "Audit the IRL file I just added"
- "I found issues in plugin X, can you audit it?"
- "Add this file to IRL examples"

## Step-by-Step Audit Process

### Step 1: Verify File Location

Check that file is in correct location:
```
dist/tests/irl/plugin-name/filename-irl.php
```

If not, ask user to:
1. Create folder: `dist/tests/irl/plugin-name/`
2. Copy file with `-irl` suffix: `filename.php` → `filename-irl.php`

### Step 2: Identify Plugin/Theme Metadata

Extract from file header or ask user:
- Plugin/theme name
- Version number
- Original file path
- License (assume GPL if WordPress plugin)

### Step 3: Scan for Anti-Patterns

Run mental checklist against ALL current patterns:

**Security Patterns:**
- [ ] Unsanitized superglobal read (`$_GET/$_POST` without sanitize)
- [ ] Direct superglobal manipulation (assignment to `$_GET`)
- [ ] SQL injection (`$wpdb->query` without `prepare`)
- [ ] Missing nonce checks (admin actions without `wp_verify_nonce`)
- [ ] Missing capability checks (admin functions without `current_user_can`)
- [ ] XSS vulnerabilities (output without `esc_html/esc_attr`)

**Performance Patterns:**
- [ ] N+1 queries (meta queries in loops)
- [ ] WooCommerce N+1 (WC functions in loops)
- [ ] Unbounded queries (`WP_Query` without `posts_per_page`)
- [ ] WCS queries without limits (`wcs_get_subscriptions` without limit)
- [ ] get_users without limit
- [ ] get_terms without limit
- [ ] Unbounded AJAX polling (`setInterval` without limits)
- [ ] Expensive operations in polling intervals

**Best Practices:**
- [ ] Transients without expiration
- [ ] Error suppression (`@` operator)
- [ ] Complex conditionals (4+ conditions)
- [ ] Nested loops

### Step 4: Add File Header Annotation

Add to top of file (after opening `<?php`):

```php
/**
 * IRL AUDIT: [Plugin Name] v[Version]
 * File: [original/path/to/file.php]
 * Audit Date: [YYYY-MM-DD]
 * Scanner Version: [current version]
 * 
 * ANTI-PATTERNS FOUND:
 * 1. [Line XXX] pattern-id (SEVERITY) ✅/❌ Detection status
 * 2. [Line YYY] pattern-id (SEVERITY) ✅/❌ Detection status
 * 
 * SUMMARY:
 * - Total anti-patterns: X
 * - Currently detected: Y/X (Z%)
 * - New patterns needed: N
 */
```

### Step 5: Add Inline Annotations

For EACH anti-pattern found, add comment block BEFORE the line:

```php
// Line XXX
// ANTI-PATTERN: pattern-id
// SEVERITY: HIGH/MEDIUM/LOW/CRITICAL
// DETECTED: ✅ Yes (vX.X.X) OR ❌ No - NEW PATTERN NEEDED
// WHY: [Brief explanation of why this is dangerous]
// FIX: [Corrected code example]
// PATTERN_ID: pattern-id
[original vulnerable code]
```

### Step 6: Update Pattern JSON

For each anti-pattern that IS detected:

1. Open `dist/patterns/pattern-id.json`
2. Add to `irl_examples` array:
```json
{
  "file": "dist/tests/irl/plugin-name/filename-irl.php",
  "line": 123,
  "code": "vulnerable code snippet"
}
```

### Step 7: Create New Pattern (If Needed)

If anti-pattern is NOT currently detected:

1. Create `dist/patterns/new-pattern-id.json` (use existing as template)
2. Set `"enabled": false` (experimental)
3. Document in file header annotation
4. Ask user: "Should I implement detection for this new pattern?"

### Step 8: Verify Scanner Detection

Run scanner against the IRL file:
```bash
./dist/bin/check-performance.sh --paths "dist/tests/irl/plugin-name/filename-irl.php"
```

Verify:
- ✅ Patterns marked as "detected" are actually caught
- ❌ Patterns marked as "not detected" are actually missed

Update annotations if scanner behavior differs from expectation.

### Step 9: Report to User

Provide summary:
```
✅ Audit complete for [filename-irl.php]

FINDINGS:
- 3 anti-patterns found
- 2 currently detected by scanner (67%)
- 1 new pattern discovered: [pattern-name]

ACTIONS TAKEN:
- Added file header annotation
- Added 3 inline annotations
- Updated 2 pattern JSON files with IRL examples
- Created new pattern definition: [pattern-id.json] (disabled)

NEXT STEPS:
- Review annotations in the file
- Decide if new pattern should be implemented
- Consider creating synthetic test fixture from this example
```

## Annotation Style Guide

### DO:
- ✅ Be concise but clear
- ✅ Include line numbers
- ✅ Show corrected code in FIX section
- ✅ Use consistent formatting
- ✅ Mark detection status accurately

### DON'T:
- ❌ Modify the original code (only add comments)
- ❌ Remove existing comments
- ❌ Change indentation
- ❌ Add annotations for non-issues
- ❌ Duplicate annotations

## Example Output

See `dist/tests/irl/woocommerce-all-products-for-subscriptions/class-wcs-att-admin-irl.php` for a complete example.

## Troubleshooting

**Q: File has 1000+ lines, too many anti-patterns?**  
A: Annotate top 5-10 most severe issues. Add note in header: "Partial audit - top issues only"

**Q: Not sure if pattern is already detected?**  
A: Run scanner and check output. Mark as ❓ Unknown if uncertain.

**Q: Pattern is detected but with wrong severity?**  
A: Note in annotation: "DETECTED: ✅ Yes but severity should be X not Y"

**Q: Code is minified/obfuscated?**  
A: Skip audit. IRL examples should be readable code.

