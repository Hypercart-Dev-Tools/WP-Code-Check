# Proposal: Shell User Experience Improvements

**Created:** 2026-01-14  
**Status:** Proposal  
**Priority:** Medium  
**Target Audience:** Terminal/shell users who don't use VS Code agents or MCP

---

## Executive Summary

**Problem:** WP Code Check has excellent AI agent integration (MCP, templates, AI triage), but shell-only users face friction:
- Long command paths (`./dist/bin/check-performance.sh --paths ...`)
- No quick setup script
- Manual alias configuration
- No shell completion
- Limited discoverability of features

**Solution:** Create shell-first onboarding and productivity tools to match the polish of AI agent workflows.

---

## Current State Analysis

### ✅ What's Already Good for Shell Users

1. **Zero dependencies** - Bash + grep only
2. **Alias suggestion** in `dist/README.md` (lines 86-99)
3. **Clear documentation** - Comprehensive command reference
4. **Fast execution** - Scans complete in seconds
5. **JSON output** - Machine-readable for scripting
6. **Baseline support** - Manage technical debt
7. **Template system** - Reusable configurations

### ❌ What's Missing for Shell Users

1. **No installation script** - Users manually clone and configure
2. **No shell completion** - Tab completion for flags/options
3. **No interactive setup** - Must manually edit `.bashrc`/`.zshrc`
4. **No quick-start wizard** - Overwhelming for first-time users
5. **No shell integration helpers** - No `wp-check init` command
6. **No update mechanism** - Manual `git pull` required
7. **No shell-specific docs** - AI agent docs dominate README

---

## Recent Improvements (Context)

### What Was Added for AI Agents (2025-12-31 to 2026-01-14)

- ✅ MCP server for Claude Desktop/Cline
- ✅ AI triage tool (`ai-triage.py`)
- ✅ Template auto-completion for AI agents
- ✅ `_AI_INSTRUCTIONS.md` and `_AI_FAQS.md`
- ✅ Comprehensive AI workflow documentation

### What Was Added for Shell Users (Same Period)

- ✅ Bash 3.2 compatibility fixes (macOS)
- ✅ Shell syntax improvements (removed `local` keywords)
- ✅ Shared helper libraries (`dist/bin/lib/`)
- ✅ Improved error messages
- ⚠️ **Alias suggestion** (documentation only, not automated)

**Gap:** AI agents got automated workflows, shell users got manual instructions.

---

## Proposed Improvements

### 1. Installation Script (`install.sh`)

**Purpose:** One-command setup for shell users

**Features:**
```bash
# Quick install
curl -fsSL https://raw.githubusercontent.com/Hypercart-Dev-Tools/WP-Code-Check/main/install.sh | bash

# Or manual
git clone https://github.com/Hypercart-Dev-Tools/WP-Code-Check.git
cd WP-Code-Check
./install.sh
```

**What it does:**
- ✅ Detects shell (bash/zsh/fish)
- ✅ Offers to add alias to `.bashrc`/`.zshrc`
- ✅ Suggests installation location (`~/dev/wp-code-check` or custom)
- ✅ Makes scripts executable
- ✅ Runs test scan to verify installation
- ✅ Shows quick start examples

**Implementation:**
```bash
#!/usr/bin/env bash
# dist/install.sh

# Detect shell
SHELL_RC=""
if [ -n "$ZSH_VERSION" ]; then
  SHELL_RC="$HOME/.zshrc"
elif [ -n "$BASH_VERSION" ]; then
  SHELL_RC="$HOME/.bashrc"
fi

# Get installation directory
INSTALL_DIR=$(pwd)

# Offer to add alias
echo "Add alias to $SHELL_RC? (y/n)"
read -r response
if [[ "$response" =~ ^[Yy]$ ]]; then
  echo "" >> "$SHELL_RC"
  echo "# WP Code Check alias" >> "$SHELL_RC"
  echo "alias wp-check='$INSTALL_DIR/dist/bin/check-performance.sh --paths'" >> "$SHELL_RC"
  echo "✓ Alias added. Run: source $SHELL_RC"
fi

# Make scripts executable
chmod +x dist/bin/*.sh dist/bin/run

# Test installation
echo "Testing installation..."
./dist/bin/check-performance.sh --paths dist/tests/fixtures --format json > /dev/null
if [ $? -eq 0 ]; then
  echo "✓ Installation successful!"
else
  echo "✗ Installation test failed"
fi
```

