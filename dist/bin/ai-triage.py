#!/usr/bin/env python3
"""Phase 2 AI triage injector for WP Code Check reports.

- Reads an existing WP Code Check JSON log.
- Injects an `ai_triage` object (id-level triage for selected findings + overall summary).
- Does NOT modify findings; it annotates them.

This is intentionally conservative: it focuses on high-signal categories and treats
minified/vendor code differently.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, NamedTuple, Optional


class TriageDecision(NamedTuple):
    classification: str  # Confirmed | False Positive | Needs Review
    confidence: str      # high | medium | low
    rationale: str


VENDOR_HINTS = (
    '/vendor/',
    '/vendor_prefixed/',
    '/node_modules/',
    '/assets/lib/',
)
MINIFIED_HINTS = (
    '.min.js',
    '.min.css',
)


def is_vendor_or_third_party(path: str) -> bool:
    p = path.replace('\\', '/')
    return any(h in p for h in VENDOR_HINTS)


def is_minified(path: str) -> bool:
    p = path.lower()
    return any(h in p for h in MINIFIED_HINTS)


def classify_finding(f: Dict[str, Any]) -> Optional[TriageDecision]:
    """Return a triage decision for a single finding.

    Returns None if we choose not to triage this finding (keeps it unreviewed).
    """

    fid = f.get('id', '')
    file_path = f.get('file', '')
    msg = (f.get('message') or '').strip()
    code = (f.get('code') or '').strip()
    context = f.get('context') or []

    vendor = is_vendor_or_third_party(file_path)
    minified = is_minified(file_path)

    # --- Debugger statements in shipped JS are usually real issues (even if 3rd party).
    if fid == 'spo-001-debug-code':
        return TriageDecision(
            classification='Confirmed',
            confidence='high',
            rationale=(
                "Contains a `debugger;` statement in shipped JS. This will pause execution in devtools and is "
                "normally unintended for production builds (even if located in a vendored library)."
            ),
        )  # Recommendation ID: 'debugger-statements'

    # --- Unsafe RegExp: often FP in bundled/minified libs; mixed in authored code.
    if fid == 'hcc-008-unsafe-regexp':
        # Special-case: code shows escaping.
        if 'replace(/([.*+?^${}()|\\[\\]\\/\\\\])/g' in code or any(
            'replace(/([.*+?^${}()|\\[\\]\\/\\\\])/g' in (c.get('code') or '') for c in context
        ):
            return TriageDecision(
                classification='False Positive',
                confidence='high',
                rationale="The code escapes regex metacharacters before constructing RegExp, which mitigates injection.",
            )

        if vendor or minified:
            return TriageDecision(
                classification='Needs Review',
                confidence='low',
                rationale=(
                    "The pattern is in bundled/minified or third-party code. Manual review needed to confirm whether the "
                    "RegExp inputs are attacker-controlled and whether escaping/constraints exist upstream."
                ),
            )

        return TriageDecision(
            classification='Needs Review',
            confidence='medium',
            rationale=(
                "RegExp is constructed from a variable; confirm whether the variable is derived from user input and whether it is escaped/validated."
            ),
        )

    # --- Superglobal findings: prefer structured guarded/sanitized booleans when present.
    if fid == 'spo-002-superglobals':
        # Heuristic: docblocks/comments mentioning $_POST/$_GET; or constants containing 'POST' etc.
        if msg.lower().startswith('direct superglobal'):
            if code.strip().startswith('*') or code.strip().startswith('/*') or '$_POST' in code or '$_GET' in code:
                # If it's a docblock/comment line, it is not an access.
                if code.lstrip().startswith('*') or code.lstrip().startswith('/*'):
                    return TriageDecision(
                        classification='False Positive',
                        confidence='high',
                        rationale='This hit appears to be inside a comment/docblock (mentions superglobals but does not access them).',
                    )

            # Some hits are actually safe wrappers / validated flows.
            if 'verify_request_nonce' in code or any('verify_request_nonce' in (c.get('code') or '') for c in context):
                return TriageDecision(
                    classification='False Positive',
                    confidence='medium',
                    rationale='Nonce verification is performed via a helper (`verify_request_nonce`) in close proximity; direct access is part of a validated flow.',
                )

        # Prefer the scanner-provided guarded/sanitized booleans when available. These are
        # populated for DSM findings in v2.0.3+ and give us a more accurate picture than
        # re-deriving intent from raw code/guards arrays.
        guarded = f.get('guarded')
        sanitized = f.get('sanitized')
        guarded_b = guarded if isinstance(guarded, bool) else None
        sanitized_b = sanitized if isinstance(sanitized, bool) else None

        if guarded_b is not None or sanitized_b is not None:
            # Case 1: Guarded + sanitized DSM – usually acceptable WordPress form handling.
            if guarded_b is True and sanitized_b is True:
                return TriageDecision(
                    classification='False Positive',
                    confidence='high',
                    rationale=(
                        'Direct superglobal manipulation is both guard-protected (nonce/cap checks) '
                        'and sanitized on write; this matches standard WordPress form-handling patterns '
                        'and is unlikely to be a true issue.'
                    ),
                )

            # Case 2: Guarded but not clearly sanitized – lower risk but worth review.
            if guarded_b is True and (sanitized_b is False or sanitized_b is None):
                return TriageDecision(
                    classification='Needs Review',
                    confidence='medium',
                    rationale=(
                        'Direct superglobal manipulation is guard-protected (nonce/cap checks present) '
                        'but no write-side sanitization was detected; verify that values are constrained '
                        'before use and that bridge code does not bypass validation.'
                    ),
                )

            # Case 3: Sanitized but unguarded – input is constrained but CSRF/authz risk remains.
            if guarded_b is False and sanitized_b is True:
                return TriageDecision(
                    classification='Needs Review',
                    confidence='medium',
                    rationale=(
                        'Direct superglobal manipulation applies sanitization but no nonce/capability '
                        'guard was detected; consider adding CSRF/authz checks even if the values are '
                        'sanitized to reduce attack surface.'
                    ),
                )

            # Case 4: Unguarded and unsanitized (or unknown) – treat as confirmed high-signal.
            if guarded_b is False and (sanitized_b is False or sanitized_b is None):
                return TriageDecision(
                    classification='Confirmed',
                    confidence='high',
                    rationale=(
                        'Direct superglobal manipulation without detected guards or sanitization; '
                        'this is high-risk and should be refactored to add nonce/capability checks '
                        'and explicit sanitization or to avoid mutating superglobals directly.'
                    ),
                )

        # Fallback heuristics for older logs without guarded/sanitized booleans.

        # For actual assignments to $_REQUEST, treat as Needs Review.
        if code.strip().startswith('$_REQUEST'):
            return TriageDecision(
                classification='Needs Review',
                confidence='medium',
                rationale='Writes to $_REQUEST; verify this cannot be influenced by attackers and does not bypass validation logic.',
            )

        if vendor:
            return TriageDecision(
                classification='Needs Review',
                confidence='low',
                rationale='Located in vendored code; validate whether it is executed in your runtime context and whether upstream validation exists.',
            )

        return TriageDecision(
            classification='Needs Review',
            confidence='medium',
            rationale='Superglobal usage detected; confirm sanitization and nonce/capability checks for the execution path.',
        )

    if fid == 'unsanitized-superglobal-read':
        # Some are immediately sanitized/cast, but the tool may flag the raw read line.
        if 'absint(' in ''.join([code] + [(c.get('code') or '') for c in context]):
            return TriageDecision(
                classification='False Positive',
                confidence='medium',
                rationale='Value is cast/sanitized (e.g., absint) in close proximity; ensure no earlier use of the raw value.',
            )

        if 'check_admin_referer' in ''.join([code] + [(c.get('code') or '') for c in context]):
            return TriageDecision(
                classification='False Positive',
                confidence='medium',
                rationale='Nonce verification is present in the nearby control flow; remaining risk depends on usage of the value.',
            )

        return TriageDecision(
            classification='Needs Review',
            confidence='medium',
            rationale='Superglobal value is read directly; verify sanitization/validation happens before use in sensitive sinks.',
        )

    # --- REST pagination guard: often policy-driven; many routes are non-list endpoints.
    if fid == 'rest-no-pagination':
        # If it looks like a single-item or action endpoint, treat as FP-ish.
        if '/(?P<id>' in code or 'CREATABLE' in ''.join([code] + [(c.get('code') or '') for c in context]):
            return TriageDecision(
                classification='False Positive',
                confidence='medium',
                rationale='Endpoint appears to be a single-resource/action route, not a list endpoint; pagination guards are less applicable.',
            )
        return TriageDecision(
            classification='Needs Review',
            confidence='medium',
            rationale='Check whether this endpoint returns unbounded lists; if so add per_page/limit constraints.',
        )

    # --- WPDB prepare: can be fine when no user input is interpolated, but still best practice.
    if fid == 'wpdb-query-no-prepare':
        if 'SELECT FOUND_ROWS()' in code:
            return TriageDecision(
                classification='False Positive',
                confidence='high',
                rationale='`SELECT FOUND_ROWS()` contains no external inputs; prepare() is not necessary for a constant query.',
            )
        if 'TRUNCATE TABLE' in code:
            return TriageDecision(
                classification='Needs Review',
                confidence='medium',
                rationale='TRUNCATE with interpolated table name can be safe if table name is internal/validated; confirm it is not user-controlled.',
            )
        return TriageDecision(
            classification='Needs Review',
            confidence='medium',
            rationale='Direct SQL query detected; verify no untrusted input is interpolated and prefer $wpdb->prepare() where applicable.',
        )

    # --- Missing cap check: many are not sinks; capability may be in menu registration args.
    if fid == 'spo-004-missing-cap-check':
        # If registering menu pages with explicit capability param, treat as FP-ish.
        if 'add_menu_page' in code or 'add_submenu_page' in code:
            return TriageDecision(
                classification='False Positive',
                confidence='medium',
                rationale='Menu registration typically includes a capability argument; confirm the capability is specified and appropriate.',
            )
        # admin_notices etc: often safe, but could leak if content shows data.
        return TriageDecision(
            classification='Needs Review',
            confidence='medium',
            rationale='Heuristic check: confirm this admin hook/output is gated by capability or only displays non-sensitive content.',
        )

    # --- JS polling: could be acceptable if it checks focus/background.
    if fid == 'ajax-polling-unbounded':
        if 'isFocused' in ''.join([code] + [(c.get('code') or '') for c in context]):
            return TriageDecision(
                classification='False Positive',
                confidence='medium',
                rationale='Polling is gated by focus/background checks; confirm interval duration and server-side throttling.',
            )
        if vendor or minified:
            return TriageDecision(
                classification='Needs Review',
                confidence='low',
                rationale='Bundled/minified code; verify interval duration and whether it can cause excessive server load.',
            )
        return TriageDecision(
            classification='Needs Review',
            confidence='medium',
            rationale='setInterval polling detected; verify interval, cancelation, and server-side rate limiting/caching.',
        )

    # --- Unbounded WP_Query/get_posts: may be mitigated with fields => ids.
    if fid == 'wp-query-unbounded':
        ctx = ''.join([code] + [(c.get('code') or '') for c in context])
        if "'fields' => 'ids'" in ctx or 'fields=>\"ids\"' in ctx:
            return TriageDecision(
                classification='False Positive',
                confidence='medium',
                rationale='Query is unbounded but appears to be IDs-only; confirm the dataset is bounded by post_type/status and used in admin/CLI context.',
            )
        return TriageDecision(
            classification='Needs Review',
            confidence='medium',
            rationale='Unbounded posts_per_page detected; consider batching/pagination or bounding by date/status and cache results.',
        )

    # --- HTTP no timeout: generally real, but WordPress has defaults; still best practice.
    if fid == 'http-no-timeout':
        return TriageDecision(
            classification='Confirmed',
            confidence='medium',
            rationale='Remote requests should pass an explicit timeout to avoid long hangs under network issues.',
        )

    # Default: do not triage.
    return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('json_path', type=Path)
    ap.add_argument('--max-findings', type=int, default=200, help='Max findings to triage (keeps report manageable).')
    args = ap.parse_args()

    print(f"[AI Triage] Reading JSON log: {args.json_path}", file=sys.stderr)
    data = json.loads(args.json_path.read_text(encoding='utf-8'))
    findings: List[Dict[str, Any]] = data.get('findings') or []
    print(f"[AI Triage] Total findings in log: {len(findings)}", file=sys.stderr)
    print(f"[AI Triage] Max findings to review: {args.max_findings}", file=sys.stderr)

    triaged_items: List[Dict[str, Any]] = []
    counts = Counter()
    confidences = Counter()

    reviewed = 0

    for f in findings:
        if reviewed >= args.max_findings:
            break

        decision = classify_finding(f)
        if decision is None:
            continue

        reviewed += 1
        counts[decision.classification] += 1
        confidences[decision.confidence] += 1

        triaged_items.append(
            {
                'finding_key': {
                    'id': f.get('id'),
                    'file': f.get('file'),
                    'line': f.get('line'),
                },
                'classification': decision.classification,
                'confidence': decision.confidence,
                'rationale': decision.rationale,
            }
        )

    print(f"[AI Triage] Findings reviewed: {reviewed}", file=sys.stderr)

    # Infer overall confidence from distribution.
    overall_conf = 'medium'
    if reviewed:
        high_ratio = confidences['high'] / reviewed
        low_ratio = confidences['low'] / reviewed
        if high_ratio >= 0.6 and low_ratio <= 0.15:
            overall_conf = 'high'
        elif low_ratio >= 0.4:
            overall_conf = 'low'

    print(f"[AI Triage] Classification breakdown:", file=sys.stderr)
    print(f"  - Confirmed Issues: {counts.get('Confirmed', 0)}", file=sys.stderr)
    print(f"  - False Positives: {counts.get('False Positive', 0)}", file=sys.stderr)
    print(f"  - Needs Review: {counts.get('Needs Review', 0)}", file=sys.stderr)
    print(f"[AI Triage] Overall confidence: {overall_conf}", file=sys.stderr)

    # Minimal executive summary tailored to what we actually observed in the triaged sample.
    narrative_parts: List[str] = []
    narrative_parts.append(
        "This Phase 2 triage pass reviews a subset of findings to separate likely true issues from policy/heuristic noise (especially in vendored/minified assets)."
    )

    # Derive which high-priority categories were actually seen in the triaged sample.
    has_debugger = any(
        (item.get('finding_key') or {}).get('id') == 'spo-001-debug-code'
        for item in triaged_items
    )
    has_http_timeout = any(
        (item.get('finding_key') or {}).get('id') == 'http-no-timeout'
        for item in triaged_items
    )
    has_rest_pagination = any(
        (item.get('finding_key') or {}).get('id') == 'rest-no-pagination'
        for item in triaged_items
    )
    has_superglobals = any(
        (item.get('finding_key') or {}).get('id') in ('spo-002-superglobals', 'unsanitized-superglobal-read')
        for item in triaged_items
    )

    key_items = []
    if has_debugger:
        key_items.append("shipped `debugger;` statements in JS assets")
    if has_http_timeout:
        key_items.append("remote HTTP requests without explicit timeouts")
    if has_rest_pagination:
        key_items.append("REST endpoints missing explicit pagination/limits")
    if has_superglobals:
        key_items.append("direct or unsanitized superglobal access")

    if key_items:
        if len(key_items) == 1:
            key_summary = key_items[0]
        else:
            key_summary = ", ".join(key_items[:-1]) + f" and {key_items[-1]}"
        narrative_parts.append(
            f"Key confirmed or high-signal items in the reviewed set include {key_summary}."
        )
    else:
        narrative_parts.append(
            "In this sampled set, no debugger statements, missing HTTP timeouts, REST pagination, or superglobal patterns were confirmed; most findings remain heuristic or require case-by-case review."
        )

    narrative_parts.append(
        "A large portion of findings often come from bundled/minified JavaScript or third-party libraries; these are difficult to validate from pattern matching alone and are therefore marked as Needs Review unless a clear mitigation is visible (e.g., regex escaping before `new RegExp()`)."
    )

    recommendations: List[str] = []

    if has_debugger:
        recommendations.append(
            'Remove/strip `debugger;` statements from shipped JS assets (or upgrade/patch the vendored library that contains them).'
        )
    if has_http_timeout:
        recommendations.append(
            'Add explicit `timeout` arguments to `wp_remote_get/wp_remote_post/wp_remote_request` calls where missing.'
        )
    if has_rest_pagination:
        recommendations.append(
            'For REST endpoints, confirm which routes return potentially large collections; add `per_page`/limit constraints there (action/single-item routes may not need pagination).'
        )
    if has_superglobals:
        recommendations.append(
            'For superglobal reads, ensure values are validated/sanitized before use and that nonce/capability checks exist on the request path.'
        )

    if not recommendations:
        recommendations.append(
            'Review the flagged findings in context and decide which ones to fix versus baseline, focusing first on CRITICAL-impact performance and security patterns.'
        )

    data['ai_triage'] = {
        'performed': True,
        'status': 'complete',
        'timestamp': datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z'),
        'version': '1.1',
        'scope': {
            'max_findings_reviewed': args.max_findings,
            'findings_reviewed': reviewed,
        },
        'summary': {
            'findings_reviewed': reviewed,  # Duplicated for convenience/back-compat
            'confirmed_issues': counts.get('Confirmed', 0),
            'false_positives': counts.get('False Positive', 0),
            'needs_review': counts.get('Needs Review', 0),
            'confidence_level': overall_conf,
        },
        'narrative': '\n\n'.join(narrative_parts),
        'recommendations': recommendations,
        'triaged_findings': triaged_items,
    }

    print(f"[AI Triage] Writing updated JSON to: {args.json_path}", file=sys.stderr)
    args.json_path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')

    # Verify write was successful
    file_size = args.json_path.stat().st_size
    print(f"[AI Triage] ✅ Successfully wrote {file_size:,} bytes", file=sys.stderr)
    print(f"[AI Triage] Triage data injected with {len(triaged_items)} triaged findings", file=sys.stderr)

    # Post-write verification: re-open and assert ai_triage exists
    print(f"[AI Triage] Verifying write integrity...", file=sys.stderr)
    try:
        verification_data = json.loads(args.json_path.read_text(encoding='utf-8'))

        # Check that ai_triage key exists
        if 'ai_triage' not in verification_data:
            print(f"[AI Triage] ❌ VERIFICATION FAILED: 'ai_triage' key not found in written JSON", file=sys.stderr)
            return 1

        # Check that ai_triage.performed is True
        if not verification_data.get('ai_triage', {}).get('performed'):
            print(f"[AI Triage] ❌ VERIFICATION FAILED: 'ai_triage.performed' is not True", file=sys.stderr)
            return 1

        # Check that triaged_findings count matches
        written_count = len(verification_data.get('ai_triage', {}).get('triaged_findings', []))
        if written_count != len(triaged_items):
            print(f"[AI Triage] ❌ VERIFICATION FAILED: Expected {len(triaged_items)} triaged findings, found {written_count}", file=sys.stderr)
            return 1

        # Check that summary exists and has expected keys
        summary = verification_data.get('ai_triage', {}).get('summary', {})
        required_keys = ['findings_reviewed', 'confirmed_issues', 'false_positives', 'needs_review', 'confidence_level']
        missing_keys = [k for k in required_keys if k not in summary]
        if missing_keys:
            print(f"[AI Triage] ❌ VERIFICATION FAILED: Missing summary keys: {missing_keys}", file=sys.stderr)
            return 1

        print(f"[AI Triage] ✅ Verification passed: ai_triage data is intact", file=sys.stderr)
        print(f"[AI Triage] ✅ Confirmed {written_count} triaged findings persisted", file=sys.stderr)

    except json.JSONDecodeError as e:
        print(f"[AI Triage] ❌ VERIFICATION FAILED: Written JSON is invalid: {e}", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"[AI Triage] ❌ VERIFICATION FAILED: Unexpected error: {e}", file=sys.stderr)
        return 1

    return 0


if __name__ == '__main__':
    raise SystemExit(main())
