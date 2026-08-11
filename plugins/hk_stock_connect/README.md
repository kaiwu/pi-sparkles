# pi_sparkles_hk_stock_connect

Tier coverage: **ProductUseful T2** · package behavior is promoted and verified only through the complete tier

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 41](../../../trading-course/sessions/41_market_structure_source_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 33](../../../trading-course/sessions/33_hk_stock_track_completion_contract_20260811.md) and Session 11.

## Reviewed first slice

The plugin returns HK-side Stock Connect eligibility and state for an exact XHKG listing: northbound/southbound leg, eligible/buy-only/sell-only/ineligible/unknown status, quota facts where officially published, effective dates, applicable calendars, source authority, corrections and receipts.

Every leg remains separately labelled from the mainland-side `pi_cn_stock_connect` contract. Identity and status cannot be inferred from ticker, index membership or historical eligibility. Conflicting exchanges/sources fail closed; source coverage and query cutoff are visible.

## Gates and exclusions

Requires reviewed HKEX/Connect source and usage rights. No quota availability guarantee, broker/account eligibility, order permission, cross-track state merge, preferred venue/share class, recommendation, or execution.

## Implemented T2 import path

The package now exposes `hk_stock_connect` and `hk_stock_connect_record`. Both use the
shared versioned `hk_stock_connect_v1` evidence packet through a caller-selected
regular UTF-8 file, an exact expected SHA-256, and an explicit 1–5,000,000 byte
budget. The import adapter rejects symlinks, truncation, invalid UTF-8,
cancellation, and missing files. The pure contract enforces track
`hk`, exact MIC scope, record kinds and required fields, typed
information states, duplicate rejection, correction lineage, omissions,
stable paging, compact summaries, and full record drill-down. It never reads
credential values, searches directories, selects a source, or makes a market
or investment judgment.
