# AGENTS.md Update - Standardized Data Analysis Pattern

**Created:** 2026-01-15  
**Completed:** 2026-01-15  
**Status:** ✅ Complete  
**Version:** AGENTS.md v2.1.0 → v2.2.0

---

## Summary

Added comprehensive "Standardized Data Analysis Pattern" section to AGENTS.md to provide AI agents with a systematic workflow for debugging and analyzing external data sources (APIs, databases, logs, scrapers).

---

## Changes Made

### 1. AGENTS.md Updates

**File:** `AGENTS.md`  
**Version:** v2.1.0 → v2.2.0  
**Lines Added:** ~260 lines

**New Section Added:**
- `## 🛠️ Standardized Data Analysis Pattern` (after JSON to HTML Report Conversion section)

**Content Includes:**
1. **The 4-Step Pattern**
   - Step 1: Capture the Data (with stderr redirection)
   - Step 1.5: Validate Data Structure (optional but recommended)
   - Step 2: Display the Raw Output (transparency requirement)
   - Step 3: Analyze the File (structured analysis framework)
   - Step 4: Iterate if Needed (refinement loop)

2. **Usage Examples (4 comprehensive examples)**
   - WordPress Database Analysis
   - API Endpoint Testing
   - Log File Debugging
   - Webhook Payload Validation

3. **Best Practices**
   - Always use `./data-stream.json` for consistency
   - Capture stderr with `2>&1`
   - Validate before analyzing
   - Show raw data first
   - Be systematic
   - Iterate incrementally

4. **File Management**
   - `.gitignore` recommendations
   - Optional timestamped history approach
   - Cleanup strategies

5. **When to Use This Pattern**
   - ✅ Use cases (8 scenarios)
   - ❌ Don't use cases (4 scenarios)

6. **Troubleshooting**
   - `jq: command not found` solution
   - File too large for chat context
   - Binary or non-text data handling

---

### 2. .gitignore Updates

**File:** `.gitignore`  
**Lines Added:** 6 lines

**New Entries:**
```gitignore
# Data analysis temporary files (from STANDARDIZED DATA ANALYSIS PATTERN)
# See AGENTS.md for usage guidelines
data-stream.json
data-stream-*.json
data-stream.txt
data-stream.csv
```

---

## Enhancements Made

### Original User Proposal
User provided a basic 4-step pattern with examples.

### AI Enhancements Added

1. **Step 1.5: Validation Step**
   - Added optional validation before analysis
   - Includes `jq empty` for JSON validation
   - File type checking for non-JSON data
   - Encoding validation for text files

2. **Comprehensive Examples**
   - Expanded from 3 to 4 examples
   - Added detailed comments for each step
   - Included expected analysis output
   - Added WordPress-specific examples (WP-CLI, REST API)

3. **Best Practices Section**
   - 6 key principles for consistent usage
   - Emphasis on systematic approach
   - Incremental iteration guidance

4. **File Management**
   - `.gitignore` integration
   - Optional timestamped history approach
   - Automatic cleanup strategy (keep last 10)

5. **When to Use / When Not to Use**
   - Clear decision framework
   - 8 positive use cases
   - 4 negative use cases (avoid misuse)

6. **Troubleshooting Section**
   - Common problems and solutions
   - Tool installation guidance
   - Data size handling strategies
   - Encoding conversion examples

7. **Transparency Rationale**
   - Explicit "Why this matters" section
   - Prevents AI hallucination
   - Ensures user visibility
   - Creates shared reference point

---

## Benefits

### For AI Agents
- ✅ Clear, repeatable workflow for data analysis
- ✅ Prevents hallucination by forcing raw data display
- ✅ Structured analysis framework (schema → quality → stats → recommendations)
- ✅ Reduces back-and-forth debugging cycles

### For Users
- ✅ Transparency (can see what AI is analyzing)
- ✅ Reproducible debugging sessions
- ✅ No copy-paste errors or truncation
- ✅ Consistent analysis quality
- ✅ Easy to iterate and refine queries

### For the Project
- ✅ Standardized debugging approach
- ✅ Better documentation of data analysis workflows
- ✅ Reduced debugging time
- ✅ Improved AI-human collaboration

---

## Use Cases in This Project

This pattern is particularly valuable for:

1. **WordPress Database Analysis**
   - Analyzing WP_Query results
   - Inspecting post meta, user meta, options
   - Debugging custom post types and taxonomies

2. **Performance Scanner Development**
   - Testing pattern detection accuracy
   - Analyzing scan results
   - Validating JSON output structure

3. **API Integration Testing**
   - WordPress REST API endpoints
   - Custom scraper endpoints
   - Webhook payload validation

4. **Log Analysis**
   - PHP error logs
   - WordPress debug logs
   - Plugin-specific logs

---

## Files Modified

1. ✅ `AGENTS.md` - Added ~260 lines (v2.1.0 → v2.2.0)
2. ✅ `.gitignore` - Added 6 lines (data-stream files)
3. ✅ `PROJECT/3-COMPLETED/AGENTS-MD-UPDATE-DATA-ANALYSIS-PATTERN.md` - This document

---

## Next Steps

**Recommended:**
- Test the pattern in real debugging scenarios
- Gather feedback on effectiveness
- Consider creating a helper script (`bin/capture-data.sh`) to automate the pattern

**Optional:**
- Add examples to PROJECT documentation
- Create video tutorial demonstrating the pattern
- Add pattern to onboarding documentation for new contributors

---

## Lessons Learned

1. **Standardization Reduces Friction** - Having a consistent file location (`./data-stream.json`) eliminates decision fatigue
2. **Transparency Builds Trust** - Forcing `cat` before analysis ensures user can verify AI's work
3. **Validation Prevents Errors** - Step 1.5 catches malformed data early
4. **Examples Are Essential** - Concrete examples make abstract patterns actionable
5. **Troubleshooting Saves Time** - Anticipating common problems reduces support burden

---

## Status

✅ **Complete** - AGENTS.md updated with comprehensive data analysis pattern  
✅ **Tested** - Pattern structure validated  
✅ **Documented** - Full documentation in AGENTS.md  
✅ **Version Bumped** - v2.1.0 → v2.2.0

