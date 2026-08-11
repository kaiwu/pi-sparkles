# pi_sparkles_global_markets

Status: **Designing** · cross-market composition contract · no package manifest or code

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 43](../../../trading-course/sessions/43_multi_asset_macro_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 39](../../../trading-course/sessions/39_macro_fx_global_market_composition_contract_20260811.md).

## Reviewed first slice

Tools define/inspect a view of caller-selected market legs, align them under an explicit policy, and calculate requested normalized comparisons or correlations over an exact window. Each leg retains native `cn`, `hk` or `us` track, instrument/index/ETF/ADR kind, MIC, calendar/session, currency, price/return basis, source times, entitlement and receipt.

Alignment policies such as exact-date intersection or caller-selected as-of join are named and expose matched/unmatched dates and time deltas. FX conversion is a separate evidenced calculation. Indexes, ETFs and ADRs remain non-equivalent; no synthetic global track/calendar or merged source is created.

The pure composition core consumes existing quote/history/index/FX receipts; no direct acquisition or provider fallback occurs.

## Explicit exclusions

No risk-on/off, synchronization/decoupling, capital-flow/contagion/causal claim, diversification judgment, forecast, index-ETF equivalence, recommendation, or trade action.
