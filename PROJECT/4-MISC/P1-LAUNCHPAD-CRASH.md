# Launchpad / ACF Pro Local 502 Lessons Learned

## TLDR; Root Cause Analysis

The local `502` / PHP-FPM `SIGSEGV` issue was not caused by one single generic WordPress failure; it was a layered child-theme Launchpad render/bootstrap problem that surfaced through multiple fault boundaries. 

Early in the investigation, top-level `_()` alias calls inside Launchpad ACF settings files repeatedly acted as crash triggers or reliable crash-boundary markers under the Local PHP-FPM runtime, and later the final active homepage boundary narrowed into the first Launchpad content-row wrapper / `hero-header` render path in `template-parts/content.php`, where dynamic `_()` output usage in IDs, classes, inline styles, and related render fragments was replaced with context-appropriate escaped/plain output. 

After those targeted fixes, the tmux-backed crash loop confirmed homepage, admin, and cron requests all returned `200` with no new PHP-FPM `SIGSEGV` or nginx upstream-close errors, so the practical root cause was the child theme's brittle Launchpad bootstrap/render implementation rather than Local itself.

## In the Future, What Could Have Sped Up the Debugging Process

This is realistic to speculate on. A few things likely would have shortened the investigation substantially:

- Having the tmux-backed crash-loop harness from the very beginning, so theme switching, probing, log capture, and recovery were automated instead of partially manual.
- Having clearer ownership boundaries in `neo-launchpad.php`, especially between bootstrap, ACF settings registration, WooCommerce hooks, and rendering, so the active fault boundary could have been narrowed faster.
- Having a smaller, modular Launchpad renderer instead of one large `template-parts/content.php` switchboard, which would have reduced the search space once the crash moved into row rendering.
- Having a documented inventory of high-risk output/translation patterns such as dynamic `_()` usage in settings and render fragments, since that pattern ended up being a repeated boundary marker.
- Having a standard first-response debugging checklist for Local WordPress crashes that immediately captures `debug.log`, PHP-FPM, nginx, active theme state, and a fallback-theme comparison.
- Having a few targeted smoke tests for the main Launchpad page path, admin path, and cron path, so regression confirmation could have happened faster and with less ambiguity.

## Status

- Date: 2026-03-05/06
- Environment: Local WP (`site-uclasacto.local`), PHP 8.2, nginx + PHP-FPM
- Current local outcome: the fallback theme loads `200`, and the latest tmux-backed crash-loop confirmation now also returns `200` for the child-theme homepage, `/wp-admin/`, and `wp-cron.php?doing_wp_cron=1`; the previously failing request now advances through the first `hero-header` row and into row 2 (`neo-html`) without producing a new PHP-FPM `SIGSEGV` or nginx upstream-close error before auto-recovering to Twenty Twenty-One

## Checklist

- [x] Reproduced the frontend `502 Bad Gateway`
- [x] Confirmed basic nginx/static/PHP routing was working
- [x] Confirmed WordPress requests were crashing PHP-FPM workers
- [x] Isolated ACF Pro as one local crash trigger
- [x] Disabled ACF Pro locally
- [x] Disabled the WP Engine object cache drop-in locally
- [x] Confirmed `/wp-admin/` could work while `/` still failed
- [x] Found a separate child-theme fatal path tied to WooCommerce functions
- [x] Confirmed the original theme stack was still active when `502`s persisted
- [x] Switched the local site to Twenty Twenty-One and verified `200 OK`
- [x] Re-activated ACF Pro 6.7.1 locally without an immediate crash
- [x] Narrowed the current suspect path to the child theme / Launchpad Builder integration
- [x] Added temporary debug instrumentation to the child theme Launchpad render path
- [x] Re-tested the original child theme stack with the new temporary debug logging enabled
- [x] Added per-include `acf_init()` breadcrumbs to isolate the exact settings file that crashes
- [x] Added direct `_general.php` breadcrumbs at the most likely crash boundaries
- [x] Replaced suspect `_()` translation alias calls in Launchpad settings files with `__()`
- [x] Added direct `_builder.php` breadcrumbs at the most likely crash boundaries
- [x] Replaced the first narrowed `_builder.php` `_()` calls at the exact crash boundary
- [x] Replaced the next narrowed `_builder.php` `_()` call at `field_theme_builder_tab`
- [x] Updated this Lessons Learned doc with the latest `_builder.php` breakpoint and a later audit plan
- [x] Replaced the next narrowed top-level `_builder.php` `_()` calls at `field_launchpad_builder`
- [x] Added optional supplemental debugging-tool guidance for HookTrace, Query Monitor, and ACF logging
- [x] Re-confirmed the live frontend fatal is `is_account_page()` in `functions.php` and identified duplicate child-theme directory ambiguity
- [x] Confirmed the current local recovery workflow has included manual child-theme folder renames and that the duplicate-folder state affects log/code correlation
- [x] Restored one canonical active child-theme directory: `ucla-sacto-child-theme`, with the sparse copy parked as backup
- [x] Confirmed the Astra parent theme is missing its root `functions.php`, explaining the `astra_html_before()` frontend fatal
- [x] Replaced the remaining `_()` calls inside `_builder.php` flexible-content and member settings definitions with `__()`
- [x] Verified against the official WordPress.org Astra 4.11.9 repository that the package should contain both root `functions.php` and `inc/compatibility/`
- [x] Verified the user-installed Astra `4.12.3` is now complete locally, including root `functions.php` and `inc/compatibility/`
- [x] Confirmed the latest activation-time breadcrumbs now stop immediately after `acf_init loaded _builder.php`, and added the next breadcrumb layer before each remaining post-`_builder.php` settings include
- [x] Confirmed the next activation-time boundary moved into `_color-scheme.php` and replaced its remaining top-level `_()` alias calls with `__()`
- [x] Pivoted from breadcrumb-first narrowing to saved outside-FPM CLI probe scripts for `_color-scheme.php` and `_builder.php`
- [x] Confirmed the current agent-side process runner is not producing trustworthy stdout or output files for direct PHP / WP-CLI environment checks in this session
- [x] Added a tmux-backed crash-loop harness that switches themes via `~/bin/local-wp`, probes homepage/admin/cron, captures debug/php/nginx deltas, and auto-reverts to Twenty Twenty-One
- [x] Verified the first automated crash loop reproduced child-theme `502`s on homepage and `/wp-admin/`, kept `wp-cron.php` returning `200`, and restored fallback homepage `200` without manual theme toggling
- [x] Cleared the normal `neo-walker.php` fatal and advanced the active crash boundary into Launchpad content-row rendering (`hero-header`)
- [x] Cleared the first Launchpad content-row / `hero-header` wrapper crash boundary so the child homepage now loads without reproducing the local PHP-FPM `SIGSEGV`
- [ ] Confirm the fix holds on any additional frontend paths the user wants covered beyond the automated homepage/admin/cron loop

