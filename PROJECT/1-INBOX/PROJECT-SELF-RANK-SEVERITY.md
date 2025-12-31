# Severity Ranking MVP v1

**Context**: WP Code Check is a CLI scanner that detects 15+ WordPress performance/security antipatterns. It already ships hardcoded checks with fixed severity levels (CRITICAL, HIGH, MEDIUM, LOW). This feature allows teams to customize severity rankings per-project to reduce noise and focus on what matters to them.

## Problem
- **Developer A** thinks missing nonce checks are CRITICAL (security team)
- **Developer B** downranks them to MEDIUM (code review overhead)
- **Developer C** wants `deprecated-function` as LOW (legacy codebase)

Currently: All teams get the same severity levels. No customization = noise.

## The MVP Approach: Shipped Config + Local Override

**Core Concept**: Ship a `/dist/config/severity-levels.json` with the project. Users copy it locally, customize it, and push to CI/CD. Factory defaults live in the file as an escape hatch.

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
# Step 1: Copy shipped config to project root or ~/.wp-code-check.json
cp ./dist/config/severity-levels.json ./.wp-code-check-severity.json

# Step 2: Edit locally (change "level" field only)
# Change deprecated-function from MEDIUM to LOW:
# "deprecated-function": {
#   "level": "LOW",           <- Edit this
#   "factory_default": "MEDIUM" <- Leave this for reference

# Step 3: Run scanner with custom config
./dist/bin/check-performance.sh --paths . --severity-config ./.wp-code-check-severity.json

# Step 4: If you break it, just check factory_default in the file
# Or delete the file to use shipped defaults
```

**How It Works in the Script:**

```bash
# 1. Load shipped defaults
load_severity_defaults()

# 2. Load user config if it exists (overrides shipped)
if [ -f "$SEVERITY_CONFIG_FILE" ]; then
  CUSTOM_LEVELS=$(load_custom_severity_config "$SEVERITY_CONFIG_FILE")
fi

# 3. Resolve final severity for display
get_severity_for_check() {
  local check_id="$1"
  # Return custom > shipped
  echo "${CUSTOM_LEVELS[$check_id]:-${SHIPPED_LEVELS[$check_id]}}"
}
```

**Why This Works:**
- ✅ Zero complexity (just JSON + array lookup)
- ✅ Shipped by default (lives in `/dist/config/`)
- ✅ Self-documenting (factory defaults in same file)
- ✅ Version controllable (commit to repo for team alignment)
- ✅ Low risk (users can always reference or delete file to reset)
- ✅ Multi-location support (project-level, user-level, explicit path)
- ✅ Integrates seamlessly with existing bash script (jq already used)

### Data Model (Minimal)

```bash
# In the script, after loading config:
declare -A SEVERITY_OVERRIDES  # Custom severities loaded from file

# Load shipped defaults into associative array
load_severity_defaults() {
  SEVERITY_SHIPPED["wp-ajax-missing-nonce"]="HIGH"
  SEVERITY_SHIPPED["unbounded-rest-endpoint"]="CRITICAL"
  SEVERITY_SHIPPED["unbounded-query-get-posts"]="CRITICAL"
  SEVERITY_SHIPPED["n-plus-one-pattern"]="MEDIUM"
  SEVERITY_SHIPPED["deprecated-function"]="MEDIUM"
}

# Load custom overrides from user config file (if exists)
load_custom_severity_config() {
  local config_file="$1"
  # Parse JSON and populate SEVERITY_OVERRIDES array
  # Use jq or simple grep/sed for portability
}

# Get final severity (custom > shipped)
get_severity() {
  local check_id="$1"
  echo "${SEVERITY_OVERRIDES[$check_id]:-${SEVERITY_SHIPPED[$check_id]}}"
}
```

### Quickest Win: 3-Day Sprint

**Day 1**: Extract hardcoded severity levels from `check-performance.sh` into `/dist/config/severity-levels.json`
- Identify all 15+ checks and their current hardcoded levels
- Create JSON structure with factory defaults
- Add metadata (version, last_updated)

**Day 2**: Add `load_custom_severity_config()` + `get_severity()` helpers in `check-performance.sh`
- Parse JSON config file with jq (already used elsewhere in script)
- Merge user overrides into shipped defaults
- Update all check output lines to call `get_severity()` instead of hardcoding `[CRITICAL]`
- Add `--severity-config` CLI option

**Day 3**: Testing + documentation
- Test with custom config in different locations (project root, home dir)
- Verify CLI option works
- Update README with usage examples
- Add validation (warn if invalid severity level in config)

### Example Output (After MVP)

**TEXT REPORT:**
```
WP Code Check v1.0.59

Project: My Plugin v2.1.0 [plugin]
Scanning paths: .
Severity config: ./.wp-code-check-severity.json (2 customizations active)

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
    "severity_config": "./.wp-code-check-severity.json",
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
  <p><strong>Config file:</strong> ./.wp-code-check-severity.json</p>
  <button>Restore Factory Defaults</button>
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

1. **Where to customize**:
   - Copy shipped `/dist/config/severity-levels.json` to project root: `./.wp-code-check-severity.json`
   - Or place in home directory: `~/.wp-code-check-severity.json`
   - Pass explicit path: `./dist/bin/check-performance.sh --paths . --severity-config ./custom-levels.json`

2. **Restore to factory defaults**:
   - Check `"factory_default"` in the file to see what the original was
   - Delete your local copy to revert to shipped defaults
   - Or manually change `"level"` back to match `"factory_default"`

3. **Version control** (optional):
   - Commit `.wp-code-check-severity.json` to repo for team alignment
   - All developers on team get same severity customizations
   - CI/CD automatically uses the project's custom config

### Config File Locations (Priority Order)

1. `--severity-config <path>` (explicit argument, highest priority)
2. `./.wp-code-check-severity.json` (project root)
3. `~/.wp-code-check-severity.json` (user home)
4. Shipped defaults in `/dist/config/severity-levels.json` (fallback)

### Implementation Checklist

**Phase 1 Work:**
- [ ] Extract all hardcoded severity levels from `check-performance.sh` (grep for `\[CRITICAL\]`, `\[HIGH\]`, `\[MEDIUM\]`, `\[LOW\]`)
- [ ] Create `/dist/config/severity-levels.json` with all checks + factory defaults
- [ ] Map check patterns to rule IDs (e.g., `wp-ajax-missing-nonce`, `unbounded-rest-endpoint`)
- [ ] Document each check with category (security, performance, maintenance)

**Phase 2 Work:**
- [ ] Add `load_severity_defaults()` function to setup shipped levels
- [ ] Add `load_custom_severity_config()` to parse JSON file (use jq)
- [ ] Add `get_severity(rule_id)` lookup function
- [ ] Track which checks are customized (array of rule_ids with custom levels)
- [ ] Update all check output lines to use `get_severity()` instead of hardcoded levels
- [ ] Show customization notice in text report header (e.g., "2 customizations active")
- [ ] Add inline notes for customized findings (e.g., "CRITICAL → HIGH")
- [ ] Add `--severity-config <path>` CLI option
- [ ] Support config file discovery (project root, home dir)

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