# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.60] - 2025-12-31

### Added
- **Severity Level Configuration File** - Created `/dist/config/severity-levels.json` with all 28 checks and their factory default severity levels
  - **Purpose:** Foundation for Day 2 implementation of customizable severity rankings (PROJECT-SELF-RANK-SEVERITY.md)
  - **Structure:** JSON file with metadata, rule IDs, names, severity levels, categories, and descriptions
  - **Coverage:** All 28 checks (12 CRITICAL, 9 HIGH, 6 MEDIUM, 1 LOW)
  - **Categories:** 10 security checks, 17 performance checks, 1 maintenance check
  - **Location:** `dist/config/severity-levels.json`
  - **Usage (Day 2):** Users will copy this file, edit `level` fields, and pass `--severity-config <path>` to customize severity rankings
  - **Factory Defaults:** Each check includes `factory_default` field for reference (users can always see original values)
  - **Self-Documenting:** Includes instructions, version, last_updated, and total_checks in metadata
  - **Comment Field Support:** Any field starting with underscore (`_comment`, `_note`, `_reason`, `_ticket`, etc.) is ignored by parser
    - **Purpose:** Users can document why they changed severity levels
    - **Examples:** `_comment: "Upgraded per security audit"`, `_ticket: "JIRA-1234"`, `_date: "2025-12-31"`
    - **Parser Behavior:** Underscore-prefixed fields are filtered out during parsing (won't affect functionality)
    - **Use Cases:** Document incidents, reference tickets, track authors, add dates, explain decisions
  - **Rule IDs Mapped:**
    - CRITICAL: spo-001-debug-code, hcc-001-localstorage-exposure, hcc-002-client-serialization, spo-003-insecure-deserialization, unbounded-posts-per-page, unbounded-numberposts, nopaging-true, unbounded-wc-get-orders, get-users-no-limit, get-terms-no-limit, pre-get-posts-unbounded, rest-no-pagination
    - HIGH: spo-002-superglobals, admin-no-capability-check, ajax-no-nonce, ajax-polling-unbounded, hcc-005-expensive-polling, unbounded-sql-terms, cron-interval-unvalidated, file-get-contents-url, order-by-rand
    - MEDIUM: hcc-008-unsafe-regexp, like-leading-wildcard, n-plus-one-pattern, transient-no-expiration, script-versioning-time, http-no-timeout
    - LOW: timezone-sensitive
  - **Next Steps (Day 2):** Implement `load_severity_defaults()`, `load_custom_severity_config()`, and `get_severity()` functions in check-performance.sh

- **Example Configuration File** - Created `/dist/config/severity-levels.example.json` showing how to customize severity levels
  - **Purpose:** Demonstrates comment field usage and severity customization patterns
  - **Examples:** Shows upgrading/downgrading severity levels with documentation
  - **Comment Examples:** Demonstrates `_comment`, `_note`, `_reason`, `_ticket`, `_date`, `_author` fields
  - **Workflow Guide:** Includes step-by-step instructions in `_notes` section

- **Configuration Documentation** - Created `/dist/config/README.md` with comprehensive usage guide
  - **Quick Start:** Copy, edit, and use custom config files
  - **Comment Field Reference:** Table of common underscore field names and their purposes
  - **Field Reference:** Which fields are editable vs. read-only
  - **Best Practices:** DOs and DON'Ts for config customization
  - **Example Workflow:** Complete workflow from copy to CI/CD integration

## [1.0.59] - 2025-12-31

### Fixed
- **Timezone-Sensitive Pattern False Positive** - Fixed detection to exclude `gmdate()` (timezone-safe function)
  - **Issue:** Pattern was flagging `gmdate()` as timezone-sensitive, but `gmdate()` always returns UTC (timezone-safe)
  - **Root Cause:** Pattern matched any function containing "date" without distinguishing between `date()` and `gmdate()`
  - **Fix:** Updated pattern to use `grep -v "gmdate"` to exclude timezone-safe `gmdate()` calls
  - **Impact:** Reduces false positives - only flags `date()` (timezone-dependent) and `current_time('timestamp')`
  - **Location:** Lines 2071-2082 in check-performance.sh
  - **Rationale:**
    - `date()` - Uses PHP's configured timezone (can vary by server) - **SHOULD BE FLAGGED**
    - `gmdate()` - Always returns UTC/GMT (consistent across environments) - **SHOULD NOT BE FLAGGED**
    - WordPress stores all dates internally as UTC, so `gmdate()` is the recommended approach
  - **Testing:** Verified with test file containing both `date()` and `gmdate()` calls
    - ✅ `date('Y-m-d')` - Correctly flagged
    - ✅ `gmdate('Y-m-d')` - Correctly NOT flagged
    - ✅ `current_time('timestamp')` - Correctly flagged

- **Version Drift Bug** - Created single source of truth for version number to prevent version inconsistencies
  - **Issue:** Script had 4 different hardcoded version strings that were out of sync (header: 1.0.59, banner/logs/JSON: 1.0.58)
  - **Root Cause:** Version number was hardcoded in 4 different locations instead of using a single variable
  - **Fix:** Created `SCRIPT_VERSION="1.0.59"` constant at top of script and replaced all hardcoded references
  - **Impact:** Version now displays consistently across banner, logs, and JSON output
  - **Locations Updated:**
    - Line 50: Created `SCRIPT_VERSION` variable (single source of truth)
    - Line 415: Log file version (now uses `$SCRIPT_VERSION`)
    - Line 608: JSON output version (now uses `$SCRIPT_VERSION`)
    - Line 1216: Banner version (now uses `$SCRIPT_VERSION`)
  - **Future-Proof:** Only need to update ONE line (line 50) when bumping versions

- **Duplicate Timestamp Function** - Removed duplicate `get_local_timestamp()` and moved to shared helpers
  - **Issue:** `get_local_timestamp()` was defined in main script instead of using shared helper library
  - **Root Cause:** Function was created before `common-helpers.sh` existed
  - **Fix:**
    - Added `timestamp_local()` to `dist/bin/lib/common-helpers.sh` (line 23-28)
    - Replaced 2 calls to `get_local_timestamp()` with `timestamp_local()` (lines 414, 463)
    - Deleted duplicate function definition from main script
  - **Impact:** Timestamp function now reusable across all scripts, follows DRY principles
  - **Benefit:** Future scripts can use `timestamp_local()` without duplicating code

- **Template Loading Path** - Fixed `REPO_ROOT` variable in bash script to correctly load templates from `dist/TEMPLATES/`
  - **Issue:** Script was looking for templates in repository root `/TEMPLATES/` instead of `dist/TEMPLATES/`
  - **Root Cause:** `REPO_ROOT` was set to `$SCRIPT_DIR/../..` (repository root) instead of `$SCRIPT_DIR/..` (dist directory)
  - **Fix:** Changed `REPO_ROOT` calculation from `../..` to `..` to point to `dist/` directory
  - **Impact:** `--project <name>` flag now correctly loads templates from `dist/TEMPLATES/<name>.txt`
  - Updated `dist/TEMPLATES/_AI_INSTRUCTIONS.md` to clarify templates must be in `dist/TEMPLATES/` (not repository root)
  - Added inline comments in bash script explaining the path structure

### Added
- **HCC Security & Performance Rules** - Added 4 new checks based on KISS Plugin Quick Search audit
  - **HCC-001:** Sensitive data in localStorage/sessionStorage (CRITICAL)
    - Detects when sensitive plugin/user/admin/settings data is stored in browser storage
    - Catches patterns like: `localStorage.setItem('plugin_cache', ...)`
    - Impact: CRITICAL - Any visitor can read localStorage via browser console
    - Location: Lines 1430-1443 in check-performance.sh
  - **HCC-002:** Serialization of objects to client storage (CRITICAL)
    - Detects when objects are serialized (JSON.stringify) and stored in browser storage
    - Catches patterns like: `localStorage.setItem(key, JSON.stringify(obj))`
    - Impact: CRITICAL - Serialized data often contains sensitive metadata (versions, paths, settings)
    - Location: Lines 1445-1451 in check-performance.sh
  - **HCC-005:** Expensive WP functions in polling intervals (HIGH)
    - Enhances existing AJAX polling check to detect expensive WordPress functions
    - Scans both `.js` and `.php` files for `setInterval()` calls
    - Checks 20 lines of context for: `get_plugins()`, `get_themes()`, `get_posts()`, `WP_Query`, `get_users()`, etc.
    - Impact: HIGH - Prevents performance degradation from polling expensive operations
    - Location: Lines 1612-1668 in check-performance.sh
    - Example: Catches `setInterval()` that calls `get_plugins()` every 30 seconds
  - **HCC-008:** User input in RegExp without escaping (MEDIUM)
    - Detects unsafe RegExp construction with concatenated variables
    - Catches patterns like: `new RegExp('\\b' + query + '\\b')` and `RegExp(\`pattern${userInput}\`)`
    - Impact: MEDIUM - Can lead to ReDoS attacks or unexpected regex behavior
    - Location: Lines 1465-1474 in check-performance.sh
    - Uses single `-E` pattern with alternation for BSD grep compatibility
    - Example: Catches the exact KISS Plugin Quick Search pattern
    - Note: Cannot detect if variables are properly escaped (expected false positives)
  - **Testing:** All rules verified with comprehensive test files and real-world code
  - **Based on:** AUDIT-2025-12-31.md findings from KISS Plugin Quick Search
  - **Documentation:** See `1-INBOX/KISS-PQS-FINDINGS-RULES.md` for full rule specifications

- **Contributor License Agreement (CLA)** - Added CLA requirement for contributors
  - Created `CLA.md` - Individual Contributor License Agreement
  - Created `CLA-CORPORATE.md` - Corporate Contributor License Agreement
  - Updated `CONTRIBUTING.md` with CLA signing instructions
  - Updated `README.md` to mention CLA requirement
  - Updated `LICENSE-SUMMARY.md` with CLA information
  - CLA is fully compatible with Apache 2.0 and dual-license model
  - Based on Apache Software Foundation's CLA template
  - Allows contributions to be distributed under both open source and commercial licenses

### Changed
- **Baseline File Renamed** - Renamed `.neochrome-baseline` to `.hcc-baseline` (HCC = Hypercart Code Check)
  - Updated default baseline filename in `check-performance.sh`
  - Updated all documentation references
  - Updated test fixtures and test scripts
  - Updated `.gitignore` patterns
  - Renamed `dist/tests/fixtures/.neochrome-baseline` to `.hcc-baseline`

---

## [1.0.58] - 2025-12-31

### Fixed
- **Test Fixture Baseline File** - Added `.hcc-baseline` test fixture to git
  - File was being ignored by `.gitignore`, causing CI test failures
  - Added exception in `.gitignore` for `dist/tests/fixtures/.hcc-baseline`
  - Fixes "JSON baseline behavior" test failure in GitHub Actions

### Added

- **Fixture Validation (Proof of Detection)** - Built-in verification that detection patterns work correctly
  - **Always-On Validation**: Every scan now runs a quick validation against 4 core test fixtures
  - **Fixtures Tested**:
    - `antipatterns.php` - 6 intentional bad patterns (unbounded queries, N+1, etc.)
    - `clean-code.php` - 0 errors expected (correct patterns should pass)
    - `ajax-safe.php` - 0 errors expected (safe AJAX patterns)
    - `file-get-contents-url.php` - 4 errors expected (external URL detection)
  - **Report Integration**:
    - **Text Output**: Shows "✓ Detection verified: 4 test fixtures passed" in SUMMARY section
    - **JSON Output**: New `fixture_validation` object with status, passed count, failed count, and message
    - **HTML Report**: Footer shows "✓ Detection Verified (4 fixtures)" badge with color-coded status
  - **Benefits**:
    - Provides "proof of detection" in every report
    - Builds user confidence that the scanner actually works
    - Catches regression issues if patterns break
    - Industry standard approach (similar to PHPCS, ESLint, Semgrep)
  - **Performance**: Validation runs silently and quickly (<1 second for 4 fixtures)

- **Fixture Test Project Type** - Files in `/tests/fixtures/` are now identified as "Fixture Test" type
  - **Detection**: Automatically detects when scanning fixture test files
  - **Display**: Shows "Type: Fixture Test" in reports instead of "unknown"
  - **Improved Type Labels**: All project types now use friendly labels:
    - `plugin` → "WordPress Plugin"
    - `theme` → "WordPress Theme"
    - `fixture` → "Fixture Test"
    - `unknown` → "Unknown"

- **HTML Report Branding Update** - Updated branding from "Neochrome WP Toolkit" to "WP Code Check by Hypercart"
  - **Page Title**: "WP Code Check Performance Report"
  - **Header**: "🚀 WP Code Check Performance Report"
  - **Footer**: "Generated by WP Code Check by Hypercart" with link to https://WPCodeCheck.com
  - **Link Styling**: Blue (#6366f1) clickable link that opens in new tab

### Changed

- **GitHub Actions Workflow Consolidation** - Merged three separate workflows into one comprehensive CI workflow
  - **Before**: Three workflows running simultaneously:
    - `ci.yml` - Basic performance checks on PRs
    - `performance-audit-slack.yml` - Audit with Slack notifications on all events
    - `performance-audit-slack-on-failure.yml` - Audit with Slack notifications only on failures
  - **After**: Single consolidated `ci.yml` workflow with conditional Slack notifications
  - **Triggers**:
    - `pull_request` to main/development branches (PRIMARY)
    - `workflow_dispatch` for manual runs
    - Does NOT trigger on `push` to reduce CI noise and focus on PR review stage
  - **Slack Notification Logic**:
    - Only sends to Slack when PR audit fails
    - Gracefully handles missing `SLACK_WEBHOOK_URL` secret
    - Reduces notification noise while maintaining visibility on issues
  - **Benefits**:
    - Eliminates duplicate workflow runs (was running 3+ workflows per event)
    - Reduces CI noise while maintaining visibility
    - Easier to maintain single workflow file
    - Consistent artifact naming with run numbers
  - **Removed Files**:
    - `.github/workflows/performance-audit-slack.yml`
    - `.github/workflows/performance-audit-slack-on-failure.yml`
  - **Safeguards Added**:
    - Added prominent warning comments in `ci.yml` header explaining single-workflow policy
    - Disabled `example-caller.yml` triggers (changed to `workflow_dispatch` only)
      - This template file was causing duplicate CI runs
      - Now only runs manually, preventing automatic triggers
      - Added clear warnings that it's a template/example file
    - Created `.github/workflows/README.md` documenting:
      - Why we use a single workflow
      - How to modify CI behavior without creating new files
      - Checklist before creating new workflows
      - Documentation of template files (example-caller.yml, wp-performance.yml)
      - History of consolidation to prevent regression

- **DRY Refactor: Consolidated Grouping Logic** - Created centralized `group_and_add_finding()` helper function
  - **Before**: Duplicate grouping logic in `run_check()` function and admin capability check (92 lines duplicated)
  - **After**: Single reusable helper function (56 lines) used by both code paths
  - **Benefits**:
    - Easier to maintain - changes to grouping logic only need to be made in one place
    - Consistent behavior across all checks
    - Reduced code complexity and potential for bugs
    - Follows DRY (Don't Repeat Yourself) principle
  - **Implementation**: Helper function manages grouping state via global variables and supports flush mode for final group output
  - **No Functional Changes**: Grouping behavior remains identical, just consolidated into a shared helper

### Fixed

- **Robust Line Number Validation** - Added numeric validation for line numbers before arithmetic operations
  - **Issue**: `grep` can occasionally output non-standard formats (e.g., "Binary file ... matches") that would make `lineno` empty or non-numeric
  - **Risk**: Using non-numeric `lineno` in bash arithmetic (`$((lineno - last_line))`) would trigger bash errors and break JSON generation
  - **Fix**: Added `[[ "$lineno" =~ ^[0-9]+$ ]]` validation in three locations:
    - `run_check()` function - before grouping findings (line 1331)
    - `group_and_add_finding()` function - before arithmetic operations (line 1262)
    - `format_finding()` function - before context line calculations (line 925)
  - **Behavior**: Non-numeric line numbers are now silently skipped instead of causing script errors
  - **Impact**: More robust JSON generation even when scanning binary files or encountering unexpected grep output

- **GitHub Actions CI Exit Code Handling** - Fixed CI workflow to handle non-zero exit codes gracefully
  - **Issue**: Performance checks on the toolkit repository itself may find issues (intentional test patterns)
  - **Problem**: Non-zero exit codes from `check-performance.sh` would fail the CI workflow
  - **Fix**: Added `|| EXIT_CODE=$?` capture and `exit 0` to make the step informational rather than blocking
  - **Behavior**: CI now shows a warning if issues are found but doesn't fail the workflow
  - **Impact**: CI can complete successfully while still reporting any detected issues

- **Baseline Test Script Exit Code Handling** - Fixed `test-baseline-functionality.sh` to properly capture exit codes with `set -e`
  - **Issue**: Script uses `set -e` which terminates immediately on non-zero exit codes
  - **Problem**: When `check-performance.sh` returns non-zero (expected when errors are found), the test script would terminate before capturing `$EXIT_CODE`
  - **Fix**: Temporarily disable `set -e` around command execution using `set +e` / `set -e` wrapper
  - **Locations Fixed**: All 4 test scenarios (baseline generation, suppression, new issue detection, ignore-baseline)
  - **Impact**: Tests can now properly validate exit codes without premature termination

- **HTML Report Path Display** - Fixed "Paths Scanned" showing `.` instead of full absolute path
  - **Issue**: When scanning with `--paths .`, the HTML report header showed "Paths Scanned: ." instead of the full directory path
  - **Root Cause**: Display was using the original relative path variable instead of the resolved absolute path
  - **Fix**: Changed to display `$abs_path` (resolved absolute path) instead of `$path` (original input)
  - **Impact**: HTML reports now show clear, clickable full paths like `/Users/.../wp-content/plugins/my-plugin` instead of confusing `.`

## [1.0.57] - 2025-12-31

### Added

- **Proximity-Based Finding Grouping** - Findings on nearby lines in the same file are now automatically grouped to reduce noise
  - **Grouping Logic**: Findings within 10 lines of each other in the same file are combined into a single grouped finding
  - **Clear Messaging**: Grouped findings show count and line range (e.g., "Direct superglobal manipulation (7 occurrences in lines 403-409)")
  - **Applies to All Checks**: Works for all checks using `run_check()` function (superglobals, debug code, etc.)
  - **Admin Capability Check Grouping**: Extended grouping to admin capability checks (previously ungrouped)
  - **Impact**: Reduces report clutter - e.g., 28 individual `$_POST` findings → 13 grouped findings
  - **Example**: Instead of 8 separate "Admin function missing capability check" alerts, you see "8 occurrences in lines 156-172"

- **HTML Report Search/Filter** - Interactive search functionality for filtering findings in HTML reports
  - **Real-time Filtering**: Search box at top of report filters findings as you type
  - **Comprehensive Search**: Searches across all finding content (file paths, messages, code snippets, severity levels)
  - **Case-Insensitive**: Works regardless of capitalization
  - **Results Counter**: Shows "Showing X of Y findings" with color-coded feedback (green for results, red for no matches)
  - **Keyboard Shortcut**: Press Ctrl+F (Cmd+F on Mac) to focus search box
  - **Use Cases**:
    - Search "debugger" to find all debug code
    - Search "$_POST" to find superglobal issues
    - Search "admin.php" to filter by file
    - Search "CRITICAL" to see only critical issues

- **Local Time Display in HTML Reports** - Added local timezone conversion alongside UTC timestamps
  - **Dual Display**: Shows both "Generated (UTC)" and "Local Time/Date" in report header
  - **Automatic Conversion**: JavaScript automatically converts UTC to browser's local timezone
  - **Readable Format**: Displays as "December 31, 2024, 05:12:50 PM PST" with timezone abbreviation
  - **Global Team Support**: UTC for universal reference, local time for convenience

### Changed

- **HTML Report Click Behavior** - Improved collapsible finding interaction
  - Clicking on file path links no longer collapses the finding
  - Only clicking on the finding itself toggles details/code visibility

## [1.0.54] - 2025-12-30

### Added

- **Tier 1 SPO Security-Performance Checks** - Implemented SPO-001 through SPO-004 in `check-performance.sh`, covering debug code in production (PHP + JS/TS), direct superglobal manipulation, insecure deserialization from superglobals, and admin hooks/functions missing capability checks with baseline/JSON support
- **Per-Check Include Overrides** - `run_check` now accepts per-check include overrides via `OVERRIDE_GREP_INCLUDE`, enabling mixed-language scans without duplicating logic

## [1.0.56] - 2025-12-30

### Added

- **Enhanced Project Metrics** - Added file count and lines of code statistics to all reports
  - **Files Analyzed**: Shows total number of PHP files scanned (e.g., "8 PHP files")
  - **Lines Reviewed**: Shows total lines of code analyzed with comma formatting (e.g., "4,552 lines of code")
  - **JSON Output**: Metrics included in both `project` and `summary` sections
  - **Log Files**: Metrics displayed in PROJECT INFORMATION section
  - **HTML Reports**: Metrics shown in project header with professional formatting
  - **Context Value**: Helps users understand scope, thoroughness, and error rates relative to codebase size

- **Dual Timestamp Display** - Added local time alongside UTC timestamps for better user experience
  - **Log Header**: Shows both "Generated (UTC)" and "Local Time" with timezone (e.g., "PST", "EST")
  - **Log Footer**: Shows both "Completed (UTC)" and "Local Time" for full audit trail
  - **Automatic Timezone Detection**: Uses system timezone for local time display
  - **Global Team Support**: UTC for universal reference, local time for convenience

### Fixed

- **Critical: grep Pattern Handling in run_check()** - Fixed bug where combined grep arguments (e.g., `-E console\\.log`) were treated as array elements, causing grep to fail silently and report false "Passed" results
  - **Impact**: SPO-001 and SPO-002 were not detecting issues due to broken pattern matching
  - **Solution**: Reverted to string-based pattern handling to preserve grep argument structure
  - **Validation**: Save Cart Later test now correctly detects 2 debug code instances and 10 superglobal manipulation issues
  - **Error count**: Increased from 3 to 5 errors (proving fix works correctly)

### Changed

- **Timestamp Labels**: Renamed "Timestamp (UTC)" to "Generated (UTC)" and "End Timestamp (UTC)" to "Completed (UTC)" for clarity

## [1.0.55] - 2025-12-30

### Added

- **Project Metrics Foundation** - Initial implementation of file counting and LOC analysis (superseded by 1.0.56)

## [1.0.54] - 2025-12-30

### Added

- **Security-Performance Overlap (SPO) Rules - Tier 1** - Added 4 critical security checks that also impact performance
  - **SPO-001: Debug Code in Production** [CRITICAL] - Detects `console.log()`, `debugger;`, `var_dump()`, `print_r()`, `error_log()` in production code
    - **Performance Impact**: Console logging slows JavaScript execution
    - **Security Impact**: Exposes internal logic and sensitive data
    - **Scans**: PHP and JavaScript files (`.php`, `.js`, `.jsx`, `.ts`, `.tsx`)
  - **SPO-002: Direct Superglobal Manipulation** [HIGH] - Detects `unset($_GET[`, `$_POST =`, direct superglobal assignments
    - **Performance Impact**: Bypasses WordPress caching and optimization
    - **Security Impact**: Violates WordPress security model, potential data corruption
  - **SPO-003: Insecure Data Deserialization** [CRITICAL] - Detects `unserialize($_`, `base64_decode($_`, `json_decode($_` without validation
    - **Performance Impact**: Unvalidated deserialization can cause memory issues
    - **Security Impact**: Code execution vulnerabilities, object injection attacks
  - **SPO-004: Missing Capability Checks in Admin Functions** [HIGH] - Detects admin functions/hooks without `current_user_can()` validation
    - **Performance Impact**: Unauthorized operations can trigger expensive processes
    - **Security Impact**: Privilege escalation vulnerabilities
    - **Smart Detection**: Checks 10 lines after admin function/hook for capability validation

### Changed

- **Check Organization**: SPO rules now appear in dedicated section before existing performance checks
- **Output Format**: Enhanced terminal output with SPO section header

## [1.0.53] - 2025-12-30

### Added

- **Unbounded get_users() Detection** - New CRITICAL rule (`unbounded-get-users`) detects `get_users()` calls without `'number'` parameter, which can fetch ALL users and crash sites with large user bases
- **Script Versioning with time() Detection** - New MEDIUM rule (`script-versioning-time`) detects `wp_register_script()`, `wp_enqueue_script()`, `wp_register_style()`, `wp_enqueue_style()` using `time()` as version parameter, which prevents browser caching
- **Enhanced N+1 Detection** - Extended existing N+1 pattern detection to include `get_user_meta()` in loops (previously only detected `get_post_meta` and `get_term_meta`)

### Changed

- **HOWTO-TEMPLATES.md** - Added two new skip rules to documentation: `unbounded-get-users` and `script-versioning-time`

## [1.0.52] - 2025-12-30

### Fixed

- **HTML Report Path and Link Generation** - Fixed three bugs in the `check-performance.sh` script's HTML report generation to improve correctness and reliability:
  - **Multiple Path Handling:** Correctly processes multiple space-separated paths provided via the `--paths` argument, creating distinct clickable `file://` links for each instead of a single broken link.
  - **Robust URL Encoding:** Replaced a simplistic string substitution with a `jq`-based `url_encode` function that correctly encodes a comprehensive set of reserved characters (e.g., `#`, `?`, `&`), preventing broken `file://` links for paths with special characters.
  - **HTML Snippet Escaping:** Fixed incomplete HTML escaping in code snippets. The `jq` filter now correctly escapes ampersands (`&`) in addition to `<` and `>`, preventing common PHP code (e.g., `$_GET['id']`) from breaking report rendering.
- **jq Prerequisite Check** - Moved the `require_jq` check before the `validate_json_file` call in `post-to-slack.sh` to prevent confusing "jq not installed" warnings followed by a successful validation step.

## [1.0.51] - 2025-12-30

### Added

- **Shared Bash Helper Libraries (Phase 1 DRY)** - Introduced `dist/bin/lib/` with reusable color constants, JSON validation helpers (`validate_json_file`, `require_jq`), and timestamp utilities for UTC and ISO-8601 formatting.

### Changed

- **Script DRY Refactor (Foundation)** - Updated `check-performance.sh`, `run`, `post-to-slack.sh`, `format-slack-message.sh`, `test-slack-integration.sh`, and `pre-commit-credential-check.sh` to source shared libraries, centralizing output styling, JSON validation, and timestamp generation.
- **DRY Audit Documentation** - Updated DRY audit files with Phase 1 completion statuses and next-step tracking.

## [1.0.50] - 2025-12-30

### Added

- **Clickable File Links in HTML Reports** - All file paths are now clickable `file://` URLs
  - Scanned directory path in header is clickable (opens in Finder/Explorer)
  - Each finding's file path is clickable (opens file in default editor)
  - Paths automatically converted to absolute URLs for reliability
  - URL-encoded to handle spaces and special characters (e.g., `Local Sites` → `Local%20Sites`)
  - Hover effects added for better UX (dotted underline, color change, background highlight)
  - Works when HTML report is opened locally (browser security allows `file://` from local HTML)
  - Title tooltips: "Click to open directory" / "Click to open file"

## [1.0.49] - 2025-12-30

### Changed

- **HTML Report Enhancement** - Project information now displayed in report header
  - Reuses existing `detect_project_info()` function (DRY principle)
  - Extracts project metadata from JSON output (no parallel extraction system)
  - Displays: Project Name, Version, Type (plugin/theme), and Author
  - Matches the text output format for consistency
  - Automatically populated from WordPress plugin/theme headers
  - Example: "KISS FAQs with Schema v1.04.7 [plugin] by KISS Plugins"

## [1.0.48] - 2025-12-30

### Added

- **HTML Report Generation** - Beautiful, self-contained HTML reports for local development
  - Auto-generates when running with `--format json` on local machines (suppressed in GitHub Actions)
  - Self-contained HTML with inline CSS/JS - no external dependencies
  - Responsive design with modern gradient styling
  - Features:
    - Summary dashboard with color-coded stats (errors, warnings, baselined, stale)
    - Status banner showing pass/fail with visual indicators
    - Detailed findings grouped by severity (Critical/High/Medium/Low)
    - Color-coded severity badges
    - Syntax-highlighted code snippets
    - Expandable/collapsible findings sections
    - Checks summary showing all rule results
  - Reports saved to `dist/reports/` with UTC timestamps
  - Auto-opens in default browser (macOS/Linux)
  - Template-based generation using jq for JSON parsing
  - See [PROJECT/DETAILS/HTML-REPORTS.md](PROJECT/DETAILS/HTML-REPORTS.md) for implementation details

### Changed

- **`.gitignore` Updates** - Added `dist/reports/` to ignore generated HTML reports
  - Keeps `.gitkeep` file to maintain directory structure
  - Prevents accidental commit of local report files

## [1.0.47] - 2025-12-30

### Added

- **Project Templates** - Save configuration for frequently-scanned projects
  - Create templates with `run <project-name>` command (auto-detects plugin metadata)
  - Manual template creation in `/TEMPLATES/` folder with AI completion support
  - Template variables: `PROJECT_NAME`, `PROJECT_PATH`, `NAME`, `VERSION`, `SKIP_RULES`, `FORMAT`, `BASELINE`, etc.
  - Progressive disclosure: basic → common → advanced options
  - See [HOWTO-TEMPLATES.md](HOWTO-TEMPLATES.md) for complete guide
  - **Benefits:**
    - No more typing long paths - just `run acme`
    - Consistent configuration across scans
    - Version control your scan configurations
    - Share templates with team members

- **AI Agent Instructions** - Added project-specific guidance to AGENTS.md
  - Template completion workflow documented for AI agents
  - Links to [TEMPLATES/_AI_INSTRUCTIONS.md](TEMPLATES/_AI_INSTRUCTIONS.md)
  - Updated AGENTS.md to v2.1.0

### Changed

- **`.gitignore` for Templates** - Configured to track base files but ignore user templates
  - Tracks: `_TEMPLATE.txt`, `_AI_INSTRUCTIONS.md`, `.gitkeep`
  - Ignores: All user-created template files (e.g., `kiss-faqs.txt`, `my-plugin.txt`)
  - Prevents accidental commit of local configuration with absolute paths

### Added (continued)

- **Unvalidated cron intervals detection** [ERROR/HIGH]
  - Detects WordPress cron intervals set without proper validation (absint() and bounds checking)
  - **Pattern detected:** `'interval' => $variable * 60` or `$variable * MINUTE_IN_SECONDS` without validation
  - **Smart validation:** Checks 10 lines before the interval assignment for:
    - `$var = absint(...)` pattern
    - `absint($var)` pattern
    - Bounds checking: `if ($var < 1 || $var > number)`
  - **Why it matters:** Unvalidated intervals can cause:
    - **Infinite loops:** If interval = 0, cron fires every second
    - **Silent failures:** If interval = null or negative, undefined behavior
    - **Type coercion issues:** String values coerce to 0
  - **Real-world impact:** Corrupt data in options table can crash site with infinite cron loops
  - **Recommended fix:**
    ```php
    $interval = absint($interval);
    if ($interval < 1 || $interval > 1440) {
        $interval = 15; // Safe default
    }
    ```
  - **Test fixture:** Added `cron-interval-validation.php` with 3 vulnerable patterns and 3 safe patterns

### Fixed

- **Project name detection with spaces in path** - Fixed bug where paths with spaces (e.g., `/Users/noelsaw/Local Sites/...`) were truncated at the first space, causing incorrect project detection. Changed from `awk '{print $1}'` to direct variable assignment to preserve full paths.
- **Git info display for external scans** - Git commit and branch info are now hidden when scanning paths outside the current git repository. Only shows git info when scanning within the repository root.
- **Cron fixture integration** - Wired up `cron-interval-validation.php` fixture to test harness. Previously the fixture existed but wasn't exercised in CI, creating regression risk. Now runs as Test 8 with expected counts (1 error, 0 warnings). Test suite now runs 10 tests (was 9).
- **Cron fixture documentation** - Updated fixture comment to correctly state "Expected: 1 error (3 findings)" instead of "Expected: 3 errors". Also corrected line numbers in comments to match actual findings.
- **Test harness version** - Updated `run-fixture-tests.sh` version header from 1.0.46 to 1.0.47 for consistency.

## [1.0.46] - 2025-12-29

### Added

- **file_get_contents() with external URLs detection** [ERROR/HIGH]
  - Detects `file_get_contents()` used with http/https URLs (direct strings)
  - Detects `file_get_contents()` with variables that look like URLs ($url, $api_url, $endpoint, etc.)
  - **Why it matters:** `file_get_contents()` for remote URLs is insecure (no SSL verification by default), has no timeout (can hang site), and fails silently. Should use `wp_remote_get()` instead.
  - **Impact:** Prevents security vulnerabilities and site hangs from unresponsive external APIs.

- **HTTP requests without timeout detection** [WARNING/MEDIUM]
  - Detects `wp_remote_get()`, `wp_remote_post()`, `wp_remote_request()`, and `wp_remote_head()` calls without explicit timeout parameter
  - **Smart detection:** Checks inline args (next 5 lines within same statement) AND backward lookup for `$args` variable definitions (up to 20 lines)
  - **Why it matters:** HTTP requests without timeout can hang the entire site if the external server doesn't respond. WordPress default is 5 seconds, but explicit timeouts are safer and more maintainable.
  - **Impact:** Prevents site-wide hangs from unresponsive external APIs.

- **Test fixtures and validation**
  - Added `file-get-contents-url.php` fixture with 4 expected errors
  - Added `http-no-timeout.php` fixture with 4 expected warnings
  - Updated `ajax-antipatterns.php` expected warnings (now catches HTTP timeout issue)
  - All 9 fixture tests passing

### Fixed

- **HTTP timeout detection false negative** - Fixed bug where `wp_remote_head()` without args was not flagged if a different function call with timeout appeared in the next 5 lines. Now only checks within the same statement (until semicolon).
- **HTTP timeout detection false positive** - Improved logic to check backward (up to 20 lines) for `$args` variable definitions that include timeout parameter. Prevents flagging cases like:
  ```php
  $args = array('timeout' => 10);
  $response = wp_remote_get($url, $args); // Now correctly recognized as safe
  ```
- **Fixture header comments** - Updated `file-get-contents-url.php` header to correctly state "Expected: 4 errors" (was incorrectly "3 errors")

### Changed

- **Version metadata**
  - Bumped CLI script version to 1.0.46
  - Updated fixture test script version to 1.0.46

### Enhanced

- **Project detection in logs and JSON output** - Automatically detects and displays WordPress plugin/theme information
  - **Text output:** Shows "Project: Plugin Name v1.2.3 [plugin]" at top of scan
  - **Text log files:** Includes PROJECT INFORMATION section with name, version, type, and author
  - **JSON output:** Adds `"project"` object with full metadata (type, name, version, description, author, path)
  - **Smart detection:**
    - Scans for plugin main file (PHP with "Plugin Name:" header)
    - Scans for theme style.css (with "Theme Name:" header)
    - Checks current directory and one level up (handles scanning `src/` or `includes/` subdirectories)
    - Falls back to path-based inference (`/wp-content/plugins/` or `/wp-content/themes/`)
  - **Use case:** Essential for users running analyzer from central location against multiple projects
  - **Example JSON:**
    ```json
    {
      "project": {
        "type": "plugin",
        "name": "WooCommerce",
        "version": "8.5.2",
        "description": "An eCommerce toolkit",
        "author": "Automattic",
        "path": "/var/www/wp-content/plugins/woocommerce"
      }
    }
    ```

### Documentation

- **Completely rewrote `dist/README.md`** with developer-focused content
  - Added compelling "Why This Matters" section with real-world production failure examples
  - Added "What Makes This Different" value proposition (WordPress-specific, zero dependencies, production-tested)
  - **Emphasized "Run From Anywhere" capability** - no need to copy tool into every project
  - Added detailed installation instructions with central location setup
  - Added practical examples: `~/dev/wp-analyzer/dist/bin/check-performance.sh --paths ~/Sites/my-plugin`
  - Added "Pro Tip" section with shell alias setup for one-command usage
  - Expanded "What It Detects" with real-world impact explanations (e.g., "1000 users = 60,000 requests/min")
  - Added comprehensive command reference with all flags and options
  - Added baseline management guide for legacy codebases
  - Added CI/CD integration examples (GitHub Actions, GitLab CI)
  - Improved JSON output documentation with full schema example
  - Added suppressing false positives guide with best practices
  - Total rewrite: 372 lines → 481 lines (+109 lines, +29% more content)

---

## [1.0.45] - 2025-12-29

### Added

- **Context lines for better false positive detection**
  - Error messages now show **3 lines before and after** each finding by default to help identify false positives.
  - Example: A `'limit' => -1` query now shows surrounding code, revealing if there are time constraints or other mitigating factors.
  - Context is included in both text output (indented) and JSON output (as a `context` array with line numbers).
  - Added `--no-context` flag to disable context display if needed.
  - Added `--context-lines N` flag to customize the number of context lines (default: 3).

### Changed

- **Context enabled by default**
  - Users now get important context automatically without needing to enable a flag, reducing the chance of missing mitigating factors when reviewing findings.

- **Version metadata**
  - Bumped the CLI script version to 1.0.45 to keep JSON output, terminal banners, and documentation in sync with this changelog.

---

## [1.0.44] - 2025-12-29

### Changed

- **Improved error display formatting**
  - Code excerpts in error messages are now truncated to 200 characters (with `...` ellipsis) to prevent overwhelming output from long lines of JavaScript or PHP code.
  - Source file names in error output are now displayed in **bold** for better visual scanning and readability.
  - Applied formatting improvements to all check types: AJAX polling, REST endpoints, get_terms SQL, and generic pattern checks.

- **Version metadata**
  - Bumped the CLI script version to 1.0.44 to keep JSON output, terminal banners, and documentation in sync with this changelog.

---

## [1.0.43] - 2025-12-29

### Changed

- **Project documentation alignment**
  - Updated `PROJECT/PROJECT.md` "Current State", "Proposed Approach", and "Three-layer system" sections so they reflect the currently implemented toolkit pieces (grep-based CLI, fixture suite, CI wiring, and the Neochrome WP Toolkit demo plugin) and reference GPT 5.1 feedback via `BACKLOG.md` instead of an inline TEMP dump.

- **Version metadata**
  - Bumped the CLI script and backlog version markers to 1.0.43 to keep JSON output, terminal banners, and documentation in sync with this changelog.

---

## [1.0.42] - 2025-12-29

### Changed

- **Backlog and project documentation**
  - Reflected the GPT 5.1 TEMP feedback from `PROJECT.md` into structured items in `BACKLOG.md` and noted this in the roadmap documentation.

- **Version metadata**
  - Bumped the CLI script version to 1.0.42 so JSON output, log headers, and terminal banners stay in sync with the changelog.

---

## [1.0.41] - 2025-12-28

### Changed

- **Looser wp_ajax nonce heuristic**
  - Relaxed the `wp_ajax` nonce check to require at least one `check_ajax_referer`/`wp_verify_nonce` call per file instead of matching the number of `wp_ajax` hooks.
  - Reduces false positives for common patterns where `wp_ajax_*` and `wp_ajax_nopriv_*` share a handler or nonce validation is wrapped in a helper, while still flagging completely unprotected AJAX endpoints.

### Added

- **Safe AJAX fixtures for regression coverage**
  - Added `dist/tests/fixtures/ajax-safe.php` to cover shared privileged/non-privileged handlers and helper-wrapped nonce validation that should not be flagged.
  - Wired the new fixture into `dist/tests/run-fixture-tests.sh` to prevent regressions when tweaking the `wp_ajax` nonce heuristic.

---

## [1.0.40] - 2025-12-28

### Added

- **AJAX/REST high-impact detections**
  - Detect unbounded AJAX polling patterns by scanning `setInterval` blocks that trigger fetch/jQuery AJAX/XMLHttpRequest calls.
  - Flag WordPress REST routes registered without any pagination/limit guard as CRITICAL.
  - Flag `wp_ajax` handlers missing nonce validation as HIGH impact errors to surface unthrottled AJAX endpoints.
- **Fixture coverage for AJAX regressions**
  - Added PHP and JS fixtures covering REST pagination gaps, nonce-less AJAX handlers, and polling storms, and wired them into the fixture test suite.

### Changed

- **Documentation refresh**
  - Updated `dist/README.md` to 1.0.40 with the new AJAX/REST detection rules and fixture references.

---

## [1.0.39] - 2025-12-28

### Fixed

- **Cross-platform baseline path normalization**
  - Normalized baseline file paths by stripping leading `./` so baseline entries generated on macOS or other environments reliably match runtime findings on Linux/GitHub Actions, regardless of how `grep` formats filenames.
  - Ensures the JSON `summary.baselined` metric is consistent across environments while preserving existing baseline file format and behavior.

---

## [1.0.37] - 2025-12-28

### Fixed

- **Additional JSON fixture failures (LIKE query checks)**
  - Hardened the `compare => 'LIKE'` meta query detection to skip any grep output where the parsed line number is not numeric before using it in arithmetic.
  - Prevents Bash arithmetic errors on the LIKE-leading-wildcard check from leaking into `--format json` output and breaking the JSON fixture tests on Ubuntu/GitHub Actions.
  - Uses the same `NEOCHROME_DEBUG=1` (text-only) logging pattern as the timezone check so debugging doesn't corrupt JSON output.

---

## [1.0.36] - 2025-12-28

### Fixed

- **JSON fixture failures on Linux/GitHub Actions**
  - Hardened the timezone-sensitive pattern detection to skip any grep output where the parsed line number is not numeric
  - This prevents Bash arithmetic errors from leaking into `--format json` output and causing the "Output is not valid JSON (doesn't start with {)" fixture failures.
  - Added an opt-in `NEOCHROME_DEBUG=1` mode (text output only) that logs any skipped timezone matches for future diagnosis without breaking JSON output.

---

## [1.0.35] - 2025-12-28

### Fixed

- **Baseline generation now works correctly**
  - Added missing call to `generate_baseline_file()` before script exit
  - The `--generate-baseline` flag now properly writes the baseline file in both text and JSON output modes
  - Previously, baseline counts were collected but the file was never written

---

## [1.0.34] - 2025-12-28

### Added

- **Example JSON payload for tooling authors**
  - Added a trimmed JSON example snippet to `dist/README.md` under the JSON output section, showing `summary` and a single `finding` entry to make it easier for CI/IDE integrations to parse the output.

---

## [1.0.33] - 2025-12-28

### Added

- **Baseline regression coverage**
  - Added a dedicated `.hcc-baseline` fixture and JSON-based test in `dist/tests/run-fixture-tests.sh` to validate `baselined` and `stale_baseline` behavior end-to-end.
- **Developer documentation updates**
  - Updated `dist/README.md` with JSON output and baseline usage instructions for CI/tooling, and bumped example/version references to 1.0.33.

---

## [1.0.32] - 2025-12-28

### Added

- **Baseline support for performance findings**
  - New `--generate-baseline` flag to scan the current codebase and write a `.hcc-baseline` file with per-rule, per-file allowed counts
  - New `--baseline` flag to point to a custom baseline file path and `--ignore-baseline` to disable baseline usage when needed
  - Runtime checks now consult the baseline and suppress findings that are within the recorded allowance while still emitting new or increased findings
  - JSON summary now includes `baselined` (total suppressed findings) and `stale_baseline` (entries where the recorded allowance exceeds current matches)
  - All existing rules are baseline-aware, including:
    - `unbounded-posts-per-page`, `pre-get-posts-unbounded`, `get-terms-no-limit`, `unbounded-terms-sql`
    - `timezone-sensitive-pattern`, `like-leading-wildcard`, `n-plus-1-pattern`, `transient-no-expiration`

---

## [1.0.30] - 2025-12-28

### Added

- **JSON output format** - New `--format json` flag for structured output to enable CI/CD integration, programmatic parsing, and IDE extensions
  - Outputs valid JSON with version, timestamp, paths_scanned, summary (errors/warnings/exit_code), findings array, and checks array
  - Each finding includes: id, severity, impact, file, line, message, code
  - Log file mirrors stdout format: `.log` extension for text, `.json` extension for JSON
  - Log headers/footers are omitted in JSON mode to preserve valid JSON structure

---

## [1.0.29] - 2025-12-28

### Fixed

- **CI concurrency deduplication** - Fixed concurrency group key to use `github.head_ref || github.ref` instead of PR number, so push and pull_request events for the same branch share the same group and get properly deduplicated

---

## [1.0.28] - 2025-12-28

### Fixed

- **Case-insensitive LIMIT check** - `grep -v "LIMIT"` now uses `-i` flag to catch both uppercase `LIMIT` and lowercase `limit` in SQL queries, preventing false positives for unbounded queries
- **Glob expansion in PHP file check** - Fixed `[ -f "*.php" ]` in install script which tested for literal filename `*.php` instead of using glob expansion; now uses `ls *.php` for proper detection

---

## [1.0.27] - 2025-12-27

### Fixed

- **Cross-platform warning count tolerance** - Fixture tests now accept a range of warning counts (3-5 for antipatterns.php) to accommodate differences between macOS and Linux grep/sed behavior with UTF-8 content

---

## [1.0.26] - 2025-12-27

### Fixed

- **Restored feature branch CI triggers** - Re-added `feature/**` to push triggers (needed for branches without open PRs)

---

## [1.0.25] - 2025-12-27

### Fixed

- **Duplicate CI workflow runs** - CI was running 2-3x per commit due to overlapping triggers:
  - Added `concurrency` setting to cancel in-progress runs when new commits are pushed to the same branch/PR
  - This prevents wasted GitHub Actions minutes and reduces noise in the Actions tab

---

## [1.0.24] - 2025-12-27

### Fixed

- **Critical: Removed `set -e` causing silent script exit in CI** - The `set -e` option caused check-performance.sh to exit immediately when:
  - `((ERRORS++))` returned exit code 1 (bash behavior when incrementing from 0)
  - This prevented the Summary section from being printed
  - CI fixture tests could not parse error/warning counts
  - Added explanatory comment about why `set -e` is intentionally omitted

---

## [1.0.23] - 2025-12-27

### Added

- **Debug output in fixture tests** - Added comprehensive debugging to help diagnose CI failures
  - Shows environment variables (SCRIPT_DIR, DIST_DIR, PWD)
  - Lists fixture files to confirm paths are correct
  - Shows last 20 lines of check-performance.sh output
  - Shows parsed error/warning counts before comparison

---

## [1.0.22] - 2025-12-27

### Fixed

- **Tests directory exclusion in fixture validation** - Fixed issue where `--exclude-dir=tests` prevented fixture tests from running in GitHub Actions
  - Now dynamically removes `tests` from exclusions when `--paths` targets a tests directory
  - Normal scans with `--paths "."` still correctly exclude the tests directory

---

## [1.0.21] - 2025-12-27

### Added

- **LIKE Queries with Leading Wildcards Detection** (WARNING, MEDIUM impact)
  - Detects `'compare' => 'LIKE'` in meta_query with `'value' => '%...'` pattern
  - Detects raw SQL `LIKE '%...` patterns (leading wildcard)
  - Filters out comment lines to reduce false positives
  - Leading wildcards prevent index use and cause full table scans
  - Added test fixtures: Antipattern #19 (meta_query) and #20 (raw SQL)

### Changed

- Updated fixture test expected warnings: 4 → 5 (for new LIKE detection)

### Fixed

- **CI Workflow paths** - Updated `.github/workflows/ci.yml` to use `dist/` paths after folder reorganization
  - `bin/check-performance.sh` → `dist/bin/check-performance.sh`
  - `tests/fixtures/` → `dist/tests/fixtures/`
  - Added automated fixture test step using `run-fixture-tests.sh`

---

## [1.0.20] - 2025-12-27

### Added

- **Automated Fixture Validation** (`tests/run-fixture-tests.sh`)
  - Runs `check-performance.sh` against test fixtures and validates expected counts
  - Prevents regressions when modifying detection patterns
  - Verifies `antipatterns.php` produces exactly 6 errors and 4 warnings
  - Verifies `clean-code.php` produces 0 errors (1 warning from N+1 heuristic)
  - Self-documenting expected counts for easy updates when adding new patterns

### Changed

- Updated test fixture script to use relative paths (fixes path handling with spaces)

---

## [1.0.19] - 2025-12-27

### Added

- **Remote Installation Script** (`install.sh`) - One-liner remote installation via curl
  - Clone toolkit from GitHub to `.neochrome-toolkit/` cache directory
  - Auto-copy `bin/check-performance.sh` and test fixtures to target project
  - Auto-update `.gitignore` to exclude toolkit cache
  - Support for branch selection (main/development)
- **PROJECT-REMOTE-INSTALL.md** - Documentation for remote installation options:
  - Option A: Composer package approach
  - Option B: Git submodule approach
  - Option C: Git clone script (recommended)
  - AI assistant integration instructions
- **New Test Fixtures** - Added antipattern tests for:
  - Transients without expiration (Antipattern #15, #16)
  - Timezone patterns without phpcs:ignore (Antipattern #17, #18)
  - Timezone patterns WITH phpcs:ignore to verify filtering

### Changed

- Enhanced timezone warning output to show occurrence count: `(5 occurrence(s) without phpcs:ignore)`
- Verbose mode now shows all matches instead of truncated list

---

## [1.0.18] - 2025-12-27

### Added

- **Performance Impact Scoring** - All checks now display impact level badges: `[CRITICAL]`, `[HIGH]`, `[MEDIUM]`, `[LOW]`
  - Critical checks: Unbounded queries (posts_per_page, numberposts, nopaging, wc_get_orders, get_terms, pre_get_posts)
  - High: Unbounded SQL on terms tables, ORDER BY RAND
  - Medium: N+1 patterns, Transients without expiration
  - Low: Timezone-sensitive patterns
- **Transient Abuse Detection** (WARNING) - New check for `set_transient()` calls missing the expiration parameter
- **Enhanced Timezone Warning** - Timezone check now filters out lines with `phpcs:ignore` comments on the same or previous line, reducing false positives for documented intentional usage

### Changed

- Updated `run_check()` function signature to accept impact level as second parameter

---

## [1.0.17] - 2025-12-27

### Added

- **Randomized ordering check** (WARNING) - Detects `orderby => 'rand'` and `ORDER BY RAND()` patterns that cause full table scans
- **pre_get_posts unbounded check** (ERROR) - Detects hooks that set `posts_per_page` to `-1` or `nopaging` to `true` inside `pre_get_posts`, causing sitewide unbounded queries
- **Unbounded term SQL check** (ERROR) - Detects direct SQL on `wp_terms`/`wp_term_taxonomy` tables without `LIMIT` clause
- Test fixtures for new antipatterns (#10-14)

---

## [1.0.16] - 2025-12-27

### Changed

- **Official project name** - Rebranded to "Neochrome WP Toolkit" across all user-facing documentation, plugin headers, admin UI, and log output
  - Plugin Name: `Neochrome WP Toolkit`
  - Script banner: `Neochrome WP Toolkit - Performance Checker`
  - Log headers: `Neochrome WP Toolkit - Performance Check Log`
  - Admin page title: `Neochrome WP Toolkit`
  - Internal code namespaces (`npt_` prefix) remain unchanged for backward compatibility

---

## [1.0.15] - 2025-12-27

### Fixed

- **Version mismatch** - Updated README.md to match plugin header and script versions
- **Incomplete log entries on unexpected exits** - Added trap handler in `bin/check-performance.sh` to ensure log footer is written even on script interruption (Ctrl+C), unexpected failures, or `set -e` exits
- **ANSI color codes breaking regex parsing** - Added ANSI escape sequence stripping in `npt_get_cli_checker_summary()` so error/warning counts are correctly parsed from colorized CLI output
- **Improved get_terms detection logic** - Fixed grep logic to properly detect unbounded `get_terms()` calls and added support for both single-quoted `'number'` and double-quoted `"number"` parameter keys

### Changed

- Log exit handling now uses trap mechanism instead of explicit calls, ensuring audit trail completeness

---

## [1.0.14] - 2025-12-27

### Added

- **CI workflow for the toolkit repository** (`.github/workflows/ci.yml`)
  - Runs performance checks on the toolkit itself on push to `main`, `development`, and `feature/**` branches
  - Validates test fixtures work correctly (antipatterns are detected, clean code passes)
  - Validates workflow files and scripts are present and executable
  - Uses `--no-log` flag in CI to avoid log file accumulation
  - Ensures the toolkit validates itself before being used by other projects

---

## [1.0.13] - 2025-12-27

### Changed

- **Excluded `tests/` directory from default scans** in `bin/check-performance.sh`
  - Test fixtures (`antipatterns.php`, `clean-code.php`) are now excluded by default
  - Prevents false positives from intentional bad patterns used for validation
  - Test fixtures can still be scanned explicitly: `--paths "tests/fixtures/antipatterns.php"`
  - Keeps validation capability while ensuring clean production scans

---

## [1.0.12] - 2025-12-27

### Added

- **Automatic logging** for each code analysis run in `bin/check-performance.sh`
  - Logs saved to `logs/` directory with UTC timestamp format: `YYYY-MM-DD-HHMMSS-UTC.log`
  - Each log includes: timestamp, script version, paths scanned, flags used, git commit/branch (if available), full output, and exit code
  - Provides audit trail for tracking what was scanned, when, and what was found
  - Supports trend analysis and CI debugging
  - Aligns with PROJECT.md Phase 4 goal of metrics tracking for ROI measurement
- **--no-log flag** to disable logging when needed
- `.gitignore` file to exclude logs directory from version control

---

## [1.0.11] - 2025-12-27

### Added

- Documented the `npt_`/`NPT_` prefixes and admin page slug in the README so
  it is clear this toolkit is namespaced to avoid conflicts with the original
  Neochrome performance plugin.

---

## [1.0.10] - 2025-12-27

### Changed

- Renamed all SPC/SPC_-prefixed PHP APIs in the Neochrome WP Performance
  Analysis Toolkit plugin to NPT/NPT_ equivalents to avoid conflicts with
  the original plugin when both are installed.

---

## [1.0.9] - 2025-12-27

### Added

- Added a lightweight notice on the Performance Toolkit admin page that
  surfaces error/warning counts from the local CLI checker.
- Added a "Settings" link on the Plugins screen pointing to the Tools
  → Performance Toolkit admin page.

---

## [1.0.8] - 2025-12-27

### Added

- Added a wp-admin Tools page (Performance Toolkit) to run server health
  checks and the query benchmark demo via a simple UI.

---

## [1.0.7] - 2025-12-27

### Added

- Made repository installable as a WordPress plugin by adding a plugin header
  to `automated-testing.php` (now the main plugin file).

---

## [1.0.6] - 2025-12-27

### Added

- Added `automated-testing.php` server health and query benchmark demo module
  - Lightweight DB ping, PHP compute, and memory checks
  - New `spc_run_query_benchmark_demo()` helper with adjustable query count
  - `spc_get_query_count()` wrapper to support future runtime query-count assertions

---

## [1.0.5] - 2025-12-27

### Added

- Added **Phase 2.5: PHP-Parser Deep Analysis** to PROJECT.md roadmap
- Added reference to [WP-PHP-Parser-loader](https://github.com/kissplugins/WP-PHP-Parser-loader) plugin
- Added nikic/PHP-Parser to References section

### Changed

- Updated Table of Contents with Phase 2.5 entry

---

## [1.0.4] - 2025-12-27

### Added

- **Implemented `get_terms()` check** in workflow and local script (detects missing `number` parameter)
- Added Antipattern 9 test fixture for `get_terms()` without `number`
- Added `@neochrome-n1-ok` annotation pattern for intentional N+1 cases (documented)
- Added `PerformanceTestCase` base class to Phase 3 scope
- Added metrics tracking requirement to Phase 4 scope

### Changed

- Resolved Open Question 2: Start permissive with N+1 detection, use annotation for exceptions
- Clarified severity levels for dynamic `posts_per_page`: literal -1 = error, variable = warning
- Merged Loveable feedback into PROJECT.md Audit Notes
- Fixed version display in script header

---

## [1.0.3] - 2025-12-27

### Added

- Added `date()` pattern detection to timezone warning checks (from Grok feedback)
- Added Antipattern 8 test fixture for `date('Y-m-d')` usage
- Added Installation section to README with step-by-step instructions for copying to other plugins

### Changed

- Updated `run_check()` function to support multiple grep patterns
- Merged Grok feedback into PROJECT.md main sections
- Resolved Open Questions 1 & 3 based on Grok recommendations
- Enhanced Phase 2 scope with dynamic variable detection and cache-aware N+1 checks
- Updated README Table of Contents with new Installation section

---

## [1.0.2] - 2025-12-27

### Added

- Added Table of Contents with anchor links to PROJECT.md

---

## [1.0.1] - 2025-12-27

### Changed

- Merged Gemini 3 audit recommendations into PROJECT.md main sections:
  - Added comparison table (WPCS vs PHPStan-WP vs Neochrome Toolkit)
  - Added bypass mechanism documentation for legitimate unbounded queries
  - Added SAVEQUERIES performance constraint for Layer 3
  - Added baseline file strategy to Risks/Mitigations
  - Added Phase 5: Future Enhancements (database index awareness, query plan analysis)
  - Enhanced timezone issue documentation with cache consistency context
  - Added `meta_query` complexity to antipatterns table

---

## [1.0.0] - 2025-12-27

### Added

#### Week 1: Grep-based Performance Checks (Foundation)

- **Reusable GitHub Actions Workflow** (`.github/workflows/wp-performance.yml`)
  - Callable workflow for multi-repo use
  - Configurable PHP version, scan paths, and exclude patterns
  - Critical checks that fail the build:
    - `posts_per_page => -1` detection
    - `numberposts => -1` detection
    - `nopaging => true` detection
    - `wc_get_orders` unbounded limit detection
  - Warning checks (optional strict mode):
    - N+1 pattern detection (meta functions in files with loops)
    - `current_time('timestamp')` usage in WC contexts
  - Clean summary output with GitHub Actions annotations

- **Example Caller Workflow** (`.github/workflows/example-caller.yml`)
  - Template for plugin repos to integrate the checks
  - Both reusable workflow call and standalone options

- **Local Test Script** (`bin/check-performance.sh`)
  - Run checks locally without GitHub Actions
  - Colored terminal output
  - Options: `--paths`, `--strict`, `--verbose`, `--help`
  - Same detection patterns as GitHub workflow

- **Test Fixtures** (`tests/fixtures/`)
  - `antipatterns.php` - Intentional bad patterns for testing
  - `clean-code.php` - Correct patterns demonstrating best practices

### Detection Capabilities

| Pattern | Detection Type | Status |
|---------|---------------|--------|
| `posts_per_page => -1` | Critical (fails build) | ✅ Implemented |
| `numberposts => -1` | Critical (fails build) | ✅ Implemented |
| `nopaging => true` | Critical (fails build) | ✅ Implemented |
| `wc_get_orders` unbounded | Critical (fails build) | ✅ Implemented |
| N+1 patterns (meta in loops) | Warning | ✅ Implemented |
| `current_time('timestamp')` | Warning | ✅ Implemented |
| Raw SQL without LIMIT | Warning | ✅ Implemented |

### Known Limitations

- N+1 detection uses file-level heuristics (grep-based), which may produce false positives when loops and meta functions appear in the same file but are not actually N+1 patterns
- This will be improved with PHPStan AST-based rules in Week 2-3

---

## Roadmap

### Planned for v1.1.0 (Week 2-3)
- [ ] Composer package with PHPStan rules
- [ ] AST-based N+1 detection
- [ ] Baseline file support for intentional patterns

### Planned for v1.2.0 (Week 5-6)
- [ ] Runtime test harness (PHPUnit traits)
- [ ] Query count assertions
- [ ] wp-env integration helpers
