# Professional product readiness standard

This repository builds real finance workflows through Pi plugins. A compiling
calculation, decoder, or caller-supplied packet is not automatically a useful
product. The domain contract must be correct, the Pi architecture must be
explicit, and a named professional journey must work end to end.

Delivery is governed by the six role products in
[`PRODUCT_TIERS.md`](PRODUCT_TIERS.md) and [`tiers.json`](tiers.json). Product
tiers and `cn`/`hk`/`us` tracks are not a matrix: each tier has one declared
anchor acceptance profile, while other track operations remain focused exact
contracts or are reported `track_partial`.

This standard is controlled by the finance tutor's completed audit:

- [Session 40](../trading-course/sessions/40_professional_product_readiness_audit_20260811.md): portfolio-wide readiness definitions, 81-design audit, implementation checklist, and Definition of Done;
- [Session 41](../trading-course/sessions/41_market_structure_source_product_contract_20260811.md): market structure, disclosure, source, HK/CN/SEC, cache, and tape product contracts;
- [Session 42](../trading-course/sessions/42_research_portfolio_monitoring_product_contract_20260811.md): research, portfolio, monitoring, company-intelligence, and durable artifact contracts;
- [Session 43](../trading-course/sessions/43_multi_asset_macro_product_contract_20260811.md): funds, fixed income, options, commodities, COT, crypto, macro, FX, and cross-market contracts;
- [Session 44](../trading-course/sessions/44_broker_live_operational_product_contract_20260811.md): broker observation, paper/live state machines, credentials, incidents, and compliance;
- [Session 45](../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md): uniform Pi tools, capability injection, lifecycle, five persona journeys, and cross-plugin acceptance;
- [Session 46](../trading-course/sessions/46_product_readiness_corrections_20260811.md): controlling chronology, input-path, maturity, dependency-DAG, and ambiguous-live-submission corrections.

Session 46 supersedes conflicting chronology or maturity wording in earlier
sessions. The audit concludes that all 135 catalog proposals are at least
domain- and architecture-ready. No unresolved finance-domain, Pi-architecture,
workflow, safety-design, or professional-acceptance question remains inside the
reviewed scope. Provider/access evidence and implementation remain real work,
but they are not hidden tutor gaps.

## Package inventory and tier status

Package maturity remains an honest inventory of existing code:

```text
Package: Draft -> Designing -> Implementing -> Experimental
Tier:    Queued -> BlockerResolution -> Building -> Verifying -> ProductUseful
```

- **Draft:** only a catalog proposal exists.
- **Designing:** a reviewed README binds the domain, first slice, architecture,
  user/LLM ownership, failures, external gates, tests, and exclusions.
- **Implementing:** an independent package, pure core, adapter boundary, Pi
  shell, and verification are being built.
- **Experimental:** the exact implemented contract builds, loads, passes its
  tests and bundled scenario, but the API or coverage may evolve. It describes
  existing package behavior only—not a delivery target, completed product, or
  permission for a toy, unauthenticated-source claim, missing failure state,
  hidden judgment, or unsafe effect. No new plugin is independently promoted to
  this state.
- **ProductUseful:** applies only to a whole tier. Its named professional
  journey works through a supported repeatable input path, compact response,
  drill-down, failure recovery, lifecycle, and cross-plugin handoffs. The API
  may still evolve.

The active tier and its exact blockers are recorded in `tiers.json`; there is
no selected-plugin queue. An external blocker identifies a provider, licence,
entitlement, credential, security, jurisdictional, storage, notification,
streaming, or human-authorization prerequisite. It is not a substitute for a
missing design and must be resolved before tier implementation begins.

## Uniform Pi-plugin contract

Every plugin implementation must provide the following, using `N/A` only with
an explicit reason:

1. An exact input identity: track, listing/MIC or instrument/series identity,
   scope, time basis, requested operation/policy, and instruction receipt.
2. Typed states for known, unknown, not obtained, unavailable, conflicting,
   decode failure, unperformed, truncated, cancelled, and externally blocked
   facts as applicable.
3. A compact first response targeted below 500 model tokens, containing scope,
   coverage, important limitations, a stable content-bound receipt handle, and
   neutral `available_operations`.
4. Bounded drill-down by stable handle to original lexemes, source leaves,
   formula trees, state transitions, alternatives, and correction lineage.
5. Deterministic budgets, pagination/cursors, truncation, cancellation, and
   partial-result behavior. No silent fallback, repair, or source substitution.
6. Structured errors that distinguish invalid input, identity ambiguity,
   provider failure, entitlement failure, rate limiting, decode failure,
   budget exhaustion, cancellation, state conflict, and unavailable evidence.
7. Source receipts retaining provider/authority role, retrieval and source
   times, content hash, entitlement, licence, coverage, and correction facts.
8. Structured observability with correlation/request IDs, timings, budgets,
   retries and failures, while never exposing secrets or private account data.

The plugin exposes facts, calculations, state and effects. The LLM/user owns
interpretation, benchmarks, assumptions, scenarios, thresholds, rankings,
recommendations, professional judgments, authorization, and next action unless
a cited contract explicitly assigns a purely mechanical choice to the plugin.

## Functional architecture

The evidence flow is:

