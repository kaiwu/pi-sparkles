import finance_authority_snapshot/snapshot
import finance_core/identifier
import finance_core/source
import finance_core/time.{type Instant}
import finance_hkex/request
import finance_hkex/security_search.{type Query, type Security}
import finance_http/response.{type Response}
import finance_provenance/hash
import finance_provenance/identity
import finance_track
import gleam/int
import gleam/json

pub const schema = "pi-sparkles/hkex-current-security-receipt"

pub const schema_version = 1

pub const authority_id = "hk_hkexnews_current_security_catalogue"

pub opaque type Reference {
  Reference(
    query: Query,
    provider_more_marker: String,
    candidates: List(Security),
    snapshot: snapshot.Snapshot,
  )
}

pub type ReferenceError {
  InvalidSnapshot(snapshot.CaptureError)
  InvalidSecurityPayload(security_search.DecodeError)
}

/// Capture the exact HKEXnews current-security response before decoding it.
///
/// The endpoint proves only exact code/name/stock-ID catalogue membership at
/// retrieval. It does not prove a listing interval, board, share class,
/// currency, or whether the security traded in any particular session.
pub fn capture(
  query query_value: Query,
  response response_value: Response,
  retrieved_at retrieved_at_value: Instant,
) -> Result(Reference, ReferenceError) {
  case
    snapshot.capture(
      policy(query_value),
      response_value,
      as_of: retrieved_at_value,
      retrieved_at: retrieved_at_value,
    )
  {
    Error(error) -> Error(InvalidSnapshot(error))
    Ok(captured) ->
      case security_search.decode_page(snapshot.body(captured)) {
        Error(error) -> Error(InvalidSecurityPayload(error))
        Ok(page) ->
          Ok(Reference(
            query_value,
            security_search.page_more(page),
            page
              |> security_search.page_securities
              |> security_search.resolve_code(code: security_search.query_code(
                query_value,
              ))
              |> identifier.resolution_candidates,
            captured,
          ))
      }
  }
}

pub fn query_code(value: Reference) -> String {
  security_search.query_code(value.query)
}

pub fn provider_more_marker(value: Reference) -> String {
  value.provider_more_marker
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
    #("track", json.string(finance_track.name(finance_track.Hk))),
    #("authority_id", json.string(authority_id)),
    #("provider", json.string("HKEXnews")),
    #("source_reference", json.string(source_reference(value))),
    #("query_code", json.string(query_code(value))),
    #("observed_at_unix_ms", retrieved |> int.to_string |> json.string),
    #("retrieved_at_unix_ms", retrieved |> int.to_string |> json.string),
    #("catalogue_scope", json.string("current_security_prefix_exact_code_only")),
    #("provider_more_marker", json.string(provider_more_marker(value))),
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
    #("venue_mic", json.string("XHKG")),
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
    #("stock_id", json.int(security_search.stock_id(value))),
    #("code", json.string(security_search.code(value))),
    #("name", json.string(security_search.name(value))),
    #("venue_mic", json.string("XHKG")),
  ])
}

fn policy(query_value: Query) -> snapshot.Policy {
  let assert Ok(source_ref) =
    source.new(
      provider: "HKEXnews",
      reference: exact_source_reference(query_value),
      kind: source.Exchange,
    )
  let assert Ok(value) =
    snapshot.local_analysis_policy(
      track: finance_track.Hk,
      authority_id: authority_id,
      source: source_ref,
      allowed_media_types: [
        "application/javascript",
        "application/json",
        "text/javascript",
        "application/x-javascript",
        "text/html",
      ],
      maximum_bytes: 2_000_000,
    )
  value
}

fn exact_source_reference(query_value: Query) -> String {
  request.origin
  <> request.security_prefix_path
  <> "?callback=pi_sparkles&lang=EN&type=A&name="
  <> security_search.query_code(query_value)
  <> "&market=SEHK"
}
