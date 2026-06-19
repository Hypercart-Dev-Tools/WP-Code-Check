---
Author: Noel (with Claude Code, Opus 4.8)
Date: 2026-06-18
Status: IN PROGRESS
Priority: P2
Goal: Author a device-global Claude skill (`~/.claude/skills/wpcc/SKILL.md`) so that any Claude Code session on this machine — regardless of working directory or repo — can invoke WP Code Check (WPCC) against a target path, summarize the findings, and hand back the report, without the user remembering the scanner's flags or absolute path.
Source: User request — "make a Claude skill file to invoke WPCC in any claude session on this device."
Scope: Skill authoring + invocation/summarization logic only. No changes to the scanner (`dist/bin/check-performance.sh`) itself.
---

## Status At A Glance

| Most Recently Completed Phase | What's Next |
|---|---|
| **Phase 3 — Output Parsing & Findings Summarization** (2026-06-18) | Phase 4 — Robustness, Docs & Cross-Session Verification |

---

## Table of Contents

- [Background](#background)
- [Design Decisions](#design-decisions)
- [Architecture Notes](#architecture-notes)
- [Phase 1 — Skill Scaffold & Scanner Path Resolution](#phase-1)
- [Phase 2 — Invocation Logic & Argument Mapping](#phase-2)
- [Phase 3 — Output Parsing & Findings Summarization](#phase-3)
- [Phase 4 — Robustness, Docs & Cross-Session Verification](#phase-4)
- [Out of Scope / Deferred](#out-of-scope)

---

## Background <a id="background"></a>

WPCC is invoked today via `dist/bin/check-performance.sh --paths <dir>` or the `wpcc` shell alias added by `install.sh`. Both have friction for AI-driven use:

1. **The `wpcc` alias is shell-config-only.** Claude Code's Bash tool launches a non-interactive shell that does not source `~/.zshrc`, so the `wpcc` alias is **not reliably available** to Claude. The skill must call the scanner by **absolute path**, not the alias.
2. **Scanner lives in one repo, but must be callable from anywhere.** A session working in `~/Local Sites/some-plugin` has no relative path to the scanner. The skill must encode/resolve a stable absolute path to `check-performance.sh`.
3. **Flags are non-obvious.** `--format json`, `--strict`, `--generate-baseline`, `--ai-triage`, `--verbose`, `--no-log` each change behavior. The skill should map plain-language intent ("scan this for security issues", "give me a baseline", "strict mode") to the right flags so the user never memorizes them.

A **Claude skill** is the right vehicle: a `SKILL.md` placed in `~/.claude/skills/wpcc/` is a *personal* skill, auto-discovered in **every** session on the device regardless of working directory. The invocation name comes from the **directory** (`wpcc/` → `/wpcc`), not from frontmatter; all frontmatter fields are optional, but `description` is recommended because it (plus optional `when_to_use`) is what Claude uses to decide auto-invocation. This is exactly the "any claude session on this device" requirement.

---

## Design Decisions <a id="design-decisions"></a>

| Decision | Choice | Why |
|---|---|---|
| Skill source of truth | A versioned `SKILL.md` **in this repo** (e.g. `skills/wpcc/SKILL.md`), installed to `~/.claude/skills/wpcc/` | Keeps the skill in git history/review; the device copy is a derivative, not the master. |
| Skill location (installed) | `~/.claude/skills/wpcc/SKILL.md` (personal skill) | Personal skills load in every session on the device, any cwd (vs. project `.claude/skills/` which is repo-scoped). Invocation name = directory name → `/wpcc`. |
| Install method | `ln -sfn <repo>/skills/wpcc ~/.claude/skills/wpcc` (symlink) | A symlink means repo edits are live with no re-copy; falls back to `cp -R` if symlinks are undesirable. |
| Scanner reference | Absolute path to `dist/bin/check-performance.sh`, via an ordered resolver | Bash tool can't see the `wpcc` alias; a resolved absolute path is the only reliable handle. |
| Path portability | Ordered resolver (see Phase 1): `$WPCC_HOME` → canonical path → `command -v wpcc` *only if* a real PATH executable → fail loud listing all paths tried | Survives the repo being moved; never silently scans nothing; never depends on a shell alias. |
| Default target | The directory the user names; if none, the session's cwd | Matches how a human runs `wpcc <dir>`. |
| Default format | `--format json` (parsed by skill), surface a human summary | JSON is machine-parseable so the skill can summarize cleanly instead of dumping raw scanner stdout into context. |
| Raw output handling | Write full report to a temp/file path, summarize top findings inline | Honors context-window discipline — large scans don't flood the conversation. |

---

## Architecture Notes <a id="architecture-notes"></a>

- **Scanner entrypoint:** `dist/bin/check-performance.sh` (repo root: `/Users/noelsaw/Documents/GH Repos/wp-code-check`). Invocation: `check-performance.sh --paths <dir> [flags]`.
- **Relevant flags** (from README/SHELL-QUICKSTART): `--paths <dir>`, `--format json`, `--strict`, `--generate-baseline`, `--ai-triage`, `--verbose`, `--no-log`.
- **Exit-code semantics (verified in `check-performance.sh`):** `--strict` means **"fail on warnings"** (e.g. N+1 patterns) — line 488. Errors always produce a non-zero exit; `--strict` *additionally* promotes warnings to a non-zero exit. A non-zero exit can therefore mean "findings present" **or** a real execution failure — so the skill must not treat non-zero as "scan succeeded with findings" unconditionally. Decision rule: if a JSON report was written and parses, summarize it; if JSON is missing/invalid, treat it as a scanner failure and surface stderr.
- **Skill anatomy (verified against Claude Code skills docs):** all `SKILL.md` frontmatter fields are **optional**; `description` is recommended (drives auto-invocation, with optional `when_to_use`). The invocation command (`/wpcc`) derives from the **directory name**, not from `name:`. Fields relevant to a shell-wrapping skill: `description`, `when_to_use`, `argument-hint`, `allowed-tools` (e.g. `Bash(...)` pre-approval), `disable-model-invocation`, and `$ARGUMENTS` / `$0` / `$1` substitution in the body.
- **No scanner changes.** This plan only adds a skill file plus (optionally) one small helper. If a helper script is needed it lives beside the skill in `~/.claude/skills/wpcc/`, not in the WPCC repo.
- **Existing reference docs to mirror, not duplicate:** `SHELL-QUICKSTART.md`, `dist/TEMPLATES/_AI_INSTRUCTIONS.md`. The skill should point to these rather than restate them.

---

## Phase 1 — Skill Scaffold & Scanner Path Resolution <a id="phase-1"></a>

Goal: a discoverable, well-described skill that lives in the repo, installs to the device, and can reliably locate the scanner from any cwd.

**Source of truth & install:**
- [ ] Author the skill in the repo at `skills/wpcc/SKILL.md` (this versioned file is the master; the `~/.claude/` copy is a derivative).
- [ ] Write the frontmatter: `description` (recommended — contains the trigger phrases below) and optionally `name: wpcc`. Note `/wpcc` comes from the **directory name**, so the install target dir must be `wpcc/`. Add `argument-hint` (e.g. `[path] [strict|baseline|triage]`) and consider `allowed-tools: Bash(...)` to pre-approve the scanner invocation.
- [ ] Install to the device: `mkdir -p ~/.claude/skills && ln -sfn "$(pwd)/skills/wpcc" ~/.claude/skills/wpcc` (symlink keeps repo edits live; document `cp -R` as the fallback).
- [ ] Document the **update/re-sync** path: with a symlink, repo edits are already live; with a copy, re-run the install command. State which was used.

**Scanner path resolution (exact ordered resolver):**
- [ ] In the skill body, record the canonical absolute scanner path: `/Users/noelsaw/Documents/GH Repos/wp-code-check/dist/bin/check-performance.sh`.
- [ ] Implement the resolver in this exact order, returning the first hit: (1) `"$WPCC_HOME/dist/bin/check-performance.sh"` if `WPCC_HOME` is set and the file exists; (2) the canonical absolute path above; (3) `command -v wpcc` **only if** it resolves to a real executable on `PATH` (not a shell alias — aliases are invisible to the non-interactive Bash tool), then derive the scanner from its backing repo; (4) if none resolve, **stop and print the full list of paths tried** rather than scanning nothing.
- [ ] Confirm the resolved scanner is executable (`-x`); document the `chmod +x` remedy if not.

**Discovery:**
- [ ] Verify the skill appears in the available-skills list of a **new** Claude session (no manual registration needed) and that `/wpcc` invokes it.

### QA Checklist — Phase 1
- [ ] **DRY:** Scanner path defined once (the resolver) and referenced everywhere — not re-typed per command.
- [ ] **Single source of truth:** The repo `skills/wpcc/SKILL.md` is the master; the `~/.claude/skills/wpcc` copy is a symlink/derivative, not a divergent hand-edited file.
- [ ] **Observability:** Path-resolution failure prints every path it tried, in order.
- [ ] **Litmus (discovery):** Open a brand-new session in an unrelated directory; `/wpcc` is available and the resolver finds the scanner.
- [ ] **Litmus (portability):** Set `WPCC_HOME` to a moved repo; resolver step 1 finds it. Unset it and move the canonical repo; resolver fails loud instead of silently doing nothing.
- [ ] **Litmus (no alias dependence):** Confirm the resolver never succeeds *only* because of the `wpcc` shell alias (which the Bash tool can't see).
- [ ] **Anti-goal check:** No edits to `check-performance.sh` or scanner logic; the only repo addition is the new `skills/wpcc/` directory.

---

## Phase 2 — Invocation Logic & Argument Mapping <a id="phase-2"></a>

Goal: translate plain-language intent into a correct scanner command.

- [ ] Document the default invocation: `check-performance.sh --paths <target> --format json`.
- [ ] **Direct-invocation argument shape:** define how `/wpcc` receives the target and modifiers via `$ARGUMENTS` / `$0` / `$1` in the skill body, with at least one exact example — e.g. `/wpcc "/path with spaces" strict` → first arg = target (quoted), trailing words = modifier keywords. Set `argument-hint` accordingly. Decide and record whether `disable-model-invocation` should be `true` (user-only) or left unset to also allow natural-language auto-invocation; default = leave unset (auto-invocation wanted).
- [ ] Define target resolution: use the path the user names; if none given, use the session cwd; confirm the target exists and looks like a WP plugin/theme/project before scanning.
- [ ] Map intents → flags in the skill body:
  - [ ] "strict" / "fail on warnings too" → `--strict` (promotes warnings like N+1 to a non-zero exit; errors already fail without it)
  - [ ] "baseline" / "snapshot current state" → `--generate-baseline`
  - [ ] "AI triage" / "explain the findings" → `--ai-triage`
  - [ ] "verbose" / "show everything" → `--verbose`
  - [ ] "don't write a log" → `--no-log`
- [ ] Specify that the scanner is run via the **Bash tool with the resolved absolute path**, never the `wpcc` alias.
- [ ] Add timeout guidance (scanner default `MAX_SCAN_TIME` is 300s) so the Bash call doesn't get prematurely killed on a large target.
- [ ] Document a quoting rule for paths containing spaces (e.g. `~/Local Sites/...`).

### QA Checklist — Phase 2
- [ ] **DRY:** Flag-mapping table is the one place intents are defined; the command template references it.
- [ ] **SOLID (single responsibility):** Phase 2 only builds the command; it does not parse output (that's Phase 3).
- [ ] **Observability:** The skill echoes the exact command it will run before running it, so the user can audit it.
- [ ] **Litmus (paths with spaces):** Scanning a target like `~/Local Sites/my-plugin` succeeds (proper quoting).
- [ ] **Litmus (no-target):** Invoking with no path falls back to cwd and confirms before scanning.
- [ ] **Anti-goal check:** Skill never depends on shell aliases or interactive-shell config.

---

## Phase 3 — Output Parsing & Findings Summarization <a id="phase-3"></a>

Goal: turn raw JSON scanner output into a concise, useful summary without flooding context.

- [ ] Capture scanner stdout to a file (temp or a stated path) rather than inline, per context-window discipline.
- [ ] Parse the JSON: total findings, counts by severity (CRITICAL / HIGH / etc.), and pass/fail check rollups.
- [ ] Render an inline summary: severity counts + the top N findings (file:line, rule-id, message) — not the full dump.
- [ ] Tell the user where the full report was written and how to view it (e.g. the JSON path, or the HTML via `json-to-html.py`).
- [ ] Disambiguate exit codes correctly: a non-zero exit means "errors found" (always) or "warnings found in `--strict` mode" **or** a real execution failure. Decision rule: if the JSON report exists and parses → summarize findings (non-zero is expected); if JSON is missing/unparseable → treat as a scanner failure and surface stderr. (Exit 124 = timeout, handled in Phase 4.)
- [ ] Handle empty / clean results with an explicit "no findings" message.

### QA Checklist — Phase 3
- [ ] **DRY:** One summarization routine handles all scan modes (normal, strict, baseline).
- [ ] **Observability:** Summary always states total count, severity breakdown, and report file path.
- [ ] **Context discipline:** Raw multi-hundred-line JSON is never pasted into the conversation; only the summary + path.
- [ ] **Litmus (findings):** Scan a known-dirty fixture; severity counts match the JSON and top findings are accurate.
- [ ] **Litmus (clean):** Scan a clean target; skill reports "no findings" and exits cleanly.
- [ ] **Litmus (strict exit):** `--strict` run with warnings exits non-zero but is summarized (JSON parsed), not reported as a crash.
- [ ] **Litmus (real failure):** A genuine scanner failure (no/invalid JSON) is reported as a failure with stderr, not silently summarized as "no findings".

---

## Phase 4 — Robustness, Docs & Cross-Session Verification <a id="phase-4"></a>

Goal: make the skill reliable on edge cases and document it for the user.

- [ ] Edge case: scanner not found → actionable message (where it looked, how to fix / set `WPCC_HOME`).
- [ ] Edge case: target is not a WordPress project → warn but allow override.
- [ ] Edge case: scanner times out (exit 124 via `run_with_timeout`) → surface clearly with remediation (scope down `--paths`).
- [ ] Edge case: Python helpers (`json-to-html.py`, `ai-triage.py`) absent or not executable → degrade gracefully (still show JSON summary).
- [ ] Add a short usage note to the WPCC repo docs (e.g. a mention in `SHELL-QUICKSTART.md` or a new line in README's "AI Agent Users" section) that a global `wpcc` skill exists.
- [ ] Update `CHANGELOG.md` under `[Unreleased]` (per project documentation workflow).
- [ ] **End-to-end verification:** in a fresh session, in an unrelated repo, trigger the skill by natural language ("run wpcc on this plugin") and confirm scan → summary → report-path round-trips.

### QA Checklist — Phase 4
- [ ] **DRY:** Error messages reference the single resolved-path variable; no duplicated path strings.
- [ ] **Observability:** Every failure mode (missing scanner, bad target, timeout, missing helper) yields a distinct, named message.
- [ ] **Graceful degradation:** Missing optional Python helpers do not block the core JSON scan + summary.
- [ ] **Docs sync:** README/SHELL-QUICKSTART and CHANGELOG mention the skill; no stale claims.
- [ ] **Litmus (true cross-session):** New session, new directory, natural-language trigger — full happy path works with zero manual setup.
- [ ] **Anti-goal check:** Still zero changes to scanner logic; only the skill + docs touched.

---

## Out of Scope / Deferred <a id="out-of-scope"></a>

- Modifying the scanner (`check-performance.sh`) or its detection rules.
- Bundling/distributing the skill as a Claude Code **plugin** (marketplace) — this plan ships a personal skill only; packaging is a future follow-up.
- Making the skill available on **other devices** — it is intentionally device-local per the request. (Note: device-*local* install/update **is** in scope — see Phase 1. What's deferred is cross-device sync and wiring the skill install into the repo's `install.sh`.)
- Auto-triage / LLM explanation of findings beyond passing `--ai-triage` through to the scanner.
