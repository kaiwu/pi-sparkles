# finance_execution

Experimental, provider-neutral Gleam information and calculation core for the
bounded execution slice resolved by `CG-DAY` Session 14. The package is pure:
it imports no Pi API, performs no network, clock, storage, credential, or broker
effect, and cannot submit, cancel, or replace an order.

The first long-only cash-equity slice provides:

- exact desired instructions, separately typed from broker encodings, with
  `cn`/`hk`/`us` track, listing, MIC, account, side, intent, decimal quantity,
  order behavior, time-in-force, session/time fields, and receipt references;
- sourced capability and other information states: `Known`, `Unknown`,
  `NotObtained`, `Conflicting`, `DecodeFailure`, and `NotApplicable`;
- mechanical session-window comparisons that return their timestamp,
  intervals, source receipts, and boolean, or an unperformed fact;
- explicit `visible_depth_sweep_v1` calculations over a supplied snapshot,
  side, limit, quantity, price boundary, depth budget, scale, and rounding mode;
- explicit `bar_possible_paths_v1` branches for limit touches and stop/target
  ordering without selecting a branch or claiming that a daily bar proves a
  fill;
- exact fill leaves and requested same-identity/currency/unit/side/kind
  quantity, notional, and VWAP aggregates;
- ordered lifecycle folding that preserves external broker rejection text,
  cancel/fill races, corrections, bust markers, and batch/incremental semantic
  equivalence;
- explicitly requested spread, slippage, implementation-shortfall, partial
  cost, and clock-relation latency calculations;
- bounded canonical request and semantic-result envelopes whose SHA-256 hash
  excludes the stored hash field.

There is no default order behavior, broker transformation, fill model, price,
queue amount, benchmark, fee, latency threshold, rounding rule, branch, or next
operation. Results are labelled `Hypothetical`, `HistoricalReplay`,
`ObservedBrokerReceipt`, `LLMDeclaredScenario`, or `PaperBroker` as applicable.
Unknown depth leaves a numeric requested remainder but does not turn it into a
known non-fill. Broker rejection is quoted as an external fact and is never
converted into advice. The LLM owns every choice, interpretation, correctness
or sufficiency judgment, workflow decision, and trade decision.

Run the focused suite with:

```sh
bun run test:unit -- finance_execution
```

The 24 deterministic offline tests cover information states, desired/capability
separation, visible buy and sell depth sweeps, depth exhaustion, zero-fill VWAP,
daily-bar branches, exact fill lexemes and aggregates, currency isolation,
cancel/fill races, external broker rejection, lifecycle equivalence, session
comparisons, partial costs, signed slippage, clock uncertainty, content-bound
receipts, request/result budgets, and forbidden plugin-decision language.

Top-of-book, sequenced trade-through, declared queue-ahead, intraday-bar,
auction, stop-child, broker-replay correction projections, richer fee schedules,
cross-currency aggregation, provider adapters, `pi_order_simulator`, full day
workflow, and all live mutation remain incremental. Full day-trader acceptance
also remains gated by licensed intraday data, exact track rules,
the still-open full-workflow part of `CG-DAY`, and the later `CG-LIVE`
authorization/security review. The resolved `CG-PSYCHOLOGY` journal-information
slice supplies review records but does not complete that workflow.
