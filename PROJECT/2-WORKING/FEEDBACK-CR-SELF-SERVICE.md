Verdict: Mostly False Positives / Scanner Noise

"Shell command execution" (CRITICAL) — False Positive
All 8 findings flag curl_exec($curl). This is PHP's cURL library function, not shell execution. It's the standard way to make HTTP requests in PHP without WordPress's wp_remote_* wrappers. No shell is involved — completely safe.

"Direct superglobal manipulation" on CURLOPT_POST/CURLOPT_POSTFIELDS (HIGH) — False Positive
The scanner is incorrectly matching curl_setopt($curl, CURLOPT_POST, true) as "superglobal manipulation." These are cURL options, not $_POST superglobal writes. This accounts for ~17 of the findings.

"Dynamic PHP include/require" (CRITICAL) — False Positive
Both check-user-meta.php:13 and test-alternate-registry-id.php:24 are WP-CLI test scripts that locate wp-load.php from a hardcoded relative path array. The $path variable is never user-controlled — it's iterated from a static array. No risk.

"N+1 query pattern" (CRITICAL) — False Positive
check-user-meta.php:23 — This is a flat script calling get_user_meta() sequentially for a single user, not inside a loop over users.
class-cr-business-rest-api.php:245 — This is a single get_user_meta() re-read after processing, not an N+1 pattern.

"Admin function missing capability check" (HIGH) — False Positive
credit-registry-forms.php:48 — add_action('admin_notices', ...) is a standard WordPress pattern for showing a dependency notice when a plugin is deactivated. The admin_notices hook itself only fires in the admin panel for authenticated users. The unset($_GET['activate']) on line 51 is also a standard WP pattern to suppress the "Plugin activated" message after forced deactivation.

6. Unsanitized $_GET['view_file'] (HIGH) — Valid Issue
At admin-test-page.php:191, $_GET['view_file'] is used without sanitize_file_name(). The strpos($view_file, '..') === false check on line 193 is a weak directory traversal guard (can be bypassed with encodings). Should use sanitize_file_name() like view_dir does on line 147.

7. Unsanitized $_GET['view_dir'] display before sanitization (HIGH) — Valid Issue
At admin-test-page.php:145, $_GET['view_dir'] is output with esc_html() (safe for XSS), but the sanitization via sanitize_file_name() happens on line 147 — after the display. The display itself is safe due to esc_html(), but the order is confusing.

8. $_POST['force_refresh'] (HIGH) — Low Risk
At api-functions.php:1014, this is compared strictly to the string 'true', so it can only ever be a boolean. No injection vector. However, this runs inside a WP AJAX handler — verify nonce checks exist upstream.

Many $_GET reads with sanitize_text_field() — False Positive
Lines in class-cr-rest-api.php and class-cr-business-rest-api.php that do sanitize_text_field($_GET['registry_id']) are already properly sanitized. The scanner flags the raw $_GET access but ignores the wrapping sanitization.

---

Easy wins
curl_exec() flagged as shell execution — The regex is likely matching /\b(exec|shell_exec|system|passthru)\s*\(/. Just add a negative lookbehind for curl_:


/\b(?<!curl_)(exec|shell_exec|system|passthru)\s*\(/
CURLOPT_POST flagged as superglobal manipulation — The regex is probably matching POST in any context. If the rule targets $_POST, ensure the pattern anchors on the $_ prefix:


/\$_(POST|GET|REQUEST|SERVER)\s*\[/
That alone would eliminate ~25 false positives from this report.

Sanitized reads flagged as unsanitized — This is the biggest noise source. A single-line lookahead can catch the most common WordPress pattern where the $_GET/$_POST access is wrapped in a sanitization call:


/(?<!sanitize_text_field\()(?<!sanitize_file_name\()(?<!esc_html\()(?<!esc_attr\()(?<!wp_verify_nonce\()(?<!absint\()\$_(GET|POST|REQUEST)\s*\[/
Or invert it — match the line, then exclude if the $_GET[...] appears as an argument to a known sanitizer on the same line. A two-pass approach is cleaner:

Match $_GET['foo']
Skip if the match is inside sanitize_text_field(, absint(, wp_verify_nonce(, etc.
isset($_GET[...]) / isset($_POST[...]) flagged — isset() checks don't read the value. These should be excluded entirely:


/(?<!isset\()\$_(GET|POST|REQUEST)\[/
Harder but doable
Dynamic include with hardcoded paths — The scanner can't easily tell that $path comes from a static array vs user input. But you could reduce noise by checking if the variable was assigned from a literal array within N lines above. Alternatively, skip flagging when the require is inside a file_exists() guard on the same variable — that pattern almost always indicates a bootstrap loader, not user-controlled inclusion.

N+1 detection — The heuristic "meta call inside loop" needs to actually verify there is a loop. If the scanner is matching get_user_meta anywhere near a foreach/for/while, it should confirm the meta call is lexically inside the loop body (between { and }), not just nearby by line count.

Not really fixable with regex
Admin capability check — Determining whether a current_user_can() check exists somewhere in the call chain before an add_action('admin_notices', ...) requires control-flow analysis. A regex scanner can't do this reliably. Best approach: downgrade this to INFO severity, or maintain a whitelist of hooks that are inherently admin-only (admin_notices, admin_init, etc.).

Summary of impact
Fix	Effort	False positives eliminated
curl_exec negative lookbehind	1 line	8
Anchor superglobal on $_ prefix	1 line	~17
Skip isset() wrapping	1 line	~10
Skip known sanitizer wrapping	Medium	~20
Loop verification for N+1	Medium	2
Whitelist admin-only hooks	Low	1
The first three fixes alone would cut this report from 99 findings to roughly 40, with almost no loss of true positives.