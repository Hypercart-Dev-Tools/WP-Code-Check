# Severity Ranking MVP v1

**Context**: WP Code Check is a CLI scanner that detects 15+ WordPress performance/security antipatterns. It already ships hardcoded checks with fixed severity levels (CRITICAL, HIGH, MEDIUM, LOW). This feature allows teams to customize severity rankings per-project to reduce noise and focus on what matters to them.

## Problem
- **Developer A** thinks missing nonce checks are CRITICAL (security team)
- **Developer B** downranks them to MEDIUM (code review overhead)
- **Developer C** wants `deprecated-function` as LOW (legacy codebase)

Currently: All teams get the same severity levels. No customization = noise.

## The MVP Approach: Single Config File with Explicit Override

**Core Concept**: Ship a `/dist/config/severity-levels.json` with factory defaults. Users pass `--severity-config <path>` to override. No auto-discovery, no multiple locations. Simple and explicit.

### Current State (Before MVP)

The script `./dist/bin/check-performance.sh` has hardcoded severity levels:

```bash
# Current (in script, not configurable)
text_echo "${BLUE}▸ Missing nonce validation ${RED}[HIGH]${NC}"
text_echo "${BLUE}▸ REST endpoints without pagination ${RED}[CRITICAL]${NC}"
text_echo "${BLUE}▸ Unbounded queries ${RED}[CRITICAL]${NC}"
text_echo "${BLUE}▸ N+1 patterns ${YELLOW}[MEDIUM]${NC}"
```

### MVP: Shipped Config File

**Phase 1: Create `/dist/config/severity-levels.json`**

```json
{
  "_metadata": {
    "version": "1.0.59",
    "description": "WP Code Check - Severity Level Customization",
    "last_updated": "2025-12-31"
  },
  "severity_levels": {
    "wp-ajax-missing-nonce": {
      "id": "wp-ajax-missing-nonce",
      "level": "HIGH",
      "factory_default": "HIGH",
      "category": "security",
      "description": "AJAX handler missing nonce validation"
    },
    "unbounded-rest-endpoint": {
      "id": "unbounded-rest-endpoint",
      "level": "CRITICAL",
      "factory_default": "CRITICAL",
      "category": "performance",
      "description": "REST endpoint without pagination/limits"
    },
    "unbounded-query-get-posts": {
      "id": "unbounded-query-get-posts",
      "level": "CRITICAL",
      "factory_default": "CRITICAL",
      "category": "performance",
      "description": "WP_Query with unbounded posts_per_page"
    },
    "n-plus-one-pattern": {
      "id": "n-plus-one-pattern",
      "level": "MEDIUM",
      "factory_default": "MEDIUM",
      "category": "performance",
      "description": "Potential N+1 pattern (get_post_meta in loop)"
    },
    "deprecated-function": {
      "id": "deprecated-function",
      "level": "MEDIUM",
      "factory_default": "MEDIUM",
      "category": "maintenance",
      "description": "Using deprecated WordPress function"
    }
  }
}
```

**Phase 2: How Users Customize**

```bash
# Step 1: Copy shipped config to your project
cp ./dist/config/severity-levels.json ./my-severity-config.json

# Step 2: Edit the copy (change "level" field only)
# Change deprecated-function from MEDIUM to LOW:
# "deprecated-function": {
#   "level": "LOW",           <- Edit this
#   "factory_default": "MEDIUM" <- Leave this for reference

# Step 3: Run scanner with explicit config path
./dist/bin/check-performance.sh --paths . --severity-config ./my-severity-config.json

# Step 4: If you break it, check factory_default in the file or delete it
# Without --severity-config, the tool uses /dist/config/severity-levels.json
```

**How It Works in the Script:**

```bash
# 1. Load shipped defaults from /dist/config/severity-levels.json
load_severity_defaults

# 2. If --severity-config provided, load and merge overrides
if [ -n "$SEVERITY_CONFIG_ARG" ]; then
  load_custom_severity_config "$SEVERITY_CONFIG_ARG"
fi

# 3. Get severity for any check (custom overrides shipped)
get_severity() {
  local check_id="$1"
  echo "${SEVERITY_CUSTOM[$check_id]:-${SEVERITY_SHIPPED[$check_id]}}"
}
```

