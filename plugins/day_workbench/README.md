# day_workbench

Status: **Experimental** · version: `0.1.0` · target: JavaScript/Bun

`day_workbench` is the narrow rank-20 implementation authorized by
[Course Session 22](../../../trading-course/sessions/22_cg_day_full_workflow_contract_20260809.md).
It is a network-free consumer of caller-supplied intraday evidence. It validates
packet identity, licence and entitlement declarations, sequence integrity,
session facts, and exact source lexemes; performs only an explicitly requested
calculation; and advances only an explicitly supplied workflow transition. It
does not acquire a feed, verify a caller's real-time claim, decide readiness or
a trade, or mutate an order/account.

The plugin registers three stateless read-only tools:

- `day_inspect` validates one content-hash-bound evidence packet and returns a
  compact session/feed/integrity/evidence-matrix projection plus an optional
  bounded page of retained input-order events.
- `day_calculate` validates the same packet and performs exactly one selected
  spread, midpoint, displayed-notional, quote/trade change, volume, turnover,
  VWAP, high, low, range, or depth calculation over an explicit window,
  event-filter, scale, and rounding policy. Integrity gaps make dependent
  calculations unperformed.
- `day_transition` applies one typed LLM/user declaration or mechanical
  session/evidence fact to an explicit caller-retained workflow state. It
  returns canonical next-state JSON and a SHA-256 receipt. It stores nothing,
  authorizes nothing, and treats `Ready` only as Session 22's
  `evidence_available` state—not a readiness-to-trade verdict.

This pure caller-retained transition design implements Session 22's
"first-slice stateless" requirement. A `branchId` remains part of state
identity so a caller can keep distinct Pi branches separate. Pi persistence,
portable storage, and durable journal links are later explicit effects rather
than an ambient mutable store.

## Evidence packet v1

Tools accept the exact JSON payload plus its SHA-256. The packet has one exact
listing/session stream and includes:

- `schemaVersion: "pi_day_intraday_packet_v1"`, packet ID, exact `cn`/`hk`/`us`
  track, listing ID, MIC, session date, timezone, provider, feed, currency, and
  acquisition receipt;
- `RealTime` or `Delayed(minutes)` as a caller/provider claim, always returned
  as `caller_attested_not_verified`;
- a licence label/receipt, exact venue coverage, redistribution state, and
  optional retention/display/non-display/derived/caching/logging/fixture facts;
- sequence scope (`per_feed` or `per_listing`), heartbeat expectation, explicit
  phase intervals with track-owned rule receipts, and bounded canonical events;
- every event's exact packet identity, feed, entitlement, licence/acquisition
  references, integer Unix-millisecond clock facts, sequence state, conditions,
  and source lexeme dictionary.

Supported event variants are quote, trade, depth snapshot/delta, indicative
auction, official auction result, halt, status change, correction, cancel/bust,
and heartbeat. Numeric market fields remain exact decimal strings until the
selected calculation parses them. Unknown sequence/time facts are explicit
nulls; they are not synthesized.

## Integrity and identity laws

- Packet, event, track, listing, MIC, feed, currency, entitlement, licence, and
  acquisition identities must match exactly. A mismatched event is retained and
  flagged but excluded from calculations; no feed, venue, or track fallback
  occurs.
- Exact duplicate event IDs collapse with a duplicate count. Different content
  under one event ID is retained as a conflict. Input order is preserved.
- Increasing sequence, gaps, decreases, reset-to-one, missing sequence, depth
  snapshot/delta binding, unknown correction targets, and clock-order failures
  remain explicit integrity facts. No event is silently reordered or invented.
- A gap invalidates dependent stateful calculations for the requested window;
  depth remains unavailable after a depth discontinuity until a later bound
  snapshot. Truncated packets make all completeness-dependent calculations
  unperformed.
- A content hash proves only byte fidelity. Entitlement, licence, acquisition,
  and provider identities remain declarations unless a later adapter supplies
  independently authenticated evidence.

## Calculation boundary

All operands come from retained source events and are exposed with event IDs,
formula, window, filter, exact output unit, scale, and rounding. Odd-lot,
off-exchange, and condition-code inclusion are explicit caller policies.
Division by zero, missing operands, decode failures, incompatible currency/
unit, identity conflicts, sequence gaps, and truncated evidence are
`unperformed`, not zero or a fallback value.

No output is a signal, setup, confirmation, qualification, momentum/breakout
label, liquidity/staleness verdict, candidate rank, order preference, likely
fill, recommendation, or next action. Relative volume and expected curves,
candidate scans, queue models, alerts, and advanced execution simulations are
deferred until a concrete depth trigger.

## Workflow boundary

Workflow states are `Preparation`, `Acquiring`, `Ready`, `PlanDeclared`,
`Monitoring`, `EntryIntent`, `ExitIntent`, `Closeout`, and `Review`. State
contains only exact identifiers, revision, current state/meaning, and an ordered
bounded transition receipt log. LLM/user declarations own plan, monitoring,
entry/exit intent, abort/cancel, closeout, and review choices. Mechanical
transitions require exact evidence/session receipt references and expose only a
state fact. Idempotent identical retries return the same state; conflicting use
of an idempotency key fails closed.

The state payload is caller-retained and content-hash-bound on every call. It
contains no executable order payload. `confirm_entry`, `confirm_exit`, broker
order placement/routing/cancellation/replacement, paper mutation, automatic
closeout, and alerts remain outside this plugin and outside every Pi plugin in
the repository. The user performs any actual market action through external
means; T6 can later reconcile only imported or read-only receipts.

## Budgets and exclusions

The hard first-slice limits are one listing per packet, 10 MB payload bytes,
100,000 input events, 32 distinct conflicting variants per event ID, 10 depth
levels per side, 1,000 returned event rows, 1,000 returned integrity issues,
100 workflow transitions, 100 condition codes, and 4,096 bytes per source
lexeme. Additional integrity issues are counted as omitted. Embedded times and
sequences must be JavaScript-safe integers. Event deduplication and reference
checks use bounded indexes rather than repeated whole-packet scans. A depth
delta, correction, or cancel/bust may refer only to an earlier snapshot or
original event; a later matching identifier cannot satisfy causality.
The caller supplies lower event/output budgets. Exhaustion is explicit with a
continuation offset; no sampling, hidden dropping, background acquisition,
network, filesystem, credential, clock, sleep, broker, or order effect exists.

Licensed acquisition, actual real-time streaming, provider authentication,
multi-listing scans, short/margin/derivative policy, smart routing, automated
monitoring, durable persistence, paper/live order mutation, and every trading
judgment remain outside this slice.

## Verification

Ten focused Gleam tests cover packet identity/licence/entitlement and every
event variant; duplicate/conflict, sequence gap, depth binding, correction,
cancel/bust, truncation, and filtering laws; exact quote/trade/depth
calculations and unperformed counterexamples; and branch-bound workflow
transitions, idempotence, replay validation, and the `CG-LIVE` boundary. Six Bun
binding scenarios cover all three bundled tools, caller-attested claims,
source-bound operands, gaps/incompleteness, stateless transitions, malformed
hashes, and cancellation. Warnings-as-errors, architecture, artifact export,
installed-Pi smoke, and the full repository regression pass complete the
Experimental slice.
