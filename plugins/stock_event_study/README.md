# pi_sparkles_stock_event_study

Status: **Tier 4 ProductUseful** · calculation implementation

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 42](../../../trading-course/sessions/42_research_portfolio_monitoring_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 28](../../../trading-course/sessions/28_quant_event_study_factor_contract_20260811.md).

## Reviewed first slice

The plugin binds exact event identities, point-in-time universe/data manifests, estimation/event windows, session calendars, return kind, and a caller-selected abnormal-return model. It calculates security/benchmark returns, expected and abnormal returns, CAR/AAR, cross-event aggregates, and only explicitly requested uncertainty or multiple-testing adjustments.

Each event result preserves cluster/duplicate policy, missing-session and delisting facts, model coefficients and estimation sample, ordered formulas, every source receipt, trial-ledger identity, unperformed reasons, and a non-self-referential content hash. Events from different tracks retain separate calendar legs.

The core composes `finance_series`, `finance_math`, and `finance_replay`; the Pi shell performs bounded decode/encode and cancellation, not data discovery or study design.

## Explicit exclusions

No event selection, causal attribution, expected-impact label, significance threshold, p-hacking verdict, edge/robustness/deployability claim, prediction, recommendation, or portfolio construction.

The `stock_event_study` Pi tool reads one bounded content-hashed JSON packet;
the shared pure `finance_quant` core verifies the replay manifests and performs
the return, model, abnormal-return, CAR/AAR, and requested-statistic laws.
