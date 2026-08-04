import finance_math/error.{type MetricError}
import finance_math/statistics.{type Estimator}
import gleam/float
import gleam/list
import gleam/result

/// Non-negative reliability weights. They need not already sum to one.
pub fn mean(
  values: List(Float),
  weights: List(Float),
) -> Result(Float, MetricError) {
  use total_weight <- result.try(validate(values, weights))
  Ok(weighted_sum(values, weights, 0.0) /. total_weight)
}

pub fn variance(
  values: List(Float),
  weights: List(Float),
  estimator: Estimator,
) -> Result(Float, MetricError) {
  use total_weight <- result.try(validate(values, weights))
  use average <- result.try(mean(values, weights))
  use denominator <- result.try(denominator(weights, total_weight, estimator))
  Ok(weighted_squared_deviations(values, weights, average, 0.0) /. denominator)
}

pub fn covariance(
  left: List(Float),
  right: List(Float),
  weights: List(Float),
  estimator: Estimator,
) -> Result(Float, MetricError) {
  let left_count = list.length(left)
  let right_count = list.length(right)
  case left_count == right_count {
    False -> Error(error.LengthMismatch(left_count, right_count))
    True -> {
      use total_weight <- result.try(validate(left, weights))
      use left_mean <- result.try(mean(left, weights))
      use right_mean <- result.try(mean(right, weights))
      use denominator <- result.try(denominator(
        weights,
        total_weight,
        estimator,
      ))
      Ok(
        weighted_products(left, right, weights, left_mean, right_mean, 0.0)
        /. denominator,
      )
    }
  }
}

pub fn beta(
  asset_returns: List(Float),
  benchmark_returns: List(Float),
  weights: List(Float),
  estimator: Estimator,
) -> Result(Float, MetricError) {
  use covariance <- result.try(covariance(
    asset_returns,
    benchmark_returns,
    weights,
    estimator,
  ))
  use variance <- result.try(variance(benchmark_returns, weights, estimator))
  case variance == 0.0 {
    True -> Error(error.ZeroVariance)
    False -> Ok(covariance /. variance)
  }
}

fn validate(
  values: List(Float),
  weights: List(Float),
) -> Result(Float, MetricError) {
  let value_count = list.length(values)
  let weight_count = list.length(weights)
  case
    values,
    value_count == weight_count,
    list.any(weights, fn(weight) { weight <. 0.0 })
  {
    [], _, _ -> Error(error.EmptyInput)
    _, False, _ -> Error(error.LengthMismatch(value_count, weight_count))
    _, _, True -> Error(error.InvalidWeight)
    _, True, False -> {
      let total = float.sum(weights)
      case total >. 0.0 {
        True -> Ok(total)
        False -> Error(error.ZeroWeight)
      }
    }
  }
}

fn denominator(
  weights: List(Float),
  total: Float,
  estimator: Estimator,
) -> Result(Float, MetricError) {
  case estimator {
    statistics.Population -> Ok(total)
    statistics.Sample -> {
      let squared =
        weights |> list.map(fn(weight) { weight *. weight }) |> float.sum
      let corrected = total -. squared /. total
      case corrected >. 0.0 {
        True -> Ok(corrected)
        False -> Error(error.InsufficientData(required: 2, actual: 1))
      }
    }
  }
}

fn weighted_sum(
  values: List(Float),
  weights: List(Float),
  total: Float,
) -> Float {
  case values, weights {
    [], [] -> total
    [value, ..values], [weight, ..weights] ->
      weighted_sum(values, weights, total +. value *. weight)
    _, _ -> total
  }
}

fn weighted_squared_deviations(
  values: List(Float),
  weights: List(Float),
  average: Float,
  total: Float,
) -> Float {
  case values, weights {
    [], [] -> total
    [value, ..values], [weight, ..weights] -> {
      let deviation = value -. average
      weighted_squared_deviations(
        values,
        weights,
        average,
        total +. weight *. deviation *. deviation,
      )
    }
    _, _ -> total
  }
}

fn weighted_products(
  left: List(Float),
  right: List(Float),
  weights: List(Float),
  left_mean: Float,
  right_mean: Float,
  total: Float,
) -> Float {
  case left, right, weights {
    [], [], [] -> total
    [left, ..lefts], [right, ..rights], [weight, ..weights] ->
      weighted_products(
        lefts,
        rights,
        weights,
        left_mean,
        right_mean,
        total +. weight *. { left -. left_mean } *. { right -. right_mean },
      )
    _, _, _ -> total
  }
}
