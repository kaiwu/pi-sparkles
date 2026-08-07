# pi_sparkles_finance_sources

Status: **Experimental — Session 17 rank 2 complete 2026-08-07** · version: `0.1.0` · target:
JavaScript/Bun

`finance_sources` is a thin, stateless, read-only Pi shell over
`finance_provenance`. It lets the LLM list source receipts, inspect one exact
receipt, or export a canonical reproducibility manifest from an immutable
catalogue explicitly supplied with the query.

The controlling professional scope is
[Session 17](../../../trading-course/sessions/17_product_plugin_portfolio_steering_20260807.md).
The evidence identity, graph, canonicalization, licence, integrity, and
redaction semantics come from
[`finance_provenance`](../../finance/finance_provenance/README.md).

## Decision boundary

The LLM chooses every query, catalogue, receipt handle, page, export budget,
interpretation, and next action. The plugin only decodes the supplied catalogue,
constructs the exact provenance graph, and returns requested source facts,
assumptions, relationships, limitations, canonical bytes, hashes, unknowns, or
exact operation failures.

It never chooses or emits:

- a provider, source, receipt, root, parent, assumption, licence, availability,
  query, page, verification operation, or fallback;
- source correctness, truth, quality, trust, authority, sufficiency,
  preference, comparability, freshness adequacy, entitlement adequacy,
  professional readiness, recommendation, or next-action conclusions; or
- hidden collection, ambient session history, network retrieval, verification,
  cache lookup, persistence, signing, authentication, or redistribution rights.

Every result includes `decisionOwner: "llm"` and
`pluginDecisionFields: []`. A valid graph and matching content hash prove only
that the requested representation is internally reproducible; they do not prove
that a provider or observation is correct.

## Professional routine

1. The LLM gathers exact receipt metadata already returned by provider,
   calculation, dataset, journal, or workflow tools and supplies a bounded
   catalogue. The plugin does not observe other tools automatically.
2. The LLM calls `list_sources` to obtain a compact, explicitly paged inventory
   of the supplied evidence nodes and the catalogue's canonical manifest handle.
3. When one receipt matters, the LLM calls `inspect_source` with that exact
   receipt hash and the same catalogue. The plugin returns its source,
   timestamps, content identity, licence label, availability state, parents,
   referenced assumptions, and redaction projection.
4. When reproducibility material is needed, the LLM calls `export_manifest`
   with the same catalogue and an explicit byte budget. The plugin returns the
   exact schema-v1 canonical manifest JSON and SHA-256 or reports that the
   requested export exceeds the budget.
5. The LLM alone compares sources, decides whether more information is needed,
   and chooses the next workflow operation.

Equal catalogues produce equal canonical manifest bytes and handles regardless
of which inspection tool is used. The caller repeats the immutable catalogue
after interruption; the first slice deliberately has no hidden mutable ledger.

## Why the catalogue is explicit

Session 17 describes conceptual operations as `list_sources()`,
`inspect_source(receipt_hash)`, and `export_manifest()`. A zero-argument list
would require hidden capture or storage that the reviewed first slice does not
authorize. The Pi tools therefore add one explicit `catalogue` argument to all
three operations. This is an engineering representation of the same read-only
professional task, not a change in workflow policy.

The catalogue is constructed from structured values rather than accepting an
opaque manifest JSON string. `finance_provenance` does not yet expose an
untrusted canonical-manifest importer, and this shell must not invent one or
pretend that arbitrary JSON has been verified.

## Tool surface

### `list_sources`

Inputs:

- the exact catalogue;
- `offset`, from zero through the catalogue size; and
- `limit`, from one through 200.

The tool preserves the catalogue's caller-supplied topological evidence order
and returns the requested page. Each compact row includes the receipt hash,
source fingerprint, provider, projected safe reference, source kind, as-of and
retrieval times, media type, byte length, content hash, licence label and
redistribution state, availability state, parent/assumption counts, and whether
the source reference required redaction. Pagination and omitted counts are
visible; no source is ranked, preferred, grouped as good/bad, or silently
discarded.

### `inspect_source`

Inputs:

- the exact catalogue; and
- `receiptHash`, an exact evidence identifier present in that catalogue.

The tool returns the complete safe evidence projection plus ordered parent
receipt hashes and the complete definitions of assumptions named by the
receipt. Missing handles fail explicitly and expose no nearest-match or source
fallback.

### `export_manifest`

Inputs:

- the exact catalogue; and
- `maximumManifestBytes`, from one through 5,000,000.

The tool uses `finance_provenance/canonical.encode_manifest` and
`finance_provenance/hash.manifest`. It returns the exact canonical JSON only
when its UTF-8 byte length is within the explicit budget; excess fails instead
of truncating. The export contains the catalogue's explicit roots and no
plugin-selected root. It is unsigned and carries no origin-authentication or
redistribution claim.

## Immutable catalogue contract

Each tool requires:

- `instructionRef`: SHA-256 of the caller/LLM instruction selecting this
  catalogue and operation;
