You're right to be concerned! Let me check what's happening. The baseline should be filtering out the 69 known issues, but they should still be visible in the report as "baselined". Let me investigate:

I see the issue! The baseline is working correctly - it's filtering out the 69 known issues. But you're right that this is confusing. The report should show:
1. **Total findings detected:** 69
2. **Baselined (known issues):** 69  
3. **New issues:** 0

Let me check the JSON output to see what information is available:

Good! The summary shows `"baselined": 69` correctly. The issue is that when baseline filters out all findings, the report shows "0 errors" which is technically correct (0 NEW errors), but it's not showing that there are 69 baselined issues.

Let me run the scan WITHOUT baseline to show you what the actual issues are:

Perfect! So the baseline IS working correctly:

## What's Happening (This is CORRECT behavior)

**Without baseline:** 4 error types, 69 total findings  
**With baseline:** 0 NEW errors (all 69 findings are baselined)

The baseline is doing exactly what it should - it's tracking the 69 known issues and only alerting you to NEW problems. This is the intended behavior for baseline tracking.

## Understanding the Report

The HTML report should show:
- **Errors: 0** (new errors)
- **Baselined: 69** (known issues being tracked)
- **Status: ✓ All critical checks passed!** (no NEW issues)

This means:
- ✅ No new issues introduced since baseline was created
- ✅ 69 existing issues are tracked and won't fail the build
- ✅ If you introduce a NEW issue, it will show up as an error

## To See All Issues (Including Baselined)

If you want to see the full list of all 69 issues that are being tracked, you can:

1. **View the baseline file directly:**
   ```bash
   cat "/Users/noelsaw/Local Sites/neochrome-timesheets/app/public/wp-content/plugins/ptt-mkii/.hcc-baseline"
   ```

2. **Run without baseline to see raw findings:**
   ```bash
   ./dist/bin/check-performance.sh --paths "/Users/noelsaw/Local Sites/neochrome-timesheets/app/public/wp-content/plugins/ptt-mkii"
   ```

**Is this the behavior you expected, or would you like the report to also display the baselined issues?**
