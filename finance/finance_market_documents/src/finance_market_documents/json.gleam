import finance_core/identifier
import finance_core/source
import finance_core/time
import finance_listing/listing
import finance_market_documents/document
import finance_market_documents/wire
import finance_provenance/identity
import finance_track
import gleam/dynamic/decode
import gleam/json.{type Json}
import gleam/option.{None}

pub const schema_version = 1

pub fn encode(value: document.Document) -> String {
  value |> to_json |> json.to_string
}

pub fn to_json(value: document.Document) -> Json {
  json.object([
    #("schemaVersion", json.int(schema_version)),
    #("id", value |> document.id |> document.document_id_value |> json.string),
    #("track", json.string(finance_track.name(document.track(value)))),
    #("issuer", wire.listing_json(document.issuer(value))),
    #("kind", json.string(document.kind(value))),
    #("originalTitle", json.string(document.original_title(value))),
    #("originalText", json.nullable(document.original_text(value), json.string)),
    #("language", json.string(document.language(value))),
    #(
      "publishedAtUnixMs",
      value |> document.published_at |> time.unix_milliseconds |> json.int,
    ),
    #("period", json.nullable(document.reporting_period(value), period_json)),
    #("source", wire.source_json(document.source(value))),
    #("evidenceId", wire.evidence_id_json(document.evidence_id(value))),
  ])
}

pub fn decode(input: String) -> Result(document.Document, json.DecodeError) {
  json.parse(input, decoder())
}

pub fn decoder() -> decode.Decoder(document.Document) {
  use _version <- decode.field("schemaVersion", version_decoder())
  use id_value <- decode.field("id", decode.string)
  use track <- decode.field("track", wire.track_decoder())
  use issuer <- decode.field("issuer", wire.listing_decoder())
  use kind <- decode.field("kind", decode.string)
  use title <- decode.field("originalTitle", decode.string)
  use text <- decode.field("originalText", decode.optional(decode.string))
  use language <- decode.field("language", decode.string)
  use published <- decode.field("publishedAtUnixMs", instant_decoder())
  use period <- decode.field("period", decode.optional(period_decoder()))
  use source <- decode.field("source", wire.source_decoder())
  use evidence <- decode.field("evidenceId", wire.evidence_id_decoder())
  case document.document_id(id_value) {
    Error(_) -> decode.failure(placeholder(), "valid market document")
    Ok(id) ->
      case
        document.new(
          id: id,
          track: track,
          issuer: issuer,
          kind: kind,
          original_title: title,
          original_text: text,
          language: language,
          published_at: published,
          period: period,
          source: source,
          evidence_id: evidence,
        )
      {
        Ok(value) -> decode.success(value)
        Error(_) -> decode.failure(placeholder(), "valid market document")
      }
  }
}

fn period_json(value: document.Period) -> Json {
  json.object([
    #("start", json.nullable(document.period_start(value), wire.date_json)),
    #("end", wire.date_json(document.period_end(value))),
  ])
}

fn period_decoder() -> decode.Decoder(document.Period) {
  use start <- decode.field("start", decode.optional(wire.date_decoder()))
  use end <- decode.field("end", wire.date_decoder())
  case document.period(start, end) {
    Ok(value) -> decode.success(value)
    Error(_) -> decode.failure(placeholder_period(), "valid reporting period")
  }
}

fn version_decoder() -> decode.Decoder(Int) {
  decode.int
  |> decode.then(fn(version) {
    case version == schema_version {
      True -> decode.success(version)
      False -> decode.failure(schema_version, "market document schema v1")
    }
  })
}

fn instant_decoder() -> decode.Decoder(time.Instant) {
  let assert Ok(placeholder) = time.instant(0)
  decode.int
  |> decode.then(fn(milliseconds) {
    case time.instant(milliseconds) {
      Ok(value) -> decode.success(value)
      Error(_) -> decode.failure(placeholder, "safe Unix milliseconds")
    }
  })
}

fn placeholder() -> document.Document {
  let assert Ok(id) = document.document_id("wire-placeholder")
  let assert Ok(instrument) = identifier.instrument_id("wire-placeholder")
  let assert Ok(symbol) = identifier.symbol("PLACEHOLDER")
  let assert Ok(mic) = identifier.mic("XNAS")
  let issuer = listing.new(finance_track.Us, instrument, symbol, mic)
  let assert Ok(source) =
    source.new("wire-placeholder", "placeholder", source.Synthetic)
  let assert Ok(hash) =
    identity.sha256(
      "0000000000000000000000000000000000000000000000000000000000000000",
    )
  let assert Ok(published) = time.instant(0)
  let assert Ok(value) =
    document.new(
      id: id,
      track: finance_track.Us,
      issuer: issuer,
      kind: "placeholder",
      original_title: "placeholder",
      original_text: None,
      language: "en",
      published_at: published,
      period: None,
      source: source,
      evidence_id: identity.evidence_id(hash),
    )
  value
}

fn placeholder_period() -> document.Period {
  let assert Ok(date) = time.date(1970, 1, 1)
  let assert Ok(value) = document.period(None, date)
  value
}
