# pi_sparkles_company_guidance

Tier coverage: **ProductUseful T2** · package behavior is promoted and verified only through the complete tier

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 42](../../../trading-course/sessions/42_research_portfolio_monitoring_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 30](../../../trading-course/sessions/30_filing_earnings_company_intelligence_contract_20260811.md).

## Reviewed first slice

Tools inspect guidance, list a metric/period timeline, and compare one exact guidance receipt with a resolved actual. A guidance fact retains issuer, source passage/document, stated metric/definition, unit/currency, range/point, period/horizon, qualifiers, issue/withdrawal/revision times, status, prior-guidance link, language and receipt.

History is append-only; narrowed, widened, raised, lowered, reiterated, withdrawn and corrected states are mechanical comparisons only after exact metric/unit/period coherence. Actual comparisons retain both leaves and caller-selected formula.

Parsing/normalization is pure over bounded source spans; acquisition remains provider-specific and licensed.

## Explicit exclusions

No management credibility, likelihood, beat/miss interpretation, implicit guidance inference, forecast extrapolation, confidence/sentiment, recommendation, or investment judgment.

## Implemented T2 calculation path

`company_guidance_compare` reads one versioned `company_guidance_v1` request from a
caller-owned regular UTF-8 file under an exact SHA-256 and explicit byte budget.
It accepts only `difference`, `percent_change`
and retains exact decimal lexemes, separately labelled market legs, MICs,
units/currencies, periods, accession/taxonomy/tag contexts, source receipts,
caller assumptions, expression trees, output scale and rounding. Wrong tracks,
contexts or units, duplicate/missing operands, zero denominators, invalid
decimals and unsupported operations fail closed. The result is a mechanical
calculation receipt, never a score, base case, fair-value label,
recommendation, or trade decision.
