import finance_core/decimal.{type Decimal, type RoundingMode}
import finance_core/time.{type Instant}
import finance_series/series.{type Datum, type Series}
import gleam/list
import gleam/order

pub type ReturnError {
  DivisionByZero(at: Instant)
  InvalidScale
}

/// Exact simple returns `(current / previous) - 1` at the current timestamp.
///
/// The first observation has no return and is omitted. Missing data propagates
/// to the corresponding return; the previous observation is never skipped.
pub fn simple(
  prices: Series(Decimal),
  scale scale: Int,
  rounding rounding: RoundingMode,
) -> Result(Series(Decimal), ReturnError) {
  case scale < 0 {
    True -> Error(InvalidScale)
    False ->
      case series.to_list(prices) {
        [] | [_] -> {
          let assert Ok(empty) = series.new([])
          Ok(empty)
        }
        [previous, ..rest] -> calculate(previous, rest, scale, rounding, [])
      }
  }
}

fn calculate(
  previous: series.Point(Decimal),
  remaining: List(series.Point(Decimal)),
  scale: Int,
  rounding: RoundingMode,
  returns_reversed: List(series.Point(Decimal)),
) -> Result(Series(Decimal), ReturnError) {
  case remaining {
    [] -> {
      let assert Ok(value) = returns_reversed |> list.reverse |> series.new
      Ok(value)
    }
    [current, ..rest] ->
      case return_datum(previous, current, scale, rounding) {
        Error(error) -> Error(error)
        Ok(datum) ->
          calculate(current, rest, scale, rounding, [
            series.Point(current.at, datum),
            ..returns_reversed
          ])
      }
  }
}

fn return_datum(
  previous: series.Point(Decimal),
  current: series.Point(Decimal),
  scale: Int,
  rounding: RoundingMode,
) -> Result(Datum(Decimal), ReturnError) {
  let current_at = current.at
  case previous.datum, current.datum {
    _, series.Missing(reason) -> Ok(series.Missing(reason))
    series.Missing(reason), _ -> Ok(series.Missing(reason))
    series.Present(previous_value), series.Present(current_value) ->
      case decimal.compare(previous_value, decimal.zero()) {
        order.Eq -> Error(DivisionByZero(current_at))
        _ ->
          case decimal.divide(current_value, previous_value, scale, rounding) {
            Error(decimal.DivisionByZero) -> Error(DivisionByZero(current_at))
            Error(decimal.NegativeResultScale) -> Error(InvalidScale)
            Ok(relative) ->
              Ok(series.Present(decimal.subtract(relative, decimal_one())))
          }
      }
  }
}

fn decimal_one() -> Decimal {
  let assert Ok(one) = decimal.parse("1")
  one
}
