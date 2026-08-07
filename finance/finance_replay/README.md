# finance_replay

`finance_replay` is the Experimental provider-neutral functional core for the
resolved `CG-QUANT` shared-replay information contract. It contains no Pi,
Promise, network, filesystem, clock, random, or FFI dependency.

The first completed-daily, long-only cash-equity slice provides:

- exact point-in-time universe and dataset manifests for one explicit `cn`,
  `hk`, or `us` track;
- immutable run definitions joining caller-selected feature, strategy, risk,
  execution, universe, dataset, partition, policy, cutoff, seed, and branch
  receipts;
- caller-declared fixed, expanding, rolling, walk-forward, or arbitrary
  partitions, with mechanical range relations only;
- an ordered replay-event contract that preserves unknown times, corrections,
  omitted feature results, predicate facts, desired instructions, execution
  branches, position facts, benchmarks, and terminal facts;
- a pure idempotent fold, explicit effects, ambiguity facts, batch/incremental
  semantic equivalence, and definition/state-bound checkpoints;
- append-only trial definitions and ledger events retaining completed, failed,
  cancelled, truncated, duplicate, and unperformed outcomes;
- explicitly requested net return, win/loss/tie count, drawdown-series, and
  trade-list calculations with exact operands and method metadata;
- aligned run differences, compact LLM context with stable drill handles, and
  canonical reproduction manifests plus bounded event JSONL round-trips; and
- a deterministic scripted interpreter whose event, byte, elapsed-time,
  session, and cancellation facts are all supplied explicitly.

None of these contracts selects a hypothesis, universe, feature, policy,
parameter, partition, model, branch, benchmark, metric, trial, threshold, or
next operation. They do not label an edge, significance, robustness,
correctness, sufficiency, validity, readiness, or deployability. Plugins expose
the exact information and neutral operations efficiently; the LLM makes every
research and trading decision.

Run the package tests with:

```sh
gleam test
```

The 23 offline tests cover exact wire round-trips, track preservation,
partition relations, idempotency conflicts, deterministic folding, ambiguous
ordering, checkpoint identity, complete trial-status accounting, requested
calculations, comparison, reproduction portability, compact context, budgets,
and cancellation.

