I'll create a short todo list for the steps I'll perform and mark them done.

Created 3 todos

What it does (short): it runs `wp eval` on the site container via `local-wp`, executes PHP `file_get_contents('https://$1.local')` which returns the raw HTML as a string, prints that HTML to stdout, then pipes that raw HTML into `jq .`.

Why that is a problem:
- `jq` expects JSON. Raw HTML is not JSON, so `jq` will fail with a parse error.
- `file_get_contents()` over `https://...local` can fail with SSL verification (self-signed certs) or network resolution in the container/PHP environment.
- HTML contains quotes/newlines/binary bytes, which can break shell quoting or JSON encoding if not handled.
- WP-CLI `wp eval` prints whatever your PHP echoes; there’s no automatic JSON wrapping.

Safe alternatives (copyable):

1) Return JSON-encoded HTML so `jq` can parse it:
```sh
local-wp "$1" wp eval "echo json_encode(file_get_contents('https://$1.local'));" | jq -r .
```

2) Use base64 to avoid encoding/UTF-8 issues, then decode locally:
```sh
local-wp "$1" wp eval "echo base64_encode(file_get_contents('https://$1.local'));" | base64 --decode > page.html
```

3) Use `curl` from the host (or from within the container) instead of `file_get_contents`:
```sh
# From host (if DNS resolves to local dev)
curl -sS https://example.local -k > page.html   # -k if cert is self-signed

# Or via WP container (if local-wp exposes a shell)
local-wp "$1" wp ssh "curl -sS https://$1.local -k"
```

4) Use WordPress HTTP API inside `wp eval` for more control:
```sh
local-wp "$1" wp eval "echo json_encode(wp_remote_retrieve_body(wp_safe_remote_get('https://$1.local')));" | jq -r .
```

Recommendations:
- If you want the assistant to “see” raw HTML reliably, prefer base64 (safe transport) or `json_encode` (if you want JSON). Base64 avoids encoding/character issues.
- If SSL/self-signed certs are a problem, use curl with `-k` or configure the PHP stream context / WP_HTTP to ignore verification (only for dev).
- Validate that `local-wp` runs in an environment that can resolve `*.local` and reach the site.

Want me to add a small helper script (`local-browser`) implementing the base64-safe version and test it in the repo?