**Why This Works:**
- ✅ **Zero complexity** - Just JSON + array lookup, no auto-discovery logic
- ✅ **Explicit over implicit** - Users must pass `--severity-config`, no magic file locations
- ✅ **Self-documenting** - Factory defaults live in the same file as reference
- ✅ **Version controllable** - Commit custom config to repo for team alignment
- ✅ **Low risk** - Users can always check `factory_default` or delete custom config
- ✅ **Simple fallback** - No config arg = use shipped defaults in `/dist/config/`
- ✅ **Already integrated** - Script already uses `jq` for JSON parsing

### Data Model (Minimal)

```bash
# Two associative arrays in the script:
declare -A SEVERITY_SHIPPED   # Factory defaults from /dist/config/severity-levels.json
declare -A SEVERITY_CUSTOM    # User overrides from --severity-config (if provided)

# Load shipped defaults from JSON
load_severity_defaults() {
  local config_file="$SCRIPT_DIR/../config/severity-levels.json"
  # Parse JSON with jq and populate SEVERITY_SHIPPED array
  while IFS="=" read -r key value; do
    SEVERITY_SHIPPED["$key"]="$value"
  done < <(jq -r '.severity_levels | to_entries[] | "\(.key)=\(.value.level)"' "$config_file")
}

# Load custom overrides from user config (only if --severity-config provided)
load_custom_severity_config() {
  local config_file="$1"
  # Parse JSON with jq and populate SEVERITY_CUSTOM array
  while IFS="=" read -r key value; do
    SEVERITY_CUSTOM["$key"]="$value"
  done < <(jq -r '.severity_levels | to_entries[] | "\(.key)=\(.value.level)"' "$config_file")
}

# Get final severity (custom overrides shipped)
get_severity() {
  local check_id="$1"
  echo "${SEVERITY_CUSTOM[$check_id]:-${SEVERITY_SHIPPED[$check_id]}}"
}
```

### Quickest Win: 3-Day Sprint

**Day 1**: Extract hardcoded severity levels from `check-performance.sh` into `/dist/config/severity-levels.json`
- Identify all 15+ checks and their current hardcoded levels
- Create JSON structure with factory defaults
- Add metadata (version, last_updated)

STATUS: COMPLETED

**Day 2**: Add `load_custom_severity_config()` + `get_severity()` helpers in `check-performance.sh`
- Parse JSON config file with jq (already used elsewhere in script)
- Merge user overrides into shipped defaults
- Update all check output lines to call `get_severity()` instead of hardcoding `[CRITICAL]`
- Add `--severity-config <path>` CLI option (explicit path only, no auto-discovery)

STATUS: COMPLETED

**Day 3**: Testing + documentation
- Test with custom config passed via `--severity-config`
- Test fallback to shipped defaults when no config provided
- Update README with usage examples
- Add validation (warn if invalid severity level in config)

STATUS: NOT STARTED

### Example Output (After MVP)

**TEXT REPORT:**
```
WP Code Check v1.0.59

Project: My Plugin v2.1.0 [plugin]
Scanning paths: .
Severity config: ./my-severity-config.json (2 customizations active)

━━━ CRITICAL CHECKS (will fail build) ━━━

▸ REST endpoints without pagination [CRITICAL]
  ✗ FAILED
  ./includes/api.php:42: register_rest_route()

▸ Unbounded queries [CRITICAL]
  ✗ FAILED
  ./admin/list-users.php:15: posts_per_page => -1

━━━ HIGH CHECKS ━━━

▸ AJAX missing nonce validation [HIGH → CRITICAL]
  ✗ FAILED
  ./assets/js/admin.js:78: jQuery.post('/wp-admin/admin-ajax.php')
  Note: Severity customized (factory: CRITICAL, custom: HIGH)

━━━ MEDIUM CHECKS ━━━

▸ Using deprecated functions [MEDIUM → LOW]
  ✓ PASSED
  ./includes/legacy.php:92: wp_make_content_safe()
  Note: Severity customized (factory: MEDIUM, custom: LOW)

━━━ SUMMARY ━━━
Errors:   2 (CRITICAL checks)
Warnings: 1 (HIGH checks)

⚠️  Severity customizations applied (2/15 checks):
   - wp-ajax-missing-nonce: CRITICAL → HIGH
   - deprecated-function: MEDIUM → LOW
```

