import finance_math/error.{type MetricError}
import gleam/float
import gleam/int
import gleam/list
import gleam/result

pub type CashFlow {
  CashFlow(amount: Float, years: Float)
}

pub type Compounding {
  Periodic(periods_per_year: Int)
  Continuous
}

pub type Sensitivity {
  Sensitivity(
    present_value: Float,
    macaulay_duration: Float,
    modified_duration: Float,
    convexity: Float,
    dv01: Float,
  )
}

pub fn present_value(
  cash_flows: List(CashFlow),
  yield: Float,
  compounding: Compounding,
) -> Result(Float, MetricError) {
  use _ <- result.try(validate(cash_flows, yield, compounding))
  cash_flows
  |> list.map(fn(flow) { discounted(flow, yield, compounding) })
  |> list.try_map(fn(value) { value })
  |> result.map(float.sum)
}

/// Price sensitivity to a parallel change in the annual yield argument.
pub fn sensitivity(
  cash_flows: List(CashFlow),
  yield: Float,
  compounding: Compounding,
) -> Result(Sensitivity, MetricError) {
  use _ <- result.try(validate(cash_flows, yield, compounding))
  use discounted <- result.try(
    list.try_map(cash_flows, fn(flow) {
      use value <- result.try(discounted(flow, yield, compounding))
      Ok(#(flow, value))
    }),
  )
  let price = discounted |> list.map(fn(item) { item.1 }) |> float.sum
  case price == 0.0 {
    True -> Error(error.DivisionByZero)
    False -> {
      let weighted_time =
        discounted
        |> list.map(fn(item) { item.0.years *. item.1 })
        |> float.sum
      let macaulay = weighted_time /. price
      let #(modified, convexity) = case compounding {
        Continuous -> #(
          macaulay,
          discounted
            |> list.map(fn(item) { item.0.years *. item.0.years *. item.1 })
            |> float.sum
            |> fn(value) { value /. price },
        )
        Periodic(frequency) -> {
          let frequency_float = int.to_float(frequency)
          let base = 1.0 +. yield /. frequency_float
          #(
            macaulay /. base,
            discounted
              |> list.map(fn(item) {
                item.0.years
                *. { item.0.years +. 1.0 /. frequency_float }
                *. item.1
              })
              |> float.sum
              |> fn(value) { value /. price /. { base *. base } },
          )
        }
      }
      Ok(Sensitivity(
        price,
        macaulay,
        modified,
        convexity,
        float.absolute_value(modified *. price *. 0.0001),
      ))
    }
  }
}

fn validate(
  cash_flows: List(CashFlow),
  yield: Float,
  compounding: Compounding,
) -> Result(Nil, MetricError) {
  case cash_flows {
    [] -> Error(error.EmptyInput)
    _ ->
      case list.any(cash_flows, fn(flow) { flow.years <. 0.0 }) {
        True -> Error(error.InvalidPeriod)
        False ->
          case compounding {
            Periodic(frequency) if frequency <= 0 ->
              Error(error.InvalidCompounding)
            Periodic(frequency) ->
              case 1.0 +. yield /. int.to_float(frequency) >. 0.0 {
                True -> Ok(Nil)
                False -> Error(error.DomainError)
              }
            Continuous -> Ok(Nil)
          }
      }
  }
}

fn discounted(
  flow: CashFlow,
  yield: Float,
  compounding: Compounding,
) -> Result(Float, MetricError) {
  case compounding {
    Continuous ->
      Ok(flow.amount *. float.exponential(0.0 -. yield *. flow.years))
    Periodic(frequency) -> {
      let frequency_float = int.to_float(frequency)
      use discount <- result.try(
        float.power(
          1.0 +. yield /. frequency_float,
          of: frequency_float *. flow.years,
        )
        |> result.map_error(fn(_) { error.DomainError }),
      )
      Ok(flow.amount /. discount)
    }
  }
}
