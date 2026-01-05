# PROJECT: Node.js / JavaScript Pattern Support

**Created:** 2026-01-05
**Status:** ✅ Phase 1 & Phase 2 COMPLETE
**Priority:** Medium
**Target Version:** v1.0.80 (Phase 1), v1.0.81 (Phase 2), v1.1.0+ (remaining phases)

---

## 📋 Table of Contents (Checklist)

### 🔄 CONTINUOUS: Documentation & Testing (Runs Parallel to All Phases)
> **Rationale:** Docs/testing are enablers, not afterthoughts. Each phase ships with fixtures, docs, and CI examples.

- [x] Create `dist/tests/fixtures/headless/` directory structure ✅
- [ ] Update dist/README.md incrementally as patterns are added
- [x] Create HOWTO-JAVASCRIPT-PATTERNS.md guide (start Phase 1, expand each phase) ✅
- [ ] Add CI/CD examples for JavaScript-heavy WordPress projects
- [ ] Benchmark performance on large JS codebases (50k+ LOC) — after Phase 2

---

### Phase 1: Headless WordPress Patterns ⭐ COMPLETE ✅
- [x] Add REST API client patterns (fetch/axios error handling, missing auth headers) ✅
- [x] Add environment variable exposure patterns (API keys in client bundles) ✅
- [x] Add Next.js/Nuxt data fetching patterns (missing revalidation, stale data) ✅
- [x] Add WPGraphQL/Apollo client patterns (missing error boundaries, cache issues) ✅
- [x] Add CORS and authentication patterns (credentials mode, token handling) ✅
- [x] Create headless test fixtures in `dist/tests/fixtures/headless/` ✅
- [x] Document headless patterns in HOWTO guide ✅

**Phase 1 Implementation Summary (v1.0.80):**
| Pattern ID | Severity | Description |
|------------|----------|-------------|
| `headless-api-key-exposure` | CRITICAL | API keys/secrets exposed in client bundles |
| `headless-hardcoded-wordpress-url` | MEDIUM | Hardcoded WordPress API URLs |
| `headless-graphql-no-error-handling` | HIGH | useQuery/useMutation without error handling |
| `headless-nextjs-missing-revalidate` | MEDIUM | getStaticProps without ISR revalidate |

**Files Created:**
- `dist/patterns/headless/api-key-exposure.json`
- `dist/patterns/headless/fetch-no-error-handling.json`
- `dist/patterns/headless/missing-auth-headers.json`
- `dist/patterns/headless/nextjs-missing-revalidate.json`
- `dist/patterns/headless/graphql-no-error-handling.json`
- `dist/patterns/headless/hardcoded-wordpress-url.json`
- `dist/tests/fixtures/headless/fetch-antipatterns.js`
- `dist/tests/fixtures/headless/nextjs-antipatterns.js`
- `dist/tests/fixtures/headless/graphql-antipatterns.js`
- `dist/HOWTO-JAVASCRIPT-PATTERNS.md` (documentation guide)

### Phase 2: JS/TS Scanning + DRY/Clone Detection ⭐ COMPLETE ✅
> **Rationale:** DRY/clone detection early = reuse patterns across phases, catch duplicates in fixtures, reduce noise.

**Track A: Expand Existing JS/TS Scanning**
- [x] Audit current JS/TS patterns (HCC-001, HCC-002, HCC-008, SPO-001) ✅
- [x] Add Node.js-specific security patterns (eval, child_process, fs operations) ✅
- [x] Add common JavaScript anti-patterns (callback hell, promise rejection handling) ✅
- [x] Create JS/TS test fixtures in `dist/tests/fixtures/js/` ✅

**Track B: DRY & Clone Detection for JS/TS**
- [x] Extend duplicate-functions.json to support JS/TS syntax ✅
- [x] Add JavaScript-specific magic string detection ✅
- [ ] Add cross-language duplicate detection (PHP ↔ JS) — Deferred to Phase 4
- [x] Use clone detection to validate no duplicate fixtures across phases ✅

**Phase 2 Implementation Summary (v1.0.81):**
| Pattern ID | Severity | Description |
|------------|----------|-------------|
| `njs-001-eval-code-execution` | CRITICAL | Dangerous eval(), Function(), vm.runInContext() |
| `njs-002-command-injection` | CRITICAL | child_process.exec() with user input |
| `njs-003-path-traversal` | HIGH | fs.readFile/writeFile with unsanitized paths |
| `njs-004-unhandled-promise` | HIGH | Promise chains without .catch() |
| `duplicate-storage-keys` | LOW | localStorage/sessionStorage keys across files |

