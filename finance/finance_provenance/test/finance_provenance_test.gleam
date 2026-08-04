import finance_core/source
import finance_core/time
import finance_provenance
import finance_provenance/assumption
import finance_provenance/canonical
import finance_provenance/evidence
import finance_provenance/hash
import finance_provenance/identity
import finance_provenance/manifest
import finance_provenance/redact
import finance_provenance/verify
import gleam/javascript/promise
import gleam/list
import gleam/option.{None}
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn package_is_experimental_test() {
  finance_provenance.status()
  |> should.equal(finance_provenance.Experimental)
}

pub fn hash_identity_is_canonical_test() {
  let assert Ok(hash) = identity.sha256(string.repeat("A", times: 64))

  identity.sha256_value(hash)
  |> should.equal(string.repeat("a", times: 64))
  identity.sha256("short")
  |> should.equal(Error(identity.InvalidSha256))
}

pub fn evidence_rejects_time_travel_test() {
  let assert Ok(as_of) = time.instant(200)
  let assert Ok(retrieved_at) = time.instant(100)

  evidence.new(
    id: id("a"),
    source_fingerprint: fingerprint("b"),
    source: source_ref(),
    licence: test_licence(),
    as_of: as_of,
    retrieved_at: retrieved_at,
    media_type: "application/json",
    byte_length: 10,
    content_hash: hash("c"),
    parents: [],
    assumptions: [],
  )
  |> should.equal(Error(evidence.RetrievedBeforeAsOf))
}

pub fn manifest_requires_topological_evidence_test() {
  let parent_id = id("a")
  let child = fixture("b", [parent_id], 20)

  manifest.new()
  |> manifest.add_evidence(child)
  |> should.equal(
    Error(manifest.MissingParent(identity.evidence_id_value(parent_id))),
  )
}

pub fn manifest_composes_idempotently_test() {
  let parent = fixture("a", [], 10)
  let child = fixture("b", [parent.id], 20)
  let assert Ok(with_parent) = manifest.new() |> manifest.add_evidence(parent)
  let assert Ok(with_child) = with_parent |> manifest.add_evidence(child)
  let assert Ok(idempotent) = with_child |> manifest.add_evidence(child)
  let assert Ok(rooted) = idempotent |> manifest.add_root(child.id)
  let assert Ok(rooted_twice) = rooted |> manifest.add_root(child.id)

  manifest.evidence(rooted_twice)
  |> list.length
  |> should.equal(2)
  manifest.roots(rooted_twice)
  |> should.equal([child.id])
}

pub fn manifest_rejects_same_id_with_different_content_test() {
  let first = fixture("a", [], 10)
  let conflict = fixture("a", [], 11)
  let assert Ok(manifest) = manifest.new() |> manifest.add_evidence(first)

  manifest
  |> manifest.add_evidence(conflict)
  |> should.equal(
    Error(manifest.ConflictingEvidence(identity.evidence_id_value(first.id))),
  )
}

pub fn disjoint_manifests_merge_deterministically_test() {
  let left_item = fixture("a", [], 10)
  let right_item = fixture("b", [], 20)
  let assert Ok(left) = manifest.new() |> manifest.add_evidence(left_item)
  let assert Ok(right) = manifest.new() |> manifest.add_evidence(right_item)
  let assert Ok(merged) = manifest.merge(left, right)

  manifest.evidence(merged)
  |> list.map(fn(item) { identity.evidence_id_value(item.id) })
  |> should.equal([
    identity.evidence_id_value(left_item.id),
    identity.evidence_id_value(right_item.id),
  ])
}

pub fn evidence_requires_declared_assumptions_test() {
  let assumption = test_assumption("discount-rate", "0.08")
  let derived = fixture_with_assumptions("c", [], [assumption.id], 20)

  manifest.new()
  |> manifest.add_evidence(derived)
  |> should.equal(Error(manifest.MissingAssumption("discount-rate")))

  let assert Ok(with_assumption) =
    manifest.new() |> manifest.add_assumption(assumption)
  let assert Ok(with_evidence) =
    with_assumption |> manifest.add_evidence(derived)

  manifest.assumptions(with_evidence)
  |> should.equal([assumption])
}

