import finance_core/decimal
import finance_core/time
import finance_market_alpaca/bars
import finance_market_alpaca/query.{type LatestQuoteQuery}
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/json
import gleam/order.{Eq, Gt, Lt}
import gleam/result

pub opaque type RawQuote {
  RawQuote(
    timestamp: String,
    at: time.Instant,
    bid_exchange: String,
    bid_price: String,
    bid_size: String,
    ask_exchange: String,
    ask_price: String,
    ask_size: String,
    conditions: List(String),
    tape: String,
  )
}

type Payload {
  Payload(quotes: Dict(String, RawQuote))
}

pub type DecodeError {
  InvalidJson(json.DecodeError)
  UnexpectedSymbols
}

pub fn decode(
  body: String,
  for plan: LatestQuoteQuery,
) -> Result(RawQuote, DecodeError) {
  use payload <- result.try(
    body
    |> normalize_numbers
    |> json.parse(payload_decoder())
    |> result.map_error(InvalidJson),
  )
  let expected = query.quote_symbol(plan)
  case dict.to_list(payload.quotes) {
    [#(symbol, value)] if symbol == expected -> Ok(value)
    _ -> Error(UnexpectedSymbols)
  }
}

pub fn timestamp(value: RawQuote) -> String {
  value.timestamp
}

pub fn at(value: RawQuote) -> time.Instant {
  value.at
}

pub fn bid_exchange(value: RawQuote) -> String {
  value.bid_exchange
}

pub fn bid_price(value: RawQuote) -> String {
  value.bid_price
}

pub fn bid_size(value: RawQuote) -> String {
  value.bid_size
}

pub fn ask_exchange(value: RawQuote) -> String {
  value.ask_exchange
}

pub fn ask_price(value: RawQuote) -> String {
  value.ask_price
}

pub fn ask_size(value: RawQuote) -> String {
  value.ask_size
}

pub fn conditions(value: RawQuote) -> List(String) {
  value.conditions
}

pub fn tape(value: RawQuote) -> String {
  value.tape
}

fn payload_decoder() -> decode.Decoder(Payload) {
  use quotes <- decode.field(
    "quotes",
    decode.dict(decode.string, raw_quote_decoder()),
  )
  decode.success(Payload(quotes))
}

fn raw_quote_decoder() -> decode.Decoder(RawQuote) {
  use timestamp <- decode.field("t", decode.string)
  use bid_exchange <- decode.field("bx", decode.string)
  use bid_price <- decode.field("bp", number_decoder())
  use bid_size <- decode.field("bs", number_decoder())
  use ask_exchange <- decode.field("ax", decode.string)
  use ask_price <- decode.field("ap", number_decoder())
  use ask_size <- decode.field("as", number_decoder())
  use conditions <- decode.field("c", decode.list(of: decode.string))
  use tape <- decode.field("z", decode.string)
  let assert Ok(placeholder_at) = time.instant(0)
  case
    bars.parse_timestamp(timestamp),
    decimal_is_non_negative(bid_price),
    decimal_is_non_negative(bid_size),
    decimal_is_non_negative(ask_price),
    decimal_is_non_negative(ask_size)
  {
    Ok(#(at, _)), True, True, True, True ->
      decode.success(RawQuote(
        timestamp,
        at,
        bid_exchange,
        bid_price,
        bid_size,
        ask_exchange,
        ask_price,
        ask_size,
        conditions,
        tape,
      ))
    _, _, _, _, _ ->
      decode.failure(
        RawQuote(
          "1970-01-01T00:00:00Z",
          placeholder_at,
          "?",
          "0",
          "0",
          "?",
          "0",
          "0",
          [],
          "?",
        ),
        "valid Alpaca UTC quote timestamp and non-negative quote values",
      )
  }
}

fn decimal_is_non_negative(value: String) -> Bool {
  case decimal.parse(value) {
    Ok(parsed) ->
      case decimal.compare(parsed, decimal.zero()) {
        Lt -> False
        Eq | Gt -> True
      }
    Error(_) -> False
  }
}

fn number_decoder() -> decode.Decoder(String) {
  decode.at(["__finance_market_alpaca_number__"], decode.string)
}

@external(javascript, "./bars_ffi.mjs", "normalize_numbers")
fn normalize_numbers(source: String) -> String
