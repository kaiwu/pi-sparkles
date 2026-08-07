# finance_strategy

Status: **Experimental — evidence-only CG-SWING daily core** · target:
JavaScript/Bun

`finance_strategy` is a pure, provider-neutral library for presenting a trading
hypothesis and its exact inputs to the LLM in a compact, inspectable, replayable
form. It does not make research or trade decisions. In particular, it never
emits `SetupQualified`, `Accepted`, `Rejected`, a recommendation, an action, or
an aggregate score.

The requirements evidence is trading-course
[Session 10 with the 10A and 10B addenda](../../../trading-course/sessions/10_cg_swing_daily_workflow_20260425.md).
The repository correction that the LLM owns every research and trade decision
is normative. Plugins and finance libraries may validate structure, calculate
explicit formulas, and report evidence compatibility, but their outputs remain
facts for the LLM to interpret.

This package contains no Pi, HTTP, filesystem, ambient clock, storage,
randomness, mutable cache, provider adapter, broker adapter, or JavaScript
business logic.

## Implemented boundary

The first slice supports long-only cash-equity swing evidence on completed
regular-session daily bars for the existing `cn`, `hk`, and `us` tracks:

- immutable strategy identity, version, hypothesis, negative claims, scope,
  parameters, required predicates, optional confirmations/ranking, and
  lifecycle declarations;
- exact listing/session/evaluation-cutoff context;
- upstream dependency readiness that keeps `Declared` separate from verified
  `Ready` evidence;
- feature receipts retaining formula version, parameters, warm-up, input-series
  hash, adjustment basis, unit, known time, source cutoff, observation, and
  ordered evidence roots;
- a compact evidence receipt with per-dependency and per-predicate compatibility,
  definition/input hashes, unmatched inputs, and versioned JSON;
- LLM/user plan declarations with exact price lexemes and an explicitly
  non-executable origin;
- a total workflow-history fold for plan attachment, observed entry/monitor/exit
  prices, expiry, daily stop/target ordering ambiguity, and review notes.

The fold validates event order, identity, definition hash, monotonic time, and
plan immutability. Those are structural laws, not trading decisions. Names such
as `EntryPriceObserved` describe evidence supplied by a provider, import, or
user; they do not claim that this package placed, authorized, simulated, or
authenticated a fill.

## Modules

| Module | Responsibility |
| --- | --- |
| `finance_strategy/definition` | immutable definition data, semantic version, scope, predicates, requirements, lifecycle policy, and canonical hash |
| `finance_strategy/evidence` | typed dependency and feature receipts, caller-declaration separation, validation, and canonical wire values |
| `finance_strategy/receipt` | evidence-only compatibility projection, ordered evidence roots, definition/input hashes, and versioned JSON |
| `finance_strategy/plan` | exact LLM/user plan declaration; never sizing approval or executable order |
| `finance_strategy/transition` | total structural fold over declarations and later observations |
| `finance_strategy/rsi_reversal` | executable data constructor for the reviewed example hypothesis |

There is deliberately no `evaluate` module and no aggregate decision type.
`ObservedTrue`, `ObservedFalse`, and `Unknown` are upstream predicate facts;
`Compatible`, `MissingReceipt`, `KnownAfterCutoff`, `WarmupUnavailable`, and
`UpstreamReadiness` describe whether the LLM can safely interpret those facts.
The library does not collapse them into a conclusion.

## RSI-reversal v1 data

The bundled example declares these required evidence keys:

- point-in-time eligible/liquid universe;
- completed close above the versioned long moving average;
- RSI at or below the declared threshold;
- RSI strictly above its prior-session value;
- completed close within the declared distance of the medium moving average.

Volume and sector/regime values are optional confirmation/ranking facts. The
constructor exposes the parameters and negative claims, including that the
hypothesis has no demonstrated positive expectancy. It consumes upstream
feature receipts and performs no SMA, RSI, volume, universe, or adjustment
calculation.

## Evidence and timing laws

- A symbol alone is never identity; every receipt retains the exact track,
  instrument ID, symbol, MIC, and signal session.
- Planned closures are absent from an ordered trading-session series. No path
  synthesizes prices, returns, or zero volume for a closure, suspension,
  provider omission, or unavailable history.
- Price-dependent feature receipts retain one declared adjustment basis.
  Conflicting bases are exposed as a scope issue, never silently reconciled.
- `Ready` dependencies require both a known time and evidence root. Caller
  statements remain `Declared` and cannot carry evidence roots that make them
  look verified.
- Source cutoffs and known times are compared with the requested evaluation
  cutoff. Late, missing, stale, incomplete, conflicting, unsupported, and
  warm-up-incomplete inputs remain distinct.
- A daily bar that touches both desired stop and target can be recorded as
  `DailyExitOrderingUnknown`; the history never selects a favorable or adverse
  intraday path.
- A gap through a desired stop records the first supported observed price. It
  never rewrites that price to the desired stop.

## Verification

Deterministic offline tests cover:

- definition and input hash determinism and sensitivity;
- compact receipts with no decision/qualification/acceptance field;
- true and false predicate observations without an aggregate conclusion;
- missing optional inputs, stale input, incomplete warm-up, and late dependency
  timing as separate compatibility facts;
- caller declarations never becoming verified dependencies;
- exact JSON round-trip of listing, track, session, cutoff, adjustment basis,
  units, observations, hashes, and ordered evidence roots;
- plan-shape validation without risk or execution acceptance;
- fill-before-plan, context mismatch, backward time, expiry, gap-through-stop,
  and stop/target ambiguity transition laws.

Run:

```sh
bunx gleam test
```

The focused suite has 13 passing tests. The complete repository `bun run test`
suite, including all package checks/tests, architecture/FFI/artifact layers,
plugin builds, and Pi smoke-loads, passed on 2026-08-07.

## Incremental input contracts before breadth

- resolved `CG-MARKET-DATA`, `CG-TECH`, and `CG-RISK` information/calculation
  contracts have initial slices whose provider/variant breadth remains
  incremental;
- the execution-information slice of `CG-DAY` and `finance_execution` provides
  exact selected-model order/fill/cost and capability facts, while the full
  intraday workflow remains open;
- the resolved `CG-PSYCHOLOGY` journal-information contract and
  `finance_journal`/`trade_journal` first slices provide durable event handles,
  attributed declarations, checklist facts, and requested review calculations;
- `CG-QUANT`: backtest protocol and any expectancy or robustness claim.

Coverage gaps constrain which facts can be supplied; they do not authorize a
plugin to take over the LLM's decision or judge correctness.

## Non-goals

- No quote, OHLCV, corporate-action, news, sector, account, or broker fetching.
- No indicator arithmetic, risk sizing, fee table, fill simulation, portfolio
  optimization, prediction, recommendation, or autonomous execution.
- No aggregate strategy state, candidate ranking score, buy/sell claim, plan
  acceptance, or provider authentication.
- No silent provider/track/timeframe fallback, interpolation, adjustment,
  parameter optimization, or favorable intrabar ordering.
- No claim that a threshold, fixture, observed profit, or LLM choice proves an
  edge.