## Automation Update (2026-03-06)

- Added the tracked harness `scripts/theme-crash-loop.sh`
- The harness writes per-run artifacts under `temp/theme-crash-loop/<timestamp>/`
- It uses `~/bin/local-wp` plus direct `template` / `stylesheet` / `current_theme` option updates so the loop can recover without loading the broken theme in WP-CLI
- First automated run (`20260305-215054`) produced:
  - fallback homepage `200`
  - child homepage `502`
  - child `/wp-admin/` `502`
  - child `/wp-cron.php?doing_wp_cron=1` `200`
  - recovery homepage `200` after automatic revert
- Matching log deltas from the same run showed:
  - PHP-FPM workers exiting on `SIGSEGV`
  - nginx `upstream prematurely closed connection while reading response header from upstream`
  - Launchpad breadcrumbs advancing through `_builder.php` and `_color-scheme.php`, then stopping after `acf_init loading container settings`
- The next likely active crash boundary is `settings/_container.php` or code reached immediately after that include inside `NEO_LAUNCHPAD::acf_init()`

## Container Boundary Update (2026-03-06)

- Ran 5 autonomous debug iterations focused on `neo-launchpad.php` and `settings/_container.php`
- Added include-metadata logging around `require_once(__DIR__ . '/settings/_container.php')` inside `NEO_LAUNCHPAD::acf_init()`
- Added staged breadcrumbs in `_container.php` around:
  - file start
  - the first field label translation
  - the first field array construction
  - each top-level `acf_add_local_field()` call
- The first narrowed boundary stopped at `_container.php before field_theme_container_tab`, which isolated the crash to the first `_('Container')` translation call
- Replacing only that first `_()` call with `__('Container', 'neo')` let the first field load fully and moved the crash to the next width-field translation call
- Replacing the remaining top-level `_()` calls in `_container.php` with `__()` let the entire container settings file load successfully
- The next breadcrumb now reaches:
  - `acf_init loaded _container.php`
  - `acf_init loading cta settings`
- The child theme still returns `502` on the homepage and `/wp-admin/`, while `wp-cron.php?doing_wp_cron=1` still returns `200`, so the issue is not fixed yet; the active crash boundary has simply moved deeper into the Launchpad settings chain
- Current working theory: top-level `_()` alias translation calls in Launchpad ACF settings files are a recurring crash trigger or at minimum a reliable crash-boundary marker under this Local PHP-FPM runtime
- The next likely active file is `settings/_cta.php`

## CTA Boundary Update (2026-03-06)

- Continued the tmux-backed crash-loop isolation into `settings/_cta.php`
- Added staged breadcrumbs around the CTA tab, title, and subtitle field registrations
- Replaced the CTA tab `_('CTA')` alias call with `__('CTA', 'neo')`, which let the first CTA field load and moved the crash to the next top-level CTA field
- Replaced the CTA title `_('CTA Title')` alias call with `__('CTA Title', 'neo')`, which let that field load and moved the crash to the subtitle field
- Replaced the CTA subtitle `_('CTA subtitle')` alias call with `__('CTA subtitle', 'neo')`, which let the entire CTA settings file load successfully
- The next breadcrumb now reaches:
  - `acf_init loaded _cta.php`
  - `acf_init loading footer settings`
