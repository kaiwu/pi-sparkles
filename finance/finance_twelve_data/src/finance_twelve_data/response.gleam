import finance_core/decimal
import gleam/dynamic/decode
import gleam/json
import gleam/option.{type Option, None}
import gleam/order

pub type Profile {
  Profile(
    symbol: String,
    name: String,
    exchange: String,
    mic: String,
    sector: Option(String),
    industry: Option(String),
    employees: Option(String),
    website: Option(String),
    description: Option(String),
    security_type: Option(String),
    chief_executive: Option(String),
    address: Option(String),
    address_2: Option(String),
    city: Option(String),
    postal_code: Option(String),
    state: Option(String),
    country: Option(String),
    phone: Option(String),
  )
}

pub type Statistics {
  Statistics(
    symbol: String,
    name: String,
    currency: String,
    exchange: String,
    mic: String,
    exchange_timezone: String,
    shares_outstanding: Option(String),
    float_shares: Option(String),
  )
}

type StatisticsMetadata {
  StatisticsMetadata(
    symbol: String,
    name: String,
    currency: String,
    exchange: String,
    mic: String,
    exchange_timezone: String,
  )
}

type ShareCounts {
  ShareCounts(shares_outstanding: Option(String), float_shares: Option(String))
}

pub fn decode_profile(body: String) -> Result(Profile, json.DecodeError) {
  body
  |> normalize_numbers
  |> json.parse(profile_decoder())
}

pub fn decode_statistics(body: String) -> Result(Statistics, json.DecodeError) {
  body
  |> normalize_numbers
  |> json.parse(statistics_decoder())
}

fn profile_decoder() -> decode.Decoder(Profile) {
  use symbol <- decode.field("symbol", decode.string)
  use name <- decode.field("name", decode.string)
  use exchange <- decode.field("exchange", decode.string)
  use mic <- decode.field("mic_code", decode.string)
  use sector <- optional_string("sector")
  use industry <- optional_string("industry")
  use employees <- optional_count("employees")
  use website <- optional_string("website")
  use description <- optional_string("description")
  use security_type <- optional_string("type")
  use chief_executive <- optional_string("CEO")
  use address <- optional_string("address")
  use address_2 <- optional_string("address2")
  use city <- optional_string("city")
  use postal_code <- optional_string("zip")
  use state <- optional_string("state")
  use country <- optional_string("country")
  use phone <- optional_string("phone")
  decode.success(Profile(
    symbol,
    name,
    exchange,
    mic,
    sector,
    industry,
    employees,
    website,
    description,
    security_type,
    chief_executive,
    address,
    address_2,
    city,
    postal_code,
    state,
    country,
    phone,
  ))
}

fn statistics_decoder() -> decode.Decoder(Statistics) {
  use metadata <- decode.field("meta", statistics_metadata_decoder())
  use counts <- decode.field("statistics", statistics_body_decoder())
  decode.success(Statistics(
    metadata.symbol,
    metadata.name,
    metadata.currency,
    metadata.exchange,
    metadata.mic,
    metadata.exchange_timezone,
    counts.shares_outstanding,
    counts.float_shares,
  ))
}

fn statistics_metadata_decoder() -> decode.Decoder(StatisticsMetadata) {
  use symbol <- decode.field("symbol", decode.string)
  use name <- decode.field("name", decode.string)
  use currency <- decode.field("currency", decode.string)
  use exchange <- decode.field("exchange", decode.string)
  use mic <- decode.field("mic_code", decode.string)
  use exchange_timezone <- decode.field("exchange_timezone", decode.string)
  decode.success(StatisticsMetadata(
    symbol,
    name,
    currency,
    exchange,
    mic,
    exchange_timezone,
  ))
}

fn statistics_body_decoder() -> decode.Decoder(ShareCounts) {
  use counts <- decode.field("stock_statistics", share_counts_decoder())
  decode.success(counts)
}

fn share_counts_decoder() -> decode.Decoder(ShareCounts) {
  use shares_outstanding <- optional_count("shares_outstanding")
  use float_shares <- optional_count("float_shares")
  decode.success(ShareCounts(shares_outstanding, float_shares))
}

fn optional_string(
  name: String,
  next: fn(Option(String)) -> decode.Decoder(value),
) -> decode.Decoder(value) {
  decode.optional_field(name, None, decode.optional(decode.string), next)
}

fn optional_count(
  name: String,
  next: fn(Option(String)) -> decode.Decoder(value),
) -> decode.Decoder(value) {
  decode.optional_field(
    name,
    None,
    decode.optional(non_negative_integer_decoder()),
    next,
  )
}

fn non_negative_integer_decoder() -> decode.Decoder(String) {
  exact_number_decoder()
  |> decode.then(fn(raw) {
    case decimal.parse(raw) {
      Error(_) -> decode.failure("0", "non-negative integer source number")
      Ok(value) ->
        case
          decimal.scale(value) == 0
          && decimal.compare(value, decimal.zero()) != order.Lt
        {
          True -> decode.success(raw)
          False -> decode.failure("0", "non-negative integer source number")
        }
    }
  })
}

fn exact_number_decoder() -> decode.Decoder(String) {
  decode.at(["__finance_twelve_data_number__"], decode.string)
}

@external(javascript, "./response_ffi.mjs", "normalize_numbers")
fn normalize_numbers(source: String) -> String