**Files Created:**
- `dist/patterns/nodejs/eval-code-execution.json`
- `dist/patterns/nodejs/command-injection.json`
- `dist/patterns/nodejs/path-traversal.json`
- `dist/patterns/nodejs/unhandled-promise.json`
- `dist/patterns/js/duplicate-storage-keys.json`
- `dist/tests/fixtures/js/security-antipatterns.js`
- `dist/tests/fixtures/js/promise-antipatterns.js`

**Scanner Changes:**
- Added "NODE.JS SECURITY CHECKS" section to scan output
- Updated `duplicate-functions.json` to v1.1.0 with JS/TS support
- Extended aggregated pattern processor to support file_patterns from JSON

### Phase 3: WordPress JavaScript Patterns (Classic)
- [ ] Add wp-scripts / @wordpress/scripts detection patterns
- [ ] Add Gutenberg block development patterns (deprecated APIs, security)
- [ ] Add jQuery anti-patterns (deprecated methods, direct DOM in React)
- [ ] Add WordPress REST API client patterns (nonce handling, error handling)

### Phase 4: Node.js Ecosystem Patterns
- [ ] Add package.json security patterns (outdated deps, missing lockfiles)
- [ ] Add npm/yarn audit integration (optional external tool)
- [ ] Add common Node.js performance patterns (sync fs, blocking event loop)
- [ ] Add Express/Koa security patterns (if applicable to WP tooling)

---

## 📊 Current State Analysis

### What Already Works (Updated v1.0.81)
The scanner supports JavaScript/TypeScript files for these patterns:

| Pattern ID | Files Scanned | Description |
|------------|---------------|-------------|
| `spo-001-debug-code` | `.php`, `.js`, `.jsx`, `.ts`, `.tsx` | Debug code in production |
| `hcc-001-localstorage-exposure` | `.js`, `.jsx`, `.ts`, `.tsx` | Sensitive data in localStorage |
| `hcc-002-client-serialization` | `.js`, `.jsx`, `.ts`, `.tsx` | JSON.stringify to client storage |
| `hcc-008-unsafe-regexp` | `.js`, `.jsx`, `.ts`, `.tsx`, `.php` | User input in RegExp |
| `ajax-polling-unbounded` | `.js` | setInterval without cleanup |
| `hcc-005-expensive-polling` | `.js`, `.php` | Expensive WP functions in polling |
| **`headless-api-key-exposure`** | `.js`, `.jsx`, `.ts`, `.tsx` | API keys in client bundles ✨ |
| **`headless-hardcoded-wordpress-url`** | `.js`, `.jsx`, `.ts`, `.tsx` | Hardcoded WordPress API URLs ✨ |
| **`headless-graphql-no-error-handling`** | `.js`, `.jsx`, `.ts`, `.tsx` | useQuery without error handling ✨ |
| **`headless-nextjs-missing-revalidate`** | `.js`, `.jsx`, `.ts`, `.tsx` | getStaticProps without ISR ✨ |
| **`njs-001-eval-code-execution`** | `.js`, `.jsx`, `.ts`, `.tsx` | Dangerous eval() usage ✨ |
| **`njs-002-command-injection`** | `.js`, `.jsx`, `.ts`, `.tsx` | child_process.exec injection ✨ |
| **`njs-003-path-traversal`** | `.js`, `.jsx`, `.ts`, `.tsx` | fs operations path traversal ✨ |
| **`njs-004-unhandled-promise`** | `.js`, `.jsx`, `.ts`, `.tsx` | Promise without .catch() ✨ |
| **`duplicate-functions`** | `.php`, `.js`, `.jsx`, `.ts`, `.tsx` | Clone detection (v1.1.0) ✨ |
| **`duplicate-storage-keys`** | `.js`, `.jsx`, `.ts`, `.tsx` | localStorage/sessionStorage keys ✨ |

### Gaps Remaining (Phases 3-4)
From AUDIT-COPILOT-SONNET.md and codebase analysis:

