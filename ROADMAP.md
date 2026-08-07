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

- The LLM owns every research and trade decision. Finance libraries and plugins
  provide compact typed facts, explicit calculations, compatibility/readiness
  states, provenance, and workflow history; they never emit a buy/sell verdict,
  setup qualification, plan acceptance/rejection, recommendation, or hidden
  score. Structural validation, deterministic formula evaluation, and safety or
  authorization enforcement remain allowed, but must be rendered as the exact
  facts and constraints the LLM needs rather than a substituted market opinion.
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
bar workflow, `CG-MARKET-DATA` for the information-only daily-market-data
contract, `CG-TECH` for calculation-only technical facts, `CG-RISK` for
calculation-only risk facts, and the execution-information slice of `CG-DAY`
for desired instructions, capabilities, explicit simulations,
lifecycle/fills, and requested calculations. The full intraday workflow part
of `CG-DAY` and every other gate remain **Open**.

| Gate | Trading-course TOC cross-reference | Finance-advisor deep dive required before design | Applies first to |
| --- | --- | --- | --- |
| `CG-MARKET-DATA` **(Resolved — 2026-08-07)** | Phase 1, Week 1 “Market Literacy” and Week 2 “Data & Tools” | Define the minimum trustworthy quote/bar/depth fields for each persona; source-time, session, auction, spread, volume and market-depth interpretation; trader-facing data-quality failures; and safe CSV/JSON/XLSX/SQL import expectations. | `pi_finance_dataset`, charts, snapshots, screeners, and later intraday surfaces |
| `CG-RISK` **(Resolved — 2026-08-07)** | Phase 1, Week 3 “Risk Management Foundation” and Phase 5, Week 19 “Advanced Risk Management” | Replace slogans such as “2% rule” and “2:1” with configurable laws: account and portfolio heat, gap/leverage/correlation/liquidity risk, stop distance, lot rounding, scaling, drawdown limits, stress cases, zero-size outcomes, and every constraint the LLM must see when deciding on a proposed plan. | `finance_strategy`, `pi_trade_plan`, `pi_portfolio_risk` |
| `CG-PSYCHOLOGY` **(Journal-information slice Resolved — 2026-08-07)** | Phase 1, Week 4 “Market Psychology” and Phase 5, Week 20 “Trading Psychology Mastery” | Specify user-declared bias/emotion/checklist vocabulary, pre-trade and post-trade review, immutable attribution, requested comparisons/metrics, portable storage, and boundaries against inferred diagnosis, plugin-owned process judgment, or automatic risk changes. | `finance_journal`, `pi_trade_journal`, and every persona review loop |
| `CG-TECH` **(Resolved — 2026-08-07)** | Phase 2, Weeks 5–8 “Technical Analysis” | Provide exact formulas, seeds, parameters, warm-up, missing-session and corporate-action treatment for SMA/EMA, RSI, MACD, KD9, Bollinger, ATR and VWAP; operational definitions and counterexamples for support/resistance, trend, breakout, gaps, divergence, volume confirmation, patterns and multi-timeframe use. | `finance_indicators`, `pi_stock_technicals`, screeners, charts and alerts |
| `CG-FUNDAMENTAL` | Phase 3, Weeks 9–12 “Fundamental Analysis” | Define a minimum complete investor dossier, statement/period/segment/debt and cash-flow checks, sector-specific metrics, business quality, governance/management evidence, industry/macro context, valuation methods, sensitivity, and “insufficient evidence” cases. | governance/industry, quality/growth/valuation, fundamentals, and `pi_investor_workbench` |
| `CG-SWING` **(Resolved — 2026-08-06)** | Phase 4, Week 13 “Swing Trading System” and Week 16 “Strategy Integration” | Walk one complete weekly-to-daily workflow: universe, sector/regime/catalyst context, setup and confirmation, entry/stop/target/expiry, sizing/scaling, monitoring, exits, invalidation and journal review; distinguish required evidence from preferences. | `finance_strategy` completed-daily-bar slice, `pi_swing_workbench`, the next sprint |
| `CG-DAY` **(Execution-information slice Resolved — 2026-08-07; full intraday workflow Open)** | Phase 4, Week 14 “Day Trading System” and Phase 5, Week 17 “Order Types & Execution” | Define pre-market, auction, opening-range, intraday and close workflows; permissible data latency; spread/depth/tape use; overtrading controls; order choice; partial/non-fill, gap, latency, impact and queue uncertainty; and track-specific stop/order availability. | `finance_execution`, `pi_order_simulator`, `pi_day_workbench` |
| `CG-QUANT` | Phase 4, Week 15 “Quantitative Approaches” | Specify the research protocol: falsifiable hypothesis, point-in-time universe/data availability, adjustments, feature/signal versioning, fill/cost model, train/validation/test and walk-forward design, multiple testing, uncertainty/significance, robustness, benchmarks and reproducible run acceptance. | `pi_quant_research`, `pi_backtest`, factor lab and event study |
| `CG-PORTFOLIO` | Phase 5, Week 18 “Portfolio Management” and Week 19 “Advanced Risk Management” | Define position/portfolio sizing, diversification versus hidden concentration, correlation regimes, rebalance and cash-flow rules, leverage/liquidity/currency exposure, VaR/CVaR limits, stress tests and drawdown response without false precision. | portfolio, risk, scenarios, attribution and rebalance proposals |
| `CG-LIVE` | Phase 6, Weeks 21–24+ “Live Trading” | Define readiness evidence for paper-to-micro-live transition, broker/account criteria, size-increase and stop conditions, execution and emotion review, incident handling and rollback; this augments rather than weakens the separate security review. | paper-broker acceptance and any live-broker design |

