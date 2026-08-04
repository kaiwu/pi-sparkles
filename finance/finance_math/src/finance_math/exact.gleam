import finance_core/decimal.{type Decimal, type RoundingMode}
import finance_math/error.{type MetricError}
import gleam/int
import gleam/list
import gleam/result

/// Add exact decimals without changing their precision.
pub fn sum(values: List(Decimal)) -> Decimal {
  list.fold(values, decimal.zero(), decimal.add)
}

/// Divide using an explicit output scale and rounding policy.
pub fn ratio(
  numerator: Decimal,
  denominator: Decimal,
  scale: Int,
  rounding: RoundingMode,
) -> Result(Decimal, MetricError) {
  decimal.divide(numerator, denominator, scale, rounding)
  |> result.map_error(fn(error) {
    case error {
      decimal.DivisionByZero -> error.DivisionByZero
      decimal.NegativeResultScale -> error.InvalidScale
    }
  })
}

/// Compute a ratio expressed in percentage points.
pub fn percentage(
  numerator: Decimal,
  denominator: Decimal,
  scale: Int,
  rounding: RoundingMode,
) -> Result(Decimal, MetricError) {
  ratio(
    decimal.multiply(numerator, decimal_from_int(100)),
    denominator,
    scale,
    rounding,
  )
}

/// `(current - previous) / previous`, with no hidden zero convention.
pub fn growth(
  current: Decimal,
  previous: Decimal,
  scale: Int,
  rounding: RoundingMode,
) -> Result(Decimal, MetricError) {
  ratio(decimal.subtract(current, previous), previous, scale, rounding)
}

/// Arithmetic mean with an explicit decimal precision policy.
pub fn mean(
  values: List(Decimal),
  scale: Int,
  rounding: RoundingMode,
) -> Result(Decimal, MetricError) {
  case values {
    [] -> Error(error.EmptyInput)
    _ ->
      ratio(sum(values), decimal_from_int(list.length(values)), scale, rounding)
  }
}

fn decimal_from_int(value: Int) -> Decimal {
  let assert Ok(decimal_value) = value |> int.to_string |> decimal.parse
  decimal_value
}
