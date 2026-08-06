# Finance plugin roadmap

This roadmap sketches a family of small Gleam packages that can turn Pi into a
finance research agent, initially focused on public equities. Each plugin is an
independent Gleam project, can be distributed as source through Hex, and must be
built into a Pi-loadable JavaScript artifact with Gleam and Bun.

The catalog is intentionally broad. It is a menu and dependency map, not a
promise to build every package at once.

Catalog entries without an implementation directory are **Draft**. Implemented
entries use the lifecycle state recorded in their package README and the status
sections below. Each implementation gets its own `plugins/<name>/`
directory and is an independent Gleam project. Its local `README.md` becomes the
detailed design document; this roadmap retains only the proposal, priority,
dependencies, and delivery status.

## Proposal lifecycle

Use these states when work begins:

```text
Draft -> Selected -> Designing -> Implementing -> Experimental -> Stable
                                   |                    |
                                   +----> Paused <------+
```

- **Draft** means only the proposal in this file exists.
- **Selected** means it is next in the implementation sequence.
- **Designing** starts by creating `plugins/<name>/README.md`, not code.
- **Implementing** means its independent Gleam project and tests exist.
- **Experimental** means it builds, loads in Pi, and can be distributed as Hex
  source, but its API/provider behavior may still change.
- **Stable** requires documented compatibility, release, migration, and
  operational policies.

A proposal or build step marked **Course gate `CG-*` (Open)** has an additional
stop between **Selected** and **Designing**. When that work reaches the front of
the queue, pause, tell the user which gate was reached, and ask them to obtain
the referenced finance-advisor deep dive. Do not create the package directory,
finalize formulas/policy, or start implementation by filling the gap with model
knowledge. Record the advisor's requirements and counterexamples in the
cross-referenced trading-course repository, link that deep-dive note from the
gate row here, record its
reviewed scope, and change the gate to **Resolved — YYYY-MM-DD**; then let the
package README become the detailed design. The registry's “Applies first to”
column and downstream consumption of a gated contract are binding even if a
proposal row does not repeat the marker. A resolved gate may be reopened when a
new track, timeframe, instrument class, or materially different workflow
exceeds the advisor's reviewed scope.

Each plugin README should cover:

1. user stories and explicit non-goals;
2. commands, tools, flags, events, and custom session data;
3. public Gleam modules and types;
4. provider endpoints, authentication, entitlements, licence, cache, pacing,
   retry, and outage behavior;
5. schemas, decoding rules, units, timestamps, adjustment and freshness policy;
6. permissions, secrets, trust boundary, and non-interactive behavior;
7. lifecycle behavior across reload, new/resume/fork, compaction, and shutdown;
8. pure, FFI, artifact, Pi integration, and provider-contract tests;
9. tested Pi/binding/provider versions and known limitations;
10. Hex source contents and the exact source-to-Pi build instructions.

Creating a plugin directory therefore means its proposal has graduated from
this catalog. Empty placeholder directories are not useful and should not be
created ahead of implementation.

## Product direction

The first useful finance agent should answer questions such as:

- What is this security, where does it trade, and how fresh is the quote?
- What changed in the latest 10-K, 10-Q, or 8-K?
- How are revenue, margins, cash flow, leverage, and dilution changing?
- Which upcoming earnings, dividends, splits, and macro releases matter?
- How does a company compare with peers under explicit valuation assumptions?
- What risks and concentrations exist in a portfolio?
- Can this research be reproduced from cited source data?

It should not begin with autonomous live trading. Read-only research, provenance,
portfolio analytics, and paper execution give us the highest usefulness with a
much smaller failure cost.

## Trader-requirement steering audit — 2026-08-06

The ultimate product goal is to meet trader requirements. Packages, bindings,
providers, and feature counts are enabling machinery; they are not success by
themselves. An audit against the trading curriculum's four working personas
finds strong trust and research foundations, but only partial end-to-end trader
workflows.

