# RELAY · WPCC Claude Skill Plan — QA Review
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
6. **Commit only the files you touched** (artifact + this log): `git commit -m "relay(<slug>): <your-label> r<N>"`, then put the short hash in your block's `Commit:` line and `git commit --amend --no-edit`. Push if the team shares a remote.
7. **Stop.** Tell the operator your one-line result (e.g. "Changes requested, 1 Blocker — Producer's turn").

## Setup
- Artifact under review: `PROJECT/1-INBOX/FEATURE-2026-06-18-WPCC-CLAUDE-SKILL.md`
- Definition of Done: The plan is complete, technically accurate, and executable — a competent engineer could build the device-global `wpcc` Claude skill from it with no missing steps, no factual errors about how Claude skills / the WPCC scanner work, and no silent gaps between the stated goal and the phased checklist.
- Producer: Claude (Opus 4.8)   ·   Reviewer: Codex
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
8. End your turn by committing it: `relay(<slug>): <role> r<N>`, then fill the hash into your `Commit:` line — so the other agent can `git diff` exactly what changed. If your turn touched no tracked files (comments-only, or this log is gitignored), write `Commit: none (comments only)`.
9. **One window at a time, clean tree at every handoff.** Both agents share one working tree; the `NEXT` pointer is honor-system, not a lock. Never start a turn while the other window may still be editing, and never flip `NEXT` with uncommitted changes left in the tree — commit or stash first, so the next agent never inherits half-finished state.
10. **Evidence contract — state your proof every turn.** The Producer logs a one-line `Verification:` (what it ran / skipped / couldn't run); the Reviewer logs a verdict `Basis:` — `behaviorally proven` (ran/observed) or `textual only` (read, not run) — and classes any prior fix `textually fixed` vs `behaviorally proven`. An `Approved` can't silently mean "looked fine on read": if correctness rides on runtime behavior and nothing ran, `textual only` is the strongest honest verdict. Scales to the artifact — a pure doc answers `N/A — non-executable artifact`.
11. **Reconcile claims against the file, not this log.** A disposition is a claim until the artifact proves it. The Producer, before flipping `NEXT`, re-reads the artifact (or `git show <its commit>`) and confirms each `Implemented → @ file:line` actually landed — citing the line as it appears in the commit diff. The Reviewer, before it may set `Approved`, re-reads the **artifact itself** and confirms every `Implemented` finding is present and complete; any missing or partial one flips the verdict to `Changes requested` with a `[Blocker] claimed-implemented-but-absent @ file:line`. For a non-executable artifact (design-spec / plan doc) this file check is the only backstop — so the closing approval is never granted on the log's word alone.

## Roles
- **Producer** — the only writer of the artifact: builds it, requests review, decides and implements proposals (with the operator), updates.
- **Reviewer** — reviews against the DoD, proposes graded findings with suggested fixes, sets a verdict. Never edits the artifact.

---
## Log

### Round 1 · Producer · Claude Opus 4.8 · 2026-06-18 22:25 PDT
**Did:** Authored the plan `PROJECT/1-INBOX/FEATURE-2026-06-18-WPCC-CLAUDE-SKILL.md` — a device-global Claude skill (`~/.claude/skills/wpcc/SKILL.md`) so any Claude session on this machine can invoke WPCC against a target path and summarize findings. Structure: frontmatter → Status-at-a-glance table → ToC → 4 phases (scaffold/path-resolution, invocation/arg-mapping, output-parsing/summarization, robustness/docs/verification) each with observable checklist items + a QA checklist → Out-of-Scope.
**Review this (focus areas):**
- **Factual accuracy about Claude skills:** Is the claim correct that a `SKILL.md` with `name`+`description` frontmatter in `~/.claude/skills/<name>/` is auto-discovered in *every* session on the device, triggered by its description? Is the directory layout right?
- **The alias claim:** I assert the `wpcc` shell alias is invisible to Claude's Bash tool (non-interactive shell doesn't source `~/.zshrc`), so the skill must call the scanner by absolute path. Verify this is sound and that the scanner path / flags (`--paths`, `--format json`, `--strict`, `--generate-baseline`, `--ai-triage`) match `dist/bin/check-performance.sh` and `install.sh`/`SHELL-QUICKSTART.md`.
- **Completeness / omission-diff:** Does every part of the stated Goal map to a phase checklist item? Any silent gap (e.g. how the skill is *installed* / kept in sync, since it lives outside the repo at `~/.claude/skills/`)?
- **Portability assumption:** The hard-coded canonical path `/Users/noelsaw/Documents/GH Repos/wp-code-check/...` plus a runtime resolver — is the resolver concrete enough to be buildable, or hand-wavy?
- **Phase ordering & observability:** Are the QA checklists phase-appropriate and the checklist items genuinely observable/testable?
**Verification:** N/A — non-executable artifact (plan doc). Source facts cross-checked against `README.md`, `SHELL-QUICKSTART.md`, and `install.sh` in this repo while authoring.
**Open questions:**
- Should the plan add an explicit phase/step for an *install mechanism* (copy/symlink the skill into `~/.claude/skills/` and a way to update it), or is that correctly deferred to Out-of-Scope?
- Is "device-local, no other-device sync" the right scope, or should portability via `install.sh` be in-scope from the start?
**Commit:** 1cc4d7f

<!-- ↓↓↓  NEXT TURN GOES ABOVE THIS LINE — keep this marker last  ↓↓↓ -->
