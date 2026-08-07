import finance_core/decimal.{type Decimal}
import finance_math/exact
import finance_provenance/identity.{type Sha256}
import finance_risk/calculation.{type Expression, type RoundingSpec}
import finance_risk/fact.{type Fact}
import finance_risk/numeric
import finance_track.{type Track}
import gleam/int as gleam_int
import gleam/list
import gleam/string

pub opaque type Position {
  Position(
    position_id: String,
    account_id: String,
    track: Track,
    listing_id: String,
    quantity: Fact(Int),
    entry_price: Fact(Decimal),
    desired_stop: Fact(Decimal),
    currency: String,
    source_receipt: Sha256,
  )
}

pub type PositionError {
  InvalidText(field: String)
}

pub type Contribution {
  Contribution(position_id: String, expression: Expression)
}

pub opaque type Heat {
  Heat(
    operation_id: String,
    formula_variant: String,
    currency: String,
    contributions: List(Contribution),
    total: Expression,
  )
}

pub fn position(
  position_id position_id_value: String,
  account_id account_id_value: String,
  track track_value: Track,
  listing_id listing_id_value: String,
  quantity quantity_value: Fact(Int),
  entry_price entry_value: Fact(Decimal),
  desired_stop stop_value: Fact(Decimal),
  currency currency_value: String,
  source_receipt receipt_value: Sha256,
) -> Result(Position, PositionError) {
  case
    valid_text(position_id_value),
    valid_text(account_id_value),
    valid_text(listing_id_value),
    valid_text(currency_value)
  {
    False, _, _, _ -> Error(InvalidText("position_id"))
    _, False, _, _ -> Error(InvalidText("account_id"))
    _, _, False, _ -> Error(InvalidText("listing_id"))
    _, _, _, False -> Error(InvalidText("currency"))
    True, True, True, True ->
      Ok(Position(
        position_id_value,
        account_id_value,
        track_value,
        listing_id_value,
        quantity_value,
        entry_value,
        stop_value,
        currency_value,
        receipt_value,
      ))
  }
}

pub fn planned_stop_v1(
  operation_id operation_id_value: String,
  currency currency_value: String,
  positions position_values: List(Position),
  rounding rounding_value: RoundingSpec,
) -> Heat {
  let contributions =
    list.map(position_values, fn(position) {
      Contribution(
        position.position_id,
        position_contribution(position, rounding_value),
      )
    })
  let total =
    heat_total(
      operation_id_value,
      currency_value,
      contributions,
      rounding_value,
    )
  Heat(
    operation_id_value,
    "heat_planned_stop_v1",
    currency_value,
    contributions,
    total,
  )
}

pub fn remaining(
  operation_id operation_id_value: String,
  declared_budget budget_value: Fact(Decimal),
  current current_value: Heat,
  proposed proposed_value: Heat,
  rounding rounding_value: RoundingSpec,
) -> Expression {
  calculation.subtract_three(
    operation_id_value,
    "remaining_heat_declared_budget_minus_current_minus_proposed_v1",
    budget_value,
    current_value.total,
    proposed_value.total,
    rounding_value,
  )
}

pub fn operation_id(value: Heat) -> String {
  value.operation_id
}

pub fn formula_variant(value: Heat) -> String {
  value.formula_variant
}

pub fn currency(value: Heat) -> String {
  value.currency
}

pub fn contributions(value: Heat) -> List(Contribution) {
  value.contributions
}

pub fn total(value: Heat) -> Expression {
  value.total
}

pub fn contribution_position_id(value: Contribution) -> String {
  value.position_id
}

pub fn contribution_expression(value: Contribution) -> Expression {
  value.expression
}

pub fn position_id(value: Position) -> String {
  value.position_id
}

pub fn account_id(value: Position) -> String {
  value.account_id
}

pub fn position_track(value: Position) -> Track {
  value.track
}

pub fn listing_id(value: Position) -> String {
  value.listing_id
}

pub fn quantity(value: Position) -> Fact(Int) {
  value.quantity
}

pub fn entry_price(value: Position) -> Fact(Decimal) {
  value.entry_price
}

