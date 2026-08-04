import finance_core/time.{type Instant}
import finance_math/error.{type MetricError}
import finance_math/finite
import finance_math/root
import gleam/float
import gleam/int
import gleam/list
import gleam/result

pub type TimedCashFlow {
  TimedCashFlow(amount: Float, at: Instant)
}

/// Net present value with the first cash flow at period zero.
pub fn net_present_value(
  rate: Float,
  cash_flows: List(Float),
) -> Result(Float, MetricError) {
  use rate <- result.try(finite.input(rate))
  use cash_flows <- result.try(finite.inputs(cash_flows))
  case cash_flows, rate >. -1.0 {
    [], _ -> Error(error.EmptyInput)
    _, False -> Error(error.DomainError)
    _, True -> discounted_sum(rate, cash_flows, 0, 0.0)
  }
}

/// IRR using an explicit bracket, tolerance, and finite iteration budget.
pub fn internal_rate_of_return(
  cash_flows: List(Float),
  lower lower: Float,
  upper upper: Float,
  tolerance tolerance: Float,
  maximum_iterations maximum_iterations: Int,
) -> Result(Float, MetricError) {
  use lower <- result.try(finite.input(lower))
  use upper <- result.try(finite.input(upper))
  use tolerance <- result.try(finite.input(tolerance))
  use _ <- result.try(finite.inputs(cash_flows))
  use _ <- result.try(require_sign_change(cash_flows))
  case lower >. -1.0 {
    False -> Error(error.InvalidBounds)
    True ->
      root.bisection(
        fn(rate) { net_present_value(rate, cash_flows) },
        lower,
        upper,
        tolerance,
        maximum_iterations,
      )
  }
}

/// Date-aware NPV using an explicit day-count basis such as `365.0` or
/// `365.25`. Cash flows must be ordered and the first establishes time zero.
pub fn dated_net_present_value(
  rate: Float,
  cash_flows: List(TimedCashFlow),
  days_per_year: Float,
) -> Result(Float, MetricError) {
  use rate <- result.try(finite.input(rate))
  use days_per_year <- result.try(finite.input(days_per_year))
  use _ <- result.try(
    cash_flows
    |> list.map(fn(flow) { flow.amount })
    |> finite.inputs,
  )
  case cash_flows, rate >. -1.0, days_per_year >. 0.0 {
    [], _, _ -> Error(error.EmptyInput)
    _, False, _ -> Error(error.DomainError)
    _, _, False -> Error(error.InvalidPeriod)
    [first, ..], True, True ->
      dated_discounted_sum(rate, cash_flows, first.at, days_per_year, 0.0)
  }
}

pub fn dated_internal_rate_of_return(
  cash_flows: List(TimedCashFlow),
  days_per_year: Float,
  lower lower: Float,
  upper upper: Float,
  tolerance tolerance: Float,
  maximum_iterations maximum_iterations: Int,
) -> Result(Float, MetricError) {
  use days_per_year <- result.try(finite.input(days_per_year))
  use lower <- result.try(finite.input(lower))
  use upper <- result.try(finite.input(upper))
  use tolerance <- result.try(finite.input(tolerance))
  use _ <- result.try(
    cash_flows
    |> list.map(fn(flow) { flow.amount })
    |> finite.inputs,
  )
  use _ <- result.try(
    require_sign_change(list.map(cash_flows, fn(flow) { flow.amount })),
  )
  case lower >. -1.0 {
    False -> Error(error.InvalidBounds)
    True ->
      root.bisection(
        fn(rate) { dated_net_present_value(rate, cash_flows, days_per_year) },
        lower,
        upper,
        tolerance,
        maximum_iterations,
      )
  }
}

fn discounted_sum(
  rate: Float,
  cash_flows: List(Float),
  period: Int,
  total: Float,
) -> Result(Float, MetricError) {
  case cash_flows {
    [] -> finite.output(total)
    [amount, ..rest] -> {
      use discount <- result.try(
        float.power(1.0 +. rate, of: int.to_float(period))
        |> result.map_error(fn(_) { error.DomainError }),
      )
      discounted_sum(rate, rest, period + 1, total +. amount /. discount)
    }
  }
}

fn dated_discounted_sum(
  rate: Float,
  cash_flows: List(TimedCashFlow),
  first_at: Instant,
  days_per_year: Float,
  total: Float,
) -> Result(Float, MetricError) {
  case cash_flows {
    [] -> finite.output(total)
    [TimedCashFlow(amount, at), ..rest] -> {
      let elapsed_milliseconds =
        time.unix_milliseconds(at) - time.unix_milliseconds(first_at)
      case elapsed_milliseconds < 0 {
        True -> Error(error.InvalidPeriod)
        False -> {
          let years =
            int.to_float(elapsed_milliseconds) /. 86_400_000.0 /. days_per_year
          use discount <- result.try(
            float.power(1.0 +. rate, of: years)
            |> result.map_error(fn(_) { error.DomainError }),
          )
          dated_discounted_sum(
            rate,
            rest,
            first_at,
            days_per_year,
            total +. amount /. discount,
          )
        }
      }
    }
  }
}

fn require_sign_change(values: List(Float)) -> Result(Nil, MetricError) {
  case values {
    [] -> Error(error.EmptyInput)
    _ -> {
      let has_positive = list.any(values, fn(value) { value >. 0.0 })
      let has_negative = list.any(values, fn(value) { value <. 0.0 })
      case has_positive && has_negative {
        True -> Ok(Nil)
        False -> Error(error.NoSignChange)
      }
    }
  }
}
