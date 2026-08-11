# pi_sparkles_stock_comps

Tier coverage: **ProductUseful T2** · package behavior is promoted and verified only through the complete tier

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 42](../../../trading-course/sessions/42_research_portfolio_monitoring_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 26](../../../trading-course/sessions/26_peer_valuation_industry_research_contract_20260811.md).

## Reviewed first slice

`inspect_comparable_table` consumes an exact caller-approved peer-set receipt and requested multiple definitions. It proves company/listing identity, enterprise/equity basis, taxonomy/tag, unit/currency, fiscal period, filing precedence, share class, and denominator coherence before calculating EV/Revenue, EV/EBITDA, P/E, P/B, dividend yield, or another explicitly defined ratio.

Outputs retain numerator/denominator leaves, expression trees, unperformed reasons, coherence facts, per-company rows, and only caller-requested statistics with population and ordering. Alternative filings, duplicates, negative/zero denominators, and unavailable inputs remain explicit.

The calculation core composes `finance_math` and resolved fundamental candidates; the shell neither fetches data nor converts currencies unless an explicit FX receipt and policy are supplied.

## Explicit exclusions

No peer selection, hidden normalization, default statistic, silent exclusion of negative multiples, fair-value inference, good/bad comparability label, recommendation, or target price.

## Implemented T2 calculation path

`inspect_comparable_table` reads one versioned `stock_comps_v1` request from a
caller-owned regular UTF-8 file under an exact SHA-256 and explicit byte budget.
It accepts only `ratio`
and retains exact decimal lexemes, separately labelled market legs, MICs,
units/currencies, periods, accession/taxonomy/tag contexts, source receipts,
caller assumptions, expression trees, output scale and rounding. Wrong tracks,
contexts or units, duplicate/missing operands, zero denominators, invalid
decimals and unsupported operations fail closed. The result is a mechanical
calculation receipt, never a score, base case, fair-value label,
recommendation, or trade decision.
