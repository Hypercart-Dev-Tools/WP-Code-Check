---
Author: Noel (with Claude Code, Opus 4.8)
Date: 2026-06-18
Status: NOT STARTED
Priority: P2
Goal: Author a device-global Claude skill (`~/.claude/skills/wpcc/SKILL.md`) so that any Claude Code session on this machine — regardless of working directory or repo — can invoke WP Code Check (WPCC) against a target path, summarize the findings, and hand back the report, without the user remembering the scanner's flags or absolute path.
Source: User request — "make a Claude skill file to invoke WPCC in any claude session on this device."
Scope: Skill authoring + invocation/summarization logic only. No changes to the scanner (`dist/bin/check-performance.sh`) itself.
---

## Status At A Glance

| Most Recently Completed Phase | What's Next |
|---|---|
| None — plan created 2026-06-18 | **Phase 1 — Skill Scaffold & Scanner Path Resolution** |

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

A **Claude skill** is the right vehicle: a `SKILL.md` with `name` + `description` frontmatter placed in `~/.claude/skills/<name>/` is auto-discovered in **every** session on the device and triggered by its description. This is exactly the "any claude session on this device" requirement.

---

## Design Decisions <a id="design-decisions"></a>

| Decision | Choice | Why |
|---|---|---|
| Skill location | `~/.claude/skills/wpcc/SKILL.md` | User-level skills load in every session on the device (vs. project `.claude/skills/` which is repo-scoped). |
| Scanner reference | Absolute path to `dist/bin/check-performance.sh`, with a fallback resolver | Bash tool can't see the `wpcc` alias; absolute path is the only reliable handle. |
| Path portability | Resolve at run time (check known install dir, then `command -v wpcc`-style git-root probe), fail loud if not found | Survives the repo being moved; avoids a hard-coded path silently scanning nothing. |
| Default target | The directory the user names; if none, the session's cwd | Matches how a human runs `wpcc <dir>`. |
| Default format | `--format json` (parsed by skill), surface a human summary | JSON is machine-parseable so the skill can summarize cleanly instead of dumping raw scanner stdout into context. |
| Raw output handling | Write full report to a temp/file path, summarize top findings inline | Honors context-window discipline — large scans don't flood the conversation. |

---

## Architecture Notes <a id="architecture-notes"></a>

- **Scanner entrypoint:** `dist/bin/check-performance.sh` (repo root: `/Users/noelsaw/Documents/GH Repos/wp-code-check`). Invocation: `check-performance.sh --paths <dir> [flags]`.
- **Relevant flags** (from README/SHELL-QUICKSTART): `--paths <dir>`, `--format json`, `--strict` (non-zero exit on findings), `--generate-baseline`, `--ai-triage`, `--verbose`, `--no-log`.
- **Skill anatomy:** `SKILL.md` requires YAML frontmatter with `name` and `description`. The `description` is the trigger surface — it must contain the phrases that should fire the skill ("scan with wpcc", "run wp code check", "check this plugin for performance/security issues").
- **No scanner changes.** This plan only adds a skill file plus (optionally) one small helper. If a helper script is needed it lives beside the skill in `~/.claude/skills/wpcc/`, not in the WPCC repo.
- **Existing reference docs to mirror, not duplicate:** `SHELL-QUICKSTART.md`, `dist/TEMPLATES/_AI_INSTRUCTIONS.md`. The skill should point to these rather than restate them.

---

## Phase 1 — Skill Scaffold & Scanner Path Resolution <a id="phase-1"></a>

Goal: a discoverable, well-described skill stub that can reliably locate the scanner from any cwd.

- [ ] Create directory `~/.claude/skills/wpcc/`.
- [ ] Create `~/.claude/skills/wpcc/SKILL.md` with valid YAML frontmatter (`name: wpcc`, a `description` containing the trigger phrases listed in Architecture Notes).
- [ ] In the skill body, record the canonical absolute scanner path: `/Users/noelsaw/Documents/GH Repos/wp-code-check/dist/bin/check-performance.sh`.
- [ ] Add a runtime path-resolution snippet: (1) test the canonical path; (2) if missing, probe for a moved repo (e.g. search common parents / read a `WPCC_HOME` env var); (3) if still unresolved, **stop and tell the user** rather than scanning nothing.
- [ ] Confirm the scanner is executable (`-x`); document the `chmod +x` remedy if not.
- [ ] Verify the skill appears in the available-skills list of a **new** Claude session (no manual registration needed).

### QA Checklist — Phase 1
- [ ] **DRY:** Scanner path defined once in the skill, referenced everywhere — not re-typed per command.
- [ ] **Single source of truth:** Frontmatter `name` matches the directory name (`wpcc`); no second copy of the path elsewhere.
- [ ] **Observability:** Path-resolution failure produces a clear, actionable message naming the path it tried.
- [ ] **Litmus (discovery):** Open a brand-new session in an unrelated directory; the `wpcc` skill is listed and resolves the scanner.
- [ ] **Litmus (portability):** Temporarily rename/move the repo; the resolver fails loud instead of silently doing nothing.
- [ ] **Anti-goal check:** No edits made to `check-performance.sh` or anything in the WPCC repo.

---

## Phase 2 — Invocation Logic & Argument Mapping <a id="phase-2"></a>

Goal: translate plain-language intent into a correct scanner command.

- [ ] Document the default invocation: `check-performance.sh --paths <target> --format json`.
- [ ] Define target resolution: use the path the user names; if none given, use the session cwd; confirm the target exists and looks like a WP plugin/theme/project before scanning.
- [ ] Map intents → flags in the skill body:
  - [ ] "strict" / "fail on findings" → `--strict`
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
- [ ] Handle the `--strict` non-zero exit code gracefully (a non-zero exit means "findings present", not "scanner crashed").
- [ ] Handle empty / clean results with an explicit "no findings" message.

### QA Checklist — Phase 3
- [ ] **DRY:** One summarization routine handles all scan modes (normal, strict, baseline).
- [ ] **Observability:** Summary always states total count, severity breakdown, and report file path.
- [ ] **Context discipline:** Raw multi-hundred-line JSON is never pasted into the conversation; only the summary + path.
- [ ] **Litmus (findings):** Scan a known-dirty fixture; severity counts match the JSON and top findings are accurate.
- [ ] **Litmus (clean):** Scan a clean target; skill reports "no findings" and exits cleanly.
- [ ] **Litmus (strict exit):** `--strict` run with findings is summarized, not reported as a failure/error.

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
- Bundling/distributing the skill as a Claude Code **plugin** (marketplace) — this plan ships a user-level skill only; packaging is a future follow-up.
- Making the skill available on **other devices** — it is intentionally device-local per the request. A portable install step (`install.sh` copies the skill to `~/.claude/skills/`) is a deferred enhancement.
- Auto-triage / LLM explanation of findings beyond passing `--ai-triage` through to the scanner.
