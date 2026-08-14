import finance_core/decimal
import finance_eastmoney/query.{type CnMoversQuery}
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/order.{Gt}
import gleam/result
import gleam/string

pub type Fact {
  Observed(raw: String)
  Unavailable(reason: String)
}

pub opaque type Mover {
  Mover(
    code: String,
    provider_market_id: String,
    name: String,
    last: Fact,
    change_percent: Fact,
    change: Fact,
    provider_volume: Fact,
    provider_amount: Fact,
    turnover_percent: Fact,
    high: Fact,
    low: Fact,
    open: Fact,
    previous_close: Fact,
    provider_market_cap: Fact,
    provider_float_market_cap: Fact,
  )
}

pub opaque type Movers {
  Movers(provider_total: Int, rows: List(Mover))
}

type Payload {
  Payload(total: String, rows: List(Mover))
}

pub type DecodeError {
  InvalidJson(json.DecodeError)
  InvalidProviderTotal(String)
  ProviderCountMismatch(expected: Int, received: Int)
  InvalidIdentity(code: String, provider_market_id: String)
  DuplicateIdentity(code: String, provider_market_id: String)
  InvalidRankValue(code: String, raw: String)
  ProviderOrderMismatch(previous_code: String, next_code: String)
}

pub fn decode(
  body: String,
  for plan: CnMoversQuery,
) -> Result(Movers, DecodeError) {
  use payload <- result.try(
    body
    |> normalize_numbers
    |> json.parse(payload_decoder())
    |> result.map_error(InvalidJson),
  )
  use total <- result.try(
    int.parse(payload.total)
    |> result.map_error(fn(_) { InvalidProviderTotal(payload.total) }),
  )
  let expected = int.min(total, query.cn_movers_limit(plan))
  use _ <- result.try(case list.length(payload.rows) == expected {
    True -> Ok(Nil)
    False -> Error(ProviderCountMismatch(expected, list.length(payload.rows)))
  })
  use _ <- result.try(validate_identities(payload.rows, []))
  use _ <- result.try(validate_order(payload.rows))
  Ok(Movers(total, payload.rows))
}

pub fn provider_total(value: Movers) -> Int {
  value.provider_total
}

pub fn rows(value: Movers) -> List(Mover) {
  value.rows
}

pub fn code(value: Mover) -> String {
  value.code
}

pub fn provider_market_id(value: Mover) -> String {
  value.provider_market_id
}

pub fn name(value: Mover) -> String {
  value.name
}

pub fn last(value: Mover) -> Fact {
  value.last
}

pub fn change_percent(value: Mover) -> Fact {
  value.change_percent
}

pub fn change(value: Mover) -> Fact {
  value.change
}

pub fn provider_volume(value: Mover) -> Fact {
  value.provider_volume
}

pub fn provider_amount(value: Mover) -> Fact {
  value.provider_amount
}

pub fn turnover_percent(value: Mover) -> Fact {
  value.turnover_percent
}

pub fn high(value: Mover) -> Fact {
  value.high
}

pub fn low(value: Mover) -> Fact {
  value.low
}

pub fn open(value: Mover) -> Fact {
  value.open
}

pub fn previous_close(value: Mover) -> Fact {
  value.previous_close
}

pub fn provider_market_cap(value: Mover) -> Fact {
  value.provider_market_cap
}

pub fn provider_float_market_cap(value: Mover) -> Fact {
  value.provider_float_market_cap
}

fn payload_decoder() -> decode.Decoder(Payload) {
  use rc <- decode.field("rc", number_decoder())
  use data <- decode.field("data", data_decoder())
  case rc == "0" {
    True -> decode.success(data)
    False -> decode.failure(data, "successful Eastmoney movers response")
  }
}

fn data_decoder() -> decode.Decoder(Payload) {
  use total <- decode.field("total", number_decoder())
  use rows <- decode.field("diff", decode.list(of: mover_decoder()))
  decode.success(Payload(total, rows))
}

fn mover_decoder() -> decode.Decoder(Mover) {
  use last <- fact_field("f2")
  use change_percent <- fact_field("f3")
  use change <- fact_field("f4")
  use volume <- fact_field("f5")
  use amount <- fact_field("f6")
  use turnover <- fact_field("f8")
  use code <- decode.field("f12", decode.string)
  use provider_market_id <- decode.field("f13", number_decoder())
  use name <- decode.field("f14", decode.string)
  use high <- fact_field("f15")
  use low <- fact_field("f16")
  use open <- fact_field("f17")
  use previous_close <- fact_field("f18")
  use market_cap <- fact_field("f20")
  use float_market_cap <- fact_field("f21")
  decode.success(Mover(
    code,
    provider_market_id,
    name,
    last,
    change_percent,
    change,
    volume,
    amount,
    turnover,
    high,
    low,
    open,
    previous_close,
    market_cap,
    float_market_cap,
  ))
}

fn fact_field(
  name: String,
  next: fn(Fact) -> decode.Decoder(value),
) -> decode.Decoder(value) {
  decode.field(name, fact_decoder(), next)
}

fn fact_decoder() -> decode.Decoder(Fact) {
  number_decoder()
  |> decode.map(Observed)
  |> decode.one_of(or: [
    decode.string
    |> decode.then(fn(value) {
      case value {
        "-" -> decode.success(Unavailable("provider_unavailable"))
        _ ->
          decode.failure(
            Unavailable("invalid_provider_value"),
            "numeric value or provider unavailable sentinel",
          )
      }
    }),
  ])
}

fn number_decoder() -> decode.Decoder(String) {
  decode.at(["__finance_eastmoney_movers_number__"], decode.string)
}

fn validate_identities(
  rows: List(Mover),
  seen: List(String),
) -> Result(Nil, DecodeError) {
  case rows {
    [] -> Ok(Nil)
    [row, ..rest] -> {
      let key = row.provider_market_id <> ":" <> row.code
      use _ <- result.try(
        case
          valid_code(row.code)
          && { row.provider_market_id == "0" || row.provider_market_id == "1" }
        {
          True -> Ok(Nil)
          False -> Error(InvalidIdentity(row.code, row.provider_market_id))
        },
      )
      use _ <- result.try(case list.contains(seen, key) {
        True -> Error(DuplicateIdentity(row.code, row.provider_market_id))
        False -> Ok(Nil)
      })
      validate_identities(rest, [key, ..seen])
    }
  }
}

fn validate_order(rows: List(Mover)) -> Result(Nil, DecodeError) {
  case rows {
    [] | [_] -> Ok(Nil)
    [previous, next, ..rest] -> {
      use previous_value <- result.try(rank_value(previous))
      use next_value <- result.try(rank_value(next))
      use _ <- result.try(case decimal.compare(next_value, previous_value) {
        Gt -> Error(ProviderOrderMismatch(previous.code, next.code))
        _ -> Ok(Nil)
      })
      validate_order([next, ..rest])
    }
  }
}

fn rank_value(row: Mover) -> Result(decimal.Decimal, DecodeError) {
  case row.change_percent {
    Unavailable(_) -> Error(InvalidRankValue(row.code, "provider_unavailable"))
    Observed(raw) ->
      decimal.parse(raw)
      |> result.map_error(fn(_) { InvalidRankValue(row.code, raw) })
  }
}

fn valid_code(code: String) -> Bool {
  string.length(code) == 6
  && code
  |> string.to_graphemes
  |> list.all(fn(character) { string.contains("0123456789", character) })
}

@external(javascript, "./movers_ffi.mjs", "normalize_numbers")
fn normalize_numbers(source: String) -> String
