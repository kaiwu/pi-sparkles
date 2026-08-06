# finance_strategy

Status: **Designing — CG-SWING completed-daily-bar slice** · target:
JavaScript/Bun

`finance_strategy` is the pure, provider-neutral contract that makes a trading
hypothesis inspectable and replayable. Its first slice supports a long-only
cash-equity swing workflow evaluated after a completed daily session and
normally held for several sessions. It does not claim that the example strategy
has positive expectancy.

The requirements evidence is trading-course
[Session 10 with the 10A and 10B addenda](../../../trading-course/sessions/10_cg_swing_daily_workflow_20260425.md).
Where the course gives market examples, this design applies the repository's
track, evidence, and effective-date laws. The reviewed `CG-SWING` scope is
recorded in the [roadmap](../../ROADMAP.md#cg-swing-resolution--2026-08-06).

The package is a functional core. It contains no Pi, HTTP, filesystem, clock,
storage, randomness, mutable cache, provider adapter, broker adapter, or
JavaScript business logic.

## Trader requirement

A swing trader must be able to answer, without reconstructing hidden model
reasoning:

1. What exact security and completed session were evaluated?
2. Which required predicates passed or failed, and which optional evidence was
   unknown?
3. Which observations and feature versions produced that decision?
4. What entry, invalidation, target, expiry, and monitoring intent was saved
   before any order?
5. Which risk, market-rule, and execution capabilities were still missing?
6. What happened later, and did the trader follow the saved process regardless
   of profit or loss?

The same versioned definition and transition rules must be reusable by a
screener, alert, workbench, simulator, backtest, and journal.

## Reviewed scope

- long-only cash equities on the existing `cn`, `hk`, and `us` tracks;
- completed regular-session daily bars only;
- exact listing, venue, currency, calendar, and effective-date context;
- a versioned RSI-reversal example with required predicates separated from
  optional confirmations and ranking;
- entry intent for the next eligible session, expiry, desired stop and target,
  daily monitoring, and explicit exit ambiguity;
- planned-versus-observed transitions with complete source leaves.

Support is capability-specific, not track-wide. A track or listing is
`NotReady` when the exact identity, calendar, adjustment, data, market-rule,
risk, or execution evidence required by the selected definition is unavailable.

## Planned modules

| Module | Responsibility |
| --- | --- |
| `finance_strategy/definition` | immutable strategy identity, version, scope, parameters, predicates, confirmations, ranking and lifecycle policy |
| `finance_strategy/evidence` | typed observation, feature, calendar, market-rule, risk and execution receipts plus compatibility validation |
| `finance_strategy/evaluate` | pure predicate evaluation and reason tree |
| `finance_strategy/plan` | desired entry, invalidation, target, expiry and monitoring intents; never an executable order |
| `finance_strategy/transition` | total fold over signal, plan, fill, monitoring and exit events |
| `finance_strategy/receipt` | canonical result, definition/input hashes, ordered evidence roots and versioned JSON |
| `finance_strategy/rsi_reversal` | executable data constructor for the first reviewed hypothesis |

`finance_strategy` may depend inward on provider-neutral core, evidence,
listing, math, series, and provenance packages. It consumes indicator, risk,
market-rule, and execution results as typed receipts. It does not fetch or
recalculate them and imports no market-owned package.

## Core values

The design must represent at least these values without flattening them into
display text:

- `StrategyDefinition`: stable ID, semantic version, hypothesis, negative
  claims, instrument/track/timeframe scope, predicate tree, optional
  confirmations, ranking, parameters, and validity window;
- `EvaluationContext`: exact listing key, signal session, evaluation instant,
  source cutoff, reviewed calendar coverage, and ordered evidence roots;
- `FeatureReceipt`: feature ID and formula version, parameters, warm-up state,
  input-series hash, track/listing/session, adjustment basis, unit, source
  cutoff, and quality;
- `RuleReceipt`: exact track, listing/board/share class, rule kind, authority,
  effective interval, retrieval evidence, and value;
- `RiskReceipt`: named risk-policy version, exact account context, proposed size,
  stop/gap/notional/heat checks, rounding inputs, and reasons;
- `ExecutionCapabilityReceipt`: requested order intent, exchange support,
  broker support, session, tick/lot inputs, and effective evidence;
- `StrategyReceipt`: decision, complete reason tree, definition/input hashes,
  warnings, unresolved dependencies, and every evidence root;
- `WorkflowEvent`: qualified signal, plan attached, entry expired, fill observed,
  monitor observation, exit observation, ambiguity, and review attached.

A caller declaration may be retained as a declaration but must not be relabelled
as authority or provider evidence.

## Decision states

Predicate truth and evidence readiness are different:

| State | Meaning |
| --- | --- |
| `SetupQualified` | all required setup predicates pass, but risk and execution readiness may not yet be attached |
| `Accepted` | setup, sizing constraints, and required execution dependencies all pass; an entry intent may be handed to an explicitly authorized execution layer |
| `Rejected` | complete compatible evidence proves that a required predicate or constraint is false |
| `Expired` | a previously accepted entry intent did not fill inside its versioned validity window |
| `NotReady` | evidence or a predicate/sizing/order dependency is missing, stale, incomplete, conflicting, or unsupported |
| `NotEvaluable` | the evidence became known only after the permitted decision window |

The result never converts `NotReady` into `Rejected`. Optional confirmation or
ranking evidence may be `Unknown` with an `AuditWarning`; missing evidence that
can change a predicate, position size, or executable order always blocks.

## Trading-session and observation laws

- An input series contains actual ordered trading sessions. Weekends and
  planned closures have no row and do not count toward a lookback.
- No strategy path may synthesize a close, return, or zero volume for a closure,
  suspension, provider omission, or unavailable history.
- An expected open session missing from provider output requires explicit gap
  classification. Incomplete pagination or a provider gap is `NotReady`.
- A resolved suspension requires the feature contract's full post-resumption
  warm-up. An ongoing suspension cannot produce an actionable setup.
- Every price-dependent feature uses one adjustment-consistent OHLC basis over
  its complete lookback, with adjustment method, factor source, application
  dates, and provenance. Unavailable, conflicting, or discontinuous provenance
  is `NotReady`.
- A local row proves only row presence. The evaluation also requires canonical
  acquisition/gap receipts, source and retrieval times, exact identity,
  completeness, calendar coverage, and content-bound evidence.
- Volume and turnover predicates require proven units and semantics. Unknown
  lot/share or value/currency semantics are not guessed.

These laws build on `finance_ohlcv` and the exact track-owned OHLCV joins; this
package does not introduce a second observation-receipt schema.

## RSI-reversal v1 definition

The first definition is a testable hypothesis encoded as data, not a universal
buy rule. Its defaults, including its normal holding horizon, are visible in
the definition and may be changed only by creating a new definition version.

The required setup shape is:

- a point-in-time eligible and liquid universe with exact status and event
  evidence;
- completed close above the versioned long moving average;
- RSI at or below the oversold threshold and strictly higher than its prior-
  session value;
- completed close within the configured distance of the medium moving average.

Volume, moving-average alignment, higher-low, candle, persistence,
sector/regime, and catalyst facts are confirmations or ranking only when the
definition says so. They must not silently migrate into required predicates.
The package consumes their feature receipts; `CG-TECH` remains open for exact
SMA, RSI, ATR, volume, warm-up, and adjustment-production contracts.

The reviewed desired-plan shape records:

- a next-eligible-session entry ceiling and a bounded expiry window;
- a desired stop equal to the tighter valid protective level selected by the
  versioned volatility and structural-stop rule;
- a target expressed from the exact planned risk distance;
- no scaling in the first version;
- daily close review and a versioned trailing-stop intent;
- holding-period, invalidation, target, stop, and manual-exit categories.

These are analytical intents. Exact tick/lot validity, account risk, position
size, gap stress, portfolio heat, fees, order availability, and broker mapping
remain receipts from open `CG-RISK`, `CG-DAY`, market-rule, and execution
contracts. Until they are supplied, the setup may be `SetupQualified` but not
`Accepted`.

## Causal timing and exit ambiguity

- Evaluation proves the daily bar is complete through calendar and acquisition
  evidence, not merely because a clock appears to be after the close.
- Source-known and retrieval times must precede the selected evaluation cutoff.
- A condition known only from session close can affect the next executable
  decision; it cannot be backdated to an intraday fill.
- Intraday stop or target claims require ordered trade/quote evidence and an
  explicit fill policy.
- If one daily bar contains both the stop and target and no finer sequence
  evidence is supplied, the result is `UnknownOrdering`. It must not choose the
  favorable or adverse path by convention.
- A gap through a desired stop records the first supported executable outcome;
  it does not pretend the stop price was filled.

## Market and account facts

Settlement, same-day resale, price limits, ticks, lots, fees, taxes, account
restrictions, leverage, and broker order support are separate effective-dated
facts. Production definitions do not embed the course's CN/HK/US examples as
timeless constants. Callers supply exact receipts from `finance_market_rules`
and the appropriate market-owned package, plus opaque account/broker
capabilities. Unknown or conflicting facts block the affected decision.

## Transition and review laws

The pure fold accepts only events that are legal from the current state. It
rejects fill-before-plan, monitor-before-fill, exit-before-entry, events for a
different listing/track/definition, backward timestamps, and edits that rewrite
the original plan.

Observed fills and prices are new evidence leaves. They never mutate planned
values. Review compares plan, observations, actions, and result; a losing trade
may be process-compliant and a profitable trade may contain a process
violation. User-declared psychology/checklist fields and the durable journal
schema remain the open `CG-PSYCHOLOGY` and `journal_schema` dependencies.

## Acceptance criteria

- Every decision is reproducible from a definition version and complete input
  receipts without Pi, provider, clock, or storage access.
- Exact identity, track, session, source cutoff, adjustment basis, units, and
  evidence roots survive evaluation and JSON round-trip.
- False predicates, missing evidence, late evidence, expired entries, and
  ambiguous exit ordering remain distinct typed results.
- Planned closures never become data points; gaps and suspensions never become
  synthetic flat returns or zero volume.
- A missing `CG-TECH`, `CG-RISK`, market-rule, account, or execution receipt
  blocks only the decisions it can affect and is named in the result.
- Fixtures use supplied valid calendars and complete typed inputs. They cover a
  qualified setup, predicate rejection, unfilled expiry, gap-through-stop,
  stop-and-target `UnknownOrdering`, unsupported stop execution, missing gap
  bound, and missing adjustment provenance.
- Property and transition-sequence tests cover determinism, event legality,
  evidence preservation, no-look-ahead timing, and definition-version changes.

## Open gates before implementation breadth

- `CG-MARKET-DATA`: minimum completed-daily observation, source-rights,
  freshness, volume/turnover semantics, and trader-facing quality contract;
- `CG-TECH`: formula, seed, warm-up, volume, missing-session, and adjustment
  production contracts;
- `CG-RISK`: account risk, gap stress, position sizing, notional, portfolio heat,
  fee reserve, and zero-size policy;
- `CG-DAY` plus the named execution dependency: exact order/fill/cost and broker
  capability contracts;
- `CG-PSYCHOLOGY` plus `journal_schema`: pre/post-trade checklist and durable
  review vocabulary;
- `CG-QUANT`: backtest protocol and any expectancy or robustness claim.

## Non-goals

- No quote, OHLCV, corporate-action, news, sector, account, or broker fetching.
- No indicator arithmetic, risk sizing, fee table, fill simulation, portfolio
  optimization, prediction, recommendation, or autonomous execution.
- No silent provider/track/timeframe fallback, interpolation, adjustment,
  parameter optimization, or favorable intrabar ordering.
- No claim that one setup, threshold, fixture, or profitable outcome proves an
  edge.
