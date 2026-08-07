# finance_indicators

Experimental, provider-neutral Gleam calculations for the first resolved
`CG-TECH` slice. The package is a pure functional core: it imports no Pi API,
performs no network or storage effects, and does not choose an indicator,
parameter, source, price basis, gap treatment, rounding policy, interpretation,
or next action.

The initial slice implements:

- `sma_v1` over the explicitly selected `slot_window_v1` observation window;
- `rsi_wilder_v1` with explicit period, zero/zero convention, parseable-value
  policy, gap stop/reseed policy, and per-step decimal precision;
- `atr_wilder_v1` with `tr_first_hl_v1`, explicit gap stop/reseed policy, and
  exposed true-range components;
- canonical request receipts and semantic-result envelopes whose SHA-256 hash
  excludes the stored hash field;
- immutable ordered input lexemes, adjustment basis, unit facts, evidence
  roots, unknowns, conflicts, decode failures, failed mechanical checks,
  unperformed dates, intermediate values, and available drill-down operations.

`finance_ohlcv` fact states can be adapted without collapsing unavailable or
conflicting evidence. Parseable values that failed a mechanical predicate are
used or excluded only according to the request. A requested raw calculation
may retain an unknown unit; the package does not turn that fact into a
professional sufficiency verdict.

Only explicitly requested `summary_fields` are bound into a request receipt.
This library returns calculated and unperformed expressions, never readiness,
setup, signal, candidate, recommendation, or trade decisions. The LLM owns all
such decisions.

Run the focused suite with:

```sh
bun run test:unit -- finance_indicators
```

The 18 offline tests cover formula fixtures, warm-up omissions, missing middle
slots, recursive gap policies, zero/zero RSI, failed mechanical-check policy,
unknown units, input ordering, source correction, adjustment-basis binding,
requested summaries, and receipt integrity/determinism.

EMA/MACD, Bollinger, KD, volume relations, other rolling/gap variants,
incremental execution traces, and technical primitives remain incremental.
Their absence does not authorize a plugin-owned fallback or decision.
