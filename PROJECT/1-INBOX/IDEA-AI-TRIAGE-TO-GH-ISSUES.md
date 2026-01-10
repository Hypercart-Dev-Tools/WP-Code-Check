# AI Triage to GitHub Issues Workflow

**Created:** 2026-01-10
**Status:** Idea / Planning
**Priority:** Medium

---

## 🎯 Core Concept

**One Parent Issue Per Scan** with a checklist of confirmed findings that can be converted to child issues using GitHub's tasklist feature.

---

## 💡 Thoughts on Extending the Workflow

### **Current State Analysis**

✅ **What I Can Detect:**
- **WP Code Check Repo:** `Hypercart-Dev-Tools/WP-Code-Check` (public)
- **Scanned Plugin Repo:** `Hypercart-Dev-Tools/Server-Monitor-MKII` (detected via git remote)
- **Template System:** 12 configured plugins/themes with paths
- **GitHub CLI:** Authenticated and ready

### **Proposed Workflow Extension**

I can absolutely extend the Phase 3 workflow to automatically create issues in the **scanned plugin/theme's repository** (not the scanner repo). Here's how:

---

## 🎯 Enhanced Phase 3 Workflow

### **Current Flow:**
```
Scan → AI Triage → Manual Review → Manual Issue Creation
```

### **Proposed Enhanced Flow:**
```
Scan → AI Triage → Auto-Detect Repo → Create ONE Parent Issue with Checklist
```

**Key Difference:** Instead of creating multiple individual issues, create **one parent issue** with a GitHub tasklist. Users can then convert checklist items to child issues as needed.

---

## 🔧 Implementation Strategy

### **Phase 3A: Repository Detection**

Add to template files:
```bash
# ============================================================
# GITHUB INTEGRATION (Optional)
# ============================================================

# GITHUB_REPO=Hypercart-Dev-Tools/Server-Monitor-MKII
# GITHUB_AUTO_ISSUE=true
# GITHUB_ISSUE_LABELS=code-quality,wp-code-check
# GITHUB_ASSIGNEE=@me
# GITHUB_MILESTONE=v1.0
# GITHUB_CREATE_PARENT_ISSUE=true  # One issue per scan with checklist
```

### **Phase 3B: Auto-Detection Logic**

```bash
# 1. Check if PROJECT_PATH is a git repo
# 2. Extract remote URL
# 3. Parse owner/repo from URL
# 4. Verify gh CLI has access
# 5. Create ONE parent issue with checklist of confirmed findings
```

### **Phase 3C: Parent Issue Creation Strategy**

**One issue per scan session:**
```bash
gh issue create \
  --repo "Hypercart-Dev-Tools/Server-Monitor-MKII" \
  --title "[WP Code Check] Scan Report - 2026-01-10 (2 confirmed issues)" \
  --body "$(cat parent-issue-template.md)" \
  --label "code-quality,wp-code-check" \
  --assignee "@me"
```

---

## 📋 Parent Issue Template Structure

```markdown
# 🔍 WP Code Check Scan Report - 2026-01-10

**Scan Date:** 2026-01-10T20:59:27Z
**Scanner Version:** 1.2.2
**Project:** Hypercart Server Monitor MKII v0.2.0
**Files Analyzed:** 20 files (3,438 lines of code)

---

## 📊 Executive Summary

- **Total Findings:** 5
- **Confirmed Issues:** 2 ⚠️
- **False Positives:** 3 ✅
- **AI Confidence:** High

**Status:** ⚠️ Action Required

---

## ✅ Confirmed Issues (Action Required)

The following issues have been confirmed by AI triage and require attention. Click the checkbox to convert each item to a child issue.

### 🔴 Critical Issues (0)

*None found*

### 🟠 High Priority Issues (2)

- [ ] **Unbounded query in HealthRepository.php:45** - Missing LIMIT clause on `get_posts()` call could cause performance issues on sites with large datasets. [View Details](#issue-1)
- [ ] **Missing nonce verification in ajax_handler.php:78** - AJAX handler `wp_ajax_custom_action` does not verify nonce before processing request. [View Details](#issue-2)

### 🟡 Medium Priority Issues (0)

*None found*

### 🔵 Low Priority Issues (0)

*None found*

---

## ℹ️ False Positives (No Action Needed)

The following findings were flagged but determined to be false positives:

<details>
<summary><strong>3 False Positives</strong> (click to expand)</summary>

### ✅ Direct superglobal manipulation (2 occurrences)
- **Files:** `tab-manual-test.php:66`, `tab-email.php:88`
- **Reason:** JavaScript `type: 'POST'` in jQuery AJAX calls, not PHP superglobal manipulation
- **Confidence:** High

### ✅ Transient without expiration
- **File:** `LockHelper.php:41`
- **Reason:** Expiration is set via `self::LOCK_TTL` constant (300 seconds) on line 47
- **Confidence:** High

</details>

---

## 📝 Issue Details

### Issue #1: Unbounded query in HealthRepository.php:45

**Severity:** HIGH
**Pattern ID:** unbounded-get-posts
**File:** `src/Persistence/HealthRepository.php`
**Line:** 45

**Code:**
```php
$posts = get_posts( array(
    'post_type' => 'health_sample',
    'post_status' => 'publish',
    // Missing: 'posts_per_page' => 100
) );
```

**AI Analysis:**
- **Classification:** Confirmed Issue
- **Confidence:** High (95%)
- **Impact:** Performance degradation on sites with >1000 health samples

**Recommendation:**
Add explicit limit to prevent unbounded queries:
```php
$posts = get_posts( array(
    'post_type' => 'health_sample',
    'post_status' => 'publish',
    'posts_per_page' => 100, // Add limit
) );
```

---

### Issue #2: Missing nonce verification in ajax_handler.php:78

**Severity:** HIGH
**Pattern ID:** missing-nonce-ajax
**File:** `src/Admin/ajax_handler.php`
**Line:** 78

**Code:**
```php
add_action( 'wp_ajax_custom_action', 'handle_custom_action' );

