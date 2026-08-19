# pi_sparkles_cn_market_snapshot

Status: **Tier 4 ProductUseful** · CN market-packet implementation

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 41](../../../trading-course/sessions/41_market_structure_source_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 11](../../../trading-course/sessions/11_cg_market_data_20260807.md) and the existing `stock_market_snapshot` contract.

## Reviewed packet calculation

Validate one caller/provider-supplied SSE, SZSE or BSE member packet and calculate exact observed breadth, turnover and caller-defined group summaries using the provider-neutral snapshot engine. Each member retains exact CN listing/MIC/board/share/status identity, current/previous price facts, quantity units, source times, entitlement/licence, coverage and receipts.

Partial/unknown membership, unavailable/conflicting prices, suspensions and duplicate rows remain visible. Limit-up/down or fund-flow facts appear only as exact supplied/source-labelled observations; the plugin never derives them from incomplete prices or labels.

## Explicit exclusions

The packet calculator performs no source acquisition/fallback, market
completion, sector-rotation/fund-flow inference, market strength/mood, ranking,
forecast, recommendation, or trade action.

The `cn_market_snapshot` Pi tool reads one bounded, content-hashed caller-owned
JSON packet and delegates all calculations to the shared pure `finance_quant`
core. Cancellation and byte limits are enforced by the import capability.

## Acquisition-backed current overview

`cn_market_overview` performs one bounded, non-fallback Eastmoney batch request
for the reviewed 上证指数, 深证成指, 创业板指, 沪深300, and 科创50 identities. It retains
exact JSON numeric lexemes, five benchmark snapshots, provider index-associated
SSE/SZSE advancing/declining/unchanged counts, provider-reported amounts, a
content SHA-256 receipt, retrieval time, rights facts, and typed failures.

This is provider-scoped evidence rather than an exchange-authenticated complete
membership packet. Breadth completeness, amount/volume semantics, provider
timestamp and latency remain unknown. The result explicitly marks intraday
ordering, fund flow, sector rotation, prior-session amount comparison, and BSE
coverage unavailable. It therefore supports an honest current Shanghai/Shenzhen
overview without implying those missing facts or replacing the exact imported
member-packet calculation.

## Composed sector comparison

`cn_sector_series` is the acquisition leg for broad CN industry-sector trend
questions. The caller supplies one date window; the tool performs exactly 11
bounded, paced Eastmoney daily-history requests for the pinned CSI 800
level-one profile. It emits a typed `comparisonInput` plus its content SHA-256,
but performs no return calculation or ranking. The shared calculation-only
`compare_series_returns` tool verifies that handoff and calculates
one-session, five-session, and complete observed-window returns without
network access, provider selection, or universe selection.

The profile follows the pinned CSI methodology's 11-sector projection:
financials (`000974`) and real estate (`399965`) are separate, and the legacy
combined financials-and-real-estate index `000934` is excluded. CSI is the
classification/index authority; Eastmoney remains only the price-observation
vendor. The acquisition result exposes both identities, actual observed dates,
exact closes, individual response hashes, an ordered manifest receipt, and the
provider request count. The calculator separately exposes its formula,
rounding, verified input receipt, and mechanical ordering.

This is a CSI 800 large/mid-cap industry proxy, not every A-share sector,
concept board, or theme. Fund flow, constituent breadth, causal rotation,
AI/theme exposure, confirmed tops, stabilization, and reversals are explicitly
unavailable and must not be inferred from relative price returns.

Cross-track review: the comparison calculator is shared by `cn`, `hk`, and
`us`. The CSI profile remains CN-only because the classification and index
identities are market-owned; no HK or US sector acquisition is inferred from it.
