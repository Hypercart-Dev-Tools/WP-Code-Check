# WP Code Check by Hypercart - Performance & Security Analyzer

**Version:** 1.0.60
© Copyright 2025 Hypercart (a DBA of Neochrome, Inc.)

---

## 🎯 For Developers: Why This Matters

### The Problem

You're building a WordPress plugin or theme. Everything works great in development. Then production hits:

- 💥 **Site crashes** under load because someone used `posts_per_page => -1`
- 🐌 **Admin dashboard freezes** from N+1 queries in a loop
- 🔥 **Server melts down** from unbounded AJAX polling every 100ms
- 💸 **Database explodes** from REST endpoints with no pagination
- 🕳️ **Security holes** from AJAX handlers missing nonce validation
- ⏱️ **Entire site hangs** from `file_get_contents()` on an unresponsive API

**These aren't edge cases. They're production killers that slip through code review every day.**

### The Solution

This toolkit **automatically detects 28 critical WordPress performance and security antipatterns** before they reach production.

**Think of it as:**
- 🛡️ **ESLint/PHPStan for WordPress performance** - catches issues static analysis misses
- 🔍 **Automated code review** - finds patterns that crash sites under load
- 🚨 **Pre-deployment safety net** - fails CI/CD before bad code ships
- 📊 **Technical debt tracker** - baseline existing issues, prevent new ones

### What Makes This Different

**WordPress-specific intelligence:**
- Understands `WP_Query`, `get_posts()`, `wp_ajax_*`, `register_rest_route()`, WooCommerce patterns
- Knows the difference between safe and dangerous WordPress APIs
- Catches issues that generic linters can't see

**Zero dependencies:**
- Pure bash + grep - runs anywhere (local, CI/CD, Docker, GitHub Actions)
- No PHP extensions, no Composer dependencies, no Node.js required
- Works on macOS, Linux, Windows (WSL)

**Production-tested:**
- Detects real issues that have crashed real WordPress sites
- Used in CI/CD pipelines processing millions of requests/day
- Battle-tested patterns from 10+ years of WordPress performance consulting

---

## 🚀 Quick Start: Run From Anywhere

**Key Feature:** You don't need to copy this tool into every project. Keep it in one location and point it at any codebase.

### Installation (One-Time Setup)

```bash
# Clone to a central location (anywhere on your machine)
git clone https://github.com/Hypercart-Dev-Tools/WP-Code-Check.git ~/dev/wp-analyzer

# Or download and extract to any directory
cd ~/dev/wp-analyzer
```

### Usage: Analyze Any Project

```bash
# Analyze any WordPress project from anywhere
~/dev/wp-analyzer/dist/bin/check-performance.sh --paths /path/to/your/plugin

# Examples:
~/dev/wp-analyzer/dist/bin/check-performance.sh --paths ~/Sites/my-plugin
~/dev/wp-analyzer/dist/bin/check-performance.sh --paths /var/www/client-site/wp-content/themes/custom
~/dev/wp-analyzer/dist/bin/check-performance.sh --paths ~/projects/woocommerce-extension

# Analyze multiple projects at once
~/dev/wp-analyzer/dist/bin/check-performance.sh --paths "~/plugin1 ~/plugin2 ~/theme"

# Analyze current directory
cd ~/Sites/my-plugin
~/dev/wp-analyzer/dist/bin/check-performance.sh --paths .
```

### Pro Tip: Create an Alias

Add to your `~/.bashrc` or `~/.zshrc`:

```bash
# One-line analyzer - use from anywhere
alias wp-analyze='~/dev/wp-analyzer/dist/bin/check-performance.sh --paths'

# Then use it anywhere:
wp-analyze ~/Sites/my-plugin
wp-analyze .
wp-analyze ~/client-work/custom-theme --strict
wp-analyze ~/projects/plugin --format json > report.json
```

### Alternative: Per-Project Installation

If you prefer to include it in each project (e.g., for CI/CD):

```bash
# Add as Composer dev dependency
composer require --dev neochrome/wp-toolkit

# Or copy dist/ folder into your project
cp -r ~/dev/wp-analyzer/dist ./vendor/neochrome/

# Then run from project root
./dist/bin/check-performance.sh --paths .
```