function handle_custom_action() {
    // Missing: check_ajax_referer( 'custom_action_nonce', 'nonce' );

    $data = $_POST['data'];
    // Process data...
}
```

**AI Analysis:**
- **Classification:** Confirmed Issue
- **Confidence:** High (98%)
- **Impact:** CSRF vulnerability - unauthorized users could trigger this action

**Recommendation:**
Add nonce verification at the start of the handler:
```php
function handle_custom_action() {
    check_ajax_referer( 'custom_action_nonce', 'nonce' );

    if ( ! current_user_can( 'manage_options' ) ) {
        wp_send_json_error( 'Insufficient permissions' );
    }

    $data = sanitize_text_field( $_POST['data'] );
    // Process data...
}
```

---

## 📎 Resources

- **Full HTML Report:** [View Report](https://example.com/reports/2026-01-10-205923-UTC.html)
- **JSON Log:** [Download JSON](https://example.com/logs/2026-01-10-205923-UTC.json)
- **Scanner Documentation:** [WP Code Check](https://github.com/Hypercart-Dev-Tools/WP-Code-Check)

---

## 🔄 Next Steps

1. **Review confirmed issues** above
2. **Convert checklist items to child issues** by clicking the checkboxes (GitHub will prompt you)
3. **Assign and prioritize** child issues as needed
4. **Fix issues** and create PRs
5. **Re-run scan** to verify fixes

---

*Auto-generated by [WP Code Check](https://github.com/Hypercart-Dev-Tools/WP-Code-Check) v1.2.2*
```

---

## 🚀 Benefits of Parent Issue + Checklist Approach

### **1. Reduced Noise**
- **One issue per scan** instead of 5-10 individual issues
- Keeps issue tracker clean and organized
- Easy to see scan history at a glance

### **2. Flexible Workflow**
- **Convert to child issues on-demand** - only create issues for items you want to track separately
- **Batch review** - see all findings in one place before deciding what to action
- **Progressive disclosure** - false positives collapsed by default

### **3. Better Context**
- **Executive summary** at the top shows scan health at a glance
- **AI triage included** - see why each finding was confirmed or dismissed
- **Full details inline** - no need to click through multiple issues

### **4. GitHub Tasklist Integration**
- **Native GitHub feature** - checkboxes can be converted to child issues with one click
- **Progress tracking** - see completion percentage automatically
- **Linked issues** - child issues automatically reference parent

### **5. Audit Trail**
- **One issue per scan session** - permanent record of each scan
- **Historical comparison** - compare scan results over time
- **Trend analysis** - see if code quality is improving or degrading

### **6. Team Collaboration**
- **Single point of discussion** - team can comment on overall scan results
- **Selective assignment** - convert specific items to child issues and assign to different team members
- **Milestone tracking** - link parent issue to milestone, child issues inherit it

---

## ⚠️ Considerations & Safeguards

### **1. Permission Checks**
```bash
# Verify gh CLI has write access to target repo
gh repo view "$GITHUB_REPO" --json viewerPermission
```