```text
provider/user-owned input
        |
        v
provider adapter or bounded import
        |
        v
canonical finance observations/receipts
        |
        v
pure plugin domain calculation or transition
        |
        v
thin Pi shell: compact response + bounded drill-down
        |
        v
LLM/human interpretation and next explicit operation
```

These arrows are data/evidence flow and capability injection, never
plugin-to-plugin source imports. Shared pure packages may be imported according
to the finance dependency DAG. Plugin shells compose through Pi/LLM-visible
typed receipts and handles.

- Domain modules import no Pi, Promise, FFI, HTTP, clock, randomness, storage,
  environment, credentials, or mutable business state.
- Provider adapters use `finance_http` and explicit typed ports. They own
  bounded request plans, decoders, pacing/retry rules, cancellation,
  pagination, entitlement/licence facts, and fixture tests.
- The Pi root exports only `extension(api: pi.ExtensionApi) -> Promise(Nil)`
  and wires decode, capabilities, pure transitions, effect interpretation, and
  encoding.
- Track-owned packages remain isolated. No active navigation state, provider,
  ticker, or currency default may relabel an observation or select another
  market.

## State and lifecycle

Every plugin declares exactly one state class:

- **Stateless:** identical typed inputs produce identical outputs across new,
  resume, fork, reload, compaction, concurrency and shutdown.
- **Session-local:** Pi branch state uses atomic immutable transitions,
  content-bound version handles and stale-completion rejection. Forks become
  independent branches; no cross-branch mutation occurs.
- **Durable:** user-owned append-only events or versioned snapshots survive
  reload/restart, support replay/export/correction lineage, use idempotency
  keys, redact private fields, and define retention/compaction/concurrency.

Provider-owned account/order state is never represented as plugin-owned state.
It is observed through provider receipts and reconciled explicitly.

## Supported input path

ProductUseful requires at least one named, supported, versioned, repeatable
end-to-end input path appropriate to the tier's anchor journey:

- licensed or public provider acquisition with entitlement/source receipt;
- bounded user-owned import with content hash and documented schema;
- canonical upstream receipts from tools delivered by ProductUseful tiers; or
- a deterministic local path when the professional task itself is local-only.

An ad hoc pasted fixture is not sufficient. A provider-neutral core can be a
valuable engineering milestone and can reach Experimental, but it must be
reported as `core_ready`, not as an end-to-end professional product.

Provider choice does not change the canonical domain model. Every adapter must
prove exact endpoint/source identity, authentication or public-access mode,
coverage, timestamps/latency semantics, corrections/completeness behavior,
entitlement/licence, budgets, fixture provenance, and intended output rights.

## Verification and professional Definition of Done

A tier may be called ProductUseful only when all applicable items pass together:

- pure unit, law/invariant, invalid/unknown/conflict, and transition-sequence
  tests;
- real response-byte provider decoder fixtures, with secrets and private data
  removed under an explicit fixture right;
- FFI/binding, artifact export, installed-Pi smoke, architecture, and full
  repository regression checks run once at the tier verification boundary;
- the supported input path exercises identity → acquisition/import → decode →
  canonical receipt → calculation/transition → compact response → drill-down;
- provider timeout/outage, malformed response, rate/entitlement failure,
  budget exhaustion, cancellation, omissions, conflicts, corrections, and
  continuation are exercised without crashes or silent fallback;
- stateful plugins survive their declared reload/fork/resume/concurrency path;
- at least one complete applicable Session 45 persona journey runs with a real
  model and verifies every cross-plugin receipt handoff;
- the README documents the recurring professional task, supported input path,
  operations, limits, external gates, source rights, failure recovery, and
  forbidden conclusions.

## Honest partial-product reporting

`finance_track_status` and `/finance-setup` should expose these exact facts:

- `core_ready`: pure/domain implementation exists;
- `adapter_missing`: supported acquisition/import path is absent;
- `composition_missing`: individual components exist but the professional
  workflow handoff does not;
- `acceptance_pending`: components exist but the persona journey has not passed;
- `external_blocked(reason)`: an exact external prerequisite is missing;
- `track_partial`: some of `cn`, `hk`, `us` are supported and others are not.

These are facts, not grades. An existing package may be Experimental and also
`adapter_missing`; no package is presented as ProductUseful independently. A
tier may be ProductUseful for its declared anchor profile while another track
is explicitly `track_partial`, provided the unsupported track is not required
by that tier's acceptance contract.

During tier construction, cross-package changes are one atomic working set.
Every touched package must remain formatted, buildable with warnings as errors,
and focused-test clean at each handoff; incomplete public tools, placeholder
successes, panic/TODO paths, and half-updated receipt producers or consumers are
forbidden. `bun run tier:checkpoint -- Tn` enforces this integrity rule without
promoting any package.

## Tutor reopen rule

New tutor input is required only when work exceeds the reviewed scope through a
materially different instrument class, market track, professional workflow,
effect boundary, calculation with an interpretive surface, time resolution, or
direction/leverage model.

Provider-adapter implementation, credentials, licences, additional fixtures,
performance work, storage-adapter selection, UI rendering, and another venue
within an already specified track are engineering/access work under the
existing contracts. If such work reveals a genuinely new market semantic or
professional decision, stop and formulate one exact QA rather than guessing.