---

## 💡 What It Detects

### 🚨 Critical Errors (Build Fails)

These patterns **will crash your site** under production load:

| Pattern | Why It's Dangerous | Real-World Impact |
|---------|-------------------|-------------------|
| **AJAX polling** via `setInterval` + fetch/ajax | Creates request storms that hammer backend | 1000 users = 60,000 requests/min → server meltdown |
| **`register_rest_route`** without pagination | Unbounded REST data fetch | API returns 50,000 posts → 500MB response → timeout |
| **`wp_ajax_*`** handlers missing nonce | Unlimited AJAX flood, no CSRF protection | Bots flood endpoint → database locks → site down |
| **`posts_per_page => -1`** | Loads ALL posts into memory | 10,000 posts × 2KB = 20MB per request → OOM crash |
| **`numberposts => -1`** | Same as above for `get_posts()` | Memory exhaustion on high-traffic pages |
| **`nopaging => true`** | Disables all pagination limits | Silent killer - bypasses safety checks |
| **`wc_get_orders(['limit' => -1])`** | WooCommerce unbounded query | 50,000 orders → 100MB+ → PHP fatal error |
| **`get_terms()`** without `number` | Loads entire taxonomy into memory | 100,000 tags → memory exhaustion |
| **`pre_get_posts`** forcing unbounded | Modifies queries globally | Breaks pagination site-wide |
| **Unbounded SQL** on `wp_terms` | Full table scans without limits | Locks database on large sites |
| **`file_get_contents()`** with URLs | No timeout, no SSL verification, blocks PHP | External API down → entire site hangs for 30+ seconds |

### ⚠️ Warnings (Review Recommended)

These patterns **degrade performance** and should be fixed:

| Pattern | Why It Matters | Impact |
|---------|---------------|--------|
| **`ORDER BY RAND()`** | Full table scan on every query | 100,000 rows → 2-5 second queries |
| **`set_transient()`** without expiration | Stale data accumulates forever | Database bloat, cache pollution |
| **N+1 patterns** (meta in loops) | Query multiplication | 100 posts × 3 meta queries = 300 queries per page |
| **`current_time('timestamp')`** | Deprecated, timezone issues | Use `current_datetime()` instead |
| **HTTP requests** without timeout | External API hangs → site hangs | 5-30 second page loads if API is slow |

---

## 📊 Command Reference

### Basic Usage

```bash
# Analyze current directory
wp-analyze .

# Analyze specific project
wp-analyze ~/Sites/my-plugin

# Analyze multiple paths
wp-analyze "~/plugin ~/theme ~/custom-code"

# Verbose output (show all matches, not just first)
wp-analyze ~/Sites/my-plugin --verbose

# Strict mode (fail on warnings too - for CI/CD)
wp-analyze ~/Sites/my-plugin --strict

# JSON output (for tooling/CI)
wp-analyze ~/Sites/my-plugin --format json

# Disable log file
wp-analyze ~/Sites/my-plugin --no-log

# Custom context lines (default: 3)
wp-analyze ~/Sites/my-plugin --context-lines 5

# No context (just show the line)
wp-analyze ~/Sites/my-plugin --no-context
```

### Advanced: Baseline Management

**Baseline files** let you "grandfather in" existing issues while preventing new ones:

```bash
# Generate baseline from current state
wp-analyze ~/Sites/my-plugin --format json --generate-baseline

# This creates .hcc-baseline in the scanned directory
# Commit this file to version control

# Future runs will only fail on NEW or INCREASED issues
wp-analyze ~/Sites/my-plugin --format json

# Ignore baseline temporarily (see all issues)
wp-analyze ~/Sites/my-plugin --format json --ignore-baseline

# Use custom baseline file
wp-analyze ~/Sites/my-plugin --format json --baseline /path/to/custom-baseline
```

**Use case:** Legacy codebase with 50 existing issues. Generate baseline, commit it. Now CI only fails on new issues while you fix old ones incrementally.

### Testing Baseline Functionality

Validate that baseline features work correctly on any project:

