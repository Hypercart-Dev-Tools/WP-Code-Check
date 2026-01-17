# AI Triage to GitHub Issues Workflow

**Created:** 2026-01-10  
**Status:** Partially Implemented  
**Priority:** Medium

---

## Table of Contents

1. Summary
2. Implemented Capabilities (Checked)
3. Notes and Evidence

---

## Summary

This plan has been trimmed to match what is actually implemented. The current implementation supports creating a single GitHub issue from a scan JSON, or generating an issue body for manual use. All hypothetical or unimplemented tasks were removed.

## Implemented Capabilities (Checked)

- [x] Create a single GitHub issue from a scan JSON via `dist/bin/create-github-issue.sh`
- [x] Require `--scan-id` and read `dist/logs/<SCAN_ID>.json`
- [x] Validate GitHub CLI availability and authentication (`gh`)
- [x] Read optional `GITHUB_REPO` from matching template (by `PROJECT_PATH`)
- [x] Allow manual repo override via `--repo owner/repo`
- [x] Generate issue body with summary counts and confirmed findings checklist
- [x] Include a short "needs review" section (top 5)
- [x] Save issue body for manual use when no repo is provided (`dist/issues/GH-issue-<SCAN_ID>.md`)
- [x] Prompt for confirmation before creating the issue

## Notes and Evidence

- Implementation entrypoint: `dist/bin/create-github-issue.sh`
- Documentation reference: `README.md` (GitHub Issue Creation section)