The personas are acceptance lenses, not permanent user identities and not new
market tracks. One user may use several workflows. A workflow selection may
change defaults, information density, and review cadence, but it must never
change an observation's `cn`, `hk`, or `us` track, substitute a provider, or
reinterpret source evidence.

| Trader workflow | Required decision loop | Current roadmap coverage | Steering gap |
| --- | --- | --- | --- |
| Day trader | Establish the live session and auction/halts state; scan intraday price, volume, spread, depth, and tape; form a bounded entry/exit plan; size risk; monitor; review execution. | Quote, calendar/rules, order-book, tape, alerts, paper brokers, and compliance are proposed or narrow slices. | **Weakest.** No licensed, freshness-bounded intraday stream, shared order/fill model, fast trade-plan tool, or latency/execution-quality acceptance gate. Daily bars must not be presented as a day-trading surface. |
| Swing trader | Scan a point-in-time universe; confirm price/volume/volatility and sector regime; inspect catalysts; define entry, stop, target, size, and holding horizon; monitor and journal. | Daily OHLCV, series/math, screener, technicals, catalysts, alerts, watchlist, and journal exist as separate proposals. | **Best next workflow.** The pieces lack one inspectable signal definition, risk/reward plan, saved workflow state, and end-to-end acceptance test. |
| Long-term investor | Resolve the security; read primary disclosures and complete statements; assess business quality, governance, valuation, dividends/actions, portfolio fit, and thesis changes; review periodically. | US primary-source and exact-fact slices are strongest; valuation, quality, actions, portfolio, thesis, news, and reports are proposed. | Statement breadth, segments, debt, governance/capital allocation, dividend history, peer/industry context, and CN/HK primary-document depth are incomplete. Narrow vendor facts are not an investor dossier. |
| Quant researcher | State a falsifiable hypothesis; bind a point-in-time universe and dataset; define features/signals; simulate costs and fills; validate out of sample; measure uncertainty; reproduce every run. | Math, series, calendars, OHLCV receipts, factor lab, event study, and a thin backtest proposal exist. | Point-in-time universe membership, corporate-action truth, shared strategy/execution semantics, parameter-trial accounting, statistical tests, walk-forward validation, and reproducible dataset manifests are incomplete. |

The following decisions bind later proposals:

- Professional workflow fit is a release criterion, not presentation polish.
  Each workbench starts from the persona's recurring day-to-day loop, preserves
  context across interruptions, makes the routine path short, groups exceptions
  for triage, and progressively reveals evidence when the trader drills in. A
  package that exposes every concept but forces the trader to manually assemble
  the normal workflow does not meet the trader requirement.
- Workbenches should feel like one coherent professional instrument rather than
  a bag of tools: one exact working set, stable vocabulary, sensible versioned
  defaults, batch actions where safe, and a clear “what changed / what needs my
  attention / what is next” view. Natural interaction must not hide assumptions,
  cross tracks, weaken a gate, or turn a plan into an order.
- Start acceptance from a trader task and decision loop, not from an indicator
  checklist. RSI, MACD, KD9, Bollinger Bands, ATR, VWAP, support/resistance, and
  patterns are parameterized evidence transformations, never standalone buy or
  sell claims.
- A computed feature or signal retains its exact input series, track/listing
  identity, source/as-of boundary, parameters, lookback and warm-up state,
  missing-data policy, formula version, and any confirmation rule.
- Trade planning is read-only analysis. Entry, stop, target, scaling, risk
  budget, order choice, and invalidation conditions remain a proposed plan until
  a separately authorized paper or live plugin acts on an exact draft.
- Alerts, screeners, backtests, paper simulations, and journals consume the same
  versioned strategy and execution definitions. They must not each invent
  incompatible signal, fee, slippage, or fill semantics.
