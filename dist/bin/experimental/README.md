# 🧪 Experimental Tools

**Status:** Experimental | **Stability:** Beta | **Support:** Community-driven

This folder contains **experimental tools** that extend WP Code Check with advanced analysis capabilities. These tools are functional but may have rough edges, false positives, or breaking changes in future releases.

---

## 🔬 What's Inside

### Golden Rules Analyzer
**File:** `golden-rules-analyzer.php`  
**Type:** Semantic PHP analyzer for WordPress architectural antipatterns  
**Requires:** PHP 7.4+ CLI  

**What it does:**
- Detects architectural violations that pattern matching can't catch
- Analyzes code semantics using PHP tokenization
- Enforces 6 core architectural principles for WordPress development

**When to use:**
- Code reviews before major releases
- Refactoring legacy codebases
- Enforcing team coding standards
- Deep analysis of complex plugins/themes

**When NOT to use:**
- CI/CD pipelines (use quick scanner instead - faster, zero dependencies)
- Quick spot checks (overkill for simple tasks)
- Production environments (experimental status)

---

## 📖 End-to-End User Story: Complete Code Quality Workflow

### Scenario: You're Preparing a WordPress Plugin for Release

**Goal:** Catch both surface-level issues AND architectural problems before shipping.

---

### Step 1: Quick Scan (Fast Feedback Loop)

**Use the bash scanner for rapid iteration during development:**

```bash
# Run quick scan while coding
./dist/bin/check-performance.sh --paths ~/my-plugin

# Example output (takes <5 seconds):
✓ Checking for unbounded WP_Query calls...
  ⚠ WARNING: Found 2 unbounded queries
  
✓ Checking for direct database queries...
  ✓ No issues found
  
✓ Checking for missing nonce verification...
  ⚠ WARNING: Found 3 forms without nonce checks
```

**What you get:**
- ⚡ **Speed:** Results in <5 seconds
- 🎯 **Focus:** 30+ critical performance/security checks
- 🚀 **Zero setup:** No dependencies, works everywhere
- ✅ **CI/CD ready:** Perfect for automated pipelines

**When to run:** After every significant code change, before commits

---

### Step 2: Fix Quick Wins

**Address the low-hanging fruit identified by the quick scanner:**

```php
// BEFORE (flagged by quick scanner)
$query = new WP_Query( array(
    'post_type' => 'product'
    // Missing posts_per_page!
) );

// AFTER (fixed)
$query = new WP_Query( array(
    'post_type' => 'product',
    'posts_per_page' => 20  // ✅ Bounded query
) );
```

**Verify the fix:**
```bash
./dist/bin/check-performance.sh --paths ~/my-plugin
# ✓ No unbounded queries found
```

---

### Step 3: Deep Analysis (Pre-Release Check)

**Now run the experimental Golden Rules analyzer for architectural issues:**

```bash
# Run deep semantic analysis
php ./dist/bin/experimental/golden-rules-analyzer.php ~/my-plugin

# Example output (takes 10-30 seconds):
/my-plugin/includes/class-product-manager.php
  ERROR Line 45: Direct state mutation detected: $this->status = 'active'
    → Use a state handler method like: set_state, transition_to, transition
  
  WARNING Line 78: Option key "product_settings" appears 5 times
    → Define: const OPTION_PRODUCT_SETTINGS = 'product_settings';
  
  WARNING Line 102: wp_remote_get result not checked with is_wp_error()
    → Add: if (is_wp_error($response)) { /* handle error */ }

Summary: 1 error, 2 warnings, 0 info
```

**What you get:**
- 🧠 **Semantic analysis:** Understands code structure, not just patterns
- 🏗️ **Architectural enforcement:** Catches design-level antipatterns
- 📚 **Best practices:** Enforces WordPress coding standards
- 🎓 **Educational:** Explains WHY something is wrong

**When to run:** Before major releases, during code reviews, when refactoring

---

### Step 4: Fix Architectural Issues

**Address the deeper problems identified by Golden Rules:**

```php
// BEFORE (flagged by Golden Rules - direct state mutation)
class Product_Manager {
    private $status;
    
    public function activate_product() {
        $this->status = 'active';  // ❌ Direct mutation
    }
}

// AFTER (fixed - state flows through gates)
class Product_Manager {
    private $status;
    
    public function activate_product() {
        $this->set_status( 'active' );  // ✅ Uses state handler
    }
    
    private function set_status( $new_status ) {
        // Centralized state management
        $old_status = $this->status;
        $this->status = $new_status;
        
        // Can add validation, logging, hooks
        do_action( 'product_status_changed', $old_status, $new_status );
    }
}
```