- The child theme still returns `502` on the homepage and `/wp-admin/`, while `wp-cron.php?doing_wp_cron=1` still returns `200`, so the root crash is still active but now sits deeper in the Launchpad settings chain
- Current working theory remains unchanged: top-level `_()` alias translation calls in Launchpad ACF settings files are acting as a recurring crash trigger or crash-boundary marker under this Local PHP-FPM runtime
- The next likely active file is `settings/_footer.php`

## Footer Boundary Update (2026-03-06)

- Continued the tmux-backed crash-loop isolation into `settings/_footer.php`
- Added staged breadcrumbs around the footer tab, title, and copyright field registrations
- Replaced the footer tab `_('Footer')` alias call with `__('Footer', 'neo')`, which let the first footer field load and moved the crash to the next top-level footer field
- Replaced the footer title `_('Footer Title')` alias call with `__('Footer Title', 'neo')`, which let that field load and moved the crash to the copyright field
- Replaced the footer copyright `_('Footer Copyright')` alias call with `__('Footer Copyright', 'neo')`, which let the entire footer settings file load successfully
- The next breadcrumb now reaches:
  - `acf_init loaded _footer.php`
  - `acf_init loading header settings`
- The child theme still returns `502` on the homepage and `/wp-admin/`, while `wp-cron.php?doing_wp_cron=1` still returns `200`, so the root crash is still active but now sits deeper in the Launchpad settings chain
- Current working theory remains unchanged: top-level `_()` alias translation calls in Launchpad ACF settings files are acting as a recurring crash trigger or crash-boundary marker under this Local PHP-FPM runtime
- The next likely active file is `settings/_header.php`

## Header Boundary Update (2026-03-06)

- Continued the tmux-backed crash-loop isolation into `settings/_header.php`
- Added staged breadcrumbs around the header tab registration
- Replaced the header tab `_('Header')` alias call with `__('Header', 'neo')`, which let the header settings file load successfully
- The next breadcrumb now reaches:
  - `acf_init loaded _header.php`
  - `acf_init loading news settings`
- The child theme still returns `502` on the homepage and `/wp-admin/`, while `wp-cron.php?doing_wp_cron=1` still returns `200`, so the root crash is still active but now sits deeper in the Launchpad settings chain
- Current working theory remains unchanged: top-level `_()` alias translation calls in Launchpad ACF settings files are acting as a recurring crash trigger or crash-boundary marker under this Local PHP-FPM runtime
- The next likely active file is `settings/_news.php`

## News Boundary Update (2026-03-06)

- Continued the tmux-backed crash-loop isolation into `settings/_news.php`
- Added staged breadcrumbs around the news tab, title, and subtitle field registrations
- Replaced the news tab `_('News')` alias call with `__('News', 'neo')`, which let the first news field load and moved the crash to the next top-level news field
- Replaced the news title `_('News Title')` alias call with `__('News Title', 'neo')`, which let that field load and moved the crash to the subtitle field
- Replaced the news subtitle `_('News Subtitle')` alias call with `__('News Subtitle', 'neo')`, which let the entire news settings file load successfully
- The next breadcrumb now reaches:
  - `acf_init loaded _news.php`
  - `acf_init complete`
  - `init start`
- The child theme still returns `502` on the homepage, while `/wp-admin/` now returns `200` and `wp-cron.php?doing_wp_cron=1` still returns `200`, so the root crash is still active but now sits beyond the Launchpad settings includes
- Current working theory has narrowed: the repeated top-level `_()` alias pattern is no longer the active stop point once `_news.php` loads, and the next likely boundary is inside `NEO_LAUNCHPAD::init()` or the next frontend bootstrap layer after `acf_init`
- The latest logs also continue to show an early translation-loading notice for `learndash-certificate-builder`, which may be a secondary bootstrap smell but has not yet replaced the PHP-FPM `SIGSEGV` as the primary failure to isolate

## Init Boundary Update (2026-03-06)

- Added staged breadcrumbs inside `NEO_LAUNCHPAD::init()` after image-size registration, custom role setup, enqueue-hook setup, and around each post-type / taxonomy registration block.
- Re-ran the tmux-backed crash loop and confirmed all new `init()` breadcrumbs complete for:
  - `/?crash-loop=child-home`
  - `/wp-admin/?crash-loop=child-admin`
  - `/wp-cron.php?doing_wp_cron=1&crash-loop=child-cron`
- The failing homepage request now reaches:
  - `acf_init complete`
  - `init complete`
  - `child_enqueue_assets start`
  - `child_enqueue_assets complete`
- Despite those last-good breadcrumbs, the homepage still returns `502`, PHP-FPM still exits on `SIGSEGV`, and nginx still reports the upstream premature-close error.
- This moves the active crash boundary beyond the Launchpad settings chain, beyond `NEO_LAUNCHPAD::init()`, and beyond the currently logged portion of `child_enqueue_assets()` into a later frontend-only bootstrap or render path.
- The early `learndash-certificate-builder` translation-loading notice is still visible and remains a secondary bootstrap smell, but it has not displaced the homepage segfault as the primary failure.

## WP Head Boundary Update (2026-03-06)

- Added minimal breadcrumbs in `neo-launchpad.php` for the next frontend hooks after `child_enqueue_assets()`:
  - `wp_head_injection()`
  - `font_include()`
  - the WooCommerce noindex `wp_head` closure
  - `google_map()`
