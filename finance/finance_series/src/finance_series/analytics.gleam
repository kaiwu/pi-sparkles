import finance_core/time.{type Instant}
import finance_math/error.{type MetricError}
import finance_math/statistics.{type Estimator}
import finance_series/alignment.{type Aligned}
import finance_series/series.{type Series}
import gleam/int
import gleam/list
import gleam/option.{None, Some}

pub type TimelinePolicy {
  ExactTimeline
  Intersection
}

pub type MissingPolicy {
  RejectMissing
  DropMissing
}

pub type AnalyticsError {
  TimelineMismatch(at: Instant)
  MissingValue(at: Instant)
  NoComparableObservations
  MathFailure(error: MetricError)
  InvalidAnnualization
}

pub fn paired_values(
  left: Series(Float),
  right: Series(Float),
  timeline timeline: TimelinePolicy,
  missing missing: MissingPolicy,
) -> Result(#(List(Float), List(Float)), AnalyticsError) {
  let join = case timeline {
    ExactTimeline -> alignment.Full
    Intersection -> alignment.Inner
  }
  collect_pairs(
    alignment.align(left, right, join: join),
    timeline,
    missing,
    [],
    [],
  )
}

pub fn spread(
  left: Series(Float),
  right: Series(Float),
  timeline timeline: TimelinePolicy,
  missing missing: MissingPolicy,
) -> Result(Series(Float), AnalyticsError) {
  let join = case timeline {
    ExactTimeline -> alignment.Full
    Intersection -> alignment.Inner
  }
  collect_spread(
    alignment.align(left, right, join: join),
    timeline,
    missing,
    [],
  )
}

pub fn beta(
  asset_returns: Series(Float),
  benchmark_returns: Series(Float),
  timeline timeline: TimelinePolicy,
  missing missing: MissingPolicy,
  estimator estimator: Estimator,
) -> Result(Float, AnalyticsError) {
  case paired_values(asset_returns, benchmark_returns, timeline, missing) {
    Error(error) -> Error(error)
    Ok(#(asset, benchmark)) ->
      statistics.beta(asset, benchmark, estimator)
      |> map_math_error
  }
}

pub fn correlation(
  left: Series(Float),
  right: Series(Float),
  timeline timeline: TimelinePolicy,
  missing missing: MissingPolicy,
  estimator estimator: Estimator,
) -> Result(Float, AnalyticsError) {
  case paired_values(left, right, timeline, missing) {
    Error(error) -> Error(error)
    Ok(#(left, right)) ->
      statistics.correlation(left, right, estimator)
      |> map_math_error
  }
}

pub fn tracking_error(
  portfolio_returns: Series(Float),
  benchmark_returns: Series(Float),
  periods_per_year: Int,
  timeline timeline: TimelinePolicy,
  missing missing: MissingPolicy,
  estimator estimator: Estimator,
) -> Result(Float, AnalyticsError) {
  case periods_per_year > 0 {
    False -> Error(InvalidAnnualization)
    True ->
      case spread(portfolio_returns, benchmark_returns, timeline, missing) {
        Error(error) -> Error(error)
        Ok(active) ->
          active
          |> series.present_values
          |> list.map(fn(pair) { pair.1 })
          |> statistics.annualized_volatility(periods_per_year, estimator)
          |> map_math_error
      }
  }
}

pub fn information_ratio(
  portfolio_returns: Series(Float),
  benchmark_returns: Series(Float),
  periods_per_year: Int,
  timeline timeline: TimelinePolicy,
  missing missing: MissingPolicy,
  estimator estimator: Estimator,
) -> Result(Float, AnalyticsError) {
  case spread(portfolio_returns, benchmark_returns, timeline, missing) {
    Error(error) -> Error(error)
    Ok(active) -> {
      let values =
        active |> series.present_values |> list.map(fn(pair) { pair.1 })
      case
        statistics.mean(values),
        tracking_error(
          portfolio_returns,
          benchmark_returns,
          periods_per_year,
          timeline,
          missing,
          estimator,
        )
      {
        Error(error), _ -> Error(MathFailure(error))
        _, Error(error) -> Error(error)
        Ok(_), Ok(0.0) -> Error(MathFailure(error.ZeroVariance))
        Ok(average), Ok(tracking_error) ->
          Ok(average *. int.to_float(periods_per_year) /. tracking_error)
      }
    }
  }
}

fn collect_pairs(
  aligned: List(Aligned(Float, Float)),
  timeline: TimelinePolicy,
  missing: MissingPolicy,
  left_reversed: List(Float),
  right_reversed: List(Float),
) -> Result(#(List(Float), List(Float)), AnalyticsError) {
  case aligned {
    [] ->
      case left_reversed {
        [] -> Error(NoComparableObservations)
        _ -> Ok(#(list.reverse(left_reversed), list.reverse(right_reversed)))
      }
    [alignment.Aligned(at, left, right), ..rest] ->
      case left, right {
        None, _ | _, None ->
          case timeline {
            ExactTimeline -> Error(TimelineMismatch(at))
            Intersection ->
              collect_pairs(
                rest,
                timeline,
                missing,
                left_reversed,
                right_reversed,
              )
          }
        Some(series.Present(left)), Some(series.Present(right)) ->
          collect_pairs(rest, timeline, missing, [left, ..left_reversed], [
            right,
            ..right_reversed
          ])
        _, _ ->
          case missing {
            RejectMissing -> Error(MissingValue(at))
            DropMissing ->
              collect_pairs(
                rest,
                timeline,
                missing,
                left_reversed,
                right_reversed,
              )
          }
      }
  }
}

fn collect_spread(
  aligned: List(Aligned(Float, Float)),
  timeline: TimelinePolicy,
  missing: MissingPolicy,
  points_reversed: List(series.Point(Float)),
) -> Result(Series(Float), AnalyticsError) {
  case aligned {
    [] -> {
      let assert Ok(result) = points_reversed |> list.reverse |> series.new
      case series.is_empty(result) {
        True -> Error(NoComparableObservations)
        False -> Ok(result)
      }
    }
    [alignment.Aligned(at, left, right), ..rest] ->
      case left, right {
        None, _ | _, None ->
          case timeline {
            ExactTimeline -> Error(TimelineMismatch(at))
            Intersection ->
              collect_spread(rest, timeline, missing, points_reversed)
          }
        Some(series.Present(left)), Some(series.Present(right)) ->
          collect_spread(rest, timeline, missing, [
            series.Point(at, series.Present(left -. right)),
            ..points_reversed
          ])
        _, _ ->
          case missing {
            RejectMissing -> Error(MissingValue(at))
            DropMissing ->
              collect_spread(rest, timeline, missing, points_reversed)
          }
      }
  }
}

fn map_math_error(
  result: Result(value, MetricError),
) -> Result(value, AnalyticsError) {
  case result {
    Ok(value) -> Ok(value)
    Error(error) -> Error(MathFailure(error))
  }
}
