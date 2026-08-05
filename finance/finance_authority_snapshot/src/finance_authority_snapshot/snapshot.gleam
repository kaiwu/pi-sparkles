import finance_core/source.{type SourceRef}
import finance_core/time.{type Instant}
import finance_http/response.{type Response}
import finance_provenance/evidence.{type Evidence}
import finance_provenance/hash
import finance_provenance/identity
import finance_track.{type Track}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub opaque type Policy {
  Policy(
    track: Track,
    authority_id: String,
    source: SourceRef,
    allowed_media_types: List(String),
    maximum_bytes: Int,
  )
}

pub opaque type Snapshot {
  Snapshot(
    track: Track,
    authority_id: String,
    source: SourceRef,
    body: String,
    evidence: Evidence,
  )
}

pub type PolicyError {
  InvalidAuthorityId
  WrongTrackAuthorityId(expected_prefix: String)
  NonAuthoritySource
  EmptyMediaAllowlist
  InvalidMediaType(value: String)
  DuplicateMediaType(value: String)
  InvalidMaximumBytes
}

pub type CaptureError {
  UnexpectedStatus(received: Int)
  MissingContentType
  UnsupportedMediaType(received: String)
  EmptyBody
  ByteLengthMismatch(declared: Int, actual: Int)
  ResponseTooLarge(maximum: Int, received: Int)
  InvalidHash(identity.IdentityError)
  InvalidEvidence(evidence.EvidenceError)
}

pub fn local_analysis_policy(
  track track_value: Track,
  authority_id authority_id_value: String,
  source source_value: SourceRef,
  allowed_media_types allowed_media_values: List(String),
  maximum_bytes maximum_bytes_value: Int,
) -> Result(Policy, PolicyError) {
  let prefix = finance_track.name(track_value) <> "_"
  case
    valid_id(authority_id_value),
    string.starts_with(authority_id_value, prefix),
    authority_source(source_value),
    allowed_media_values,
    first_invalid_media(allowed_media_values),
    first_duplicate(allowed_media_values),
    maximum_bytes_value > 0
  {
    False, _, _, _, _, _, _ -> Error(InvalidAuthorityId)
    _, False, _, _, _, _, _ -> Error(WrongTrackAuthorityId(prefix))
    _, _, False, _, _, _, _ -> Error(NonAuthoritySource)
    _, _, _, [], _, _, _ -> Error(EmptyMediaAllowlist)
    _, _, _, _, Some(value), _, _ -> Error(InvalidMediaType(value))
    _, _, _, _, _, Some(value), _ -> Error(DuplicateMediaType(value))
    _, _, _, _, _, _, False -> Error(InvalidMaximumBytes)
    True, True, True, [_, ..], None, None, True ->
      Ok(Policy(
        track_value,
        authority_id_value,
        source_value,
        allowed_media_values,
        maximum_bytes_value,
      ))
  }
}

/// Capture a bounded UTF-8 response before any semantic decoder runs.
///
/// `as_of` is caller-supplied because a raw response may expose no trustworthy
/// publication timestamp. Source adapters may conservatively use retrieval time
/// for a point-in-time page/feed snapshot.
pub fn capture(
  policy policy_value: Policy,
  response response_value: Response,
  as_of as_of_value: Instant,
  retrieved_at retrieved_at_value: Instant,
) -> Result(Snapshot, CaptureError) {
  use media_type <- result_try(validate_response(policy_value, response_value))
  let body = response.body(response_value)
  use content_hash <- result_try(
    hash.text(body) |> result_map_error(InvalidHash),
  )
  let fingerprint_payload =
    fields([
      "authority-source-v1",
      finance_track.name(policy_value.track),
      policy_value.authority_id,
      source.provider(policy_value.source),
      source.reference(policy_value.source),
      source_kind_name(source.kind(policy_value.source)),
    ])
  use fingerprint_hash <- result_try(
    hash.text(fingerprint_payload) |> result_map_error(InvalidHash),
  )
  let source_fingerprint = identity.source_fingerprint(fingerprint_hash)
  let byte_length = response.byte_length(response_value)
  let evidence_payload =
    fields([
      "authority-evidence-v1",
      identity.source_fingerprint_value(source_fingerprint),
      identity.sha256_value(content_hash),
      int.to_string(time.unix_milliseconds(as_of_value)),
      int.to_string(time.unix_milliseconds(retrieved_at_value)),
      media_type,
      int.to_string(byte_length),
      "official-public-local-analysis-only",
      "no_redistribution",
    ])
  use evidence_hash <- result_try(
    hash.text(evidence_payload) |> result_map_error(InvalidHash),
  )
  use item <- result_try(
    evidence.new(
      id: identity.evidence_id(evidence_hash),
      source_fingerprint: source_fingerprint,
      source: policy_value.source,
      licence: evidence.Licence(
        label: "official-public-local-analysis-only",
        redistribution: evidence.NoRedistribution,
        notes: Some(
          "Public read access does not grant bulk redistribution; retain the official source link and attribution.",
        ),
      ),
      as_of: as_of_value,
      retrieved_at: retrieved_at_value,
      media_type: media_type,
      byte_length: byte_length,
      content_hash: content_hash,
      parents: [],
      assumptions: [],
    )
    |> result_map_error(InvalidEvidence),
  )
  Ok(Snapshot(
    policy_value.track,
    policy_value.authority_id,
    policy_value.source,
    body,
    item,
  ))
}

