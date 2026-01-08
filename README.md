# WP Code Check by Hypercart

**Fast, zero-dependency WordPress performance analyzer that catches critical issues before they crash your site.**

[![CI](https://github.com/Hypercart-Dev-Tools/WP-Code-Check/actions/workflows/ci.yml/badge.svg)](https://github.com/Hypercart-Dev-Tools/WP-Code-Check/actions)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)

> **Versioning:** See `dist/README.md` for the current released version. The version in the dist README (and the main bash script header) is the canonical source of truth.

---

## Why WP Code Check?

WordPress sites fail in production because of **performance antipatterns** that slip through code review:

- 🔥 **Unbounded queries** (`posts_per_page => -1`) that fetch 50,000 posts and crash the server
- 🐌 **N+1 query patterns** that turn 1 request into 1,000 database calls
- 💥 **Missing capability checks** that let subscribers delete your entire site
- 🔐 **Insecure deserialization** that opens remote code execution vulnerabilities
- 🧲 **Debug code in production** (`var_dump`, `console.log`) that exposes sensitive data

**WP Code Check catches these issues in seconds** — before they reach production.

---

## What Makes It Different?

| Feature | WP Code Check | WPCS | PHPStan-WP |
|---------|---------------|------|------------|
| **Zero dependencies** | ✅ Bash + grep only | ❌ Requires PHP, Composer | ❌ Requires PHP, Composer |
| **Runs anywhere** | ✅ Local, CI/CD, any OS | ⚠️ PHP environment needed | ⚠️ PHP environment needed |
| **WordPress-specific** | ✅ WP performance focus | ⚠️ Generic PHP standards | ⚠️ Type safety focus |
| **Speed** | ✅ Scans 10K files in <5s | ⚠️ Slower on large codebases | ⚠️ Slower on large codebases |
| **Production-tested** | ✅ Real-world patterns | ✅ Industry standard | ✅ Type-focused |

---

## Quick Start

### Installation

```bash
# Clone the repository
git clone https://github.com/Hypercart-Dev-Tools/WP-Code-Check.git
cd WP-Code-Check

# Run against your WordPress plugin/theme
./dist/bin/check-performance.sh --paths /path/to/your/plugin
```

### Example Output

```
━━━ CRITICAL CHECKS (will fail build) ━━━

▸ Unbounded posts_per_page [CRITICAL]
  ✗ FAILED
  ./includes/query-helpers.php:45: 'posts_per_page' => -1

▸ Debug code in production [CRITICAL]
  ✗ FAILED
  ./admin/js/admin.js:293: debugger;

━━━ SUMMARY ━━━
  Errors:   2
  Warnings: 0

✗ Check failed with 2 error(s)
```

---

## Features

### 🔍 **30+ Performance & Security Checks**

- **Critical**: Unbounded queries, insecure deserialization, localStorage sensitive data, client-side serialization, **direct database queries without $wpdb->prepare()**
- **High**: Direct superglobal manipulation, **unsanitized superglobal read**, **admin functions without capability checks**, **WooCommerce N+1 patterns**, AJAX without nonce validation, unbounded SQL, expensive WP functions in polling
- **Medium**: N+1 patterns, transients without expiration, HTTP requests without timeout, unsafe RegExp construction, PHP short tags, **WooCommerce Subscriptions queries without limits**
- **Low**: Timezone-sensitive patterns

See [full check list](dist/README.md#what-it-detects).

### 📊 **Multiple Output Formats**

```bash
# Human-readable text (default)
./dist/bin/check-performance.sh --paths .

# JSON for CI/CD integration
./dist/bin/check-performance.sh --paths . --format json

# Auto-generated HTML reports
# Opens in browser automatically (local development)
```

### 🎯 **Baseline Support**

Manage technical debt in legacy codebases:

```bash
# Generate baseline from current state
./dist/bin/check-performance.sh --paths . --generate-baseline

# Future scans only report NEW issues
./dist/bin/check-performance.sh --paths .
```

### 📝 **Project Templates**

Save scan configurations for frequently-checked projects:

```bash
# Create template
./dist/bin/run my-plugin

# Reuse template
./dist/bin/run my-plugin
```

See [HOWTO-TEMPLATES.md](dist/HOWTO-TEMPLATES.md) for details.

### 🤖 **Phase 2: AI-Assisted Triage (v1.1 POC)**

Validate findings and identify false positives with AI assistance:

```bash
# After running a scan, use AI to triage the results
# AI analyzes the JSON log and provides:
# - Summary stats (reviewed, confirmed, false positives)
# - Overall narrative assessment
# - Recommendations for next steps
```

**Features:**
- ✅ **False Positive Detection** - Identifies common false positives (e.g., `phpcs:ignore` comments, adjacent sanitization)
- ✅ **Confidence Scoring** - Rates overall assessment confidence (high/medium/low)
- ✅ **Actionable Recommendations** - Prioritized list of issues to fix
- ✅ **Executive Summary** - 3-5 paragraph narrative for stakeholders

See [TEMPLATES/_AI_INSTRUCTIONS.md](dist/TEMPLATES/_AI_INSTRUCTIONS.md) for detailed triage workflow.

---

## CI/CD Integration

### GitHub Actions

```yaml
name: WP Code Check
on: [push, pull_request]

jobs:
  performance:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Run WP Code Check
        run: |
          git clone https://github.com/Hypercart-Dev-Tools/WP-Code-Check.git
          ./WP-Code-Check/dist/bin/check-performance.sh --paths . --format json
```

### GitLab CI

```yaml
wp-code-check:
  script:
    - git clone https://github.com/Hypercart-Dev-Tools/WP-Code-Check.git
    - ./WP-Code-Check/dist/bin/check-performance.sh --paths . --format json
```

---

## Documentation

- **[User Guide](dist/README.md)** - Complete command reference and examples (includes canonical version number)
- **[Template Guide](dist/HOWTO-TEMPLATES.md)** - Project template system
- **[Changelog](CHANGELOG.md)** - Version history and development progress
- **[AI Agent Guide](AGENTS.md)** - WordPress development guidelines for AI assistants
- **[Disclosure Policy](DISCLOSURE-POLICY.md)** - Responsible disclosure and public report publication policy

---

## Command Reference

```bash
# Basic scan
./dist/bin/check-performance.sh --paths /path/to/plugin

# JSON output for CI/CD
./dist/bin/check-performance.sh --paths . --format json

# Strict mode (warnings fail the build)
./dist/bin/check-performance.sh --paths . --strict

# Generate baseline for legacy code
./dist/bin/check-performance.sh --paths . --generate-baseline

# Verbose output (show all findings)
./dist/bin/check-performance.sh --paths . --verbose

# Disable logging
./dist/bin/check-performance.sh --paths . --no-log
```

---

## Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

**Note:** Contributors must sign a [Contributor License Agreement (CLA)](CLA.md) before their first pull request can be merged. This is a one-time process that ensures legal clarity for the dual-license model.

---

## 📄 License

WP Code Check is **dual-licensed**:

### Open Source License (Apache 2.0)

The core tool is licensed under the **Apache License 2.0**, which means:

- ✅ **Free for everyone** - Use for personal or commercial projects
- ✅ **Modify and distribute** - Fork, customize, and share
- ✅ **Patent protection** - Includes explicit patent grant
- ✅ **No restrictions** - Use in proprietary software

See [LICENSE](LICENSE) for full terms.

### Commercial License (Optional)

For organizations that need **priority support, advanced features, or SLA guarantees**, we offer commercial licenses:

- 🎯 **Priority Support** - Guaranteed response times, dedicated channels
- 🚀 **Advanced Features** - Custom rules, white-label reports, team collaboration
- 🏢 **Enterprise Features** - SSO, audit logs, on-premise deployment
- 📊 **Service Level Agreements** - Uptime guarantees and compliance support

See [LICENSE-COMMERCIAL.md](LICENSE-COMMERCIAL.md) for details and pricing.

**Contact:** noel@hypercart.io

---

## About

**WP Code Check** is developed by [Hypercart](https://hypercart.com), a DBA of Neochrome, Inc.

- 🌐 Website: [WPCodeCheck.com](https://wpcodecheck.com)
- 📧 Support: noel@hypercart.io
- 🐛 Issues: [GitHub Issues](https://github.com/Hypercart-Dev-Tools/WP-Code-Check/issues)

---

**Made with ❤️ for the WordPress community**

