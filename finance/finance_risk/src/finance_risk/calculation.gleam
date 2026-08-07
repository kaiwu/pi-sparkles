import finance_core/decimal.{type Decimal, type RoundingMode}
import finance_math/exact
import finance_provenance/identity
import finance_risk/fact.{type Fact}
import finance_risk/numeric
import gleam/int as gleam_int
import gleam/list
import gleam/string as gleam_string

pub type RoundingPolicy {
  FinalOnly
}

pub opaque type RoundingSpec {
  RoundingSpec(
    output_scale: Int,
    intermediate_scale: Int,
    rounding_mode: RoundingMode,
    policy: RoundingPolicy,
  )
}

pub type RoundingError {
  InvalidScale
}

pub type Operand {
  Operand(
    name: String,
    state: String,
    source_references: List(String),
    source_lexemes: List(String),
    currencies: List(String),
    units: List(String),
    retained_alternatives: List(String),
  )
}

pub type Intermediate {
  Intermediate(name: String, value: String)
}

pub type Expression {
  Calculated(
    operation_id: String,
    formula_variant: String,
    value: Decimal,
    output_lexeme: String,
    currency: String,
    unit: String,
    ordered_operands: List(Operand),
    intermediate_values: List(Intermediate),
  )
  Unperformed(
    operation_id: String,
    formula_variant: String,
    reason: String,
    ordered_operands: List(Operand),
  )
}

pub fn rounding(
  output_scale output_scale_value: Int,
  intermediate_scale intermediate_scale_value: Int,
  rounding_mode rounding_mode_value: RoundingMode,
) -> Result(RoundingSpec, RoundingError) {
  case output_scale_value < 0 || intermediate_scale_value < output_scale_value {
    True -> Error(InvalidScale)
    False ->
      Ok(RoundingSpec(
        output_scale_value,
        intermediate_scale_value,
        rounding_mode_value,
        FinalOnly,
      ))
  }
}

pub fn output_scale(value: RoundingSpec) -> Int {
  value.output_scale
}

pub fn intermediate_scale(value: RoundingSpec) -> Int {
  value.intermediate_scale
}

pub fn rounding_mode(value: RoundingSpec) -> RoundingMode {
  value.rounding_mode
}

pub fn rounding_policy(value: RoundingSpec) -> RoundingPolicy {
  value.policy
}

pub fn planned_loss_per_unit(
  operation_id operation_id_value: String,
  entry entry_value: Fact(Decimal),
  stop stop_value: Fact(Decimal),
  rounding rounding_value: RoundingSpec,
) -> Expression {
  binary_same_currency(
    operation_id_value,
    "long_planned_loss_per_unit_v1",
    "entry_price",
    entry_value,
    "stop_price",
    stop_value,
    "currency_per_share",
    rounding_value,
    decimal.subtract,
  )
}

pub fn gap_loss_per_unit(
  operation_id operation_id_value: String,
  entry entry_value: Fact(Decimal),
  gap_open gap_open_value: Fact(Decimal),
  rounding rounding_value: RoundingSpec,
) -> Expression {
  binary_same_currency(
    operation_id_value,
    "long_gap_loss_per_unit_max_zero_v1",
    "entry_price",
    entry_value,
    "gap_open_price",
    gap_open_value,
    "currency_per_share",
    rounding_value,
    fn(entry, gap_open) {
      decimal.subtract(entry, gap_open) |> numeric.nonnegative
    },
  )
}

pub fn fact_value(
  operation_id operation_id_value: String,
  formula_variant formula_value: String,
  operand_name operand_name_value: String,
  value fact_value: Fact(Decimal),
  output_unit output_unit_value: String,
  rounding rounding_value: RoundingSpec,
) -> Expression {
  let operands = [operand(operand_name_value, fact_value)]
  case fact.known_value(fact_value) {
    Ok(sourced) -> {
      let source = fact.sourced_source(sourced)
      calculated_at_output_scale(
        operation_id_value,
        formula_value,
        fact.sourced_value(sourced),
        fact.currency(source),
        output_unit_value,
        operands,
        [],
        rounding_value,
      )
    }
    Error(_) -> unavailable(operation_id_value, formula_value, operands)
  }
}

pub fn fraction_amount(
  operation_id operation_id_value: String,
  basis_name basis_name_value: String,
  basis basis_value: Fact(Decimal),
  fraction fraction_value: Fact(Decimal),
  rounding rounding_value: RoundingSpec,
) -> Expression {
  let operands = [
    operand(basis_name_value, basis_value),
    operand("fraction", fraction_value),
  ]
  case fact.known_value(basis_value), fact.known_value(fraction_value) {
    Ok(basis), Ok(fraction) -> {
      let basis_source = fact.sourced_source(basis)
      let raw =
        decimal.multiply(
          fact.sourced_value(basis),
          fact.sourced_value(fraction),
        )
      calculated_at_output_scale(
        operation_id_value,
        "declared_fraction_of_named_basis_v1",
        raw,
        fact.currency(basis_source),
        fact.unit(basis_source),
        operands,
        [Intermediate("unrounded_product", decimal.to_string(raw))],
        rounding_value,
      )
    }
    _, _ ->
      unavailable(
        operation_id_value,
        "declared_fraction_of_named_basis_v1",
        operands,
      )
  }
}