pub fn structural_redaction_is_recursive_and_idempotent_test() {
  let input =
    redact.Object([
      #("symbol", redact.Text("AAPL")),
      #("Authorization", redact.Text("Bearer secret")),
      #(
        "nested",
        redact.Object([
          #("api_key", redact.Text("secret-key")),
          #("safe", redact.Boolean(True)),
        ]),
      ),
      #(
        "items",
        redact.Array([
          redact.Object([#("private-token", redact.Text("custom-secret"))]),
        ]),
      ),
    ])
  let expected =
    redact.Object([
      #("symbol", redact.Text("AAPL")),
      #("Authorization", redact.Text("[REDACTED]")),
      #(
        "nested",
        redact.Object([
          #("api_key", redact.Text("[REDACTED]")),
          #("safe", redact.Boolean(True)),
        ]),
      ),
      #(
        "items",
        redact.Array([
          redact.Object([#("private-token", redact.Text("[REDACTED]"))]),
        ]),
      ),
    ])
  let redacted = redact.apply(input, ["private-token"])

  redacted
  |> should.equal(expected)
  redact.apply(redacted, ["private-token"])
  |> should.equal(redacted)
}

pub fn sha256_ffi_matches_published_vector_test() {
  let assert Ok(digest) = hash.text("abc")

  identity.sha256_value(digest)
  |> should.equal(
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  )
}

pub fn url_redaction_removes_userinfo_fragments_and_signed_queries_test() {
  let unsafe =
    "https://user:pass@example.test/path?symbol=AAPL&api_key=secret&X-Amz-Signature=signature#token=fragment-secret"
  let safe = redact.url(unsafe, [])

  safe
  |> should.equal(
    "https://[REDACTED]@example.test/path?symbol=AAPL&api_key=%5BREDACTED%5D&X-Amz-Signature=%5BREDACTED%5D",
  )
  redact.url(safe, [])
  |> should.equal(safe)
}

pub fn url_redaction_decodes_keys_and_accepts_provider_policy_test() {
  redact.url(
    "https://example.test/data?api%5Fkey=secret&provider_nonce=abc&safe=yes",
    ["provider_nonce"],
  )
  |> should.equal(
    "https://example.test/data?api%5Fkey=%5BREDACTED%5D&provider_nonce=%5BREDACTED%5D&safe=yes",
  )
}

pub fn canonical_manifest_is_independent_of_insertion_order_test() {
  let first = fixture("a", [], 10)
  let second = fixture("b", [], 20)
  let low_assumption = test_assumption("a-rate", "0.03")
  let high_assumption = test_assumption("z-rate", "0.08")
  let assert Ok(left) =
    manifest.new()
    |> manifest.add_assumption(high_assumption)
    |> result_then(manifest.add_assumption(_, low_assumption))
    |> result_then(manifest.add_evidence(_, second))
    |> result_then(manifest.add_evidence(_, first))
    |> result_then(manifest.add_root(_, second.id))
    |> result_then(manifest.add_root(_, first.id))
  let assert Ok(right) =
    manifest.new()
    |> manifest.add_assumption(low_assumption)
    |> result_then(manifest.add_assumption(_, high_assumption))
    |> result_then(manifest.add_evidence(_, first))
    |> result_then(manifest.add_evidence(_, second))
    |> result_then(manifest.add_root(_, first.id))
    |> result_then(manifest.add_root(_, second.id))

  canonical.encode_manifest(left)
  |> should.equal(canonical.encode_manifest(right))
  hash.manifest(left)
  |> should.equal(hash.manifest(right))
}

pub fn verification_plan_enforces_finite_budgets_test() {
  let item = fixture("a", [], 10)
  let assert Ok(with_evidence) = manifest.new() |> manifest.add_evidence(item)

  verify.plan(with_evidence, maximum_items: 0, maximum_content_bytes: 100)
  |> should.equal(Error(verify.InvalidMaximumItems))
  verify.plan(with_evidence, maximum_items: 1, maximum_content_bytes: 0)
  |> should.equal(Error(verify.InvalidMaximumContentBytes))
  verify.plan(with_evidence, maximum_items: 1, maximum_content_bytes: 100)
  |> should.be_ok
  verify.plan(with_evidence, maximum_items: 1, maximum_content_bytes: 9)
  |> should.equal(Error(verify.EvidenceContentLimitExceeded(item.id, 10, 9)))
}

