**STATUS:** Not Started
**Author:** GitHub Copilot (Chat GPT 5.2)
**PRIORITY**: High

## Table of Contents

- [Phased Progress Checklist (High Level)](#phased-progress-checklist-high-level)
- [Phase 1 — Reduce Obvious False Positives (Low Risk, High Impact)](#phase-1--reduce-obvious-false-positives-low-risk-high-impact)
- [Phase 2 — Add Context Signals (Guards + Sanitization) to Improve Triage](#phase-2--add-context-signals-guards--sanitization-to-improve-triage)
- [Phase 3 — Reclassify Findings (Categories + Severity Defaults)](#phase-3--reclassify-findings-categories--severity-defaults)
- [Acceptance Criteria](#acceptance-criteria)

> **Note for the LLM/agent:** As each task is completed, continuously update this document by ticking the relevant checklist items (`[x]`).

## Phased Progress Checklist (High Level)

- [ ] **Phase 1 complete:** Scanner no longer flags PHPDoc/comment-only matches; avoids POST-method false positives in HTML/REST config.
- [ ] **Phase 2 complete:** Findings include context signals (nonce/cap checks; sanitizer detection) and are downgraded appropriately.
- [ ] **Phase 3 complete:** Findings are categorized (security vs best-practice vs performance) with clearer default severities.

## Phase 1 — Reduce Obvious False Positives (Low Risk, High Impact)

### Goal
Eliminate the most common “clearly wrong” matches that do not represent executable code paths.

### Checklist
- [ ] **Comment/docblock aware matching**
  - [ ] Ignore matches inside PHPDoc blocks (`/** ... */`).
  - [ ] Ignore matches inside block comments (`/* ... */`).
  - [ ] Ignore matches inside single-line comments (`// ...`).
  - [ ] Regression check: a docblock like `@uses wp_remote_get()` no longer triggers `http-no-timeout`.

- [ ] **Stop treating HTML/REST config as superglobal access**
  - [ ] Ensure rules like `spo-002-superglobals` only match real superglobal tokens (e.g., `$_GET[` / `$_POST[` / `$_REQUEST[` / etc.).
  - [ ] Explicitly exclude/avoid matching:
    - [ ] `<form ... method="POST">` (HTML attribute)
    - [ ] `array( 'methods' => 'POST', ... )` (REST route config)

### Deliverables
- [ ] Updated scanner logic/patterns to ignore comment/docblock contexts.
- [ ] Updated superglobal rules to match only executable access patterns.
- [ ] A small regression fixture set covering:
  - [ ] docblock `@uses` vs real function call
  - [ ] HTML `<form method="POST">`
  - [ ] REST route `'methods' => 'POST'`

## Phase 2 — Add Context Signals (Guards + Sanitization) to Improve Triage

### Goal
Keep reporting potentially risky patterns, but attach “context” so reviewers can triage faster and reduce high-severity noise.

### Checklist
- [ ] **Guard heuristics (nearby checks)**
  - [ ] If a superglobal read is preceded within ~N lines by `check_ajax_referer(`, downgrade severity (e.g., `error -> review`).
  - [ ] If preceded within ~N lines by `wp_verify_nonce(` (or equivalent nonce checks), downgrade severity.
  - [ ] If preceded within ~N lines by `current_user_can(` (or wrapper), downgrade severity.
  - [ ] Output should record which guard(s) were detected (e.g., `guards: ['check_ajax_referer','current_user_can']`).

- [ ] **Sanitizer/caster detection on superglobal reads**
  - [ ] Detect common WP sanitizers/casters wrapping input (examples):
    - [ ] `sanitize_text_field( $_GET[...] )`
    - [ ] `sanitize_email( $_POST[...] )`
    - [ ] `absint( $_GET[...] )`
    - [ ] `esc_url_raw( $_REQUEST[...] )`
  - [ ] Output should record which sanitizer was detected (e.g., `sanitizers: ['sanitize_email']`).

- [ ] **Refine `$wpdb->prepare()` finding severity when no user input exists**
  - [ ] If SQL is a literal and only includes safe identifiers (e.g. `{$wpdb->options}`), classify as best-practice / lower severity.
  - [ ] Keep higher severity for concatenated SQL that includes superglobals or other tainted variables.

### Deliverables
- [ ] JSON output augmented with guard/sanitizer hints.
- [ ] Severity downgrade rules for “guarded” findings.
- [ ] Regression fixtures for guarded vs unguarded superglobal reads.

## Phase 3 — Reclassify Findings (Categories + Severity Defaults)

### Goal
Separate “likely vulnerability” from “context-dependent security hygiene” and “best practice” so output is easier to consume.

### Checklist
- [ ] **Add/standardize rule categories**
  - [ ] `security-vuln-likely`
  - [ ] `security-context-dependent`
  - [ ] `best-practice`
  - [ ] `performance`

- [ ] **Define default severity per category**
  - [ ] Ensure best-practice rules (e.g., missing explicit timeout) do not default to the same “HIGH” urgency as exploitable patterns.

- [ ] **Update reporting summary**
  - [ ] Summaries should group by category and severity.
  - [ ] Ensure the report can clearly answer:
    - [ ] “How many confirmed?”
    - [ ] “How many false positives?”
    - [ ] “How many need review?”

### Deliverables
- [ ] Updated pattern metadata schema (if needed) to include `category` and default severity.
- [ ] Updated report generator to group by category.

## Acceptance Criteria

- [ ] Running the scanner on `/temp` (WP Health Check plugin) shows:
  - [ ] No findings triggered purely by docblocks/comments.
  - [ ] No findings triggered by HTML `<form method="POST">`.
  - [ ] No findings triggered by REST route `'methods' => 'POST'`.
  - [ ] Superglobal findings include guard/sanitizer context when present.
  - [ ] `$wpdb->query()` “no prepare” static queries are reduced in severity / categorized as best-practice.
  - [ ] Reports clearly separate security-vuln-likely vs best-practice vs performance.