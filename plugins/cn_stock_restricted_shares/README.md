# pi_sparkles_cn_stock_restricted_shares

Tier coverage: **ProductUseful T2** · package behavior is promoted and verified only through the complete tier

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 41](../../../trading-course/sessions/41_market_structure_source_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 11](../../../trading-course/sessions/11_cg_market_data_20260807.md).

## Reviewed first slice

Return announced restricted-share unlock events with exact CN listing/share class, eligible holder label, planned/actual unlock quantities and units, denominator/percentage when supplied, restriction reason, announcement/expected/effective/trading dates, conditions, revisions and source receipts.

Planned eligibility, actual release and tradability are distinct states. Missing conditions or schedule changes remain unknown/conflicting; no market impact is inferred. CN calendars/rules are consumed only through exact receipts.

## Explicit exclusions

No supply-pressure or price-impact estimate by default, actual-sale inference, materiality/risk label, notification, recommendation, or trade action.

## Implemented T2 import path

The package now exposes `cn_restricted_shares` and `cn_restricted_share_record`. Both use the
shared versioned `cn_stock_restricted_shares_v1` evidence packet through a caller-selected
regular UTF-8 file, an exact expected SHA-256, and an explicit 1–5,000,000 byte
budget. The import adapter rejects symlinks, truncation, invalid UTF-8,
cancellation, and missing files. The pure contract enforces track
`cn`, exact MIC scope, record kinds and required fields, typed
information states, duplicate rejection, correction lineage, omissions,
stable paging, compact summaries, and full record drill-down. It never reads
credential values, searches directories, selects a source, or makes a market
or investment judgment.
