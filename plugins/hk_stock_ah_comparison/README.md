# pi_sparkles_hk_stock_ah_comparison

Tier coverage: **ProductUseful T2** · package behavior is promoted and verified only through the complete tier

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 41](../../../trading-course/sessions/41_market_structure_source_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 33](../../../trading-course/sessions/33_hk_stock_track_completion_contract_20260811.md) and comparative laws from [Session 26](../../../trading-course/sessions/26_peer_valuation_industry_research_contract_20260811.md).

## Reviewed first slice

On an explicit request for a specific proven A/H relationship, the plugin compares two independently sourced listing legs. Each leg retains its own `cn` or `hk` track, MIC, board/share class, price kind/time, calendar/session, currency, corporate-action basis, source/rights receipt, unavailable/conflicting states, and correction lineage.

An exact A/H price ratio or premium/discount is calculated only after the caller supplies an FX rate/direction/time policy and coherent price/action bases. Output exposes both legs, FX leaf, time delta, formula, assumptions and unperformed reasons; it never creates a synthetic track or canonical issuer price.

## Gates and exclusions

Implementation waits for a concrete A/H workflow plus sufficient CN/HK identity, pricing, corporate-action and FX evidence. No automatic pair discovery, silent currency/time alignment, fungibility claim, “cheaper”/arbitrage/value judgment, recommendation, or cross-market execution.

## Implemented T2 calculation path

`hk_ah_price_comparison` reads one versioned `hk_stock_ah_comparison_v1` request from a
caller-owned regular UTF-8 file under an exact SHA-256 and explicit byte budget.
It accepts only `premium_discount_fx`
and retains exact decimal lexemes, separately labelled market legs, MICs,
units/currencies, periods, accession/taxonomy/tag contexts, source receipts,
caller assumptions, expression trees, output scale and rounding. Wrong tracks,
contexts or units, duplicate/missing operands, zero denominators, invalid
decimals and unsupported operations fail closed. The result is a mechanical
calculation receipt, never a score, base case, fair-value label,
recommendation, or trade decision.