**JSON REPORT:**
```json
{
  "metadata": {
    "version": "1.0.59",
    "project": "My Plugin",
    "type": "plugin",
    "scan_time": "2025-12-31T15:30:45Z",
    "severity_config": "./my-severity-config.json",
    "severity_customizations": {
      "wp-ajax-missing-nonce": {
        "factory_default": "CRITICAL",
        "custom_level": "HIGH",
        "reason": "User override in project config"
      },
      "deprecated-function": {
        "factory_default": "MEDIUM",
        "custom_level": "LOW",
        "reason": "User override in project config"
      }
    }
  },
  "findings": [
    {
      "id": "unbounded-rest-endpoint",
      "severity": "CRITICAL",
      "severity_customized": false,
      "file": "./includes/api.php",
      "line": 42,
      "code": "register_rest_route()"
    },
    {
      "id": "wp-ajax-missing-nonce",
      "severity": "HIGH",
      "severity_customized": true,
      "factory_default": "CRITICAL",
      "file": "./assets/js/admin.js",
      "line": 78,
      "code": "jQuery.post('/wp-admin/admin-ajax.php')"
    }
  ]
}
```

**HTML REPORT:**
```html
<div class="severity-customizations-banner">
  <h3>⚠️ Severity Customizations Active</h3>
  <p>This report uses custom severity levels. 2 out of 15 checks have been customized:</p>
  <table>
    <tr>
      <th>Check</th>
      <th>Factory Default</th>
      <th>Custom Level</th>
    </tr>
    <tr>
      <td>AJAX missing nonce</td>
      <td><span class="badge critical">CRITICAL</span></td>
      <td><span class="badge high">HIGH</span></td>
    </tr>
    <tr>
      <td>Deprecated functions</td>
      <td><span class="badge medium">MEDIUM</span></td>
      <td><span class="badge low">LOW</span></td>
    </tr>
  </table>
  <p><strong>Config file:</strong> ./my-severity-config.json</p>
  <p><em>To restore factory defaults, omit --severity-config or check "factory_default" values in the config file.</em></p>
</div>

<!-- Each finding shows if severity was customized -->
<div class="finding">
  <h4>REST endpoints without pagination <span class="badge critical">CRITICAL</span></h4>
  <p>File: ./includes/api.php:42</p>
  <p><code>register_rest_route()</code></p>
  <!-- No custom notice for this one -->
</div>

<div class="finding">
  <h4>AJAX missing nonce <span class="badge high">HIGH</span></h4>
  <p>File: ./assets/js/admin.js:78</p>
  <p><code>jQuery.post('/wp-admin/admin-ajax.php')</code></p>
  <div class="custom-severity-notice">
    <strong>Note:</strong> Severity customized for this rule
    <br/>Factory default: <span class="badge critical">CRITICAL</span> → Custom: <span class="badge high">HIGH</span>
  </div>
</div>
```

### Rules for Users

1. **How to customize**:
   - Copy shipped `/dist/config/severity-levels.json` to your project
   - Edit the copy (change `"level"` field, leave `"factory_default"` for reference)
   - Pass explicit path: `./dist/bin/check-performance.sh --paths . --severity-config ./my-config.json`

2. **Restore to factory defaults**:
   - Check `"factory_default"` in your config file to see the original value
   - Delete your custom config and omit `--severity-config` to use shipped defaults
   - Or manually change `"level"` back to match `"factory_default"`

3. **Version control** (recommended):
   - Commit your custom config to repo for team alignment
   - All developers use: `--severity-config ./team-severity.json`
   - CI/CD uses the same config for consistent builds

### Config File Locations (Simplified)

1. **`--severity-config <path>`** - Explicit path to custom config (user provides)
2. **`/dist/config/severity-levels.json`** - Factory defaults (always used as fallback)

**No auto-discovery.** No searching project root or home directory. Explicit is better than implicit.

---

## 🎯 Complexity Reductions (v1.1 Simplification)

### ❌ **REMOVED: Multi-Location Config Discovery**

**Before (v1.0):**
```bash
# Script searched 4 locations in priority order:
1. --severity-config <path>
2. ./.wp-code-check-severity.json (project root)
3. ~/.wp-code-check-severity.json (user home)
4. /dist/config/severity-levels.json (fallback)
```

**After (v1.1 - Simplified):**
```bash
# Script only uses 2 locations:
1. --severity-config <path> (explicit, user must provide)
2. /dist/config/severity-levels.json (fallback)
```

**Why?**
- ✅ **Eliminates file discovery logic** - No need to check if files exist in multiple locations
- ✅ **Explicit over implicit** - Users know exactly which config is being used
- ✅ **Reduces debugging complexity** - No "which config file is active?" confusion
- ✅ **Factory defaults always visible** - Shipped config in `/dist/config/` is the source of truth
- ✅ **Simpler testing** - Only 2 code paths instead of 4

