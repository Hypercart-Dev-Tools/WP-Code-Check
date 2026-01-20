# Project Automation: Phase 2 AI Triage Integration

**Created**: 2026-01-07  
**Status**: Not Started  
**Priority**: High  
**Target Version**: v1.1.0

---

## Project Goal:

Enable AI-assisted false positive detection as a 2nd pass after static analysis, with results stored in JSON and rendered in HTML for both local dev and server deployment.

Final generated HTML Reports should have the following:
Plugin/theme metadata (inc. license type)
Analysis date/time
Scanner version
Phase 2 - AI analysis (TLDR;)
Phase 1 - Raw scanner / deterministic output (detailed)

## Highlevel Workflow: [insert here]

1. User runs test on plugin/theme
2. JSON report is generated with placeholder for Phase 2
3. HTML report is generated with placeholder for Phase 2
4. User runs Phase 2 (AI triage)
5. JSON report is updated with Phase 2 data
6. JSON file is uploaded to WP server
7. WP server generates HTML report with Phase 2 and Phase 1 content in place

## Final outcome

## 📋 Implementation Checklist

- [ ] **Phase 1: JSON Schema Updates**
  - [ ] Add `ai_triage` placeholder object to JSON schema
  - [ ] Define structure: `status`, `findings_reviewed`, `verdicts`, `timestamp`
  - [ ] Document in PATTERN-LIBRARY.md

- [ ] **Phase 2: HTML Template Updates**
  - [ ] Add Phase 2 placeholder section to report-template.html
  - [ ] Create `#ai-triage` injection point with `data-ai-inject="triage"`
  - [ ] Style placeholder state (pending/complete/error)
  - [ ] Add disclaimer box styling

- [ ] **Phase 3: AI Agent Instructions**
  - [ ] Update `_AI_INSTRUCTIONS.md` with Phase 2 workflow
  - [ ] Document JSON injection method
  - [ ] Document HTML re-generation after JSON update
  - [ ] Add disclaimer text template

- [ ] **Phase 4: Local Dev Workflow**
  - [ ] Test AI triage injection into JSON
  - [ ] Test JSON → HTML re-conversion with AI data
  - [ ] Verify both local HTML and server-ready JSON work

- [ ] **Phase 5: Server-Side Script**
  - [ ] Create `dist/bin/json-to-html-with-ai.py` (or enhance existing)
  - [ ] Handle missing `ai_triage` section gracefully
  - [ ] Preserve AI triage data during conversion

---

## 🎯 Overview

**Goal**: Enable AI-assisted false positive detection as a 2nd pass after static analysis, with results stored in JSON and rendered in HTML for both local dev and server deployment.

**Architecture**:
```
Static Scan → JSON (Phase 1 data + AI placeholder)
                ↓
            Local Dev AI Agent (optional)
                ↓
            JSON (Phase 1 + Phase 2 AI triage)
                ↓
            JSON → HTML (local or server)
                ↓
            Final HTML Report (with both phases)
```

---

## 📐 JSON Schema: `ai_triage` Object

```json
{
  "ai_triage": {
    "status": "pending",
    "performed": false,
    "timestamp": null,
    "version": "1.0",
    "disclaimer": "This AI-assisted analysis is provided for informational purposes only...",
    "summary": {
      "findings_reviewed": 0,
      "confirmed_issues": 0,
      "false_positives": 0,
      "needs_review": 0,
      "confidence_level": "N/A"
    },
    "verdicts": [],
    "recommendations": [],
    "notes": "Not performed yet"
  }
}
```

**Verdict Object Structure**:
```json
{
  "finding_id": "hcc-008-unsafe-regexp",
  "file": "repeater.js",
  "line": 126,
  "verdict": "confirmed",
  "reason": "User property in RegExp without escaping",
  "confidence": "high",
  "recommendation": "Add regex escaping for property names"
}
```

---

## 🎨 HTML Template: Phase 2 Placeholder

```html
<!-- Phase 2: AI-Assisted Triage (Placeholder) -->
<section id="ai-triage" class="ai-triage-section" data-ai-inject="triage">
  <h2>Phase 2 (TL;DR) - Automated AI False Positive Scan</h2>
  
  <div class="ai-triage-disclaimer">
    <strong>⚠️ Disclaimer:</strong> This AI-assisted analysis is provided for 
    informational purposes only and represents probabilistic pattern matching, 
    not definitive security assessment. Developers must perform manual code 
    review to verify all findings. We make no guarantees about accuracy or 
    completeness. When in doubt, treat flagged code as requiring human review.
  </div>
  
  <div class="ai-triage-content" data-status="pending">
    <p class="status-message">⏳ Not performed yet</p>
    <p class="help-text">
      Run the AI triage command to analyze findings and identify likely false positives.
    </p>
  </div>
</section>
```

