# GitHub Issue Creation Feature

**Created:** 2026-01-13  
**Completed:** 2026-01-13  
**Status:** ✅ Completed  
**Shipped In:** v1.3.2

## Summary

Implemented automated GitHub issue creation from scan results with AI triage data. Users can now generate clean, actionable GitHub issues directly from JSON scan logs with a single command.

## Implementation

### Files Created

1. **`dist/bin/create-github-issue.sh`** (275 lines)
   - Standalone script to create GitHub issues from JSON scan results
   - Reads scan metadata, AI triage data, and generates formatted issue body
   - Interactive preview before creating issues
   - Supports both `--repo owner/repo` flag and template-based repo detection

### Files Modified

1. **`README.md`**
   - Added GitHub Issue Creator to tools table
   - Added usage documentation section

2. **`CHANGELOG.md`**
   - Added v1.3.2 release notes

3. **`dist/bin/check-performance.sh`**
   - Added helpful hint message after scan completion
   - Shows command to create GitHub issue if gh CLI is available and scan has AI triage data

4. **`dist/TEMPLATES/_TEMPLATE.txt`**
   - Added optional `GITHUB_REPO` field for automated issue creation

5. **`dist/TEMPLATES/_AI_INSTRUCTIONS.md`**
   - Added instructions for AI agents to detect GitHub repository

## Features

✅ **Auto-formatted Issues** - Clean, actionable GitHub issues with checkboxes  
✅ **AI Triage Integration** - Shows confirmed issues vs. needs review  
✅ **Template Integration** - Reads GitHub repo from project templates  
✅ **Interactive Preview** - Review before creating the issue  
✅ **Confidence Levels** - Shows AI confidence for each finding  
✅ **File Path Cleanup** - Removes local paths for cleaner display  
✅ **Timezone Conversion** - Converts UTC timestamps to local time  
✅ **Report Links** - Includes links to full HTML and JSON reports

## Usage

```bash
# Create issue from latest scan
./dist/bin/create-github-issue.sh \
  --scan-id 2026-01-12-155649-UTC \
  --repo owner/repo

# Or use template's GitHub repo
./dist/bin/create-github-issue.sh --scan-id 2026-01-12-155649-UTC
```

## Requirements

- GitHub CLI (`gh`) installed and authenticated
- Scan with AI triage data (`--ai-triage` flag)
- JSON scan log in `dist/logs/`

## Example Output

The script generates issues with:
- Scan metadata (plugin/theme name, version, scanner version)
- Summary stats (total findings, confirmed, needs review, false positives)
- Confirmed issues section with checkboxes
- Needs review section with confidence levels
- Links to full HTML and JSON reports
- WPCodeCheck.com branding

## Testing

✅ Tested with Elementor v3.34.1 scan (200 AI-triaged findings)  
✅ Created test issue #67 in Hypercart-Dev-Tools/WP-Code-Check  
✅ Verified issue format and content  
✅ Verified file path cleanup  
✅ Verified timezone conversion  
✅ Verified interactive preview

## Integration

The main scanner (`check-performance.sh`) now shows a helpful hint after scan completion:

```
💡 Create GitHub issue from this scan:
   dist/bin/create-github-issue.sh --scan-id 2026-01-12-155649-UTC --repo owner/repo
```

This hint only appears if:
- GitHub CLI (`gh`) is installed
- Scan has AI triage data
- Running locally (not in CI)

## Future Enhancements

- [ ] Auto-detect GitHub repo from `.git/config`
- [ ] Support for creating sub-issues from confirmed findings
- [ ] Support for adding labels, assignees, milestones
- [ ] Support for updating existing issues with new scan results
- [ ] Integration with CI/CD to auto-create issues on failures

## Related

- **Full JSON Report:** [2026-01-12-155649-UTC.json](../dist/logs/2026-01-12-155649-UTC.json)
- **Test Issue:** https://github.com/Hypercart-Dev-Tools/WP-Code-Check/issues/67
- **Script:** [create-github-issue.sh](../dist/bin/create-github-issue.sh)
- **Documentation:** [README.md](../README.md)

## Lessons Learned

1. **Use `--body-file` instead of `--body`** - Large issue bodies can cause issues with command-line arguments
2. **Support both `.metadata` and `.project` formats** - JSON structure changed between versions
3. **Clean up file paths** - Remove local paths for cleaner display
4. **Show helpful hints** - Guide users to features they might not know about
5. **Interactive preview** - Let users review before creating issues

