# P1 – PHP Parser / Static Analysis Integration Plan
**Status:** Research Completed · **Created:** 2026-02-03 · **Updated:** 2026-02-04

## Table of Contents
- [Background](#background)
- [High-Level Phased Checklist](#high-level-phased-checklist)
- [Background & Goals](#background--goals)
- [Tooling Options Overview](#tooling-options-overview)
- [Recommended Tooling Choice](#recommended-tooling-choice)
- [Phase 0 – Spike & Decision](#phase-0--spike--decision)
- [Phase 1 – Local PHPStan Integration](#phase-1--local-phpstan-integration)
  - [Phase 1 Findings](#phase-1-findings-2026-02-03)
  - [Phase 1 Decision](#phase-1-decision)
- [Phase 2 – PHP-Parser AST Experiments for WPCC](#phase-2--php-parser-ast-experiments-for-wpcc)
  - [Phase 2 Findings](#phase-2-findings-2026-02-04)
  - [Phase 2 Decision](#phase-2-decision)
- [Phase 3 – Hardening & Developer Experience](#phase-3--hardening--developer-experience)
- [Risk / Quagmire Avoidance](#risk--quagmire-avoidance)
- [LLM Notes](#llm-notes)
- [Appendix – PHPStan WordPress Setup Handoff](#appendix--phpstan-wordpress-setup-handoff)

## Background
WPCC today is a shell-based scanner that leans on grep-style rules, cached file lists, and small Python helpers to produce deterministic JSON logs and HTML reports.
It is intentionally distributed without a Composer/vendor footprint, and its checks are primarily syntactic (e.g., unbounded queries, superglobals, magic strings) rather than type- or contract-aware.
This plan explores how to layer PHP-Parser and dedicated static analysis tools (PHPStan/Psalm) on top of that foundation without breaking the lightweight distribution model.

## High-Level Phased Checklist
> **Note for LLMs:** Whenever you progress an item below, update its checkbox state in-place so humans can see progress without scrolling.
- [x] Phase 0 – Clarify goals, choose pilot use cases, decide tooling mix
- [x] Phase 1 – Run PHPStan/Psalm on a target plugin repo with simple IRL checks ✅ **(2026-02-03)**
- [x] Phase 2 – Implement first PHP-Parser-based AST rule inside WPCC ✅ **(2026-02-04)**
- [ ] Phase 3 – Stabilize, document, and integrate into CI / WPCC flows

## Background & Goals
We want type- and shape-aware analysis that can catch:
- Contract mismatches between producers (`search_customers()`) and consumers (filters/Ajax).
- Misused settings from `get_option()` and similar APIs.
- Nullability mistakes around `get_user_by()`, `get_post()`, `wc_get_order()`, etc.

Constraints:
- WPCC today is shell + grep + small Python helpers, with no Composer footprint.
- We must avoid a quagmire where bundling a full static analyser into WPCC explodes complexity.
- First wins must be small, IRL, and obviously useful to developers.
- We already have in-house PHP-Parser plumbing:
  - `kissplugins/WP-PHP-Parser-loader` for loading/configuring PHP-Parser in WP.
  - A working harness in `KISS-woo-shipping-settings-debugger` for using AST analysis on real plugins.

## Tooling Options Overview
**PHPStan**
- Mature static analyser with strong ecosystem.
- Good WordPress support via `phpstan/wordpress` and community configs.
- Excellent at cross-function type contracts and array shapes.
- Assumes a Composer-managed project; heavy to embed directly into WPCC.

**Psalm**
- Very capable analyser with rich type system and taint analysis.
- Similar Composer + bootstrap expectations as PHPStan.
- Slightly smaller WP-specific ecosystem for our current needs.

**nikic/PHP-Parser**
- Low-level AST library; we get syntax trees and must build our own analysis.
- Great for narrow, custom rules where grep is too blunt.
- No built-in type inference, data flow, or WordPress awareness.
- Fits WPCC’s distribution model better, especially given our existing loader + harness, but only if we keep scope tight.

## Recommended Tooling Choice
**Short answer**
- For plugin development repos (e.g., Woo Fast Search), start with **PHPStan** as the primary static analysis tool.
- For WPCC itself and its “no Composer” distribution, use **PHP-Parser** for a small set of targeted AST-based checks, not as a general type system.

Rationale:
- PHPStan/Psalm already solved the hard problems (types, inheritance, generics, data flow); recreating that on top of PHP-Parser would be a multi-month project.
- WPCC can still benefit from lightweight AST rules where grep is too blunt, while keeping install friction low.
- PHPStan has a slight edge over Psalm here due to WordPress extensions, docs, and recipes that match our IRL patterns.

## Phase 0 – Spike & Decision
**Goals**
- Confirm the “easier” IRL use cases (options shape, nullability, list vs single) are lower effort and lower risk than the wholesale filter contract.
- Decide on: (a) initial PHPStan configuration for a target plugin repo; (b) first AST rule worth building with PHP-Parser in WPCC, reusing our existing loader and harness patterns where possible.

**Tasks**
- [ ] Pick 1–2 IRL scenarios as pilots:
  - [ ] Settings/options shape via `get_option()`.
  - [ ] Nullability guards for `get_user_by()` / `get_post()` / `wc_get_order()`.
- [ ] Run a manual PHPStan spike (level 1–3) on the plugin repo using Composer dev-dependency.
- [ ] Document major friction points (WordPress stubs, bootstrap, performance).
- [ ] Review `WP-PHP-Parser-loader` and KISS-woo-shipping-settings-debugger harness to understand existing AST patterns and APIs.
- [ ] Sketch one candidate PHP-Parser rule where grep is not enough (e.g., verifying a specific Ajax response array shape) that can be implemented by reusing the loader/harness concepts.
- [ ] Roughly sketch a JSON config schema for AST rules (e.g., for `ajax-response-shape`: function selectors, expected keys, severity/impact) before implementation.
- [ ] Time-box Phase 0 spikes (e.g., 4–6 engineering hours) and add a “stop and reassess” checkpoint; if PHPStan WP stubs/bootstrap friction is too high, pivot or descope rather than pushing through.


## Phase 1 – Local PHPStan Integration
**Intent:** Keep this out of WPCC's distribution; treat it as a per-repo dev tool.

**Status:** ✅ **COMPLETE** — PHPStan validated as viable for plugin development.

**Tasks**
- [x] Add PHPStan as a dev dependency to the target plugin repo.
- [x] Create a minimal `phpstan.neon` with:
  - [x] WordPress extension / stubs configuration sketched (see Appendix and fixture at `temp/KISS-woo-fast-search/phpstan.neon`).
  - [ ] Baseline file to mute existing noise. *(Deferred — not needed for decision)*
- [x] Encode 1–2 simple IRL checks:
  - [x] `get_option()` wrapper returning a documented array shape (`get_plugin_settings()`).
  - [x] One nullability wrapper (`find_customer_by_email(): ?WP_User`).
- [ ] Run PHPStan in CI and locally; confirm it stays fast and stable. *(Deferred to production adoption)*
- [x] Record a canonical IRL failure fixture for later regression tests: the Woo Fast Search "wholesale filter contract mismatch" bug at commit `9dec5a4cd713b6528673cc8a0561e6c4db925667`, checked out locally at `temp/KISS-woo-fast-search` (source: https://github.com/kissplugins/KISS-woo-fast-search/commit/9dec5a4cd713b6528673cc8a0561e6c4db925667).

### Phase 1 Findings (2026-02-03)

**Run #1 — Clean signal with stubs installed**

| Metric | Before Stubs | After Stubs |
|--------|--------------|-------------|
| Errors | ~444 | **1** |
| Type | All "symbol not found" noise | Actionable code quality issue |

- Installed PHPStan + WP/Woo/wp-cli stubs via Composer in `temp/KISS-woo-fast-search`.
- Re-ran PHPStan at level 3 with `--memory-limit=1G`.
- Result: **1 error** — `Variable $post in empty() always exists and is not falsy` in `class-kiss-woo-coupon-lookup.php:116`.
- WordPress/WooCommerce symbol noise is **eliminated**.

**Run #2 — Typed helper calibration**

Created `includes/class-kiss-woo-typed-helpers.php` with:
- `get_plugin_settings()` returning `array{debug_mode: bool, cache_ttl: int, max_results: int}`
- `find_customer_by_email()` returning `?WP_User`
- Intentional violations to test PHPStan detection

| Violation | Description | PHPStan Level | Caught? |
|-----------|-------------|---------------|---------|
| #2 | Accessing `$user->display_name` on `WP_User\|null` without null check | 8 | ✅ Yes |
| #3 | Accessing `$settings['api_key']` which doesn't exist in shape | 3 | ✅ Yes |
| #1 | Passing flat array to filter expecting structured hash | — | ⚠️ Requires typed interface |

**Key insight:** PHPStan catches array shape and nullability violations **if the types are documented**. The original wholesale filter bug would be caught if `KISS_Woo_Order_Filter::apply()` had a PHPDoc shape like `@param array{customers: array, guest_orders: array, orders: array} $results`.

### Phase 1 Decision

**✅ PHPStan is viable and valuable for plugin development.**

- Signal/noise ratio is excellent once stubs are installed.
- Array shape enforcement works at level 3.
- Nullability enforcement works at level 8.
- Setup is documented in Appendix and reproducible.

**Recommendation:** Adopt PHPStan as a dev tool for KISS plugins. Add typed helpers incrementally. Consider adding PHPDoc shapes to interfaces like `KISS_Woo_Order_Filter` to catch contract mismatches.

**Next:** Proceed to Phase 2 (PHP-Parser AST experiments for WPCC) or adopt PHPStan in production plugin repos.


## Phase 2 – PHP-Parser AST Experiments for WPCC
**Intent:** Add one small AST-based rule to WPCC to prove value over grep, without changing WPCC’s installation story, and **leverage our existing loader + harness** so this remains a low-risk, low-effort experiment.

**Status:** ✅ **COMPLETE** — Proof-of-concept AST checker built and validated.

### Proposed First AST Rule: Ajax Response Shape Checker
**Scenario (example: Woo Fast Search, or similar search feature)**
- Target a specific Ajax endpoint function (e.g. `ajax_search_customers()`).
- Enforce that any returned array literal for the JSON response has a **fixed, documented shape**, for example:
  - `['customers' => list, 'total' => int, 'has_more' => bool]`.

**What the rule does (AST-level)**
- Parse target PHP files and locate:
  - Functions matching a configured name/pattern (e.g. `kiss_woo_ajax_search_customers`).
  - `return` statements that return an array literal.
- Validate that those array literals:
  - Contain required keys (`customers`, `total`, `has_more`).
  - Do **not** contain obviously conflicting duplicate shapes for the same function.
  - Optionally: flag if the same function sometimes returns a bare list vs a keyed array literal.

**Limitations (v1)**
- Only inspects direct array literals in `return` statements.
- Patterns like `$result = [...]; return $result;` or arrays built via helper functions are out of scope for the initial rule.
- This is acceptable for v1; broader data-flow or variable-tracking can be revisited in later phases if this rule proves useful.

**CLI contract (sketch)**
- New helper, invoked from WPCC (names TBD), for example:
  - `php dist/bin/wpcc-ast-check.php --rule ajax-response-shape --config dist/config/ajax-response-shape.json --paths "${PATHS}"`.
- Output: JSON object with a `findings` array compatible with WPCC’s log schema, e.g. each finding contains at minimum:
  - `id` (e.g. `ast-001-ajax-response-shape`)
  - `severity` (e.g. `warning` or `error`)
  - `impact` (e.g. `MEDIUM`)
  - `file`, `line`, `message`, `code`, and optional `context` lines (mirroring existing entries in `dist/logs/*.json`).

**Tasks**
- [x] Decide and document how PHP-Parser will be distributed for WPCC (e.g., bundle loader/helper into `dist/` and rely on `WP-PHP-Parser-loader` to manage `nikic/php-parser`, keeping WPCC itself Composer-free).
- [x] Reuse or adapt `WP-PHP-Parser-loader` so WPCC can reliably load PHP-Parser in its own context.
- [x] Mirror or borrow minimal harness patterns from KISS-woo-shipping-settings-debugger for walking ASTs and emitting JSON findings.
- [x] Define a small JSON config format for this rule (e.g. function names and expected keys).
- [x] Implement the `return-array-shape` rule end-to-end:
  - [x] CLI entry point callable from WPCC (`dist/bin/ast/wpcc-ast-check.php`).
  - [x] JSON output format consistent with existing `findings` entries (id/severity/impact/file/line/message/code/context).
  - [ ] Wiring into the scan pipeline behind a feature flag. *(Deferred to Phase 3)*
- [ ] Measure performance impact and confirm it’s acceptable on medium-sized plugins. *(Deferred to Phase 3)*
- [x] Test against IRL fixture (`temp/KISS-woo-fast-search`) to validate detection of return array shapes.

### Phase 2 Findings (2026-02-04)

**What was built:**

| Component | File | Purpose |
|-----------|------|---------|
| Autoloader | `dist/bin/ast/autoload.php` | Standalone PHP-Parser loader for CLI context (no WordPress required) |
| Visitor | `dist/bin/ast/ReturnArrayShapeVisitor.php` | NodeVisitor that collects return statements with array literals |
| CLI Entry | `dist/bin/ast/wpcc-ast-check.php` | Main script with `--paths`, `--rule`, `--config`, `--output` options |
| Example Config | `dist/bin/ast/config/return-array-shape.example.json` | JSON config for expected keys and target scopes |

**Test Results:**

| Test | Command | Result |
|------|---------|--------|
| Shape detection | `--paths class-kiss-woo-ajax-handler.php` | ✅ Detected 3 return shapes across 2 methods |
| Missing key finding | Config with `wholesale_flag` in expected keys | ✅ Generated 2 findings for missing key |

**Sample output (text format):**

```text
WPCC AST Check Results
======================

Rule: return-array-shape
Files scanned: 1
Findings: 0
Parse errors: 0

Detected Return Array Shapes:
  class-kiss-woo-ajax-handler.php:152 - KISS_Woo_Ajax_Handler::perform_search
    Keys: [customers, guest_orders, orders, coupons, should_redirect_to_order, redirect_url, search_scope]
  class-kiss-woo-ajax-handler.php:205 - KISS_Woo_Ajax_Handler::perform_search
    Keys: [customers, guest_orders, orders, coupons, should_redirect_to_order, redirect_url, search_scope]
  class-kiss-woo-ajax-handler.php:383 - KISS_Woo_Ajax_Handler::get_debug_data
    Keys: [traces, memory_peak_mb, php_version, wc_version]
```

**Key observations:**

1. **PHP-Parser library version:** Bundled v5.2.0 from `WP-PHP-Parser-loader` generates PHP 8.5 deprecation warnings (`SplObjectStorage::attach()` deprecated). Suppressed in CLI script but library should be updated in future.
2. **Autoloader approach:** Works outside WordPress context using SPL autoloader with fallback paths (env var → dev path → dist path).
3. **Visitor pattern:** `ParentConnectingVisitor` is essential for determining function/method scope from return statements.
4. **Config-driven rules:** JSON config with `expected_keys` and `target_scopes` (with glob patterns) provides flexibility without code changes.

### Phase 2 Decision

**✅ PHP-Parser AST checking is viable for narrow, targeted rules in WPCC.**

- Can detect return array shapes and enforce expected keys.
- Outputs WPCC-compatible JSON findings.
- Stays Composer-free by bundling PHP-Parser library separately.
- Scope is appropriately limited (direct return statements only).

**Limitations confirmed:**

- Cannot track shapes through variable assignments (`$result = [...]; return $result;`).
- Cannot infer types or follow data flow.
- For deeper contract analysis, PHPStan remains the better tool.

**Next steps (Phase 3):**
- Wire into main WPCC scan pipeline behind feature flag.
- Update bundled PHP-Parser library to address deprecation warnings.
- Create synthetic test fixtures for CI.
- Document usage in README or recipes.

## Phase 3 – Hardening & Developer Experience
**Tasks**
- [ ] Decide which AST-based rules graduate from “experiment” to “default on”.
- [ ] Document how WPCC interacts with PHPStan in plugin repos (if at all).
- [ ] Add docs / recipes in `~/bin/ai-ddtk/recipes/` for:
  - [ ] Running PHPStan on a plugin with WPCC.
  - [ ] Enabling/disabling AST-based checks.
- [ ] Capture lessons learned to avoid future quagmires (what worked, what hurt).

## Risk / Quagmire Avoidance
- Keep PHPStan usage local to plugin repos, not bundled into WPCC.
- Keep PHP-Parser usage narrowly scoped (one or a few high-value rules).
- Regularly reassess: if a path starts requiring custom type inference or complex data flow, stop and reconsider before committing.

## LLM Notes
- When you complete or materially progress any task in this file, update the checklist(s) above rather than creating new documents.
- Do not expand this document into a full design spec; keep it as a high-level plan plus checklists and link out to more detailed docs in other files if needed.

## Appendix – PHPStan WordPress Setup Handoff

### Prerequisites
PHPStan and Composer are installed system-wide (for example via Homebrew):

```bash
phpstan --version  # e.g. PHPStan 2.1.38
composer --version # e.g. Composer 2.9.5
```

### Quick Setup for Any WordPress Plugin

1. **Install PHPStan and stubs in the plugin directory**

   ```bash
   cd /path/to/your-plugin

   composer require --dev \
     phpstan/phpstan \
     phpstan/extension-installer \
     szepeviktor/phpstan-wordpress \
     php-stubs/wordpress-stubs \
     php-stubs/woocommerce-stubs \
     php-stubs/wp-cli-stubs \
     --no-interaction
   ```

2. **Create `phpstan.neon` in the plugin root**

   ```neon
   parameters:
       level: 3
       paths:
           - includes
           - admin
           # Add your plugin's PHP directories
       tmpDir: build/phpstan
       bootstrapFiles:
           - vendor/php-stubs/wordpress-stubs/wordpress-stubs.php
           - vendor/php-stubs/woocommerce-stubs/woocommerce-stubs.php
           - vendor/php-stubs/wp-cli-stubs/wp-cli-stubs.php
       ignoreErrors:
           # Ignore plugin-specific constants (adjust pattern to match your plugin)
           - '#Constant YOUR_PLUGIN_\w+ not found#'
   ```

3. **Run analysis**

   ```bash
   phpstan analyse --configuration=phpstan.neon --memory-limit=1G
   ```

### Key Notes

| Item | Details |
|------|---------|
| **Extension installer** | `phpstan/extension-installer` will automatically load `szepeviktor/phpstan-wordpress` – no manual `includes:` is needed. |
| **Memory limit** | Use `--memory-limit=1G` for larger plugins (512M can be too low). |
| **Plugin constants** | Add an `ignoreErrors` regex for your plugin's constants (defined in the main plugin file). |
| **WP-CLI stubs** | Prefer `wp-cli-stubs.php` over `wp-cli-commands-stubs.php` to avoid extra Composer dependencies. |
| **Levels** | Start at level 3; increase towards 5+ as you fix issues. |

### Available Stubs

| Package | What it provides |
|---------|------------------|
| `php-stubs/wordpress-stubs` | Core WordPress functions, classes, and hooks. |
| `php-stubs/woocommerce-stubs` | `WC_Order`, `WC_Coupon`, `wc_get_order()`, and other WooCommerce symbols. |
| `php-stubs/wp-cli-stubs` | `WP_CLI` class and related methods. |

### Example Output

```text
 ------ ----------------------------------------------------------- 
  Line   includes/class-example.php                                
 ------ ----------------------------------------------------------- 
  :116   Variable $post in empty() always exists and is not falsy. 
 ------ ----------------------------------------------------------- 

 [ERROR] Found 1 error
```

===

### Layperson's assessment

## Plain-English Summary: PHP-Parser & PHPStan for WPCC

### What We Tested

We evaluated two tools to help catch bugs that WPCC's current "search for text patterns" approach can't find:

1. **PHPStan** — A mature, battle-tested code analyzer that understands PHP types and data shapes
2. **PHP-Parser** — A lower-level library that lets us build custom, targeted checks

---

### The Verdict

| Tool | Viability | Best For | Skill Level Required |
|------|-----------|----------|---------------------|
| **PHPStan** | ✅ High | Plugin developers who want thorough type checking | Intermediate+ (needs Composer, config file, understanding of type hints) |
| **PHP-Parser (our custom checker)** | ✅ Viable for narrow use | WPCC power users who want specific shape enforcement | Advanced (needs JSON config, understanding of what "array shape" means) |

---

### Will Average Developers Find This Useful?

**Honest answer: It depends.**

#### PHPStan (for plugin repos)
- **Junior developers:** Will see errors but may not understand what "array shape mismatch" or "nullable type" means without training
- **Mid-level developers:** Will benefit significantly — catches real bugs before they hit production
- **Senior developers:** Already know this is valuable; will adopt quickly

**Barrier to entry:** Requires Composer, a config file, and some understanding of PHP type annotations. Not plug-and-play.

#### Our PHP-Parser Checker (for WPCC)
- **Junior developers:** Probably too abstract — "why does my return array need specific keys?"
- **Mid-level developers:** Useful if they understand the contract between functions (e.g., "this Ajax endpoint must always return `customers`, `orders`, `guest_orders`")
- **Senior developers:** Will appreciate the targeted enforcement without needing a full static analyzer

**Barrier to entry:** Requires writing a JSON config that specifies expected keys and target functions. Not self-explanatory.

---

### What Problems Do These Actually Solve?

The original bug that motivated this work:

> A search function returned a flat list of customers, but the filter expecting it wanted a structured object with `customers`, `guest_orders`, and `orders` keys. The mismatch silently broke the feature.

| Tool | Can it catch this bug? | How? |
|------|------------------------|------|
| **WPCC (current)** | ❌ No | Text pattern matching can't understand data shapes |
| **PHPStan** | ✅ Yes, if types are documented | Add `@param array{customers: array, guest_orders: array, orders: array}` to the filter interface |
| **Our PHP-Parser checker** | ⚠️ Partially | Can verify return statements have expected keys, but can't trace data flow through variables |

---

### Feasibility for WPCC Integration

| Aspect | PHPStan | PHP-Parser Checker |
|--------|---------|-------------------|
| **Distribution** | ❌ Can't bundle (too heavy, needs Composer) | ✅ Can bundle (we control the code) |
| **Setup effort** | Medium (per-repo config) | Low (single CLI call) |
| **Maintenance** | Low (community-maintained) | Medium (we maintain it) |
| **False positives** | Low (mature tool) | Unknown (new, untested at scale) |
| **Coverage** | Broad (types, nullability, shapes, more) | Narrow (only direct return statements) |

---

### Recommendation

1. **For plugin developers:** Adopt PHPStan in your plugin repos. It's worth the setup cost. The Phase 1 findings show it catches real bugs with minimal noise once stubs are installed.

2. **For WPCC itself:** The PHP-Parser checker is a viable *optional* add-on for teams that want to enforce specific contracts. It should remain behind a feature flag and documented as "advanced usage."

3. **For broad adoption:** Neither tool is "install and forget" for beginners. Both require understanding *why* type safety matters. Consider adding a recipe or tutorial that explains the value proposition before diving into setup.

---

### Bottom Line

> **Can developers of all skill levels use this?**

Not out of the box. These tools reward developers who already understand:
- Why functions should have predictable return shapes
- What "nullable" means and why it matters
- How to read and write type annotations

For junior developers, the value comes *after* someone senior sets it up and explains what the errors mean. The tools themselves won't teach good practices — they enforce them.

====

Response #3
## Where Should PHPStan Live?

**Short answer: Per-project repo, not WPCC or AI-DDTK.**

Here's why:

---

### PHPStan's Nature

PHPStan needs to understand *your specific codebase*:
- Your classes, functions, and their type hints
- Your plugin's constants and globals
- Your dependencies (WooCommerce, WordPress, etc.)

This means it needs:
1. A `phpstan.neon` config file **in each project**
2. Composer dev-dependencies **in each project** (stubs, extensions)
3. A `vendor/` folder **in each project**

---

### What WPCC/AI-DDTK *Can* Provide

| Asset | Where It Belongs | Purpose |
|-------|------------------|---------|
| **Setup recipe/template** | AI-DDTK (`recipes/phpstan-wordpress-setup.md`) | Copy-paste instructions for new projects |
| **Template `phpstan.neon`** | AI-DDTK (`templates/phpstan.neon.template`) | Starting point config |
| **"Run PHPStan" wrapper script** | AI-DDTK or WPCC | Optional convenience script that checks if PHPStan is installed and runs it |
| **PHPStan itself** | Each project's `composer.json` | Must be per-project |

---

### Practical Integration Options

#### Option A: Recipe-Only (Recommended)
AI-DDTK provides documentation and templates. Developers copy them into their projects.

```
~/bin/ai-ddtk/
├── recipes/
│   └── phpstan-wordpress-setup.md    # Step-by-step guide
├── templates/
│   └── phpstan.neon.template         # Copy into project root
```

**Pros:** Simple, no maintenance burden, developers own their config
**Cons:** Manual setup per project

#### Option B: WPCC "PHPStan Check" Command
WPCC gains a `--phpstan` flag that:
1. Checks if `phpstan.neon` exists in target path
2. Checks if PHPStan is installed (globally or in project)
3. Runs PHPStan and merges findings into WPCC's JSON output

```bash
wpcc --paths /path/to/plugin --phpstan
```

**Pros:** Unified interface, findings in one report
**Cons:** WPCC now depends on external tool being installed; more complexity

#### Option C: AI-DDTK "Project Scaffolder"
AI-DDTK provides a script that sets up PHPStan in any WordPress plugin:

```bash
ai-ddtk scaffold phpstan /path/to/my-plugin
# Creates phpstan.neon, runs composer require --dev, etc.
```

**Pros:** One command to set up
**Cons:** Still requires Composer in the project; more code to maintain

---

### My Recommendation

**Start with Option A (Recipe-Only) in AI-DDTK.**

The Appendix you already have in `P1-PHP-PARSER.md` is essentially this recipe. Move it to:

```
~/bin/ai-ddtk/recipes/phpstan-wordpress-setup.md
```

Then, if you find yourself setting up PHPStan in 5+ projects and it's tedious, consider Option C (scaffolder).

PHPStan integration into WPCC itself (Option B) adds complexity for marginal benefit — developers who want PHPStan will run it directly; those who don't won't use the flag anyway.

---

### Summary

| Question | Answer |
|----------|--------|
| Can PHPStan be bundled into WPCC? | ❌ No — too heavy, needs Composer |
| Can PHPStan be bundled into AI-DDTK? | ❌ No — same reason |
| Should WPCC call PHPStan? | ⚠️ Maybe later, as optional flag |
| What should AI-DDTK provide? | ✅ Recipe + template config |
| Where does PHPStan actually run? | ✅ Each project's repo |

====

# WooCommerce Theme Integration

## PHPStan for WooCommerce-Heavy Themes: Yes, Very Useful

**Short answer: Yes — this is actually one of PHPStan's sweet spots.**

---

### Why WooCommerce Themes Benefit

WooCommerce themes are riddled with exactly the bugs PHPStan catches:

| Common Bug Pattern | Example | PHPStan Catches It? |
|-------------------|---------|---------------------|
| **Null order objects** | `$order = wc_get_order($id); echo $order->get_total();` — crashes if order doesn't exist | ✅ Yes (level 5+) |
| **Wrong product type** | Calling `->get_stock_quantity()` on a grouped product that doesn't support it | ✅ Yes |
| **Missing array keys** | `$settings['shipping_zone']` when key doesn't exist | ✅ Yes (level 3+) |
| **Hook callback signatures** | Filter expects 3 args, you only accept 2 | ✅ Yes |
| **Deprecated WC methods** | Using `$order->id` instead of `$order->get_id()` | ✅ Yes (with stubs) |

---

### Real-World Debugging Scenarios

#### Scenario 1: "Why does checkout randomly crash?"
```php
// Theme's checkout customization
$order = wc_get_order( $order_id );
$customer_name = $order->get_billing_first_name(); // 💥 Crashes if $order is false
```

PHPStan at level 5+ will flag: *"Cannot call method get_billing_first_name() on WC_Order|false"*

#### Scenario 2: "Product page shows wrong price sometimes"
```php
// Theme's price display override
$product = wc_get_product( $product_id );
$price = $product->get_sale_price(); // 💥 Variable products don't have direct sale price
```

PHPStan will flag the type mismatch if you're treating a `WC_Product_Variable` like a `WC_Product_Simple`.

#### Scenario 3: "Settings page loses values"
```php
$options = get_option( 'theme_wc_settings' );
$tax_display = $options['tax_display_mode']; // 💥 Key might not exist
```

PHPStan at level 3+ with array shapes will catch undefined keys.

---

### Setup for a WooCommerce Theme

Same as plugin setup, but scan theme directories:

```neon
# phpstan.neon in theme root
parameters:
    level: 3
    paths:
        - functions.php
        - inc
        - woocommerce          # WC template overrides
        - template-parts
    excludePaths:
        - vendor
        - node_modules
    tmpDir: build/phpstan
    bootstrapFiles:
        - vendor/php-stubs/wordpress-stubs/wordpress-stubs.php
        - vendor/php-stubs/woocommerce-stubs/woocommerce-stubs.php
```

Then:
```bash
composer require --dev phpstan/phpstan phpstan/extension-installer szepeviktor/phpstan-wordpress php-stubs/wordpress-stubs php-stubs/woocommerce-stubs
phpstan analyse --memory-limit=1G
```

---

### What to Expect

| Level | What You'll See | Noise Level |
|-------|-----------------|-------------|
| 1-2 | Basic errors (undefined classes, syntax issues) | Low |
| 3 | Array access issues, some type mismatches | Medium |
| 5 | Null safety issues (the gold for WC debugging) | Medium-High |
| 8 | Strict typing (probably too noisy for legacy themes) | High |

**Recommendation:** Start at level 3, fix those issues, then bump to level 5 for the null-safety wins.

---

### Caveats for Themes

1. **Template files are messy** — WooCommerce template overrides often use global variables (`$product`, `$order`) that PHPStan can't trace. You may need `@var` annotations:
   ```php
   /** @var WC_Product $product */
   global $product;
   ```

2. **Hook callbacks need type hints** — PHPStan works best when your functions have parameter types:
   ```php
   // Before (PHPStan can't help much)
   add_filter( 'woocommerce_cart_item_price', 'my_custom_price', 10, 3 );
   function my_custom_price( $price, $cart_item, $cart_item_key ) { ... }
   
   // After (PHPStan can validate)
   function my_custom_price( string $price, array $cart_item, string $cart_item_key ): string { ... }
   ```

3. **Legacy code = lots of initial errors** — A theme with years of WC customizations will likely show 50-200+ errors on first run. Use a baseline file to mute existing issues and only catch new ones:
   ```bash
   phpstan analyse --generate-baseline
   ```

---

### Bottom Line

| Question | Answer |
|----------|--------|
| Is PHPStan useful for WC themes? | ✅ Yes, very |
| What bugs will it find? | Null objects, wrong product types, missing array keys, deprecated methods |
| Is setup harder than for plugins? | Slightly (template globals are messier) |
| Worth the effort? | ✅ Yes, especially for themes with checkout/cart customizations |

Would you like me to create a recipe specifically for WooCommerce theme debugging in AI-DDTK?
