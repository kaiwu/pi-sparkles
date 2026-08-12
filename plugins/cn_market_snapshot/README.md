# pi_sparkles_cn_market_snapshot

Status: **Tier 4 ProductUseful** · CN market-packet implementation

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 41](../../../trading-course/sessions/41_market_structure_source_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 11](../../../trading-course/sessions/11_cg_market_data_20260807.md) and the existing `stock_market_snapshot` contract.

## Reviewed first slice

Validate one caller/provider-supplied SSE, SZSE or BSE member packet and calculate exact observed breadth, turnover and caller-defined group summaries using the provider-neutral snapshot engine. Each member retains exact CN listing/MIC/board/share/status identity, current/previous price facts, quantity units, source times, entitlement/licence, coverage and receipts.

Partial/unknown membership, unavailable/conflicting prices, suspensions and duplicate rows remain visible. Limit-up/down or fund-flow facts appear only as exact supplied/source-labelled observations; the plugin never derives them from incomplete prices or labels.

## Explicit exclusions

No source acquisition/fallback, market completion, sector-rotation/fund-flow inference, market strength/mood, ranking, forecast, recommendation, or trade action.

The `cn_market_snapshot` Pi tool reads one bounded, content-hashed caller-owned
JSON packet and delegates all calculations to the shared pure `finance_quant`
core. Cancellation and byte limits are enforced by the import capability.
