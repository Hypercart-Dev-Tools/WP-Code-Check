# GREP-Detectable Anti-Patterns (Code Quality Scanner)

This list highlights common anti-patterns observed in this project that can be detected with simple GREP / ripgrep rules. The intent is to catch regressions early in code review or CI.

---

## 1) Multiple Refresh Endpoints / Overlapping Actions
**Problem**: Different AJAX actions for the same behavior increase brittleness and inconsistency.

**GREP Patterns**
- `sbi_refresh_repository`
- `sbi_refresh_status`

**Interpretation**
- If both appear in active code paths, you likely have redundant refresh flows.

---

## 2) Mixed Rendering Paths
**Problem**: Mixing server-rendered HTML with client-side DOM manipulation leads to duplication (e.g., duplicated buttons).

**GREP Patterns**
- `row_html`
- `rows_html`
- `append\(html\)`
- `innerHTML =`

**Interpretation**
- If you render HTML in the backend **and** set DOM with `innerHTML`/`append`, ensure a single owner of rendering.

---

## 3) Inline Script for Core Actions
**Problem**: Inline JS actions bypass the primary frontend controller and diverge from FSM-driven flow.

**GREP Patterns**
- `<script>` (within PHP templates)
- `$(document).on\('click', '\.sbi-` (inline jQuery handlers)

**Interpretation**
- Core action handlers should live in a dedicated JS/TS module.

---

## 4) Shadow State Stores / Globals
**Problem**: Global variables and ad-hoc flags compete with FSM state.

**GREP Patterns**
- `window\.sbi` (especially `window.sbiSystemLoading`, `window.sbiActiveRequests`)
- `var .* = .*; // fallback`

**Interpretation**
- Any fallback/global state should be explicitly quarantined or removed.

---

## 5) Duplicate Diagnostics Panels
**Problem**: Multiple debugging systems (SSE diagnostics, AJAX debug, inline logs) fragment observability.

**GREP Patterns**
- `debug` (broad scan for `debugLog`, `sbiDebug`, `debug panel`)
- `SSE` / `sse` in UI templates

**Interpretation**
- Diagnostics should be centralized and share a common schema.

---

## 6) Action Buttons Always Rendered Regardless of State
**Problem**: Always rendering generic actions (like Refresh) increases DOM churn and duplication risk.

**GREP Patterns**
- `sbi-refresh-status`
- `Refresh` (in action rendering code)

**Interpretation**
- If `Refresh` is always appended while other actions are conditional, consider standardizing action rendering logic.

---

## 7) Hidden State Transitions in Non-FSM Paths
**Problem**: Calling FSM transitions from many different code paths can cause races.

**GREP Patterns**
- `refresh_state\(`
- `transition\(`

**Interpretation**
- Multiple call sites should be audited and consolidated.

---

## Usage Notes
- These patterns are intentionally broad. When detected, **review the context** before flagging as a violation.
- The ideal is to keep canonical endpoints, single renderers, and FSM-driven state changes.

----

Follow up by ChatGPT 4.1

Here’s how I would split the IRL-KISS-SBI patterns between the GREP scanner and the PHP (tokenized) scanner:

**Best for GREP Scanner (simple, file/text-based, language-agnostic):**
1. Multiple Refresh Endpoints / Overlapping Actions  
 - Patterns: sbi_refresh_repository, sbi_refresh_status  
 - Rationale: Simple string search, no context needed.

To genericize patterns like sbi_refresh_repository and sbi_refresh_status for other plugins/themes, use a regex that matches any common namespace or prefix followed by a refresh-related action. For example:

- Regex: \b([a-z0-9_]+_)?refresh_(repository|status)\b

This will match:
- sbi_refresh_repository
- myplugin_refresh_status
- customprefix_refresh_repository

You can further generalize by allowing for other common action suffixes (e.g., refresh_data, refresh_cache):

- Regex: \b([a-z0-9_]+_)?refresh_[a-z0-9_]+\b

This approach will catch refresh actions across different naming conventions, making the rule reusable for any plugin or theme.

2. Mixed Rendering Paths  
 - Patterns: row_html, rows_html, append(html), innerHTML =  
 - Rationale: Detectable by searching for keywords in PHP/JS.

3. Inline Script for Core Actions  
 - Patterns: <script> in PHP, $(document).on('click', '.sbi-  
 - Rationale: Regex/string search in templates and JS.

5. Duplicate Diagnostics Panels  
 - Patterns: debug, SSE/sse  
 - Rationale: Broad keyword search, best as a GREP warning.

6. Action Buttons Always Rendered Regardless of State  
 - Patterns: sbi-refresh-status, Refresh  
 - Rationale: Simple keyword search in rendering code.

**Best for PHP (Tokenized) Scanner (needs code structure/context):**
4. Shadow State Stores / Globals  
 - Patterns: window.sbi*, var ... = ...; // fallback  
 - Rationale: Detecting global state and fallback logic is more robust with token/context analysis, especially in JS/PHP.

7. Hidden State Transitions in Non-FSM Paths  
 - Patterns: refresh_state(, transition(  
 - Rationale: Requires understanding call sites, function context, and FSM structure—better suited for tokenized/static analysis.

**Summary:**  
- Use the GREP scanner for broad, language-agnostic, or string-based patterns.
- Use the PHP/tokenized scanner for patterns that require code context, variable scope, or function/call analysis.