import finance_math/error.{type MetricError}
import finance_math/finite
import gleam/float
import gleam/result

/// Deterministic bounded bisection for continuous scalar functions.
pub fn bisection(
  function: fn(Float) -> Result(Float, MetricError),
  lower lower: Float,
  upper upper: Float,
  tolerance tolerance: Float,
  maximum_iterations maximum_iterations: Int,
) -> Result(Float, MetricError) {
  use lower <- result.try(finite.input(lower))
  use upper <- result.try(finite.input(upper))
  use tolerance <- result.try(finite.input(tolerance))
  case lower <. upper, tolerance >. 0.0, maximum_iterations > 0 {
    False, _, _ -> Error(error.InvalidBounds)
    _, False, _ -> Error(error.InvalidTolerance)
    _, _, False -> Error(error.InvalidIterationLimit)
    True, True, True -> {
      use lower_value <- result.try(
        function(lower) |> result.map(finite.output) |> result.flatten,
      )
      use upper_value <- result.try(
        function(upper) |> result.map(finite.output) |> result.flatten,
      )
      case lower_value == 0.0, upper_value == 0.0 {
        True, _ -> Ok(lower)
        _, True -> Ok(upper)
        False, False ->
          case same_sign(lower_value, upper_value) {
            True -> Error(error.RootNotBracketed)
            False ->
              bisect(
                function,
                lower,
                upper,
                lower_value,
                tolerance,
                maximum_iterations,
                0,
              )
          }
      }
    }
  }
}

fn bisect(
  function: fn(Float) -> Result(Float, MetricError),
  lower: Float,
  upper: Float,
  lower_value: Float,
  tolerance: Float,
  maximum_iterations: Int,
  completed: Int,
) -> Result(Float, MetricError) {
  case completed >= maximum_iterations {
    True -> Error(error.DidNotConverge(maximum_iterations))
    False -> {
      let midpoint = lower +. { upper -. lower } /. 2.0
      use midpoint_value <- result.try(
        function(midpoint) |> result.map(finite.output) |> result.flatten,
      )
      case
        float.absolute_value(midpoint_value) <=. tolerance
        || { upper -. lower } /. 2.0 <=. tolerance
      {
        True -> finite.output(midpoint)
        False ->
          case same_sign(lower_value, midpoint_value) {
            True ->
              bisect(
                function,
                midpoint,
                upper,
                midpoint_value,
                tolerance,
                maximum_iterations,
                completed + 1,
              )
            False ->
              bisect(
                function,
                lower,
                midpoint,
                lower_value,
                tolerance,
                maximum_iterations,
                completed + 1,
              )
          }
      }
    }
  }
}

fn same_sign(left: Float, right: Float) -> Bool {
  { left >. 0.0 && right >. 0.0 } || { left <. 0.0 && right <. 0.0 }
}
