# pi_sparkles_swing_workbench

Status: **Designing — CG-SWING shell; implementation prerequisites open**

`swing_workbench` is the thin Pi workflow for a completed-daily-bar swing
trader. It assembles exact identity, daily data, feature, event, market-rule,
risk, execution-capability, watchlist, and journal receipts around the pure
[`finance_strategy`](../../finance/finance_strategy/README.md) contract. It
does not own any of those engines.

The design derives from the resolved `CG-SWING` trading-course
[Session 10 with the 10A and 10B addenda](../../../trading-course/sessions/10_cg_swing_daily_workflow_20260425.md).
It is a design document only: no Gleam project is created until the prerequisite
typed contracts listed below are implementable.

## User stories

A trader can:

- preflight whether a named strategy is actually supported for one exact
  listing, track, session, account profile, and broker profile;
- scan a point-in-time universe and see qualified, rejected, not-ready, and
  late candidates without those states being conflated;
- inspect every predicate, optional confirmation, ranking fact, assumption,
  source cutoff, and evidence link;
- save a read-only entry/invalidation/target/expiry intent before any order;
- attach risk and execution-readiness receipts without treating the plan as an
  order;
- monitor the saved definition and plan using new dated observations;
- compare planned and observed actions, including an unfilled entry, gap-through
  stop, or unknown stop/target ordering;
- judge process adherence separately from profit and loss.

The workbench never says that a setup is safe, guaranteed, optimal, or proven
profitable.

## Professional daily rhythm

The primary interface follows the trader's routine instead of exposing a menu
of finance functions:

1. **After the close — scan and triage.** Show what changed, which candidates
   newly qualified, which became invalid or not ready, and the few exceptions
   needing inspection. Preserve the rest in a compact working set.
2. **Plan the next session.** Drill from a candidate into its predicate evidence
   and create the entry, invalidation, target, expiry, and monitoring intent
   without retyping identity, strategy, or source context.
3. **Before the next open — preflight.** Revalidate freshness, corporate events,
   market/account rules, risk, and executable-order support. Highlight only
   changes from the saved plan; block on material conflicts.
4. **While holding — monitor by exception.** Lead with invalidation, stop/target,
   gap, event, stale-data, and expiry changes. Do not make the trader reread the
   original dossier on every check.
5. **After exit and periodically — review.** Reuse the immutable plan and
   observed events, ask only for facts the system cannot know, and separate
   process adherence from outcome.

`/swing` with no sub-action resumes the next legal step for the active branch.
It leads with “needs attention,” “changed since last review,” and “next action,”
then offers evidence drill-down. Expert users retain direct tools, stable JSON,
and batch candidate triage; convenience never suppresses a blocker or source.

Workflow acceptance includes task-time and interruption tests: a trader must be
able to resume a saved working set without reconstructing context, inspect why a
candidate changed state in one drill-down, and complete the routine path without
copying identifiers or evidence between tools.

## Proposed Pi surface

| Surface | Contract |
| --- | --- |
| `/swing` | resume the active daily loop; lead with changed/attention/next items, then expose status, exact context, blockers, and evidence drill-down |
| `swing_candidates` | evaluate a bounded caller-supplied point-in-time universe and return per-candidate reason/evidence trees |
| `swing_plan` | compose a setup-qualified result with supplied risk, market-rule, and execution-capability receipts; save an immutable plan intent only |
| `swing_review` | fold observed fills/bars/exits and supplied journal facts against the saved definition and plan |

The root module will eventually export
`extension(api: pi.ExtensionApi) -> Promise(Nil)`. The Pi/Promise layer decodes
inputs, obtains explicit capabilities, invokes pure domain modules, renders
bounded results, and records typed custom-session events. No business policy
belongs in the shell or JavaScript FFI.

Pi cannot autonomously call another plugin's tools. `/swing` therefore provides
bounded orchestration guidance and custom data; the agent performs explicit
tool calls. Composition is through stable versioned JSON receipts rather than
an assumed in-process plugin registry.

## Planned package surface

