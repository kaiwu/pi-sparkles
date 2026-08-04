import finance_core/source
import finance_core/time
import finance_provenance
import finance_provenance/evidence
import finance_provenance/identity
import finance_provenance/manifest
import gleam/list
import gleam/option.{None}
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn package_is_implementing_test() {
  finance_provenance.status()
  |> should.equal(finance_provenance.Implementing)
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

fn fixture(
  identity_character: String,
  parents: List(identity.EvidenceId),
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
    )
  item
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