- Re-ran the tmux-backed crash loop and confirmed the failing homepage request now reaches:
  - `child_enqueue_assets complete`
  - `wp_head_injection complete`
  - `font_include complete`
  - `woo wp_head noindex complete`
- The same failing homepage request still returns `502`, PHP-FPM still exits on `SIGSEGV`, and nginx still reports the upstream premature-close error.
- No `google_map()` / footer breadcrumb appeared for the failing homepage request, so the active crash boundary is now narrowed to a later frontend template/render stage after the current `wp_head` hooks but before footer execution.
- Current next-target theory: inspect the first post-`wp_head` template path used by the failing page (`page.php`/navigation/renderer) because the render logs have not yet appeared for the crashing homepage request.

## Render Boundary Update (2026-03-06)

- Added staged breadcrumbs in `page.php`, `template-parts/navigation.php`, and `template-parts/footer.php` around the first render/template boundaries after `wp_head()`.
- Replaced the immediate render-path dynamic `_()` output calls in `template-parts/navigation.php` and `template-parts/footer.php` with escaped output so the first render path no longer depends on the `_()` alias pattern.
- That change moved the homepage off the earlier `502`/`SIGSEGV` path and exposed a normal PHP fatal in `neo-walker.php` during `wp_nav_menu()` fallback rendering:
  - `property_exists(): Argument #1 ($object_or_class) must be of type object|string, array given`
- Patched `neo-walker.php` so the custom walker normalizes `$args` for both object-style and array-style menu/page-menu rendering paths.
- Re-ran the tmux-backed crash loop and confirmed the `neo-walker.php` fatal is gone; the failing homepage now reaches:
  - `navigation template complete`
  - `page template after navigation`
  - `page template before renderer`
  - `renderer toggle evaluated`
  - `renderer entering launchpad path`
  - `content entry`
  - `content template start`
  - `content row start` with `row_layout="hero-header"`
- The homepage still returns `502`, PHP-FPM still exits on `SIGSEGV`, and nginx still reports the upstream premature-close error, so the active crash boundary is now narrowed to code inside or immediately after the shared content-row wrapper and first `hero-header` render path.

## Content Row Fix Update (2026-03-06)

- Inspected the exact pre-`hero-header` shared-wrapper region in `template-parts/content.php` and found a dense cluster of dynamic `_()` output calls in the selector/id, padding CSS values, inline background styles, wrapper classes, alignment classes, and header button text.
- Replaced only those narrowed first-row `_()` output calls with escaped/plain output appropriate to context and added minimal breadcrumbs for:
  - `content row wrapper start`
  - `content row wrapper complete`
  - `hero-header branch start`
  - `hero-header branch ready to render`
- `php -l template-parts/content.php` passed after the change.
- Re-ran the tmux-backed crash loop twice and both confirmation runs now produced:
  - fallback homepage `200`
  - child homepage `200`
  - child `/wp-admin/` `200`
  - child `wp-cron.php?doing_wp_cron=1` `200`
  - recovery homepage `200`
- The new breadcrumbs confirm the previous failing homepage request now advances through:
  - `content row wrapper complete`
  - `hero-header branch ready to render`
  - row 2 start with `row_layout="neo-html"`
- No new PHP-FPM `SIGSEGV` worker exit and no new nginx `upstream prematurely closed connection` line appeared in the successful confirmation runs.
- Current practical conclusion: the immediate first-row shared wrapper / `hero-header` `_()` output cluster in `template-parts/content.php` was the last active homepage crash boundary in this Local runtime.

## Original Symptoms

- Homepage/front end returned `502 Bad Gateway`
- Static files still loaded
- A trivial PHP file still loaded
- WordPress bootstrap routes triggered upstream failure
- `/wp-admin/` was sometimes reachable even while `/` failed

## What We Tried

### 1) Basic sanity checks

- Checked static asset responses
- Checked a simple standalone PHP file response
- Confirmed this was not a general Local/nginx outage
- Reproduced the failure with real browser-style requests and Playwright earlier in the investigation

### 2) Log-based confirmation

- Checked Local PHP-FPM logs
- Checked nginx error logs
- Confirmed repeated PHP-FPM worker crashes with `SIGSEGV`
- Confirmed nginx errors like `upstream prematurely closed connection while reading response header from upstream`

## Main Lesson

This was not just a normal PHP fatal. At least part of the issue was a true PHP-FPM crash/segfault under the WordPress runtime.

### 3) Least-invasive plugin isolation

- Used DB-based changes to `active_plugins` instead of editing plugin code
- Disabled all normal plugins temporarily
- Verified WordPress could respond normally without the full plugin stack
- Reintroduced plugins selectively

### 4) ACF Pro isolation

- Tested ACF Pro (`advanced-custom-fields-pro/acf.php`) in isolation
- Confirmed ACF Pro 6.7.1 alone could trigger the local `502`
- Compared against Gravity Forms alone, which did **not** reproduce the same crash

## Main Lesson

ACF Pro was a real local crash trigger here, not just a coincidental plugin in the stack.

### 5) Local-only ACF disable

- Per request, removed ACF Pro from the local `active_plugins` option
- Verified ACF stayed disabled locally afterward

