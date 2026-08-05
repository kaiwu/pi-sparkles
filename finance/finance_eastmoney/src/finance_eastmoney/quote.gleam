import finance_eastmoney/query.{type QuoteQuery}
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/string

pub opaque type Quote {
  Quote(
    code: String,
    name: String,
    decimals: Int,
    last: String,
    open: String,
    high: String,
    low: String,
    previous_close: String,
    provider_volume: Int,
    provider_unix_seconds: Int,
    price_limit_up: Option(String),
    price_limit_down: Option(String),
  )
}

type RawQuote {
  RawQuote(
    code: String,
    name: String,
    decimals: Int,
    last: Int,
    open: Int,
    high: Int,
    low: Int,
    previous_close: Int,
    provider_volume: Int,
    provider_unix_seconds: Int,
    price_limit_up: Option(Int),
    price_limit_down: Option(Int),
  )
}

pub type DecodeError {
  InvalidJson(json.DecodeError)
  CodeMismatch(expected: String, received: String)
}

pub fn decode(
  body: String,
  for plan: QuoteQuery,
) -> Result(Quote, DecodeError) {
  case json.parse(body, payload_decoder()) {
    Error(error) -> Error(InvalidJson(error))
    Ok(raw) -> {
      let expected = query.quote_code(plan)
      case raw.code == expected {
        False -> Error(CodeMismatch(expected, raw.code))
        True -> Ok(from_raw(raw))
      }
    }
  }
}

pub fn code(value: Quote) -> String {
  value.code
}

pub fn name(value: Quote) -> String {
  value.name
}

pub fn decimals(value: Quote) -> Int {
  value.decimals
}

pub fn last(value: Quote) -> String {
  value.last
}

pub fn open(value: Quote) -> String {
  value.open
}

pub fn high(value: Quote) -> String {
  value.high
}

pub fn low(value: Quote) -> String {
  value.low
}

pub fn previous_close(value: Quote) -> String {
  value.previous_close
}

pub fn provider_volume(value: Quote) -> Int {
  value.provider_volume
}

pub fn provider_unix_seconds(value: Quote) -> Int {
  value.provider_unix_seconds
}

pub fn price_limit_up(value: Quote) -> Option(String) {
  value.price_limit_up
}

pub fn price_limit_down(value: Quote) -> Option(String) {
  value.price_limit_down
}

fn payload_decoder() -> decode.Decoder(RawQuote) {
  use rc <- decode.field("rc", decode.int)
  use value <- decode.field("data", raw_decoder())
  case rc == 0 {
    True -> decode.success(value)
    False -> decode.failure(value, "successful Eastmoney quote response")
  }
}

fn raw_decoder() -> decode.Decoder(RawQuote) {
  use code <- decode.field("f57", decode.string)
  use name <- decode.field("f58", decode.string)
  use decimals <- decode.field("f59", decode.int)
  use last <- decode.field("f43", decode.int)
  use open <- decode.field("f46", decode.int)
  use high <- decode.field("f44", decode.int)
  use low <- decode.field("f45", decode.int)
  use previous_close <- decode.field("f60", decode.int)
  use provider_volume <- decode.field("f47", decode.int)
  use provider_unix_seconds <- decode.field("f86", decode.int)
  use price_limit_up <- decode.optional_field(
    "f51",
    None,
    decode.int |> decode.map(Some),
  )
  use price_limit_down <- decode.optional_field(
    "f52",
    None,
    decode.int |> decode.map(Some),
  )
  let value =
    RawQuote(
      code,
      name,
      decimals,
      last,
      open,
      high,
      low,
      previous_close,
      provider_volume,
      provider_unix_seconds,
      price_limit_up,
      price_limit_down,
    )
  case
    code != "",
    name != "" && string.trim(name) == name,
    decimals >= 0 && decimals <= 8,
    provider_volume >= 0,
    provider_unix_seconds >= 0
  {
    True, True, True, True, True -> decode.success(value)
    _, _, _, _, _ -> decode.failure(value, "valid Eastmoney quote fields")
  }
}

fn from_raw(value: RawQuote) -> Quote {
  Quote(
    value.code,
    value.name,
    value.decimals,
    scaled(value.last, value.decimals),
    scaled(value.open, value.decimals),
    scaled(value.high, value.decimals),
    scaled(value.low, value.decimals),
    scaled(value.previous_close, value.decimals),
    value.provider_volume,
    value.provider_unix_seconds,
    option_scaled(value.price_limit_up, value.decimals),
    option_scaled(value.price_limit_down, value.decimals),
  )
}

fn option_scaled(value: Option(Int), decimals: Int) -> Option(String) {
  case value {
    None -> None
    Some(value) -> Some(scaled(value, decimals))
  }
}

fn scaled(value: Int, decimals: Int) -> String {
  let sign = case value < 0 {
    True -> "-"
    False -> ""
  }
  let digits = value |> int.absolute_value |> int.to_string
  case decimals {
    0 -> sign <> digits
    places -> {
      let padded = string.pad_start(digits, to: places + 1, with: "0")
      let split = string.length(padded) - places
      sign
      <> string.slice(padded, at_index: 0, length: split)
      <> "."
      <> string.slice(padded, at_index: split, length: places)
    }
  }
}
