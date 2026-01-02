# Severity Override System - Practical Examples

**Date:** 2026-01-01  
**Version:** 1.0.69

---

## 🎯 Use Case 1: Legacy Codebase

**Scenario:** You have a legacy WordPress plugin with 50+ SQL injection risks. You want to track new issues without being overwhelmed by existing ones.

### Step 1: Run Initial Scan
```bash
./dist/bin/check-performance.sh --paths "wp-content/plugins/my-legacy-plugin"
```

**Result:** 50 CRITICAL errors for `wpdb-query-no-prepare`

### Step 2: Create Custom Severity Config
**File:** `my-legacy-severity.json`
```json
{
  "_metadata": {
    "project": "Legacy Plugin Cleanup",
    "created": "2026-01-01",
    "reason": "Downgrade existing issues while we fix them incrementally"
  },
  "severity_levels": {
    "wpdb-query-no-prepare": {
      "level": "MEDIUM",
      "_reason": "50 existing violations - fixing incrementally",
      "_ticket": "JIRA-1234",
      "_target_date": "2026-06-01"
    }
  }
}
```

### Step 3: Run with Custom Config
```bash
./dist/bin/check-performance.sh \
  --paths "wp-content/plugins/my-legacy-plugin" \
  --severity-config my-legacy-severity.json
```

