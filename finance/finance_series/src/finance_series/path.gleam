import finance_core/observation.{type MissingReason}
import finance_core/time.{type Instant}
import finance_series/series.{type Series}
import gleam/float
import gleam/list
import gleam/option.{type Option, None, Some}

pub type MissingPathPolicy {
  /// Emit a missing point but retain the last known path state.
  SkipMissingReturn
  /// Once a return is missing, all later path values remain missing.
  InvalidateAfterMissing
}

pub type PathError {
  InvalidInitialValue
  ReturnBelowMinusOne(at: Instant)
  NonPositiveWealth(at: Instant)
}

pub fn wealth_index(
  returns: Series(Float),
  initial_value initial_value: Float,
  missing missing_policy: MissingPathPolicy,
) -> Result(Series(Float), PathError) {
  case initial_value >. 0.0 {
    False -> Error(InvalidInitialValue)
    True ->
      build_wealth(
        series.to_list(returns),
        initial_value,
        missing_policy,
        None,
        [],
      )
  }
}

pub fn cumulative_return(
  returns: Series(Float),
  missing missing_policy: MissingPathPolicy,
) -> Result(Series(Float), PathError) {
  case wealth_index(returns, initial_value: 1.0, missing: missing_policy) {
    Error(error) -> Error(error)
    Ok(wealth) -> Ok(series.map(wealth, fn(value) { value -. 1.0 }))
  }
}

pub fn drawdown(
  wealth: Series(Float),
  missing missing_policy: MissingPathPolicy,
) -> Result(Series(Float), PathError) {
  build_drawdown(series.to_list(wealth), None, missing_policy, None, [])
}

fn build_wealth(
  points: List(series.Point(Float)),
  wealth: Float,
  policy: MissingPathPolicy,
  invalidated: Option(MissingReason),
  output_reversed: List(series.Point(Float)),
) -> Result(Series(Float), PathError) {
  case points {
    [] -> finish(output_reversed)
    [point, ..rest] ->
      case invalidated, point.datum {
        Some(reason), _ ->
          build_wealth(rest, wealth, policy, invalidated, [
            series.Point(point.at, series.Missing(reason)),
            ..output_reversed
          ])
        None, series.Missing(reason) -> {
          let next_invalidated = case policy {
            SkipMissingReturn -> None
            InvalidateAfterMissing -> Some(reason)
          }
          build_wealth(rest, wealth, policy, next_invalidated, [
            series.Point(point.at, series.Missing(reason)),
            ..output_reversed
          ])
        }
        None, series.Present(return_value) ->
          case return_value <. -1.0 {
            True -> Error(ReturnBelowMinusOne(point.at))
            False -> {
              let next = wealth *. { 1.0 +. return_value }
              build_wealth(rest, next, policy, None, [
                series.Point(point.at, series.Present(next)),
                ..output_reversed
              ])
            }
          }
      }
  }
}

fn build_drawdown(
  points: List(series.Point(Float)),
  peak: Option(Float),
  policy: MissingPathPolicy,
  invalidated: Option(MissingReason),
  output_reversed: List(series.Point(Float)),
) -> Result(Series(Float), PathError) {
  case points {
    [] -> finish(output_reversed)
    [point, ..rest] ->
      case invalidated, point.datum {
        Some(reason), _ ->
          build_drawdown(rest, peak, policy, invalidated, [
            series.Point(point.at, series.Missing(reason)),
            ..output_reversed
          ])
        None, series.Missing(reason) -> {
          let next_invalidated = case policy {
            SkipMissingReturn -> None
            InvalidateAfterMissing -> Some(reason)
          }
          build_drawdown(rest, peak, policy, next_invalidated, [
            series.Point(point.at, series.Missing(reason)),
            ..output_reversed
          ])
        }
        None, series.Present(value) ->
          case value >. 0.0 {
            False -> Error(NonPositiveWealth(point.at))
            True -> {
              let next_peak = case peak {
                None -> value
                Some(peak) -> float.max(peak, value)
              }
              let decline = { value /. next_peak } -. 1.0
              build_drawdown(rest, Some(next_peak), policy, None, [
                series.Point(point.at, series.Present(decline)),
                ..output_reversed
              ])
            }
          }
      }
  }
}

fn finish(
  output_reversed: List(series.Point(Float)),
) -> Result(Series(Float), PathError) {
  let assert Ok(output) = output_reversed |> list.reverse |> series.new
  Ok(output)
}