| Module | Responsibility |
| --- | --- |
| `pi_sparkles_swing_workbench` | Pi/Promise effect shell and surface registration only |
| `pi_sparkles_swing_workbench/decode` | bounded runtime decoding into typed receipt inputs |
| `pi_sparkles_swing_workbench/domain` | pure working-set, preflight, next-action and workflow composition laws |
| `pi_sparkles_swing_workbench/state` | pure versioned custom-event replay and branch projection |
| `pi_sparkles_swing_workbench/render` | deterministic attention/change/next summaries and evidence drill-down |

The first custom-data schema will include stable events for working-set
selection, candidate evaluation attachment, immutable plan attachment,
observation attachment, expiry/exit attachment, and review attachment. Every
event carries its schema version, workflow ID, exact track/listing key,
strategy version, receipt hashes, event time, and predecessor revision. Payload
bounds and redaction rules are part of decoding, not rendering conventions.

## Workflow

```text
exact listing + active track
          |
          v
capability preflight --------------------------------> NotReady report
          |
          v
point-in-time universe + completed daily receipts
          |
          v
versioned feature/event receipts --> finance_strategy --> SetupQualified
                                                        /             \
                                                       v               v
                                             risk receipt      rule/execution receipt
                                                       \               /
                                                        v             v
                                                   Accepted plan intent
                                                            |
                                               watch / observe / expire
                                                            |
                                                            v
                                            planned-versus-observed review
```

Each arrow preserves the exact `cn`, `hk`, or `us` track and complete listing
key. No step may resolve, substitute, or relabel a provider, calendar, venue,
currency, account, or broker profile silently.

## Required inputs

The shell accepts bounded, versioned receipts rather than loose prose or bare
numbers:

- validated active-track context and exact listing identities;
- point-in-time universe membership and eligibility facts;
- canonical completed-daily OHLCV acquisition and gap receipts;
- feature receipts from the future reviewed `finance_indicators` slice;
- dated event/catalyst evidence where selected by the definition;
- exact calendar, listing/status, tick, lot, fee/tax, resale, and other required
  market-rule receipts;
- strategy definition and prior transition receipt;
- account-scoped risk result from the future trade-plan/risk contract;
- exchange and broker execution-capability receipt;
- optional watchlist/alert handles and journal-schema receipt.

An input is incompatible when its track, listing, session, definition version,
source cutoff, adjustment basis, unit, or evidence hash disagrees with another
required input. Incompatibility returns `NotReady` with all detected conflicts;
the shell never chooses a favored receipt.

## Capability preflight

Preflight reports each dependency as `Ready`, `NotReady(reason)`, or
`Unsupported(scope)`. A candidate may be screened only when its required data
and predicate dependencies are ready. It may become `Accepted` only when sizing
and executable-order dependencies are also ready.

Open prerequisites are:

- `CG-MARKET-DATA` for minimum completed-daily receipts, freshness,
  volume/turnover semantics, source rights, and trader-facing quality states;
- `CG-TECH` for exact indicator and adjustment-production receipts;
- `CG-RISK` and `pi_trade_plan` for account-scoped size, gap, notional, heat,
  rounding, and fee-reserve decisions;
- `CG-DAY`, `finance_execution`, and broker capability input for order support
  and fill/cost semantics;
- `CG-PSYCHOLOGY` and `journal_schema` for durable pre/post-trade review fields;
- sector/regime and catalyst providers when a selected definition makes them
  required rather than optional context.

Missing predicate, size, or executable-order dependencies block. Missing
optional confirmation or ranking evidence remains explicitly `Unknown` and may
produce an audit warning. No warning can authorize a plan that is otherwise
`NotReady`.

## State and lifecycle

The plugin stores only immutable workflow events and exact receipt references in
Pi custom session data. It does not copy provider datasets or treat session data
as cross-session durable storage.

- reload re-registers surfaces without duplicating events;
- resume replays a strictly versioned, contiguous event stream;
- fork inherits only the branch history supplied by Pi and then diverges;
- branch changes rebuild the visible workflow from that branch;
- malformed, unknown-version, hash-mismatched, or non-contiguous events lock
  mutation and return a repair/export report;