---

### 2. Shell Completion (`wp-check-completion.bash`)

**Purpose:** Tab completion for flags and options

**Features:**
```bash
# After sourcing completion script
wp-check --<TAB>
# Shows: --paths --format --strict --verbose --baseline --help

wp-check --format <TAB>
# Shows: text json
```

**Implementation:**
```bash
# dist/bin/wp-check-completion.bash

_wp_check_completion() {
  local cur prev opts
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"
  
  opts="--paths --format --strict --verbose --no-log --baseline --generate-baseline --help"
  
  case "${prev}" in
    --format)
      COMPREPLY=( $(compgen -W "text json" -- ${cur}) )
      return 0
      ;;
    --paths|--baseline)
      COMPREPLY=( $(compgen -d -- ${cur}) )
      return 0
      ;;
    *)
      ;;
  esac
  
  COMPREPLY=( $(compgen -W "${opts}" -- ${cur}) )
  return 0
}

complete -F _wp_check_completion wp-check
```

---

### 3. Interactive Setup Wizard (`wp-check init`)

**Purpose:** Guided first-time setup

**Features:**
```bash
$ wp-check init

WP Code Check - Interactive Setup
==================================

[1/4] Where should we scan by default?
  1. Current directory (.)
  2. Specific path
  3. Ask every time
> 1

[2/4] What output format do you prefer?
  1. Text (human-readable)
  2. JSON (for CI/CD)
> 1

[3/4] Create a shell alias?
  Alias: wp-check
  Command: ~/dev/wp-code-check/dist/bin/check-performance.sh
> y

[4/4] Run a test scan?
> y

✓ Setup complete!

Quick start:
  wp-check ~/my-plugin
  wp-check . --strict
  wp-check --help
```

---

### 4. Update Command (`wp-check update`)

**Purpose:** Easy updates without manual git commands

**Features:**
```bash
$ wp-check update

Checking for updates...
Current version: 1.2.1
Latest version:  1.3.0

Changelog:
  - Added shell completion
  - Fixed baseline detection
  - Improved error messages

Update now? (y/n) > y

Updating...
✓ Updated to v1.3.0
```

**Implementation:**
```bash
# In check-performance.sh or separate script
if [ "$1" = "update" ]; then
  git fetch origin
  CURRENT=$(git describe --tags)
  LATEST=$(git describe --tags origin/main)
  
  if [ "$CURRENT" != "$LATEST" ]; then
    echo "Update available: $CURRENT → $LATEST"
    git pull origin main
  else
    echo "Already up to date ($CURRENT)"
  fi
  exit 0
fi
```

---

### 5. Shell-Specific Quick Start Guide

**Purpose:** Dedicated documentation for shell users

**File:** `SHELL-QUICKSTART.md`

**Contents:**
- Installation (one-liner)
- Alias setup
- Common workflows
- Shell completion
- Troubleshooting
- No mention of AI agents/MCP

---

### 6. Enhanced Help Output

**Current:**
```bash
$ ./dist/bin/check-performance.sh --help
# Shows basic usage
```

