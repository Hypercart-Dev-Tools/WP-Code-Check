# AI Triage to GitHub Issues Workflow

**Created:** 2026-01-10
**Status:** Idea / Planning
**Priority:** Medium

---

## 📑 Table of Contents

1. [Core Concept](#-core-concept)
2. [Implementation Phases](#-implementation-phases)
   - [Phase 1: Core Functionality (MVP)](#phase-1-core-functionality-mvp)
   - [Phase 2: Enhanced Features](#phase-2-enhanced-features)
   - [Phase 3: Advanced Automation](#phase-3-advanced-automation)
3. [Workflow Overview](#-thoughts-on-extending-the-workflow)
4. [Enhanced Phase 3 Workflow](#-enhanced-phase-3-workflow)
5. [Implementation Strategy](#-implementation-strategy)
6. [Parent Issue Template Structure](#-parent-issue-template-structure)
7. [Benefits & Considerations](#-benefits-of-parent-issue--checklist-approach)
8. [Implementation Plan](#-implementation-plan)
9. [Example Usage](#-example-usage)
10. [Design Decisions](#-design-decisions)
11. [Template Enhancement Strategy](#-template-enhancement-strategy)
12. [Fallback Detection Strategy](#-fallback-detection-strategy)

---

## 🎯 Core Concept

**One Parent Issue Per Scan** with a checklist of confirmed findings that can be converted to child issues using GitHub's tasklist feature.

---

## 📋 Implementation Phases

### **Phase 1: Core Functionality (MVP)**

**Goal:** Create parent GitHub issues with AI-triaged findings as checklists

- [ ] **1.1 Template System Enhancement**
  - [ ] Update `_TEMPLATE.txt` with GitHub integration section
  - [ ] Add `GITHUB_REPO`, `GITHUB_AUTO_ISSUE`, `GITHUB_ISSUE_LABELS` fields
  - [ ] Add `GITHUB_ASSIGNEE`, `GITHUB_MILESTONE` fields
  - [ ] Add `GITHUB_ALLOW_MULTIPLE_DAILY_SCANS` field
  - [ ] Update `_AI_INSTRUCTIONS.md` with Phase 3 workflow documentation

- [ ] **1.2 Repository Detection**
  - [ ] Create `dist/bin/lib/detect-github-repo.sh` helper script
  - [ ] Implement git remote URL parsing (HTTPS, SSH, git:// formats)
  - [ ] Extract owner/repo from various GitHub URL formats
  - [ ] Validate repository format (owner/repo pattern)
  - [ ] Add fallback to template-specified `GITHUB_REPO` value

- [ ] **1.3 GitHub CLI Validation**
  - [ ] Check if `gh` CLI is installed
  - [ ] Verify `gh auth status` (authenticated)
  - [ ] Validate repository access with `gh repo view`
  - [ ] Check write permissions with `gh repo view --json viewerPermission`
  - [ ] Add helpful error messages for each failure case

- [ ] **1.4 Parent Issue Template Generator**
  - [ ] Create `dist/bin/lib/generate-parent-issue-body.sh` script
  - [ ] Format executive summary (total findings, confirmed, false positives)
  - [ ] Generate GitHub tasklist syntax for confirmed issues
  - [ ] Add severity sections (Critical, High, Medium, Low)
  - [ ] Include collapsed `<details>` section for false positives
  - [ ] Add detailed breakdown for each confirmed issue (code, analysis, recommendation)
  - [ ] Include links to HTML report and JSON log
  - [ ] Add footer with scanner version and branding

- [ ] **1.5 Issue Creation Logic**
  - [ ] Add `--create-github-issue` flag to `check-performance.sh`
  - [ ] Integrate repository detection after template loading
  - [ ] Generate parent issue body from AI triage JSON
  - [ ] Create issue with `gh issue create` command
  - [ ] Apply labels from template (`GITHUB_ISSUE_LABELS`)
  - [ ] Assign to user from template (`GITHUB_ASSIGNEE`)
  - [ ] Link to milestone if specified (`GITHUB_MILESTONE`)
  - [ ] Output issue URL to console

- [ ] **1.6 Duplicate Detection**
  - [ ] Search for existing issues with same UTC timestamp in title
  - [ ] Use `gh issue list --search "in:title [WP Code Check] Scan Report (YYYY-MM-DD-HHMMSS)"`
  - [ ] UTC timestamp ensures unique identification per scan
  - [ ] If found (unlikely with timestamp), add comment instead of creating duplicate
  - [ ] Support `GITHUB_ALLOW_MULTIPLE_DAILY_SCANS` for backward compatibility

- [ ] **1.7 Dry-Run Mode**
  - [ ] Add `--dry-run-github-issue` flag
  - [ ] Preview issue title, labels, assignee, milestone
  - [ ] Display full markdown body with formatting
  - [ ] Show what would be created without actually creating it
  - [ ] Add instructions on how to create for real

- [ ] **1.8 Opt-In Safety**
  - [ ] Default `GITHUB_AUTO_ISSUE=false` in templates
  - [ ] Require explicit `true` value to enable auto-creation
  - [ ] Skip GitHub integration silently if not enabled
  - [ ] Allow manual issue creation from JSON log later

- [ ] **1.9 Testing & Validation**
  - [ ] Test with Hypercart Server Monitor MKII repository
  - [ ] Verify parent issue creation with checklist
  - [ ] Test duplicate detection (same-day scans)
  - [ ] Verify dry-run mode output
  - [ ] Test with different label/assignee/milestone configurations
  - [ ] Validate GitHub tasklist → child issue conversion workflow

- [ ] **1.10 Documentation**
  - [ ] Update README.md with GitHub integration section
  - [ ] Add setup instructions (gh CLI installation, authentication)
  - [ ] Document template configuration options
  - [ ] Add example workflows (auto, manual, dry-run)
  - [ ] Include screenshots of parent issue and child issue conversion
  - [ ] Document security considerations and permissions

---

### **Phase 2: Enhanced Features**

**Goal:** Add advanced integrations and analytics

- [ ] **2.1 GitHub Projects Integration**
  - [ ] Add `GITHUB_PROJECT` field to templates
  - [ ] Auto-add parent issue to project board
  - [ ] Set project status (e.g., "Triage", "To Do")
  - [ ] Support GitHub Projects v2 API

- [ ] **2.2 Report Artifact Upload**
  - [ ] Upload HTML report as GitHub release asset
  - [ ] Link to uploaded report in parent issue body
  - [ ] Add JSON log as downloadable artifact
  - [ ] Set retention policy for old reports

- [ ] **2.3 Trend Analysis**
  - [ ] Compare current scan with previous scan results
  - [ ] Show improvement/regression metrics in issue
  - [ ] Add trend chart (e.g., "5 issues → 2 issues ✅")
  - [ ] Track issue resolution rate over time

- [ ] **2.4 Smart Labeling**
  - [ ] Auto-detect issue type (security, performance, reliability)
  - [ ] Apply category labels to parent issue
  - [ ] Suggest labels for child issues based on pattern ID
  - [ ] Support custom label mapping in templates

- [ ] **2.5 Team Mentions**
  - [ ] Parse CODEOWNERS file for file ownership
  - [ ] `@mention` relevant team members in issue
  - [ ] Add team-based assignee suggestions
  - [ ] Support custom mention rules in templates

---

### **Phase 3: Advanced Automation**

**Goal:** Full automation with intelligent workflows

- [ ] **3.1 Auto-Close Resolved Issues**
  - [ ] Re-scan and compare with previous findings
  - [ ] Auto-close child issues when issue no longer detected
  - [ ] Add comment with verification details
  - [ ] Support manual override (keep issue open)

- [ ] **3.2 Webhook Notifications**
  - [ ] Add Slack webhook integration
  - [ ] Add Discord webhook integration
  - [ ] Send scan summary to configured channels
  - [ ] Include quick links to parent issue

- [ ] **3.3 Email Digests**
  - [ ] Weekly summary of scan results
  - [ ] Aggregate multiple scans into one email
  - [ ] Include trend analysis and highlights
  - [ ] Support multiple recipients

- [ ] **3.4 Multi-Platform Support**
  - [ ] GitLab integration (GitLab CLI)
  - [ ] Bitbucket integration (Bitbucket API)
  - [ ] Azure DevOps integration (Azure CLI)
  - [ ] Generic webhook for other platforms

- [ ] **3.5 Auto-PR Creation**
  - [ ] Detect simple fixable issues (e.g., add LIMIT clause)
  - [ ] Generate fix code automatically
  - [ ] Create PR with fix and link to parent issue
  - [ ] Add tests to verify fix
  - [ ] Request review from CODEOWNERS

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
  --title "[WP Code Check] Scan Report (2026-01-10-205923) - 2 confirmed issues" \
  --body "$(cat parent-issue-template.md)" \
  --label "code-quality,wp-code-check" \
  --assignee "@me"
```

**Title Format:** `[WP Code Check] Scan Report (YYYY-MM-DD-HHMMSS) - N confirmed issues`
- **UTC Timestamp:** Matches JSON log filename for easy correlation
- **Issue Count:** Quick visibility of scan severity
- **Unique Identifier:** Prevents duplicates, enables log lookup

---

## 📋 Parent Issue Template Structure

```markdown
# 🔍 WP Code Check Scan Report (2026-01-10-205927)

**Scan Timestamp:** 2026-01-10-205927 UTC (2026-01-10T20:59:27Z)
**Scanner Version:** 1.2.2
**Project:** Hypercart Server Monitor MKII v0.2.0
**Files Analyzed:** 20 files (3,438 lines of code)
**Log File:** `2026-01-10-205927-UTC.json`

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

*🤖 AI Supercharged Code Review by [WP Code Check](https://wpcodecheck.com) v1.2.2*
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
# Check if scan report already exists for this exact timestamp
# UTC timestamp format: YYYY-MM-DD-HHMMSS (matches JSON log filename)
TIMESTAMP="2026-01-10-205927"
gh issue list --repo "$GITHUB_REPO" --search "in:title [WP Code Check] Scan Report ($TIMESTAMP)"

# With UTC timestamp, duplicates are virtually impossible
# Each scan has unique timestamp matching the JSON log file
# Example: 2026-01-10-205927-UTC.json → Issue title includes (2026-01-10-205927)
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

### **Step 2: Add Repo Detection & Template Enhancement**
- **Update `_TEMPLATE.txt`** - Add GitHub integration section
- **Update existing templates** - Add `GITHUB_REPO=` field (optional, auto-detected if blank)
- **Create `detect-github-repo.sh` helper** - Auto-detect from git remote if not in template
- **Parse git remote URL** - Extract owner/repo from various formats
- **Validate access with `gh` CLI** - Check permissions before creating issues

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
# ✅ Scan complete: 5 findings (2026-01-10-205927-UTC.json)
# 🧠 AI Triage: 2 confirmed, 3 false positives
# 🔍 Detected repo: Hypercart-Dev-Tools/Server-Monitor-MKII
# 📝 Creating parent issue with 2 confirmed items...
# 📋 Title: [WP Code Check] Scan Report (2026-01-10-205927) - 2 confirmed issues
# ✅ Issue created: https://github.com/Hypercart-Dev-Tools/Server-Monitor-MKII/issues/42
```

### **Manual Review:**
```bash
# Review AI triage first
./dist/bin/run hypercart-server-monitor-mkii --format json

# Then create parent issue from scan log
./dist/bin/create-github-issue-from-scan.sh dist/logs/2026-01-10-205927-UTC.json

# Output:
# 📊 Scan Summary: 2 confirmed issues, 3 false positives (2026-01-10-205927)
# 📝 Creating parent issue in Hypercart-Dev-Tools/Server-Monitor-MKII...
# 📋 Title: [WP Code Check] Scan Report (2026-01-10-205927) - 2 confirmed issues
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
# Title: [WP Code Check] Scan Report (2026-01-10-205927) - 2 confirmed issues
# Labels: code-quality, wp-code-check
# Assignee: @me
# Repo: Hypercart-Dev-Tools/Server-Monitor-MKII
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
- ✅ **One parent issue per scan** (UTC timestamp ensures uniqueness)
- ✅ **Timestamp format:** `(YYYY-MM-DD-HHMMSS)` matches JSON log filename
- ✅ **Virtually no duplicates** - each scan has unique timestamp
- ✅ **Easy correlation:** Issue title → JSON log file (e.g., `2026-01-10-205927-UTC.json`)
- ⚙️ **Configurable:** `GITHUB_ALLOW_MULTIPLE_DAILY_SCANS` kept for backward compatibility

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

---

## 📋 Appendix A: Template Updates & Fallback Strategy

### **Question 1: Do we need to update existing templates?**

**Answer:** No, existing templates will continue to work. GitHub integration is **opt-in** and **auto-detected**.

### **Question 2: What's the fallback if template doesn't have GITHUB_REPO?**

**Answer:** Multi-layer fallback strategy with auto-detection.

---

## 🔧 Template Enhancement Strategy

### **1. Update `_TEMPLATE.txt` (Reference Template)**

Add new optional section:

```bash
# ============================================================
# GITHUB INTEGRATION (Optional - Phase 3)
# ============================================================

# GitHub repository (owner/repo format)
# If blank, will auto-detect from git remote in PROJECT_PATH
# Example: GITHUB_REPO=Hypercart-Dev-Tools/Server-Monitor-MKII
# GITHUB_REPO=

# Auto-create GitHub issue after scan (requires gh CLI)
# Default: false (manual review required)
# GITHUB_AUTO_ISSUE=false

# Issue labels (comma-separated)
# Default: code-quality,wp-code-check
# GITHUB_ISSUE_LABELS=code-quality,wp-code-check

# Issue assignee (@username or leave blank)
# Default: @me (current gh CLI user)
# GITHUB_ASSIGNEE=@me

# Milestone (must exist in repo)
# Default: none
# GITHUB_MILESTONE=

# Allow multiple issues per day (default: false)
# If false, will add comment to existing issue instead of creating new one
# GITHUB_ALLOW_MULTIPLE_DAILY_SCANS=false
```

### **2. Existing Templates - Backward Compatibility**

**No changes required!** Existing templates like `hypercart-server-monitor-mkii.txt` will:
- ✅ Continue to work exactly as before
- ✅ Auto-detect GitHub repo if `GITHUB_REPO` is not set
- ✅ Skip GitHub integration if `GITHUB_AUTO_ISSUE` is not set to `true`

**Optional enhancement:** Users can manually add `GITHUB_REPO=` field if they want to override auto-detection.

---

## 🔍 Fallback Detection Strategy

### **Layer 1: Template Configuration (Explicit)**

```bash
# User explicitly sets in template
GITHUB_REPO=Hypercart-Dev-Tools/Server-Monitor-MKII
```

**Priority:** Highest (user knows best)

### **Layer 2: Git Remote Auto-Detection (Smart)**

If `GITHUB_REPO` is blank or not set:

```bash
# detect-github-repo.sh logic:

# 1. Check if PROJECT_PATH is a git repository
cd "$PROJECT_PATH" || exit 1
if ! git rev-parse --git-dir > /dev/null 2>&1; then
  echo "Not a git repository" >&2
  exit 1
fi

# 2. Get remote URL
REMOTE_URL=$(git remote get-url origin 2>/dev/null)

# 3. Parse owner/repo from various formats:
# - https://github.com/owner/repo.git
# - git@github.com:owner/repo.git
# - https://github.com/owner/repo
# - git://github.com/owner/repo.git

GITHUB_REPO=$(echo "$REMOTE_URL" | sed -E 's#.*github\.com[:/]([^/]+/[^/]+)(\.git)?$#\1#')

# 4. Validate format (owner/repo)
if [[ ! "$GITHUB_REPO" =~ ^[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+$ ]]; then
  echo "Invalid GitHub repo format: $GITHUB_REPO" >&2
  exit 1
fi

echo "$GITHUB_REPO"
```

**Priority:** Medium (reliable for GitHub-hosted projects)

### **Layer 3: Manual Specification (Fallback)**

If auto-detection fails:

```bash
# Scanner prompts user (if --create-github-issue flag is used):
echo "⚠️  Could not auto-detect GitHub repository"
echo "Please specify repository in template or use --github-repo flag:"
echo ""
echo "  ./dist/bin/run my-plugin --create-github-issue --github-repo owner/repo"
echo ""
echo "Or add to template:"
echo "  GITHUB_REPO=owner/repo"
exit 1
```

**Priority:** Lowest (requires user intervention)

### **Layer 4: Skip GitHub Integration (Safe Default)**

If all detection fails and user didn't explicitly request GitHub integration:

```bash
# Silently skip GitHub integration
# Scan completes normally, no issue created
# User can manually create issue from JSON log later
```

**Priority:** Safest (no errors, no spam)

---

## 🎯 Detection Flow Diagram

```
┌─────────────────────────────────────┐
│ User runs scan with template        │
└─────────────┬───────────────────────┘
              │
              ▼
      ┌───────────────────┐
      │ GITHUB_AUTO_ISSUE │
      │ = true?           │
      └───────┬───────────┘
              │
        ┌─────┴─────┐
        │           │
       NO          YES
        │           │
        │           ▼
        │   ┌───────────────────┐
        │   │ GITHUB_REPO set   │
        │   │ in template?      │
        │   └───────┬───────────┘
        │           │
        │     ┌─────┴─────┐
        │     │           │
        │    YES         NO
        │     │           │
        │     │           ▼
        │     │   ┌───────────────────┐
        │     │   │ Auto-detect from  │
        │     │   │ git remote        │
        │     │   └───────┬───────────┘
        │     │           │
        │     │     ┌─────┴─────┐
        │     │     │           │
        │     │   SUCCESS     FAIL
        │     │     │           │
        │     └─────┤           │
        │           │           ▼
        │           │   ┌───────────────────┐
        │           │   │ Prompt user or    │
        │           │   │ skip integration  │
        │           │   └───────────────────┘
        │           │
        │           ▼
        │   ┌───────────────────┐
        │   │ Validate gh CLI   │
        │   │ access            │
        │   └───────┬───────────┘
        │           │
        │     ┌─────┴─────┐
        │     │           │
        │   SUCCESS     FAIL
        │     │           │
        │     │           ▼
        │     │   ┌───────────────────┐
        │     │   │ Error: gh CLI not │
        │     │   │ authenticated     │
        │     │   └───────────────────┘
        │     │
        │     ▼
        │   ┌───────────────────┐
        │   │ Create parent     │
        │   │ GitHub issue      │
        │   └───────────────────┘
        │
        ▼
┌─────────────────────────────────────┐
│ Scan complete (no GitHub issue)     │
└─────────────────────────────────────┘
```

---

## 🛠️ Implementation Details

### **File: `dist/bin/lib/detect-github-repo.sh`**

```bash
#!/usr/bin/env bash
# Detect GitHub repository from git remote or template configuration
# Usage: detect_github_repo <project_path> [template_repo]
# Returns: owner/repo format or exits with error

detect_github_repo() {
  local project_path="$1"
  local template_repo="${2:-}"

  # Layer 1: Use template value if provided
  if [ -n "$template_repo" ]; then
    echo "$template_repo"
    return 0
  fi

  # Layer 2: Auto-detect from git remote
  if [ ! -d "$project_path" ]; then
    echo "Error: Project path does not exist: $project_path" >&2
    return 1
  fi

  cd "$project_path" || return 1

  # Check if git repository
  if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "Error: Not a git repository: $project_path" >&2
    return 1
  fi

  # Get remote URL (try origin first, then any remote)
  local remote_url
  remote_url=$(git remote get-url origin 2>/dev/null)
  if [ -z "$remote_url" ]; then
    remote_url=$(git remote get-url "$(git remote | head -1)" 2>/dev/null)
  fi

  if [ -z "$remote_url" ]; then
    echo "Error: No git remote found" >&2
    return 1
  fi

  # Parse GitHub repo from various URL formats
  local github_repo
  github_repo=$(echo "$remote_url" | sed -E 's#.*github\.com[:/]([^/]+/[^/]+)(\.git)?$#\1#')

  # Validate format
  if [[ ! "$github_repo" =~ ^[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+$ ]]; then
    echo "Error: Could not parse GitHub repo from: $remote_url" >&2
    return 1
  fi

  echo "$github_repo"
  return 0
}

# If sourced, export function; if executed, run it
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  detect_github_repo "$@"
fi
```

### **Integration in `check-performance.sh`**

Add after template loading (around line 304):

```bash
# Load template variables
source "$TEMPLATE_FILE"

# Apply template variables
if [ -n "${PROJECT_PATH:-}" ]; then
  PATHS="$PROJECT_PATH"
fi

# NEW: Detect GitHub repository if GitHub integration is enabled
if [ "${GITHUB_AUTO_ISSUE:-false}" = "true" ]; then
  # Source the detection helper
  source "$LIB_DIR/detect-github-repo.sh"

  # Detect or use template value
  DETECTED_GITHUB_REPO=$(detect_github_repo "$PATHS" "${GITHUB_REPO:-}")

  if [ $? -eq 0 ]; then
    GITHUB_REPO="$DETECTED_GITHUB_REPO"
    echo "✓ GitHub repository detected: $GITHUB_REPO"
  else
    echo "⚠️  Could not detect GitHub repository"
    echo "   Add GITHUB_REPO=owner/repo to template or use --github-repo flag"
    exit 1
  fi

  # Validate gh CLI access
  if ! command -v gh &> /dev/null; then
    echo "⚠️  GitHub CLI (gh) not found"
    echo "   Install: https://cli.github.com/"
    exit 1
  fi

  if ! gh auth status &> /dev/null; then
    echo "⚠️  GitHub CLI not authenticated"
    echo "   Run: gh auth login"
    exit 1
  fi

  # Check repository access
  if ! gh repo view "$GITHUB_REPO" &> /dev/null; then
    echo "⚠️  Cannot access repository: $GITHUB_REPO"
    echo "   Check repository name and permissions"
    exit 1
  fi
fi
```

---

## ✅ Summary: Template Update Strategy

### **Existing Templates**
- ✅ **No changes required** - backward compatible
- ✅ **Auto-detection works** - if project is in git repo with GitHub remote
- ✅ **Opt-in only** - GitHub integration disabled by default

### **New Templates**
- ✅ **Include GitHub section** - from updated `_TEMPLATE.txt`
- ✅ **Pre-filled if auto-detected** - AI agent can detect during template completion
- ✅ **Optional field** - can be left blank for auto-detection

### **Fallback Strategy**
1. **Template value** (if set) → Use it
2. **Git remote** (if available) → Auto-detect
3. **User prompt** (if --create-github-issue flag used) → Ask for it
4. **Skip integration** (if no flag) → Silent fallback

### **Migration Path**
- **Phase 1:** Update `_TEMPLATE.txt` with new section
- **Phase 2:** Existing templates work as-is (no migration needed)
- **Phase 3:** Users can optionally add `GITHUB_REPO=` to templates over time
- **Phase 4:** AI agent auto-completes new templates with detected repo

**Zero breaking changes, maximum flexibility!** 🎉
