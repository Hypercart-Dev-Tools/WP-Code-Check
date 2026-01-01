# Spec: Disallowed PHP Short Tags Check

**Author**: GitHub Copilot
**Date**: 2025-12-31
**Status**: Proposed

## 1. Feature Summary

This document specifies a new check for the `check-performance.sh` script to detect and flag the use of PHP short tags (`<?` and `<?=`). This aligns with the official WordPress Coding Standards, which mandate the use of full `<?php ... ?>` tags for maximum server compatibility.

## 2. Rationale & Justification

The [WordPress Coding Standards state](https://developer.wordpress.org/coding-standards/wordpress-coding-standards/php/#no-shorthand-php-tags):

> **Important**: Never use shorthand PHP start tags. Always use full PHP tags.

- **Compatibility**: The `short_open_tag` setting in `php.ini` is not guaranteed to be enabled on all hosting environments. Code using short tags will fail to parse on servers where it is disabled.
- **Clarity**: Full PHP tags are explicit and leave no ambiguity.
- **WPCS Compliance**: This check helps teams adhere to WordPress community best practices automatically.

## 3. Technical Specification

### 3.1. Rule Definition

- **Rule ID**: `disallowed-php-short-tags`
- **Severity**: `MEDIUM` (by default, customizable via `severity-levels.json`)
- **Category**: `compatibility`
- **Description**: "PHP short tags are used. The WordPress Coding Standards require full `<?php` tags for compatibility."

### 3.2. Detection Logic

The check will be implemented within the `check-performance.sh` script. It will use `grep` to identify files containing disallowed short tags.

**Patterns to detect:**

1.  **Short echo tag**: `<?=`
2.  **Short open tag**: `<?` followed by a space, tab, or newline. This avoids false positives with `<?xml`.

**Grep Implementation:**

```bash
# The pattern will look for `<?=` or `<?` followed by whitespace.
# The `-P` flag enables Perl-compatible regular expressions (PCRE) for lookarounds.
# We must exclude `<?php` and `<?xml`.

PATTERN="<?(?!php|xml|=)"
grep -rEhn "$PATTERN" --include="*.php" $PATHS
```
A simpler grep without lookbehind might be more portable if `-P` is not guaranteed.

**Alternative Grep (more portable):**
```bash
# Find all `<?` tags, then filter out the valid ones.
grep -rhn "<? " --include="*.php" $PATHS | grep -v "<?php" | grep -v "<?xml"
grep -rhn "<?=" --include="*.php" $PATHS
```

### 3.3. Reporting

- **Text Report**: Findings will be listed under a "MEDIUM" severity section, clearly indicating the file, line number, and the violating code.
- **JSON Report**: A finding will be added to the `findings` array with the `disallowed-php-short-tags` rule ID.
- **HTML Report**: The finding will be displayed with its severity and a link to the relevant line of code.

### 3.4. Configuration

The check will be added to the default severity configuration file.

**Entry for `/dist/config/severity-levels.json`:**

```json
"disallowed-php-short-tags": {
  "id": "disallowed-php-short-tags",
  "level": "MEDIUM",
  "factory_default": "MEDIUM",
  "category": "compatibility",
  "description": "PHP short tags are used. The WordPress Coding Standards require full `<?php` tags."
}
```

## 4. Implementation Plan

1.  **Add to `check-performance.sh`**: Implement the `grep` logic as a new check function within the script.
2.  **Update Config**: Add the new rule definition to `/dist/config/severity-levels.json`.
3.  **Add Test Fixture**: Create a new test file in `dist/tests/fixtures/` containing examples of short tags to ensure they are correctly detected.
4.  **Update Documentation**: Add the new check to the `README.md` list of available checks.

## 5. Example Finding

**Text Output:**
```
━━━ MEDIUM CHECKS ━━━

▸ Disallowed PHP short tags [MEDIUM]
  ✗ FAILED
  ./template-parts/header.php:15: <?= get_bloginfo('name') ?>
  ./includes/legacy-widget.php:42: <? echo 'This is not allowed'; ?>
```