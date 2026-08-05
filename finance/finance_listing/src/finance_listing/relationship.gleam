import finance_listing/effective.{type Interval}
import finance_listing/listing.{type Key}
import finance_provenance/identity.{type EvidenceId}
import gleam/list
import gleam/option.{type Option}
import gleam/string

/// An evidence-backed, effective-dated relationship between two listings.
///
/// Market packages own the vocabulary and endpoint laws for `kind`.
pub opaque type Relationship {
  Relationship(
    kind: String,
    first: Key,
    second: Key,
    effective: Interval,
    evidence_id: Option(EvidenceId),
  )
}

pub type RelationshipError {
  InvalidKind
  SameListing
}

pub fn new(
  kind kind: String,
  first first: Key,
  second second: Key,
  effective effective: Interval,
  evidence_id evidence_id: Option(EvidenceId),
) -> Result(Relationship, RelationshipError) {
  case valid_kind(kind), first == second {
    False, _ -> Error(InvalidKind)
    _, True -> Error(SameListing)
    True, False -> Ok(Relationship(kind, first, second, effective, evidence_id))
  }
}

pub fn kind(value: Relationship) -> String {
  value.kind
}

pub fn first(value: Relationship) -> Key {
  value.first
}

pub fn second(value: Relationship) -> Key {
  value.second
}

pub fn effective(value: Relationship) -> Interval {
  value.effective
}

pub fn evidence_id(value: Relationship) -> Option(EvidenceId) {
  value.evidence_id
}

fn valid_kind(value: String) -> Bool {
  value != ""
  && string.length(value) <= 100
  && {
    value
    |> string.to_graphemes
    |> list.all(fn(character) {
      string.contains("abcdefghijklmnopqrstuvwxyz0123456789_", character)
    })
  }
}