### 6) Object cache isolation

- Investigated the WP Engine object cache drop-in
- Disabled it locally by removing `wp-content/object-cache.php`
- Re-tested the frontend
- Result: object cache removal alone did **not** fix the homepage `502`

## Main Lesson

The object cache may have been adding noise/confusion, but it was not the only remaining cause of the frontend failure.

### 7) Theme/frontend-path isolation

- Continued testing because admin remained reachable while the homepage failed
- Found a separate theme-side fatal when WooCommerce was not available:
  - `Call to undefined function is_account_page()`
  - file: `wp-content/themes/ucla-sacto-child-theme/functions.php`
- This showed there was also fragile frontend/theme code beyond the ACF crash

### 8) Child-theme / Astra signal in logs

- Read `wp-content/debug.log` after reproducing the latest `502`
- Found child-theme/Astra-related frontend notices including:
  - `neo-swiper`
  - `neo-plyr`
  - missing dependency: `astra-theme-css`

## Main Lesson

The Launchpad/child-theme frontend path appears tightly coupled to Astra assets and/or theme assumptions. That makes it a likely secondary failure path once ACF is involved.

### 9) Theme state verification

- Earlier theme-switch attempts appeared successful from partial probes, but that turned out to be misleading
- Re-checked live DB values directly
- Confirmed the site was still actually on:
  - `current_theme = Normans Nursery`
  - `stylesheet = ucla-sacto-child-theme`
  - `template = astra`

## Main Lesson

Do not trust a partial HTTP result alone during Local debugging. Verify the live theme/plugin state directly in `wp_options`.

### 10) Corrected local theme switch

- Re-applied the local theme switch using direct DB updates
- Verified the live state became:
  - `current_theme = Twenty Twenty-One`
  - `stylesheet = twentytwentyone`
  - `template = twentytwentyone`
- Re-tested with real `GET` requests, not just `HEAD`
- Confirmed:
  - `/` -> `200`
  - `/?nocache=1` -> `200`
  - `/wp-admin/` -> `302` to login
- Confirmed returned HTML contained Twenty Twenty-One assets/body classes

## Instrumentation Update

- ACF Pro 6.7.1 was re-activated locally and did **not** immediately reproduce the crash in the current test state
- Suspicion has now shifted more strongly to the child theme / Launchpad Builder path
- Temporary debug logging was added at these strategic locations:
  - `neo-launchpad.php`
    - constructor / `init()`
    - `acf_init()`
    - `child_enqueue_assets()`
    - `neo_get_field()` for the Launchpad toggle
    - shutdown fatal logging
  - `template-parts/renderer.php`
    - before Launchpad toggle evaluation
    - before entering Launchpad rendering
    - on caught `Throwable` exceptions
  - `template-parts/content.php`
    - at content entry
    - row-by-row flexible-content layout logging
  - `functions.php`
    - guard + debug log around `is_account_page()` usage
- Theme version was bumped to `3.5.1` for this temporary debugging iteration
- Latest crash test result:
  - `NEO_LAUNCHPAD_DEBUG constructor complete` logged successfully
  - `NEO_LAUNCHPAD_DEBUG acf_init start` logged successfully
  - `acf_init complete` did **not** log
  - `acf_init loading builder settings` did **not** log
  - This narrows the crash to the early `acf_init()` include path, likely in `settings/_general.php` or `settings/_api.php`, before `_builder.php` is loaded
- Follow-up instrumentation update:
  - Added breadcrumbs immediately after each `require_once()` inside `NEO_LAUNCHPAD::acf_init()`
  - Bumped theme version to `3.5.2` for this debugging iteration
  - Re-tested after adding the per-include breadcrumbs
  - The log still stopped at `NEO_LAUNCHPAD_DEBUG acf_init start`
  - No `acf_init loaded _general.php`, `acf_init loaded _api.php`, or later include breadcrumbs appeared
  - This further narrows the active crash to the first include boundary: `require_once(__DIR__ . '/settings/_general.php')`, or to code inside `settings/_general.php` before control returns
- Proactive crash-follow-up instrumentation:
  - Added direct breadcrumbs inside `settings/_general.php` at file entry and around each top-level ACF registration call
  - Added markers before/after:
    - `group_user_options`
    - `group_location_options`
    - `acf_add_options_page(...)`
    - `theme_general_settings_group`
  - Bumped theme version to `3.5.3` for this debugging iteration
  - The most suspicious remaining spot in `_general.php` is the `_('Theme Settings')` translation alias used during options-page and field-group registration
- Targeted fix attempt after the next breadcrumb run:
  - `debug.log` now advances through:
    - `_general.php loaded group_user_options`
    - `_general.php loaded group_location_options`
    - `_general.php before acf_add_options_page`
  - Logging stops there for both `/wp-cron.php` and `/wp-admin/themes.php?activated=true`
  - Replaced the suspect `_()` alias only at the narrowed crash boundary:
    - `_general.php`: `Theme Settings` option-page and field-group labels
    - `_api.php`: `API` tab label
  - Used `__()` to match the rest of the settings file conventions
  - Bumped theme version to `3.5.4` for this debugging iteration
