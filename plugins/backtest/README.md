# backtest

Status: **Tier 4 ProductUseful — completed 2026-08-12** · version: `0.1.0` · target:
JavaScript/Bun

`backtest` is a thin, stateless Pi shell over the completed-daily scripted
interpreter and reproduction contracts in `finance_replay`. It registers
exactly three tools:

- `submit_run` verifies one canonical run definition and an ordered canonical
  event script, executes the pure replay fold under caller budgets and an
  explicit cancellation point, and returns the exact processed prefix and stop
  state.
- `inspect_events` reconstructs the same run and pages only the processed event
  prefix in fold order, with event payloads omitted unless explicitly requested.
- `export_backtest_manifest` reconstructs the run, builds one canonical reproduction
  manifest whose primary run receipts come from the verified definition, and
  exports a bounded page of canonical event JSONL.

The professional scope and stop point come from
[Session 16](../../../trading-course/sessions/16_cg_quant_shared_replay_information_contract_20260807.md)
and the rank from
[Session 17](../../../trading-course/sessions/17_product_plugin_portfolio_steering_20260807.md).
The plugin composes the existing `finance_replay.definition`, `event`, `fold`,
`scripted`, and `reproduction` laws. It does not create a second replay engine,
event format, cursor, or manifest format.

## Exact run input

All three tools receive the same immutable run declaration:

- `cadencePolicy` must be
  `caller_declared_completed_daily_cash_equity_v1`. This declaration does not
  turn a daily row into exchange or provider proof; exact event facts and their
  referenced receipts remain controlling.
- `definition.canonicalJson` is the exact canonical
  `finance_replay.RunDefinition` envelope and `definition.contentHash` is its
  expected digest. The plugin decodes, re-encodes, and hashes it before use.
- Each event supplies its exact canonical `finance_replay.Event` envelope and
  expected canonical content hash, plus caller-declared elapsed milliseconds
  and a session increment of zero or one. The plugin derives encoded byte cost
  from the actual UTF-8 canonical JSON; callers cannot understate byte use.
- `budget` declares positive maximum events, encoded bytes, elapsed
  milliseconds, and sessions. The plugin passes these exact limits to
  `finance_replay.scripted.run`.
- `cancellation` is either `continue` or `cancel_before`, with an exact replay
  clock, cancellation instant, and attributed actor. Cancellation happens
  before the first event at or after that replay clock.

Every decoded event must name the verified run-definition ID. Core fold laws
reject event-ID collisions, idempotency-key conflicts, backward replay clocks,
and backward known event times. Events are never reordered, deduplicated,
netted, repaired, or silently dropped. Exact idempotent retries remain core
`AlreadyStored` outcomes and do not advance the retained fold state.

The first slice accepts at most 10,000 supplied events, 200,000 UTF-8 bytes per
canonical event envelope, and 2,000,000 UTF-8 bytes for the definition
envelope. These boundary limits are in addition to the caller's smaller run
budgets and the core's 65,536-character event-payload limit.

## `submit_run`

`submit_run` executes the supplied script synchronously and locally. “Submit”
does not mean enqueue, persist, schedule, or launch a background job.

The compact result includes:

- verified definition and calculated run-state handles;
- core fold status and revision;
- processed and omitted event counts;
- the exact stop variant: `input_exhausted`, `budget_truncated`, or
  `cancelled`, including the controlling budget/replay cursor or cancellation
  facts;
- exact counts by retained event kind and ambiguous ordering facts; and
- `decisionOwner: "llm"`, an empty `pluginDecisionFields`, and only the three
  available plugin operations.

`InputExhausted` reports only that the supplied script ended. It does not imply
that a terminal `RunCompleted` event exists. The separate fold status remains
`open`, `completed`, `truncated`, or `cancelled` according to the retained event
stream. A budget or cancellation stop retains the exact prefix and never claims
completeness.

## `inspect_events`

The caller supplies the same run declaration plus `offset`, `limit`, and
`includePayloads`. The plugin replays the declaration and pages
`fold.events(scripted.state(result))`; it never reads ambient or prior tool
state.

