# HOWTO: JavaScript & TypeScript Pattern Detection

> **Version:** 1.0.80
> **Last Updated:** 2026-01-05

This guide covers JavaScript and TypeScript pattern detection in WP Code Check, with a focus on headless WordPress architectures (Next.js, Nuxt, Gatsby, etc.).

---

## 📋 Table of Contents

1. [Quick Start](#quick-start)
2. [Headless WordPress Patterns](#headless-wordpress-patterns)
3. [Pattern Reference](#pattern-reference)
4. [Framework-Specific Guidance](#framework-specific-guidance)
5. [Baseline Configuration](#baseline-configuration)
6. [Troubleshooting](#troubleshooting)

---

## Quick Start

### Scanning JavaScript/TypeScript Files

```bash
# Scan a Next.js project
./bin/check-performance.sh --paths ./my-nextjs-app/

# Scan specific directories
./bin/check-performance.sh --paths "./src ./pages ./components"

# JSON output for CI/CD
./bin/check-performance.sh --paths ./src --format json
```

### File Types Scanned

The scanner automatically includes these JavaScript/TypeScript file types:
- `.js` - JavaScript
- `.jsx` - React JSX
- `.ts` - TypeScript
- `.tsx` - React TypeScript

---

## Headless WordPress Patterns

These patterns detect common issues in decoupled WordPress frontends.

### HWP-001: API Key Exposure [CRITICAL]

**What it detects:** API keys, secrets, or tokens hardcoded in client-side JavaScript that will be exposed in browser bundles.

**Why it matters:** Any code in `.js`/`.ts` files shipped to browsers is visible to users via DevTools. Secrets in client bundles are compromised.

```javascript
// ❌ BAD: Hardcoded API key (exposed in browser)
const WORDPRESS_API_KEY = 'sk_live_abc123secret';

// ❌ BAD: Sensitive value in NEXT_PUBLIC_ (exposed to browser)
const token = process.env.NEXT_PUBLIC_SECRET_KEY;

// ✅ GOOD: Server-only environment variable
const token = process.env.WP_AUTH_TOKEN; // Not exposed to browser
```

**Fix:** Move secrets to server-only environment variables (without `NEXT_PUBLIC_`, `NUXT_PUBLIC_`, or `VITE_` prefixes).

---

### HWP-002: Hardcoded WordPress URL [MEDIUM]

**What it detects:** Full WordPress URLs hardcoded instead of using environment variables.

**Why it matters:** Hardcoded URLs break deployments across environments (dev, staging, production).

```javascript
// ❌ BAD: Hardcoded URL
fetch('https://mysite.com/wp-json/wp/v2/posts');

// ❌ BAD: Hardcoded GraphQL endpoint
const client = new ApolloClient({
  uri: 'https://mysite.com/graphql',
});

// ✅ GOOD: Environment variable
fetch(`${process.env.NEXT_PUBLIC_WORDPRESS_URL}/wp-json/wp/v2/posts`);
```

**Fix:** Use environment variables for all WordPress URLs.

---

### HWP-003: GraphQL No Error Handling [HIGH]

**What it detects:** Apollo Client `useQuery`/`useMutation` hooks without error handling.

**Why it matters:** Without error handling, failed GraphQL queries cause silent failures or broken UIs.

```javascript
// ❌ BAD: No error destructuring
const { data, loading } = useQuery(GET_POSTS);

// ✅ GOOD: Error handling included
const { data, loading, error } = useQuery(GET_POSTS, {
  onError: (err) => console.error('GraphQL error:', err),
});

if (error) return <ErrorMessage error={error} />;
```

---

### HWP-004: Missing ISR Revalidate [MEDIUM]

**What it detects:** Next.js `getStaticProps` without `revalidate` for WordPress content.

**Why it matters:** Without ISR (Incremental Static Regeneration), content is frozen at build time and won't update when WordPress content changes.

```javascript
// ❌ BAD: No revalidate (content frozen forever)
export async function getStaticProps() {
  const posts = await fetchPosts();
  return { props: { posts } };
}

// ✅ GOOD: ISR with revalidate
export async function getStaticProps() {
  const posts = await fetchPosts();
  return {
    props: { posts },
    revalidate: 60, // Regenerate every 60 seconds
  };
}
```

---

## Pattern Reference

| Pattern ID | Severity | Description |
|------------|----------|-------------|
| `headless-api-key-exposure` | CRITICAL | API keys/secrets in client bundles |
| `headless-hardcoded-wordpress-url` | MEDIUM | Hardcoded WordPress API URLs |
| `headless-graphql-no-error-handling` | HIGH | useQuery/useMutation without error handling |
| `headless-nextjs-missing-revalidate` | MEDIUM | getStaticProps without ISR |

---

### Nuxt 3

**Environment Variables:**
```bash
# .env
NUXT_PUBLIC_WORDPRESS_URL=https://wp.example.com  # Exposed to browser
NUXT_WP_AUTH_TOKEN=secret_here                     # Server-only
```

**Data Fetching:**
```javascript
// pages/posts/[slug].vue
<script setup>
const config = useRuntimeConfig();
const route = useRoute();

const { data: post, error } = await useFetch(
  `${config.public.wordpressUrl}/wp-json/wp/v2/posts`,
  {
    query: { slug: route.params.slug },
    transform: (posts) => posts[0],
  }
);

if (error.value) {
  throw createError({ statusCode: 404, message: 'Post not found' });
}
</script>
```

### Gatsby

**Environment Variables:**
```bash
# .env.development / .env.production
GATSBY_WORDPRESS_URL=https://wp.example.com  # Exposed to browser
WP_AUTH_TOKEN=secret_here                     # Build-time only
```

### Vite / Astro

**Environment Variables:**
```bash
# .env
VITE_WORDPRESS_URL=https://wp.example.com    # Exposed to browser
WP_SECRET=secret_here                         # Server-only (Astro SSR)
```

---

## Baseline Configuration

### Suppressing False Positives

If a pattern is intentionally used (e.g., `getStaticProps` for truly static content), add to baseline:

```bash
# .baseline.txt
headless-nextjs-missing-revalidate:pages/about.js:16
```

### Project Template Configuration

Create a project template for headless WordPress projects:

```bash
# TEMPLATES/my-headless-project.txt
[project]
name = My Headless Site
type = headless-nextjs

[paths]
scan = src pages components lib

[severity_overrides]
# Upgrade hardcoded URLs to HIGH for production
headless-hardcoded-wordpress-url = HIGH

[baseline]
# Static pages that don't need revalidate
headless-nextjs-missing-revalidate:pages/about.tsx:10
headless-nextjs-missing-revalidate:pages/privacy.tsx:8
```

---

## Troubleshooting

### Pattern Not Detecting Expected Issues

1. **Check file extensions:** Ensure files have `.js`, `.jsx`, `.ts`, or `.tsx` extensions
2. **Check excluded paths:** By default, `node_modules/`, `vendor/`, `.git/` are excluded
3. **Use verbose mode:** `--verbose` shows all matches, not just first occurrence

### False Positives

**getStaticProps flagged but content is truly static:**
```javascript
// Add to baseline or use comment suppression
// wpcheck:ignore headless-nextjs-missing-revalidate
export async function getStaticProps() {
  // This page is intentionally static (legal content)
}
```

**Hardcoded URL in example/test code:**
```javascript
// Test files are excluded by default
// If not, add to baseline: headless-hardcoded-wordpress-url:__tests__/api.test.js:15
```

### Performance on Large Codebases

For projects with 50k+ lines of JavaScript:

```bash
# Scan specific directories only
./bin/check-performance.sh --paths "src/pages src/components"

# Use JSON output for faster parsing
./bin/check-performance.sh --paths ./src --format json > results.json
```

---

## Related Documentation

- [dist/README.md](README.md) - Main scanner documentation
- [dist/patterns/headless/](patterns/headless/) - Pattern JSON definitions
- [PROJECT/1-INBOX/PROJECT-NODEJS.md](../PROJECT/1-INBOX/PROJECT-NODEJS.md) - JS/TS roadmap

---

## Changelog

### v1.0.80 (2026-01-05)
- Initial release of headless WordPress patterns
- Added 4 new checks: HWP-001 through HWP-004
- Created test fixtures in `dist/tests/fixtures/headless/`

