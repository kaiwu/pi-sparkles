# pi_sparkles_sec_ownership

Status: **Designing** · SEC decode slice · no package manifest or code

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 41](../../../trading-course/sessions/41_market_structure_source_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 11](../../../trading-course/sessions/11_cg_market_data_20260807.md) and the existing `finance_sec`/`sec_edgar` contracts.

## Reviewed first slice

Decode exact Schedule 13D/G and 13F filing metadata and reported holdings/ownership facts. Preserve filer/issuer/CIK/accession/form/amendment identity, reporting/filing dates, voting/investment authority, security/CUSIP/share quantities/value lexemes, ownership percentages/denominators when stated, source documents, duplicates and correction lineage.

Filing families and reporting lags remain distinct. Entity/security mapping requires evidence; amended filings never overwrite originals. Bounded SEC acquisition follows identified read-only pacing and fixture-tested decoding.

## Explicit exclusions

No current ownership inference, beneficial-owner equivalence across filers, complete portfolio claim, institutional sentiment, governance/control judgment, recommendation, or trade action.