- Trader-facing charts are views of typed evidence, not a second analytics
  engine. Axes, units, timezone, session gaps, adjustment basis, warm-up, source
  cut-off, and omitted points remain visible; every chart has a structured-data
  fallback outside the TUI.
- Psychology support is a user-declared checklist and review loop. The system
  may record FOMO, confirmation-bias, loss-aversion, discipline, and confidence
  labels supplied by the user; it must not infer a diagnosis or silently alter
  risk limits from prose sentiment.
- Readiness is track-specific. A workflow is not supported on a track until its
  identity, calendar/rules, source rights, time resolution, and required data
  quality pass that workflow's acceptance gate.

### Course-demand gates

The canonical local course TOC is
[`../trading-course/ROADMAP.md`](../trading-course/ROADMAP.md). These references
name the curriculum topic to deepen; they do not copy its illustrative rules
into production policy. `CG-SWING` is resolved for the bounded completed-daily-
bar workflow recorded below; every other gate remains **Open**.

| Gate | Trading-course TOC cross-reference | Finance-advisor deep dive required before design | Applies first to |
| --- | --- | --- | --- |
| `CG-MARKET-DATA` | Phase 1, Week 1 “Market Literacy” and Week 2 “Data & Tools” | Define the minimum trustworthy quote/bar/depth fields for each persona; source-time, session, auction, spread, volume and market-depth interpretation; trader-facing data-quality failures; and safe CSV/JSON/XLSX/SQL import expectations. | `pi_finance_dataset`, charts, snapshots, screeners, and later intraday surfaces |
| `CG-RISK` | Phase 1, Week 3 “Risk Management Foundation” and Phase 5, Week 19 “Advanced Risk Management” | Replace slogans such as “2% rule” and “2:1” with configurable laws: account and portfolio heat, gap/leverage/correlation/liquidity risk, stop distance, lot rounding, scaling, drawdown limits, stress cases, and when a plan must be rejected. | `finance_strategy`, `pi_trade_plan`, `pi_portfolio_risk` |
| `CG-PSYCHOLOGY` | Phase 1, Week 4 “Market Psychology” and Phase 5, Week 20 “Trading Psychology Mastery” | Specify user-declared bias/emotion/checklist vocabulary, pre-trade and post-trade review, process-adherence scoring, losing/winning-streak review, and boundaries against inferred diagnosis or automatic risk changes. | `pi_trade_journal` and every persona review loop |
| `CG-TECH` | Phase 2, Weeks 5–8 “Technical Analysis” | Provide exact formulas, seeds, parameters, warm-up, missing-session and corporate-action treatment for SMA/EMA, RSI, MACD, KD9, Bollinger, ATR and VWAP; operational definitions and counterexamples for support/resistance, trend, breakout, gaps, divergence, volume confirmation, patterns and multi-timeframe use. | `finance_indicators`, `pi_stock_technicals`, screeners, charts and alerts |
| `CG-FUNDAMENTAL` | Phase 3, Weeks 9–12 “Fundamental Analysis” | Define a minimum complete investor dossier, statement/period/segment/debt and cash-flow checks, sector-specific metrics, business quality, governance/management evidence, industry/macro context, valuation methods, sensitivity, and “insufficient evidence” cases. | governance/industry, quality/growth/valuation, fundamentals, and `pi_investor_workbench` |
| `CG-SWING` **(Resolved — 2026-08-06)** | Phase 4, Week 13 “Swing Trading System” and Week 16 “Strategy Integration” | Walk one complete weekly-to-daily workflow: universe, sector/regime/catalyst context, setup and confirmation, entry/stop/target/expiry, sizing/scaling, monitoring, exits, invalidation and journal review; distinguish required evidence from preferences. | `finance_strategy` completed-daily-bar slice, `pi_swing_workbench`, the next sprint |
| `CG-DAY` | Phase 4, Week 14 “Day Trading System” and Phase 5, Week 17 “Order Types & Execution” | Define pre-market, auction, opening-range, intraday and close workflows; permissible data latency; spread/depth/tape use; overtrading controls; order choice; partial/non-fill, gap, latency, impact and queue uncertainty; and track-specific stop/order availability. | `finance_execution`, `pi_order_simulator`, `pi_day_workbench` |
| `CG-QUANT` | Phase 4, Week 15 “Quantitative Approaches” | Specify the research protocol: falsifiable hypothesis, point-in-time universe/data availability, adjustments, feature/signal versioning, fill/cost model, train/validation/test and walk-forward design, multiple testing, uncertainty/significance, robustness, benchmarks and reproducible run acceptance. | `pi_quant_research`, `pi_backtest`, factor lab and event study |
| `CG-PORTFOLIO` | Phase 5, Week 18 “Portfolio Management” and Week 19 “Advanced Risk Management” | Define position/portfolio sizing, diversification versus hidden concentration, correlation regimes, rebalance and cash-flow rules, leverage/liquidity/currency exposure, VaR/CVaR limits, stress tests and drawdown response without false precision. | portfolio, risk, scenarios, attribution and rebalance proposals |
| `CG-LIVE` | Phase 6, Weeks 21–24+ “Live Trading” | Define readiness evidence for paper-to-micro-live transition, broker/account criteria, size-increase and stop conditions, execution and emotion review, incident handling and rollback; this augments rather than weakens the separate security review. | paper-broker acceptance and any live-broker design |