pub fn track(value: Snapshot) -> Track {
  value.track
}

pub fn authority_id(value: Snapshot) -> String {
  value.authority_id
}

pub fn source(value: Snapshot) -> SourceRef {
  value.source
}

pub fn body(value: Snapshot) -> String {
  value.body
}

pub fn evidence(value: Snapshot) -> Evidence {
  value.evidence
}

fn authority_source(value: SourceRef) -> Bool {
  case source.kind(value) {
    source.Official | source.Exchange | source.Regulator -> True
    _ -> False
  }
}

fn validate_response(
  policy: Policy,
  value: Response,
) -> Result(String, CaptureError) {
  case response.status(value) {
    200 ->
      case response.first_header(value, name: "content-type") {
        None -> Error(MissingContentType)
        Some(raw_media_type) -> {
          let media_type = normalize_media_type(raw_media_type)
          let declared = response.byte_length(value)
          let actual = string.byte_size(response.body(value))
          case
            list.contains(policy.allowed_media_types, media_type),
            response.body(value) != "",
            declared == actual,
            declared <= policy.maximum_bytes
          {
            False, _, _, _ -> Error(UnsupportedMediaType(media_type))
            _, False, _, _ -> Error(EmptyBody)
            _, _, False, _ -> Error(ByteLengthMismatch(declared, actual))
            _, _, _, False ->
              Error(ResponseTooLarge(policy.maximum_bytes, declared))
            True, True, True, True -> Ok(media_type)
          }
        }
      }
    status -> Error(UnexpectedStatus(status))
  }
}

fn normalize_media_type(value: String) -> String {
  case string.split(value, on: ";") {
    [first, ..] -> first |> string.trim |> string.lowercase
    [] -> ""
  }
}

fn fields(values: List(String)) -> String {
  values
  |> list.map(fn(value) {
    int.to_string(string.byte_size(value)) <> ":" <> value
  })
  |> string.join("")
}

fn source_kind_name(value: source.SourceKind) -> String {
  case value {
    source.Official -> "official"
    source.Exchange -> "exchange"
    source.Regulator -> "regulator"
    source.LicensedVendor -> "licensed_vendor"
    source.UserSupplied -> "user_supplied"
    source.Synthetic -> "synthetic"
    source.Other(kind) -> "other:" <> kind
  }
}

fn first_invalid_media(values: List(String)) -> Option(String) {
  case values {
    [] -> None
    [first, ..rest] ->
      case valid_media_type(first) {
        True -> first_invalid_media(rest)
        False -> Some(first)
      }
  }
}

fn first_duplicate(values: List(String)) -> Option(String) {
  case values {
    [] -> None
    [first, ..rest] ->
      case list.contains(rest, first) {
        True -> Some(first)
        False -> first_duplicate(rest)
      }
  }
}

fn valid_media_type(value: String) -> Bool {
  value != ""
  && string.trim(value) == value
  && value == string.lowercase(value)
  && !string.contains(value, ";")
  && !string.contains(value, " ")
  && !string.contains(value, "\r")
  && !string.contains(value, "\n")
  && string.contains(value, "/")
}

fn valid_id(value: String) -> Bool {
  value != ""
  && string.trim(value) == value
  && string.length(value) <= 100
  && {
    value
    |> string.to_graphemes
    |> list.all(fn(character) {
      string.contains("abcdefghijklmnopqrstuvwxyz0123456789_", character)
    })
  }
}

fn result_try(
  value: Result(a, e),
  next: fn(a) -> Result(b, e),
) -> Result(b, e) {
  case value {
    Ok(value) -> next(value)
    Error(error) -> Error(error)
  }
}

fn result_map_error(value: Result(a, e), wrap: fn(e) -> f) -> Result(a, f) {
  case value {
    Ok(value) -> Ok(value)
    Error(error) -> Error(wrap(error))
  }
}
