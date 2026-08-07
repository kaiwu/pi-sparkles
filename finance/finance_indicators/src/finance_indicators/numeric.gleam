import finance_core/decimal.{type Decimal, type RoundingMode}
import finance_math/error.{type MetricError}
import finance_math/exact
import gleam/int
import gleam/list
import gleam/order.{Eq, Gt, Lt}
import gleam/result
import gleam/string

pub fn mean(
  values: List(Decimal),
  scale: Int,
  rounding: RoundingMode,
) -> Result(Decimal, String) {
  exact.mean(values, scale, rounding)
  |> map_metric_error
}

pub fn ratio(
  numerator: Decimal,
  denominator: Decimal,
  scale: Int,
  rounding: RoundingMode,
) -> Result(Decimal, String) {
  exact.ratio(numerator, denominator, scale, rounding)
  |> map_metric_error
}

pub fn quantize(
  value: Decimal,
  scale: Int,
  rounding: RoundingMode,
) -> Result(Decimal, String) {
  decimal.quantize(value, scale, rounding)
  |> fn(result) {
    case result {
      Ok(value) -> Ok(value)
      Error(_) -> Error("invalid_scale")
    }
  }
}

pub fn formatted(
  value: Decimal,
  scale: Int,
  rounding: RoundingMode,
) -> Result(String, String) {
  use value <- result.try(quantize(value, scale, rounding))
  Ok(pad_scale(decimal.to_string(value), scale))
}

pub fn formatted_exact(value: Decimal, scale: Int) -> String {
  pad_scale(decimal.to_string(value), scale)
}

pub fn from_int(value: Int) -> Decimal {
  let assert Ok(value) = value |> int.to_string |> decimal.parse
  value
}

pub fn absolute(value: Decimal) -> Decimal {
  case decimal.compare(value, decimal.zero()) {
    Lt -> decimal.negate(value)
    Eq | Gt -> value
  }
}

pub fn maximum(first: Decimal, rest: List(Decimal)) -> Decimal {
  list.fold(rest, first, fn(best, candidate) {
    case decimal.compare(candidate, best) {
      Gt -> candidate
      Eq | Lt -> best
    }
  })
}

pub fn is_zero(value: Decimal) -> Bool {
  decimal.compare(value, decimal.zero()) == Eq
}

fn pad_scale(value: String, scale: Int) -> String {
  case scale, string.split(value, on: ".") {
    0, [whole] -> whole
    0, [whole, _] -> whole
    _, [whole] -> whole <> "." <> string.repeat("0", times: scale)
    _, [whole, fraction] ->
      whole <> "." <> string.pad_end(fraction, to: scale, with: "0")
    _, _ -> value
  }
}

fn map_metric_error(
  value: Result(Decimal, MetricError),
) -> Result(Decimal, String) {
  case value {
    Ok(value) -> Ok(value)
    Error(_) -> Error("decimal_arithmetic_failure")
  }
}