#### CG-SWING resolution — 2026-08-06

- **Evidence:** trading-course
  [Session 10 with the 10A and final 10B corrective addenda](../trading-course/sessions/10_cg_swing_daily_workflow_20260425.md).
- **Reviewed scope:** long-only cash equities on a completed-daily-bar cadence,
  normally held for several sessions, with a point-in-time universe, an
  inspectable RSI-reversal strategy example, plan-before-order, monitoring,
  explicit exit ambiguity, expiry, and planned-versus-observed review. It is a
  workflow contract and test hypothesis, not evidence of positive expectancy.
- **Normative design:** [`finance_strategy`](finance/finance_strategy/README.md)
  owns pure strategy definitions, evidence guards, evaluation, and lifecycle
  transitions. [`pi_swing_workbench`](plugins/swing_workbench/README.md) is the
  thin Pi compositor. Neither owns indicator arithmetic, sizing, provider
  access, market rules, fill simulation, or journal storage.
- **Accepted corrections:** planned closures are absent from ordered trading-
  session series; no synthetic prices or volume are inserted; price-dependent
  features require an adjustment-consistent series and provenance; row presence
  is not an observation receipt; false predicates are distinct from missing or
  late evidence; close-known decisions cannot become earlier intraday facts;
  and a daily bar touching stop and target without sequence evidence yields
  `UnknownOrdering`.
- **Repository boundary:** course market, fee, tax, lot, tick, account, broker,
  and calendar facts are requirements examples. Production evaluation consumes
  exact track/listing/effective-date receipts from the existing market-owned
  packages and caller capabilities; it does not embed those tables as timeless
  constants. The addendum's `CG-JOURNAL` label maps to the existing
  `CG-PSYCHOLOGY` gate plus the ordinary `journal_schema` dependency because
  `CG-JOURNAL` is not registered here. Provider omission and incomplete
  evidence return `NotReady`, never a semantic rejection of the security.
- **Adjacent gates remain open and blocking where applicable:** minimum daily
  observation, freshness, volume/turnover, source-rights, and import semantics
  belong to `CG-MARKET-DATA`; indicator formulas, warm-up, and adjustment
  production to `CG-TECH`; position sizing, gap stress, account constraints,
  and portfolio heat to `CG-RISK`;
  executable order support and fill/cost policy to `CG-DAY` and the named
  execution dependency; journal schema and psychology review to
  `CG-PSYCHOLOGY`; and expectancy/backtest claims to `CG-QUANT`. A missing
  dependency that can change a predicate, size, or executable order returns
  `NotReady`; optional confirmation/ranking omissions may be labelled warnings.

