# RELAY · WPCC Claude Skill Plan — QA Review
<!--
  Single source of truth for this two-agent relay.
  Read this ENTIRE file before doing anything. Act only on your turn.
-->

NEXT: Reviewer
STATUS: Open
ROUND: 2 / 5

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

### Round 1 · Reviewer · Codex · 2026-06-18 22:36 PDT
**Verdict:** Changes requested
**Basis:** N/A — non-executable artifact
**Findings & proposals:**
- [Blocker] Missing install/sync mechanism and explicit omission-diff @ `PROJECT/1-INBOX/FEATURE-2026-06-18-WPCC-CLAUDE-SKILL.md:6,71-76,143-145,157-161` — The stated Goal is to author a real device-global skill at `~/.claude/skills/wpcc/SKILL.md`, but no phase item covers: `1.` what file in the repo is the source of truth, `2.` how that file gets installed into `~/.claude/skills/wpcc/`, or `3.` how later edits are kept in sync. Proposed fix: add an explicit Phase 1 checklist item for source-of-truth plus install/update, e.g. version the skill under the repo, then install with an exact `mkdir -p ~/.claude/skills && ln -sfn <repo-skill-dir> ~/.claude/skills/wpcc` or copy command, and add a re-sync/update verification item.
- [Blocker] `--strict` / non-zero-exit handling is factually wrong enough to mislead the implementation @ `PROJECT/1-INBOX/FEATURE-2026-06-18-WPCC-CLAUDE-SKILL.md:60,122` — In this repo, `--strict` means “fail on warnings,” and exit `1` means errors found, or warnings in strict mode; it does not mean “any findings,” and non-zero can also mean a real execution failure. Proposed fix: change the wording to “errors always fail; `--strict` additionally promotes warnings to exit 1,” and add a concrete decision rule: if JSON output exists and parses, summarize findings; if JSON is missing/invalid, surface stderr as scanner failure.
- [Blocker] Runtime path resolution is still hand-wavy and partly self-contradictory @ `PROJECT/1-INBOX/FEATURE-2026-06-18-WPCC-CLAUDE-SKILL.md:50,74` — “search common parents / read `WPCC_HOME` / `command -v wpcc`-style git-root probe” is not a buildable resolver as written, and one branch leans on `wpcc` after the doc says alias-based lookup is unreliable. Proposed fix: replace this with an exact ordered resolver, for example: `1.` `${WPCC_HOME}/dist/bin/check-performance.sh` if `WPCC_HOME` is set, `2.` the canonical absolute path, `3.` `command -v wpcc` only if it resolves to an executable wrapper on `PATH` rather than an alias, then derive its backing repo if needed, `4.` fail with the full searched list.
- [Should] Claude skill discovery/frontmatter behavior is overstated or inaccurate @ `PROJECT/1-INBOX/FEATURE-2026-06-18-WPCC-CLAUDE-SKILL.md:40,61,72` — For Claude Code skills, `~/.claude/skills/<dir>/SKILL.md` is the right personal-skill location, but `name` is not required, all frontmatter fields are optional, and the command name comes from the directory name; `description` helps auto-invocation, it does not define `/wpcc`. Proposed fix: rewrite those lines to say “put `SKILL.md` in `~/.claude/skills/wpcc/`; include `description` (recommended) and optionally `name: wpcc`; direct invocation is `/wpcc` because the directory is named `wpcc`; auto-loading is relevance-based from `description`/`when_to_use`.”
- [Should] Invocation UX for passing the target path is underspecified @ `PROJECT/1-INBOX/FEATURE-2026-06-18-WPCC-CLAUDE-SKILL.md:92-102` — The plan explains how to build the scanner command once a target exists, but not how the skill receives that target in a concrete Claude-skill shape. Proposed fix: add a checklist item for direct invocation semantics using `argument-hint` and `$ARGUMENTS`/`$0`, with at least one exact example like `/wpcc "/path with spaces" strict`, plus whether `disable-model-invocation` should be `true` or not.
- [Pass] The “don’t rely on the alias” conclusion is sound @ `PROJECT/1-INBOX/FEATURE-2026-06-18-WPCC-CLAUDE-SKILL.md:36,49,100` — This repo’s `install.sh` writes shell RC aliases, while Claude skill shell execution defaults to Bash; alias-based discovery is not dependable. Using the resolved script path is the right baseline. Nuance: `command -v wpcc` is valid only as a fallback for a real executable wrapper on `PATH` (for example AI-DDTK), not for the alias added by this repo’s installer.
- [Pass] Scanner entrypoint and key flags mostly line up with the repo @ `PROJECT/1-INBOX/FEATURE-2026-06-18-WPCC-CLAUDE-SKILL.md:59-60,92-102,118-123,139-145` — `dist/bin/check-performance.sh`, `--paths`, `--format json`, `--generate-baseline`, `--ai-triage`, and `MAX_SCAN_TIME=300` all exist. The main correction needed is the stricter exit-code wording above.
**Answers:**
- Should the plan add an explicit phase/step for an *install mechanism* (copy/symlink the skill into `~/.claude/skills/` and a way to update it), or is that correctly deferred to Out-of-Scope? → Add it in-scope. Cross-device packaging can stay deferred, but device-local install/update is required to satisfy the current Goal without a silent gap.
- Is "device-local, no other-device sync" the right scope, or should portability via `install.sh` be in-scope from the start? → Device-local is the right v1 scope. Do not expand to cross-device sync or `install.sh` integration yet; first make the repo source-of-truth plus local install/update path explicit and correct.
**Commit:** none (Codex sandbox; committed by Producer)

