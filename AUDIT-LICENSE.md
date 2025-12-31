# WP Code Check — License Update Audit

Date: 2026-03-07

## Scope

Reviewed the recent licensing updates introducing Contributor License Agreements (CLA and CCLA) and their interaction with the existing Apache 2.0 license and the commercial licensing terms. Source documents reviewed: `LICENSE`, `CLA.md`, `CLA-CORPORATE.md`, `CONTRIBUTING.md`, and `LICENSE-COMMERCIAL.md`.

## Compatibility Assessment

- **Apache 2.0 baseline:** Remains the outbound open-source license for the core project without added restrictions. The CLA/CCLA explicitly allow dual licensing while preserving Apache distribution, which is compatible with Apache’s permissive terms.
- **Contributor inbound rights:** Both CLA variants grant Hypercart broad copyright and patent rights and permit relicensing under Apache 2.0 and commercial terms, addressing the rights needed for dual licensing.
- **Commercial license positioning:** The commercial license is optional and framed as additive; it does not claim to relicense community binaries without meeting Apache conditions, so no direct conflict identified.

## Findings and Recommendations

| Priority | Severity | Finding | Recommendation |
| --- | --- | --- | --- |
| P1 | Medium | **Contributor expectation mismatch.** The CONTRIBUTING guide tells contributors their work “will be licensed under the Apache License 2.0” without also noting the CLA’s explicit multi-license grant, which could surprise contributors even though the CLA text is clear. | Update `CONTRIBUTING.md` to state that contributions are accepted under Apache 2.0 and, per the signed CLA/CCLA, may be redistributed under Apache 2.0 and Hypercart commercial licenses. |
| P2 | Low | **Administrative clarity.** The CLA/CCLA reference submission via comment/email/DocuSign but do not mention where signed agreements are tracked, which could slow verification in compliance reviews. | Add a short note identifying the system of record (e.g., CLA bot/CRM) for signed agreements and how contributors can confirm receipt. |
| P3 | Low | **Terms dependency.** The commercial license references an external Terms of Service URL without summarizing key constraints (governing law, indemnities, warranty disclaimers). Risk is minimal because the commercial path is optional, but linking to non-repo terms can complicate offline audits. | Add a brief summary of key ToS obligations or include a snapshot/version reference in-repo to aid future compliance checks. |

## Conclusion

The new CLA and CCLA are compatible with Apache 2.0 and provide the rights necessary for dual licensing alongside the commercial offering. Addressing the noted transparency and admin-clarity items will reduce contributor friction and simplify compliance reviews.