1. ~~**Single-language limitation** - DRY/clone detection is PHP-only~~ ✅ FIXED in v1.0.81
2. **No Node.js ecosystem patterns** - npm/yarn, package.json, lockfiles
3. **No WordPress JS build tool patterns** - wp-scripts, webpack configs
4. **No Gutenberg-specific patterns** - Block API deprecations, security
5. ~~**No async/Promise patterns** - Unhandled rejections, callback hell~~ ✅ FIXED in v1.0.81

---

## 🎯 High-Value Pattern Opportunities

### Tier 1: Headless WordPress (High Priority) ⭐ COMPLETE ✅
```
✅ fetch/axios without error handling [HIGH] — headless-fetch-no-error-handling
✅ API keys exposed in client-side code [CRITICAL] — headless-api-key-exposure
✅ Missing authentication headers [HIGH] — headless-missing-auth-headers
✅ Hardcoded API URLs (not environment variables) [MEDIUM] — headless-hardcoded-wordpress-url
✅ Missing revalidate/ISR in Next.js [MEDIUM] — headless-nextjs-missing-revalidate
✅ GraphQL queries without error boundaries [HIGH] — headless-graphql-no-error-handling
- Credentials mode missing for CORS [HIGH] — Partial (covered in fetch patterns)
```

### Tier 2: General JS Security (Critical/High) ⭐ MOSTLY COMPLETE ✅
```
✅ eval() usage in JavaScript [CRITICAL] — njs-001-eval-code-execution
✅ child_process.exec with user input [CRITICAL] — njs-002-command-injection
✅ fs.readFile/writeFile with user-controlled paths [HIGH] — njs-003-path-traversal
- innerHTML assignment (XSS vectors) [HIGH] — Phase 3
- document.write usage [HIGH] — Phase 3
- postMessage without origin validation [HIGH] — Phase 3
```

### Tier 3: Performance (Medium/High)
```
- Synchronous fs operations (fs.readFileSync in hot paths) [HIGH] — Phase 4
✅ Missing error handling in async/await [MEDIUM] — njs-004-unhandled-promise
- Large synchronous JSON.parse [MEDIUM] — Phase 4
- Blocking event loop patterns [HIGH] — Phase 4
- Memory leak patterns (event listeners not removed) [MEDIUM] — Phase 4
```

### Tier 4: WordPress JS Specific (Medium)
```
- Deprecated jQuery methods in WP context [MEDIUM]
- wp.ajax without nonce [HIGH]
- Gutenberg deprecated APIs [MEDIUM]
- Direct DOM manipulation in React blocks [MEDIUM]
- Missing i18n wrappers (__(), _n()) [LOW]
```

---

## 🔧 Implementation Approach

### Pattern File Structure
```
dist/patterns/
├── core/
│   ├── security.json          # Existing
│   └── performance.json       # Existing
├── js/                        # NEW - JavaScript patterns
│   ├── security.json          # eval, XSS, injection
│   ├── performance.json       # sync ops, memory leaks
│   └── wordpress.json         # WP-specific JS patterns
├── dry/
│   └── duplicate-functions.json  # Extend for JS/TS
```

### Scanner Modifications
1. Add `--language` flag to filter by file type (optional)
2. Extend `GREP_INCLUDE` defaults to include JS/TS for more patterns
3. Add JavaScript function extraction for clone detection

---

## 📚 References

### Source Documents Consolidated
- **AUDIT-COPILOT-SONNET.md** - "Single-language - PHP-only" identified as weakness
- **KISS-PQS-FINDINGS-RULES.md** - HCC patterns already scan JS/TS files
- **CHANGELOG.md** - SPO-001 scans `.php`, `.js`, `.jsx`, `.ts`, `.tsx`

### External Resources
- [WordPress JavaScript Coding Standards](https://developer.wordpress.org/coding-standards/wordpress-coding-standards/javascript/)
- [ESLint Plugin WordPress](https://www.npmjs.com/package/eslint-plugin-wordpress)
- [Node.js Security Best Practices](https://nodejs.org/en/docs/guides/security/)

---

## 📝 Notes

**Why Medium Priority:**
- Core PHP scanning is the primary use case for WordPress plugins/themes
- JS/TS support exists for critical security patterns
- Full Node.js support is additive, not blocking

**Dependencies:**
- None - can leverage existing grep-based infrastructure
- Optional: ESLint integration for advanced static analysis (Phase 4+)

**Risks:**
- JavaScript syntax variety (CommonJS, ESM, TypeScript) may require multiple patterns
- Performance impact on large node_modules directories (already excluded)

