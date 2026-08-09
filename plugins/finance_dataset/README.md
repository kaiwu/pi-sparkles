# pi_sparkles_finance_dataset

Status: **Experimental — Session 17 rank 5 complete 2026-08-08** · version: `0.1.0` · target:
JavaScript/Bun

`finance_dataset` is a thin, stateless, read-only Pi shell over the canonical
dataset-manifest types in `finance_replay` and the four implemented daily gap
states in `finance_ohlcv`. It lets the LLM inspect one exact bitemporal dataset
manifest, drill one exact listing/date, or list every supplied correction
vintage without fetching, selecting, repairing, or judging the data.

The professional scope and stop point come from
[Session 17](../../../trading-course/sessions/17_product_plugin_portfolio_steering_20260807.md).
[Session 11](../../../trading-course/sessions/11_cg_market_data_20260807.md)
controls completed-daily observations and omission facts, while
[Session 16](../../../trading-course/sessions/16_cg_quant_shared_replay_information_contract_20260807.md)
controls dataset manifests, bitemporal availability, corrections, and stable
reproduction handles. The implementation composes
[`finance_ohlcv`](../../finance/finance_ohlcv/README.md) and
[`finance_replay`](../../finance/finance_replay/README.md); it does not define a
second observation, gap, vintage, or manifest law.

## Decision boundary

The LLM chooses every manifest, supplement, listing/date drill, vintage filter,
page, interpretation, and next operation. The plugin performs only exact
decoding, canonical hash verification, mechanical counting, equality filters,
stable pagination, and deterministic rendering.

It never chooses or emits:

- a provider, source, dataset, manifest, listing, date, vintage, correction,
  cutoff, gap policy, receipt root, transformation, or fallback;
- a preferred, latest, original, corrected, visible, usable, clean, valid,
  trustworthy, sufficient, point-in-time-safe, representative, or complete
  research dataset;
- an imputed, forward-filled, repaired, adjusted, merged, deduplicated, or
  substituted observation;
- source truth, provider authentication, licence permission, data quality,
  bias, leakage, survivorship, research-result, deployment, recommendation, or
  next-action conclusions; or
- hidden retrieval, registry lookup, filesystem/database read, cache access,
  persistence, import, export, clock, network, entitlement, or mutation effects.

Every result includes `decisionOwner: "llm"` and
`pluginDecisionFields: []`. A matching digest proves only that the supplied
canonical manifest bytes decode to their content-bound representation. A
matching inspection-projection handle proves only that the same manifest hash,
caller-supplied omission projection, and caller-supplied receipt-root order
were inspected.

## Why the manifest and supplements are explicit

Session 17 abbreviates the first operation as
`inspect_dataset(manifest_hash)`. Resolving a hash without also supplying its
bytes would require a registry or storage effect. That effect is not authorized
for this first slice. Each tool therefore receives one immutable `dataset`
value containing:

- `manifestJson`: the exact canonical envelope produced by
  `finance_replay/manifest.encode_dataset`;
- `manifestHash`: the expected 64-character SHA-256 content handle, which must
  match the envelope and its recomputed core digest;
- `omissions`: an ordered caller-supplied projection using only the implemented
  `finance_ohlcv.GapState` variants (`market_closure`, `suspension`,
  `provider_omission`, or `unavailable_history`); and
- `receiptRoots`: ordered caller-supplied SHA-256 roots associated with this
  inspection context.

The supplement is explicit because a manifest with no observation row cannot
by itself prove why that row is absent. The plugin never infers an omission from
an absent row. Supplied omissions remain visibly caller-supplied OHLCV gap
facts; their evidence reference may be absent. Unknown or newer gap families
remain expressible in the manifest's exact observation-state facts and
limitations, but this shell does not widen the reviewed four-state OHLCV enum.

All three tools replay the same immutable value after interruption. There is no
ambient active dataset and no silent reuse of a prior call.

## Tool surface

### `inspect_dataset`

Inputs:

- the exact dataset value described above.

The result exposes the manifest ID, version, provider, source/import
provenance, exact `cn`/`hk`/`us` track, coverage interval, declared limitations,
verified manifest handle, and calculated inspection-projection handle. Compact
counts include observations, distinct listing IDs, distinct observation dates,
supplied omissions, supplied receipt roots, correction-lineage links, and every
`Known`, `Unknown`, `NotObtained`, `NotApplicable`, `Conflicting`, or
`DecodeFailure` state for the observation-state, availability-time,
knowledge-time, and correction-vintage slots.

The omission summary counts the four exact supplied OHLCV gap variants. It does
not compare coverage to an unsupplied calendar, invent expected sessions, or
turn a non-known fact into a quality verdict.

### `drill_observation`

Inputs:

- the exact dataset value;
- `listingId` and canonical `observationDate` (`YYYY-MM-DD`); and
- `offset` and `limit` for an explicit page of matching entries.

The tool matches exact listing ID and exact session date only. It returns every
matching manifest observation handle and supplied omission in manifest-first,
caller-supplied order. Observation entries retain identity, track, MIC, all
observation/publication/availability/knowledge/retrieval/cutoff times,
correction vintage and lineage, session/calendar/status facts, units, currency,
scale, timezone, adjustment basis, quantity semantics, entitlement, licence,
state, content hash, corporate-action references, and transformation
references.

An omission-only match is a successful exact unavailable projection. If neither
an observation nor an omission names the selector, the call fails explicitly;
there is no nearest-date, current-symbol, alternate-listing, provider, track, or
vintage fallback. Pagination never changes the retained order and reports the
exact omitted count and continuation offset.

### `list_vintages`

Inputs:

