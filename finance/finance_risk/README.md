# finance_risk

Experimental, provider-neutral Gleam calculations for the first resolved
`CG-RISK` slice. The package is a pure functional core: it imports no Pi API,
performs no network or storage effects, and does not select a threshold,
scenario, account field, quantity, lot rule, cost assumption, interpretation,
or next operation.

The initial long-only, completed-daily planning slice implements:

- sourced `Known`, `Unknown`, `NotObtained`, `Conflicting`, and
  `DecodeFailure` facts retaining source kind/reference, effective and
  retrieval times, exact lexeme, currency, unit, scope, and alternatives;
- exact planned-loss and gap-scenario loss per unit, fraction-of-named-basis
  budgets, and loss at an explicitly supplied quantity;
- independent stop-budget, gap-budget, notional, cash/buying-power, and other
  caller-named quantity bounds through the generic bound calculation;
- whole-share and caller-supplied minimum/increment projections, plus an
  intersection only when its exact bound list is requested;
- ordered single-currency `heat_planned_stop_v1` position contributions and a
  requested remaining-budget expression;
- composable rate-of-notional, fixed, and per-share cost components, preserving
  the known subtotal when another component is unavailable;
- canonical request and semantic-result envelopes whose SHA-256 hash excludes
  the stored hash field.

All policies are explicit inputs. The package owns no automatic percentage,
gap, heat, notional, lot, fee, rounding, branch, or summary default. A negative
planned loss, negative remaining budget, zero projected quantity, missing grid,
or failed division remains a mechanical result or unperformed expression. It
never becomes a plan status, selected quantity, recommendation, authorization,
or workflow decision; the LLM owns those decisions.

Market-owned rule packages remain responsible for exact effective lot/tick
facts, account adapters for account and position observations, and later
execution packages for order support and fills. `finance_risk` only consumes
the facts supplied to the requested arithmetic and preserves their provenance.

Run the focused suite with:

```sh
bun run test:unit -- finance_risk
```

The 20 offline tests cover exact and edge-case planned loss, explicit fraction
budgets, CN-style grid projection, alternate policy inputs, independent gap,
notional and cash bounds, unknown grids, requested intersections, zero grid
points, ordered heat decomposition, negative remaining heat, partial costs,
conflicting account facts, receipt content binding/determinism, and forbidden
plugin-verdict language.

Shorts, derivatives, margin maintenance/liquidation, multi-currency portfolio
aggregation, multi-leg scaling, tiered/minimum/capped costs, correlation and
liquidity stress, VaR/CVaR, drawdown schedules, intraday risk, and execution
integration remain incremental.
