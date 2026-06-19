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
| **Phase 4 — JavaScript DOM-XSS Detection** (2026-06-19) | **Phase 5 — Privilege Simulation & Cross-Method N+1** |

### Progress Log

- **2026-06-19 — Phases 1–4 landed** on branch `rules/issue-61-detection-gaps` (3 commits):
  - `fe41e9c` **Stage A / Phase 1** — exclusion-leak fix (KISS `files_analyzed` 1207→25, 0 vendor findings), `[: : integer expression expected` bug fixed, JS/TS file-list cache + `js_cached_grep()` added (unblocks P3/P4), `runtime_assessment` field added to `add_json_finding`.
  - `4b6fbf3` **Phase 2** — `php-direct-access-entrypoint` rule with escalator detection + severity calibration (live-entrypoint / inert-on-standard-host / direct-access-candidate). 4 fixtures.
  - `f2f27fb` **Phases 3–4** — root-cause plumbing fix (JS/headless runner was `cached_grep` over the PHP-only list → JS patterns no-op'd in any mixed repo; now `js_cached_grep`). New rules `js-secret-literal` (HIGH), `dev-local-path-leak` (LOW), `js-dom-xss` (HIGH); `php-hardcoded-credentials.json` regex extended. 4 fixtures.
  - **Precision bug caught by scanning live KISS (not just fixtures):** the `grep -r` fallback (used when a file-list cache is unavailable — JS-only repos, restricted-temp CI, sandboxes where `mktemp` is denied) scanned *all* extensions and false-positived on `.md/.html/.py` audit clutter. Fixed with `JS_INCLUDE`/`PHP_INCLUDE` `--include` filters on all new helper calls.
  - **Verification:** full fixture suite **28/0** (`DEFAULT_FIXTURE_VALIDATION_COUNT` 20→28); per-fixture detection js-secret 2/2, js-dom-xss 2/2, dev-local-path php 1 (entrypoint correctly 0), js 1; KISS re-scan — new rules hit **only `.js`, zero non-source false positives**.
  - **Note:** KISS-woo-fast-search was fully remediated by its maintainer mid-effort (all 8 root scripts + JS password + unescaped `order.total` removed), so the **fixtures are the durable regression test**, not the moving live plugin.

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
- [Audit-Item Disposition (omission-diff vs #61)](#audit-disposition)
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
| Real password in `debug-wholesale-orders.js` | ⚠️ secret patterns exist (`dist/patterns/…`) but JS not scanned in mixed repos | extend patterns + JS file path | 1, 3 |
| N+1 in `class-kiss-woo-order-formatter.php` | ❌ heuristic is single-function-scoped | **AST track** (`P1-PHP-PARSER.md`) — not grep | 5→AST |
| XSS: `order.total` unescaped in admin JS | ❌ no JS DOM-XSS check (and JS not scanned in mixed repos) | `js-dom-xss` + JS file path | 1, 4 |
| (bonus) vendor/ scanned, false positives | ⚠️ exclusion exists (`EXCLUDE_DIRS`, line 146) but **leaks** | exclusion leak fix | 1 |
| (bonus) `line 3709: [: : integer expression expected` | ⚠️ runtime bash error during magic-string phase | bug fix | 1 |

---

## Architecture Notes

- Scanner entrypoint: `dist/bin/check-performance.sh` (~6,558 lines). Checks are largely inline.
- Findings are emitted via `add_json_finding "rule-id" "severity" "impact" "file" "line" "message" "code" [...]` (line ~1460).
- Check pass/fail rollups via `add_json_check "Name" "impact" "passed|failed" count` (line ~1596).
- Detection is validated against **test fixtures** (scan reports `fixture_validation`, currently 20 fixtures). **Every new rule in this plan ships with at least one positive and one negative fixture.**
- File discovery: `cached_grep` (line ~3440) / `fast_grep` (line ~3392) over a pre-cached **PHP-only** file list; it falls back to recursive `grep -r` **only for JS-only projects**. **Consequence (Codex r1):** in a *mixed* PHP+JS repo the JS files are not reliably fed to JS-capable checks — `OVERRIDE_GREP_INCLUDE` (lines ~3735–3786) is not sufficient alone. This is the root cause behind the missed JS password and JS XSS, and a hard prerequisite for Phases 3–4.
- **Existing infra to extend, not rebuild (Codex r1):** vendor/build exclusion already exists — `EXCLUDE_DIRS="vendor node_modules .git tests .next dist build"` (line 146) — yet the KISS scan still pulled 1,217 files incl. `vendor/`, so Phase 1 is a *leak fix*, not a new exclusion. Secret detection already has pattern files: `dist/patterns/php-hardcoded-credentials.json` and `dist/patterns/headless/api-key-exposure.json` — Phase 3 extends these.
- `add_json_finding` has a **fixed positional field set** (rule-id, severity, impact, file, line, message, code, guards, sanitizers, guarded, sanitized) — **there is no `runtime_assessment` field**; Phase 6 must define how it is emitted.
- A completed **AST/PHPStan track** exists (`PROJECT/3-COMPLETED/P1-PHP-PARSER.md`) — interprocedural / nullability / unresolved-symbol analysis belongs there, not in grep. Phase 5's cross-method N+1 is routed to it.
- Portable timeout wrapper: `run_with_timeout` (line ~1215). `MAX_SCAN_TIME` default 300s.

---

<a name="phase-1"></a>
## Phase 1 — Scanner Hygiene & Calibration Foundation

**Why first:** accuracy of every later phase depends on not scanning `vendor/` and on a clean run. This phase has no new detectors — it removes noise and fixes two known defects.

- [x] **Fix the exclusion *leak*, don't "add" exclusion (Codex r1):** `EXCLUDE_DIRS` already lists `vendor node_modules .git tests .next dist build` (line 146) yet the KISS scan pulled 1,217 files incl. `vendor/`. Trace which scan path bypasses `GREP_EXCLUSIONS` (line ~1008) and close it so exclusion holds across `cached_grep`, `fast_grep`, **and** the JS override paths.
- [x] **Establish a JS/TS file path for mixed repos (Codex r1):** add a JS/TS file cache or a forced recursive scan for non-PHP checks, because `cached_grep` uses a PHP-only list (see Architecture Notes). **Hard prerequisite for Phases 3–4** — without it, JS detectors silently never run in PHP+JS repos.
- [x] Re-scan KISS-woo-fast-search; confirm `files_analyzed` drops from ~1,217 to the plugin's real count and **0 findings reference `vendor/`** (today it false-positives `php-shell-exec-functions` in `nikic/php-parser/.../ShellExec.php`).
- [x] Fix `dist/bin/check-performance.sh:3709` `[: : integer expression expected` (guard the numeric comparison against empty/unset values in the magic-string detector).
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

**Highest-value detector.** A single rule catches all 8 KISS scripts. Flags any `.php` file that is a **likely direct-access candidate** — lacks an `ABSPATH`/`WPINC` guard while doing real work (DB, output, side effects). **NB (Codex r1):** grep can prove *missing guard + top-level side effects*, **not** actual webserver/route reachability — the rule id, messages, and QA all say **"candidate,"** never "proven reachable."

- [x] New rule `php-direct-access-entrypoint`: a PHP file under a plugin/theme/mu-plugin root that **does not** contain `defined( 'ABSPATH' ) || exit` (or `if ( ! defined( 'ABSPATH' ) ) exit;`, `WPINC` guard, or a class-only file with no top-level side effects).
- [x] Suppress on files that are pure class/function definitions with no top-level executable statements (autoloaded includes are not entrypoints).
- [x] Raise impact when the unguarded file also: bootstraps WP (`require .../wp-load.php`), echoes/`print_r`s data, runs `$wpdb`, `fopen`/`fputcsv`, or calls `wp_set_current_user`.
- [ ] Detect committed data-export artifacts next to exporters (`*.csv`, `*.sql` dumps) and flag as potential exposed output.
- [x] Fixtures: (+) script doing `$wpdb` work with no guard; (+) script with `require wp-load.php`; (−) class-only include; (−) file with proper `ABSPATH` guard.

### QA Checklist — Phase 2
- [ ] **Litmus (recall):** re-scan KISS-woo-fast-search → all 8 root scripts flagged by `php-direct-access-entrypoint`.
- [ ] **Litmus (precision):** scanning the plugin's legitimate `includes/` class files yields **no** entrypoint findings.
- [ ] **Observability:** each finding lists which escalators fired (wp-load / db / output / privilege).
- [ ] **No double-count:** a script already flagged here is not separately emitted as a generic superglobal/`wpdb` finding at higher severity (dedupe or cross-reference).
- [ ] **SOLID:** guard-detection logic is one function, reused, unit-fixtured.

---

<a name="phase-3"></a>
## Phase 3 — Secret & Local-Path Detection (PHP + JS)

Catches the committed password (the single most legitimately serious item in the audit) plus hardcoded emails and developer local paths. **Must scan `.js`, not just `.php` — which depends on the Phase 1 JS file path.**

- [x] **Extend the existing detectors, don't rebuild (Codex r1):** `dist/patterns/php-hardcoded-credentials.json` and `dist/patterns/headless/api-key-exposure.json` already exist. Add `password`/`passwd`/`pwd`/`secret`/`token`/`bearer` literal coverage and confirm they actually execute on `.js/.ts` files in a mixed repo (blocked on Phase 1 — this is *why* the JS password was missed, not "no check exists").
- [x] Detect hardcoded developer filesystem paths: `/Users/<name>/`, `/home/<name>/`, `C:\\Users\\`, `...Local Sites/...` (info-leak + non-portability signal).
- [ ] Detect hardcoded personal/role emails used as defaults (`*@<domain>` in benchmark/query defaults).
- [x] Entropy/format heuristics to cut false positives (skip obvious placeholders: `your_password_here`, `xxxx`, empty strings, `process.env.*`, `getenv(...)`).
- [x] Note in the finding that committed secrets persist in git history (rotation, not just deletion, is required).
- [x] Fixtures: (+) `password: 'RealLooking#Value1'` in JS; (+) `$api_key = 'sk-...'` in PHP; (+) `/Users/dev/Local Sites/...`; (−) `password: process.env.WP_PASS`; (−) `'your_api_key_here'`.

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

**Depends on Phase 1's JS file path (Codex r1)** — DOM-XSS detection cannot fire if mixed-repo JS files never reach the check.

- [x] New rule `js-dom-xss`: sink (`.html(`, `.append(`, `.prepend(`, `.before(`, `.after(`, `innerHTML =`, `insertAdjacentHTML`) fed a concatenation containing an unescaped identifier (not wrapped in `escapeHtml`/`esc_html`/`textContent`/`DOMPurify`).
- [ ] Bonus signal `js-inconsistent-escape`: the same property (e.g. `order.total`) is escaped in one sink and not in another within the same file — high-confidence real bug.
- [x] Respect existing `EXCLUDE_FILES` (skip `*.min.js`, bundles).
- [x] Fixtures: (+) `$el.html('<td>' + order.total + '</td>')`; (+) `innerHTML = data.name`; (−) `$el.text(order.total)`; (−) `$el.html(escapeHtml(order.total))`.

### QA Checklist — Phase 4
- [ ] **Litmus:** re-scan KISS → `admin/kiss-woo-admin.js:132` flagged; line 597 (`escapeHtml(order.total...)`) **not** flagged.
- [ ] **Inconsistency catch:** the `order.total` escaped-vs-unescaped split in the same file raises `js-inconsistent-escape`.
- [ ] **Precision:** `.text()` / `textContent` sinks never flagged.
- [ ] **Observability:** finding shows the sink line and names the unescaped identifier.
- [ ] **Scope honesty:** if minified/bundled files are skipped, the scan log states how many JS files were skipped (no silent truncation).

---

<a name="phase-5"></a>
## Phase 5 — Privilege Simulation & Cross-Method N+1

One heuristic ships in grep (privilege simulation); cross-method N+1 is **routed to the AST track** (Codex r1).

- [ ] New rule `php-privilege-simulation`: `wp_set_current_user(` / `wp_set_auth_cookie(` / `grant_super_admin(` in a non-test runtime file (info: even in tests, flag if file is a direct-access candidate per Phase 2).
- [ ] **Route cross-method N+1 to the AST/PHPStan track (Codex r1):** `PROJECT/3-COMPLETED/P1-PHP-PARSER.md`, **not** grep. The current WC N+1 rule (`dist/bin/check-performance.sh:~5678-5726`) only inspects same-file loop windows; interprocedural call chains (helper → loop in another method/file) are outside grep's reach. Add a BACKLOG item under that track.
- [ ] **Grep-track scope stays narrow:** privilege simulation + at most **same-*method* redundant reloads** (e.g. `wc_get_order($id)` when an order for `$id` is already in scope in the same function). Do **not** attempt cross-file call-graph in bash.
- [ ] Fixtures (grep track): (+) `wp_set_current_user(1)` in a root script; (+) `wc_get_order($id)` reloaded when `$id`'s order is already in scope in the **same function**; (−) `wc_get_order` called once outside any loop. The **helper-in-loop / interprocedural** case is an **AST-track backlog fixture** (`P1-PHP-PARSER.md`), not a grep fixture.

### QA Checklist — Phase 5
- [ ] **Litmus (grep track):** re-scan KISS → `test-wholesale-ajax.php:8` flagged for privilege simulation. (Cross-method N+1 in `class-kiss-woo-order-formatter.php:115` is verified on the **AST track**, not here.)
- [ ] **Precision:** legitimate single `wc_get_order()` calls and admin-context `wp_set_current_user` in genuine CLI tools are not over-flagged (severity calibrated, see Phase 6).
- [ ] **Scope honesty:** the grep track makes no cross-file N+1 claim; the routed AST item is linked from BACKLOG.
- [ ] **False-negative honesty:** BACKLOG entry lists N+1 shapes still uncaught and which track owns them.

---

<a name="phase-6"></a>
## Phase 6 — Severity Calibration & Documentation

The audit's lesson: a finding is only useful if its severity is defensible. A WP-CLI script that hardcodes `/Users/dev/...wp-load.php` is **inert on a real prod host** — flag it (hygiene, git history, info-leak) but do not call it "CRITICAL: escalates any visitor to admin."

- [ ] Add bootstrap/portability awareness to Phase 2/5 findings: detect `Run with: wp eval-file`, hardcoded non-portable `require` paths, or missing WP bootstrap → annotate as `runtime: inert-on-standard-host (delete for hygiene)` vs `runtime: live-entrypoint`.
- [ ] Define a severity matrix: committed secret = HIGH (rotation); live unauth entrypoint w/ data output = HIGH/CRITICAL; inert dev script = MEDIUM (delete); local-path leak = LOW.
- [ ] Define the `runtime_assessment` **output contract (Codex r1 — `add_json_finding` has a fixed field set with no such field):** either (a) add a new optional positional arg + JSON key to `add_json_finding` **and** update the HTML/markdown report renderers and any downstream triage consumers, or (b) fold it into the existing `message` string. Default to (a) for machine-readability; enumerate the downstream changes it requires.
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

<a name="audit-disposition"></a>
## Audit-Item Disposition (omission-diff vs #61)

Codex r1 flagged that three audit items were named in the relay but given no home. Every issue #61 finding now has an explicit disposition:

| Issue #61 item | Disposition |
|---|---|
| 8 public scripts / no auth | **This plan** — Phase 2 |
| `wp_set_current_user(1)` | **This plan** — Phase 5 |
| Committed secret / emails / local paths | **This plan** — Phase 3 (extends existing patterns) |
| JS DOM-XSS (`order.total`) | **This plan** — Phase 4 (+ Phase 1 JS path) |
| N+1 in order formatter | **AST track** (`P1-PHP-PARSER.md`) — routed out of grep |
| HPOS query missing `o.type = 'shop_order'` | **Plugin-fix-only** by default; an *optional* narrow SQL alias-misuse heuristic is the author's call — **not** committed here |
| `$parts[0]` access w/o empty-array guard | **Plugin-fix-only** — array-bounds is an AST/PHPStan concern, not a grep rule |
| Toolbar `floatingSearchBar` null-guard | **Plugin-fix-only** — JS null-deref is out of WPCC's current scope |
| Pagination dead handler / undefined fn | **Plugin-fix-only** — unresolved-symbol analysis is out of scope (AST track candidate) |

---

<a name="out-of-scope"></a>
## Out of Scope / Deferred

- Full taint analysis / inter-procedural call-graph (Phase 5 uses bounded heuristics only).
- Secret scanning of git history (WPCC scans the working tree; history scanning is a separate tool — note in finding text, don't implement here).
- Auto-fixing / auto-deleting flagged files (report only).
- Framework-specific entrypoint conventions outside WordPress.

### Deferred during Phases 1–4 implementation (2026-06-19)

Items in the Phase 1–4 checklists that were intentionally **not** shipped (left unchecked above), with rationale — these are the active follow-ups (BACKLOG.md is deprecated; track them here):

- **`js-inconsistent-escape`** (Phase 4 bonus): same property escaped in one sink, unescaped in another within a file. Deferred — needs cross-line same-file state; `js-dom-xss` already catches the unescaped sink directly.
- **Inline-JS-in-PHP DOM-XSS**: `js-dom-xss` is scoped to `.js/.ts` files, so `.html(... + ...)` inside `<script>` blocks in `.php` (e.g. KISS `class-kiss-woo-self-test.php`) is not flagged. Belongs on a PHP-aware / AST track that can extract embedded JS.
- **DOM-XSS i18n precision tuning**: `js-dom-xss` flags all concatenation-into-HTML sinks (7 on live KISS, several building UI from i18n/static strings). Defensible as "review" findings, but an allow-list for purely-i18n/static concatenation would cut noise. Severity stays HIGH with hedged messaging for now.
- **Hardcoded personal/role email detection** (Phase 3): `*@<domain>` defaults in benchmark/query code. Deferred — narrower value than secrets/paths; revisit if it recurs in audits.
- **Committed data-export artifact detection** (Phase 2): flag `*.csv`/`*.sql` dumps committed next to exporters. Deferred — file-presence heuristic, separable from the entrypoint rule.
- **`--include-vendor` opt-in flag** + **fixture-authoring doc in `docs/`** (Phase 1): polish; not blocking detection.
- **`mktemp` / restricted-temp cache degradation** (cross-cutting, pre-existing): when `mktemp` is denied (hardened servers, some CI sandboxes) both the PHP and JS file-list caches come back empty and every check falls back to recursive `grep -r`. Correct (exclusions + the new `--include` filters hold) but slower. Pre-existing — affects the PHP cache too — so out of scope for issue #61; worth a dedicated hardening pass (honor `$TMPDIR` in the mktemp templates).

> **Note:** `PROJECT/2-WORKING/` is over its soft cap of 3 docs (per `DOCS-INSTRUCTIONS.md`). Consider moving a completed working doc to `3-COMPLETED/` before starting Phase 1.