#### CG-MARKET-DATA resolution — 2026-08-07

- **Evidence:** trading-course
  [Session 11 and its information-only amendments](../trading-course/sessions/11_cg_market_data_20260807.md).
- **Reviewed scope:** regular-session daily OHLCV facts for long-only cash
  equities on the `cn`, `hk`, and `us` tracks: identity, calendar/status,
  acquisition, timing, adjustment, units, source-rights statements, quality,
  conflicts, imports, compact summaries, drill-down, and stable evidence
  references.
- **Controlling boundary:** plugins preserve and efficiently expose observations,
  provenance, unknowns, conflicts, omissions, mechanical checks, available
  operations, and explicitly requested calculations. They do not judge
  correctness, trustworthiness, sufficiency, usability, freshness, readiness,
  setup quality, provider preference, the next action, or a trade. The LLM owns
  every such decision.
- **Accepted mechanics:** every required slot may be known, unknown, not
  obtained, conflicting, or a decode failure without discarding other safe
  evidence; parse failures remain distinct from mechanical predicates;
  classifications include their component facts and versioned rules; no
  imputation occurs unless explicitly requested by the LLM and returned as a
  separate calculated artifact; rights predicates retain sourced, declared,
  host-policy, or unknown authority.
- **Implementation freedom:** package/type placement is non-blocking. Incremental
  shared and track-owned information contracts may proceed without claiming
  complete provider or track coverage. The resolved `CG-TECH` contract owns
  indicator calculations; the resolved `CG-RISK` contract owns risk
  calculations; `CG-DAY` and the other adjacent gates still own their
  respective facts. The LLM owns all professional decisions.
- **Initial implementation:** [`finance_ohlcv`](finance/finance_ohlcv/README.md)
  now exposes generic fact states, raw reported-row mechanics, quantity, rights,
  timing comparisons, bounded acquisition-attempt evidence, a typed packet, and
  neutral available operations alongside its existing validated `Bar`/`Batch`
  projection. Fourteen focused offline tests and the full repository suite pass.

#### CG-TECH resolution — 2026-08-07

- **Evidence:** trading-course
  [Session 12 and its design-closing amendments](../trading-course/sessions/12_cg_tech_indicator_calculations_20260807.md).