**Proposed:**
```bash
$ wp-check --help

WP Code Check v1.2.1 - WordPress Performance Analyzer

USAGE:
  wp-check [options]

COMMON WORKFLOWS:
  wp-check ~/my-plugin              # Quick scan
  wp-check . --strict               # Fail on warnings
  wp-check . --generate-baseline    # Create baseline
  wp-check . --format json          # CI/CD output

OPTIONS:
  --paths <dir>         Paths to scan (default: current directory)
  --format text|json    Output format (default: json)
  --strict              Fail on warnings
  --baseline <file>     Use custom baseline file
  --help                Show this help

EXAMPLES:
  # Scan current directory
  wp-check .
  
  # Scan multiple paths
  wp-check --paths "~/plugin1 ~/plugin2"
  
  # Generate baseline for legacy code
  wp-check . --generate-baseline
  
  # CI/CD integration
  wp-check . --format json --strict

DOCUMENTATION:
  User Guide:    dist/README.md
  Templates:     dist/HOWTO-TEMPLATES.md
  Changelog:     CHANGELOG.md

SUPPORT:
  Issues: https://github.com/Hypercart-Dev-Tools/WP-Code-Check/issues
  Docs:   https://wpcodecheck.com
```

---

## Implementation Priority

### Phase 1: Quick Wins (1-2 hours)

1. ✅ **Enhanced `--help` output** - Better examples and formatting
2. ✅ **`install.sh` script** - Automated alias setup
3. ✅ **`SHELL-QUICKSTART.md`** - Dedicated shell user docs

### Phase 2: Productivity (3-4 hours)

4. ✅ **Shell completion** - Bash/Zsh tab completion
5. ✅ **`wp-check update` command** - Easy updates
6. ✅ **Interactive wizard** - `wp-check init`

### Phase 3: Polish (2-3 hours)

7. ✅ **Shell integration tests** - Verify alias/completion work
8. ✅ **Update root README** - Add shell-first quick start
9. ✅ **Screencast/GIF** - Show shell workflow in action

---

## Success Metrics

**How we'll know this worked:**

1. **Reduced time-to-first-scan** - From 5 minutes to 30 seconds
2. **Increased shell user adoption** - Track GitHub stars/clones
3. **Fewer "how do I install" issues** - GitHub issue reduction
4. **Positive feedback** - User testimonials about ease of use
5. **Shell completion usage** - Track completion script downloads

---

## Comparison: Before vs. After

### Before (Current State)

```bash
# User journey
1. Clone repo manually
2. Read documentation
3. Find command path
4. Type long command: ./dist/bin/check-performance.sh --paths ~/plugin
5. Manually edit .bashrc to add alias
6. Source .bashrc
7. Remember all flags (no completion)
```

**Time to first scan:** ~5 minutes  
**Friction points:** 7

### After (Proposed)

```bash
# User journey
1. Run: curl -fsSL https://... | bash
2. Answer 4 setup questions
3. Type: wp-check ~/plugin
```

**Time to first scan:** ~30 seconds  
**Friction points:** 1

---

## Open Questions

1. **Should we create a `wp-check` wrapper script** instead of relying on aliases?
   - Pro: Works without shell config
   - Con: Adds another file to maintain

2. **Should shell completion be opt-in or auto-installed?**
   - Opt-in: Less intrusive
   - Auto: Better UX

3. **Should we support Fish shell?**
   - Bash/Zsh cover 95% of users
   - Fish requires different completion syntax

4. **Should `install.sh` modify shell config automatically?**
   - Auto: Faster setup
   - Manual: User control

---

## Next Steps

1. **Get feedback** on this proposal
2. **Prioritize features** (Phase 1 vs. Phase 2 vs. Phase 3)
3. **Create implementation tasks** in PROJECT/2-WORKING/
4. **Build Phase 1** (quick wins)
5. **Test with real shell users**
6. **Iterate based on feedback**

---

## Related Documents

- `dist/README.md` - Current user guide (has alias suggestion)
- `README.md` - Main README (AI-agent focused)
- `FAQS.md` - Installation FAQ
- `dist/TEMPLATES/_AI_INSTRUCTIONS.md` - AI agent workflow (for comparison)

---

**Proposal Status:** Ready for review  
**Estimated Effort:** 6-9 hours total (across 3 phases)  
**Impact:** High - Makes WP Code Check accessible to non-AI-agent users