Each compact row retains event ID, kind, replay clock, semantic content hash,
canonical content hash, and exact canonical-envelope byte count. The complete
canonical event envelope appears only when `includePayloads` is true. Paging
preserves fold order and returns the same run-state handle at every offset.
`offset` may equal the processed count and `limit` is 1 through 200.

Events beyond a budget or cancellation stop are not presented as processed.
The result reports their exact omitted count and the stop cursor so the LLM can
distinguish run truncation from page continuation.

## `export_backtest_manifest`

The caller supplies the same run declaration, reproduction-only metadata, and
an event-export page budget. The plugin constructs
`finance_replay.reproduction.Manifest` directly. It takes the following fields
from the verified run definition rather than trusting duplicate declarations:

- run-definition digest;
- partition receipt;
- universe-manifest hash;
- dataset-manifest hash; and
- execution-model receipt.

The caller explicitly supplies environment versions, trial IDs, ordered source
hashes, transformation/calendar/rule/corporate-action/cost/output/checkpoint
receipts, seed/random-stream facts, entitlement limitations, omitted/unknown/
conflicting dependencies, export provenance, and privacy policy. The plugin
adds mechanical effect facts for cadence policy, exact budgets, stop state,
processed count, and omitted count; it makes no interpretation of them.

The result contains the canonical manifest JSON and handle plus a bounded
canonical event-JSONL page. `offset`, `maximumEvents`, and
`maximumCharacters` are explicit. The plugin selects the longest ordered
prefix within both limits. It reports `complete`, `returnedCount`, and
`nextOffset`; a partial page is never labelled a complete reproduction bundle.
If one event cannot fit the character budget at the current offset, the call
fails with its required character count instead of returning a zero-progress
cursor.

The fixed directory names `receipts/` and `checkpoints/` are canonical bundle
metadata only. This slice writes no files. A matching digest proves content
coherence, not provider origin, licence permission, source correctness,
research quality, or deployability.

## Decision and effect boundary

The LLM chooses every definition, event, receipt, budget, cancellation point,
inspection page, export page, interpretation, and next operation. The plugin
performs only canonical decoding, exact identity checks, deterministic replay,
mechanical counting, stable paging, and canonical reproduction construction.

It performs no:

- market-data or provider fetch;
- filesystem, database, cache, registry, queue, job, or session-state mutation;
- hidden clock, sleep, randomness, credential, entitlement lookup, retry, or
  background execution;
- event generation, interpolation, ordering choice, branch selection, netting,
  fill prediction, parameter search, model training, or portfolio optimization;
- correctness/sufficiency judgment, validation pass/fail, significance test,
  edge/robustness claim, preferred run, deployment decision, recommendation,
  authorization, or next-action selection.

## Architecture, lifecycle, and verification

The root Pi module is only the effect shell: it registers the three tools,
decodes untrusted inputs, calls pure domain operations, and resolves or rejects
the tool promise. Namespaced domain modules contain all definition/event/run/
manifest validation and rendering. They import no Pi or promises. No JavaScript
FFI is required.

Lifecycle: **ProductUseful** in T4. Nine focused tests and four bundled adapter
scenarios cover:

- canonical definition/event acceptance and hash drift;
- event run-ID mismatch, duplicate IDs, idempotency conflict, and ordering
  failures;
- input exhaustion distinct from completed fold status;
- all four budgets and cancellation with exact retained prefixes/cursors;
- stable event paging and explicit payload omission;
- reproduction-definition receipt binding and canonical manifest hash;
- bounded full and partial JSONL export, including no-progress rejection; and
- absence of persistence claims, verdict fields, and plugin-owned decisions.

No tutor request or `/tmp/QA01.md` is needed for this slice because Sessions 16
and 17 already resolve the exact completed-daily scripted replay and
reproduction boundary. Expanding into persistent run storage, a new provider,
intraday replay, automatic search/optimization, validation verdicts, or
deployment decisions reopens the applicable review gate.

Artifact export, installed-Pi smoke, all architecture checks, and the full
repository regression passed on 2026-08-08. The full run included 141
binding/artifact tests with 977 assertions and the three-track 177-assertion
swing acceptance lane.