**CSS Styling**:
```css
.ai-triage-section {
  background: #f0f4ff;
  border-left: 4px solid #4a90e2;
  padding: 20px;
  margin: 30px 0;
  border-radius: 4px;
}

.ai-triage-disclaimer {
  background: #fff3cd;
  border: 1px solid #ffc107;
  padding: 12px;
  border-radius: 4px;
  margin-bottom: 15px;
  font-size: 0.9em;
}

.ai-triage-content[data-status="pending"] {
  color: #666;
  font-style: italic;
}

.ai-triage-content[data-status="complete"] {
  color: #155724;
}

.ai-triage-content[data-status="error"] {
  color: #721c24;
  background: #f8d7da;
  padding: 10px;
  border-radius: 4px;
}
```

---

## 🤖 AI Agent Workflow (Local Dev)

**Step 1: Detect Report**
```bash
# After scan completes, AI agent checks for new JSON
latest_json=$(ls -t dist/logs/*.json | head -1)
echo "New report: $latest_json"
```

**Step 2: Perform Triage**
```bash
# AI agent reads JSON, analyzes findings
# Generates verdicts and recommendations
# Updates JSON ai_triage section
```

**Step 3: Update JSON**
```bash
# AI agent injects Phase 2 data into JSON
# Sets: status="complete", performed=true, timestamp, verdicts[], etc.
```

**Step 4: Re-generate HTML**
```bash
# Re-run JSON → HTML converter with updated JSON
python3 dist/bin/json-to-html.py "$latest_json" "dist/reports/$(basename $latest_json .json).html"
```

---

## 📝 AI Instructions Update

Add to `_AI_INSTRUCTIONS.md`:

```markdown
## Phase 2: AI-Assisted Triage (Optional)

After HTML report is generated, you can perform a 2nd pass AI triage:

1. **Read the JSON log** to understand findings
2. **Analyze each critical finding** for false positives
3. **Update the JSON** with verdicts and recommendations
4. **Re-generate HTML** to include AI triage section

### JSON Injection Method

Use Python to safely update JSON:
\`\`\`python
import json

with open('dist/logs/TIMESTAMP.json', 'r') as f:
    data = json.load(f)

data['ai_triage'] = {
    'status': 'complete',
    'performed': True,
    'timestamp': '2026-01-07T16:45:00Z',
    'verdicts': [
        {
            'finding_id': 'hcc-008-unsafe-regexp',
            'verdict': 'confirmed',
            'reason': '...'
        }
    ]
}

with open('dist/logs/TIMESTAMP.json', 'w') as f:
    json.dump(data, f, indent=2)
\`\`\`

### Re-generate HTML

After updating JSON:
\`\`\`bash
python3 dist/bin/json-to-html.py dist/logs/TIMESTAMP.json dist/reports/TIMESTAMP.html
\`\`\`
```

---

## 🖥️ Server-Side Script

**File**: `dist/bin/json-to-html-with-ai.py`

- Reads JSON with optional `ai_triage` section
- Injects Phase 2 content into HTML template
- Handles missing `ai_triage` gracefully (shows placeholder)
- Preserves all data for archival

**Key Features**:
- Detects `ai_triage.performed === true`
- Renders verdicts table if present
- Shows disclaimer prominently
- Maintains backward compatibility

---

## 🔄 Workflow Examples

### Local Dev (With AI Triage)
```bash
# 1. Run scan
./run gravityforms --format json

# 2. AI agent performs triage (automatic or manual)
# → Updates JSON with Phase 2 data

# 3. Re-generate HTML
python3 dist/bin/json-to-html.py dist/logs/2026-01-07-163420-UTC.json dist/reports/2026-01-07-163420-UTC.html

# 4. Open report (now includes Phase 2)
open dist/reports/2026-01-07-163420-UTC.html
```

### Server Deployment (No AI)
```bash
# 1. Receive JSON from local dev
# 2. Run server-side converter
python3 dist/bin/json-to-html-with-ai.py input.json output.html

# 3. If JSON has ai_triage data, render it
# 4. If not, show placeholder
```

---

## 🎯 Success Criteria

- ✅ JSON schema includes `ai_triage` placeholder
- ✅ HTML template has Phase 2 section with placeholder
- ✅ AI agent can inject triage data into JSON
- ✅ JSON → HTML conversion preserves AI data
- ✅ Both local and server workflows work
- ✅ Disclaimer is prominent and clear
- ✅ Backward compatible (old JSON without ai_triage still works)

---

## 📚 Related Files

- `dist/TEMPLATES/_AI_INSTRUCTIONS.md` - Update with Phase 2 workflow
- `dist/bin/templates/report-template.html` - Add Phase 2 section
- `dist/bin/json-to-html.py` - Enhance to handle ai_triage
- `PATTERN-LIBRARY.json` - Document ai_triage schema

