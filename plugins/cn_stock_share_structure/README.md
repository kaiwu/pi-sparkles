# pi_sparkles_cn_stock_share_structure

Tier coverage: **ProductUseful T2** · package behavior is promoted and verified only through the complete tier

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 41](../../../trading-course/sessions/41_market_structure_source_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 11](../../../trading-course/sessions/11_cg_market_data_20260807.md).

## Reviewed first slice

Return dated total, issued, tradable, restricted and A/B/H or other disclosed share-class quantities for one exact CN issuer/listing. Preserve denominator/type labels, quantities/units/lexemes, effective/report/publication/retrieval dates, source document, corrections, conflicts and receipts.

Different denominator scopes and dates never collapse. Issuer-level capital and listing-level float remain distinct; totals are reconciled only when exact components share scope/date/unit. Missing classes or source coverage remain unknown.

## Explicit exclusions

No inferred free float, market-cap denominator choice, ownership/control conclusion, automatic corporate-action adjustment, recommendation, or trade action.

## Implemented T2 import path

The package now exposes `cn_share_structure` and `cn_share_structure_record`. Both use the
shared versioned `cn_stock_share_structure_v1` evidence packet through a caller-selected
regular UTF-8 file, an exact expected SHA-256, and an explicit 1–5,000,000 byte
budget. The import adapter rejects symlinks, truncation, invalid UTF-8,
cancellation, and missing files. The pure contract enforces track
`cn`, exact MIC scope, record kinds and required fields, typed
information states, duplicate rejection, correction lineage, omissions,
stable paging, compact summaries, and full record drill-down. It never reads
credential values, searches directories, selects a source, or makes a market
or investment judgment.
