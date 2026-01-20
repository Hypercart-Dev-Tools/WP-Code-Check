# DRY + Architecture Checker (Grep-first) — Specification
*Generated: 2026-01-01*

This spec describes a DRY + architecture checker that **starts with an existing grep-pattern engine** backed by a **JSON ruleset**, and then progressively increases precision with lightweight structure heuristics and (optionally) AST-based analysis.

Core design principle: **deterministic detectors produce evidence** (file/line matches, counts, grouping keys). The tool reports findings and suggested remediation, and can optionally route high-signal findings to an LLM for explanation and refactor guidance.

---
## 1. Goals

- Catch high-impact duplication and architectural issues using pattern matching + aggregation.
- Run fast in CI and produce **stable, actionable results**.
- Support gradual adoption:
  - informative mode → PR comments → gated builds for agreed categories.
- Enable future evolution to AST **without rewriting** reporting/triage workflows.

## 2. Non-goals

- Perfect semantic clone detection (reserved for AST phase).
- Automatic refactoring (can be added later).
- Replacing existing linters/formatters (this targets DRY + architecture, not style).

## 3. Can we get value before AST?

Yes. Even without AST, you can catch meaningful categories:

- **Layer boundary violations** (imports/require/use across forbidden folders)
- **Repeated strings**: SQL fragments, endpoint paths, error codes/messages, feature flag keys
- **Repeated scaffolding**: retry loops, authz checks, logging wrappers (approximate via regex)
- **Organizational smells**: “god utils”, runtime code containing debug calls / TODOs without tracking

Precision is lower than AST, but signal is often strong if you combine patterns with:
- aggregation thresholds (min occurrences, min distinct files),
- path scoping (include/exclude globs),
- allowlists/suppressions.

---
## 4. Assumptions & Inputs

- A grep-pattern engine exists and loads patterns from a JSON file.
- Engine scans a file set (glob include/exclude) and emits matches with:
  - file path
  - line number(s)
  - match text
  - capture groups (if any)
- Engine can compute per-pattern aggregates (counts, distinct file counts), or you can post-process results.

### Outputs

- Human-readable report: Markdown (CI logs / PR comment body)
- Machine report: JSON and/or SARIF
- Exit-code policy configurable by severity/category

---

## 5. Execution Pipeline

1. **Collect file list** (repo root + include/exclude globs).
2. **Run patterns** and collect raw matches:
   - `{pattern_id, file, line, match, captures}`
3. **Aggregate** per pattern (and optionally per group):
   - total matches
   - distinct files
   - top repeated groups
4. **Apply thresholds** to decide which findings to emit.
5. **Render reports**:
   - Markdown summary for humans
   - JSON/SARIF payload for tooling
6. **Return exit code** based on configured severity/category gating.

### Suggested finding format (JSON)

```json
{
  "id": "ARCH.LAYER.IMPORT",
  "severity": "error",
  "category": "architecture",
  "title": "Layer boundary violation: domain imports infra",
  "group": "domain->infra",
  "evidence": [
    { "file": "src/domain/user/service.ts", "line": 12, "match": "import { Db } from '../infra/db'" },
    { "file": "src/domain/billing/charge.ts", "line": 8, "match": "from infra.db import session" }
  ],
  "remediation": "Introduce a domain interface and implement it in infra; inject dependency at the boundary."
}
```

---
## 6. Pattern JSON Schema (Recommended)

If your engine already has a schema, treat this as a mapping target.

| Field | Type | Notes |
|---|---|---|
| `id` | string | Stable identifier, e.g., `ARCH.LAYER.DOMAIN_IMPORTS_INFRA` |
| `description` | string | Purpose and rationale |
| `category` | string | `duplication`, `architecture`, `security`, `hygiene`, etc. |
| `severity` | string | `info` \| `warn` \| `error` |
| `languages` | array[string] | Optional: `ts`, `js`, `py`, `go`, `php`, etc. |
| `include_globs` | array[string] | Files to scan |
| `exclude_globs` | array[string] | Ignore vendor/build/generated paths |
| `regex` | string | The pattern (regex) |
| `regex_flags` | array[string] | Engine-defined flags, e.g., `i`, `m`, `s` |
| `group_by` | string | e.g., `full_match`, `capture:1`, `file` |
| `aggregate` | object | Optional thresholds and reporting controls |
| `message_template` | string | Human output; can interpolate captures |
| `remediation` | string | Fix guidance |
| `allowlist` | object | Suppressions by paths, ids, inline comments, etc. |

### Aggregation options (grep-first)