### **2. Duplicate Prevention**
```bash
# Check if scan report already exists for this date
gh issue list --repo "$GITHUB_REPO" --search "in:title [WP Code Check] Scan Report - $(date +%Y-%m-%d)"

# If exists, add comment with new scan results instead of creating new issue
# Or append to existing issue body
```

### **3. Rate Limiting**
```bash
# Only ONE issue created per scan (parent issue)
# No rate limiting concerns
# Child issues created manually by user
```

### **4. Dry-Run Mode**
```bash
# Preview issues before creation
./dist/bin/run hypercart-server-monitor-mkii --dry-run-issues
```

### **5. Opt-In Only**
```bash
# Require explicit GITHUB_AUTO_ISSUE=true in template
# Default: false (manual review required)
```

---

## 🛠️ Implementation Plan

### **Step 1: Enhance Template System**
- Add GitHub integration fields to `_TEMPLATE.txt`
- Update `_AI_INSTRUCTIONS.md` with Phase 3 workflow

### **Step 2: Add Repo Detection**
- Create `detect-github-repo.sh` helper
- Parse git remote URL
- Validate access with `gh` CLI

### **Step 3: Parent Issue Template Generator**
- Create `generate-parent-issue-body.sh`
- Format AI triage data as markdown with GitHub tasklist syntax
- Include executive summary, confirmed issues checklist, and false positives
- Add detailed breakdown for each confirmed issue

### **Step 4: Issue Creation Logic**
- Add `--create-github-issue` flag to scanner
- Create ONE parent issue per scan with checklist
- Implement duplicate detection (one issue per day max)
- Add dry-run mode to preview issue body

### **Step 5: Documentation**
- Update README with GitHub integration guide
- Add examples and best practices
- Document security considerations

---

## 🎯 Example Usage

### **Automatic (Opt-In):**
```bash
# Template has GITHUB_AUTO_ISSUE=true
./dist/bin/run hypercart-server-monitor-mkii

# Output:
# ✅ Scan complete: 5 findings
# 🧠 AI Triage: 2 confirmed, 3 false positives
# 🔍 Detected repo: Hypercart-Dev-Tools/Server-Monitor-MKII
# 📝 Creating parent issue with 2 confirmed items...
# ✅ Issue created: https://github.com/Hypercart-Dev-Tools/Server-Monitor-MKII/issues/42
```

### **Manual Review:**
```bash
# Review AI triage first
./dist/bin/run hypercart-server-monitor-mkii --format json

# Then create parent issue from scan log
./dist/bin/create-github-issue-from-scan.sh dist/logs/2026-01-10-205923-UTC.json

# Output:
# 📊 Scan Summary: 2 confirmed issues, 3 false positives
# 📝 Creating parent issue in Hypercart-Dev-Tools/Server-Monitor-MKII...
# ✅ Issue #42 created: https://github.com/Hypercart-Dev-Tools/Server-Monitor-MKII/issues/42
#
# Next steps:
# 1. Review the issue: gh issue view 42 --repo Hypercart-Dev-Tools/Server-Monitor-MKII
# 2. Convert checklist items to child issues by clicking checkboxes in GitHub UI
```

### **Dry-Run:**
```bash
# Preview parent issue body before creation
./dist/bin/run hypercart-server-monitor-mkii --dry-run-github-issue

# Output:
# 📋 Preview of GitHub issue that would be created:
#
# Title: [WP Code Check] Scan Report - 2026-01-10 (2 confirmed issues)
# Labels: code-quality, wp-code-check
# Assignee: @me
#
# Body:
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# [Full markdown preview shown here...]
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#
# Run without --dry-run to create this issue.
```

### **User Workflow After Issue Creation:**

1. **Review parent issue** in GitHub
2. **Click checkbox** next to a confirmed issue
3. **GitHub prompts:** "Convert to issue?"
4. **Click "Convert to issue"** - GitHub automatically:
   - Creates a new child issue
   - Links it to the parent issue
   - Copies the relevant details
   - Checks the box in the parent issue
5. **Assign, label, and prioritize** the child issue
6. **Create PR** to fix the issue
7. **Close child issue** when fixed
8. **Re-run scan** to verify fix

---

## 🤔 Design Decisions

### **1. Parent Issue Content**
- ✅ **Include confirmed issues in checklist** (AI confidence > 80%)
- ✅ **Include false positives in collapsed section** (for transparency)
- ✅ **Include executive summary** (quick health check)
- ✅ **Include detailed breakdown** (inline, no need to click through)

