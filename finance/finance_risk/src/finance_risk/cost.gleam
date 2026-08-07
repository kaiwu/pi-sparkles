import finance_core/decimal.{type Decimal}
import finance_math/exact
import finance_risk/calculation.{type Expression, type RoundingSpec}
import finance_risk/fact.{type Fact}
import gleam/int
import gleam/list
import gleam/string as gleam_string

pub type Side {
  Buy
  Sell
}

pub type ComponentKind {
  RateOfNotional(rate: Fact(Decimal))
  FixedAmount(amount: Fact(Decimal))
  PerShare(amount: Fact(Decimal))
}

pub opaque type Component {
  Component(component_id: String, side: Side, kind: ComponentKind)
}

pub type ComponentResult {
  ComponentResult(component_id: String, side: Side, expression: Expression)
}

pub opaque type Estimate {
  Estimate(
    operation_id: String,
    side: Side,
    currency: String,
    components: List(ComponentResult),
    known_subtotal: Expression,
    total: Expression,
  )
}

pub fn rate(
  component_id: String,
  side: Side,
  value: Fact(Decimal),
) -> Component {
  Component(component_id, side, RateOfNotional(value))
}

pub fn fixed(
  component_id: String,
  side: Side,
  value: Fact(Decimal),
) -> Component {
  Component(component_id, side, FixedAmount(value))
}

pub fn per_share(
  component_id: String,
  side: Side,
  value: Fact(Decimal),
) -> Component {
  Component(component_id, side, PerShare(value))
}

pub fn one_way(
  operation_id operation_id_value: String,
  side side_value: Side,
  currency currency_value: String,
  quantity quantity_value: Fact(Int),
  price price_value: Fact(Decimal),
  components component_values: List(Component),
  rounding rounding_value: RoundingSpec,
) -> Estimate {
  let selected =
    component_values
    |> list.filter(fn(value) { value.side == side_value })
    |> list.map(fn(value) {
      ComponentResult(
        value.component_id,
        value.side,
        calculate_component(
          operation_id_value,
          currency_value,
          quantity_value,
          price_value,
          value,
          rounding_value,
        ),
      )
    })
  let known =
    selected
    |> list.filter_map(fn(value) {
      case calculation.calculated_value(value.expression) {
        Ok(number) -> Ok(number)
        Error(_) -> Error(Nil)
      }
    })
  let subtotal =
    calculation.make_calculated(
      operation_id: operation_id_value <> ".known_subtotal",
      formula_variant: "sum_known_cost_components_v1",
      value: exact.sum(known),
      currency: currency_value,
      unit: "currency",
      ordered_operands: [],
      intermediate_values: selected
        |> list.filter_map(fn(value) {
          case value.expression {
            calculation.Calculated(_, _, _, lexeme, _, _, _, _) ->
              Ok(calculation.Intermediate(value.component_id, lexeme))
            calculation.Unperformed(_, _, _, _) -> Error(Nil)
          }
        }),
      rounding: rounding_value,
    )
  let missing =
    selected
    |> list.filter_map(fn(value) {
      case value.expression {
        calculation.Calculated(_, _, _, _, _, _, _, _) -> Error(Nil)
        calculation.Unperformed(_, _, reason, _) ->
          Ok(value.component_id <> "=" <> reason)
      }
    })
  let total = case missing {
    [] ->
      calculation.make_calculated(
        operation_id: operation_id_value,
        formula_variant: "one_way_cost_sum_v1",
        value: exact.sum(known),
        currency: currency_value,
        unit: "currency",
        ordered_operands: [],
        intermediate_values: [],
        rounding: rounding_value,
      )
    _ ->
      calculation.make_unperformed(
        operation_id_value,
        "one_way_cost_sum_v1",
        "missing_components:" <> gleam_string.join(missing, with: ","),
        [],
      )
  }
  Estimate(
    operation_id_value,
    side_value,
    currency_value,
    selected,
    subtotal,
    total,
  )
}

pub fn operation_id(value: Estimate) -> String {
  value.operation_id
}

pub fn estimate_side(value: Estimate) -> Side {
  value.side
}

pub fn currency(value: Estimate) -> String {
  value.currency
}

pub fn components(value: Estimate) -> List(ComponentResult) {
  value.components
}

pub fn known_subtotal(value: Estimate) -> Expression {
  value.known_subtotal
}

pub fn total(value: Estimate) -> Expression {
  value.total
}

pub fn component_id(value: ComponentResult) -> String {
  value.component_id
}

pub fn component_side(value: ComponentResult) -> Side {
  value.side
}

pub fn component_expression(value: ComponentResult) -> Expression {
  value.expression
}

