#!/usr/bin/env bash
#
# create-github-issue.sh
# Create GitHub issues from WP Code Check scan results
#
# Usage:
#   ./create-github-issue.sh --scan-id 2026-01-12-155649-UTC [--repo owner/repo] [--create-sub-issues]
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Default values
SCAN_ID=""
GITHUB_REPO=""
CREATE_SUB_ISSUES=false
JSON_FILE=""
TEMPLATE_FILE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --scan-id)
            SCAN_ID="$2"
            shift 2
            ;;
        --repo)
            GITHUB_REPO="$2"
            shift 2
            ;;
        --create-sub-issues)
            CREATE_SUB_ISSUES=true
            shift
            ;;
        --help)
            echo "Usage: $0 --scan-id SCAN_ID [--repo owner/repo] [--create-sub-issues]"
            echo ""
            echo "Options:"
            echo "  --scan-id SCAN_ID          Scan ID (e.g., 2026-01-12-155649-UTC)"
            echo "  --repo owner/repo          GitHub repository (optional, reads from template)"
            echo "  --create-sub-issues        Create individual sub-issues for each finding"
            echo "  --help                     Show this help message"
            exit 0
            ;;
        *)
            echo -e "${RED}Error: Unknown option $1${NC}"
            exit 1
            ;;
    esac
done

# Validate required arguments
if [[ -z "$SCAN_ID" ]]; then
    echo -e "${RED}Error: --scan-id is required${NC}"
    echo "Usage: $0 --scan-id SCAN_ID [--repo owner/repo] [--create-sub-issues]"
    exit 1
fi

# Find JSON file
JSON_FILE="$PROJECT_ROOT/dist/logs/${SCAN_ID}.json"
if [[ ! -f "$JSON_FILE" ]]; then
    echo -e "${RED}Error: JSON file not found: $JSON_FILE${NC}"
    exit 1
fi

echo -e "${BLUE}📄 Reading scan results: $JSON_FILE${NC}"

# Check if GitHub CLI is installed and authenticated
if ! command -v gh &> /dev/null; then
    echo -e "${RED}Error: GitHub CLI (gh) is not installed${NC}"
    echo "Install it from: https://cli.github.com/"
    exit 1
fi

if ! gh auth status &> /dev/null; then
    echo -e "${RED}Error: GitHub CLI is not authenticated${NC}"
    echo "Run: gh auth login"
    exit 1
fi

echo -e "${GREEN}✓ GitHub CLI authenticated${NC}"

# Extract metadata from JSON (support both .metadata and .project formats)
PLUGIN_NAME=$(jq -r '.project.name // .metadata.plugin_name // "Unknown Plugin"' "$JSON_FILE")
PLUGIN_VERSION=$(jq -r '.project.version // .metadata.plugin_version // "Unknown Version"' "$JSON_FILE")
PROJECT_PATH=$(jq -r '.project.path // .metadata.project_path // ""' "$JSON_FILE")
TOTAL_FINDINGS=$(jq -r '.summary.total_findings // 0' "$JSON_FILE")
CONFIRMED_COUNT=$(jq -r '.ai_triage.summary.confirmed_issues // 0' "$JSON_FILE")
NEEDS_REVIEW_COUNT=$(jq -r '.ai_triage.summary.needs_review // 0' "$JSON_FILE")
FALSE_POSITIVE_COUNT=$(jq -r '.ai_triage.summary.false_positives // 0' "$JSON_FILE")
SCANNER_VERSION=$(jq -r '.version // "v1.0.90"' "$JSON_FILE")

echo -e "${BLUE}📊 Scan Summary:${NC}"
echo "  Plugin/Theme: $PLUGIN_NAME v$PLUGIN_VERSION"
echo "  Total Findings: $TOTAL_FINDINGS"
echo "  Confirmed Issues: $CONFIRMED_COUNT"
echo "  Needs Review: $NEEDS_REVIEW_COUNT"
echo "  False Positives: $FALSE_POSITIVE_COUNT"

# If GITHUB_REPO not provided, try to find it from template
if [[ -z "$GITHUB_REPO" ]]; then
    echo -e "${YELLOW}⚠ No --repo specified, searching for template...${NC}"

    if [[ -n "$PROJECT_PATH" ]]; then
        # Search templates for matching path
        for template in "$PROJECT_ROOT/dist/TEMPLATES"/*.txt; do
            if grep -q "PROJECT_PATH='$PROJECT_PATH'" "$template" 2>/dev/null; then
                TEMPLATE_FILE="$template"
                GITHUB_REPO=$(grep "^GITHUB_REPO=" "$template" | cut -d"'" -f2 || echo "")
                break
            fi
        done
    fi
    
    if [[ -z "$GITHUB_REPO" ]]; then
        echo -e "${RED}Error: Could not find GITHUB_REPO in template${NC}"
        echo "Please specify --repo owner/repo or add GITHUB_REPO to your template file"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Found GITHUB_REPO in template: $GITHUB_REPO${NC}"
fi

# Clean up repo format (remove https://github.com/ if present)
GITHUB_REPO=$(echo "$GITHUB_REPO" | sed 's|https://github.com/||' | sed 's|\.git$||')

echo -e "${BLUE}🎯 Target repository: $GITHUB_REPO${NC}"

# Convert UTC timestamp to local time
SCAN_DATE=$(echo "$SCAN_ID" | cut -d'-' -f1-3)
SCAN_TIME=$(echo "$SCAN_ID" | cut -d'-' -f4 | sed 's/UTC//')
LOCAL_TIME=$(date -j -f "%Y-%m-%d-%H%M%S" "${SCAN_DATE}-${SCAN_TIME}" "+%A, %B %d, %Y at %I:%M %p %Z" 2>/dev/null || echo "Unknown")

# Generate issue title
ISSUE_TITLE="WP Code Check Review - $SCAN_ID"

# Generate issue body
ISSUE_BODY=$(cat <<EOF
# WP Code Check Review - $SCAN_ID

**Scanned:** $LOCAL_TIME
**Plugin/Theme:** $PLUGIN_NAME v$PLUGIN_VERSION
**Scanner Version:** $SCANNER_VERSION

**Summary:** $TOTAL_FINDINGS findings | $CONFIRMED_COUNT confirmed issues | $NEEDS_REVIEW_COUNT need review | $FALSE_POSITIVE_COUNT false positives

---

## ✅ Confirmed by AI Triage

EOF
)

# Add confirmed issues
# Group by rule and file to create concise issue list
CONFIRMED_ISSUES="
"
while IFS= read -r finding; do
    RULE=$(echo "$finding" | jq -r '.finding_key.id')
    FILE=$(echo "$finding" | jq -r '.finding_key.file' | sed "s|$PROJECT_PATH/||" | sed "s|^/Users/[^/]*/Downloads/||")
    LINE=$(echo "$finding" | jq -r '.finding_key.line')
    RATIONALE=$(echo "$finding" | jq -r '.rationale' | head -c 100)

    CONFIRMED_ISSUES+="- [ ] **${RATIONALE}...**"$'\n'
    CONFIRMED_ISSUES+="  \`${FILE}:${LINE}\` | Rule: \`${RULE}\`"$'\n'$'\n'
