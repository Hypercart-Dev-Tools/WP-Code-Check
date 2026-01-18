2026-01-18

- [ ] Further DSM calibrations based on findings on Hypercart Performance Monitor (MKI version) 

"If you’d like, the next step could be: pick one of these DSM patterns (e.g., the string literal match or the isset( $_POST['nonce'] ) guard line) and I can help you sketch a minimal, targeted change to the DSM grep pattern or false‑positive filter to knock that class of noise out."

- [ ] "Tighten DSM to writes/unsets
Restrict spo-002-superglobals to patterns that actually assign to or unset superglobals (e.g., $_POST[...] =, unset($_GET['...'])).
Treat pure reads (especially $_SERVER) as either:
Part of unsanitized-superglobal-read, or
Best‑practice hints at LOW / info only.

- [ ] Add a literal/string guard
Ensure DSM patterns require an actual $_ token in code, so purely textual mentions like 'REQUEST_TIME_FLOAT ...' don’t match.
Recognize the nonce‑guard pattern as a whole
Special-case the common WordPress pattern:
if ( ! isset( $_POST['nonce'] ) ) { ... bail ... }
if ( ! wp_verify_nonce( $_POST['nonce'], '...' ) ) { ... bail ... }
Treat these as explicit guards, not violations, even if the isset() line itself doesn’t see a guard yet.

- [ ] Bridge/baseline for test + debug files
You already have spo-002-superglobals-bridge and DSM fixtures; Hypercart’s class-hpm-tests.php and this admin debug block are perfect candidates if you choose to baseline them later."