**Why this matters:**
- ✅ Centralized state logic (easier to debug)
- ✅ Can add validation in one place
- ✅ Enables audit trails and logging
- ✅ Prevents inconsistent state changes

---

### Step 5: Combined Workflow (Best of Both Worlds)

**Use the unified CLI for streamlined analysis:**

```bash
# Option A: Run both tools sequentially
./dist/bin/wp-audit full ~/my-plugin

# Output:
# ━━━ Running Quick Scan (30+ checks) ━━━
# [Quick scan results...]
# 
# ━━━ Running Deep Analysis (6 Golden Rules) ━━━
# [Deep analysis results...]

# Option B: Quick scan only (CI/CD)
./dist/bin/wp-audit quick ~/my-plugin --strict

# Option C: Deep analysis only (code review)
./dist/bin/wp-audit deep ~/my-plugin
```

---

## 🎯 Real-World Example: Complete Workflow

### Day 1: Active Development
```bash
# Quick feedback loop while coding
./dist/bin/check-performance.sh --paths ~/my-plugin
# Fix issues immediately
# Commit clean code
```

### Day 5: Feature Complete
```bash
# Run deep analysis before code review
php ./dist/bin/experimental/golden-rules-analyzer.php ~/my-plugin
# Refactor architectural issues
# Document decisions in ADRs
```

### Day 7: Pre-Release
```bash
# Final comprehensive check
./dist/bin/wp-audit full ~/my-plugin --format json > final-audit.json

# Generate HTML report for stakeholders
./dist/bin/wp-audit report final-audit.json release-report.html
```

### CI/CD Pipeline
```yaml
# .github/workflows/code-quality.yml
- name: Quick Scan (Fast)
  run: ./dist/bin/check-performance.sh --paths . --strict
  
# Optional: Deep analysis on main branch only
- name: Deep Analysis (Slow)
  if: github.ref == 'refs/heads/main'
  run: php ./dist/bin/experimental/golden-rules-analyzer.php .
```

---

## 📊 Tool Comparison: When to Use What

| Scenario | Tool | Why |
|----------|------|-----|
| **During development** | Quick Scanner | Fast feedback, zero setup |
| **Before commits** | Quick Scanner | Catch obvious issues early |
| **CI/CD pipelines** | Quick Scanner | Fast, reliable, zero dependencies |
| **Code reviews** | Golden Rules | Deep architectural analysis |
| **Pre-release checks** | Both (Full) | Complete coverage |
| **Refactoring legacy code** | Golden Rules | Find design-level problems |
| **Teaching juniors** | Golden Rules | Explains best practices |

---

## 🚀 Quick Start

### Prerequisites
- **Quick Scanner:** None (zero dependencies)
- **Golden Rules:** PHP 7.4+ CLI

### Installation
```bash
# Clone the repo
git clone https://github.com/Hypercart-Dev-Tools/WP-Code-Check.git
cd WP-Code-Check

# Make scripts executable
chmod +x dist/bin/*.sh dist/bin/wp-audit
chmod +x dist/bin/experimental/*.php
```

### Basic Usage
```bash
# Quick scan (recommended first step)
./dist/bin/check-performance.sh --paths ~/my-plugin

# Deep analysis (experimental)
php ./dist/bin/experimental/golden-rules-analyzer.php ~/my-plugin

# Unified CLI (both tools)
./dist/bin/wp-audit full ~/my-plugin
```

---

## ⚠️ Experimental Status: What This Means

### What Works
- ✅ Core detection logic is solid
- ✅ Catches real architectural problems
- ✅ Provides actionable suggestions
- ✅ Integrates with existing toolkit

### Known Limitations
- ⚠️ May produce false positives (refining patterns)
- ⚠️ JSON output format not fully implemented
- ⚠️ Rule filtering (`--rule=<name>`) runs all rules
- ⚠️ Limited test coverage on edge cases

### What "Experimental" Means
- 🔄 **Breaking changes possible** - API may change in future versions
- 🐛 **Bugs expected** - Report issues, we'll fix them
- 📚 **Documentation evolving** - Feedback welcome
- 🤝 **Community-driven** - Your input shapes the roadmap

