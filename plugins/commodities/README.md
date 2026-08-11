# pi_sparkles_commodities

Status: **Designing** · exchange-data gated · no package manifest or code

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 43](../../../trading-course/sessions/43_multi_asset_macro_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 37](../../../trading-course/sessions/37_commodity_futures_cot_contract_20260811.md).

## Reviewed first slice

For one reviewed X-CBT agricultural product/provider, tools inspect exact contract specifications and observations, construct an as-of futures curve, calculate calendar/inter-commodity spreads, and build a rolled series only under a caller-selected named roll method and parameters.

Contract identity retains exchange/product/month/year, delivery/settlement type, multiplier/unit/currency, tick, first/last trade, notice/delivery dates and session/calendar. Price/settle/volume/OI facts preserve source kind/time and gaps. Every roll exposes source contracts, switch dates, adjustment formula, discontinuities and a receipt; no anonymous “continuous contract” exists.

Pure domain modules own curve/spread/roll arithmetic. The adapter is licensed, bounded, cancellable, paced and fixture-tested.

## Gates and exclusions

Requires exchange/provider rights. No implicit roll, curve fitting, seasonality/storage/convenience-yield inference, backwardation/contango/carry attractiveness label, price forecast, recommendation, or order action.