fn calculate_component(
  operation_id: String,
  currency: String,
  quantity: Fact(Int),
  price: Fact(Decimal),
  component: Component,
  rounding: RoundingSpec,
) -> Expression {
  let id = operation_id <> "." <> component.component_id
  case component.kind {
    RateOfNotional(rate) ->
      calculate_rate(id, currency, quantity, price, rate, rounding)
    FixedAmount(amount) -> calculate_fixed(id, currency, amount, rounding)
    PerShare(amount) ->
      calculate_per_share(id, currency, quantity, amount, rounding)
  }
}

fn calculate_rate(
  id: String,
  currency: String,
  quantity: Fact(Int),
  price: Fact(Decimal),
  rate: Fact(Decimal),
  rounding: RoundingSpec,
) -> Expression {
  let operands = [
    calculation.operand("quantity", quantity),
    calculation.operand("price", price),
    calculation.operand("rate", rate),
  ]
  case
    fact.known_value(quantity),
    fact.known_value(price),
    fact.known_value(rate)
  {
    Ok(q), Ok(p), Ok(r) -> {
      let price_source = fact.sourced_source(p)
      case fact.currency(price_source) == currency {
        False ->
          calculation.make_unperformed(
            id,
            "rate_times_notional_v1",
            "incompatible_currencies",
            operands,
          )
        True -> {
          let notional =
            decimal.multiply(
              decimal_from_int(fact.sourced_value(q)),
              fact.sourced_value(p),
            )
          let raw = decimal.multiply(notional, fact.sourced_value(r))
          calculation.make_calculated(
            operation_id: id,
            formula_variant: "rate_times_notional_v1",
            value: raw,
            currency: currency,
            unit: "currency",
            ordered_operands: operands,
            intermediate_values: [
              calculation.Intermediate("notional", decimal.to_string(notional)),
            ],
            rounding: rounding,
          )
        }
      }
    }
    _, _, _ -> unavailable(id, "rate_times_notional_v1", operands)
  }
}

fn calculate_fixed(
  id: String,
  currency: String,
  amount: Fact(Decimal),
  rounding: RoundingSpec,
) -> Expression {
  let operands = [calculation.operand("fixed_amount", amount)]
  case fact.known_value(amount) {
    Ok(sourced) -> {
      let source = fact.sourced_source(sourced)
      case fact.currency(source) == currency {
        False ->
          calculation.make_unperformed(
            id,
            "fixed_cost_v1",
            "incompatible_currencies",
            operands,
          )
        True ->
          calculation.make_calculated(
            operation_id: id,
            formula_variant: "fixed_cost_v1",
            value: fact.sourced_value(sourced),
            currency: currency,
            unit: "currency",
            ordered_operands: operands,
            intermediate_values: [],
            rounding: rounding,
          )
      }
    }
    Error(_) -> unavailable(id, "fixed_cost_v1", operands)
  }
}

fn calculate_per_share(
  id: String,
  currency: String,
  quantity: Fact(Int),
  amount: Fact(Decimal),
  rounding: RoundingSpec,
) -> Expression {
  let operands = [
    calculation.operand("quantity", quantity),
    calculation.operand("amount_per_share", amount),
  ]
  case fact.known_value(quantity), fact.known_value(amount) {
    Ok(q), Ok(a) -> {
      let source = fact.sourced_source(a)
      case fact.currency(source) == currency {
        False ->
          calculation.make_unperformed(
            id,
            "quantity_times_per_share_cost_v1",
            "incompatible_currencies",
            operands,
          )
        True ->
          calculation.make_calculated(
            operation_id: id,
            formula_variant: "quantity_times_per_share_cost_v1",
            value: decimal.multiply(
              decimal_from_int(fact.sourced_value(q)),
              fact.sourced_value(a),
            ),
            currency: currency,
            unit: "currency",
            ordered_operands: operands,
            intermediate_values: [],
            rounding: rounding,
          )
      }
    }
    _, _ -> unavailable(id, "quantity_times_per_share_cost_v1", operands)
  }
}

fn unavailable(
  id: String,
  formula: String,
  operands: List(calculation.Operand),
) -> Expression {
  let missing =
    operands
    |> list.filter(fn(value) { value.state != "known" })
    |> list.map(fn(value) { value.name <> "=" <> value.state })
  calculation.make_unperformed(
    id,
    formula,
    "unavailable_operands:" <> gleam_string.join(missing, with: ","),
    operands,
  )
}

fn decimal_from_int(value: Int) -> Decimal {
  let assert Ok(result) = value |> int.to_string |> decimal.parse
  result
}