### How to Help
1. **Report false positives** - Help us refine detection patterns
2. **Share use cases** - Tell us how you're using it
3. **Contribute patterns** - Submit PRs for new rules
4. **Test edge cases** - Try it on complex codebases

---

## 📚 The 6 Golden Rules Explained

### Rule 1: Search Before You Create
**Problem:** Duplicate functions across files waste memory and create maintenance nightmares.

**What it detects:**
- Functions with similar names across different files
- Copy-pasted utility functions
- Redundant helper methods

**Example:**
```php
// File: includes/helpers.php
function format_price( $amount ) { /* ... */ }

// File: includes/utils.php
function format_product_price( $amount ) { /* ... */ }  // ❌ Duplicate logic

// Better: Centralize in one place
// File: includes/helpers.php
function format_price( $amount ) { /* ... */ }  // ✅ Single source of truth
```

---

### Rule 2: State Flows Through Gates
**Problem:** Direct state mutations bypass validation, logging, and hooks.

**What it detects:**
- Direct property assignments (`$this->status = 'value'`)
- State changes outside handler methods
- Mutations that skip business logic

**Example:**
```php
// ❌ BAD: Direct mutation
$order->status = 'completed';

// ✅ GOOD: State flows through gate
$order->set_status( 'completed' );  // Can validate, log, fire hooks
```

---

### Rule 3: One Truth, One Place
**Problem:** Magic strings scattered across code make refactoring impossible.

**What it detects:**
- Repeated option keys (3+ occurrences)
- Hardcoded capability names
- Duplicate meta keys

**Example:**
```php
// ❌ BAD: Magic strings everywhere
get_option( 'my_plugin_settings' );
update_option( 'my_plugin_settings', $data );
delete_option( 'my_plugin_settings' );

// ✅ GOOD: Constant as single source of truth
const OPTION_SETTINGS = 'my_plugin_settings';
get_option( self::OPTION_SETTINGS );
update_option( self::OPTION_SETTINGS, $data );
delete_option( self::OPTION_SETTINGS );
```

---

### Rule 4: Queries Have Boundaries
**Problem:** Unbounded queries crash servers under load.

**What it detects:**
- `WP_Query` without `posts_per_page`
- Queries inside loops (N+1 problem)
- Missing pagination limits

**Example:**
```php
// ❌ BAD: Unbounded query
$query = new WP_Query( array( 'post_type' => 'product' ) );

// ❌ BAD: N+1 query in loop
foreach ( $categories as $cat ) {
    $posts = get_posts( array( 'category' => $cat->ID ) );  // Query per iteration!
}

// ✅ GOOD: Bounded query
$query = new WP_Query( array(
    'post_type' => 'product',
    'posts_per_page' => 20  // Explicit limit
) );

// ✅ GOOD: Single query with tax_query
$posts = get_posts( array(
    'tax_query' => array( /* all categories */ )  // One query for all
) );
```

---

### Rule 5: Fail Gracefully
**Problem:** Unhandled errors crash sites in production.

**What it detects:**
- `wp_remote_get()` without `is_wp_error()` check
- `file_get_contents()` without error handling
- `json_decode()` without validation

**Example:**
```php
// ❌ BAD: No error handling
$response = wp_remote_get( 'https://api.example.com/data' );
$data = json_decode( wp_remote_retrieve_body( $response ) );

// ✅ GOOD: Graceful failure
$response = wp_remote_get( 'https://api.example.com/data' );
if ( is_wp_error( $response ) ) {
    error_log( 'API request failed: ' . $response->get_error_message() );
    return false;
}

$body = wp_remote_retrieve_body( $response );
$data = json_decode( $body );
if ( json_last_error() !== JSON_ERROR_NONE ) {
    error_log( 'JSON decode failed: ' . json_last_error_msg() );
    return false;
}
```

---

### Rule 6: Ship Clean
**Problem:** Debug code and TODOs leak into production.

**What it detects:**
- `var_dump()`, `print_r()`, `error_log()` (without WP_DEBUG check)
- `TODO`, `FIXME`, `HACK` comments
- Commented-out code blocks

**Example:**
```php
// ❌ BAD: Debug code in production
function process_order( $order ) {
    var_dump( $order );  // Left in by accident!
    // TODO: Add validation
    return $order->save();
}

// ✅ GOOD: Clean production code
function process_order( $order ) {
    if ( WP_DEBUG ) {
        error_log( 'Processing order: ' . print_r( $order, true ) );
    }

    if ( ! $this->validate_order( $order ) ) {
        return new WP_Error( 'invalid_order', 'Order validation failed' );
    }

    return $order->save();
}
```