- Next breakpoint after the `_general.php` fix:
  - `debug.log` now advances through:
    - `_general.php loaded options page`
    - `_general.php loaded theme_general_settings_group`
    - `acf_init loaded _general.php`
    - `acf_init loaded _api.php`
    - `acf_init loading builder settings`
  - Logging stops before `acf_init loaded _builder.php`
  - This moves the active crash boundary to `require_once(__DIR__ . '/settings/_builder.php')` or top-level code inside `_builder.php`
  - Added direct `_builder.php` breadcrumbs around the most likely failure points:
    - `field_launchpad_toggle`
    - `group_launchpad_settings`
    - the top-level `WP_Query` / team-items hydration block
    - `field_theme_builder_tab`
    - `field_launchpad_builder`
    - `group_member_settings`
  - `_builder.php` also contains many remaining `_()` translation alias usages, so that remains a strong follow-up suspect if the next crash stops on one of those boundaries
  - Bumped theme version to `3.5.5` for this debugging iteration
- Next breakpoint after the first `_builder.php` breadcrumbs:
  - `debug.log` now advances through:
    - `_builder.php start`
    - `_builder.php before field_launchpad_toggle`
  - Logging stops before `_builder.php loaded field_launchpad_toggle`
  - This narrows the active crash to the very first `acf_add_local_field(...)` in `_builder.php`
  - Replaced only the three `_()` calls at that exact boundary:
    - `Enable/Disable Page Builder`
    - `Enable`
    - `Disable`
  - Kept the existing `_builder.php` breadcrumbs in place for the next re-test
  - Bumped theme version to `3.5.6` for this debugging iteration
- Next breakpoint after the first `_builder.php` fix:
  - `debug.log` now advances through:
    - `_builder.php loaded field_launchpad_toggle`
    - `_builder.php loaded group_launchpad_settings`
    - `_builder.php loaded team query`
    - `_builder.php loaded team items`
    - `_builder.php before field_theme_builder_tab`
  - Logging stops before `_builder.php loaded field_theme_builder_tab`
  - This narrows the active crash to the tab-field registration for `field_theme_builder_tab`
  - Replaced only that exact `_()` label call with `__('Launchpad Builder', 'neo')`
  - Kept the existing `_builder.php` breadcrumbs in place for the next re-test
  - Bumped theme version to `3.5.7` for this debugging iteration
- Current narrowed state after the latest log read:
  - `debug.log` now proves the first `_builder.php` fix worked and execution advances through:
    - `_builder.php loaded field_launchpad_toggle`
    - `_builder.php loaded group_launchpad_settings`
    - `_builder.php loaded team query`
    - `_builder.php loaded team items`
    - `_builder.php before field_theme_builder_tab`
  - Logging stops before `_builder.php loaded field_theme_builder_tab`
  - The active crash boundary is therefore the `field_theme_builder_tab` registration itself, with `field_launchpad_builder` remaining the next likely minimal suspect if the next run advances farther
  - Theme version is being bumped again to `3.5.8` for this documentation/planning iteration
- Latest log read after the `field_theme_builder_tab` fix:
  - `debug.log` now advances through:
    - `_builder.php loaded field_theme_builder_tab`
    - `_builder.php before field_launchpad_builder`
  - Logging stops before `_builder.php loaded field_launchpad_builder`
  - This narrows the active crash to the flexible-content registration for `field_launchpad_builder`
  - Replaced only the top-level `_()` calls at that exact boundary:
    - `Launchpad Builder`
    - `Build your own landing page`
    - `Add new Section`
  - Kept the existing `_builder.php` breadcrumbs in place for the next re-test
  - Bumped theme version to `3.5.9` for this debugging iteration

## Current Local State

- ACF Pro re-activated locally
- WP Engine object cache drop-in disabled locally
- Theme should be reverted to an installed default WordPress base theme after each crash test before continuing
- On this local site, the safe installed fallback theme is `twentytwentyone` (not `twentytwentyfour`)
- Frontend currently loads normally in this local troubleshooting configuration
- The latest child-theme crash test shifted back to a frontend fatal in `functions.php` at `enqueue_dashboard_scripts()`
- The latest decisive fatal is `Call to undefined function is_account_page()` at `functions.php:335`
- The current local recovery workflow has included manually renaming the child-theme folder to force switch-back behavior when DB/theme switching was unreliable
- The child-theme directories have now been normalized back to one canonical active code path: `ucla-sacto-child-theme`
- The former sparse duplicate is now parked as `ucla-sacto-child-theme-sparse-backup`
- The canonical `ucla-sacto-child-theme/functions.php` still contains the WooCommerce guard around `is_account_page()` at the earlier fatal boundary
- The Astra parent theme has now been manually restored and updated locally to version `4.12.3`
- Astra `4.12.3` now has both root `functions.php` and `inc/compatibility/` present on disk, removing the earlier parent-theme integrity blocker
- Earlier agent-side shell restore attempts were unreliable in this session, so the current Astra repair was confirmed by direct filesystem verification instead of terminal output
- The latest `themes.php?activated=true` requests no longer end at the old Astra parent-theme failure; they now log through `_builder.php` and then stop before any `_color-scheme.php` / later include breadcrumb appears
- Added the next breadcrumb layer in `acf_init()` before each remaining post-`_builder.php` include so the next activation/crash test can identify the exact file boundary
- The latest activation-time requests now reach `acf_init loading color scheme settings` but still stop before `acf_init loaded _color-scheme.php`, moving the current narrowed boundary into top-level code inside `settings/_color-scheme.php`
- Replaced the remaining top-level `_()` alias calls in `_color-scheme.php` with `__()` as the next least-invasive narrowed fix
- Theme version was bumped to `3.5.18` for the `_color-scheme.php` translation-fix iteration
- Prepared saved CLI probe files `.augment-probe-color-scheme.php` and `.augment-probe-builder.php` to test the narrowed settings files outside PHP-FPM without waiting on `debug.log`
- Confirmed those saved probe files are present and structurally sane on disk
- The agent-side process runner in this session is currently not returning trustworthy stdout even for trivial commands like `php --version` or `echo`, and it also failed to materialize expected output files from direct probe runs
- Because of that runner limitation, the next reliable signal should come from the user's own terminal for `php --version`, `php -m`, direct probe execution, and Local/PHP-FPM log inspection rather than from additional agent-side shell retries
- Theme version was bumped to `3.5.19` for the CLI-probe pivot / runner-blocker iteration