- `additionalSensitiveQueryKeys`: explicit provider-specific query keys to
  redact in addition to the mandatory provenance list;
- zero to 500 typed assumptions;
- one to 500 evidence entries in parent-before-child order; and
- zero to 500 explicit root receipt hashes.

Each assumption preserves:

- stable textual ID, name, origin (`user`, `provider`, `method`, or `policy`),
  and explanation; and
- one explicit value variant: text, exact decimal, money with exact decimal and
  currency, or boolean.

Each evidence entry preserves:

- receipt/evidence ID, source fingerprint, provider, reference, and source kind;
- licence label, redistribution state, and optional notes;
- exact as-of and retrieval instants;
- media type, byte length, content SHA-256;
- parent receipt hashes and assumption IDs; and
- availability: available, unavailable with reason, expired, superseded by an
  exact receipt hash, or verification-failed with reason.

The catalogue constructor reuses `finance_provenance` smart constructors and
manifest graph laws. Parents and assumptions must already exist before a child;
roots must name supplied evidence; duplicates must be byte-identical. Failures
are graph facts, not source-quality judgments.

## Safe reference projection

Source references pass through mandatory structural redaction before entering
the manifest:

- URL fragments and userinfo are removed;
- mandatory and caller-supplied sensitive query values are redacted;
- if the core still rejects a reference because the sensitive key itself
  remains visible, the reference becomes a digest-bound logical
  `redacted-reference:sha256:<hash>`; and
- the result reports whether redaction changed the reference.

The original unsafe reference is never returned, logged, included in an error,
or stored by this plugin. Catalogue fields are metadata only and must never be
used to carry response bodies, credentials, cookies, signed URLs, private file
paths, or arbitrary secret text.

## Result contract

Every result is versioned and returns:

- the instruction reference;
- assumption, evidence, and root counts;
- the canonical manifest SHA-256 handle and canonical byte count;
- the exact requested projection;
- neutral available operations;
- `decisionOwner: "llm"` and an empty `pluginDecisionFields` list; and
- limitations distinguishing graph validity and content binding from truth,
  authority, source quality, authentication, licence permission, or
  professional sufficiency.

The compact list and inspection projections never include raw response bodies.
`export_manifest` includes only the canonical metadata manifest. Unknown
licence or redistribution state remains explicitly unknown.

## Architecture

```text
untrusted Pi catalogue + query
          │
          ▼
typed boundary decoder
          │
          ▼
pure finance_sources catalogue preparation/query/rendering
          │
          ▼
finance_provenance constructors / manifest / canonical / hash / redact
          │
          ▼
Pi text + structured result
```

- `pi_sparkles_finance_sources.gleam` is the thin Pi/Promise registration
  shell.
- `pi_sparkles_finance_sources/decode.gleam` decodes untrusted catalogue and
  operation values into immutable boundary types.
- `pi_sparkles_finance_sources/domain.gleam` prepares a safe typed catalogue,
  invokes the provenance core, and returns deterministic projections.
- No module performs network, filesystem, environment, clock, randomness,
  storage, entitlement, verification, or mutable-cache effects.
- The shell accepts evidence from any explicitly labelled track or global
  workflow without inventing a fourth market track or silently merging market
  observations. Track semantics remain inside the supplied receipt metadata.

## Lifecycle and stop point

The package is **Experimental**. Its typed API and replay shape may still
change, but the implemented first slice has passed its focused and repository
verification gates.

The first slice stops after the three stateless read-only tools, explicit
catalogue replay, compact paged listing, one-receipt drill-down, and bounded
canonical export. It does not add hidden ingestion, event subscription,
persistence, cache management, source verification/fetching, signing,
notarization, comparison, source choice, quality scoring, citation rendering,
or provider adapters.

Later depth requires a concrete Session 17 trigger, such as two consumers
needing the same persistent receipt registry or the LLM being unable to compare
runs because a required definition is not queryable. General wishes for more
metadata, automatic trust judgments, or repeated correctness testing are not
depth triggers.

## Verification

Eight focused pure tests cover:

- typed catalogue construction with assumptions, parent-before-child evidence,
  roots, availability states, licences, and unknown redistribution;
- deterministic canonical bytes and manifest hashes;
- compact list order, explicit pagination, and visible omissions;
- exact receipt inspection with linked assumptions and no nearest fallback;
- redaction of userinfo, fragments, mandatory query secrets, and additional
  provider-specific keys without secret-bearing errors;
- explicit export byte-budget failure without truncation;
- graph failures for missing parents/assumptions, unknown roots, and conflicting
  duplicate IDs; and
- absence of correctness, quality, trust, preference, rank, recommendation,
  verification, and plugin-next-action fields.

Repository integration includes two bundled scenarios covering list→inspect→
export, safe-reference redaction and exact failures, plus artifact registration,
installed-Pi smoke loading, architecture/redaction checks, and the compact
professional interaction fixture. The final gate is `bun run test`.

Session 17 does not require a real tutor-LLM run because this thin shell adds no
provider, persistent effect, mutation, or three-plugin handoff.
