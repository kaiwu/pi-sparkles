import finance_core/decimal.{type Decimal, type RoundingMode}
import finance_core/observation.{type MissingReason}
import finance_math/error.{type MetricError}
import finance_math/exact
import gleam/list
import gleam/order.{type Order, Gt, Lt}
import gleam/result
import gleam/string

/// The caller must distinguish unavailable data from numeric zero.
pub type InputValue {
  Available(value: Decimal)
  Missing(reason: MissingReason)
}

pub type Input {
  Input(name: String, value: InputValue)
}

/// A provider-neutral exact formula tree.
///
/// This deliberately models algebra rather than enumerating ratios such as
/// ROE, EBITDA margin, or current ratio. Named metrics can be small values that
/// build this tree, while the evaluator retains one set of missing/zero rules.
pub type Formula {
  Literal(value: Decimal)
  Reference(name: String)
  Add(left: Formula, right: Formula)
  Subtract(left: Formula, right: Formula)
  Multiply(left: Formula, right: Formula)
  Divide(
    numerator: Formula,
    denominator: Formula,
    scale: Int,
    rounding: RoundingMode,
  )
  Negate(value: Formula)
  Sum(values: List(Formula))
  Mean(values: List(Formula), scale: Int, rounding: RoundingMode)
  Minimum(values: List(Formula))
  Maximum(values: List(Formula))
}

pub fn evaluate(
  formula: Formula,
  with inputs: List(Input),
) -> Result(Decimal, MetricError) {
  use _ <- result.try(validate_inputs(inputs, []))
  evaluate_valid(formula, inputs)
}

/// Return referenced input names once, in first-appearance order.
pub fn references(formula: Formula) -> List(String) {
  collect_references(formula, []) |> list.reverse
}

fn evaluate_valid(
  formula: Formula,
  inputs: List(Input),
) -> Result(Decimal, MetricError) {
  case formula {
    Literal(value) -> Ok(value)
    Reference(name) -> resolve(name, inputs)
    Add(left, right) -> {
      use left <- result.try(evaluate_valid(left, inputs))
      use right <- result.try(evaluate_valid(right, inputs))
      Ok(decimal.add(left, right))
    }
    Subtract(left, right) -> {
      use left <- result.try(evaluate_valid(left, inputs))
      use right <- result.try(evaluate_valid(right, inputs))
      Ok(decimal.subtract(left, right))
    }
    Multiply(left, right) -> {
      use left <- result.try(evaluate_valid(left, inputs))
      use right <- result.try(evaluate_valid(right, inputs))
      Ok(decimal.multiply(left, right))
    }
    Divide(numerator, denominator, scale, rounding) -> {
      use numerator <- result.try(evaluate_valid(numerator, inputs))
      use denominator <- result.try(evaluate_valid(denominator, inputs))
      exact.ratio(numerator, denominator, scale, rounding)
    }
    Negate(value) -> {
      use value <- result.try(evaluate_valid(value, inputs))
      Ok(decimal.negate(value))
    }
    Sum(values) ->
      values
      |> list.try_map(fn(value) { evaluate_valid(value, inputs) })
      |> result.map(exact.sum)
    Mean(values, scale, rounding) -> {
      use values <- result.try(
        list.try_map(values, fn(value) { evaluate_valid(value, inputs) }),
      )
      exact.mean(values, scale, rounding)
    }
    Minimum(values) -> extremum(values, inputs, decimal.compare, True)
    Maximum(values) -> extremum(values, inputs, decimal.compare, False)
  }
}

fn resolve(name: String, inputs: List(Input)) -> Result(Decimal, MetricError) {
  case list.find(inputs, fn(input) { input.name == name }) {
    Error(_) -> Error(error.UnknownInput(name))
    Ok(Input(_, Available(value))) -> Ok(value)
    Ok(Input(_, Missing(reason))) -> Error(error.MissingInput(name, reason))
  }
}

fn extremum(
  formulas: List(Formula),
  inputs: List(Input),
  compare: fn(Decimal, Decimal) -> Order,
  minimum: Bool,
) -> Result(Decimal, MetricError) {
  use values <- result.try(
    list.try_map(formulas, fn(value) { evaluate_valid(value, inputs) }),
  )
  case values {
    [] -> Error(error.EmptyInput)
    [first, ..rest] ->
      Ok(
        list.fold(rest, first, fn(best, candidate) {
          case compare(candidate, best), minimum {
            Lt, True -> candidate
            Gt, False -> candidate
            _, _ -> best
          }
        }),
      )
  }
}

fn validate_inputs(
  inputs: List(Input),
  names: List(String),
) -> Result(Nil, MetricError) {
  case inputs {
    [] -> Ok(Nil)
    [Input(name, _), ..rest] ->
      case name == "" || string.trim(name) != name, list.contains(names, name) {
        True, _ -> Error(error.InvalidInputName)
        _, True -> Error(error.DuplicateInput(name))
        False, False -> validate_inputs(rest, [name, ..names])
      }
  }
}

fn collect_references(formula: Formula, found: List(String)) -> List(String) {
  case formula {
    Literal(_) -> found
    Reference(name) -> add_reference(found, name)
    Add(left, right)
    | Subtract(left, right)
    | Multiply(left, right)
    | Divide(left, right, _, _) ->
      collect_references(right, collect_references(left, found))
    Negate(value) -> collect_references(value, found)
    Sum(values) | Mean(values, _, _) | Minimum(values) | Maximum(values) ->
      list.fold(values, found, fn(found, value) {
        collect_references(value, found)
      })
  }
}

fn add_reference(found_reversed: List(String), name: String) -> List(String) {
  case list.contains(found_reversed, name) {
    True -> found_reversed
    False -> [name, ..found_reversed]
  }
}