pub fn desired_stop(value: Position) -> Fact(Decimal) {
  value.desired_stop
}

pub fn position_currency(value: Position) -> String {
  value.currency
}

pub fn source_receipt(value: Position) -> Sha256 {
  value.source_receipt
}

fn position_contribution(
  value: Position,
  rounding: RoundingSpec,
) -> Expression {
  let loss =
    calculation.planned_loss_per_unit(
      value.position_id <> ".loss_per_unit",
      value.entry_price,
      value.desired_stop,
      rounding,
    )
  let quantity_operand = calculation.operand("quantity", value.quantity)
  case loss, fact.known_value(value.quantity) {
    calculation.Calculated(_, _, loss_value, _, currency, _, operands, _),
      Ok(quantity)
    -> {
      let clamped = numeric.nonnegative(loss_value)
      let raw =
        decimal.multiply(
          clamped,
          decimal_from_int(fact.sourced_value(quantity)),
        )
      calculation.make_calculated(
        operation_id: value.position_id <> ".planned_stop_contribution",
        formula_variant: "quantity_times_max_zero_entry_minus_stop_v1",
        value: raw,
        currency: currency,
        unit: "currency",
        ordered_operands: list.append(operands, [quantity_operand]),
        intermediate_values: [
          calculation.Intermediate(
            "nonnegative_loss_per_unit",
            decimal.to_string(clamped),
          ),
        ],
        rounding: rounding,
      )
    }
    calculation.Unperformed(_, _, reason, operands), _ ->
      calculation.make_unperformed(
        value.position_id <> ".planned_stop_contribution",
        "quantity_times_max_zero_entry_minus_stop_v1",
        "dependency_unperformed:" <> reason,
        list.append(operands, [quantity_operand]),
      )
    _, _ ->
      calculation.make_unperformed(
        value.position_id <> ".planned_stop_contribution",
        "quantity_times_max_zero_entry_minus_stop_v1",
        "unavailable_operands:quantity=" <> fact.state_name(value.quantity),
        [quantity_operand],
      )
  }
}

fn heat_total(
  operation_id: String,
  currency: String,
  contributions: List(Contribution),
  rounding: RoundingSpec,
) -> Expression {
  let unperformed =
    contributions
    |> list.filter(fn(value) {
      case value.expression {
        calculation.Calculated(_, _, _, _, _, _, _, _) -> False
        calculation.Unperformed(_, _, _, _) -> True
      }
    })
  case unperformed {
    [_, ..] ->
      calculation.make_unperformed(
        operation_id,
        "heat_planned_stop_v1",
        "unperformed_contributions:"
          <> {
          unperformed
          |> list.map(fn(value) { value.position_id })
          |> string.join(with: ",")
        },
        [],
      )
    [] -> {
      let calculated =
        list.map(contributions, fn(value) {
          let assert Ok(number) = calculation.calculated_value(value.expression)
          number
        })
      let mismatched =
        list.any(contributions, fn(value) {
          case value.expression {
            calculation.Calculated(_, _, _, _, found, _, _, _) ->
              found != currency
            calculation.Unperformed(_, _, _, _) -> False
          }
        })
      case mismatched {
        True ->
          calculation.make_unperformed(
            operation_id,
            "heat_planned_stop_v1",
            "incompatible_currencies",
            [],
          )
        False ->
          calculation.make_calculated(
            operation_id: operation_id,
            formula_variant: "heat_planned_stop_v1",
            value: exact.sum(calculated),
            currency: currency,
            unit: "currency",
            ordered_operands: [],
            intermediate_values: list.map(contributions, fn(value) {
              let assert calculation.Calculated(_, _, _, lexeme, _, _, _, _) =
                value.expression
              calculation.Intermediate(value.position_id, lexeme)
            }),
            rounding: rounding,
          )
      }
    }
  }
}

fn valid_text(value: String) -> Bool {
  value != "" && string.trim(value) == value
}

fn decimal_from_int(value: Int) -> Decimal {
  let assert Ok(result) = value |> gleam_int.to_string |> decimal.parse
  result
}
