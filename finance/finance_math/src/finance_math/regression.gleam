import finance_math/error.{type MetricError}
import finance_math/statistics
import gleam/float
import gleam/int
import gleam/list
import gleam/result

pub type Model {
  Model(
    intercept: Float,
    coefficients: List(Float),
    fitted: List(Float),
    residuals: List(Float),
    r_squared: Float,
    adjusted_r_squared: Float,
    observations: Int,
  )
}

/// Ordinary least squares using normal equations and bounded Gauss-Jordan
/// elimination with partial pivoting.
///
/// Predictor data is observation-major: one inner list per dependent value.
pub fn ordinary_least_squares(
  dependent: List(Float),
  predictors: List(List(Float)),
  include_intercept include_intercept: Bool,
  singular_tolerance singular_tolerance: Float,
) -> Result(Model, MetricError) {
  use width <- result.try(validate(
    dependent,
    predictors,
    include_intercept,
    singular_tolerance,
  ))
  let design = case include_intercept {
    True -> list.map(predictors, fn(row) { [1.0, ..row] })
    False -> predictors
  }
  let columns = transpose(design)
  let normal_matrix =
    list.map(columns, fn(left) {
      list.map(columns, fn(right) { dot(left, right) })
    })
  let normal_target = list.map(columns, fn(column) { dot(column, dependent) })
  let augmented = append_column(normal_matrix, normal_target, [])
  use solved <- result.try(solve(
    augmented,
    0,
    list.length(columns),
    singular_tolerance,
  ))
  let coefficients_with_intercept =
    list.map(solved, fn(row) {
      let assert Ok(value) = list.last(row)
      value
    })
  let #(intercept, coefficients) = case include_intercept {
    True -> {
      let assert [intercept, ..coefficients] = coefficients_with_intercept
      #(intercept, coefficients)
    }
    False -> #(0.0, coefficients_with_intercept)
  }
  let fitted =
    list.map(predictors, fn(row) { intercept +. dot(row, coefficients) })
  let residuals = subtract_lists(dependent, fitted, [])
  use r_squared <- result.try(coefficient_of_determination(
    dependent,
    residuals,
    include_intercept,
  ))
  let observations = list.length(dependent)
  let adjusted = case include_intercept {
    True ->
      1.0
      -. { 1.0 -. r_squared }
      *. int.to_float(observations - 1)
      /. int.to_float(observations - width - 1)
    False ->
      1.0
      -. { 1.0 -. r_squared }
      *. int.to_float(observations)
      /. int.to_float(observations - width)
  }
  Ok(Model(
    intercept,
    coefficients,
    fitted,
    residuals,
    r_squared,
    adjusted,
    observations,
  ))
}

pub fn predict(
  model: Model,
  predictors: List(Float),
) -> Result(Float, MetricError) {
  case list.length(predictors) == list.length(model.coefficients) {
    True -> Ok(model.intercept +. dot(predictors, model.coefficients))
    False ->
      Error(error.LengthMismatch(
        list.length(model.coefficients),
        list.length(predictors),
      ))
  }
}

fn validate(
  dependent: List(Float),
  predictors: List(List(Float)),
  include_intercept: Bool,
  tolerance: Float,
) -> Result(Int, MetricError) {
  let observations = list.length(dependent)
  case dependent, observations == list.length(predictors), tolerance >. 0.0 {
    [], _, _ -> Error(error.EmptyInput)
    _, False, _ ->
      Error(error.LengthMismatch(observations, list.length(predictors)))
    _, _, False -> Error(error.InvalidTolerance)
    _, True, True -> {
      let assert [first, ..rest] = predictors
      let width = list.length(first)
      let consistent = list.all(rest, fn(row) { list.length(row) == width })
      let parameter_count =
        width
        + case include_intercept {
          True -> 1
          False -> 0
        }
      case width > 0, consistent, observations > parameter_count {
        False, _, _ -> Error(error.InvalidModel)
        _, False, _ -> Error(error.InvalidModel)
        _, _, False ->
          Error(error.InsufficientData(
            required: parameter_count + 1,
            actual: observations,
          ))
        True, True, True -> Ok(width)
      }
    }
  }
}

fn transpose(rows: List(List(Float))) -> List(List(Float)) {
  case rows {
    [] -> []
    [first, ..] ->
      first
      |> list.index_map(fn(_, index) {
        list.map(rows, fn(row) { at(row, index) })
      })
  }
}

