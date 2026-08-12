# finance_portfolio_review

Pure exact-decimal mechanics shared by the Tier 3 portfolio scenario,
attribution, rebalance, and tax-lot shells. Inputs are versioned,
content-bound caller or upstream-receipt packets. The core retains separately
labelled `cn`, `hk`, and `us` legs, explicit FX operands, source receipt hashes,
formula/version labels, assumptions, reconciliation deltas, and unperformed or
infeasible facts.

The package implements caller-defined price scenarios, Brinson attribution,
continuous and caller-grid rebalance deltas, and lot cost/gain/holding-period
arithmetic. It does not select scenarios, benchmarks, targets, constraints,
lots, tax rules, recommendations, orders, probabilities, or judgments.