### **2. Label Strategy**
- ✅ **Standard labels:** `code-quality`, `wp-code-check`
- ✅ **Severity labels on child issues** (when converted): `critical`, `high`, `medium`, `low`
- ✅ **Category labels on child issues**: `security`, `performance`, `reliability`
- ⚙️ **Configurable in template:** `GITHUB_ISSUE_LABELS=custom,labels`

### **3. Assignee Strategy**
- ✅ **Default:** Auto-assign to `@me` (scanner runner)
- ⚙️ **Configurable:** `GITHUB_ASSIGNEE=@username` or `GITHUB_ASSIGNEE=` (leave unassigned)
- 💡 **Child issues:** Inherit parent assignee by default, can be changed

### **4. Milestone Integration**
- ✅ **Default:** No milestone (user can add manually)
- ⚙️ **Configurable:** `GITHUB_MILESTONE=v1.0` (if milestone exists)
- 💡 **Child issues:** Inherit parent milestone automatically

### **5. Duplicate Handling**
- ✅ **One parent issue per day max** (check for existing issue with same date)
- ✅ **If exists:** Add comment with new scan results instead of creating new issue
- ⚙️ **Configurable:** `GITHUB_ALLOW_MULTIPLE_DAILY_SCANS=true` (create new issue each time)

### **6. Notification Preferences**
- ✅ **Default:** Standard GitHub notifications (issue creation)
- 💡 **Future:** Webhook support for Slack/Discord
- 💡 **Future:** Email digest option

---

## 💭 Recommended Implementation Approach

### **Phase 1: Core Functionality (MVP)**
1. ✅ **Parent issue creation** - one issue per scan with checklist
2. ✅ **Dry-run mode** - preview issue before creation
3. ✅ **Opt-in only** - require explicit `GITHUB_AUTO_ISSUE=true` in template
4. ✅ **Confirmed issues in checklist** - AI confidence > 80%
5. ✅ **False positives collapsed** - transparency without noise
6. ✅ **Duplicate detection** - max one issue per day (configurable)

### **Phase 2: Enhanced Features**
- 📊 **GitHub Projects integration** - auto-add to project board
- 🔗 **Link to HTML report** - upload report as artifact, link in issue
- 📈 **Trend analysis** - compare with previous scans, show improvement/regression
- 🏷️ **Smart labeling** - auto-detect issue type and apply appropriate labels
- 👥 **Team mentions** - `@mention` relevant team members based on file ownership

### **Phase 3: Advanced Automation**
- 🔄 **Auto-close resolved issues** - when re-scan shows issue fixed
- 🔔 **Webhook notifications** - Slack/Discord integration
- 📧 **Email digests** - weekly summary of scan results
- 🌐 **Multi-platform support** - GitLab, Bitbucket, Azure DevOps
- 🤖 **Auto-PR creation** - generate fix PRs for simple issues (e.g., add LIMIT clause)

---

---

## 🎉 Summary

### **Key Innovation: Parent Issue + Checklist**

Instead of creating 5-10 individual issues per scan (noisy), create **ONE parent issue** with:
- ✅ Executive summary (TL;DR)
- ✅ Checklist of confirmed issues (convertible to child issues)
- ✅ Collapsed false positives section (transparency)
- ✅ Detailed breakdown inline (no clicking through)

### **Benefits Over Individual Issues**

| Aspect | Individual Issues | Parent Issue + Checklist |
|--------|------------------|-------------------------|
| **Noise** | 5-10 issues per scan | 1 issue per scan |
| **Context** | Scattered across issues | All in one place |
| **Flexibility** | All or nothing | Convert only what you need |
| **History** | Hard to track scans | One issue = one scan session |
| **Collaboration** | Fragmented discussion | Centralized discussion |
| **GitHub Integration** | Manual linking | Native tasklist → child issues |

### **Implementation Readiness**

**Infrastructure Already in Place:**
- ✅ Template system with project paths
- ✅ AI triage with confidence scoring
- ✅ GitHub CLI authenticated and working
- ✅ Git repo detection working
- ✅ JSON output with all necessary data

**What's Needed:**
1. Parent issue template generator (bash script)
2. GitHub tasklist markdown formatter
3. Duplicate detection logic
4. Dry-run preview mode
5. Template configuration fields

**Estimated Effort:** 4-6 hours for MVP (Phase 1)

---

## 🚀 Next Steps

**When ready to implement:**
1. Update template system with GitHub integration fields
2. Create `generate-parent-issue-body.sh` script
3. Add `--create-github-issue` flag to scanner
4. Build dry-run mode for testing
5. Test with Hypercart Server Monitor MKII
6. Document workflow in README

**No action taken yet** - awaiting your approval to proceed! 🎯
