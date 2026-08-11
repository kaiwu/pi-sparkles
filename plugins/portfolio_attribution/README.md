# pi_sparkles_portfolio_attribution

Status: **Designing** · requirements only · no package manifest or code

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 42](../../../trading-course/sessions/42_research_portfolio_monitoring_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 24](../../../trading-course/sessions/24_cg_portfolio_full_review_contract_20260811.md).

## Reviewed first slice

The plugin calculates caller-selected Brinson, holdings-based, and currency attribution over an exact portfolio snapshot and benchmark receipt. Proposed tools are `attribution_brinson`, `attribution_holdings`, and `attribution_currency`.

Inputs retain portfolio/benchmark identities, period boundaries, weights, returns, group mappings, currencies, FX receipts, cash flows, and corporate-action treatment. Outputs expose allocation, selection, interaction, currency and cash terms when requested; per-group or per-position contributions; unmapped facts; the exact formula/intermediates; and an explicit reconciliation delta.

## Laws and boundaries

- The caller selects the benchmark, grouping, attribution variant, period, and FX policy. The plugin never supplies a default.
- Period, identity, unit, and currency coherence are proved before calculation; an incompatible leg is unperformed without discarding independent results.
- Residuals and missing benchmark facts remain visible and are never silently distributed.
- A pure `finance_portfolio_attribution` core composes `finance_core` and `finance_math`; the Pi shell remains a decode/encode boundary with no acquisition or storage.

Acceptance covers complete and partial Brinson, holdings and currency cases, unmapped positions, zero denominators, reconciliation, duplicate/conflicting facts, exact receipts, and compact drill-down.

## Explicit exclusions

No benchmark or method selection, performance grade, good/bad contribution label, causal explanation, forecast, recommendation, optimization, or trading action.
