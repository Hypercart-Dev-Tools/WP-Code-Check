# License Audit – WP Code Check

## Scope
- Reviewed Apache 2.0 grant in `LICENSE`, dual-license positioning in `LICENSE-SUMMARY.md`, commercial license terms in `LICENSE-COMMERCIAL.md`, contributor flow in `CONTRIBUTING.md`, and contributor agreements in `CLA.md` and `CLA-CORPORATE.md`.

## Compatibility Assessment
- **Apache 2.0 remains the governing open-source license.** The root `LICENSE` file is the unmodified Apache 2.0 text, preserving patent grants and outbound licensing consistent with the project’s stated open-source posture.
- **Contributor agreements enable dual licensing.** Both individual and corporate CLAs explicitly grant Hypercart the right to sublicense Contributions under Apache 2.0 and commercial terms, keeping inbound rights compatible with the outbound Apache license while permitting commercial relicensing.
- **Commercial license is additive, not restrictive.** The commercial license document positions premium features and support without limiting the Apache 2.0 rights for the core code, maintaining a clean separation between community and paid offerings.

## Recommendations (triaged)
| ID | Recommendation | Priority | Severity | Rationale | Status |
| --- | --- | --- | --- | --- | --- |
| R1 | Enforce CLA signature verification for all inbound Contributions before merge (e.g., checklist or bot gate) to preserve the ability to dual-license contributions commercially. | P1 | High | Without consistent CLA capture, commercial sublicensing rights for third-party code could be challenged, creating licensing uncertainty. | Pending |
| R2 | Add a short statement in `LICENSE-COMMERCIAL.md` explicitly affirming that Apache 2.0 rights remain unaffected for the community distribution, to preempt confusion between free and paid terms. | P3 | Low | Clarifies that commercial terms are optional and non-restrictive, reducing downstream misinterpretation risk. | Pending |
| R3 | Maintain a lightweight ledger of third-party dependencies (if added later) with their licenses to ensure only Apache-compatible assets are shipped in both distributions. | P2 | Medium | Proactive dependency tracking prevents accidental inclusion of GPL-incompatible code that could undermine dual-licensing. | Pending |

## Conclusion
- No blocking compatibility issues were identified between the Apache 2.0 license, contributor agreements, and the commercial licensing model. The project can continue dual licensing as structured, provided the above operational safeguards are implemented.