fn append_column(
  rows: List(List(Float)),
  values: List(Float),
  output_reversed: List(List(Float)),
) -> List(List(Float)) {
  case rows, values {
    [], [] -> list.reverse(output_reversed)
    [row, ..rows], [value, ..values] ->
      append_column(rows, values, [list.append(row, [value]), ..output_reversed])
    _, _ -> list.reverse(output_reversed)
  }
}

fn solve(
  rows: List(List(Float)),
  column: Int,
  size: Int,
  tolerance: Float,
) -> Result(List(List(Float)), MetricError) {
  case column >= size {
    True -> Ok(rows)
    False -> {
      let #(pivot_index, pivot_magnitude) =
        select_pivot(rows, column, 0, column, 0.0)
      case pivot_magnitude <=. tolerance {
        True -> Error(error.SingularSystem)
        False -> {
          let swapped = swap_rows(rows, column, pivot_index)
          let pivot_row = row_at(swapped, column)
          let pivot = at(pivot_row, column)
          let normalized = list.map(pivot_row, fn(value) { value /. pivot })
          let eliminated =
            list.index_map(swapped, fn(row, index) {
              case index == column {
                True -> normalized
                False -> {
                  let factor = at(row, column)
                  subtract_scaled(row, normalized, factor, [])
                }
              }
            })
          solve(eliminated, column + 1, size, tolerance)
        }
      }
    }
  }
}

fn select_pivot(
  rows: List(List(Float)),
  column: Int,
  index: Int,
  best_index: Int,
  best_magnitude: Float,
) -> #(Int, Float) {
  case rows {
    [] -> #(best_index, best_magnitude)
    [row, ..rest] ->
      case index < column {
        True ->
          select_pivot(rest, column, index + 1, best_index, best_magnitude)
        False -> {
          let magnitude = float.absolute_value(at(row, column))
          case magnitude >. best_magnitude {
            True -> select_pivot(rest, column, index + 1, index, magnitude)
            False ->
              select_pivot(rest, column, index + 1, best_index, best_magnitude)
          }
        }
      }
  }
}

fn swap_rows(
  rows: List(List(Float)),
  left: Int,
  right: Int,
) -> List(List(Float)) {
  case left == right {
    True -> rows
    False -> {
      let left_row = row_at(rows, left)
      let right_row = row_at(rows, right)
      list.index_map(rows, fn(row, index) {
        case index == left, index == right {
          True, _ -> right_row
          _, True -> left_row
          False, False -> row
        }
      })
    }
  }
}

fn subtract_scaled(
  row: List(Float),
  pivot: List(Float),
  factor: Float,
  output_reversed: List(Float),
) -> List(Float) {
  case row, pivot {
    [], [] -> list.reverse(output_reversed)
    [value, ..row], [pivot_value, ..pivot] ->
      subtract_scaled(row, pivot, factor, [
        value -. factor *. pivot_value,
        ..output_reversed
      ])
    _, _ -> list.reverse(output_reversed)
  }
}

fn coefficient_of_determination(
  dependent: List(Float),
  residuals: List(Float),
  include_intercept: Bool,
) -> Result(Float, MetricError) {
  use average <- result.try(statistics.mean(dependent))
  let total = case include_intercept {
    True ->
      dependent
      |> list.map(fn(value) {
        let deviation = value -. average
        deviation *. deviation
      })
      |> float.sum
    False -> dependent |> list.map(fn(value) { value *. value }) |> float.sum
  }
  case total == 0.0 {
    True -> Error(error.ZeroVariance)
    False -> {
      let unexplained =
        residuals |> list.map(fn(value) { value *. value }) |> float.sum
      Ok(1.0 -. unexplained /. total)
    }
  }
}

fn subtract_lists(
  left: List(Float),
  right: List(Float),
  output_reversed: List(Float),
) -> List(Float) {
  case left, right {
    [], [] -> list.reverse(output_reversed)
    [left, ..lefts], [right, ..rights] ->
      subtract_lists(lefts, rights, [left -. right, ..output_reversed])
    _, _ -> list.reverse(output_reversed)
  }
}

fn dot(left: List(Float), right: List(Float)) -> Float {
  case left, right {
    [], [] -> 0.0
    [left, ..lefts], [right, ..rights] -> left *. right +. dot(lefts, rights)
    _, _ -> 0.0
  }
}

fn at(values: List(Float), index: Int) -> Float {
  let assert [value, ..] = list.drop(values, index)
  value
}

fn row_at(rows: List(List(Float)), index: Int) -> List(Float) {
  let assert [row, ..] = list.drop(rows, index)
  row
}