- **Reviewed scope:** versioned daily-bar calculations and relations, exact
  input projections, seeds, window/gap/rounding/parseable-value policies,
  warm-up omissions, adjustment and unit facts, intermediate values, source
  corrections, batch/incremental semantic equivalence, compact requested
  projections, drill-down operations, and content-bound receipts.
- **Controlling boundary:** indicator libraries and plugins calculate only what
  the LLM requests and expose inputs, parameters, alternatives, outputs,
  provenance, unknowns, conflicts, omissions, and available operations. They
  never select an indicator or parameter, interpret a value, judge correctness
  or sufficiency, label readiness/setup/signal/candidate state, rank/recommend,
  choose a next action, or decide a trade.
- **Accepted mechanics:** no implicit price basis, imputation, seed, regional
  convention, gap recovery, rounding, failed-check policy, conflict branch, or
  summary calculation; unavailable dates remain unperformed expressions rather
  than whole-request rejection; raw unknown-unit arithmetic may be returned
  with that unit fact when explicitly requested; semantic-result hashing is
  non-self-referential and separate from optional execution traces.
- **Initial implementation:**
  [`finance_indicators`](finance/finance_indicators/README.md) implements
  `slot_window_v1` SMA, Wilder RSI, true range, and Wilder ATR with canonical
  request and semantic-result receipts. Eighteen deterministic offline tests
  and the full `bun run test` repository suite pass. EMA/MACD, Bollinger, KD,
  volume relations, other variants, execution traces, and technical primitives
  remain incremental without reopening the resolved LLM-only boundary.

#### CG-RISK resolution — 2026-08-07

- **Evidence:** trading-course
  [Session 13](../trading-course/sessions/13_cg_risk_calculation_contract_20260807.md),
  which supersedes Sessions 02, 05, and 10/10A/10B wherever they assigned a
  risk policy, scenario, quantity, sufficiency judgment, or next action to a
  plugin.
- **Reviewed scope:** long-only cash equities on completed-daily planning for
  separately labelled `cn`, `hk`, and `us` legs: exact account/position/plan
  facts, explicitly selected budgets and scenarios, per-constraint quantity
  bounds, supplied trade-unit grids, requested intersections, gap loss, costs,
  portfolio heat, FX seams, unknown/conflicting branches, compact operations,
  and content-bound receipts.
- **Controlling boundary:** risk libraries and plugins expose supported
  calculations and preserve their exact inputs, intermediate values, outputs,
  provenance, unknowns, conflicts, omissions, alternatives, and available
  operations. They never choose a policy, threshold, scenario, quantity,
  sufficiency/correctness judgment, plan status, authorization, recommendation,
  or next operation; the LLM owns every such decision.
- **Accepted mechanics:** negative/zero loss and remaining-budget values are
  returned without a verdict; every requested bound remains independent;
  intersection occurs only for an explicit bound list; unknown grid, FX, cost,
  or scenario operands leave other calculations available; market-rule,
  account, scenario, and cost facts remain source-separated; semantic hashing
  is non-self-referential and separate from optional execution traces.
- **Initial implementation:** [`finance_risk`](finance/finance_risk/README.md)
  implements sourced information states, exact planned/gap loss and explicit
  fraction budgets, generic independent quantity bounds, supplied-grid
  projection, requested intersections, single-currency planned-stop heat,
  partial cost decompositions, and canonical request/semantic receipts. Twenty
  deterministic offline tests and the full repository suite pass. Shorts,
  derivatives, margin liquidation, cross-currency aggregation, scaling,
  tiered costs, correlation/liquidity stress, VaR/CVaR, drawdown schedules,
  intraday risk, and execution integration remain incremental.

#### CG-DAY execution-information resolution — 2026-08-07

- **Evidence:** trading-course
  [Session 14](../trading-course/sessions/14_cg_day_execution_information_contract_20260807.md),
  which resolves the bounded execution-information slice while explicitly
  leaving the complete professional intraday loop open.
