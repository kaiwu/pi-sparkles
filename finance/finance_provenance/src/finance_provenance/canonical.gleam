import finance_core/currency
import finance_core/decimal
import finance_core/source
import finance_core/time
import finance_provenance/assumption.{type Assumption, type Value}
import finance_provenance/evidence.{
  type Availability, type Evidence, type Licence, type Redistribution,
}
import finance_provenance/identity.{type EvidenceId}
import finance_provenance/manifest.{type Manifest}
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/string

pub fn manifest_json(manifest: Manifest) -> Json {
  json.object([
    #("schema_version", json.int(1)),
    #(
      "assumptions",
      manifest
        |> manifest.assumptions
        |> list.sort(by: compare_assumptions)
        |> json.array(assumption_json),
    ),
    #(
      "evidence",
      manifest
        |> manifest.evidence
        |> list.sort(by: compare_evidence)
        |> json.array(evidence_json),
    ),
    #(
      "roots",
      manifest
        |> manifest.roots
        |> list.sort(by: compare_evidence_ids)
        |> json.array(fn(id) { id |> identity.evidence_id_value |> json.string }),
    ),
  ])
}

pub fn encode_manifest(manifest: Manifest) -> String {
  manifest |> manifest_json |> json.to_string
}

fn assumption_json(assumption: Assumption) -> Json {
  json.object([
    #("id", assumption.id |> assumption.id_value |> json.string),
    #("name", json.string(assumption.name)),
    #("origin", assumption.origin |> origin_name |> json.string),
    #("value", value_json(assumption.value)),
    #("explanation", json.string(assumption.explanation)),
  ])
}

fn value_json(value: Value) -> Json {
  case value {
    assumption.TextValue(value) -> typed_value("text", json.string(value))
    assumption.DecimalValue(value) ->
      typed_value("decimal", value |> decimal.to_string |> json.string)
    assumption.MoneyValue(value) ->
      json.object([
        #("kind", json.string("money")),
        #("amount", value.amount |> decimal.to_string |> json.string),
        #("currency", value.currency |> currency.code |> json.string),
      ])
    assumption.BooleanValue(value) -> typed_value("boolean", json.bool(value))
  }
}

fn evidence_json(evidence: Evidence) -> Json {
  json.object([
    #("id", evidence.id |> identity.evidence_id_value |> json.string),
    #(
      "source_fingerprint",
      evidence.source_fingerprint
        |> identity.source_fingerprint_value
        |> json.string,
    ),
    #("source", source_json(evidence.source)),
    #("licence", licence_json(evidence.licence)),
    #(
      "as_of_unix_ms",
      evidence.as_of |> time.unix_milliseconds |> int.to_string |> json.string,
    ),
    #(
      "retrieved_at_unix_ms",
      evidence.retrieved_at
        |> time.unix_milliseconds
        |> int.to_string
        |> json.string,
    ),
    #("media_type", json.string(evidence.media_type)),
    #("byte_length", evidence.byte_length |> int.to_string |> json.string),
    #(
      "content_hash",
      evidence.content_hash |> identity.sha256_value |> json.string,
    ),
    #(
      "parents",
      evidence.parents
        |> list.sort(by: compare_evidence_ids)
        |> json.array(fn(id) { id |> identity.evidence_id_value |> json.string }),
    ),
    #(
      "assumptions",
      evidence.assumptions
        |> list.sort(by: fn(left, right) {
          string.compare(assumption.id_value(left), assumption.id_value(right))
        })
        |> json.array(fn(id) { id |> assumption.id_value |> json.string }),
    ),
    #("availability", availability_json(evidence.availability)),
  ])
}

fn source_json(value: source.SourceRef) -> Json {
  json.object([
    #("provider", value |> source.provider |> json.string),
    #("reference", value |> source.reference |> json.string),
    #("kind", value |> source.kind |> source_kind_name |> json.string),
  ])
}

fn licence_json(licence: Licence) -> Json {
  json.object([
    #("label", json.string(licence.label)),
    #(
      "redistribution",
      licence.redistribution |> redistribution_name |> json.string,
    ),
    #("notes", optional_string(licence.notes)),
  ])
}

fn availability_json(availability: Availability) -> Json {
  case availability {
    evidence.Available -> json.object([#("state", json.string("available"))])
    evidence.Unavailable(reason) -> state_with("unavailable", "reason", reason)
    evidence.Expired -> json.object([#("state", json.string("expired"))])
    evidence.Superseded(by) ->
      state_with("superseded", "by", identity.evidence_id_value(by))
    evidence.VerificationFailed(reason) ->
      state_with("verification_failed", "reason", reason)
  }
}

fn typed_value(kind: String, value: Json) -> Json {
  json.object([#("kind", json.string(kind)), #("value", value)])
}

fn state_with(state: String, key: String, value: String) -> Json {
  json.object([#("state", json.string(state)), #(key, json.string(value))])
}

fn optional_string(value: Option(String)) -> Json {
  case value {
    Some(value) -> json.string(value)
    None -> json.null()
  }
}

fn compare_assumptions(left: Assumption, right: Assumption) -> order.Order {
  string.compare(assumption.id_value(left.id), assumption.id_value(right.id))
}

fn compare_evidence(left: Evidence, right: Evidence) -> order.Order {
  string.compare(
    identity.evidence_id_value(left.id),
    identity.evidence_id_value(right.id),
  )
}

fn compare_evidence_ids(left: EvidenceId, right: EvidenceId) -> order.Order {
  string.compare(
    identity.evidence_id_value(left),
    identity.evidence_id_value(right),
  )
}

fn origin_name(origin: assumption.Origin) -> String {
  case origin {
    assumption.User -> "user"
    assumption.Provider -> "provider"
    assumption.Method -> "method"
    assumption.Policy -> "policy"
  }
}

fn redistribution_name(redistribution: Redistribution) -> String {
  case redistribution {
    evidence.PublicDomain -> "public_domain"
    evidence.AttributionRequired -> "attribution_required"
    evidence.InternalUseOnly -> "internal_use_only"
    evidence.NoRedistribution -> "no_redistribution"
    evidence.UnknownRedistribution -> "unknown"
  }
}

fn source_kind_name(kind: source.SourceKind) -> String {
  case kind {
    source.Official -> "official"
    source.Exchange -> "exchange"
    source.Regulator -> "regulator"
    source.LicensedVendor -> "licensed_vendor"
    source.UserSupplied -> "user_supplied"
    source.Synthetic -> "synthetic"
    source.Other(kind) -> "other:" <> kind
  }
}
