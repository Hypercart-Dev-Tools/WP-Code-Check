# PROPOSAL-GOLDENRULES-v1.1
** TYPE:** RULES -> CALIBRATION
**STATUS:** DRAFT

## Purpose

This proposal documents a pragmatic v1.1 direction for the **Golden Rules Analyzer** within the WP Code Check ecosystem.

Goals:
- Reduce “this is normal WordPress” backlash
- Preserve meaningful architectural signal
- Clarify intent, scope, and safe defaults
- Provide a WP-friendly default configuration
- Treat Golden Rules as **advisory**, not enforcement

This document assumes Golden Rules remains **experimental** and **non-blocking**.

---

## Executive Summary

Golden Rules provides architectural insight but currently flags several patterns that are *idiomatic and unavoidable* in WordPress development.

v1.1 focuses on:
- Explicitly de-emphasizing or softening high-noise rules
- Adjusting defaults to align with WordPress realities
- Reframing output as **review prompts**
- Using configuration profiles rather than universal correctness

---

## Rules That Generate the Most WordPress Noise

### 1. State Flows Through Gates (High Noise)

**What it flags**
- Property mutation outside constructors or setter-like methods

**Why this is normal in WordPress**
- Objects are often mutable data containers
- Hooks frequently mutate state post-construction
- Lazy initialization is common

**Current Risk**
- Very high false positives
- Pushes an OOP purity model WordPress does not follow

**v1.1 Recommendation**
- Default severity: `info`
- Allow common WP lifecycle methods
- Encourage review, not refactor

---

### 2. One Truth, One Place (Medium–High Noise)

**What it flags**
- Repeated string literals (option keys, meta keys)

**Why this is normal in WordPress**
- Procedural codebases
- Hooks, templates, and admin screens repeat keys
- Backwards compatibility discourages refactors

**Current Risk**
- Flags stable, intentional duplication
- Encourages churn without clear benefit

**v1.1 Recommendation**
- Increase minimum occurrence threshold
- Ignore keys matching common WP patterns (`_transient_`, `_wp_`)
- Keep as `warning`, not `error`

---

### 3. Query Boundaries (Medium Noise)

**What it flags**
- Unbounded or loosely bounded queries

**Why this is normal in WordPress**
- Defaults are often acceptable (`posts_per_page`)
- Filters modify limits downstream
- Pagination may be handled elsewhere

**Current Risk**
- Partial context leads to false alarms

**v1.1 Recommendation**
- Allow default WP_Query limits
- Flag only *explicitly* unbounded queries
- Keep severity at `warning`

---

### 4. Fail Gracefully (Medium Noise)

**What it flags**
- Functions that return `false` or `null` without nearby error handling

**Why this is normal in WordPress**
- Errors are often handled at call sites
- WP_Error usage is inconsistent across codebases

**Current Risk**
- Proximity-based detection is brittle

**v1.1 Recommendation**
- Downgrade to `info`
- Treat as documentation / design signal only

---

### 5. Debug Output (Low–Medium Noise)

**What it flags**
- `var_dump`, `print_r`, `error_log` without WP_DEBUG checks

**Why this is sometimes normal**
- Debug wrappers abstract the check
- Multi-line conditions break regex detection

**v1.1 Recommendation**
- Keep rule
- Allow wrapper functions by default
- Severity remains `warning`

---

## Rules That Retain Strong Signal in WordPress

These rules consistently identify real issues:

- N+1 Query Patterns
- Hardcoded Magic Numbers in Queries
- Direct SQL Without $wpdb Preparation
- Output Without Escaping (when applicable)

These should remain enabled with current or slightly tuned sensitivity.

---

## Proposed WP-Friendly Default Profile

```json
{
  "severity_overrides": {
    "StateFlowsThroughGates": "info",
    "FailGracefully": "info",
    "OneTruthOnePlace": "warning"
  },
  "state_handlers": [
    "__construct",
    "init",
    "setup",
    "register",
    "boot",
    "hydrate",
    "load",
    "set_*"
  ],
  "single_truth": {
    "min_occurrences": 4,
    "ignore_patterns": [
      "^_wp_",
      "^_transient_",
      "^_site_transient_"
    ]
  },
  "query_boundaries": {
    "allow_default_limits": true,
    "flag_only_unbounded": true
  },
  "debug": {
    "allowed_wrappers": [
      "my_debug",
      "wp_debug_log"
    ]
  }
}