```bash
# Test baseline with default project (Save Cart Later)
./dist/tests/test-baseline-functionality.sh

# Test baseline with any template
./dist/tests/test-baseline-functionality.sh --project shoptimizer

# Test baseline with custom path
./dist/tests/test-baseline-functionality.sh --paths /path/to/your/plugin
```

**What it tests:**
- ✅ **Baseline generation**: Creates `.hcc-baseline` file correctly
- ✅ **Issue suppression**: Baselined issues don't cause failures
- ✅ **New issue detection**: Issues above baseline are caught
- ✅ **Stale baseline detection**: Reduced issues are flagged
- ✅ **Ignore flag**: `--ignore-baseline` works correctly

**Output:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Neochrome WP Toolkit - Baseline Functionality Test
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

▸ Test: Baseline Generation
  ✓ PASSED: Baseline file created with 7 entries

▸ Test: Baseline Suppression
  ✓ PASSED: Baseline suppressed 7 findings
  ✓ PASSED: All issues successfully suppressed

▸ Test: New Issue Detection
  ✓ PASSED: Detected new issue above baseline

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Test Summary
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Tests Run:    10
  Passed:       10
  Failed:       0

✓ All baseline tests passed!
```

**Use cases:**
- **Development**: Validate baseline works before committing changes
- **CI/CD**: Add to test suite for regression protection
- **Troubleshooting**: Diagnose baseline issues on user projects
- **Documentation**: Show users how baseline should behave

---

## 🔧 CI/CD Integration

### GitHub Actions

**Option 1: Standalone analyzer (recommended)**

```yaml
# .github/workflows/performance-audit.yml
name: Performance Audit

on: [push, pull_request]

jobs:
  audit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Clone analyzer
        run: git clone https://github.com/Hypercart-Dev-Tools/WP-Code-Check.git /tmp/analyzer

      - name: Run audit
        run: /tmp/analyzer/dist/bin/check-performance.sh --paths . --strict --format json
```

**Option 2: Include in project**

```yaml
# .github/workflows/performance-audit.yml
name: Performance Audit

on: [push, pull_request]

jobs:
  audit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Run audit
        run: ./dist/bin/check-performance.sh --paths . --strict
```

### GitLab CI

```yaml
# .gitlab-ci.yml
performance-audit:
  stage: test
  script:
    - git clone https://github.com/Hypercart-Dev-Tools/WP-Code-Check.git /tmp/analyzer
    - /tmp/analyzer/dist/bin/check-performance.sh --paths . --strict
  only:
    - merge_requests
    - main
```

### Composer Integration (Optional)

If you prefer Composer-based workflows, add to your `composer.json`:

```json
{
  "scripts": {
    "audit": "./dist/bin/check-performance.sh --paths .",
    "audit:strict": "./dist/bin/check-performance.sh --paths . --strict",
    "audit:verbose": "./dist/bin/check-performance.sh --paths . --verbose",
    "ci": "@audit:strict"
  }
}
```

Then use:
```bash
composer audit
composer audit:strict
composer ci
```

---

## 📈 Understanding Results

### Exit Codes

| Code | Meaning | When It Happens |
|------|---------|-----------------|
| `0` | ✅ All checks passed | No errors found (warnings OK in normal mode) |
| `1` | ❌ Issues found | Errors found, OR warnings found in `--strict` mode |

### Output Formats

**Text (default)** - Human-readable, colored output:
```bash
wp-analyze ~/Sites/my-plugin
```

**JSON** - Machine-readable for CI/tooling:
```bash
wp-analyze ~/Sites/my-plugin --format json > results.json
```

JSON structure:
```json
{
  "version": "1.0.46",
  "timestamp": "2025-12-29T10:30:00Z",
  "paths_scanned": ["~/Sites/my-plugin"],
  "strict_mode": false,
  "summary": {
    "total_errors": 2,
    "total_warnings": 1,
    "baselined": 0,
    "stale_baseline": 0,
    "exit_code": 1
  },
  "findings": [
    {
      "id": "unbounded-posts-per-page",
      "severity": "error",
      "impact": "CRITICAL",
      "file": "./includes/query.php",
      "line": 42,
      "code": "'posts_per_page' => -1,",
      "message": "Unbounded posts_per_page can cause memory exhaustion"
    }
  ],
  "checks": [
    {
      "id": "unbounded-posts-per-page",
      "name": "Unbounded posts_per_page",
      "status": "failed",
      "severity": "error",
      "impact": "CRITICAL",
      "finding_count": 2
    }
  ]
}
```

---

## 🛠️ Suppressing False Positives

Sometimes a pattern is intentional (e.g., admin-only query, cached result). Suppress with `phpcs:ignore`:

```php
// Suppress specific check
// phpcs:ignore WordPress.WP.PostsPerPage.posts_per_page_posts_per_page
$posts = get_posts( array( 'posts_per_page' => -1 ) );

