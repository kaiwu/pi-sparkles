import finance_math/error.{type MetricError}
import gleam/float
import gleam/int
import gleam/list
import gleam/result

/// Population uses `n`; Sample uses Bessel's correction, `n - 1`.
pub type Estimator {
  Population
  Sample
}

pub fn mean(values: List(Float)) -> Result(Float, MetricError) {
  case values {
    [] -> Error(error.EmptyInput)
    _ -> Ok(float.sum(values) /. int.to_float(list.length(values)))
  }
}

pub fn variance(
  values: List(Float),
  estimator: Estimator,
) -> Result(Float, MetricError) {
  let count = list.length(values)
  use average <- result.try(mean(values))
  use denominator <- result.try(estimator_denominator(estimator, count))
  let squared_deviations =
    values
    |> list.map(fn(value) {
      let deviation = value -. average
      deviation *. deviation
    })
    |> float.sum
  Ok(squared_deviations /. int.to_float(denominator))
}

pub fn standard_deviation(
  values: List(Float),
  estimator: Estimator,
) -> Result(Float, MetricError) {
  use variance <- result.try(variance(values, estimator))
  variance
  |> float.square_root
  |> result.map_error(fn(_) { error.DomainError })
}

pub fn covariance(
  left: List(Float),
  right: List(Float),
  estimator: Estimator,
) -> Result(Float, MetricError) {
  let left_count = list.length(left)
  let right_count = list.length(right)
  case left_count == right_count {
    False -> Error(error.LengthMismatch(left_count, right_count))
    True -> {
      use left_mean <- result.try(mean(left))
      use right_mean <- result.try(mean(right))
      use denominator <- result.try(estimator_denominator(estimator, left_count))
      let products = deviation_products(left, right, left_mean, right_mean, [])
      Ok(float.sum(products) /. int.to_float(denominator))
    }
  }
}

pub fn correlation(
  left: List(Float),
  right: List(Float),
  estimator: Estimator,
) -> Result(Float, MetricError) {
  use covariance <- result.try(covariance(left, right, estimator))
  use left_deviation <- result.try(standard_deviation(left, estimator))
  use right_deviation <- result.try(standard_deviation(right, estimator))
  case left_deviation == 0.0 || right_deviation == 0.0 {
    True -> Error(error.ZeroVariance)
    False -> Ok(covariance /. { left_deviation *. right_deviation })
  }
}

pub fn beta(
  asset_returns: List(Float),
  benchmark_returns: List(Float),
  estimator: Estimator,
) -> Result(Float, MetricError) {
  use covariance <- result.try(covariance(
    asset_returns,
    benchmark_returns,
    estimator,
  ))
  use benchmark_variance <- result.try(variance(benchmark_returns, estimator))
  case benchmark_variance == 0.0 {
    True -> Error(error.ZeroVariance)
    False -> Ok(covariance /. benchmark_variance)
  }
}

pub fn simple_returns(prices: List(Float)) -> Result(List(Float), MetricError) {
  case prices {
    [] -> Error(error.EmptyInput)
    [_] -> Error(error.InsufficientData(required: 2, actual: 1))
    [first, ..rest] -> simple_returns_loop(first, rest, [])
  }
}

pub fn annualized_volatility(
  returns: List(Float),
  periods_per_year: Int,
  estimator: Estimator,
) -> Result(Float, MetricError) {
  case periods_per_year > 0 {
    False -> Error(error.InvalidPeriod)
    True -> {
      use deviation <- result.try(standard_deviation(returns, estimator))
      let assert Ok(root) =
        periods_per_year |> int.to_float |> float.square_root
      Ok(deviation *. root)
    }
  }
}

/// Historical value-at-risk as a positive loss at the nearest-rank quantile.
pub fn historical_value_at_risk(
  returns: List(Float),
  confidence: Float,
) -> Result(Float, MetricError) {
  case returns, confidence >. 0.0 && confidence <. 1.0 {
    [], _ -> Error(error.EmptyInput)
    _, False -> Error(error.InvalidConfidence)
    _, True -> {
      let losses =
        returns
        |> list.map(fn(value) { 0.0 -. value })
        |> list.sort(by: float.compare)
      let rank =
        confidence *. int.to_float(list.length(losses))
        |> float.ceiling
        |> float.round
      case list.drop(losses, rank - 1) {
        [loss, ..] -> Ok(loss)
        [] -> Error(error.DomainError)
      }
    }
  }
}

/// Maximum peak-to-trough decline, returned as a non-negative fraction.
pub fn maximum_drawdown(prices: List(Float)) -> Result(Float, MetricError) {
  case prices {
    [] -> Error(error.EmptyInput)
    [first, ..] if first <=. 0.0 -> Error(error.DomainError)
    [first, ..rest] -> maximum_drawdown_loop(rest, first, 0.0)
  }
}

/// Compound annual growth rate for a positive beginning and ending value.
pub fn compound_growth_rate(
  beginning: Float,
  ending: Float,
  periods: Float,
) -> Result(Float, MetricError) {
  case beginning >. 0.0 && ending >=. 0.0, periods >. 0.0 {
    False, _ -> Error(error.DomainError)
    _, False -> Error(error.InvalidPeriod)
    True, True ->
      ending /. beginning
      |> float.power(of: 1.0 /. periods)
      |> result.map(fn(value) { value -. 1.0 })
      |> result.map_error(fn(_) { error.DomainError })
  }
}

fn estimator_denominator(
  estimator: Estimator,
  count: Int,
) -> Result(Int, MetricError) {
  case estimator, count {
    _, 0 -> Error(error.EmptyInput)
    Sample, 1 -> Error(error.InsufficientData(required: 2, actual: 1))
    Population, _ -> Ok(count)
    Sample, _ -> Ok(count - 1)
  }
}

fn deviation_products(
  left: List(Float),
  right: List(Float),
  left_mean: Float,
  right_mean: Float,
  products: List(Float),
) -> List(Float) {
  case left, right {
    [], [] -> list.reverse(products)
    [left, ..left_rest], [right, ..right_rest] ->
      deviation_products(left_rest, right_rest, left_mean, right_mean, [
        { left -. left_mean } *. { right -. right_mean },
        ..products
      ])
    _, _ -> list.reverse(products)
  }
}

fn simple_returns_loop(
  previous: Float,
  remaining: List(Float),
  returns: List(Float),
) -> Result(List(Float), MetricError) {
  case remaining {
    [] -> Ok(list.reverse(returns))
    [current, ..rest] ->
      case previous == 0.0 {
        True -> Error(error.DivisionByZero)
        False ->
          simple_returns_loop(current, rest, [
            current /. previous -. 1.0,
            ..returns
          ])
      }
  }
}

fn maximum_drawdown_loop(
  prices: List(Float),
  peak: Float,
  maximum: Float,
) -> Result(Float, MetricError) {
  case prices {
    [] -> Ok(maximum)
    [price, ..rest] ->
      case price <=. 0.0 {
        True -> Error(error.DomainError)
        False -> {
          let next_peak = case price >. peak {
            True -> price
            False -> peak
          }
          let drawdown = { next_peak -. price } /. next_peak
          maximum_drawdown_loop(rest, next_peak, float.max(maximum, drawdown))
        }
      }
  }
}
