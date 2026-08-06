import finance_authority_snapshot/snapshot
import finance_cninfo/request
import finance_cninfo/security_master.{type Security}
import finance_core/identifier
import finance_core/source
import finance_core/time.{type Instant}
import finance_http/response.{type Response}
import finance_provenance/hash
import finance_provenance/identity
import finance_track
import gleam/int
import gleam/json
import gleam/list
import gleam/string

pub const schema = "pi-sparkles/cninfo-current-security-receipt"

pub const schema_version = 1

pub const authority_id = "cn_cninfo_security_catalogue"

pub opaque type Reference {
  Reference(
    query_code: String,
    candidates: List(Security),
    snapshot: snapshot.Snapshot,
  )
}

pub type ReferenceError {
  InvalidQueryCode
  InvalidSnapshot(snapshot.CaptureError)
  InvalidSecurityPayload(json.DecodeError)
}

/// Capture the exact CNINFO repository catalogue before decoding it.
///
/// Returned candidates prove only their code/organization/name/category/pinyin
/// association in this repository snapshot. They do not prove SSE/SZSE/BSE
/// venue origin, board, share class, currency, listing interval, or status.
pub fn capture(
  query_code code: String,
  response response_value: Response,
  retrieved_at retrieved_at_value: Instant,
) -> Result(Reference, ReferenceError) {
  case valid_code(code) {
    False -> Error(InvalidQueryCode)
    True ->
      case
        snapshot.capture(
          policy(),
          response_value,
          as_of: retrieved_at_value,
          retrieved_at: retrieved_at_value,
        )
      {
        Error(error) -> Error(InvalidSnapshot(error))
        Ok(captured) ->
          case security_master.decode(snapshot.body(captured)) {
            Error(error) -> Error(InvalidSecurityPayload(error))
            Ok(values) ->
              Ok(Reference(
                code,
                values
                  |> security_master.resolve_code(code: code)
                  |> identifier.resolution_candidates,
                captured,
              ))
          }
      }
  }
}

pub fn query_code(value: Reference) -> String {
  value.query_code
}

pub fn candidates(value: Reference) -> List(Security) {
  value.candidates
}

pub fn resolution(value: Reference) -> String {
  case value.candidates {
    [] -> "no_match"
    [_] -> "unique"
    [_, _, ..] -> "ambiguous"
  }
}

pub fn source_reference(value: Reference) -> String {
  value.snapshot |> snapshot.source |> source.reference
}

pub fn retrieved_at(value: Reference) -> Instant {
  value.snapshot |> snapshot.evidence |> fn(item) { item.retrieved_at }
}

pub fn evidence_id(value: Reference) -> String {
  value.snapshot
  |> snapshot.evidence
  |> fn(item) { item.id }
  |> identity.evidence_id_value
}

pub fn source_fingerprint(value: Reference) -> String {
  value.snapshot
  |> snapshot.evidence
  |> fn(item) { item.source_fingerprint }
  |> identity.source_fingerprint_value
}

pub fn media_type(value: Reference) -> String {
  value.snapshot |> snapshot.evidence |> fn(item) { item.media_type }
}

pub fn response_byte_length(value: Reference) -> Int {
  value.snapshot |> snapshot.evidence |> fn(item) { item.byte_length }
}

pub fn content_sha256(value: Reference) -> String {
  value.snapshot
  |> snapshot.evidence
  |> fn(item) { item.content_hash }
  |> identity.sha256_value
}

pub fn canonical_digest(value: Reference) -> String {
  let assert Ok(digest) = value |> canonical_text |> hash.text
  identity.sha256_value(digest)
}

pub fn canonical_text(value: Reference) -> String {
  let retrieved = value |> retrieved_at |> time.unix_milliseconds
  json.object([
    #("schema", json.string(schema)),
    #("schema_version", json.int(schema_version)),
    #("track", json.string(finance_track.name(finance_track.Cn))),
    #("authority_id", json.string(authority_id)),
    #("provider", json.string("CNINFO")),
    #("source_reference", json.string(source_reference(value))),
    #("query_code", json.string(query_code(value))),
    #("observed_at_unix_ms", retrieved |> int.to_string |> json.string),
    #("retrieved_at_unix_ms", retrieved |> int.to_string |> json.string),
    #(
      "catalogue_scope",
      json.string("public_repository_catalogue_snapshot_exact_code_only"),
    ),
    #("evidence_id", json.string(evidence_id(value))),
    #("source_fingerprint", json.string(source_fingerprint(value))),
    #("media_type", json.string(media_type(value))),
    #(
      "response_byte_length",
      value |> response_byte_length |> int.to_string |> json.string,
    ),
    #("content_sha256", json.string(content_sha256(value))),
    #("resolution", json.string(resolution(value))),
    #("candidates", json.array(value.candidates, candidate_json)),
    #("venue_mic", json.null()),
    #("board", json.null()),
    #("share_class", json.null()),
    #("currency", json.null()),
    #("listing_effective_from", json.null()),
    #("listing_effective_to", json.null()),
    #("trading_status", json.null()),
  ])
  |> json.to_string
}

fn candidate_json(value: Security) -> json.Json {
  json.object([
    #("code", json.string(security_master.code(value))),
    #("organization_id", json.string(security_master.organization_id(value))),
    #("short_name", json.string(security_master.short_name(value))),
    #("category", json.string(security_master.category(value))),
    #("pinyin", json.string(security_master.pinyin(value))),
    #("venue_mic", json.null()),
    #("board", json.null()),
  ])
}

fn policy() -> snapshot.Policy {
  let assert Ok(source_ref) =
    source.new(
      provider: "CNINFO",
      reference: request.discovery_origin <> request.security_master_path,
      kind: source.Official,
    )
  let assert Ok(value) =
    snapshot.local_analysis_policy(
      track: finance_track.Cn,
      authority_id: authority_id,
      source: source_ref,
      allowed_media_types: ["application/json", "text/json", "text/plain"],
      maximum_bytes: 5_000_000,
    )
  value
}

fn valid_code(value: String) -> Bool {
  string.length(value) == 6
  && value
  |> string.to_graphemes
  |> list.all(fn(character) { string.contains("0123456789", character) })
}