**Result:** 50 MEDIUM warnings (won't fail build)

### Step 4: Generate Baseline
```bash
./dist/bin/check-performance.sh \
  --paths "wp-content/plugins/my-legacy-plugin" \
  --severity-config my-legacy-severity.json \
  --generate-baseline
```

**Result:** `.hcc-baseline` file created - future scans only show NEW issues

---

## 🎯 Use Case 2: Strict Security Project

**Scenario:** You're building a payment gateway plugin. Security is paramount - you want ALL security issues to fail the build.

### Custom Severity Config
**File:** `payment-gateway-severity.json`
```json
{
  "_metadata": {
    "project": "Payment Gateway Plugin",
    "security_level": "MAXIMUM",
    "reason": "PCI compliance required - zero tolerance for security issues"
  },
  "severity_levels": {
    "unsanitized-superglobal-read": {
      "level": "CRITICAL",
      "_reason": "Upgraded from HIGH - handles payment data"
    },
    "wpdb-query-no-prepare": {
      "level": "CRITICAL",
      "_reason": "Already CRITICAL - no changes"
    },
    "transient-no-expiration": {
      "level": "HIGH",
      "_reason": "Upgraded from MEDIUM - could leak payment data"
    },
    "n-plus-one-pattern": {
      "level": "CRITICAL",
      "_reason": "Upgraded from MEDIUM - performance critical for checkout"
    }
  }
}
```

### Run with Strict Mode
```bash
./dist/bin/check-performance.sh \
  --paths "wp-content/plugins/payment-gateway" \
  --severity-config payment-gateway-severity.json \
  --strict
```

**Result:** Build fails on ANY CRITICAL or HIGH issue

---

## 🎯 Use Case 3: Performance-Focused Project

**Scenario:** You're optimizing a high-traffic WooCommerce site. Performance issues are more critical than minor security issues.

### Custom Severity Config
**File:** `performance-priority-severity.json`
```json
{
  "_metadata": {
    "project": "High-Traffic WooCommerce Site",
    "focus": "Performance optimization",
    "traffic": "1M+ visitors/month"
  },
  "severity_levels": {
    "get-users-no-limit": {
      "level": "CRITICAL",
      "_reason": "Site has 50k+ users - unbounded queries crash site"
    },
    "unbounded-posts-per-page": {
      "level": "CRITICAL",
      "_reason": "100k+ products - unbounded queries timeout"
    },
    "n-plus-one-pattern": {
      "level": "CRITICAL",
      "_reason": "Upgraded from MEDIUM - causes 5+ second page loads"
    },
    "wc-n-plus-one-pattern": {
      "level": "CRITICAL",
      "_reason": "Upgraded from HIGH - checkout page critical"
    },
    "ajax-polling-unbounded": {
      "level": "CRITICAL",
      "_reason": "Upgraded from HIGH - kills server with 1000+ concurrent users"
    },
    "unsanitized-superglobal-read": {
      "level": "MEDIUM",
      "_reason": "Downgraded from HIGH - admin-only code, low risk"
    }
  }
}
```

---

## 🎯 Use Case 4: Multi-Environment Strategy

**Scenario:** Different severity levels for dev, staging, and production.

### Development Environment
**File:** `severity-dev.json`
```json
{
  "_metadata": {
    "environment": "development",
    "strictness": "low"
  },
  "severity_levels": {
    "n-plus-one-pattern": {
      "level": "LOW",
      "_reason": "Just warnings in dev - don't block development"
    },
    "transient-no-expiration": {
      "level": "LOW"
    }
  }
}
```

### Staging Environment
**File:** `severity-staging.json`
```json
{
  "_metadata": {
    "environment": "staging",
    "strictness": "medium"
  },
  "severity_levels": {
    "n-plus-one-pattern": {
      "level": "MEDIUM",
      "_reason": "Warnings in staging - review before production"
    },
    "wpdb-query-no-prepare": {
      "level": "CRITICAL",
      "_reason": "Block SQL injection before production"
    }
  }
}
```

### Production Environment
**File:** `severity-production.json`
```json
{
  "_metadata": {
    "environment": "production",
    "strictness": "maximum"
  },
  "severity_levels": {
    "n-plus-one-pattern": {
      "level": "CRITICAL",
      "_reason": "Block all performance issues in production"
    },
    "wpdb-query-no-prepare": {
      "level": "CRITICAL"
    },
    "get-users-no-limit": {
      "level": "CRITICAL"
    }
  }
}
```

### CI/CD Pipeline
```yaml
# .github/workflows/code-check.yml
jobs:
  dev-check:
    runs-on: ubuntu-latest
    steps:
      - name: Run dev checks
        run: ./dist/bin/check-performance.sh --severity-config severity-dev.json

  staging-check:
    runs-on: ubuntu-latest
    steps:
      - name: Run staging checks
        run: ./dist/bin/check-performance.sh --severity-config severity-staging.json

  production-check:
    runs-on: ubuntu-latest
    steps:
      - name: Run production checks (strict)
        run: ./dist/bin/check-performance.sh --severity-config severity-production.json --strict
```

---

## 🎯 Use Case 5: Team-Specific Overrides

**Scenario:** Different teams have different priorities.

### Frontend Team
**File:** `severity-frontend.json`
```json
{
  "severity_levels": {
    "hcc-001-localstorage-exposure": {
      "level": "CRITICAL",
      "_team": "Frontend",
      "_reason": "We handle all client-side storage"
    },
    "hcc-008-unsafe-regexp": {
      "level": "HIGH",
      "_reason": "Frontend team owns all JS regex"
    },
    "wpdb-query-no-prepare": {
      "level": "LOW",
      "_reason": "Backend team handles database queries"
    }
  }
}
```

### Backend Team
**File:** `severity-backend.json`
```json
{
  "severity_levels": {
    "wpdb-query-no-prepare": {
      "level": "CRITICAL",
      "_team": "Backend",
      "_reason": "We own all database queries"
    },
    "get-users-no-limit": {
      "level": "CRITICAL",
      "_reason": "Backend team handles all user queries"
    },
    "hcc-001-localstorage-exposure": {
      "level": "LOW",
      "_reason": "Frontend team handles client-side code"
    }
  }
}
```

---

## 📊 Comparison: Pattern JSON vs Severity Config

| Aspect | Pattern JSON Files | Severity Config File |
|--------|-------------------|---------------------|
| **Purpose** | Pattern definition | User customization |
| **Location** | `dist/patterns/*.json` | `dist/config/severity-levels.json` or custom |
| **Scope** | Individual patterns | All 33 patterns |
| **Contains** | Detection logic, examples, remediation | Severity levels only |
| **Edited by** | Pattern authors, contributors | End users, DevOps teams |
| **Version controlled** | Yes (part of repo) | Optional (project-specific) |
| **Override mechanism** | N/A | `--severity-config <path>` |

---

## 💡 Best Practices

### 1. Document Your Overrides
Always use `_comment`, `_reason`, `_ticket` fields to explain why you changed severity:
```json
{
  "wpdb-query-no-prepare": {
    "level": "MEDIUM",
    "_reason": "50 existing violations in legacy code",
    "_ticket": "JIRA-1234",
    "_target_date": "2026-06-01",
    "_owner": "backend-team@example.com"
  }
}
```

### 2. Use Baselines for Existing Issues
Don't downgrade severity - use baselines instead:
```bash
# Generate baseline for existing issues
./dist/bin/check-performance.sh --generate-baseline

# Future scans only show NEW issues
./dist/bin/check-performance.sh
```

### 3. Upgrade Severity for Critical Projects
For payment, auth, or PII handling:
```json
{
  "unsanitized-superglobal-read": {
    "level": "CRITICAL",  // Upgraded from HIGH
    "_reason": "Handles payment card data"
  }
}
```

### 4. Environment-Specific Configs
Use different configs for dev/staging/prod:
```bash
# Development (lenient)
./dist/bin/check-performance.sh --severity-config severity-dev.json

# Production (strict)
./dist/bin/check-performance.sh --severity-config severity-prod.json --strict
```

---

## 📂 File Locations

**Factory Defaults:**
- `dist/config/severity-levels.json`

**Pattern Definitions:**
- `dist/patterns/*.json` (4 files currently)

**User Custom Configs:**
- Create anywhere (e.g., `my-severity.json`, `severity-prod.json`)
- Pass via `--severity-config <path>`

---

**TL;DR:** Pattern JSON files define WHAT to detect. Severity config files define HOW SEVERE it is for YOUR project. Use `--severity-config` to customize per environment/team/project.

