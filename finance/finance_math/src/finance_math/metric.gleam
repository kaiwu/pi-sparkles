import finance_core/currency.{type Currency as CoreCurrency}
import finance_core/decimal.{type Decimal}
import finance_math/error.{type MetricError}
import finance_math/formula.{type Formula, type Input}
import gleam/list
import gleam/result
import gleam/string

/// Units are output contracts; they are never inferred from field names.
pub type Unit {
  Scalar
  PercentagePoints
  Multiple
  Currency(currency: CoreCurrency)
  CurrencyPerShare(currency: CoreCurrency)
  Days
  Years
  Count
  Custom(label: String)
}

pub type Assumption {
  Assumption(name: String, value: String)
}

pub opaque type Definition {
  Definition(
    name: String,
    unit: Unit,
    formula: Formula,
    assumptions: List(Assumption),
  )
}

/// A self-describing exact result. Provenance packages can attach evidence for
/// each `input_names` entry without reverse-engineering the formula.
pub type Metric {
  Metric(
    name: String,
    value: Decimal,
    unit: Unit,
    input_names: List(String),
    assumptions: List(Assumption),
  )
}

pub fn define(
  name name: String,
  unit unit: Unit,
  formula formula_value: Formula,
  assumptions assumptions: List(Assumption),
) -> Result(Definition, MetricError) {
  case
    valid_text(name) && valid_unit(unit),
    valid_assumptions(assumptions, [])
  {
    False, _ -> Error(error.InvalidInputName)
    _, Error(error) -> Error(error)
    True, Ok(Nil) -> Ok(Definition(name, unit, formula_value, assumptions))
  }
}

pub fn calculate(
  definition: Definition,
  inputs: List(Input),
) -> Result(Metric, MetricError) {
  let Definition(name, unit, formula_value, assumptions) = definition
  use value <- result.try(formula.evaluate(formula_value, with: inputs))
  Ok(Metric(name, value, unit, formula.references(formula_value), assumptions))
}

fn valid_assumptions(
  assumptions: List(Assumption),
  names: List(String),
) -> Result(Nil, MetricError) {
  case assumptions {
    [] -> Ok(Nil)
    [Assumption(name, value), ..rest] ->
      case valid_text(name) && valid_text(value), list.contains(names, name) {
        False, _ -> Error(error.InvalidInputName)
        _, True -> Error(error.DuplicateInput(name))
        True, False -> valid_assumptions(rest, [name, ..names])
      }
  }
}

fn valid_unit(unit: Unit) -> Bool {
  case unit {
    Custom(label) -> valid_text(label)
    _ -> True
  }
}

fn valid_text(value: String) -> Bool {
  value != "" && string.trim(value) == value
}