pub fn amount_at_quantity(
  operation_id operation_id_value: String,
  formula_variant formula_value: String,
  per_unit per_unit_value: Expression,
  quantity quantity_value: Fact(Int),
  rounding rounding_value: RoundingSpec,
) -> Expression {
  let quantity_operand = operand("quantity", quantity_value)
  case per_unit_value, fact.known_value(quantity_value) {
    Calculated(_, _, per_unit, _, currency, _, prior_operands, _), Ok(quantity)
    -> {
      let raw =
        decimal.multiply(
          per_unit,
          decimal_from_int(fact.sourced_value(quantity)),
        )
      calculated_at_output_scale(
        operation_id_value,
        formula_value,
        raw,
        currency,
        "currency",
        list.append(prior_operands, [quantity_operand]),
        [Intermediate("unrounded_product", decimal.to_string(raw))],
        rounding_value,
      )
    }
    Unperformed(_, _, reason, prior_operands), _ ->
      Unperformed(
        operation_id_value,
        formula_value,
        "dependency_unperformed:" <> reason,
        list.append(prior_operands, [quantity_operand]),
      )
    Calculated(_, _, _, _, _, _, prior_operands, _), _ ->
      unavailable(
        operation_id_value,
        formula_value,
        list.append(prior_operands, [quantity_operand]),
      )
  }
}

pub fn ratio_by_expression(
  operation_id operation_id_value: String,
  formula_variant formula_value: String,
  numerator_name numerator_name_value: String,
  numerator numerator_value: Fact(Decimal),
  denominator denominator_value: Expression,
  rounding rounding_value: RoundingSpec,
) -> Expression {
  let numerator_operand = operand(numerator_name_value, numerator_value)
  case fact.known_value(numerator_value), denominator_value {
    Ok(numerator),
      Calculated(
        _,
        _,
        denominator,
        denominator_lexeme,
        currency,
        _,
        operands,
        _,
      )
    -> {
      let numerator_source = fact.sourced_source(numerator)
      case fact.currency(numerator_source) == currency {
        False ->
          Unperformed(
            operation_id_value,
            formula_value,
            "incompatible_currencies:"
              <> fact.currency(numerator_source)
              <> ":"
              <> currency,
            list.append([numerator_operand], operands),
          )
        True ->
          case
            exact.ratio(
              fact.sourced_value(numerator),
              denominator,
              rounding_value.intermediate_scale,
              rounding_value.rounding_mode,
            )
          {
            Error(_) ->
              Unperformed(
                operation_id_value,
                formula_value,
                "division_by_zero",
                list.append([numerator_operand], operands),
              )
            Ok(raw) ->
              Calculated(
                operation_id_value,
                formula_value,
                raw,
                numeric.fixed(raw, rounding_value.intermediate_scale),
                currency,
                "shares",
                list.append([numerator_operand], operands),
                [
                  Intermediate("denominator", denominator_lexeme),
                  Intermediate(
                    "intermediate_scale",
                    int_text(rounding_value.intermediate_scale),
                  ),
                ],
              )
          }
      }
    }
    _, Unperformed(_, _, reason, operands) ->
      Unperformed(
        operation_id_value,
        formula_value,
        "dependency_unperformed:" <> reason,
        list.append([numerator_operand], operands),
      )
    _, Calculated(_, _, _, _, _, _, operands, _) ->
      unavailable(
        operation_id_value,
        formula_value,
        list.append([numerator_operand], operands),
      )
  }
}

pub fn subtract_three(
  operation_id operation_id_value: String,
  formula_variant formula_value: String,
  budget budget_value: Fact(Decimal),
  current current_value: Expression,
  proposed proposed_value: Expression,
  rounding rounding_value: RoundingSpec,
) -> Expression {
  let budget_operand = operand("declared_budget", budget_value)
  case fact.known_value(budget_value), current_value, proposed_value {
    Ok(budget),
      Calculated(_, _, current, _, current_currency, _, current_operands, _),
      Calculated(_, _, proposed, _, proposed_currency, _, proposed_operands, _)
    -> {
      let source = fact.sourced_source(budget)
      let budget_currency = fact.currency(source)
      case
        budget_currency == current_currency
        && current_currency == proposed_currency
      {
        False ->
          Unperformed(
            operation_id_value,
            formula_value,
            "incompatible_currencies",
            [budget_operand, ..list.append(current_operands, proposed_operands)],
          )
        True -> {
          let raw =
            decimal.subtract(fact.sourced_value(budget), current)
            |> decimal.subtract(proposed)
          calculated_at_output_scale(
            operation_id_value,
            formula_value,
            raw,
            budget_currency,
            "currency",
            [budget_operand, ..list.append(current_operands, proposed_operands)],
            [Intermediate("unrounded_difference", decimal.to_string(raw))],
            rounding_value,
          )
        }
      }
    }
    _, Unperformed(_, _, reason, operands), _
    | _, _, Unperformed(_, _, reason, operands)
    ->
      Unperformed(
        operation_id_value,
        formula_value,
        "dependency_unperformed:" <> reason,
        [budget_operand, ..operands],
      )
    _, _, _ -> unavailable(operation_id_value, formula_value, [budget_operand])
  }
}