pub fn pure_content_verification_distinguishes_length_and_hash_test() {
  let content = "synthetic evidence"
  let assert Ok(content_hash) = hash.text(content)
  let target =
    verify.Target(
      id: id("a"),
      source: source_ref(),
      expected_hash: content_hash,
      expected_bytes: string.byte_size(content),
    )

  verify.inspect(target, content)
  |> should.equal(verify.Verified(id("a")))
  verify.inspect(verify.Target(..target, expected_bytes: 1), content)
  |> should.equal(verify.LengthMismatch(id("a"), 1, string.byte_size(content)))
  verify.inspect(verify.Target(..target, expected_hash: hash("f")), content)
  |> should.equal(verify.ContentMismatch(id("a"), hash("f"), content_hash))
}

pub fn asynchronous_verification_uses_injected_fetcher_test() {
  let content = "replayable synthetic evidence"
  let assert Ok(content_hash) = hash.text(content)
  let item = fixture_with_content("a", content_hash, string.byte_size(content))
  let assert Ok(with_evidence) = manifest.new() |> manifest.add_evidence(item)
  let assert Ok(plan) =
    verify.plan(with_evidence, maximum_items: 1, maximum_content_bytes: 1024)

  use report <- promise.await(
    verify.verify(plan, fn(_target, maximum_bytes) {
      maximum_bytes
      |> should.equal(1024)
      promise.resolve(Ok(content))
    }),
  )
  verify.successful(report)
  |> should.be_true
  promise.resolve(Nil)
}

fn fixture(
  identity_character: String,
  parents: List(identity.EvidenceId),
  byte_length: Int,
) -> evidence.Evidence {
  fixture_with_assumptions(identity_character, parents, [], byte_length)
}

fn fixture_with_assumptions(
  identity_character: String,
  parents: List(identity.EvidenceId),
  assumptions: List(assumption.AssumptionId),
  byte_length: Int,
) -> evidence.Evidence {
  let assert Ok(as_of) = time.instant(100)
  let assert Ok(retrieved_at) = time.instant(200)
  let assert Ok(item) =
    evidence.new(
      id: id(identity_character),
      source_fingerprint: fingerprint("f"),
      source: source_ref(),
      licence: test_licence(),
      as_of: as_of,
      retrieved_at: retrieved_at,
      media_type: "application/json",
      byte_length: byte_length,
      content_hash: hash(identity_character),
      parents: parents,
      assumptions: assumptions,
    )
  item
}

fn fixture_with_content(
  identity_character: String,
  content_hash: identity.Sha256,
  byte_length: Int,
) -> evidence.Evidence {
  let assert Ok(as_of) = time.instant(100)
  let assert Ok(retrieved_at) = time.instant(200)
  let assert Ok(item) =
    evidence.new(
      id: id(identity_character),
      source_fingerprint: fingerprint("f"),
      source: source_ref(),
      licence: test_licence(),
      as_of: as_of,
      retrieved_at: retrieved_at,
      media_type: "application/json",
      byte_length: byte_length,
      content_hash: content_hash,
      parents: [],
      assumptions: [],
    )
  item
}

fn test_assumption(id_value: String, value: String) -> assumption.Assumption {
  let assert Ok(id) = assumption.id(id_value)
  let assert Ok(value) =
    assumption.new(
      id: id,
      name: "Discount rate",
      value: assumption.TextValue(value),
      origin: assumption.User,
      explanation: "Explicit test assumption",
    )
  value
}

fn source_ref() -> source.SourceRef {
  let assert Ok(value) =
    source.new(
      provider: "synthetic-provider",
      reference: "fixture/quote",
      kind: source.Synthetic,
    )
  value
}

fn test_licence() -> evidence.Licence {
  evidence.Licence(
    label: "synthetic-test-only",
    redistribution: evidence.PublicDomain,
    notes: None,
  )
}

fn hash(character: String) -> identity.Sha256 {
  let assert Ok(value) = identity.sha256(string.repeat(character, times: 64))
  value
}

fn id(character: String) -> identity.EvidenceId {
  character
  |> hash
  |> identity.evidence_id
}

fn fingerprint(character: String) -> identity.SourceFingerprint {
  character
  |> hash
  |> identity.source_fingerprint
}

fn result_then(
  result: Result(value, error),
  next: fn(value) -> Result(next, error),
) -> Result(next, error) {
  case result {
    Ok(value) -> next(value)
    Error(error) -> Error(error)
  }
}