- the exact dataset value;
- optional exact `listingId` and optional canonical `observationDate` filters;
  and
- `offset` and `limit` for an explicit page.

The tool lists matching observation handles in canonical manifest order. A row
contains the observation ID/content handle, identity/date, publication,
availability, knowledge, retrieval and cutoff times, exact correction-vintage
fact, lineage, state, and linked calendar/status/corporate-action/transformation
references. It does not sort by time, collapse duplicates, infer correction
precedence, select the latest visible row, apply a knowledge cutoff, or call an
unknown vintage `original`.

## Bounds and validation

- `manifestJson` must be non-empty and no larger than 10,000,000 UTF-8 bytes.
- The core manifest retains its 10,000-entry maximum and rejects malformed
  fields, duplicate observation IDs, track substitution, invalid intervals, and
  any inner or outer hash mismatch.
- `manifestHash` and every receipt root must be exact SHA-256 hex.
- At most 10,000 omission facts and 10,000 receipt roots may be supplied.
- Every omission date must be inside the exact manifest coverage interval.
- Listing IDs and evidence references are bounded, trimmed strings. Manifest
  source/import references and omission evidence references receive mandatory
  URL userinfo, fragment, and secret-query redaction in the output projection;
  the raw supplied values remain bound only by the verified/calculated hashes.
  Other free-text manifest facts must not be used to carry secrets.
- Pages use `offset` from zero through the matching count and `limit` from one
  through 200. No result is silently truncated.

The shell computes `inspectionProjectionHandle` over canonical JSON containing
the verified manifest hash plus the ordered omission and receipt-root
supplement. It is a deterministic content handle, not provider authentication,
source authority, a signature, or a quality certificate.

## Efficient professional routine

1. The LLM obtains or constructs an exact canonical dataset manifest and any
   separately evidenced daily gap projection.
2. It calls `inspect_dataset` for coverage, compact state counts, limitations,
   omissions, and stable handles.
3. It drills a listing/date only when the compact facts require exact metadata.
4. It calls `list_vintages` when it needs to compare the supplied original,
   corrected, unknown, or conflicting vintage facts.
5. The LLM alone chooses a cutoff or vintage, requests other evidence or a
   replay, interprets the facts, and records any research conclusion elsewhere.

This manifest → observation → vintage routine is resumable with the two stable
handles and the explicit page offsets. Raw OHLCV values are not stored in the
Session 16 observation handle, so this shell exposes their exact content hash
and metadata rather than pretending to return row values. A provider/data tool
or content-addressed store must supply raw bytes in a later, separately reviewed
operation.

## Result contract

Every result is schema version 1 and returns:

- the verified dataset manifest handle and calculated inspection-projection
  handle;
- exact manifest identity, track, coverage, and declared limitations;
- the requested compact or drill projection with visible pagination;
- neutral `availableOperations` naming only these three read operations;
- `decisionOwner: "llm"` and an empty `pluginDecisionFields`; and
- limitations separating content integrity and exact equality facts from
  origin, correctness, quality, sufficiency, point-in-time safety, selection,
  licence permission, or professional judgment.

No output contains an aggregate verdict. Terms such as `known`, `conflicting`,
`provider_omission`, and `correctionVintage` are exact supplied fact states,
not workflow decisions.

## Architecture and effects

```text
untrusted canonical manifest + exact hash + supplied gaps/roots + query
                                  │
                                  ▼
                         typed boundary decoder
                                  │
                                  ▼
                 pure finance_dataset validation/query/rendering
                         │                         │
                         ▼                         ▼
        finance_replay manifest/fact/wire   finance_ohlcv GapState
                                  │
                                  ▼
                         Pi text + structured result
```

- `pi_sparkles_finance_dataset.gleam` registers the three Pi tools and owns no
  domain policy.
- `pi_sparkles_finance_dataset/decode.gleam` decodes untrusted values into
  immutable boundary types.
- `pi_sparkles_finance_dataset/domain.gleam` validates the exact core manifest,
  constructs the supplied OHLCV gaps, calculates counts/handles, applies exact
  filters, and renders deterministic projections.
- A narrow accessor addition to `finance_replay/manifest` exposes opaque
  manifest metadata without duplicating its canonical wire decoder.
- No module performs network, filesystem, database, environment, clock,
  randomness, cache, storage, import, export, entitlement, or mutation effects.

## Lifecycle, verification, and stop point

The package is **Experimental**. Eight focused tests cover canonical hash
validation, track preservation, compact state/omission counts, exact observation
and omission-only drill results, vintage preservation and pagination,
unavailable/conflicting fact rendering, out-of-coverage gaps, malformed
dates/hashes/manifests, no selector fallback, stable projection handles, URL
secret redaction, and absence of plugin decision fields or verdict language.

Two bundled boundary scenarios cover the compact manifest → observation →
vintage interaction and exact failure/redaction behavior. Artifact export,
installed-Pi smoke loading, architecture checks, and the full `bun run test`
repository regression passed on 2026-08-08. The full run included 124
binding/artifact tests and the 177-assertion swing acceptance lane. No tutor-LLM
run was required because this thin shell introduces no new professional
workflow, three-plugin handoff, provider, persistence, or effectful operation.

The first slice stops after the three stateless read-only tools over one
caller-supplied completed-daily manifest. It does not add a dataset registry,
raw-row content store, import/export adapters, calendar-driven gap derivation,
vintage/cutoff selection, adjustment, imputation, repair, transformation,
comparison, profiling, query engine, screener, replay submission, source
adapter, chart, or quality tool. Those require a concrete Session 17 depth
trigger or their separately ranked breadth item.
