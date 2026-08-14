# pi_sparkles_swing_workbench

Status: **Experimental — network-free, LLM-owned workflow-context slice**

`swing_workbench` is a thin Pi shell for retaining exact completed-daily swing
workflow information across a session branch. It attaches canonical
[`finance_strategy`](../../finance/finance_strategy/README.md) evidence,
caller-supplied information states, opaque LLM/user plan declarations, and
observations or review facts. It can also retain an exact external journal
event handle without reading or interpreting that event. It does not acquire
market data, run an indicator, calculate risk, simulate an order, or decide
what any fact means.

The contract derives from the resolved `CG-SWING` trading-course
[Session 10 with the 10A and 10B addenda](../../../trading-course/sessions/10_cg_swing_daily_workflow_20260425.md).
The controlling rule is simpler than any workflow convention: the LLM owns
every interpretation, policy, candidate choice, plan, and next operation. The
plugin only preserves and efficiently exposes the exact information supplied
to it.

## Implemented Pi surface

| Surface | Current contract |
| --- | --- |
| `/swing [workflow-id]` | Show a compact summary for all branch workflows or one exact ID, followed by the neutral statement that the LLM chooses every interpretation and operation |
| `swing_candidates` | Attach one canonical `finance_strategy` receipt and bounded caller-supplied facts; report exact mechanical changes from the prior snapshot |
| `swing_plan` | Attach one immutable, content-bound, non-executable plan declaration authored by the LLM or user, with exact risk/rule/execution receipt references |
| `swing_review` | Append a content-bound observation or review record using caller vocabulary and exact evidence references |
| `swing_journal_link` | Attach one caller-selected `(workflow, journal, event, relation)` handle with its canonical content hash and attachment time; never read, trust, select, or interpret the event |
| `swing_snapshot` | Export deterministic structured state for all workflows or one exact workflow, including receipt payloads, changes, declarations, review records, and neutral available operations |
| `swing_state_export` | Write a canonical SHA-256-bound reconstruction log for all workflows or one exact workflow to a new caller-selected local file; identical retries are idempotent and different existing content is a conflict |
| `swing_state_import` | Load one caller-selected file with an exact expected hash into an empty branch; reconstruct its information state without choosing merge, overwrite, interpretation, or a next operation |

The root module exports
`extension(api: pi.ExtensionApi) -> Promise(Nil)`. The Pi/Promise shell decodes
bounded inputs, appends custom events, restores the active branch, and renders
results. Pi cannot autonomously invoke another plugin's tools, so composition is
through explicit versioned JSON receipts supplied by the agent.

## Decision boundary

The plugin has no setup, candidate, plan, process-quality, correctness,
sufficiency, or trade decision type. Structured snapshots state
`decisionOwner: "llm"` and `pluginDecisionFields: []`.

It may perform only structural mechanics needed to retain exact information:

- decode a canonical `finance_strategy` evidence receipt;
- verify a supplied SHA-256 content binding;
- keep the exact `cn`, `hk`, or `us` track and complete listing key;
- enforce workflow identity, event revision, count, and input bounds;
- retain caller-selected external journal/event IDs, relation vocabulary, and
  canonical content hashes exactly;
- compare facts by exact typed equality and report added, changed, unchanged,
  or removed;
- replay the active session branch exactly;
- construct, verify, and replay a canonical portable event log selected by the
  caller;
- expose a neutral list of available operations.

Those mechanics do not establish that evidence is correct, trustworthy,
sufficient, usable, current enough, professionally appropriate, or actionable.
They do not qualify or reject a setup, rank a candidate, accept a plan, select a
quantity, recommend an order encoding, judge a review, or choose the next
operation.

## Information model

A candidate snapshot contains one exact strategy evidence receipt plus bounded
facts. Each fact has a caller-assigned role (`required`, `optional`, `ranking`,
or `context`), an exact detail string, receipt references, and one of these
states:

- `known`
- `unknown`
- `not_obtained`
- `conflicting`
- `decode_failure`
- `declared`
- `unsupported`
- `stale`
- `late`

