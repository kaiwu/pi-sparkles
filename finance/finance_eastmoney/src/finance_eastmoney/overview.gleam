import finance_eastmoney/query.{type CnOverviewQuery}
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub type Fact {
  Observed(raw: String)
  Unavailable(reason: String)
}

pub opaque type Benchmark {
  Benchmark(
    code: String,
    provider_market_id: String,
    name: String,
    last: Fact,
    change_percent: Fact,
    change: Fact,
    provider_volume: Fact,
    provider_reported_amount: Fact,
    high: Fact,
    low: Fact,
    open: Fact,
    previous_close: Fact,
    advanced: Fact,
    declined: Fact,
    unchanged: Fact,
  )
}

pub opaque type Overview {
  Overview(benchmarks: List(Benchmark))
}

type Payload {
  Payload(total: String, benchmarks: List(Benchmark))
}

pub type DecodeError {
  InvalidJson(json.DecodeError)
  ProviderCountMismatch(expected: Int, received: String)
  MissingBenchmark(code: String)
  DuplicateBenchmark(code: String)
  UnexpectedBenchmark(code: String, provider_market_id: String)
  InvalidObservedValue(field: String, raw: String)
}

pub fn decode(
  body: String,
  for _plan: CnOverviewQuery,
) -> Result(Overview, DecodeError) {
  use payload <- result.try(
    body
    |> normalize_numbers
    |> json.parse(payload_decoder())
    |> result.map_error(InvalidJson),
  )
  use _ <- result.try(case int.parse(payload.total) {
    Ok(5) -> Ok(Nil)
    _ -> Error(ProviderCountMismatch(5, payload.total))
  })
  use _ <- result.try(validate_benchmarks(
    expected_benchmarks(),
    payload.benchmarks,
  ))
  Ok(Overview(order_benchmarks(expected_benchmarks(), payload.benchmarks)))
}

pub fn benchmarks(value: Overview) -> List(Benchmark) {
  value.benchmarks
}

pub fn code(value: Benchmark) -> String {
  value.code
}

pub fn provider_market_id(value: Benchmark) -> String {
  value.provider_market_id
}

pub fn name(value: Benchmark) -> String {
  value.name
}

pub fn last(value: Benchmark) -> Fact {
  scaled_price(value.last)
}

pub fn change_percent(value: Benchmark) -> Fact {
  scaled_price(value.change_percent)
}

pub fn change(value: Benchmark) -> Fact {
  scaled_price(value.change)
}

pub fn provider_volume(value: Benchmark) -> Fact {
  value.provider_volume
}

pub fn provider_reported_amount(value: Benchmark) -> Fact {
  value.provider_reported_amount
}

pub fn high(value: Benchmark) -> Fact {
  scaled_price(value.high)
}

pub fn low(value: Benchmark) -> Fact {
  scaled_price(value.low)
}

pub fn open(value: Benchmark) -> Fact {
  scaled_price(value.open)
}

pub fn previous_close(value: Benchmark) -> Fact {
  scaled_price(value.previous_close)
}

pub fn advanced(value: Benchmark) -> Fact {
  value.advanced
}

pub fn declined(value: Benchmark) -> Fact {
  value.declined
}

pub fn unchanged(value: Benchmark) -> Fact {
  value.unchanged
}

pub fn shanghai_breadth(value: Overview) -> Option(Benchmark) {
  find(value.benchmarks, "000001")
}

pub fn shenzhen_breadth(value: Overview) -> Option(Benchmark) {
  find(value.benchmarks, "399001")
}

fn payload_decoder() -> decode.Decoder(Payload) {
  use rc <- decode.field("rc", number_decoder())
  use data <- decode.field("data", data_decoder())
  case rc == "0" {
    True -> decode.success(data)
    False -> decode.failure(data, "successful Eastmoney overview response")
  }
}

fn data_decoder() -> decode.Decoder(Payload) {
  use total <- decode.field("total", number_decoder())
  use benchmarks <- decode.field("diff", decode.list(of: benchmark_decoder()))
  decode.success(Payload(total, benchmarks))
}

fn benchmark_decoder() -> decode.Decoder(Benchmark) {
  use last <- fact_field("f2")
  use change_percent <- fact_field("f3")
  use change <- fact_field("f4")
  use provider_volume <- fact_field("f5")
  use provider_reported_amount <- fact_field("f6")
  use code <- decode.field("f12", decode.string)
  use provider_market_id <- decode.field("f13", number_decoder())
  use name <- decode.field("f14", decode.string)
  use high <- fact_field("f15")
  use low <- fact_field("f16")
  use open <- fact_field("f17")
  use previous_close <- fact_field("f18")
  use advanced <- fact_field("f104")
  use declined <- fact_field("f105")
  use unchanged <- fact_field("f106")
  decode.success(Benchmark(
    code,
    provider_market_id,
    name,
    last,
    change_percent,
    change,
    provider_volume,
    provider_reported_amount,
    high,
    low,
    open,
    previous_close,
    advanced,
    declined,
    unchanged,
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
  decode.at(["__finance_eastmoney_overview_number__"], decode.string)
}

fn expected_benchmarks() -> List(#(String, String)) {
  [
    #("000001", "1"),
    #("399001", "0"),
    #("399006", "0"),
    #("000300", "1"),
    #("000688", "1"),
  ]
}

fn validate_benchmarks(
  expected: List(#(String, String)),
  received: List(Benchmark),
) -> Result(Nil, DecodeError) {
  use _ <- result.try(
    list.try_each(received, fn(value) {
      case list.find(expected, fn(item) { item.0 == value.code }) {
        Error(_) ->
          Error(UnexpectedBenchmark(value.code, value.provider_market_id))
        Ok(item) ->
          case item.1 == value.provider_market_id {
            True -> Ok(Nil)
            False ->
              Error(UnexpectedBenchmark(value.code, value.provider_market_id))
          }
      }
    }),
  )
  list.try_each(expected, fn(item) {
    let matches = list.filter(received, fn(value) { value.code == item.0 })
    case matches {
      [] -> Error(MissingBenchmark(item.0))
      [_] -> Ok(Nil)
      [_, _, ..] -> Error(DuplicateBenchmark(item.0))
    }
  })
}

fn order_benchmarks(
  expected: List(#(String, String)),
  received: List(Benchmark),
) -> List(Benchmark) {
  list.filter_map(expected, fn(item) {
    list.find(received, fn(value) { value.code == item.0 })
  })
}

fn find(values: List(Benchmark), expected_code: String) -> Option(Benchmark) {
  case list.find(values, fn(value) { value.code == expected_code }) {
    Ok(value) -> Some(value)
    Error(_) -> None
  }
}

fn scaled_price(value: Fact) -> Fact {
  case value {
    Unavailable(reason) -> Unavailable(reason)
    Observed(raw) ->
      case int.parse(raw) {
        Error(_) -> Unavailable("provider_integer_lexeme_invalid")
        Ok(number) -> Observed(scale_two(number))
      }
  }
}

fn scale_two(value: Int) -> String {
  let sign = case value < 0 {
    True -> "-"
    False -> ""
  }
  let digits = value |> int.absolute_value |> int.to_string
  let padded = string.pad_start(digits, to: 3, with: "0")
  let split = string.length(padded) - 2
  sign
  <> string.slice(padded, at_index: 0, length: split)
  <> "."
  <> string.slice(padded, at_index: split, length: 2)
}

@external(javascript, "./overview_ffi.mjs", "normalize_numbers")
fn normalize_numbers(source: String) -> String
