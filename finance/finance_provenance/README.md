# finance_provenance

Status: **Experimental** · version: `0.1.0` · target: JavaScript/Bun

`finance_provenance` records where financial facts came from, what content was
observed, and which assumptions produced a derived result. It turns evidence
into portable, redacted, verifiable manifests. It is a library rather than a Pi
extension; a future source-ledger plugin will own session persistence and user
commands.

The implemented slice includes validated SHA-256 identities, distinct source
fingerprints and evidence IDs, typed assumptions, recursive/idempotent
structural redaction, licence/availability-labelled evidence, and immutable
manifests that require assumptions and parents before derived evidence, reject
conflicting IDs, add roots idempotently, and merge deterministic evidence
sequences. Canonical manifest JSON sorts identity-bearing collections and hashes
through a known-vector-tested SHA-256 FFI. URL redaction removes fragments,
userinfo, signed parameters, encoded secret keys, and provider-configured keys.
Bounded asynchronous verification is implemented through an injected fetcher.
Importing untrusted canonical manifests and external-dependency declarations
remain post-foundation interoperability work; constructed manifests are fully
validated and canonically encoded.

## User stories

- A quote, filing fact, or macro observation can be traced to a safe provider
  reference, an as-of time, a retrieval time, and the exact response content.
- A derived metric records its input evidence and explicit assumptions.
- A report can export a deterministic manifest without leaking credentials,
  signed URLs, cookies, or private filesystem paths.
- A replay tool can verify hashes and report unavailable evidence without
  pretending that a source is still reachable.

## Non-goals

- No network client, cache, crawler, credential manager, citation UI, or Pi
  session storage.
- No claim that a content hash grants redistribution rights or proves the
  provider was truthful.
- No embedding of full licensed response bodies by default.
- No signing/notarization protocol in 0.1; hashes provide integrity, not author
  identity.

## Dependency boundary

The package depends on `finance_core` for `Instant`, `SourceRef`, and canonical
encoding primitives. Core never imports provenance. An `Observation(a)` keeps a
minimal safe source reference and optional evidence ID; this package stores the
full evidence record keyed by that ID.

## Functional design

Evidence construction, canonicalization, redaction, fingerprinting, graph
validation, manifest merging, and derivation are pure transformations. A
manifest is an immutable value; adding evidence returns a new manifest or a
typed conflict, so independent evidence-producing packages can compose without
sharing a mutable ledger.

Verification is split into a pure plan and reducer around an explicit fetch
capability. Planning produces the safe references and expected hashes to fetch;
the shell performs bounded asynchronous reads; the reducer turns typed outcomes
into a verification report. Tests can fold success, mismatch, unavailable,
duplicate, and out-of-order outcomes without networking. Hashing FFI, if
required, is a mechanical interpreter for bytes and contains no evidence
policy.

## Module surface

| Module | Responsibility |
| --- | --- |
| `finance_provenance/identity` | distinct SHA-256, source-fingerprint, and evidence-ID values |
| `finance_provenance/hash` | reviewed SHA-256 interpreter and canonical manifest hashing |
| `finance_provenance/canonical` | deterministic schema-v1 manifest encoding |
| `finance_provenance/evidence` | content identity, retrieval metadata, parent inputs, and verification state |
| `finance_provenance/assumption` | typed user/provider/model assumptions and units |
| `finance_provenance/manifest` | deterministic evidence graph, roots, metadata, composition, and validation |
| `finance_provenance/redact` | structural secret and private-reference redaction |
| `finance_provenance/verify` | hash verification through a caller-supplied asynchronous fetch function |

## Identity model

Two identifiers serve different purposes:

- A `SourceFingerprint` hashes a normalized request identity: provider,
  endpoint/reference, non-secret parameters, and relevant entitlement variant.
  It answers “was this the same logical request?”
- An `EvidenceId` is content-addressed from the source fingerprint, as-of
  identity, normalized content hash, decoder/schema version, and material
  provider metadata. It answers “was this the same observed fact?”

Repeated retrieval of unchanged normalized content can share an evidence ID
while recording another retrieval attempt. Changed content, restatements, or a
different as-of identity produces a new evidence ID. Retrieval time alone does
not rewrite the fact identity.

