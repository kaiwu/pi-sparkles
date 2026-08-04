import finance_core/decimal.{type Decimal}
import finance_core/observation.{type MissingReason}
import finance_core/time.{type Instant}
import finance_series/path.{type MissingPathPolicy}
import finance_series/series.{type Series}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{Eq, Lt}

pub type ExactPathError {
  InvalidInitialValue
  ReturnBelowMinusOne(at: Instant)
}

pub fn wealth_index(
  returns: Series(Decimal),
  initial_value initial_value: Decimal,
  missing missing_policy: MissingPathPolicy,
) -> Result(Series(Decimal), ExactPathError) {
  case decimal.compare(initial_value, decimal.zero()) {
    Lt | Eq -> Error(InvalidInitialValue)
    _ -> build(series.to_list(returns), initial_value, missing_policy, None, [])
  }
}

pub fn cumulative_return(
  returns: Series(Decimal),
  missing missing_policy: MissingPathPolicy,
) -> Result(Series(Decimal), ExactPathError) {
  use wealth <- result_try(wealth_index(
    returns,
    initial_value: one(),
    missing: missing_policy,
  ))
  Ok(series.map(wealth, fn(value) { decimal.subtract(value, one()) }))
}

fn build(
  points: List(series.Point(Decimal)),
  wealth: Decimal,
  policy: MissingPathPolicy,
  invalidated: Option(MissingReason),
  reversed: List(series.Point(Decimal)),
) -> Result(Series(Decimal), ExactPathError) {
  case points {
    [] -> {
      let assert Ok(value) = reversed |> list.reverse |> series.new
      Ok(value)
    }
    [point, ..rest] ->
      case invalidated, point.datum {
        Some(reason), _ ->
          build(rest, wealth, policy, invalidated, [
            series.Point(point.at, series.Missing(reason)),
            ..reversed
          ])
        None, series.Missing(reason) -> {
          let next = case policy {
            path.SkipMissingReturn -> None
            path.InvalidateAfterMissing -> Some(reason)
          }
          build(rest, wealth, policy, next, [
            series.Point(point.at, series.Missing(reason)),
            ..reversed
          ])
        }
        None, series.Present(return_value) -> {
          let relative = decimal.add(one(), return_value)
          case decimal.compare(relative, decimal.zero()) {
            Lt -> Error(ReturnBelowMinusOne(point.at))
            _ -> {
              let next = decimal.multiply(wealth, relative)
              build(rest, next, policy, None, [
                series.Point(point.at, series.Present(next)),
                ..reversed
              ])
            }
          }
        }
      }
  }
}

fn one() -> Decimal {
  let assert Ok(value) = decimal.parse("1")
  value
}

fn result_try(
  result: Result(value, error),
  next: fn(value) -> Result(next, error),
) -> Result(next, error) {
  case result {
    Ok(value) -> next(value)
    Error(error) -> Error(error)
  }
}