### ✅ **KEPT: Factory Defaults in Custom Config**

Users still copy `/dist/config/severity-levels.json` and edit it. The `"factory_default"` field remains in the file as a reference, so users can always see what the original value was.

### 📝 **User Workflow (Simplified)**

```bash
# 1. Copy factory config
cp ./dist/config/severity-levels.json ./my-team-config.json

# 2. Edit the copy
vim ./my-team-config.json  # Change "level" fields

# 3. Use it explicitly
./dist/bin/check-performance.sh --paths . --severity-config ./my-team-config.json

# 4. Commit to repo for team alignment
git add my-team-config.json
git commit -m "Add team severity customizations"
```

**No magic. No auto-discovery. Just explicit paths.**

---

### ✅ **KEPT: Simple JSON Structure**

The JSON config structure remains minimal and self-documenting:

```json
{
  "_metadata": { "version": "1.0.59", ... },
  "severity_levels": {
    "rule-id": {
      "id": "rule-id",
      "level": "HIGH",              // ← User edits this
      "factory_default": "CRITICAL", // ← Reference (don't edit)
      "category": "security",
      "description": "..."
    }
  }
}
```

**Why this structure?**
- ✅ **Self-documenting** - Factory defaults visible in same file
- ✅ **Easy to edit** - Just change `"level"` field
- ✅ **Easy to parse** - Simple `jq` queries
- ✅ **Version controllable** - JSON diffs are readable
- ✅ **No nested complexity** - Flat structure, no inheritance or overrides

**What we're NOT doing:**
- ❌ No YAML (adds dependency, more complex parsing)
- ❌ No INI files (harder to parse in bash)
- ❌ No environment variables (not version controllable)
- ❌ No database storage (overkill for simple config)

### Implementation Checklist

**Phase 1 Work:**
- [ ] Extract all hardcoded severity levels from `check-performance.sh` (grep for `\[CRITICAL\]`, `\[HIGH\]`, `\[MEDIUM\]`, `\[LOW\]`)
- [ ] Create `/dist/config/severity-levels.json` with all checks + factory defaults
- [ ] Map check patterns to rule IDs (e.g., `wp-ajax-missing-nonce`, `unbounded-rest-endpoint`)
- [ ] Document each check with category (security, performance, maintenance)

**Phase 2 Work:**
- [ ] Add `load_severity_defaults()` function to load `/dist/config/severity-levels.json`
- [ ] Add `load_custom_severity_config()` to parse user config (use jq)
- [ ] Add `get_severity(rule_id)` lookup function (custom overrides shipped)
- [ ] Track which checks are customized (compare custom vs shipped arrays)
- [ ] Update all check output lines to use `get_severity()` instead of hardcoded levels
- [ ] Show customization notice in text report header (e.g., "2 customizations active")
- [ ] Add inline notes for customized findings (e.g., "CRITICAL → HIGH")
- [ ] Add `--severity-config <path>` CLI option (explicit path only, no auto-discovery)

**Phase 3 Work:**
- [ ] Unit tests: verify config loading, merging, priority order
- [ ] Integration tests: run with custom config, verify output includes customization notices
- [ ] Text report: show banner header with active customizations + inline notes per finding
- [ ] JSON report: add `severity_customizations` metadata + `severity_customized` flag per finding
- [ ] HTML report: add customizations banner table + highlight customized findings with badges
- [ ] Error handling: warn if config missing, invalid JSON, unknown rule IDs

## Future Extensions (Not MVP)

- ☐ Filter reports by severity threshold: `--min-severity HIGH` (only show HIGH, CRITICAL)
- ☐ Fail CI only on specific severities: `--fail-on CRITICAL` (ignore MEDIUM warnings)
- ☐ Team presets in config: `"team_override": { "security": {...}, "devs": {...} }`
- ☐ Per-rule comments in config: `"note": "This team ignores deprecated warnings"`
- ☐ HTML dashboard showing custom vs factory defaults

## Why Not Build This?

❌ **Weighted scoring systems**: Overkill for v1, simple levels are enough
❌ **Per-file rules**: Not needed yet—most teams apply same rules project-wide
❌ **Auto-detection**: Not our job—user decides what matters to them
❌ **Database storage**: JSON files are simpler, version-controllable, mergeable
❌ **UI/CLI filters**: Start with config file, add filter options later if needed