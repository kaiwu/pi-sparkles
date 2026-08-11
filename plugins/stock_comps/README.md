# pi_sparkles_stock_comps

Status: **Designing** · requirements only · no package manifest or code

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 42](../../../trading-course/sessions/42_research_portfolio_monitoring_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 26](../../../trading-course/sessions/26_peer_valuation_industry_research_contract_20260811.md).

## Reviewed first slice

`inspect_comparable_table` consumes an exact caller-approved peer-set receipt and requested multiple definitions. It proves company/listing identity, enterprise/equity basis, taxonomy/tag, unit/currency, fiscal period, filing precedence, share class, and denominator coherence before calculating EV/Revenue, EV/EBITDA, P/E, P/B, dividend yield, or another explicitly defined ratio.

Outputs retain numerator/denominator leaves, expression trees, unperformed reasons, coherence facts, per-company rows, and only caller-requested statistics with population and ordering. Alternative filings, duplicates, negative/zero denominators, and unavailable inputs remain explicit.

The calculation core composes `finance_math` and resolved fundamental candidates; the shell neither fetches data nor converts currencies unless an explicit FX receipt and policy are supplied.

## Explicit exclusions

No peer selection, hidden normalization, default statistic, silent exclusion of negative multiples, fair-value inference, good/bad comparability label, recommendation, or target price.
