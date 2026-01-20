# GREP-Detectable Anti-Patterns (Code Quality Scanner)
Date: 2026-01-16
Status: Not Started
Source: KISS Smart Batch Installer (SBI) MKII plugin failed FSM patterns

This list highlights common anti-patterns observed in this project that can be detected with simple GREP / ripgrep rules. The intent is to catch regressions early in code review or CI.

## Viability Summary (Pattern Library Readiness)
- **Overall**: Viable with tuning. These are practical as "early warning" grep rules, but should be marked as **contextual** (review-required) to avoid false positives.
- **Best candidates**: 1, 2, 6, 7 (clear anti-pattern intent, low ambiguity in SBI context).
- **Higher risk of false positives**: 3, 4, 5 (common strings in unrelated files or legitimate uses).
- **Recommendation**: Keep them as "warning" severity, add scope hints (PHP/JS files) and regex anchoring where possible.

---

## 1) Multiple Refresh Endpoints / Overlapping Actions
**Problem**: Different AJAX actions for the same behavior increase brittleness and inconsistency.

**GREP Patterns**
- `sbi_refresh_repository`
- `sbi_refresh_status`

**Generic Pattern (`wp-check`):**
```json
{
  "id": "overlapping-actions",
  "severity": "warning",
  "description": "Detects likely overlapping refresh-related AJAX actions",
  "grep": "\\b([a-z0-9_]+_)?refresh_(repository|status|data|cache)\\b"
}
```

**Interpretation**
- If both appear in active code paths, you likely have redundant refresh flows.
- **Viability**: High. This is a known failure mode in SBI and easy to spot in code review.
- **Refinement**: Prefer scoping to AJAX hooks (e.g., `wp_ajax_`) when feasible to reduce noise.

---

## 2) Mixed Rendering Paths
**Problem**: Mixing server-rendered HTML with client-side DOM manipulation leads to duplication (e.g., duplicated buttons).

**GREP Patterns**
- `row_html`
- `rows_html`
- `append\(html\)`
- `prepend\(html\)`
- `after\(html\)`
- `before\(html\)`
- `innerHTML =`

**Generic Pattern (`wp-check`):**
```json
{
  "id": "mixed-rendering-paths",
  "severity": "warning",
  "description": "Detects mixing of server-side and client-side rendering",
  "grep": "(row_html|rows_html|append\\(html\\)|prepend\\(html\\)|after\\(html\\)|before\\(html\\)|innerHTML\\s*=)"
}
```

**Interpretation**
- If you render HTML in the backend **and** set DOM with `innerHTML`/`append`, ensure a single owner of rendering.
- **Viability**: High. Detects the exact class of regressions that created duplicate UI in SBI.
- **Refinement**: Scope to JS files to avoid matching PHP string templates that never execute.

---

## 3) Inline Script for Core Actions
**Problem**: Inline JS actions bypass the primary frontend controller and diverge from FSM-driven flow.

**GREP Patterns**
- `<script>` (within PHP templates)
- `$(document).on\('click', '\.[a-zA-Z0-9_-]+` (inline jQuery handlers)

**Generic Pattern (`wp-check`):**
```json
{
  "id": "inline-script-for-core-actions",
  "severity": "warning",
  "description": "Detects inline scripts for core actions",
  "grep": "(<script>|\\$\\(document\\)\\.on\\('click', '\\.[a-zA-Z0-9_-]+)"
}
```

**Interpretation**
- Core action handlers should live in a dedicated JS/TS module.
- **Viability**: Medium. `<script>` is noisy; useful if restricted to specific templates or admin pages.
- **Refinement**: Prefer scoping to `templates/` or `admin` views and ignore vendor/compiled assets.

---

## 4) Shadow State Stores / Globals
**Problem**: Global variables and ad-hoc flags compete with FSM state.

**GREP Patterns**
- `window\.[a-zA-Z0-9_]+`
- `var .* = .*; // fallback`

**Generic Pattern (`wp-check`):**
```json
{
  "id": "shadow-state-stores-globals",
  "severity": "warning",
  "description": "Detects shadow state stores and globals",
  "grep": "(window\\.[a-zA-Z0-9_]+|var\\s+[^=]+?=\\s+[^;]+;\\s*\\/\\/\\s*fallback)"
}
```

**Interpretation**
- Any fallback/global state should be explicitly quarantined or removed.
- **Viability**: Medium. Legitimate globals exist; this is more useful as a review prompt than a strict violation.
- **Refinement**: Consider narrowing to `window\\.sbi_`-style namespaces once a naming standard is defined.

---

## 5) Duplicate Diagnostics Panels
**Problem**: Multiple debugging systems (SSE diagnostics, AJAX debug, inline logs) fragment observability.

**GREP Patterns**
- `debugLog`
- `sbiDebug`
- `debug-panel`
- `sse-diagnostics`

**Generic Pattern (`wp-check`):**
```json
{
  "id": "duplicate-diagnostics-panels",
  "severity": "warning",
  "description": "Detects duplicate diagnostics panels",
  "grep": "(debugLog|sbiDebug|debug-panel|sse-diagnostics)"
}
```

**Interpretation**
- Diagnostics should be centralized and share a common schema.
- **Viability**: Medium. Common tokens can appear in legitimate debug tooling or test fixtures.
- **Refinement**: Consider requiring two or more tokens in the same file to reduce noise.

---

## 6) Action Buttons Always Rendered Regardless of State
**Problem**: Always rendering generic actions (like Refresh) increases DOM churn and duplication risk.

**GREP Patterns**
- `sbi-refresh-status`
- `class="button button-secondary sbi-refresh-status"`

**Generic Pattern (`wp-check`):**
```json
{
  "id": "action-buttons-always-rendered",
  "severity": "warning",
  "description": "Detects action buttons that are always rendered regardless of state",
  "grep": "class=\"button button-secondary sbi-refresh-status\""
}
```

**Interpretation**
- If `Refresh` is always appended while other actions are conditional, consider standardizing action rendering logic.
- **Viability**: High in SBI. This is a very specific and actionable UI regression detector.
- **Refinement**: If generalized, use a named button class convention rather than literal strings.

---

## 7) Hidden State Transitions in Non-FSM Paths
**Problem**: Calling FSM transitions from many different code paths can cause races.

**GREP Patterns**
- `refresh_state\(`
- `transition\(`
- `window.dispatchEvent`

**Generic Pattern (`wp-check`):**
```json
{
  "id": "hidden-state-transitions",
  "severity": "warning",
  "description": "Detects hidden state transitions in non-FSM paths",
  "grep": "(refresh_state\\(|transition\\(|window.dispatchEvent)"
}
```

**Interpretation**
- Multiple call sites should be audited and consolidated.
- **Viability**: High. This catches the "state change from anywhere" smell early.
- **Refinement**: Tighten `transition\\(` to known FSM methods if naming is standardized.

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