- **Reviewed scope:** long-only cash equities on separately labelled `cn`,
  `hk`, and `us` tracks: desired instructions, sourced broker/account/exchange
  capabilities, session comparisons, explicit daily-bar/depth/scenario models,
  unknown queue and remainder facts, ordered lifecycle/fill receipts, requested
  aggregate/cost/benchmark/latency calculations, compact operations, and
  content-bound receipts. Daily swing use does not claim intraday sequence.
- **Controlling boundary:** execution libraries and plugins expose exact facts,
  labelled model branches, external broker states, requested calculations,
  provenance, unknowns, conflicts, omissions, alternatives, and available
  operations. They never select an order or broker encoding, transform to a
  fallback, predict a fill, choose a branch/benchmark/threshold, judge
  correctness or sufficiency, recommend a response, decide the next operation,
  or authorize a trade. The LLM owns every such decision.
- **Accepted mechanics:** desired instructions and broker-native encodings are
  distinct; depth snapshots do not prove queue or hidden size; daily bars emit
  compatible paths rather than a fill; partial remainders stay unknown beyond
  the scenario window; broker rejection text remains an external fact;
  cancel/fill races retain every event; unknown cost or clock operands leave
  known calculations available; semantic hashes are non-self-referential and
  batch/incremental folds are equivalent for equal ordered events.
- **Initial implementation:**
  [`finance_execution`](finance/finance_execution/README.md) implements sourced
  facts and desired capabilities, session comparisons,
  `visible_depth_sweep_v1`, `bar_possible_paths_v1`, exact fill aggregation,
  lifecycle folding, requested spread/slippage/shortfall/cost/latency
  calculations, and canonical request/semantic receipts. Twenty-four
  deterministic offline tests pass. Additional models, provider/broker
  adapters, `pi_order_simulator`, licensed intraday data, full day-workflow
  behavior, journal composition, and all mutation remain separate. The
  `CG-PSYCHOLOGY` journal-information slice is resolved below; it does not
  complete the day-trader workflow.

#### CG-PSYCHOLOGY journal-information resolution — 2026-08-07

- **Evidence:** trading-course
  [Session 15](../trading-course/sessions/15_cg_psychology_journal_information_contract_20260807.md),
  which is the canonical contract for attributed declarations, checklists,
  immutable journal events, local-first portability, requested calculations,
  compact context, corrections, redaction metadata, and failure behavior.
- **Reviewed scope:** exact user, LLM, imported, provider, broker, system, and
  calculated attribution; open declaration vocabulary; versioned partial
  checklists; append-only correction/redaction lineage; point-in-time views;
  JSONL storage/query/export/import effects; explicitly requested
  plan-observation comparison and long-cash realized net P&L; and compact
  resumable context for `cn`, `hk`, and `us` journal records.
- **Controlling boundary:** journal libraries and plugins preserve exact events,
  privacy, identity, provenance, unknowns, conflicts, omissions, calculations
  explicitly requested by the LLM, and neutral available operations. They never
  infer psychology, diagnose, grade process or discipline, judge correctness or
  sufficiency, explain performance causally, select a review policy, change
  risk, recommend a response, authorize a trade, or choose the next operation.
  The LLM owns every interpretation and decision.
- **Accepted mechanics:** authorship never changes in a projection; corrections
  and redactions append rather than rewrite history; same idempotency key plus
  identical semantic content returns the original event; private prose is
  omitted from compact context and ordinary queries unless explicitly
  requested; storage capability and security facts remain distinct; exact
  cross-track/listing identity is never inferred from a symbol; and export
  privacy is caller-selected rather than plugin policy.
- **Initial implementation:**
  [`finance_journal`](finance/finance_journal/README.md) implements immutable
  events, information states, replay/query/export, checklist receipts,
  comparisons, realized net P&L, and compact context with twenty offline tests.
  [`trade_journal`](plugins/trade_journal/README.md) supplies the thin Pi shell
  and bounded local-first JSONL backend with five plugin tests and four binding
  scenarios; artifact verification, installed-Pi smoke loading, and the full
  repository suite pass. Pagination continuations, partial import, more requested metrics,
  deletion, databases, persona templates, `CG-QUANT` statistics,
  `CG-PORTFOLIO` attribution, and `CG-LIVE` integration remain incremental and
  do not authorize plugin-owned decisions.