- compaction does not replace structured state with summary prose;
- shutdown performs no network write, order submission, or hidden persistence.

Changing a definition version does not rewrite an existing candidate or plan.
The trader starts a new evaluation whose relationship to the previous one is
explicit.

## Rendering and budgets

Candidate output is ordered deterministically and bounded by caller-visible
limits. A result shows:

- track, exact listing, signal session, evaluation cutoff and strategy version;
- state and required-predicate reason tree;
- optional confirmations/ranking with `Present`, `Unknown`, or `Conflicting`;
- desired plan values separately from supported executable order fields;
- readiness gaps and the plugin/tool responsible for supplying each receipt;
- source, freshness, adjustment basis, units, entitlement and evidence links;
- omitted-row counts and a continuation/export path when a table is truncated.

Charts, when later composed, are views over the same typed receipts and always
retain a structured-data fallback. The workbench performs no hidden second
calculation for display.

Initial limits must be explicit for candidate count, evidence roots per
candidate, transition count, serialized custom-data bytes, and rendered rows.
Exceeding a limit returns a typed partial/too-large result; it does not discard
evidence silently.

## Permissions and trust boundary

The first slice is read-only and non-interactive except for explicit Pi command
and tool calls. It has no credential environment variables and no direct
network, filesystem, or broker access. A plan is not an order. Paper or live
execution requires a separate installed plugin, an exact accepted draft, and
its own authorization and safety gates.

Provider content, journal prose, and imported labels are untrusted data. They
cannot alter tool policy, track identity, risk limits, execution permissions,
or system instructions.

## Acceptance journeys

Seeded offline tests must cover at least:

1. a completed-session qualified setup whose risk receipt reduces size for gap
   exposure before it becomes accepted;
2. a complete evaluation rejected by a false RSI predicate;
3. an accepted entry intent expiring unfilled after a gap above its ceiling;
4. a later session opening through the desired stop without claiming a stop-
   price fill;
5. a daily bar touching target and stop and returning `UnknownOrdering`;
6. a qualified setup blocked because the desired stop cannot be mapped to a
   supported executable order;
7. missing gap-stress/account policy returning `NotReady`;
8. missing adjustment provenance, incomplete pagination, stale evidence,
   provider gap, insufficient warm-up, and ambiguous identity returning
   distinct `NotReady` reasons;
9. the same symbol on a conflicting track being rejected without fallback;
10. a losing, gap-affected trade that followed the saved plan and a profitable
    trade that violated it.

Pure tests cover the workflow fold and compatibility laws. Later implementation
also requires FFI input contracts, artifact default export, Pi load/reload/
resume/fork tests, malformed-state locking, rendering bounds, and architecture
checks. Provider plugin unit tests remain fixture-only.

## Implementation boundary

This README graduates only the `CG-SWING` interaction design. Implementation
must begin with the network-free receipt preflight, reason rendering, and pure
workflow transitions. Candidate acquisition, indicator arithmetic, sizing, and
execution remain unavailable until their own gates and packages are ready.

When implementation starts, the directory gains its independent `gleam.toml`,
`src/`, `test/`, and package version. Hex will distribute reviewed Gleam/FFI
source, not `dist/`; users build the Pi adapter and bundle through the root Bun
tasks. The exact commands will be:

```sh
bun run check -- swing_workbench
bun run test:unit -- swing_workbench
bun run build -- swing_workbench
bun run test:pi -- swing_workbench
```

No Pi, binding, or provider version is claimed tested while this remains
design-only.

## Non-goals

- No provider client, symbol resolver, calendar, indicator engine, sector model,
  news classifier, risk calculator, fee table, or fill simulator.
- No intraday/day-trading surface, short selling, options, futures, FX, crypto,
  leverage default, autonomous monitoring, paper order, or live order.
- No hidden score that collapses required predicates and optional evidence.
- No inferred psychology, edge, confidence, suitability, or recommendation.
- No silent replacement of unknown data with model knowledge, cached prose,
  another track, a looser timeframe, or a different provider.
