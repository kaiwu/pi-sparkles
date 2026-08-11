# pi_sparkles_sec_ownership

Tier coverage: **ProductUseful T2** · package behavior is promoted and verified only through the complete tier

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 41](../../../trading-course/sessions/41_market_structure_source_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 11](../../../trading-course/sessions/11_cg_market_data_20260807.md) and the existing `finance_sec`/`sec_edgar` contracts.

## Reviewed first slice

Decode exact Schedule 13D/G and 13F filing metadata and reported holdings/ownership facts. Preserve filer/issuer/CIK/accession/form/amendment identity, reporting/filing dates, voting/investment authority, security/CUSIP/share quantities/value lexemes, ownership percentages/denominators when stated, source documents, duplicates and correction lineage.

Filing families and reporting lags remain distinct. Entity/security mapping requires evidence; amended filings never overwrite originals. Bounded SEC acquisition follows identified read-only pacing and fixture-tested decoding.

## Explicit exclusions

No current ownership inference, beneficial-owner equivalence across filers, complete portfolio claim, institutional sentiment, governance/control judgment, recommendation, or trade action.

## Implemented T2 import path

The package now exposes `sec_ownership_filings` and `sec_ownership_record`. Both use the
shared versioned `sec_ownership_v1` evidence packet through a caller-selected
regular UTF-8 file, an exact expected SHA-256, and an explicit 1–5,000,000 byte
budget. The import adapter rejects symlinks, truncation, invalid UTF-8,
cancellation, and missing files. The pure contract enforces track
`us`, exact MIC scope, record kinds and required fields, typed
information states, duplicate rejection, correction lineage, omissions,
stable paging, compact summaries, and full record drill-down. It never reads
credential values, searches directories, selects a source, or makes a market
or investment judgment.