These are retained information labels, not plugin conclusions. A false
predicate inside the strategy receipt remains distinct from absent or late
evidence. Missing market-data, indicator, risk, rule, execution, sector,
catalyst, or journal coverage can therefore be attached explicitly without
blocking this shell or being silently omitted.

The plan payload is opaque user/LLM data. Its hash, source strategy receipt,
origin, receipt references, and creation time are retained exactly. Attaching
the same plan is idempotent; a different replacement is rejected structurally
so a declaration cannot be silently rewritten. A plan is never an order or an
authorization.

Review records preserve caller-selected `recordKind` vocabulary. They may refer
to the attached plan and any evidence receipts, but the plugin does not infer
adherence, discipline, bias, emotion, outcome quality, or a response.

## State and lifecycle

State is a strict contiguous event log in Pi custom session data:

- `candidate_attached`
- `plan_attached`
- `review_attached`
- `journal_reference_attached`

Resume replays the current branch. A fork inherits only the events Pi supplies
for that branch and then diverges. A session-tree change rebuilds the projection
from the new active branch. Malformed JSON, unknown schema/version, invalid
content binding, an impossible transition, or a revision gap locks mutation on
that branch instead of overwriting history.

`swing_state_export` makes the selected projection portable as a deterministic
contiguous reconstruction log. Export creates a mode-0600 local file through a
bounded atomic effect. It never overwrites different existing content; an
exact lost-ack retry returns `already_stored`. Import requires the exact
canonical content hash and an empty target branch. It never merges or replaces
branch state; an exact retry returns `already_imported`. The imported revision
is the portable log revision, while `sourceRevision` retains the source branch
revision. For an exact-workflow export these can differ because unrelated
workflow events are intentionally absent.

Journal references remain external handles: `trade_journal` can resolve them
from caller-selected local JSONL in another Pi session. This plugin makes no
network request, reads no credential, submits no order, and runs no background
monitor. Portable JSON is user-owned plaintext; ownership, encryption, access
control, backup, and synchronization remain `not_obtained` facts.

## Package surface

| Module | Responsibility |
| --- | --- |
| `pi_sparkles_swing_workbench` | Pi/Promise registration, branch restoration, event append, and notification shell |
| `pi_sparkles_swing_workbench/decode` | bounded runtime decoding into typed inputs |
| `pi_sparkles_swing_workbench/domain` | pure content binding, information facts, declarations, review records, and exact fact changes |
| `pi_sparkles_swing_workbench/state` | pure versioned workflow transitions, event encoding/decoding, and replay |
| `pi_sparkles_swing_workbench/portable` | pure canonical selection, reconstruction-log receipt, hash verification, and replay metadata |
| `pi_sparkles_swing_workbench/render` | deterministic summaries and structured snapshots with neutral available operations |
| `pi_sparkles_swing_workbench/effect/store` | generic mutable cell only; no business logic |
| `pi_sparkles_swing_workbench/effect/portable_file_ffi` | generic bounded local read, lock, compare/create, and atomic replacement effects only |

## Current bounds

- 50 workflows per active branch;
- 20 candidate snapshots per workflow;
- 100 review records per workflow;
- 100 external journal event references per workflow;
- revision 10,000 maximum;
- 64 facts per candidate snapshot;
- 64 receipt references per fact or receipt-reference collection;
- 200,000 characters for a canonical strategy receipt;
- 20,000 characters for a plan or review payload;
- 1,000 characters for a fact detail.
- caller-selected portable-file bounds from 1 byte through 100,000,000 bytes.

Exceeding a bound or supplying an invalid hash rejects that requested mutation.
It does not discard another workflow or reinterpret the input.

## Professional workflow fit

The stored context can support the daily rhythm from the course—after-close
inspection, LLM-authored planning, next-session comparison, monitoring facts,
and post-exit review—without embedding that rhythm as a plugin state machine.
`/swing` and `swing_snapshot` expose exact facts, changes, and available
operations; the LLM decides which workflow matters and which operation, if any,
to request.

Additional provider receipts, indicator variants, risk expressions, execution
models, alerts, and journal schemas can be composed incrementally. The current
acceptance catalog now includes exact sector/regime, catalyst, task-time, and
point-in-time universe/candidate observation families on all three tracks.
Their breadth remains incremental;
an absent family limits available information but does not require the
workbench to know correctness or make a fallback decision.