done < <(jq -c '.ai_triage.triaged_findings[] | select(.classification == "Confirmed")' "$JSON_FILE" 2>/dev/null)

if [[ -z "$CONFIRMED_ISSUES" ]]; then
    CONFIRMED_ISSUES="No confirmed issues found."
fi

ISSUE_BODY+="$CONFIRMED_ISSUES"

ISSUE_BODY+="
---

## 🔍 Most Critical but Unconfirmed

"

# Add needs review issues (False Positives with low confidence or other classifications)
NEEDS_REVIEW=""
while IFS= read -r finding; do
    RULE=$(echo "$finding" | jq -r '.finding_key.id')
    FILE=$(echo "$finding" | jq -r '.finding_key.file' | sed "s|$PROJECT_PATH/||" | sed "s|^/Users/[^/]*/Downloads/||")
    LINE=$(echo "$finding" | jq -r '.finding_key.line')
    CLASSIFICATION=$(echo "$finding" | jq -r '.classification')
    CONFIDENCE=$(echo "$finding" | jq -r '.confidence')

    NEEDS_REVIEW+="- [ ] **${CLASSIFICATION} (${CONFIDENCE} confidence)**"$'\n'
    NEEDS_REVIEW+="  \`${FILE}:${LINE}\` | Rule: \`${RULE}\`"$'\n'$'\n'
done < <(jq -c '.ai_triage.triaged_findings[] | select(.classification != "Confirmed" and .classification != "False Positive")' "$JSON_FILE" 2>/dev/null | head -5)

if [[ -z "$NEEDS_REVIEW" ]]; then
    NEEDS_REVIEW="No issues need review."
fi

ISSUE_BODY+="$NEEDS_REVIEW"

# Add footer with links
HTML_REPORT="dist/reports/${SCAN_ID}.html"
JSON_REPORT="dist/logs/${SCAN_ID}.json"

ISSUE_BODY+="

---

**Full Report:** [HTML](../$HTML_REPORT) | [JSON](../$JSON_REPORT)
**Powered by:** [WPCodeCheck.com](https://wpCodeCheck.com)
"

# Save issue body to temp file for debugging
TEMP_ISSUE_FILE="/tmp/gh-issue-${SCAN_ID}.md"
echo "$ISSUE_BODY" > "$TEMP_ISSUE_FILE"

echo -e "${BLUE}📝 Issue body saved to: $TEMP_ISSUE_FILE${NC}"
echo -e "${YELLOW}Preview:${NC}"
echo "----------------------------------------"
head -n 30 "$TEMP_ISSUE_FILE"
echo "----------------------------------------"

# Ask for confirmation
read -p "Create GitHub issue in $GITHUB_REPO? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Cancelled by user${NC}"
    exit 0
fi

# Create GitHub issue
echo -e "${BLUE}🚀 Creating GitHub issue...${NC}"

ISSUE_URL=$(gh issue create \
    --repo "$GITHUB_REPO" \
    --title "$ISSUE_TITLE" \
    --body-file "$TEMP_ISSUE_FILE" \
    --label "automated-scan,security,performance" \
    2>&1)

if [[ $? -eq 0 ]]; then
    echo -e "${GREEN}✅ GitHub issue created successfully!${NC}"
    echo -e "${GREEN}   $ISSUE_URL${NC}"

    # Extract issue number
    ISSUE_NUMBER=$(echo "$ISSUE_URL" | grep -oE '[0-9]+$')
    echo -e "${BLUE}   Issue #$ISSUE_NUMBER${NC}"

    # Create sub-issues if requested
    if [[ "$CREATE_SUB_ISSUES" == true ]]; then
        echo -e "${BLUE}📋 Creating sub-issues...${NC}"
        echo -e "${YELLOW}⚠ Sub-issue creation not yet implemented${NC}"
        # TODO: Implement sub-issue creation
    fi
else
    echo -e "${RED}❌ Failed to create GitHub issue${NC}"
    echo "$ISSUE_URL"
    exit 1
fi

# Clean up temp file
rm -f "$TEMP_ISSUE_FILE"

echo -e "${GREEN}✅ Done!${NC}"

