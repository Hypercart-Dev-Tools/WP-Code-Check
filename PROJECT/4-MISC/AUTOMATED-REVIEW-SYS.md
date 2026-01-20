# Automated Review System for WordPress Plugins & Themes

**Date:** 2026-01-01  
**Status:** Inception  
**Goal:** Establish a scalable, (semi)automated review system for WordPress plugins and themes to identify security, performance, and code quality issues.

## Project Goals and Outcomes

### Goals

- Help improve the security and performance of WordPress plugins and themes.
- Create a repeatable pipeline to ingest, scan, and produce reports for WP plugins/themes at scale.
- Minimize false-positive risk by adding an AI-assisted confirmation layer and a human review path for uncertain cases.
- Publish responsibly with an embargo window and clear, defensible language.

### Outcomes (v1)

- A reliable ingestion + scanning workflow that only re-scans new releases.
- Per-project JSON reports with consistent schema, plus HTML/Markdown rendering for humans.
- A publishable “public report” view that prioritizes CRITICAL/HIGH signal over noise.
- An auditable trail that records: the original finding, extracted context, AI verdict + confidence, and publication status.

## Table of Contents

- [Project Goals and Outcomes](#project-goals-and-outcomes)
- [Strategic Considerations](#strategic-considerations)
- [Technical Architecture (First Pass)](#technical-architecture-first-pass)
- [AI Confirmation Layer](#ai-confirmation-layer)
- [Embargo / No-Index (45 Days)](#embargo--no-index-45-days)
- [HTML Reports in WordPress](#html-reports-in-wordpress)
- [Security and Correctness Checklist](#security-and-correctness-checklist)
- [Minimal Implementation Shape (CPT + File + Caching)](#minimal-implementation-shape-cpt--file--caching)
- [Mapping Report Schema to UI](#mapping-report-schema-to-ui)
- [Open Questions](#open-questions)

## Strategic Considerations

### The good

The 45-day no-index approach mirrors responsible disclosure norms and gives plugin authors time to remediate before SEO amplifies the findings. This positions the project as a responsible actor rather than a “gotcha” security effort.

There is also clear ecosystem value: WP.org plugin review is notoriously understaffed, and many plugins with serious issues slip through. A public, searchable database of static analysis findings could become a useful resource for agencies vetting plugins before recommending them to clients.

### The tricky parts

1. **False positive reputation risk** — Static analysis without runtime context will flag legitimate patterns. If reports confidently claim “SQL injection vulnerability” and it turns out there is proper sanitization upstream, credibility erodes quickly. The mitigation detection work helps, but public reports require higher confidence than internal tooling.
2. **Legal considerations** — Publishing security findings (even with a delay) can draw unwanted attention. You are not exploiting vulnerabilities, but some authors may react poorly. This likely warrants legal review by counsel familiar with security research.
3. **Maintainer relations** — The WordPress ecosystem is small. Publishing reports (even accurate ones) without first attempting private disclosure can burn bridges. Consider notifying authors first, then publishing after the embargo window regardless of response.
4. **Signal vs. noise** — Reports that show many low-severity findings dilute the message. Public reports may need stricter thresholds (e.g., CRITICAL/HIGH only) or clearer severity communication.

## Technical Architecture (First Pass)

Proposed end-to-end pipeline:

```
┌─────────────────────────────────────────────────────────────────┐
│                     WP.org Plugin Ingestion                      │
├─────────────────────────────────────────────────────────────────┤
│  1. Fetch SVN/ZIP from WP.org API                               │
│  2. Track versions (only scan new releases)                     │
│  3. Extract metadata (active installs, last update, author)     │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                    WP Code Check Static Analysis                 │
├─────────────────────────────────────────────────────────────────┤
│  • Run check-performance.sh --format json                       │
│  • Filter to CRITICAL/HIGH for public reports                   │
│  • Apply mitigation detection (reduce false positives)          │
│  • Generate structured findings with file:line references       │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                 AI-Assisted Confirmation Layer                   │
├─────────────────────────────────────────────────────────────────┤
│  For each CRITICAL/HIGH finding:                                │
│  1. Extract context (function + surrounding code)               │
│  2. Evaluate mitigations and upstream sanitization              │
│  3. Emit a structured verdict + confidence                      │
│  4. Publish only CONFIRMED/LIKELY with appropriate caveats      │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Report Generation & Publishing                │
├─────────────────────────────────────────────────────────────────┤
│  • Markdown/HTML report per plugin                              │
│  • noindex meta tag + robots.txt for 45 days                    │
│  • After 45 days: remove noindex and publish                    │
│  • Optional: notify plugin author at day 0                      │
└─────────────────────────────────────────────────────────────────┘
```

## AI Confirmation Layer

The AI layer exists to reduce false positives by validating likely mitigations, guards, and upstream sanitization that static pattern matching can miss.

### Prompt structure (example)

```markdown
## Task
Analyze this static analysis finding and determine if it's a true positive.

## Finding
- **Type:** unbounded-posts-per-page
- **Severity:** CRITICAL
- **File:** includes/class-query-handler.php
- **Line:** 142
- **Pattern matched:** posts_per_page => -1

## Code Context
[Insert 50-100 lines centered on the finding]

## Analysis Required
1. Is there pagination or limiting logic elsewhere in this function?
2. Is this query scoped by a parent ID, taxonomy, or other constraint?
3. Is the result cached (transient, object cache)?
4. Is this admin-only code with capability checks?
5. Are there other mitigating factors that invalidate the finding?

## Response Format
- **Verdict:** CONFIRMED | LIKELY | UNCERTAIN | FALSE_POSITIVE
- **Confidence:** 0-100
- **Reasoning:** [2-3 sentences]
- **Mitigations found:** [list or "none"]
```

### Key considerations

1. **Token budget** — Sending full plugin codebases is impractical; context extraction should focus on the containing function plus any nearby helpers.
2. **Output consistency** — Use structured responses so verdicts can be processed downstream.
3. **Human review queue** — UNCERTAIN findings should go to a manual queue rather than being auto-published.
4. **Audit trail** — Store the AI reasoning, the exact prompt context, and model metadata for dispute resolution.

## Embargo / No-Index (45 Days)

Example logic for an embargo window (45 days) applied to reports:

```php
// In your report template
<?php if ( strtotime( $report->created_at ) > strtotime( '-45 days' ) ) : ?>
    <meta name="robots" content="noindex, nofollow">
<?php endif; ?>
```

Operationally, a daily cron could:

1. Find reports older than 45 days that are still marked as embargoed.
2. Regenerate them without the `noindex` tag.
3. Optionally ping Google Search Console API (if you decide to automate indexing).

## HTML Reports in WordPress

These JSON reports can be rendered into a report-page UI in WordPress. Two viable implementation paths (plus a hybrid) are below.

### Option A: Render from JSON on-the-fly (file-based)

**Flow**

1. Store JSON files in a controlled directory (e.g. `wp-content/uploads/wpcc-reports/`).
2. Add a pretty URL like `/wpcc-report/2025-12-31-035054-UTC/`.
3. On request: load JSON → decode → render template.

**Pros**

- No DB bloat.
- New reports appear instantly when files are added.
- Easy to keep reports immutable.

**Cons**

- If JSON is large, decoding on every hit can be expensive unless you cache.

**Make it fast**

- Cache parsed arrays or rendered HTML keyed by `filemtime()` so the cache invalidates automatically when the JSON changes.

### Option B: Import into a Custom Post Type (batch convert)

**Flow**

1. Create CPT: `wpcc_report`.
2. Each JSON file becomes one post (title = project name + timestamp).
3. Store:
   - Raw JSON (optional) in post meta or as an attached file.
   - Parsed “index fields” (errors/warnings counts, project name, timestamp) in post meta for querying.

**Pros**

- Native WP admin browsing/search/filtering.
- Easy to build an archive page (sorting, taxonomy, etc.).
- Good fit if you plan dashboards across many reports.

**Cons**

- More moving parts (importer + update strategy).
- Storing huge JSON in `postmeta` can be heavy; prefer storing the file and only indexing key fields.

### Recommended: Hybrid

- Store JSON files in uploads.
- Create/update a CPT post per report that stores:
  - `report_file` (attachment ID recommended).
  - Index fields: `timestamp`, `project_name`, `exit_code`, `total_errors`, `total_warnings`, etc.
- Render single report pages by reading the file (and caching).

This provides fast navigation and search (via CPT/meta), without pushing large JSON blobs into the database.

## Security and Correctness Checklist

1. **Never allow arbitrary file paths from request params.** Use an allowlist or store a file reference in post meta.
2. **Escape output** using WordPress escaping:
   - Titles/text: `esc_html()`
   - Attributes: `esc_attr()`
   - URLs: `esc_url()`
   - Code blocks: `esc_html()` inside `<pre><code>`
3. **If exposing report JSON via REST**:
   - Consider restricting access (capability checks) if reports include sensitive file paths.
   - Or strip/normalize sensitive fields before returning (e.g., remove absolute local paths).

## Minimal Implementation Shape (CPT + File + Caching)

### 1) CPT registration

```php
add_action( 'init', function () {
    register_post_type(
        'wpcc_report',
        [
            'label'        => 'WPCC Reports',
            'public'       => true,
            'has_archive'  => true,
            'rewrite'      => [ 'slug' => 'wpcc-report' ],
            'supports'     => [ 'title' ],
            'show_in_rest' => true,
        ]
    );
} );
```

### 2) Store a file reference in post meta

- `wpcc_report_file` = attachment ID (recommended) or a relative path under uploads.

### 3) Render + cache by `filemtime()`

```php
function wpcc_load_report_data_from_attachment( int $attachment_id ): array {
    $path = get_attached_file( $attachment_id );
    if ( ! $path || ! file_exists( $path ) ) {
        return [];
    }

    $mtime     = (int) filemtime( $path );
    $cache_key = 'wpcc_report_' . $attachment_id . '_' . $mtime;

    $cached = wp_cache_get( $cache_key, 'wpcc' );
    if ( is_array( $cached ) ) {
        return $cached;
    }

    $raw  = file_get_contents( $path );
    $data = json_decode( $raw, true );

    if ( ! is_array( $data ) ) {
        $data = [];
    }

    wp_cache_set( $cache_key, $data, 'wpcc', HOUR_IN_SECONDS );
    return $data;
}
```

### 4) Single template

- In `single-wpcc_report.php` (theme) or via `template_include` (plugin), load `$data` and render.
- Enqueue JS and pass a REST URL (or inline the data if it’s small).

## Mapping Report Schema to UI

From the sample JSON schema:

- Header: `project.name`, `project.version`, `project.type`, `project.author`, `project.files_analyzed`, `project.lines_of_code`, `timestamp`, `paths_scanned`, `strict_mode`.
- Status banner: `summary.exit_code`, `summary.total_errors`.
- Tabs/cards: derive from `checks` and `findings` (group by severity/type).

## Open Questions

1. **Scope** — All 60,000+ WP.org plugins, or start with top 1,000 by active installs?
2. **Update frequency** — Scan on every new version, or periodic sweeps?
3. **Dispute process** — What happens when an author disputes a report? Define a documented process.
4. **Liability framing** — “Potential issues identified by automated analysis” vs. “Vulnerabilities found” (language matters).
5. **Business model** — Lead-gen for consulting, a standalone SaaS, or open community data?