## Verification

The package has deterministic offline coverage for receipt/hash binding,
information-state preservation, fact deltas, track isolation, immutable plans,
review references, replay/revision failures, deterministic no-decision
snapshots, and malformed histories. Binding tests cover attachment of a
candidate/plan/review, exact tool-facing JSON, resume, fork, branch locking,
portable-file conflict behavior, and restoration in a distinct plugin instance.
The bundled artifact exports Pi's required default factory and smoke-loads
without a model call.

Five additional seeded acceptance tests compose the workbench test surface with
the pure `finance_replay` and `finance_journal` contracts. They exercise the
caller/LLM-declared after-close → plan → preflight → monitor → review sequence
for `cn`, `hk`, and `us`; exact interruption/resume; replay batch equivalence;
journal JSONL portability; track-specific exception triage; and mechanical
stage durations. The package has 20 pure tests in total. These fixtures prove
composition and auditability only: they do not establish provider coverage,
positive expectancy, professional sufficiency, or whole-product acceptance.

The repository-level deterministic acceptance lane also drives the actual
bundled `swing_workbench` and `trade_journal` tool interfaces for `cn`, `hk`,
and `us`, including exact branch restart and local journal reload. Its
acceptance shell now invokes the actual bundled CN/HK/US OHLCV tools over exact
scripted response bytes and copies each complete tool result plus its
market-owned gap receipt. The Gleam fixture builder composes
indicator-request, risk-request, track-owned effective-rule, execution
semantic, sector/regime, catalyst, exact task-time, and point-in-time
universe/candidate receipts. The expanded nine-receipt catalog is attached and
content-hash verified on each track. Provider fixtures remain non-live and
explicitly non-authenticating, and rule
hashes remain content hashes rather than provider signatures.
The US universe/candidate receipt is built from the actual
`finance_market_alpaca` asset decoder over exact scripted response bytes and
retains every provider asset field. CN/HK universe rows remain synthetic.
The deterministic lane also attaches the three exact stored journal event
handles to each workbench, replays revision 8 from five workflow events plus
three reference events, and verifies a fresh journal plugin instance can find
the same events by workflow ID. It passes three track journeys with 173
assertions.

The opt-in live tutor lane gives the configured Pi model the same bounded US
receipt catalog and drives thirteen ordered calls through candidate inspection,
plan, preflight, monitor, replay, review, final snapshot, and journal storage.
At each decision stage the model independently selects one neutral
content-bound alternative; the verifier proves the selected hashes, selected
plan reference, all nine catalog hashes, final snapshot, and `llm_declared`
journal payload agree while the workbench exposes an empty plugin-decision
field list. A fresh Pi process with the same native session ID first verifies
exact revision-8 restoration, then attaches the stored journal handle and
verifies revision 9 from nine contiguous extension events, then writes the
caller-selected portable file. A third process uses a distinct Pi session ID,
recovers the journal handle, imports the exact expected portable hash into its
empty branch, and verifies an identical revision-9 snapshot. These 21 calls
prove caller-selected cross-session state reconstruction without giving the
plugin a restore, merge, interpretation, or operation decision.
The live lane makes real model calls and is not part of the default suite.

```sh
bun run check -- swing_workbench
bun run test:unit -- swing_workbench
bun run test:acceptance -- swing
bun run build -- swing_workbench
bun run test:aggregate:pi
bun run test:live:tutor
```

## Non-goals

- No provider client, identity resolver, calendar, indicator engine, sector or
  news model, risk calculator, fee table, fill simulator, journal database, or
  managed/synchronized/encrypted storage service.
- No plugin-owned readiness, correctness, sufficiency, candidate, rank,
  recommendation, next-action, plan, order, or trade decision.
- No autonomous monitoring, paper order, live order, broker fallback, or hidden
  policy default.
- No inferred psychology, diagnosis, confidence, edge, expectancy,
  suitability, process score, or automatic risk change.
- No silent replacement of unknown information with model knowledge, cached
  prose, another track, a looser timeframe, or a different provider.
