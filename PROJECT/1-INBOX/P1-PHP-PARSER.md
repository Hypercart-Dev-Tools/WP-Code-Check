# P1 – PHP Parser / Static Analysis Integration Plan
**Status:** Not Started · **Created:** 2026-02-03

## Table of Contents
- [Background](#background)
- [High-Level Phased Checklist](#high-level-phased-checklist)
- [Background & Goals](#background--goals)
- [Tooling Options Overview](#tooling-options-overview)
- [Recommended Tooling Choice](#recommended-tooling-choice)
- [Phase 0 – Spike & Decision](#phase-0--spike--decision)
- [Phase 1 – Local PHPStan Integration](#phase-1--local-phpstan-integration)
- [Phase 2 – PHP-Parser AST Experiments for WPCC](#phase-2--php-parser-ast-experiments-for-wpcc)
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
- [ ] Phase 2 – Implement first PHP-Parser-based AST rule inside WPCC
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
- [ ] Decide and document how PHP-Parser will be distributed for WPCC (e.g., bundle loader/helper into `dist/` and rely on `WP-PHP-Parser-loader` to manage `nikic/php-parser`, keeping WPCC itself Composer-free).
- [ ] Reuse or adapt `WP-PHP-Parser-loader` so WPCC can reliably load PHP-Parser in its own context.
- [ ] Mirror or borrow minimal harness patterns from KISS-woo-shipping-settings-debugger for walking ASTs and emitting JSON findings.
- [ ] Define a small JSON config format for this rule (e.g. function names and expected keys).
- [ ] Implement the `ajax-response-shape` rule end-to-end:
  - [ ] CLI entry point callable from WPCC.
  - [ ] JSON output format consistent with existing `findings` entries (id/severity/impact/file/line/message/code/context).
  - [ ] Wiring into the scan pipeline behind a feature flag.
- [ ] Measure performance impact and confirm it’s acceptable on medium-sized plugins.
 	- [ ] Create small synthetic fixtures for this rule (e.g., one "good" and one "bad" Ajax endpoint file plus expected `findings` JSON) so we can exercise AST feedback without depending on live IRL plugins, and keep the Woo Fast Search fixture at `temp/KISS-woo-fast-search` as the primary real-world reference.

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