- `min_total_matches`: trigger only if pattern matches at least N times.
- `min_distinct_files`: trigger only if matches occur in at least N files (good DRY heuristic).
- `max_per_file`: cap noisy matches or downgrade severity.
- `top_k_groups`: report only the largest clusters.
- `dedupe_key`: normalize by capture group (endpoint path, SQL shape, error code).

---
## 7. Phased Approach (2–3 Phases)

### Phase 1 — Grep-only MVP (Immediate Value)

**Goal:** Catch obvious DRY and architecture problems with low cost and low implementation risk.

Deliverables:
- Layer boundary checks via import/require/use patterns (folder-based architecture).
- Duplicate strings: endpoints, SQL fragments, error codes/messages, feature flag keys.
- Approximate duplication smells: retry loops, auth checks, logging wrappers.
- Hygiene: ban TODO/FIXME in runtime code without tracking reference; forbid debug logs in shipping code (optional).
- CI integration: publish Markdown summary; **warn-only by default**.

Success criteria:
- Runs in CI in seconds to a couple minutes (repo-size dependent).
- Produces stable ids + file/line evidence.
- Low-noise initial ruleset + suppression support.

### Phase 2 — Grep + Lightweight Structure (No AST)

**Goal:** Improve DRY detection quality without a full parser.

Additions:
- **Normalized block fingerprinting**: strip whitespace/comments, tokenize lightly, rolling hashes over N-line windows.
- **Near-duplicate clustering**: n-gram similarity on tokens for candidate blocks (bounded to top-N candidates).
- **Regex-based import graph extraction**: detect cycles/forbidden edges; report shortest violating paths.
- Optional churn-aware prioritization (rank clusters in files that change frequently).

Success criteria:
- Meaningful reduction in false positives compared to pure regex clusters.
- Better grouping: “these 7 files share the same scaffolding block.”

### Phase 3 — AST Integration + High-precision Rules (Optional)

**Goal:** Move from syntactic to semantic evidence with lower false positives.

Additions:
- AST clone detection (normalize identifiers; hash subtrees; detect Type-2/Type-3 clones).
- Symbol-aware dependency boundaries (true module boundaries vs folders).
- Suppressions by symbol/function rather than only file paths.
- Optional: refactor suggestions / patch proposals for mechanical changes.

---
## 8. Reporting & CI Policy

Recommended rollout:
1. **Baseline mode**: run in CI, generate report artifact, no gating.
2. **PR annotations**: comment with top findings; allow suppressions.
3. **Gating**: fail builds only for selected categories (e.g., `error` architecture violations) once stable.

Noise control levers:
- Raise thresholds (`min_distinct_files`) for duplication patterns.
- Tighten `include_globs` (target `src/` only).
- Add `exclude_globs` for generated code, vendor, migrations, tests.
- Support allowlists by `(pattern id, path glob)` and optionally inline suppression comments.

---

## 9. LLM Hook (Optional)

If you add an LLM reviewer, keep it constrained:

- LLM consumes **deterministic evidence** (clusters, import violations, file/line context excerpts).
- Only send **top-ranked** clusters (size, spread across modules, churn, risk areas like auth/billing).
- Require output structure:
  - classification: acceptable duplication vs refactor candidate
  - risk explanation (drift, bugs, security, maintenance)
  - refactor plan: extraction target + interface + migration steps
  - tests to write before refactor

---

## 10. Example Pattern Set (JSON)

The patterns below are intentionally generic. Tune to your repo conventions and languages.