For a useful answer, ask the advisor to return: persona and holding horizon;
track/instrument scope; required inputs and permissible freshness; exact formulas
or decision rules with defaults identified as defaults; unknown/fail-closed
cases; at least two worked examples and two counterexamples; and what the tool
must never conclude. This becomes requirements evidence, not provider evidence.

## Rules for every finance plugin

Finance tools need a stricter contract than ordinary convenience plugins:

- Follow `FUNCTIONAL_DESIGN.md`: finance rules, calculations, validation, and
  workflow transitions are pure functions over immutable types. Pi, HTTP,
  clocks, storage, randomness, and credentials remain explicit shell
  capabilities.
- Model multi-step workflows as typed events and effects so they can be folded,
  replayed, audited, and tested without Pi or provider access.
- Every observation carries its source, `as_of` time, retrieval time, timezone,
  currency/unit, and delayed/real-time status.
- Prices say whether they are raw or adjusted and identify the session
  (pre-market, regular, after-hours, or closed).
- Missing, stale, estimated, restated, and revised data are explicit states, not
  silently converted to zero.
- Decimal financial values stay as strings or exact decimal representations at
  the FFI boundary; binary floats are reserved for derived analytics where the
  precision policy is stated.
- Corporate actions and symbol changes are first-class. A ticker alone is not a
  permanent security identifier.
- Every analytical result records its inputs and assumptions. The agent must not
  invent a quote, filing fact, consensus estimate, or citation.
- Provider limits, entitlements, and redistribution terms are respected. Cache
  policy is provider-specific.
- Credentials come from environment/configuration and are never appended to Pi
  sessions, logs, tool details, or error messages.
- Read-only is the default. Paper and live execution are separate plugins and
  capabilities.
- Output is research tooling, not a guarantee, fiduciary service, or substitute
  for professional advice.

## Roadmap phases

This file is the governing index. Together, `ROADMAP.md` and `R0.md`–`R3.md`
are the proposal catalog required by the repository guidelines. The lifecycle,
trader-requirement steering decisions, course-demand gates, track laws, and
finance-plugin rules above apply to every phase file.

| Phase | Detailed roadmap | Scope | Exit/steering purpose |
| --- | --- | --- | --- |
| **R0 — Trustworthy substrate and implemented baseline** | [`R0.md`](R0.md) | Shared finance packages, dependency laws, completed arbitrations, Experimental vertical slices, and the current depth gaps. | Establish what is real and reusable before counting trader-facing breadth. |
| **R1 — Finance capability catalog** | [`R1.md`](R1.md) | Foundation/trust, market data, CN/HK/US research, fundamentals, valuation, trader workbenches, events, macro, portfolio, backtest, and execution proposals. | Keep the complete capability map while thin workbenches compose shared engines instead of cloning them. |
| **R2 — Delivery and trader-workflow convergence** | [`R2.md`](R2.md) | Active delivery ledger, F0–F6 delivery, T0–T4 four-trader acceptance, CN0–CN4, and the next swing-trader sprint. | Keep state, blockers, next artifacts and forbidden claims explicit; choose implementation order from trader decision loops and stop at every open course gate before design. |
| **R3 — Provider policy and open decisions** | [`R3.md`](R3.md) | Candidate/accepted providers, entitlement and source cautions, and unresolved product/data decisions. | Resolve provider and policy choices without creating invisible fallback chains. |

Read phases in order for a full audit. They are categories, not permission to
skip dependencies: an item in a later file still depends on all applicable R0
contracts, track-specific evidence gates, and course-demand stops. New detailed
proposals go in the appropriate phase file and must be linked from this index if
they change a phase's scope. [`R2.md`](R2.md#active-delivery-ledger--2026-08-06)
is the active work ledger; the other files should not grow duplicate status
lists.
