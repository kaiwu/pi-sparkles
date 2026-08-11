# pi_sparkles_cn_stock_valuation

Tier coverage: **ProductUseful T2** · package behavior is promoted and verified only through the complete tier

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 42](../../../trading-course/sessions/42_research_portfolio_monitoring_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 26](../../../trading-course/sessions/26_peer_valuation_industry_research_contract_20260811.md).

## Reviewed first slice

This is the mainland-owned extension of the `pi_stock_valuation` calculation contract. It requires exact `cn` listing/MIC/board/share-class identity, China GAAP/statement scope, tradable/restricted share denominators, A/B/H relationship receipts, native currency, dated corporate actions, and caller-supplied valuation assumptions.

It calculates only named valuation variants and sensitivity grids, retaining complete source leaves and separately labelled cross-listed legs. Any A/H comparison requires an explicit relationship plus independent prices, currencies, calendars, FX and times. Conflicts or missing restricted-share/capital facts remain visible.

Pure CN modules may compose shared math/evidence but must not import HK/US market domains. Provider acquisition stays outside the first calculation slice.

## Explicit exclusions

No automatic A/H discount, China-GAAP discount, non-tradable-share adjustment, currency default, fair value, target price, base case, peer selection, recommendation, or cross-track collapse.

## Implemented T2 calculation path

`cn_inspect_valuation` reads one versioned `cn_stock_valuation_v1` request from a
caller-owned regular UTF-8 file under an exact SHA-256 and explicit byte budget.
It accepts only `enterprise_to_equity_per_share`
and retains exact decimal lexemes, separately labelled market legs, MICs,
units/currencies, periods, accession/taxonomy/tag contexts, source receipts,
caller assumptions, expression trees, output scale and rounding. Wrong tracks,
contexts or units, duplicate/missing operands, zero denominators, invalid
decimals and unsupported operations fail closed. The result is a mechanical
calculation receipt, never a score, base case, fair-value label,
recommendation, or trade decision.
