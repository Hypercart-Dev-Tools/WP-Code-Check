# RELAY · WPCC Public-Entrypoint & Secret Detection Plan
<!--
  Single source of truth for this two-agent relay.
  Read this ENTIRE file before doing anything. Act only on your turn.
-->

NEXT: Reviewer
STATUS: Open
ROUND: 1 / 5

## ▶ TAKE YOUR TURN — read this first (works for ANY agent: Claude, Codex, Gemini)
The operator just said "take your turn on this file." Everything you need is **in this file** — don't wait for pasted instructions.
1. **Read this whole file** (header, Setup, Ground rules, every turn in the Log).
2. **Check it's your turn:** `NEXT` (top) names the role to act. Confirm you are the agent bound to it (see Setup) **and** the last Log block isn't already yours. If not → STOP and reply "wrong window — nudge the <other> window."
3. **Do your role's work** on the artifact named in Setup (read the real files / the latest `git show <last commit>` diff; cite `file:line`):
   - **Reviewer:** review vs the Definition of Done → graded findings (`[Blocker]`/`[Should]`/`[Nit]`/`[Pass]`), each with a concrete proposed fix → set a **Verdict** (Approved | Changes requested | Blocked). Do **not** edit the artifact; you only append findings here. **Before you set `Approved`, re-read the artifact file itself** (not this log) and confirm every prior `Implemented` fix is actually present and complete — any that is missing or partial → set `Changes requested` with a `[Blocker] claimed-implemented-but-absent @ file:line` instead. For a doc artifact this file check is the only backstop there is.
   - **Producer:** for every open finding log a disposition (Implemented / Modified / Declined + why), make the change, then add new work. **Before you flip `NEXT`, re-read the artifact and confirm each `Implemented → @ file:line` actually landed in the file** — cite the line as it appears in your commit diff. A claim you can't point to in the file is not done.
4. **Append ONE block** at the very bottom, directly **above** the marker line (`<!-- ↓↓↓ NEXT TURN ... -->`). Never edit earlier turns. Header it `### Round N · <Role> · <your-label> · <date time>`; a Reviewer block carries `**Verdict:**` + `**Findings & proposals:**` (graded bullets) + `**Commit:**`; a Producer block carries `**Decisions on proposals:**` + `**Did:**` + `**Re-review this:**` + `**Commit:**`. (Need the exact shape? Mirror the most recent block of the other role above.)
5. **Update the header:** flip `NEXT` to the other role; set `STATUS` (`Approved` closes the relay — Reviewer only; else leave `Open`); the Producer bumps `ROUND` when opening a new cycle.
6. **Commit only the files you touched** (artifact + this log): `git commit -m "relay(wpcc-detection-plan): <your-label> r<N>"`, then put the short hash in your block's `Commit:` line and `git commit --amend --no-edit`. Push if the team shares a remote.
7. **Stop.** Tell the operator your one-line result (e.g. "Changes requested, 1 Blocker — Producer's turn").

