# pi_sparkles_stock_factor_lab

Status: **Tier 4 ProductUseful** · single-factor research implementation

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 42](../../../trading-course/sessions/42_research_portfolio_monitoring_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 28](../../../trading-course/sessions/28_quant_event_study_factor_contract_20260811.md).

## Reviewed first slice

The plugin executes an exact caller-supplied factor definition over point-in-time universe and dataset manifests. Definitions bind source fields, transformations, lag/knowledge cutoff, missing-data policy, rebalance calendar, bucket construction, weighting, return horizon, currency and track scope.

Outputs retain per-period membership and bucket assignments, exposures/returns, missing/delisted/suspended facts, requested regressions/correlations/statistics, transformation leaves, trial identity, and definition/run receipts. Cross-sectional and time-series scopes are distinct. Multi-track inputs remain separately labelled and require explicit FX/alignment policies.

Pure modules compose `finance_series`, `finance_math`, and `finance_replay`; no provider fetch, hidden cache, randomness, or parameter search occurs in the shell.

## Explicit exclusions

No factor discovery, default winsorization/neutralization/buckets, multi-factor optimizer, portfolio construction, edge/robustness/significance/deployability verdict, backtest selection, forecast, recommendation, or trade action.

The `stock_factor_lab` Pi tool reads one bounded content-hashed JSON packet;
the shared pure `finance_quant` core verifies canonical point-in-time manifests
and performs bucket, return, IC, turnover, and cumulative-path calculations.
