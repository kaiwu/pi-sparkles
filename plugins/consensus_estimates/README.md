# pi_sparkles_consensus_estimates

Tier coverage: **ProductUseful T2** · package behavior is promoted and verified only through the complete tier

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 42](../../../trading-course/sessions/42_research_portfolio_monitoring_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 30](../../../trading-course/sessions/30_filing_earnings_company_intelligence_contract_20260811.md).

## Reviewed first slice

Tools list exact contributor/vendor estimates, construct an as-of consensus snapshot under a caller-selected statistic/cohort, track one contributor's revisions, and calculate surprise only under an explicit actual/estimate policy.

Every estimate retains issuer, contributor or anonymized vendor identity, metric/definition, unit/currency, fiscal period/end, estimate/as-of/publication times, statistic/population, inclusion rules, licence and receipt. Amendments, stale vintages, duplicates and contributor changes remain separate. Surprise proves exact metric, unit and period coherence and exposes both source candidates.

The pure core performs cohort/statistic/revision arithmetic; the adapter handles bounded licensed acquisition and never exposes forbidden contributor data.

## Gates and exclusions

Blocked on licensed estimates and redistribution terms. No hidden cohort/default consensus, analyst quality/rank, forecast reliability, beat/miss significance, target price, recommendation, or trade action.

## Implemented T2 calculation path

`consensus_estimate_calculation` reads one versioned `consensus_estimates_v1` request from a
caller-owned regular UTF-8 file under an exact SHA-256 and explicit byte budget.
It accepts only `mean`, `difference`, `percent_change`
and retains exact decimal lexemes, separately labelled market legs, MICs,
units/currencies, periods, accession/taxonomy/tag contexts, source receipts,
caller assumptions, expression trees, output scale and rounding. Wrong tracks,
contexts or units, duplicate/missing operands, zero denominators, invalid
decimals and unsupported operations fail closed. The result is a mechanical
calculation receipt, never a score, base case, fair-value label,
recommendation, or trade decision.
