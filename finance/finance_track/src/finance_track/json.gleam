import finance_core/identifier
import finance_core/time
import finance_track
import finance_track/context.{type Context}
import gleam/dynamic/decode
import gleam/json.{type Json}
import gleam/option.{type Option, None, Some}

pub const schema_version = 1

pub fn encode(value: Context) -> String {
  value |> to_json |> json.to_string
}

pub fn to_json(value: Context) -> Json {
  json.object([
    #("schemaVersion", json.int(schema_version)),
    #("track", json.string(finance_track.name(context.track(value)))),
    #("marketScope", json.string(context.market_scope(value))),
    #(
      "venueMic",
      json.nullable(context.venue_mic(value), fn(mic) {
        json.string(identifier.mic_value(mic))
      }),
    ),
    #("board", json.nullable(context.board(value), json.string)),
    #(
      "timezone",
      json.nullable(context.timezone(value), fn(zone) {
        json.string(time.timezone_name(zone))
      }),
    ),
    #("sourceLanguage", json.string(context.source_language(value))),
    #("providers", json.array(context.providers(value), json.string)),
    #("entitlement", json.string(context.entitlement(value))),
    #("limitations", json.array(context.limitations(value), json.string)),
  ])
}

/// Fields added to a Pi tool's existing top-level details object.
///
/// `track` is intentionally duplicated inside `trackContext` so consumers can
/// route cheaply while the nested value remains independently versioned and
/// decodable.
pub fn result_fields(value: Context) -> List(#(String, Json)) {
  [
    #("track", json.string(finance_track.name(context.track(value)))),
    #("trackContext", to_json(value)),
  ]
}

pub fn decode(input: String) -> Result(Context, json.DecodeError) {
  json.parse(input, decoder())
}

pub fn decoder() -> decode.Decoder(Context) {
  use _version <- decode.field("schemaVersion", version_decoder())
  use track <- decode.field("track", track_decoder())
  use market_scope <- decode.field("marketScope", decode.string)
  use venue <- decode.field("venueMic", decode.optional(decode.string))
  use board <- decode.field("board", decode.optional(decode.string))
  use timezone <- decode.field("timezone", decode.optional(decode.string))
  use source_language <- decode.field("sourceLanguage", decode.string)
  use providers <- decode.field("providers", decode.list(of: decode.string))
  use entitlement <- decode.field("entitlement", decode.string)
  use limitations <- decode.field("limitations", decode.list(of: decode.string))
  case optional_mic(venue), optional_timezone(timezone) {
    Ok(venue), Ok(timezone) ->
      case
        context.new(
          track: track,
          market_scope: market_scope,
          venue_mic: venue,
          board: board,
          timezone: timezone,
          source_language: source_language,
          providers: providers,
          entitlement: entitlement,
          limitations: limitations,
        )
      {
        Ok(value) -> decode.success(value)
        Error(_) -> decode.failure(placeholder(), "valid market track context")
      }
    _, _ -> decode.failure(placeholder(), "valid market track context")
  }
}

fn version_decoder() -> decode.Decoder(Int) {
  decode.int
  |> decode.then(fn(version) {
    case version == schema_version {
      True -> decode.success(version)
      False -> decode.failure(schema_version, "finance track schema v1")
    }
  })
}

fn track_decoder() -> decode.Decoder(finance_track.Track) {
  decode.string
  |> decode.then(fn(value) {
    case finance_track.from_name(value) {
      Ok(track) -> decode.success(track)
      Error(_) -> decode.failure(finance_track.Us, "cn, hk, or us track")
    }
  })
}

fn optional_mic(value: Option(String)) -> Result(Option(identifier.Mic), Nil) {
  case value {
    None -> Ok(None)
    Some(value) ->
      case identifier.mic(value) {
        Ok(value) -> Ok(Some(value))
        Error(_) -> Error(Nil)
      }
  }
}

fn optional_timezone(
  value: Option(String),
) -> Result(Option(time.Timezone), Nil) {
  case value {
    None -> Ok(None)
    Some(value) ->
      case time.timezone(value) {
        Ok(value) -> Ok(Some(value))
        Error(_) -> Error(Nil)
      }
  }
}

fn placeholder() -> Context {
  let assert Ok(value) =
    context.new(
      track: finance_track.Us,
      market_scope: "us_placeholder",
      venue_mic: None,
      board: None,
      timezone: None,
      source_language: "en-US",
      providers: ["placeholder"],
      entitlement: "unknown",
      limitations: [],
    )
  value
}
