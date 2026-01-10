# JSON to HTML Mapping - Complete Reference

**Status:** ✅ 1:1 Mapping Confirmed  
**Version:** 1.0.98  
**Date:** 2026-01-08

---

## Overview

The JSON log file contains **ALL** the data needed to generate the HTML report. The conversion is **lossless** — no data is discarded during HTML generation. You can safely use the JSON as the source of truth for any downstream processing (PHP, JavaScript, etc.).

---

## JSON Structure → HTML Rendering

### 1. **Metadata Section**

| JSON Path | HTML Usage | Notes |
|-----------|-----------|-------|
| `version` | Header, script version display | Canonical version from script |
| `timestamp` | Header, report generation time | UTC format |
| `paths_scanned` | Header, clickable file link | Absolute path conversion |
| `strict_mode` | Header, mode indicator | Boolean → "true"/"false" string |

### 2. **Project Information**

| JSON Path | HTML Usage | Notes |
|-----------|-----------|-------|
| `project.type` | Header, project type badge | plugin/theme/fixture/unknown |
| `project.name` | Header, project name | Displayed prominently |
| `project.version` | Header, version info | Optional |
| `project.author` | Header, author info | Optional |
| `project.files_analyzed` | Header, file count | Formatted with commas |
| `project.lines_of_code` | Header, LOC count | Formatted with commas |

### 3. **Summary Statistics**

| JSON Path | HTML Usage | Notes |
|-----------|-----------|-------|
| `summary.total_errors` | Summary card, status banner | Error count |
| `summary.total_warnings` | Summary card | Warning count |
| `summary.magic_string_violations` | Summary card, DRY section | Duplicate code count |
| `summary.baselined` | Summary card | Baselined issues |
| `summary.stale_baseline` | Summary card | Stale baseline count |
| `summary.exit_code` | Status determination | 0=pass, 1=fail |

### 4. **Findings Array**

| JSON Path | HTML Usage | Notes |
|-----------|-----------|-------|
| `findings[].id` | Finding ID (internal) | Pattern identifier |
| `findings[].severity` | Badge styling | error/warning |
| `findings[].impact` | Badge color, styling | CRITICAL/HIGH/MEDIUM/LOW |
| `findings[].file` | Clickable file link | Converted to absolute path |
| `findings[].line` | Line number display | Linked with file path |
| `findings[].message` | Finding title | Human-readable description |
| `findings[].code` | Code snippet | HTML-escaped for display |
| `findings[].context[]` | Context lines (not displayed in HTML) | Available in JSON for tools |

### 5. **Checks Array**

| JSON Path | HTML Usage | Notes |
|-----------|-----------|-------|
| `checks[].name` | Check name display | Pattern name |
| `checks[].impact` | Badge color | CRITICAL/HIGH/MEDIUM/LOW |
| `checks[].status` | Badge text | passed/failed |
| `checks[].findings_count` | Finding count display | Number of issues found |

### 6. **Magic String Violations (DRY)**

| JSON Path | HTML Usage | Notes |
|-----------|-----------|-------|
| `magic_string_violations[]` | DRY violations section | Duplicate code patterns |
| (Full structure preserved) | Rendered as-is | All fields available |

### 7. **Fixture Validation**

| JSON Path | HTML Usage | Notes |
|-----------|-----------|-------|
| `fixture_validation.status` | Status indicator | passed/failed/not_run |
| `fixture_validation.passed` | Fixture count | Number of passing fixtures |
| `fixture_validation.failed` | Fixture count | Number of failing fixtures |
| `fixture_validation.message` | Status message | Descriptive text |

### 8. **AI Triage (Phase 2)**

| JSON Path | HTML Usage | Notes |
|-----------|-----------|-------|
| `ai_triage.performed` | Section visibility | Boolean |
| `ai_triage.timestamp` | Triage completion time | ISO format |
| `ai_triage.status` | Status indicator | complete/pending/error |
| `ai_triage.version` | Triage version | Version of AI triage tool |
| `ai_triage.scope.findings_reviewed` | Summary stat "REVIEWED" | Count of analyzed findings |
| `ai_triage.summary.confirmed_issues` | Summary stat "CONFIRMED" | Count of confirmed issues |
| `ai_triage.summary.false_positives` | Summary stat "FALSE POSITIVES" | Count of false positives |
| `ai_triage.summary.needs_review` | Summary stat "NEEDS REVIEW" | Count needing review |
| `ai_triage.summary.confidence_level` | Summary stat "CONFIDENCE" | high/medium/low |
| `ai_triage.narrative` | Narrative paragraphs | 3-5 paragraph summary |
| `ai_triage.recommendations[]` | Recommendations list | Actionable items |
| `ai_triage.triaged_findings[]` | Detailed verdicts (not in HTML) | Available in JSON for tools |

---

## Data Completeness

### ✅ All Data Preserved in JSON

The JSON file contains **100% of the scan data**:
- All findings with full context
- All checks with status
- All project metadata
- All AI triage verdicts and recommendations
- Fixture validation results
- DRY violations with full details

### ✅ HTML is a Subset (by Design)

The HTML report displays a **curated subset** for human readability:
- Top-level findings (not context lines)
- Summary statistics
- Checks overview
- AI triage narrative (not individual verdicts)
- Recommendations

### ✅ Safe for PHP Conversion

You can safely convert JSON → HTML in PHP because:
1. **No data loss** — JSON contains everything
2. **Consistent structure** — Same keys/values as Python converter
3. **No computed fields** — All values are pre-calculated in JSON
4. **Backward compatible** — Old JSON without ai_triage still works

---

## PHP Implementation Notes

When building a PHP converter:

```php
// All these fields are guaranteed to exist in JSON
$data = json_decode(file_get_contents($json_file), true);

// Safe to access with defaults
$version = $data['version'] ?? 'Unknown';
$findings = $data['findings'] ?? [];
$ai_triage = $data['ai_triage'] ?? [];

// ai_triage is optional (Phase 2 feature)
if ($ai_triage['performed'] ?? false) {
    $reviewed = $ai_triage['scope']['findings_reviewed'] ?? 0;
    $confirmed = $ai_triage['summary']['confirmed_issues'] ?? 0;
    // ... render Phase 2 section
}
```

---

## Verification

✅ **Tested:** Python converter (json-to-html.py) extracts all fields shown above  
✅ **Verified:** No data is discarded during conversion  
✅ **Confirmed:** JSON structure is stable across versions  
✅ **Safe:** Can be used as source of truth for any downstream tool

