# pi_sparkles_cn_regulatory

Tier coverage: **ProductUseful T2** · package behavior is promoted and verified only through the complete tier

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 41](../../../trading-course/sessions/41_market_structure_source_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 11](../../../trading-course/sessions/11_cg_market_data_20260807.md).

## Reviewed first slice

Search exact CSRC/SSE/SZSE/BSE rules, inquiry/supervision letters, disciplinary actions and enforcement releases. Results retain authority/publisher role, document/event ID/type, exact issuer/listing subject when stated, original Chinese title, publication/effective/event dates, jurisdiction/scope, status/correction lineage, source/attachment receipt, rights, coverage and unknowns.

Sources remain distinct authorities; entity matching and affected-listing scope require evidence. Bounded source and attachment adapters preserve original language and fail closed on unsupported files.

## Explicit exclusions

No legal interpretation/advice, guilt/materiality/severity judgment, complete enforcement-history claim, inferred affected company, translation presented as original, recommendation, or trade action.

## Implemented T2 import path

The package now exposes `cn_regulatory_documents` and `cn_regulatory_record`. Both use the
shared versioned `cn_regulatory_v1` evidence packet through a caller-selected
regular UTF-8 file, an exact expected SHA-256, and an explicit 1–5,000,000 byte
budget. The import adapter rejects symlinks, truncation, invalid UTF-8,
cancellation, and missing files. The pure contract enforces track
`cn`, exact MIC scope, record kinds and required fields, typed
information states, duplicate rejection, correction lineage, omissions,
stable paging, compact summaries, and full record drill-down. It never reads
credential values, searches directories, selects a source, or makes a market
or investment judgment.