## Evidence record

The first `Evidence` model includes:

- evidence ID and source fingerprint;
- core `SourceRef`, source kind, and provider name;
- `Licence` with provider-supplied identifier, redistribution mode, and notes;
- `as_of` and one or more `retrieved_at` instants;
- media type, byte length, SHA-256 content hash, and optional safe cache key;
- decoder name/version and normalized request metadata;
- zero or more parent evidence IDs and assumption IDs;
- explicit states for available, unavailable, expired, superseded, and
  verification-failed.

Raw content is not embedded by default. A caller may attach a relative artifact
reference only when its storage and licence policy permit it. URLs are
normalized structurally; userinfo, fragments, secret query fields, signatures,
and configured sensitive headers are removed before construction.

## Assumptions and derivations

An `Assumption` has a stable ID, name, typed value, unit/currency when relevant,
origin (`User`, `Provider`, `Method`, or `Policy`), and explanation. A derived
evidence node lists every material parent and assumption. Missing inputs are
recorded as missing rather than omitted from the graph.

Manifest roots identify final outputs. The graph must be acyclic; duplicate IDs
must have byte-identical canonical encodings. Unknown parent IDs are validation
errors unless the manifest explicitly declares an external dependency.

## Async and FFI contract

Normalization, redaction, canonical encoding, graph validation, and hashing may
be synchronous. Verification accepts a caller-provided fetch function and
returns `Promise(Result(Verification, VerifyError))`. It must never perform
hidden network I/O. Any Web Crypto or Node/Bun hashing FFI is tested against
published SHA-256 vectors and must produce identical lowercase hexadecimal
output.

## Redaction and security

- Redaction occurs before fingerprints, errors, logs, manifests, and test
  cassettes are produced.
- Header matching is case-insensitive. Defaults include authorization, cookies,
  API-key variants, proxy credentials, and common signed-query parameters.
- Callers can add provider-specific secret field names but cannot disable the
  mandatory set accidentally.
- Filesystem references become caller-supplied logical artifact IDs; manifests
  never expose home directories or temporary paths.
- Error values contain stage, safe source fingerprint, and typed cause. They do
  not retain arbitrary bodies or thrown JavaScript objects.

Redaction is defense in depth. Constructors should reject secret-bearing source
references rather than relying on an export-time scrub.

## Test design

- Canonical JSON and SHA-256 golden vectors across field orderings.
- URL, header, query, nested-object, signed-URL, filesystem, and Unicode
  redaction fixtures.
- Identity tests proving unchanged content stability and changed/restated
  content separation.
- Manifest graph tests for cycles, missing parents, duplicates, roots,
  unavailable evidence, and deterministic order.
- Algebraic tests for canonicalization idempotence and associative manifest
  merging when evidence sets do not conflict.
- Verification tests for match, mismatch, network failure, cancellation,
  content limits, and redirects using an injected fake fetcher.
- Licence fixtures proving licence labels survive export without implying a
  redistribution permission that was not supplied.

No test contacts a live provider. Public fixtures are minimal, synthetic, and
must not reproduce a licensed response corpus.

## Distribution and compatibility

The Hex package contains Gleam and reviewed hashing FFI source only. It stores
no evidence, credentials, cassettes, or generated manifests. The canonical
manifest format includes a schema version. Decoders may preserve unknown
metadata, but a verifier must reject unknown hash algorithms and canonicalization
versions rather than guess.

## Acceptance criteria

- Every exported source reference is secret-free under mandatory redaction
  tests.
- Fingerprint and evidence identity semantics are distinct and deterministic.
- A multi-source derived result exports as a valid acyclic manifest with all
  assumptions and missing inputs represented.
- Verification is explicit, asynchronous, bounded by caller limits, and fully
  testable without network access.
- Core/provenance dependency direction remains one-way.
- Formatting, warnings-as-errors build, unit tests, and Hex tarball audit pass.

## Post-foundation decisions

- Whether retrieval attempts are embedded in an evidence record or stored as a
  separate append-only record.
- Exact licence vocabulary and whether SPDX identifiers cover enough provider
  agreements.
- Canonical JSON scheme and Unicode normalization form.
- Whether signing manifests belongs in a separate package after 0.1.
