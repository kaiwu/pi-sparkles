import finance_math/error.{type MetricError}
import finance_math/finite
import finance_math/statistics.{type Estimator}
import gleam/float
import gleam/int
import gleam/list
import gleam/order
import gleam/result

/// Mean loss across the worst empirical tail. Tail size is
/// `ceil((1 - confidence) * n)` with a minimum of one observation.
pub fn historical_expected_shortfall(
  returns: List(Float),
  confidence: Float,
) -> Result(Float, MetricError) {
  use returns <- result.try(finite.inputs(returns))
  use confidence <- result.try(finite.input(confidence))
  case returns, confidence >. 0.0 && confidence <. 1.0 {
    [], _ -> Error(error.EmptyInput)
    _, False -> Error(error.InvalidConfidence)
    _, True -> {
      let tail_count =
        { 1.0 -. confidence } *. int.to_float(list.length(returns))
        |> float.ceiling
        |> float.round
        |> int.max(1)
      let tail =
        returns
        |> list.map(fn(value) { 0.0 -. value })
        |> list.sort(by: order.reverse(float.compare))
        |> list.take(tail_count)
      finite.output(float.sum(tail) /. int.to_float(list.length(tail)))
    }
  }
}

pub fn downside_deviation(
  returns: List(Float),
  minimum_acceptable_return: Float,
  estimator: Estimator,
) -> Result(Float, MetricError) {
  use returns <- result.try(finite.inputs(returns))
  use minimum_acceptable_return <- result.try(finite.input(
    minimum_acceptable_return,
  ))
  use denominator <- result.try(sample_denominator(returns, estimator))
  let downside_squared =
    returns
    |> list.map(fn(value) {
      let shortfall = float.min(value -. minimum_acceptable_return, 0.0)
      shortfall *. shortfall
    })
    |> float.sum
  downside_squared /. int.to_float(denominator)
  |> float.square_root
  |> result.map_error(fn(_) { error.DomainError })
  |> result.map(finite.output)
  |> result.flatten
}

pub fn sharpe_ratio(
  returns: List(Float),
  risk_free_per_period: Float,
  periods_per_year: Int,
  estimator: Estimator,
) -> Result(Float, MetricError) {
  use returns <- result.try(finite.inputs(returns))
  use risk_free_per_period <- result.try(finite.input(risk_free_per_period))
  use excess <- result.try(excess_returns(returns, risk_free_per_period))
  use average <- result.try(statistics.mean(excess))
  use deviation <- result.try(statistics.standard_deviation(excess, estimator))
  annualized_ratio(average, deviation, periods_per_year)
}

pub fn sortino_ratio(
  returns: List(Float),
  minimum_acceptable_return: Float,
  periods_per_year: Int,
  estimator: Estimator,
) -> Result(Float, MetricError) {
  use returns <- result.try(finite.inputs(returns))
  use minimum_acceptable_return <- result.try(finite.input(
    minimum_acceptable_return,
  ))
  use average <- result.try(statistics.mean(returns))
  use downside <- result.try(downside_deviation(
    returns,
    minimum_acceptable_return,
    estimator,
  ))
  annualized_ratio(
    average -. minimum_acceptable_return,
    downside,
    periods_per_year,
  )
}

pub fn omega_ratio(
  returns: List(Float),
  threshold: Float,
) -> Result(Float, MetricError) {
  use returns <- result.try(finite.inputs(returns))
  use threshold <- result.try(finite.input(threshold))
  case returns {
    [] -> Error(error.EmptyInput)
    _ -> {
      let gains =
        returns
        |> list.map(fn(value) { float.max(value -. threshold, 0.0) })
        |> float.sum
      let losses =
        returns
        |> list.map(fn(value) { float.max(threshold -. value, 0.0) })
        |> float.sum
      case losses == 0.0 {
        True -> Error(error.DivisionByZero)
        False -> finite.output(gains /. losses)
      }
    }
  }
}

fn excess_returns(
  returns: List(Float),
  risk_free: Float,
) -> Result(List(Float), MetricError) {
  case returns {
    [] -> Error(error.EmptyInput)
    _ -> Ok(list.map(returns, fn(value) { value -. risk_free }))
  }
}

fn annualized_ratio(
  average: Float,
  deviation: Float,
  periods_per_year: Int,
) -> Result(Float, MetricError) {
  case deviation == 0.0, periods_per_year > 0 {
    True, _ -> Error(error.ZeroVariance)
    _, False -> Error(error.InvalidPeriod)
    False, True -> {
      let assert Ok(root) =
        periods_per_year |> int.to_float |> float.square_root
      finite.output(average /. deviation *. root)
    }
  }
}

fn sample_denominator(
  values: List(Float),
  estimator: Estimator,
) -> Result(Int, MetricError) {
  case estimator, list.length(values) {
    _, 0 -> Error(error.EmptyInput)
    statistics.Sample, 1 ->
      Error(error.InsufficientData(required: 2, actual: 1))
    statistics.Population, count -> Ok(count)
    statistics.Sample, count -> Ok(count - 1)
  }
}
