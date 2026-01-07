# AI Agent Instructions for WP Code Check

ATTN: LLMs if you scan this document and see duplicate/redundant content. Or if you see conflicting instructions, please ask the Human operator for clarification.

## Quick Start

**WP Code Check Location**: `/Users/noelsaw/Documents/GitHub Repos/wp-code-check`

### Running a Scan
```bash
/Users/noelsaw/Documents/GitHub\ Repos/wp-code-check/dist/bin/check-performance.sh --paths /path/to/plugin --format json
```

### Finding Reports
- **JSON logs**: `dist/logs/` (timestamped `.json` files)
- **HTML reports**: `dist/reports/` (timestamped `.html` files)

---

## Phase 2: AI-Assisted Triage (Manual, v1.1 POC)

After HTML report is generated, perform a 2nd pass AI triage to identify false positives.

### When to Use
- User explicitly asks: "Run AI triage on this report"
- User wants to validate false positives before publishing

### Workflow Steps

**Step 1: Read the JSON log**
```bash
cat dist/logs/TIMESTAMP.json | jq '.findings[] | {id, severity, file, line}'
```

**Step 2: Analyze each critical finding** for false positives
- Check for `phpcs:ignore` comments with justification
- Verify nonce/capability checks nearby
- Look for adjacent sanitization functions
- Identify string literal matches vs actual superglobal access

**Step 3: Update the JSON** with verdicts and recommendations
```python
import json
from datetime import datetime

# Read existing JSON
with open('dist/logs/TIMESTAMP.json', 'r') as f:
    data = json.load(f)

# Inject ai_triage data
data['ai_triage'] = {
    'status': 'complete',
    'performed': True,
    'timestamp': datetime.utcnow().isoformat() + 'Z',
    'version': '1.0',
    'summary': {
        'findings_reviewed': 10,
        'confirmed_issues': 2,
        'false_positives': 7,
        'needs_review': 1,
        'confidence_level': 'high'
    },
    'verdicts': [
        {
            'finding_id': 'hcc-008-unsafe-regexp',
            'file': 'repeater.js',
            'line': 126,
            'verdict': 'confirmed',
            'reason': 'User property in RegExp without escaping',
            'confidence': 'high',
            'recommendation': 'Add regex escaping for property names'
        },
        {
            'finding_id': 'spo-002-superglobals',
            'file': 'form_display.php',
            'line': 154,
            'verdict': 'false_positive',
            'reason': 'Has phpcs:ignore comment + nonce check on line 96',
            'confidence': 'high',
            'recommendation': 'Safe to ignore - already protected'
        }
    ],
    'recommendations': [
        'Priority 1: Fix unsafe RegExp in repeater.js',
        'Priority 2: Review minified JS source'
    ]
}

# Write updated JSON
with open('dist/logs/TIMESTAMP.json', 'w') as f:
    json.dump(data, f, indent=2)
```

**Step 4: Re-generate HTML**
```bash
python3 dist/bin/json-to-html.py dist/logs/TIMESTAMP.json dist/reports/TIMESTAMP.html
```

### Verdict Types

| Verdict | Meaning | Use When |
|---------|---------|----------|
| `confirmed` | Real issue, needs fixing | Code is genuinely unsafe/problematic |
| `false_positive` | Safe to ignore | Has safeguards (nonce, sanitization, etc.) |
| `needs_review` | Unclear, manual verification needed | Ambiguous or context-dependent |

### Confidence Levels

| Level | Meaning |
|-------|---------|
| `high` | 90%+ confident in this verdict |
| `medium` | 60-89% confident |
| `low` | <60% confident, needs human review |

---

## Common False Positive Patterns

| Rule ID | Common False Positive Reason |
|---------|------------------------------|
| `spo-002-superglobals` | Has `phpcs:ignore` with nonce verification elsewhere in function |
| `rest-no-pagination` | Endpoint returns single item, not collection (e.g., `/item/{id}`) |
| `get-users-no-limit` | Args passed through `apply_filters()` hook that adds limit |
| `direct-db-query` | Query uses `$wpdb->prepare()` on adjacent line (multi-line query) |
| `admin-no-cap-check` | Function is only called from another function that has cap check |
| `n-plus-1-pattern` | File has "meta" in variable name but not actual meta query in loop |

---

## Manual JSON to HTML Conversion

If HTML generation fails during a scan:

```bash
# Find latest JSON log
latest_json=$(ls -t dist/logs/*.json | head -1)

# Convert to HTML
python3 dist/bin/json-to-html.py "$latest_json" dist/reports/manual-report.html
```

---

## Troubleshooting

| Error | Solution |
|-------|----------|
| `Permission denied` | `chmod +x /path/to/script.sh` |
| `No such file or directory` | Use absolute path, verify file exists |
| `python3: command not found` | Install Python 3 |
| `Invalid JSON` | Validate with: `jq empty dist/logs/your-file.json` |

---