// Suppress with explanation (recommended)
// phpcs:ignore WordPress.DateTime.CurrentTimeTimestamp.Requested -- Intentional for display formatting
$timestamp = current_time( 'timestamp' );

// Suppress entire line (any check)
// phpcs:ignore
$data = file_get_contents( 'https://api.example.com/data' );
```

**Best practice:** Always add `-- Explanation` to document WHY it's safe.

---

## 📦 What's Included

### Core Tools

| File | Purpose |
|------|---------|
| `bin/check-performance.sh` | Main analyzer - detects 28 antipatterns |
| `tests/fixtures/*.php` | Test fixtures (antipatterns + clean code) |
| `tests/run-fixture-tests.sh` | Validation test suite (9 tests) |

### Integration Tools

| File | Purpose |
|------|---------|
| `bin/post-to-slack.sh` | Post results to Slack webhook |
| `bin/format-slack-message.sh` | Format JSON as Slack Block Kit |
| `bin/test-slack-integration.sh` | Test Slack integration |
| `setup-integration-security.sh` | Setup credential protection |

See [PROJECT/DETAILS/INTEGRATIONS.md](../PROJECT/DETAILS/INTEGRATIONS.md) for integration guides.

---

## 🔔 Slack/Discord Notifications

Get real-time alerts when performance checks fail in CI:

```bash
# 1. Setup credential protection (prevents accidental commits)
./setup-integration-security.sh

# 2. Test integration (no credentials needed)
./dist/bin/test-slack-integration.sh

# 3. Configure webhook
cp .env.example .env
nano .env  # Add SLACK_WEBHOOK_URL

# 4. Test with real webhook
export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/WEBHOOK"
./dist/bin/test-slack-integration.sh

# 5. Use in CI/CD
./dist/bin/check-performance.sh --format json > results.json
./dist/bin/post-to-slack.sh results.json
```

**GitHub Actions example:**
```yaml
- name: Notify Slack on failure
  if: failure()
  env:
    SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK_URL }}
  run: |
    ./dist/bin/check-performance.sh --format json > results.json
    ./dist/bin/post-to-slack.sh results.json
```

---

## 📝 Logging

Logs are written to `dist/logs/` by default:
- **Format:** `YYYY-MM-DD-HHMMSS-UTC.log`
- **Disable:** Use `--no-log` flag
- **Location:** Relative to script location (not scanned directory)

Add to `.gitignore`:
```bash
echo "dist/logs/" >> .gitignore
```

---

## 🤖 For AI Assistants

**Recommended workflow:**

1. **Run audit:**
   ```bash
   ./dist/bin/check-performance.sh --paths "." --verbose
   ```

2. **If errors found:** Fix them before proceeding (these will crash production)

3. **If warnings found:** Evaluate if intentional or need fixing

4. **Document findings:** Create audit report in `AUDITS/` folder

5. **Generate baseline** (if legacy codebase):
   ```bash
   ./dist/bin/check-performance.sh --paths "." --format json --generate-baseline
   ```

---

## 🔗 Links & Support

- **Repository:** https://github.com/Hypercart-Dev-Tools/WP-Code-Check
- **Issues:** https://github.com/Hypercart-Dev-Tools/WP-Code-Check/issues
- **Documentation:** See `PROJECT/` directory for detailed guides
- **Contact:** noel@hypercart.io

---

## 📄 License

© Copyright 2025 Neochrome, Inc. All rights reserved.