## Consolidated Conclusions

1. There are at least **two separate local problems**:
   - ACF Pro 6.7.1 can trigger PHP-FPM segfaults locally
   - Astra + `ucla-sacto-child-theme` / Launchpad-related frontend behavior is also problematic locally
2. Admin success does **not** guarantee frontend safety in this stack.
3. Real `GET` requests are more reliable than `HEAD` requests for this issue.
4. DB-state verification is essential when Local appears inconsistent.
5. Least-invasive, reversible local-only changes were the right first approach.
6. The latest admin-wide crash is happening earlier than the Launchpad renderer path and inside `NEO_LAUNCHPAD::acf_init()` while `_builder.php` is registering top-level ACF fields.
7. Base-theme recovery must target a theme that is actually installed locally; this site has `twentytwentyone` available, while `twentytwentyfour` is not installed.
8. The `_builder.php` breadcrumbs now show execution can get through the first builder toggle field, the launchpad settings group, the top-level team query, and `field_theme_builder_tab` before stopping at `field_launchpad_builder`.
9. The recurring pattern still points to brittle include-time bootstrap behavior in Launchpad settings code, especially remaining `_()` translation alias calls and other top-level side effects.
10. The earlier Astra parent-theme integrity blocker is now repaired locally: Astra `4.12.3` is installed and verified on disk with both root `functions.php` and `inc/compatibility/` present.
11. Manual folder renaming has been part of the local recovery workflow, which explains the earlier runtime/path confusion.
12. That path confusion is now resolved: the full theme code is back under the canonical slug `ucla-sacto-child-theme`.
13. The earlier WooCommerce guard at `enqueue_dashboard_scripts()` is present in the canonical live folder, so the next crash test can move past folder ambiguity and back to real runtime narrowing.
14. The narrowed child-theme admin boundary is still `_builder.php`, but the remaining `_()` alias usage inside that file has now been removed as a class of likely include-time failures.
15. The current agent-side shell wrapper was unreliable for parent-theme restoration in this session, so Astra repair claims had to be based on direct filesystem verification rather than echoed terminal output.
16. The latest activation-time breadcrumbs now advance through `_builder.php`; the next unresolved boundary is between `acf_init loaded _builder.php` and the first post-`_builder.php` settings include.
17. That next boundary is now narrowed further: the latest activation-time requests reach `acf_init loading color scheme settings` and stop before `_color-scheme.php` returns control.
18. The saved outside-FPM probe scripts are ready, but the current agent-side process runner is too unreliable to trust for PHP environment comparison or direct probe output capture; the next meaningful data should come from a normal local terminal or Local's own logs.

## Recommended Next Steps

1. Keep the site on a default WordPress base theme between crash tests
2. From a normal local terminal, export `TERM=dumb`, `NO_COLOR=1`, and `CI=1`
3. Run `php --version` and `php -m | sort` to compare CLI PHP against the Local/PHP-FPM runtime
4. Run the saved direct probes: `php .augment-probe-color-scheme.php` and `php .augment-probe-builder.php`
5. Inspect the Local / PHP-FPM error log for the actual crash signal, faulting address, or extension reference
6. If the child-theme test crashes again, switch back to `twentytwentyone` before continuing the next debugging round
7. Keep one canonical active child-theme directory during debugging so logs, edits, and runtime paths stay correlated
8. After collecting CLI/log output, decide whether the next move is extension isolation, memory-limit investigation, or another narrowed theme/settings fix

## Later Audit Plan: Launchpad Bootstrap / Settings Code

1. **Map all Launchpad bootstrap entry points**
   - Review `functions.php`, `neo-launchpad.php`, and the `acf_init()` flow end-to-end
   - Document which hooks fire which includes and in what order
   - Confirm which code paths run on frontend, wp-admin, cron, and AJAX requests
2. **Inventory include-time side effects**
   - Review `_general.php`, `_api.php`, and `_builder.php` for code that executes immediately on include
   - Classify each top-level statement as one of:
     - safe ACF registration
     - translation call
     - dynamic query / data hydration
     - dependency-sensitive logic
     - output / rendering concern