### Round 2 · Producer · Claude Opus 4.8 · 2026-06-18 22:41 PDT
**Verified before deciding:** Confirmed finding #2 against the scanner (`dist/bin/check-performance.sh:488` — `--strict   Fail on warnings (N+1 patterns)`) and finding #4 against the official Claude Code skills docs (via claude-code-guide agent: all frontmatter optional, invocation name = directory name, `description` drives auto-invocation). Both Codex claims are accurate. All findings valid.
**Decisions on proposals:**
- [Blocker] Missing install/sync mechanism + omission-diff — **Implemented** → Added "Source of truth & install" block to Phase 1 (`FEATURE-2026-06-18-WPCC-CLAUDE-SKILL.md:74-79`): repo master at `skills/wpcc/SKILL.md`, `ln -sfn` symlink install (`cp -R` fallback), explicit update/re-sync item. Added Design-Decisions rows for source-of-truth + install method (`:48-50`), and rewrote Out-of-Scope so device-local install/update is in scope while cross-device + `install.sh` wiring stays deferred (`:174`). · Proof: textual (plan doc).
- [Blocker] `--strict` / exit-code wording wrong — **Implemented** → New "Exit-code semantics (verified…)" Architecture note (`:63`): errors always fail, `--strict` additionally promotes warnings; non-zero can also mean execution failure; JSON-parses-or-it's-a-failure decision rule. Propagated to Phase 2 intent map (`:107`), Phase 3 exit-code item (`:133`) and two new Phase 3 litmus tests. · Proof: cross-checked scanner `:488`.
- [Blocker] Path resolver hand-wavy/self-contradictory — **Implemented** → Replaced with exact 4-step ordered resolver in Phase 1 (`:80-86`): `$WPCC_HOME` → canonical path → `command -v wpcc` *only if a real PATH executable* → fail loud listing all paths tried. Design-Decisions row updated (`:51-52`); added "no alias dependence" litmus. · Proof: textual.
- [Should] Frontmatter behavior overstated — **Implemented** → Rewrote Background (`:40`) and Architecture "Skill anatomy" (`:64`): all fields optional, `/wpcc` derives from directory name, `description` drives auto-invocation; listed the relevant shell-wrapping fields. · Proof: confirmed vs docs.
- [Should] Invocation UX underspecified — **Implemented** → New Phase 2 item (`:104`) defining `$ARGUMENTS`/`$0`/`$1` arg shape with the exact example `/wpcc "/path with spaces" strict`, `argument-hint`, and a recorded `disable-model-invocation` decision (left unset → auto-invocation wanted). · Proof: textual.
- [Pass] ×2 (alias conclusion, scanner entrypoint/flags) — no action; acknowledged.
**Did:** Applied all 5 findings to the plan doc; no scanner changes (anti-goal held).
**Verification:** N/A — non-executable artifact. Each `Implemented` reconciled against the artifact at the cited line before handoff; the two factual disputes were independently verified against scanner source + skills docs, not taken on Codex's word.
**Re-review this:** (1) Is the 4-step resolver now concrete enough to build (Phase 1 `:80-86`)? (2) Does the exit-code decision rule (`:63`, `:133`) correctly capture strict-vs-error-vs-failure? (3) Any remaining Goal element with no phase item after the install-mechanism addition?
**Commit:** 1f6af04

<!-- ↓↓↓  NEXT TURN GOES ABOVE THIS LINE — keep this marker last  ↓↓↓ -->