---

## 🔧 Configuration

Create `.golden-rules.json` in your project root to customize behavior:

```json
{
  "rules": {
    "duplication": {
      "enabled": true,
      "similarity_threshold": 0.8
    },
    "state-gates": {
      "enabled": true,
      "allowed_methods": ["set_state", "transition_to", "update_status"]
    },
    "single-truth": {
      "enabled": true,
      "min_occurrences": 3
    },
    "query-boundaries": {
      "enabled": true,
      "max_posts_per_page": 100
    },
    "graceful-failure": {
      "enabled": true,
      "require_error_handling": ["wp_remote_get", "wp_remote_post", "file_get_contents"]
    },
    "ship-clean": {
      "enabled": true,
      "allow_debug_in_wp_debug": true
    }
  }
}
```

---

## 🎓 Learning Resources

### Understanding the Philosophy
- **DRY Principle:** Don't Repeat Yourself - centralize logic
- **Single Source of Truth:** One place to change, everywhere updates
- **Fail Fast:** Catch errors early, handle them gracefully
- **State Machines:** Controlled transitions prevent bugs

### WordPress Best Practices
- [WordPress Coding Standards](https://developer.wordpress.org/coding-standards/)
- [Plugin Handbook](https://developer.wordpress.org/plugins/)
- [Theme Handbook](https://developer.wordpress.org/themes/)

### Architectural Patterns
- **State Pattern:** Encapsulate state transitions
- **Repository Pattern:** Centralize data access
- **Factory Pattern:** Consistent object creation

---

## 🐛 Troubleshooting

### "PHP not found"
```bash
# Check PHP installation
php --version

# Install PHP (macOS)
brew install php

# Install PHP (Ubuntu)
sudo apt-get install php-cli
```

### "Permission denied"
```bash
# Make script executable
chmod +x dist/bin/experimental/golden-rules-analyzer.php
```

### "Too many false positives"
1. Create `.golden-rules.json` to adjust thresholds
2. Report patterns to GitHub issues
3. Use `--rule=<name>` to run specific rules only

### "Script hangs or times out"
- Large codebases (10,000+ files) may take several minutes
- Use `--rule=<name>` to analyze specific rules
- Consider excluding vendor/node_modules directories

---

## 📞 Support & Feedback

### Experimental Tool Support
- **GitHub Issues:** [Report bugs and false positives](https://github.com/Hypercart-Dev-Tools/WP-Code-Check/issues)
- **Discussions:** [Share use cases and feedback](https://github.com/Hypercart-Dev-Tools/WP-Code-Check/discussions)
- **Community:** Help shape the future of this tool!

### Contributing
We welcome contributions! Areas where you can help:
- 🐛 Report false positives with code examples
- 📝 Improve documentation and examples
- 🔍 Suggest new detection patterns
- 🧪 Add test cases for edge scenarios
- 🎨 Improve output formatting

---

## 🗺️ Roadmap

### Current Status (v1.2.0)
- ✅ 6 core rules implemented
- ✅ Console output with colors
- ✅ Basic configuration support
- ⚠️ JSON output (partial)
- ⚠️ Rule filtering (in progress)

### Planned Improvements
- 🔄 Full JSON output for CI/CD integration
- 🔄 Rule-specific filtering (`--rule=<name>`)
- 🔄 Configurable severity levels
- 🔄 Auto-fix suggestions (where safe)
- 🔄 IDE integration (VSCode extension)
- 🔄 Custom rule definitions

### Graduation Criteria (Move to Stable)
- [ ] 90%+ accuracy (low false positive rate)
- [ ] Full JSON output implementation
- [ ] Comprehensive test coverage
- [ ] 100+ real-world usage reports
- [ ] Documentation complete
- [ ] Performance optimized (<10s for typical plugin)

---

## 📄 License

Apache-2.0 License - See main repository LICENSE file

---

## 🙏 Credits

**Developed by:** Hypercart (a DBA of Neochrome, Inc.)
**Part of:** WP Code Check toolkit
**Inspired by:** WordPress coding standards, PHPStan, PHPCS, and 25 years of CTO experience

---

**Remember:** This is an **experimental tool**. Use it to learn, improve your code, and catch architectural issues early. But always review its suggestions with critical thinking - you're the expert on your codebase! 🚀

