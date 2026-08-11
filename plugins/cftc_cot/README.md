# pi_sparkles_cftc_cot

Status: **Designing** · public-source adapter pending · no package manifest or code

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 43](../../../trading-course/sessions/43_multi_asset_macro_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 37](../../../trading-course/sessions/37_commodity_futures_cot_contract_20260811.md).

## Reviewed first slice

Tools retrieve legacy or disaggregated CFTC reports for exact market/report/date identity, inspect category positions, and calculate requested net/change/share, percentile, or z-score facts over explicit windows.

Reports retain futures-only/combined scope, market code/name, report and release dates, category taxonomy/version, long/short/spreading/open-interest lexemes, suppressed/revised states, source receipt and publication lag. Crosswalks from a CFTC market to tradable contracts remain sourced, one-to-many and uncertain; they never imply exact equivalence.

Parsing and calculations are pure after a bounded CFTC text/PDF adapter. Percentiles/z-scores expose population/window/missing policy and remain unperformed when suppressed operands are required.

## Gates and exclusions

Source format/coverage and rights must be reviewed. No crowded/extreme/bullish/bearish label, positioning signal, inferred hedger/speculator intent, exact-contract equivalence, recommendation, or trade action.