```json
[
  {
    "id": "ARCH.LAYER.DOMAIN_IMPORTS_INFRA",
    "description": "Domain layer should not directly import infra. Enforces hex/layered architecture boundaries.",
    "category": "architecture",
    "severity": "error",
    "languages": [
      "ts",
      "js",
      "py",
      "go",
      "php"
    ],
    "include_globs": [
      "src/domain/**/*.*",
      "domain/**/*.*"
    ],
    "exclude_globs": [
      "**/test/**",
      "**/__tests__/**",
      "**/mocks/**"
    ],
    "regex": "(from\\s+infra(\\.|/)|import\\s+.*from\\s+['\\\"](.*/)?infra/|require\\(['\\\"].*/infra/)",
    "regex_flags": [
      "i"
    ],
    "group_by": "full_match",
    "aggregate": {
      "min_distinct_files": 1
    },
    "message_template": "Domain imports infra directly: {match}",
    "remediation": "Introduce a domain interface (port) and implement it in infra; inject dependency at the composition root."
  },
  {
    "id": "ARCH.LAYER.UI_IMPORTS_DB",
    "description": "UI/web layer should not import DB/ORM clients directly.",
    "category": "architecture",
    "severity": "error",
    "languages": [
      "ts",
      "js",
      "py",
      "php"
    ],
    "include_globs": [
      "src/ui/**/*.*",
      "src/web/**/*.*",
      "web/**/*.*"
    ],
    "exclude_globs": [
      "**/test/**",
      "**/__tests__/**"
    ],
    "regex": "(prisma|typeorm|sequelize|knex|psycopg2|sqlalchemy|mongoose)\\b",
    "regex_flags": [
      "i"
    ],
    "group_by": "full_match",
    "aggregate": {
      "min_distinct_files": 1
    },
    "message_template": "UI layer references DB library/client: {match}",
    "remediation": "Route persistence through an application/service layer; keep UI focused on request/response mapping."
  },
  {
    "id": "DRY.SQL_LITERAL_DUPLICATION",
    "description": "Repeated SQL string literals suggest queries should be centralized.",
    "category": "duplication",
    "severity": "warn",
    "languages": [
      "ts",
      "js",
      "py",
      "go",
      "php"
    ],
    "include_globs": [
      "src/**/*.*"
    ],
    "exclude_globs": [
      "**/migrations/**",
      "**/test/**",
      "**/__tests__/**"
    ],
    "regex": "(?s)(SELECT|INSERT|UPDATE|DELETE)\\s+.{0,200}?\\s+FROM\\s+([A-Za-z0-9_]+)",
    "regex_flags": [
      "i",
      "s"
    ],
    "group_by": "capture:0",
    "aggregate": {
      "min_total_matches": 6,
      "min_distinct_files": 3,
      "top_k_groups": 10
    },
    "message_template": "Potential duplicated SQL query detected across files.",
    "remediation": "Extract to a query module/repository with named queries; add tests for query semantics."
  },
  {
    "id": "DRY.ENDPOINT_PATH_DUPLICATION",
    "description": "Repeated hard-coded API paths; prefer a route/constants module.",
    "category": "duplication",
    "severity": "warn",
    "languages": [
      "ts",
      "js"
    ],
    "include_globs": [
      "src/**/*.{ts,tsx,js,jsx}"
    ],
    "exclude_globs": [
      "**/test/**",
      "**/__tests__/**"
    ],
    "regex": "['\\\"]/api/v[0-9]+/[A-Za-z0-9_\\-\\/]+['\\\"]",
    "regex_flags": [
      "m"
    ],
    "group_by": "full_match",
    "aggregate": {
      "min_total_matches": 8,
      "min_distinct_files": 4,
      "top_k_groups": 15
    },
    "message_template": "Hard-coded endpoint path repeated: {match}",
    "remediation": "Centralize route definitions; expose typed helpers for clients."
  },
  {
    "id": "DRY.ERROR_CODE_DUPLICATION",
    "description": "Repeated error codes/messages across modules often drift; centralize error catalog.",
    "category": "duplication",
    "severity": "warn",
    "languages": [
      "ts",
      "js",
      "py",
      "go",
      "php"
    ],
    "include_globs": [
      "src/**/*.*"
    ],
    "exclude_globs": [
      "**/test/**",
      "**/__tests__/**"
    ],
    "regex": "(ERR_[A-Z0-9_]{3,}|E[A-Z]{2,}_[A-Z0-9_]{2,})",
    "regex_flags": [
      "m"
    ],
    "group_by": "full_match",
    "aggregate": {
      "min_total_matches": 10,
      "min_distinct_files": 5,
      "top_k_groups": 20
    },
    "message_template": "Error code appears in many locations: {match}",
    "remediation": "Create a shared error catalog + constructors; ensure consistent status mapping and messaging."
  },
  {
    "id": "ARCH.RETRY_LOGIC_SCATTERED",
    "description": "Hand-rolled retry loops scattered across codebase; centralize for consistency/backoff policies.",
    "category": "duplication",
    "severity": "warn",
    "languages": [
      "ts",
      "js",
      "py",
      "go"
    ],
    "include_globs": [
      "src/**/*.*"
    ],
    "exclude_globs": [
      "**/test/**",
      "**/__tests__/**"
    ],
    "regex": "(for\\s*\\(\\s*let\\s+\\w+\\s*=\\s*0;\\s*\\w+\\s*<\\s*(3|5|10)\\s*;.*\\)\\s*\\{[\\s\\S]{0,200}?(sleep|setTimeout)|while\\s*\\(\\s*attempt.*<\\s*(3|5|10)\\s*\\))",
    "regex_flags": [
      "i",
      "s"
    ],
    "group_by": "full_match",
    "aggregate": {
      "min_distinct_files": 3
    },
    "message_template": "Retry logic pattern appears across multiple files.",
    "remediation": "Introduce a shared retry helper with jittered backoff and standard error classification."
  },
  {
    "id": "ARCH.AUTHZ_CHECKS_SCATTERED",
    "description": "Permission checks repeated; risk of inconsistencies and bypasses.",
    "category": "duplication",
    "severity": "warn",
    "languages": [
      "ts",
      "js",
      "py"
    ],
    "include_globs": [
      "src/**/*.*"
    ],
    "exclude_globs": [
      "**/test/**",
      "**/__tests__/**"
    ],
    "regex": "\\b(hasPermission|canAccess|authorize|isAuthorized)\\s*\\(",
    "regex_flags": [
      "i"
    ],
    "group_by": "capture:0",
    "aggregate": {
      "min_total_matches": 30,
      "min_distinct_files": 10
    },
    "message_template": "Authorization checks are widespread; consider central policy evaluation.",
    "remediation": "Centralize authz policy evaluation; prefer declarative rules and shared enforcement middleware."
  },
  {
    "id": "HYGIENE.NO_TODO_IN_RUNTIME",
    "description": "TODO/FIXME in runtime code often becomes permanent; require issue link or move to backlog.",
    "category": "hygiene",
    "severity": "warn",
    "languages": [
      "*"
    ],
    "include_globs": [
      "src/**/*.*"
    ],
    "exclude_globs": [
      "**/test/**",
      "**/__tests__/**"
    ],
    "regex": "\\b(TODO|FIXME)\\b(?!.*(JIRA-\\d+|GH-\\d+|#\\d+))",
    "regex_flags": [
      "i"
    ],
    "group_by": "full_match",
    "aggregate": {
      "min_total_matches": 1
    },
    "message_template": "TODO/FIXME without tracking reference: {match}",
    "remediation": "Add an issue reference (e.g., JIRA-123 / #123) or convert to a tracked task."
  },
  {
    "id": "ARCH.FORBID_DIRECT_HTTP_IN_DOMAIN",
    "description": "Domain layer should not call HTTP clients directly.",
    "category": "architecture",
    "severity": "error",
    "languages": [
      "ts",
      "js",
      "py",
      "go",
      "php"
    ],
    "include_globs": [
      "src/domain/**/*.*",
      "domain/**/*.*"
    ],
    "exclude_globs": [
      "**/test/**",
      "**/__tests__/**"
    ],
    "regex": "\\b(fetch|axios|requests\\.|http\\.Client|curl_exec)\\b",
    "regex_flags": [
      "i"
    ],
    "group_by": "full_match",
    "aggregate": {
      "min_total_matches": 1
    },
    "message_template": "Domain layer uses direct HTTP client: {match}",
    "remediation": "Wrap outbound calls behind a port/interface; implement in an infra adapter."
  },
  {
    "id": "ARCH.GOD_UTILS_MODULE",
    "description": "Large multi-purpose utils modules are a DRY trap; they collect unrelated helpers.",
    "category": "architecture",
    "severity": "info",
    "languages": [
      "*"
    ],
    "include_globs": [
      "src/**/*utils*.*",
      "src/**/*helpers*.*"
    ],
    "exclude_globs": [
      "**/test/**",
      "**/__tests__/**"
    ],
    "regex": "^.{0,200}$",
    "regex_flags": [
      "m"
    ],
    "group_by": "file",
    "aggregate": {
      "min_total_matches": 400
    },
    "message_template": "Suspiciously large utils/helpers file (line count threshold exceeded).",
    "remediation": "Split by domain responsibility; migrate callers incrementally; add module-level ownership."
  }
]
```
---

## 11. Operational Considerations

- **Performance**: parallelize pattern execution; cap file sizes; skip binary/huge files; exclude vendor/build.
- **Stability**: keep pattern ids stable; version your ruleset; track false-positive rate over time.
- **Suppressions**: prefer explicit allowlists by id + path; avoid broad suppressions that hide real issues.
- **Ownership**: route findings to code owners (optional mapping by path prefix).
- **Safety**: treat LLM output as advisory; never auto-apply changes without review.

---

## 12. Acceptance Criteria (Phase 1)

- Runs in CI under ~2 minutes on a medium repo (adjust to your runner/repo size).
- Produces Markdown summary + machine report with stable ids and line references.
- At least 5 high-signal patterns enabled with thresholds + suppressions.
- Teams can suppress a finding with a documented allowlist mechanism.