pub fn calculated_value(value: Expression) -> Result(Decimal, String) {
  case value {
    Calculated(_, _, decimal_value, _, _, _, _, _) -> Ok(decimal_value)
    Unperformed(_, _, reason, _) -> Error(reason)
  }
}

pub fn operation_id(value: Expression) -> String {
  case value {
    Calculated(id, _, _, _, _, _, _, _) | Unperformed(id, _, _, _) -> id
  }
}

pub fn formula_variant(value: Expression) -> String {
  case value {
    Calculated(_, formula, _, _, _, _, _, _) | Unperformed(_, formula, _, _) ->
      formula
  }
}

pub fn operand(name: String, value: Fact(value)) -> Operand {
  let sources = fact.fact_sources(value)
  Operand(
    name,
    fact.state_name(value),
    list.map(sources, fn(source) {
      source |> fact.source_reference |> identity.sha256_value
    }),
    list.map(sources, fact.source_lexeme),
    list.map(sources, fact.currency),
    list.map(sources, fact.unit),
    sources |> list.flat_map(fact.retained_alternatives),
  )
}

pub fn make_calculated(
  operation_id operation_id_value: String,
  formula_variant formula_value: String,
  value value_value: Decimal,
  currency currency_value: String,
  unit unit_value: String,
  ordered_operands operand_values: List(Operand),
  intermediate_values intermediate_values: List(Intermediate),
  rounding rounding_value: RoundingSpec,
) -> Expression {
  calculated_at_output_scale(
    operation_id_value,
    formula_value,
    value_value,
    currency_value,
    unit_value,
    operand_values,
    intermediate_values,
    rounding_value,
  )
}

pub fn make_unperformed(
  operation_id operation_id_value: String,
  formula_variant formula_value: String,
  reason reason_value: String,
  ordered_operands operand_values: List(Operand),
) -> Expression {
  Unperformed(operation_id_value, formula_value, reason_value, operand_values)
}

fn binary_same_currency(
  operation_id: String,
  formula_variant: String,
  left_name: String,
  left: Fact(Decimal),
  right_name: String,
  right: Fact(Decimal),
  output_unit: String,
  rounding: RoundingSpec,
  apply: fn(Decimal, Decimal) -> Decimal,
) -> Expression {
  let operands = [operand(left_name, left), operand(right_name, right)]
  case fact.known_value(left), fact.known_value(right) {
    Ok(left_value), Ok(right_value) -> {
      let left_source = fact.sourced_source(left_value)
      let right_source = fact.sourced_source(right_value)
      case fact.currency(left_source) == fact.currency(right_source) {
        False ->
          Unperformed(
            operation_id,
            formula_variant,
            "incompatible_currencies:"
              <> fact.currency(left_source)
              <> ":"
              <> fact.currency(right_source),
            operands,
          )
        True -> {
          let raw =
            apply(
              fact.sourced_value(left_value),
              fact.sourced_value(right_value),
            )
          calculated_at_output_scale(
            operation_id,
            formula_variant,
            raw,
            fact.currency(left_source),
            output_unit,
            operands,
            [Intermediate("unrounded_value", decimal.to_string(raw))],
            rounding,
          )
        }
      }
    }
    _, _ -> unavailable(operation_id, formula_variant, operands)
  }
}

fn unavailable(
  operation_id: String,
  formula_variant: String,
  operands: List(Operand),
) -> Expression {
  let missing =
    operands
    |> list.filter(fn(value) { value.state != "known" })
    |> list.map(fn(value) { value.name <> "=" <> value.state })
  Unperformed(
    operation_id,
    formula_variant,
    "unavailable_operands:" <> join(missing),
    operands,
  )
}

fn calculated_at_output_scale(
  operation_id: String,
  formula_variant: String,
  raw: Decimal,
  currency: String,
  unit: String,
  operands: List(Operand),
  intermediates: List(Intermediate),
  rounding: RoundingSpec,
) -> Expression {
  let assert Ok(value) =
    decimal.quantize(
      raw,
      scale: rounding.output_scale,
      rounding: rounding.rounding_mode,
    )
  Calculated(
    operation_id,
    formula_variant,
    value,
    numeric.fixed(value, rounding.output_scale),
    currency,
    unit,
    operands,
    intermediates,
  )
}

fn decimal_from_int(value: Int) -> Decimal {
  let assert Ok(result) = value |> int_text |> decimal.parse
  result
}

fn int_text(value: Int) -> String {
  gleam_int.to_string(value)
}

fn join(values: List(String)) -> String {
  gleam_string.join(values, with: ",")
}
