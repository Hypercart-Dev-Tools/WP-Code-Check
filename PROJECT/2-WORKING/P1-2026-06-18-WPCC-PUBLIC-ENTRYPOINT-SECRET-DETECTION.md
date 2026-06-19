---
Author: Noel (with Claude Code, Opus 4.8)
Date: 2026-06-18
Status: IN PROGRESS
Priority: P1
Goal: Close the WPCC detection gaps exposed by the KISS-woo-fast-search audit (issue #61) — publicly accessible PHP entrypoints, committed secrets, JS DOM-XSS, privilege simulation, and cross-method N+1 — and calibrate severity so inert dev scripts are not reported as live CRITICAL exploits.
Source: Empirical gap analysis. WPCC v-current scanned KISS-woo-fast-search and caught 0 of the 6 issues the human/AI audit flagged, as the actual issue.
---

## Status At A Glance

| Most Recently Completed Phase | What's Next |
|---|---|
| None — plan created 2026-06-18 | **Phase 1 — Scanner Hygiene & Calibration Foundation** |

---

## Table of Contents

- [Background](#background)
- [Gap Scorecard (why this plan exists)](#gap-scorecard)
- [Architecture Notes](#architecture-notes)
- [Phase 1 — Scanner Hygiene & Calibration Foundation](#phase-1)
- [Phase 2 — Direct-Access / Unauthenticated Entrypoint Detection](#phase-2)
- [Phase 3 — Secret & Local-Path Detection (PHP + JS)](#phase-3)
- [Phase 4 — JavaScript DOM-XSS Detection](#phase-4)
- [Phase 5 — Privilege Simulation & Cross-Method N+1](#phase-5)
- [Phase 6 — Severity Calibration & Documentation](#phase-6)
- [Out of Scope / Deferred](#out-of-scope)

---

## Background

The KISS-woo-fast-search audit (kissplugins issue #61) listed six problem classes. A controlled WPCC re-scan of the same plugin caught **none of them as the actual issue** — it emitted incidental `wpdb-query-no-prepare` / superglobal findings on 6 of the files for unrelated best-practice reasons, while the real vulnerability classes were invisible.

Two things this plan must fix:
1. **Coverage** — add the missing detectors.
2. **Calibration** — the audit itself overstated severity (it called inert, WP-CLI-only dev scripts "publicly accessible, escalates any visitor to admin"; in reality all 8 scripts fatal or exit on a normal prod host because they hardcode the developer's local macOS paths or never bootstrap WordPress). WPCC must avoid making the same mistake: report the right finding **and** the right severity.

---

## Gap Scorecard

| Audit finding | WPCC today | Target detector | Phase |
|---|---|---|---|
| 8 test/debug scripts web-reachable, no auth | ❌ no entrypoint check (no `ABSPATH` guard detection) | `php-direct-access-entrypoint` | 2 |
| `wp_set_current_user(1)` in a shipped script | ❌ none | `php-privilege-simulation` | 5 |
| Unauth coupon CSV export / data dump | ❌ only flagged `wpdb` prepare | covered by entrypoint + secret/export heuristics | 2, 3 |
| Real password in `debug-wholesale-orders.js` | ❌ no secret check; JS not scanned for secrets | `secret-hardcoded` (PHP+JS) | 3 |
| N+1 in `class-kiss-woo-order-formatter.php` | ❌ heuristic is single-function-scoped | `wc-n-plus-one-crossfn` | 5 |
| XSS: `order.total` unescaped in admin JS | ❌ no JS DOM-XSS check | `js-dom-xss` | 4 |
| (bonus) vendor/ scanned, false positives | ⚠️ scanned 1,217 files incl. `vendor/` | exclusion fix | 1 |
| (bonus) `line 3709: [: : integer expression expected` | ⚠️ runtime bash error during magic-string phase | bug fix | 1 |

---

## Architecture Notes

- Scanner entrypoint: `dist/bin/check-performance.sh` (~6,558 lines). Checks are largely inline.
- Findings are emitted via `add_json_finding "rule-id" "severity" "impact" "file" "line" "message" "code" [...]` (line ~1460).
- Check pass/fail rollups via `add_json_check "Name" "impact" "passed|failed" count` (line ~1596).
- Detection is validated against **test fixtures** (scan reports `fixture_validation`, currently 20 fixtures). **Every new rule in this plan ships with at least one positive and one negative fixture.**
- File discovery: `cached_grep` (line ~3440) / `fast_grep` (line ~3392) over a pre-cached PHP file list; JS handled via `OVERRIDE_GREP_INCLUDE` (lines ~3735–3786).
- Portable timeout wrapper: `run_with_timeout` (line ~1215). `MAX_SCAN_TIME` default 300s.

---

<a name="phase-1"></a>
## Phase 1 — Scanner Hygiene & Calibration Foundation

**Why first:** accuracy of every later phase depends on not scanning `vendor/` and on a clean run. This phase has no new detectors — it removes noise and fixes two known defects.

- [ ] Exclude `vendor/`, `node_modules/`, `dist/`, and build dirs from file discovery (confirm `EXCLUDE_FILES`/path-prune covers directories, not just `*.min.js`).
- [ ] Re-scan KISS-woo-fast-search; confirm `files_analyzed` drops from ~1,217 to the plugin's real count and **0 findings reference `vendor/`** (today it false-positives `php-shell-exec-functions` in `nikic/php-parser/.../ShellExec.php`).
- [ ] Fix `dist/bin/check-performance.sh:3709` `[: : integer expression expected` (guard the numeric comparison against empty/unset values in the magic-string detector).
- [ ] Add a `--include-vendor` opt-in flag for the rare case a user wants vendor scanned (default OFF).
- [ ] Document the fixture-authoring pattern (positive + negative) in `docs/` so Phases 2–5 follow one recipe.

### QA Checklist — Phase 1
- [ ] **Observability:** scan summary prints `files_analyzed` and an explicit `excluded_paths` count.
- [ ] **Regression:** full fixture suite still passes (≥20/20) after exclusion + bugfix.
- [ ] **No new stderr:** a scan of KISS-woo-fast-search produces zero `integer expression expected` lines on stderr.
- [ ] **DRY:** vendor/build exclusion lives in one place, reused by `cached_grep`, `fast_grep`, and JS override paths (not duplicated per check).
- [ ] **Determinism:** two consecutive scans of the same path yield identical `files_analyzed` and finding counts.

---

<a name="phase-2"></a>
## Phase 2 — Direct-Access / Unauthenticated Entrypoint Detection

**Highest-value detector.** A single rule catches all 8 KISS scripts. Flags any `.php` file that is web-reachable and lacks an `ABSPATH`/`WPINC` guard while doing real work (DB, output, side effects).

- [ ] New rule `php-direct-access-entrypoint`: a PHP file under a plugin/theme/mu-plugin root that **does not** contain `defined( 'ABSPATH' ) || exit` (or `if ( ! defined( 'ABSPATH' ) ) exit;`, `WPINC` guard, or a class-only file with no top-level side effects).
- [ ] Suppress on files that are pure class/function definitions with no top-level executable statements (autoloaded includes are not entrypoints).
- [ ] Raise impact when the unguarded file also: bootstraps WP (`require .../wp-load.php`), echoes/`print_r`s data, runs `$wpdb`, `fopen`/`fputcsv`, or calls `wp_set_current_user`.
- [ ] Detect committed data-export artifacts next to exporters (`*.csv`, `*.sql` dumps) and flag as potential exposed output.
- [ ] Fixtures: (+) script doing `$wpdb` work with no guard; (+) script with `require wp-load.php`; (−) class-only include; (−) file with proper `ABSPATH` guard.

### QA Checklist — Phase 2
- [ ] **Litmus (recall):** re-scan KISS-woo-fast-search → all 8 root scripts flagged by `php-direct-access-entrypoint`.
- [ ] **Litmus (precision):** scanning the plugin's legitimate `includes/` class files yields **no** entrypoint findings.
- [ ] **Observability:** each finding lists which escalators fired (wp-load / db / output / privilege).
- [ ] **No double-count:** a script already flagged here is not separately emitted as a generic superglobal/`wpdb` finding at higher severity (dedupe or cross-reference).
- [ ] **SOLID:** guard-detection logic is one function, reused, unit-fixtured.

---

<a name="phase-3"></a>
## Phase 3 — Secret & Local-Path Detection (PHP + JS)

Catches the committed password (the single most legitimately serious item in the audit) plus hardcoded emails and developer local paths. **Must scan `.js`, not just `.php`.**

- [ ] New rule `secret-hardcoded`: detect `password`/`passwd`/`pwd`/`secret`/`api[_-]?key`/`token`/`bearer` assigned a non-empty string literal, in `.php` **and** `.js/.ts`.
- [ ] Detect hardcoded developer filesystem paths: `/Users/<name>/`, `/home/<name>/`, `C:\\Users\\`, `...Local Sites/...` (info-leak + non-portability signal).
- [ ] Detect hardcoded personal/role emails used as defaults (`*@<domain>` in benchmark/query defaults).
- [ ] Entropy/format heuristics to cut false positives (skip obvious placeholders: `your_password_here`, `xxxx`, empty strings, `process.env.*`, `getenv(...)`).
- [ ] Note in the finding that committed secrets persist in git history (rotation, not just deletion, is required).
- [ ] Fixtures: (+) `password: 'RealLooking#Value1'` in JS; (+) `$api_key = 'sk-...'` in PHP; (+) `/Users/dev/Local Sites/...`; (−) `password: process.env.WP_PASS`; (−) `'your_api_key_here'`.

### QA Checklist — Phase 3
- [ ] **Litmus:** re-scan KISS → `debug-wholesale-orders.js` flagged for the committed password; the three hardcoded-email/path files flagged.
- [ ] **Precision:** no flags on `.env.example`-style placeholders or env-var reads.
- [ ] **Observability:** finding message states "rotate — present in git history" for secret hits.
- [ ] **Coverage proof:** a `.js`-only fixture directory produces secret findings (proves JS path works, not just PHP).
- [ ] **DRY:** PHP and JS share one secret-pattern table.

---

<a name="phase-4"></a>
## Phase 4 — JavaScript DOM-XSS Detection

Catches `order.total` rendered unescaped, and the more telling **inconsistent-escaping** signal (same field escaped elsewhere in the file).

- [ ] New rule `js-dom-xss`: sink (`.html(`, `.append(`, `.prepend(`, `.before(`, `.after(`, `innerHTML =`, `insertAdjacentHTML`) fed a concatenation containing an unescaped identifier (not wrapped in `escapeHtml`/`esc_html`/`textContent`/`DOMPurify`).
- [ ] Bonus signal `js-inconsistent-escape`: the same property (e.g. `order.total`) is escaped in one sink and not in another within the same file — high-confidence real bug.
- [ ] Respect existing `EXCLUDE_FILES` (skip `*.min.js`, bundles).
- [ ] Fixtures: (+) `$el.html('<td>' + order.total + '</td>')`; (+) `innerHTML = data.name`; (−) `$el.text(order.total)`; (−) `$el.html(escapeHtml(order.total))`.

### QA Checklist — Phase 4
- [ ] **Litmus:** re-scan KISS → `admin/kiss-woo-admin.js:132` flagged; line 597 (`escapeHtml(order.total...)`) **not** flagged.
- [ ] **Inconsistency catch:** the `order.total` escaped-vs-unescaped split in the same file raises `js-inconsistent-escape`.
- [ ] **Precision:** `.text()` / `textContent` sinks never flagged.
- [ ] **Observability:** finding shows the sink line and names the unescaped identifier.
- [ ] **Scope honesty:** if minified/bundled files are skipped, the scan log states how many JS files were skipped (no silent truncation).

---

<a name="phase-5"></a>
## Phase 5 — Privilege Simulation & Cross-Method N+1

Two heuristics that need light data-flow awareness.

- [ ] New rule `php-privilege-simulation`: `wp_set_current_user(` / `wp_set_auth_cookie(` / `grant_super_admin(` in a non-test runtime file (info: even in tests, flag if file is web-reachable per Phase 2).
- [ ] Extend N+1 detection `wc-n-plus-one-crossfn`: flag a per-item WC/meta call (`wc_get_order`, `get_post_meta`, `wc_get_product`) inside a method (e.g. `get_edit_url()`) that is itself invoked from a `foreach`/`while` over a result set in another method/file.
  - [ ] Minimum viable version: flag `wc_get_order($id)` inside a helper when an order object for `$id` was already loaded by the caller (redundant reload) — covers the KISS formatter case without full call-graph analysis.
- [ ] Fixtures: (+) `wp_set_current_user(1)` in a root script; (+) helper calling `wc_get_order` invoked inside a formatter loop; (−) `wc_get_order` called once outside any loop.

### QA Checklist — Phase 5
- [ ] **Litmus:** re-scan KISS → `test-wholesale-ajax.php:8` flagged for privilege simulation; `class-kiss-woo-order-formatter.php:115` flagged for cross-method N+1.
- [ ] **Precision:** legitimate single `wc_get_order()` calls and admin-context `wp_set_current_user` in genuine CLI tools are not over-flagged (severity calibrated, see Phase 6).
- [ ] **Observability:** N+1 finding names the calling loop site, not just the helper line.
- [ ] **Complexity guard:** cross-fn heuristic has a bounded search (no full-repo call graph); document the boundary and what it will miss.
- [ ] **False-negative honesty:** BACKLOG entry lists N+1 shapes still uncaught.

---

<a name="phase-6"></a>
## Phase 6 — Severity Calibration & Documentation

The audit's lesson: a finding is only useful if its severity is defensible. A WP-CLI script that hardcodes `/Users/dev/...wp-load.php` is **inert on a real prod host** — flag it (hygiene, git history, info-leak) but do not call it "CRITICAL: escalates any visitor to admin."

- [ ] Add bootstrap/portability awareness to Phase 2/5 findings: detect `Run with: wp eval-file`, hardcoded non-portable `require` paths, or missing WP bootstrap → annotate as `runtime: inert-on-standard-host (delete for hygiene)` vs `runtime: live-entrypoint`.
- [ ] Define a severity matrix: committed secret = HIGH (rotation); live unauth entrypoint w/ data output = HIGH/CRITICAL; inert dev script = MEDIUM (delete); local-path leak = LOW.
- [ ] Emit a one-line `runtime_assessment` per entrypoint finding so a triager sees exploitability, not just pattern presence.
- [ ] Update `CHANGELOG.md` (`[Unreleased]`) with all new rules.
- [ ] Update `PROJECT/2-WORKING/BACKLOG.md` with deferred items (full call-graph N+1, taint tracking, secret entropy tuning).
- [ ] Move this plan to `PROJECT/3-COMPLETED/` with a completion date when all phases land.
- [ ] Add the 6 KISS findings as permanent regression fixtures so this exact miss cannot recur.

### QA Checklist — Phase 6
- [ ] **Litmus:** the same KISS re-scan now reports all 6 classes with **defensible** severities (no inert script labeled CRITICAL exploit).
- [ ] **Docs in sync:** CHANGELOG, BACKLOG, and this plan all reflect shipped rules; check counts in the report match documented rules.
- [ ] **Regression lock:** KISS fixtures wired into the fixture suite; CI/`fixture_validation` count increases accordingly.
- [ ] **Self-audit:** run WPCC on WPCC's own repo — no new false positives introduced by the new rules.
- [ ] **Bottom-line:** a one-paragraph "what changed and what it now catches" summary is added to the report header or README.

---

<a name="out-of-scope"></a>
## Out of Scope / Deferred

- Full taint analysis / inter-procedural call-graph (Phase 5 uses bounded heuristics only).
- Secret scanning of git history (WPCC scans the working tree; history scanning is a separate tool — note in finding text, don't implement here).
- Auto-fixing / auto-deleting flagged files (report only).
- Framework-specific entrypoint conventions outside WordPress.

> **Note:** `PROJECT/2-WORKING/` is over its soft cap of 3 docs (per `DOCS-INSTRUCTIONS.md`). Consider moving a completed working doc to `3-COMPLETED/` before starting Phase 1.
