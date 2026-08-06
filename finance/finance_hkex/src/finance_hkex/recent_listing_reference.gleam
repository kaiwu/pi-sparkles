import finance_authority_snapshot/snapshot
import finance_core/source
import finance_core/time.{type Date, type Instant}
import finance_hkex/recent_listing.{type Event}
import finance_hkex/request
import finance_hkex/security_search.{type Query}
import finance_http/response.{type Response}
import finance_provenance/hash
import finance_provenance/identity
import finance_track
import gleam/int
import gleam/json
import gleam/option.{type Option, None, Some}

pub const schema = "pi-sparkles/hkex-recent-listing-event-receipt"

pub const schema_version = 1

pub const authority_id = "hk_hkex_recent_listing_events"

pub opaque type Reference {
  Reference(
    query: Query,
    page: recent_listing.Page,
    snapshot: snapshot.Snapshot,
  )
}

pub type ReferenceError {
  InvalidSnapshot(snapshot.CaptureError)
  InvalidListingPage(recent_listing.DecodeError)
}

/// Capture the public HKEX page before decoding its rolling two-week rows.
///
/// A non-tentative exact `New Listing` row can prove a listing start. This
/// source does not prove historical completeness, a listing end, or positive
/// trading status for any session.
pub fn capture(
  query query_value: Query,
  response response_value: Response,
  retrieved_at retrieved_at_value: Instant,
) -> Result(Reference, ReferenceError) {
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
      case
        recent_listing.decode(
          snapshot.body(captured),
          security_search.query_code(query_value),
        )
      {
        Error(error) -> Error(InvalidListingPage(error))
        Ok(page) -> Ok(Reference(query_value, page, captured))
      }
  }
}

pub fn query_code(value: Reference) -> String {
  security_search.query_code(value.query)
}

pub fn updated_as(value: Reference) -> Date {
  recent_listing.updated_as(value.page)
}

pub fn candidates(value: Reference) -> List(Event) {
  recent_listing.candidates(value.page)
}

pub fn resolution(value: Reference) -> String {
  recent_listing.resolution(value.page)
}

pub fn listing_effective_from(value: Reference) -> Option(Date) {
  case candidates(value) {
    [event] -> recent_listing.listing_effective_from(event)
    _ -> None
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
    #("provider", json.string("HKEX")),
    #("source_reference", json.string(source_reference(value))),
    #("query_code", json.string(query_code(value))),
    #("page_updated_as", json.string(date_text(updated_as(value)))),
    #("retrieved_at_unix_ms", retrieved |> int.to_string |> json.string),
    #("window_scope", json.string("rolling_current_two_weeks_only")),
    #("evidence_id", json.string(evidence_id(value))),
    #("source_fingerprint", json.string(source_fingerprint(value))),
    #("media_type", json.string(media_type(value))),
    #(
      "response_byte_length",
      value |> response_byte_length |> int.to_string |> json.string,
    ),
    #("content_sha256", json.string(content_sha256(value))),
    #("resolution", json.string(resolution(value))),
    #("candidates", json.array(candidates(value), event_json)),
    #("venue_mic", json.string("XHKG")),
    #("listing_effective_from", option_date_json(listing_effective_from(value))),
    #("listing_effective_to", json.null()),
    #("trading_status", json.null()),
  ])
  |> json.to_string
}

fn event_json(value: Event) -> json.Json {
  json.object([
    #("event_date", json.string(date_text(recent_listing.event_date(value)))),
    #("tentative", json.bool(recent_listing.tentative(value))),
    #("short_name", json.string(recent_listing.short_name(value))),
    #("code", json.string(recent_listing.code(value))),
    #("board_lot", json.string(recent_listing.board_lot(value))),
    #("ccass_marker", json.string(recent_listing.ccass_marker(value))),
    #("short_sell_marker", json.string(recent_listing.short_sell_marker(value))),
    #("stamp_duty_marker", json.string(recent_listing.stamp_duty_marker(value))),
    #("auction_marker", json.string(recent_listing.auction_marker(value))),
    #("corporate_action", json.string(recent_listing.corporate_action(value))),
    #("related_code", json.string(recent_listing.related_code(value))),
    #(
      "listing_effective_from",
      option_date_json(recent_listing.listing_effective_from(value)),
    ),
  ])
}

fn policy() -> snapshot.Policy {
  let assert Ok(source_ref) =
    source.new(
      provider: "HKEX",
      reference: request.securities_origin
        <> request.recent_listings_path
        <> "?sc_lang=en",
      kind: source.Exchange,
    )
  let assert Ok(value) =
    snapshot.local_analysis_policy(
      track: finance_track.Hk,
      authority_id: authority_id,
      source: source_ref,
      allowed_media_types: ["text/html", "application/xhtml+xml"],
      maximum_bytes: 4_000_000,
    )
  value
}

fn option_date_json(value: Option(Date)) -> json.Json {
  case value {
    Some(value) -> json.string(date_text(value))
    None -> json.null()
  }
}

fn date_text(value: Date) -> String {
  let #(year, month, day) = time.date_parts(value)
  int.to_string(year) <> "-" <> pad(month) <> "-" <> pad(day)
}

fn pad(value: Int) -> String {
  case value < 10 {
    True -> "0" <> int.to_string(value)
    False -> int.to_string(value)
  }
}
