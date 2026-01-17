
# Project Automation: Two-Pass JSON → HTML Workflow (Deterministic Scan + AI Triage)

## Table of contents + checklist (high level)

- [ ] **Define report contract (JSON schema)**
  - [ ] Include stable fields for scan metadata + findings
  - [ ] Include a **blank placeholder** for Phase 2 AI triage output
  - [ ] Include explicit status + timestamps for Phase 2
- [ ] **Phase 1: Deterministic scan** (shell/grep pipeline)
  - [ ] Write JSON report (with placeholder)
  - [ ] Generate HTML from JSON (HTML clearly shows Phase 2 as “Not performed yet”)
- [ ] **Phase 2: VS Code agent AI triage** (local)
  - [ ] Read JSON, detect placeholder/status=pending
  - [ ] Insert structured triage into JSON (no HTML editing)
  - [ ] Re-run JSON → HTML generator
- [ ] **Server-side compatibility**
  - [ ] Upload/store the **final JSON** (single source of truth)
  - [ ] Server converts JSON → HTML using same contract
- [ ] **Operational concerns**
  - [ ] Re-scan behavior (preserve or invalidate Phase 2)
  - [ ] Provenance (model/tool version, prompt hash, timestamps)
  - [ ] Safety disclaimers + user messaging

---

## Goal

Produce a **single JSON report artifact** that supports:

1. **Phase 1**: deterministic, reproducible static scanning (current bash/grep scanner)
2. **Phase 2**: optional AI-assisted triage (local VS Code agent) that adds a “fast but detailed enough” false-positive review
3. **HTML rendering** from JSON for both local dev workflows and server-generated reports

The key refinement: **Phase 2 output is written back into the JSON** (in a dedicated placeholder field), not injected into HTML.

---

## Why a JSON placeholder matters (design intent)

- **Single source of truth**: JSON becomes the canonical report that can be uploaded and rendered anywhere.
- **Idempotent rendering**: HTML is always a pure function of JSON (Phase 1-only JSON renders a Phase 2 “pending” section).
- **Workflow friendliness**: the agent can safely update only one file (JSON), then re-render.
- **Better diff/PR review**: JSON changes cleanly show “what the agent added”.

---

## Proposed report contract (Phase 1 + Phase 2)

### Minimal structure (illustrative)

Keep this intentionally small and stable. The server-side renderer should rely on these fields.

- `report_version` (string)
- `generated_at` (ISO-8601 string)
- `project` (object: name/path/ref)
- `scan` (object: tool version, ruleset id, runtime info)
- `findings` (array)
- `ai_triage` (object) **← Phase 2 placeholder lives here**

### Placeholder object for Phase 2 (recommended)

**Phase 1 writes this block (blank/pending):**

- `ai_triage.status`: `"pending" | "complete" | "error" | "skipped"`
- `ai_triage.generated_at`: `null` initially
- `ai_triage.tool`: info about the triage tool/agent (null/empty initially)
- `ai_triage.summary`: `null` initially
- `ai_triage.items`: `[]` initially
- `ai_triage.notes_md`: `""` (optional; for a human-readable markdown blob)

Rationale:
- `status` makes downstream rendering deterministic.
- `items` supports linking triage decisions to specific findings.
- `notes_md` enables a “fast narrative” without breaking structured data needs.

---

## Phase 1: Deterministic scan (current bash/grep)

### Responsibilities

- Collect findings deterministically.
- Output JSON that includes:
  - scan metadata
  - findings list
  - **Phase 2 placeholder**
- Run JSON → HTML generator.

### Output invariant

After Phase 1:
- JSON exists and is valid.
- `ai_triage.status` is `pending` (or `skipped` if explicitly disabled).
- HTML exists and includes a Phase 2 section that clearly indicates “Not performed yet”.

---

## Phase 2: VS Code agent AI triage (local)

### Responsibilities

- Read the JSON report.
- Confirm it is eligible for triage:
  - `ai_triage.status === "pending"` (or re-triage is explicitly requested)
  - report version is supported
- Perform a focused triage pass:
  - goal: reduce obvious false positives and provide actionable next steps
  - output should be “fast but detailed enough”, not a full security audit
- Write results into `ai_triage`:
  - set `status="complete"`
  - add `generated_at`
  - capture provenance (model name/version if available, prompt version/hash)
  - produce both:
    - structured per-finding decisions (in `items`)
    - optional narrative `summary` / `notes_md`
- Re-run JSON → HTML generator.

### Suggested per-finding triage item fields

Each triage item should be linkable to a deterministic finding:
- `finding_id` (stable id from Phase 1; avoid array index)
- `verdict`: `"likely_false_positive" | "likely_valid" | "needs_review"`
- `confidence`: `low | medium | high`
- `reason` (short)
- `evidence` (optional: snippets/paths/line refs)
- `suggested_fix` (optional)

---

## HTML rendering requirements (local and server)

### Rendering rules

- The HTML report must always render an “AI triage” section.
- If `ai_triage.status === "pending"`:
  - show a neutral placeholder (“Not performed yet”)
  - show instructions (how to run Phase 2)
  - show disclaimer text
- If `ai_triage.status === "complete"`:
  - show summary metrics + narrative
  - show per-finding verdicts and link back to findings

### Keep disclaimers explicit

The AI triage section should include a prominent disclaimer that the content is probabilistic and requires human verification.

---

## Re-scan / overwrite semantics (important)

A common footgun: users will re-run Phase 1 after Phase 2.

Recommended policy:

- Phase 1 always regenerates findings.
- If the set of findings changes materially, Phase 1 should either:
  1. **Invalidate Phase 2** by setting `ai_triage.status="pending"` and clearing triage fields, or
  2. Preserve Phase 2 *only if* findings are stable and matched by `finding_id`.

Practical suggestion:
- include a `scan.findings_hash` field
- Phase 2 records the `scan.findings_hash` it analyzed
- HTML renderer warns if triage hash != current findings hash

---

## Server-side pipeline (future)

- Treat JSON reports as uploadable artifacts.
- Server job converts JSON → HTML using the same contract.
- Server does **not** need to run the AI step (optional). It just renders what’s present:
  - pending placeholder renders
  - completed triage renders

---

## Suggested local automation flow (operator view)

1. Run Phase 1 scan:
   - produces `report.json` with `ai_triage.status=pending`
   - produces `report.html` with Phase 2 placeholder
2. (Optional) Run Phase 2 triage:
   - updates `report.json` (`ai_triage.status=complete` + content)
   - regenerates `report.html`

---

## Open questions (to decide soon)

- JSON schema versioning strategy (`report_version` semantics)
- Where `finding_id` comes from (hashing path+rule+line+snippet?)
- Whether Phase 2 outputs **only** narrative, only structured, or both (recommended: both)
- How to handle private code / model selection / offline vs hosted LLM
