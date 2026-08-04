import finance_math/error.{type MetricError}
import gleam/float
import gleam/list

pub fn is_finite(value: Float) -> Bool {
  let encoded = float.to_string(value)
  encoded != "NaN"
  && encoded != "Infinity"
  && encoded != "-Infinity"
  && encoded != "Infinity.0"
  && encoded != "-Infinity.0"
  && encoded != "inf"
  && encoded != "-inf"
}

pub fn input(value: Float) -> Result(Float, MetricError) {
  case is_finite(value) {
    True -> Ok(value)
    False -> Error(error.NonFiniteInput)
  }
}

pub fn inputs(values: List(Float)) -> Result(List(Float), MetricError) {
  case list.all(values, is_finite) {
    True -> Ok(values)
    False -> Error(error.NonFiniteInput)
  }
}

pub fn output(value: Float) -> Result(Float, MetricError) {
  case is_finite(value) {
    True -> Ok(value)
    False -> Error(error.NonFiniteOutput)
  }
}