3. **Standardize translation usage**
   - Replace nonstandard `_()` calls with the appropriate WordPress i18n helpers such as `__()` / `esc_html__()`
   - Verify text domains are consistent and loaded at the right point in the lifecycle
   - Check whether early translation loading is contributing to instability or just adding noise
4. **Reduce early-execution side effects**
   - Move expensive or dependency-sensitive work out of file scope where possible
   - In particular, review the top-level team `WP_Query`, dynamic choice arrays, and other derived data built during include time
   - Prefer lazy callbacks, narrower hooks, or admin-only execution where behavior allows
5. **Audit dependency guards and assumptions**
   - Check for assumptions about Astra, WooCommerce, ACF, LearnDash, and any Launchpad-specific helpers
   - Add `function_exists()`, `class_exists()`, or equivalent guards only where needed and only at proven failure boundaries
   - Confirm the bootstrap does not rely on parent-theme functions before that parent stack is ready
6. **Separate registration from rendering/data concerns**
   - Keep field/group registration focused on schema definition only
   - Move data fetching, layout preparation, and frontend rendering concerns into later dedicated functions
   - Reduce cross-file hidden coupling between settings registration and renderer/template logic
7. **Add safer debug and validation checkpoints**
   - Keep lightweight breadcrumb logging available behind a debug-friendly pattern
   - Add a repeatable validation checklist for theme activation, admin access, frontend load, and cron/AJAX requests
   - If practical later, add a small smoke-test script or WP-CLI verification sequence for activation and request checks
8. **Use supplemental tracing tools only if the current isolation path stalls**
   - Treat `HookTrace` as a hook-timeline aid, not as a replacement for line-level breadcrumbs inside large ACF definitions
   - Use `Query Monitor` for PHP errors, request context, hooks/actions, and related runtime signals on requests that stay alive long enough to surface its data
   - `HookTrace` + `Query Monitor` together can cover a large portion of request-scoped context, especially on staging/local with `WP_DEBUG` enabled
   - Manual `acf_log()` or existing `NEO_LAUNCHPAD::debug_log()` calls remain the safer targeted option for ACF-specific boundaries inside the Launchpad bootstrap
   - Avoid custom Query Monitor collectors or heavier custom integrations unless the current breadcrumb-led method stops producing forward progress
9. **Finish with a cleanup pass**
   - Once the crash path is fully isolated, remove temporary breadcrumbs that are no longer needed
   - Keep only durable guards/fixes that solve proven failure points
   - Re-test on the smallest realistic matrix: frontend, admin, cron, and one AJAX path

## Recovery Note

- The message `The requested theme does not exist.` can be explained by the local site being pointed at a non-installed fallback theme slug.
- `wp-content/themes/` now contains `astra`, `ucla-sacto-child-theme`, `ucla-sacto-child-theme-sparse-backup`, and `twentytwentyone`.
- The full child-theme code has been restored to the canonical folder name `ucla-sacto-child-theme`.
- It does **not** contain `twentytwentyfour`.

## Notes

- This debugging pass has included small, reversible repository changes in the child theme to add breadcrumbs and narrow exact failure boundaries
- The active debugging changes remain intentionally least-invasive and should be cleaned up after the crash path is fully isolated

## Why It Worked on WP Engine but Failed on Local

The most practical explanation is that WP Engine did not create a fundamentally different code path; Local exposed a portability and stability weakness in the child theme's Launchpad bootstrap/render implementation that WP Engine's runtime happened to tolerate.

Several factors likely combined here:

- **The theme code was brittle in a few high-risk areas**
  - The investigation repeatedly narrowed to top-level `_()` alias usage in Launchpad ACF settings files and then to dynamic `_()` usage inside early render fragments.
  - Those patterns are more fragile than standard WordPress translation/output helpers such as `__()`, `esc_html__()`, and explicit escaped output.
- **WP Engine and Local are not the same runtime even when both report PHP 8.x**
  - Differences in PHP-FPM build, extensions, gettext behavior, opcache, memory layout, and request/process behavior can matter a lot when the symptom is a `SIGSEGV` rather than a normal PHP fatal.
  - A segfault-level failure often means one environment is surfacing an engine/extension edge case that another environment does not trigger as easily.
- **Local also had some environment drift during the investigation**
  - The debugging process uncovered an incomplete Astra install locally, duplicate child-theme directory ambiguity, and general local/runtime inconsistency that increased the chance of environment-specific failures.
  - Those issues made Local less representative of remote and increased the amount of noise around the real Launchpad failure boundary.
- **WP Engine may simply have been masking or not triggering the same edge path**
  - A more stable or differently tuned hosting stack can make risky code appear fine until a PHP update, plugin load-order change, caching difference, or one specific request path exposes it.
  - In other words, "works on remote" did not prove the code was safe; it only meant the same brittle path was not failing there yet.

The practical takeaway is that Local did not invent the problem. It revealed that the child theme's Launchpad path was too sensitive to runtime/environment differences, and the final Local fix reduced that fragility by replacing risky dynamic `_()` usage at the proven failure boundaries.