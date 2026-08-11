# pi_sparkles_cn_stock_connect

Tier coverage: **ProductUseful T2** · package behavior is promoted and verified only through the complete tier

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 41](../../../trading-course/sessions/41_market_structure_source_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 11](../../../trading-course/sessions/11_cg_market_data_20260807.md).

## Reviewed first slice

Return mainland-side Stock Connect listing eligibility, buy-only/sell-only/ineligible/unknown state, effective dates, calendars and published quota facts for exact SSE/SZSE listing identities. Preserve program/direction, source authority, publication/retrieval times, changes/corrections, coverage and receipts.

The CN leg remains independent of `pi_hk_stock_connect`; no shared mutable state or cross-track relabelling occurs. Eligibility cannot be inferred from index membership, ticker or historical state, and broker/account permission is separate.

## Explicit exclusions

No order eligibility guarantee, quota forecast, preferred market/share class, A/H comparison, recommendation, or execution.

## Implemented T2 import path

The package now exposes `cn_stock_connect` and `cn_stock_connect_record`. Both use the
shared versioned `cn_stock_connect_v1` evidence packet through a caller-selected
regular UTF-8 file, an exact expected SHA-256, and an explicit 1–5,000,000 byte
budget. The import adapter rejects symlinks, truncation, invalid UTF-8,
cancellation, and missing files. The pure contract enforces track
`cn`, exact MIC scope, record kinds and required fields, typed
information states, duplicate rejection, correction lineage, omissions,
stable paging, compact summaries, and full record drill-down. It never reads
credential values, searches directories, selects a source, or makes a market
or investment judgment.