#### CG-SWING resolution — 2026-08-06

- **Evidence:** trading-course
  [Session 10 with the 10A and final 10B corrective addenda](../trading-course/sessions/10_cg_swing_daily_workflow_20260425.md).
- **Reviewed scope:** long-only cash equities on a completed-daily-bar cadence,
  normally held for several sessions, with a point-in-time universe, an
  inspectable RSI-reversal strategy example, plan-before-order, monitoring,
  explicit exit ambiguity, expiry, and planned-versus-observed review. It is a
  workflow contract and test hypothesis, not evidence of positive expectancy.
- **Normative implementation:**
  [`finance_strategy`](finance/finance_strategy/README.md) owns pure strategy
  definition data, evidence compatibility projection, receipt JSON, LLM/user
  plan declarations, and structural workflow history. It deliberately has no
  aggregate evaluation or decision type.
  [`pi_swing_workbench`](plugins/swing_workbench/README.md) is now an
  Experimental thin Pi evidence/context compositor. Neither owns indicator arithmetic, sizing, provider
  access, market rules, fill simulation, journal storage, or the LLM's decision.
- **Accepted corrections:** planned closures are absent from ordered trading-
  session series; no synthetic prices or volume are inserted; price-dependent
  features require an adjustment-consistent series and provenance; row presence
  is not an observation receipt; false predicates are distinct from missing or
  late evidence and never become an aggregate verdict; close-known facts cannot
  become earlier intraday facts; and a daily bar touching stop and target
  without sequence evidence yields an explicit unknown-ordering fact.
- **Repository boundary:** course market, fee, tax, lot, tick, account, broker,
  and calendar facts are requirements examples. Production evidence projection
  consumes exact track/listing/effective-date receipts from the existing
  market-owned packages and caller capabilities; it does not embed those tables
  as timeless constants or decide what the LLM should do. The addendum's
  `CG-JOURNAL` label maps to the existing
  `CG-PSYCHOLOGY` gate plus the ordinary `journal_schema` dependency because
  `CG-JOURNAL` is not registered here. Provider omission and incomplete
  evidence remain distinct compatibility facts, never a semantic rejection of
  the security.
- **Adjacent inputs remain incremental rather than plugin-design blockers:** the
  `CG-MARKET-DATA` information contract is resolved, but exact track/provider
  composition for daily observation, timing, volume/turnover, source-rights,
  and import facts remains incremental; the resolved `CG-TECH` calculation
  contract is implemented only for its first SMA/RSI/ATR slice; position
  sizing, gap stress, account constraints, and portfolio heat now use the
  resolved `CG-RISK` contract and its initial `finance_risk` calculation slice;
  the initial execution-information seam is now available, while exact
  track/account support, additional fill/cost models, and all executable order
  behavior remain incremental; the resolved journal-information contract and
  initial durable shell can now be referenced by event ID, while broader
  psychology/review templates remain incremental; and expectancy/backtest
  claims belong to `CG-QUANT`. The workbench
  can preserve exact supplied receipts and information states before those
  families are broad or complete because it never decides their correctness or
  sufficiency. Missing, stale,
  late, conflicting, declared-only, and unsupported dependencies remain named
  facts. Optional confirmation/ranking omissions stay visibly optional; no
  readiness label authorizes or rejects the LLM's plan.
- **Initial workbench implementation:** the network-free
  [`swing_workbench`](plugins/swing_workbench/README.md) attaches canonical
  strategy receipts, exact generic information facts, immutable opaque LLM/user
  plan declarations, and caller-vocabulary review records. It reports exact
  snapshot changes and neutral available operations, replays/forks Pi branch
  events, and locks malformed history. Eleven pure tests, three binding
  scenarios, artifact verification, and Pi smoke loading cover the first slice;
  no plugin decision field exists.

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
they change a phase's scope. [`R2.md`](R2.md#active-delivery-ledger--2026-08-07)
is the active work ledger; the other files should not grow duplicate status
lists.
