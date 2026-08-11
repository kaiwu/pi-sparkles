# pi_sparkles_earnings_release

Status: **Designing** · provider/licence gated · no package manifest or code

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 42](../../../trading-course/sessions/42_research_portfolio_monitoring_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 30](../../../trading-course/sessions/30_filing_earnings_company_intelligence_contract_20260811.md).

## Reviewed first slice

Tools inspect/list exact issuer earnings releases, enumerate disclosed non-GAAP metrics and reconciliations, and compare release metrics with an explicitly linked filing. Release identity retains issuer, period, publication/retrieval times, language, source document/exhibit, amendment/correction, filing link, licence and content receipt.

Every metric preserves the exact label/lexeme/unit/period/scope and separates company-defined non-GAAP figures from filed GAAP facts. Comparisons require exact identity, period and unit coherence and expose both source leaves, differences, omissions and conflicts.

Adapters must retrieve bounded licensed documents through shared HTTP/attachment contracts; parsing and comparison remain pure and fixture-tested.

## Gates and exclusions

Source/licence and document coverage remain external. No marketing claim treated as GAAP, hidden normalization, earnings quality/materiality/surprise judgment, sentiment, forecast, recommendation, or trade action.