## Setup
- Artifact under review: `PROJECT/2-WORKING/P1-2026-06-18-WPCC-PUBLIC-ENTRYPOINT-SECRET-DETECTION.md`
- Definition of Done: Every detection gap from the KISS audit (issue #61) maps to a phase with an implementable check and a verifiable QA litmus; the plan is technically accurate against the real scanner in `dist/bin/check-performance.sh`; and no gap, severity-calibration lesson, or false-positive risk is silently dropped.
- Producer: Claude Code (Opus 4.8) — this window   ·   Reviewer: second session (Claude or, for true independence, Codex/Gemini)
- Handoff: manual nudge
- Started: 2026-06-18

## Ground rules
1. This file is the single source of truth. If it isn't written here, assume the other agent doesn't know it. The two agents may be different tools (e.g. Claude and Codex) and never share memory.
2. Read the whole file. Take a turn only if `NEXT` names your role — otherwise reply "not my turn" and stop.
3. One turn = one block appended at the very bottom, above the marker. Never edit earlier turns. Then update `NEXT`, `STATUS`, `ROUND` at the top. (Only exception: right after committing, fill the hash into your own just-written turn's `Commit:` line.)
4. Stay tight. Requests and findings are bullets, not essays.
5. **The Reviewer never edits the artifact.** It proposes graded findings, each with a concrete suggested fix where possible. The Producer (the original author), with the operator, decides each proposal and implements the approved ones — logging a disposition (Implemented / Modified / Declined + reason) for every one.
6. Grade every finding:  `[Blocker]` must fix to ship · `[Should]` strong recommendation · `[Nit]` optional · `[Pass]` checked and sound (records what was verified, not assumed). Answer the Producer's "Re-review this" questions in an `Answers:` block.
7. The Reviewer posts a Verdict every turn. The relay ends on **Approved** — so to get proposals actioned in-thread the Reviewer sets `Changes requested`, not `Approved`; a `[Nit]` left on an `Approved` verdict is the author's discretion, handled out-of-band. If the max `ROUND` ends without `Approved`, set `STATUS: Escalated` and hand back to the human.
8. End your turn by committing it: `relay(wpcc-detection-plan): <role> r<N>`, then fill the hash into your `Commit:` line — so the other agent can `git diff` exactly what changed. If your turn touched no tracked files (comments-only, or this log is gitignored), write `Commit: none (comments only)`.
9. **One window at a time, clean tree at every handoff.** Both agents share one working tree; the `NEXT` pointer is honor-system, not a lock. Never start a turn while the other window may still be editing, and never flip `NEXT` with uncommitted changes left in the tree — commit or stash first, so the next agent never inherits half-finished state.
10. **Evidence contract — state your proof every turn.** The Producer logs a one-line `Verification:` (what it ran / skipped / couldn't run); the Reviewer logs a verdict `Basis:` — `behaviorally proven` (ran/observed) or `textual only` (read, not run) — and classes any prior fix `textually fixed` vs `behaviorally proven`. An `Approved` can't silently mean "looked fine on read": if correctness rides on runtime behavior and nothing ran, `textual only` is the strongest honest verdict. Scales to the artifact — a pure doc answers `N/A — non-executable artifact`.
11. **Reconcile claims against the file, not this log.** A disposition is a claim until the artifact proves it. The Producer, before flipping `NEXT`, re-reads the artifact (or `git show <its commit>`) and confirms each `Implemented → @ file:line` actually landed — citing the line as it appears in the commit diff. The Reviewer, before it may set `Approved`, re-reads the **artifact itself** and confirms every `Implemented` finding is present and complete; any missing or partial one flips the verdict to `Changes requested` with a `[Blocker] claimed-implemented-but-absent @ file:line`. For a non-executable artifact (design-spec / plan doc) this file check is the only backstop — so the closing approval is never granted on the log's word alone.

## Roles
- **Producer** — the only writer of the artifact: builds it, requests review, decides and implements proposals (with the operator), updates.
- **Reviewer** — reviews against the DoD, proposes graded findings with suggested fixes, sets a verdict. Never edits the artifact.

---
## Log

### Round 1 · Producer · 2026-06-18 19:01 PDT
**Did:**
- Wrote a 6-phase plan to close the WPCC detection gaps the KISS-woo-fast-search audit (issue #61) exposed, after a controlled re-scan caught **0 of 6** issue classes as the actual issue.
- Phases: (1) scanner hygiene — exclude `vendor/`, fix the `line 3709 [: : integer expression expected` bug; (2) `php-direct-access-entrypoint` (ABSPATH-guard) — the one rule that catches all 8 scripts; (3) `secret-hardcoded` across PHP **and** JS + local-path/email leaks; (4) `js-dom-xss` + inconsistent-escape; (5) `php-privilege-simulation` + cross-method N+1; (6) severity calibration so inert WP-CLI/local-path scripts aren't labeled CRITICAL.
- Each phase carries observable checklist items + a QA checklist; added a Gap Scorecard table mapping each audit finding → target rule → phase.
**Review this:**
- **Completeness (omission-diff — do this explicitly):** walk the 6 audit findings + 2 bonus bugs and confirm each has a home in a phase. List anything in issue #61's audit with **no** equivalent in the plan (e.g. the HPOS `o.type` query bug, the `$parts[0]` guard, the toolbar null-guard — are those plugin-fix-only, or should WPCC also detect them? The plan currently omits them as out-of-scope-for-a-scanner; challenge that.)
- **Technical accuracy:** do the proposed mechanisms match how `dist/bin/check-performance.sh` actually works (inline checks, `add_json_finding`/`add_json_check`, fixture validation at ~20 fixtures)? Flag any check that assumes infrastructure that isn't there.
- **Implementability vs false positives:** Phase 2 (ABSPATH entrypoint) and Phase 5 (cross-method N+1) are the riskiest. Can they be built in bash/grep without a false-positive explosion? Is Phase 5's cross-fn N+1 realistic, or should it drop to BACKLOG?
- **Calibration:** does Phase 6's severity matrix actually prevent the "inert script labeled CRITICAL exploit" mistake that motivated this plan?
**Verification:** N/A — non-executable artifact (planning doc). Claims were cross-checked this session against the live re-scan (114 KB JSON, 1,217 files) and the per-script WP-bootstrap analysis of all 8 root scripts.
**Open questions:**
- Should cross-method N+1 (Phase 5) ship as a bounded "redundant reload" heuristic, or defer entirely to BACKLOG as too FP-prone for bash?
- Is a 4-tier severity matrix (Phase 6) the right scope, or over-engineered for a grep-based scanner?
**Commit:** f8dca89

<!-- ↓↓↓  NEXT TURN GOES ABOVE THIS LINE — keep this marker last  ↓↓↓ -->
