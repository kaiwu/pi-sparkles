import finance_core/decimal.{type Decimal, type RoundingMode}
import finance_core/time
import finance_execution/fact.{type Fact}
import finance_execution/instruction.{type Side}
import finance_execution/numeric
import finance_math/exact
import finance_provenance/identity
import gleam/int
import gleam/list
import gleam/string

pub opaque type RoundingSpec {
  RoundingSpec(output_scale: Int, rounding_mode: RoundingMode)
}

pub type RoundingError {
  InvalidScale
}

pub type SignConvention {
  FillMinusReference
  ReferenceMinusFill
  AdversePositive
}

pub type Operand {
  Operand(
    name: String,
    state: String,
    source_references: List(String),
    source_lexemes: List(String),
    currencies: List(String),
    units: List(String),
  )
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
  )
  Unperformed(
    operation_id: String,
    formula_variant: String,
    reason: String,
    ordered_operands: List(Operand),
  )
}

pub type CostComponent {
  CostComponent(component_id: String, amount: Fact(Decimal))
}

pub type CostResult {
  CostResult(
    operation_id: String,
    ordered_components: List(CostComponent),
    known_subtotal: Expression,
    total: Expression,
    known_cost_per_quantity: Expression,
    unknown_component_ids: List(String),
  )
}

pub type ClockRelation {
  SameClock
  OffsetKnown(end_clock_minus_start_clock_ms: Int)
  OffsetUnknown(reason: String)
}

pub fn rounding(
  output_scale output_scale_value: Int,
  rounding_mode rounding_value: RoundingMode,
) -> Result(RoundingSpec, RoundingError) {
  case output_scale_value < 0 {
    True -> Error(InvalidScale)
    False -> Ok(RoundingSpec(output_scale_value, rounding_value))
  }
}

pub fn quoted_spread(
  operation_id operation_id_value: String,
  bid bid_value: Fact(Decimal),
  ask ask_value: Fact(Decimal),
  rounding rounding_value: RoundingSpec,
) -> Expression {
  binary_same_currency(
    operation_id_value,
    "quoted_spread_v1",
    "bid",
    bid_value,
    "ask",
    ask_value,
    rounding_value,
    fn(bid, ask) { decimal.subtract(ask, bid) },
  )
}

pub fn slippage_vs_limit(
  operation_id operation_id_value: String,
  side side_value: Side,
  fill_price fill_value: Fact(Decimal),
  limit_price limit_value: Fact(Decimal),
  convention convention_value: SignConvention,
  rounding rounding_value: RoundingSpec,
) -> Expression {
  binary_same_currency(
    operation_id_value,
    "slippage_vs_limit_v1",
    "fill_price",
    fill_value,
    "limit_price",
    limit_value,
    rounding_value,
    fn(fill, limit) {
      case convention_value, side_value {
        FillMinusReference, _ -> decimal.subtract(fill, limit)
        ReferenceMinusFill, _ -> decimal.subtract(limit, fill)
        AdversePositive, instruction.Buy -> decimal.subtract(fill, limit)
        AdversePositive, instruction.Sell -> decimal.subtract(limit, fill)
      }
    },
  )
}

pub fn implementation_shortfall(
  operation_id operation_id_value: String,
  side side_value: Side,
  fill_price fill_value: Fact(Decimal),
  benchmark_price benchmark_value: Fact(Decimal),
  quantity quantity_value: Fact(Decimal),
  convention convention_value: SignConvention,
  rounding rounding_value: RoundingSpec,
) -> Expression {
  let operands = [
    operand("fill_price", fill_value),
    operand("benchmark_price", benchmark_value),
    operand("quantity", quantity_value),
  ]
  case
    fact.known_value(fill_value),
    fact.known_value(benchmark_value),
    fact.known_value(quantity_value)
  {
    Ok(fill), Ok(benchmark), Ok(quantity) -> {
      let fill_source = fact.sourced_source(fill)
      let benchmark_source = fact.sourced_source(benchmark)
      case fact.currency(fill_source) == fact.currency(benchmark_source) {
        False ->
          Unperformed(
            operation_id_value,
            "implementation_shortfall_v1",
            "incompatible_currencies",
            operands,
          )
        True -> {
          let difference = case convention_value, side_value {
            FillMinusReference, _ ->
              decimal.subtract(
                fact.sourced_value(fill),
                fact.sourced_value(benchmark),
              )
            ReferenceMinusFill, _ ->
              decimal.subtract(
                fact.sourced_value(benchmark),
                fact.sourced_value(fill),
              )
            AdversePositive, instruction.Buy ->
              decimal.subtract(
                fact.sourced_value(fill),
                fact.sourced_value(benchmark),
              )
            AdversePositive, instruction.Sell ->
              decimal.subtract(
                fact.sourced_value(benchmark),
                fact.sourced_value(fill),
              )
          }
          calculated(
            operation_id_value,
            "implementation_shortfall_v1",
            decimal.multiply(difference, fact.sourced_value(quantity)),
            fact.currency(fill_source),
            "currency",
            operands,
            rounding_value,
          )
        }
      }
    }
    _, _, _ ->
      unavailable(operation_id_value, "implementation_shortfall_v1", operands)
  }
}

pub fn fill_cost_total(
  operation_id operation_id_value: String,
  currency currency_value: String,
  quantity quantity_value: Fact(Decimal),
  components component_values: List(CostComponent),
  rounding rounding_value: RoundingSpec,
) -> CostResult {
  let known =
    component_values
    |> list.filter_map(fn(value) {
      let CostComponent(_, amount) = value
      case fact.known_value(amount) {
        Ok(sourced) ->
          case fact.currency(fact.sourced_source(sourced)) == currency_value {
            True -> Ok(fact.sourced_value(sourced))
            False -> Error(Nil)
          }
        Error(_) -> Error(Nil)
      }
    })
  let unknown =
    component_values
    |> list.filter_map(fn(value) {
      let CostComponent(id, amount) = value
      case fact.known_value(amount) {
        Ok(sourced) ->
          case fact.currency(fact.sourced_source(sourced)) == currency_value {
            True -> Error(Nil)
            False -> Ok(id <> "=incompatible_currency")
          }
        Error(reason) -> Ok(id <> "=" <> reason)
      }
    })
  let subtotal_value = exact.sum(known)
  let component_operands =
    list.map(component_values, fn(value) {
      let CostComponent(id, amount) = value
      operand(id, amount)
    })
  let subtotal =
    calculated(
      operation_id_value <> ".known_subtotal",
      "sum_known_fill_cost_components_v1",
      subtotal_value,
      currency_value,
      "currency",
      component_operands,
      rounding_value,
    )
  let total = case unknown {
    [] ->
      calculated(
        operation_id_value,
        "fill_cost_total_v1",
        subtotal_value,
        currency_value,
        "currency",
        component_operands,
        rounding_value,
      )
    _ ->
      Unperformed(
        operation_id_value,
        "fill_cost_total_v1",
        "missing_components:" <> string.join(unknown, with: ","),
        component_operands,
      )
  }
  let per_quantity = case fact.known_value(quantity_value) {
    Error(reason) ->
      Unperformed(
        operation_id_value <> ".known_cost_per_quantity",
        "known_cost_per_quantity_v1",
        "quantity=" <> reason,
        [operand("quantity", quantity_value), ..component_operands],
      )
    Ok(quantity) ->
      case
        exact.ratio(
          subtotal_value,
          fact.sourced_value(quantity),
          rounding_value.output_scale,
          rounding_value.rounding_mode,
        )
      {
        Error(_) ->
          Unperformed(
            operation_id_value <> ".known_cost_per_quantity",
            "known_cost_per_quantity_v1",
            "division_by_zero",
            [operand("quantity", quantity_value), ..component_operands],
          )
        Ok(value) ->
          Calculated(
            operation_id_value <> ".known_cost_per_quantity",
            "known_cost_per_quantity_v1",
            value,
            numeric.fixed(value, rounding_value.output_scale),
            currency_value,
            "currency_per_quantity_unit",
            [operand("quantity", quantity_value), ..component_operands],
          )
      }
  }
  CostResult(
    operation_id_value,
    component_values,
    subtotal,
    total,
    per_quantity,
    unknown,
  )
}

pub fn latency(
  operation_id operation_id_value: String,
  formula_variant formula_value: String,
  start start_value: Fact(time.Instant),
  end end_value: Fact(time.Instant),
  clock_relation relation: ClockRelation,
) -> Expression {
  let operands = [
    operand("start_time", start_value),
    operand("end_time", end_value),
  ]
  case fact.known_value(start_value), fact.known_value(end_value), relation {
    Ok(start), Ok(end), SameClock ->
      latency_calculated(
        operation_id_value,
        formula_value,
        time.unix_milliseconds(fact.sourced_value(end))
          - time.unix_milliseconds(fact.sourced_value(start)),
        operands,
      )
    Ok(start), Ok(end), OffsetKnown(offset) ->
      latency_calculated(
        operation_id_value,
        formula_value,
        time.unix_milliseconds(fact.sourced_value(end))
          - offset
          - time.unix_milliseconds(fact.sourced_value(start)),
        operands,
      )
    Ok(_), Ok(_), OffsetUnknown(reason) ->
      Unperformed(
        operation_id_value,
        formula_value,
        "clock_offset_unknown:" <> reason,
        operands,
      )
    _, _, _ -> unavailable(operation_id_value, formula_value, operands)
  }
}

fn latency_calculated(
  operation_id: String,
  formula_variant: String,
  milliseconds: Int,
  operands: List(Operand),
) -> Expression {
  let assert Ok(value) = decimal.parse(int.to_string(milliseconds))
  Calculated(
    operation_id,
    formula_variant,
    value,
    int.to_string(milliseconds),
    "N/A",
    "milliseconds",
    operands,
  )
}

fn binary_same_currency(
  operation_id: String,
  formula_variant: String,
  left_name: String,
  left: Fact(Decimal),
  right_name: String,
  right: Fact(Decimal),
  rounding: RoundingSpec,
  operation: fn(Decimal, Decimal) -> Decimal,
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
            "incompatible_currencies",
            operands,
          )
        True ->
          calculated(
            operation_id,
            formula_variant,
            operation(
              fact.sourced_value(left_value),
              fact.sourced_value(right_value),
            ),
            fact.currency(left_source),
            "currency_per_share",
            operands,
            rounding,
          )
      }
    }
    _, _ -> unavailable(operation_id, formula_variant, operands)
  }
}

fn calculated(
  operation_id: String,
  formula_variant: String,
  value: Decimal,
  currency: String,
  unit: String,
  operands: List(Operand),
  rounding: RoundingSpec,
) -> Expression {
  let assert Ok(rounded) =
    decimal.quantize(
      value,
      scale: rounding.output_scale,
      rounding: rounding.rounding_mode,
    )
  Calculated(
    operation_id,
    formula_variant,
    rounded,
    numeric.fixed(rounded, rounding.output_scale),
    currency,
    unit,
    operands,
  )
}

fn unavailable(
  operation_id: String,
  formula_variant: String,
  operands: List(Operand),
) -> Expression {
  let missing =
    operands
    |> list.filter(fn(value) {
      let Operand(_, state, _, _, _, _) = value
      state != "known"
    })
    |> list.map(fn(value) {
      let Operand(name, state, _, _, _, _) = value
      name <> "=" <> state
    })
  Unperformed(
    operation_id,
    formula_variant,
    "unavailable_operands:" <> string.join(missing, with: ","),
    operands,
  )
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
  )
}

pub fn calculated_value(value: Expression) -> Result(Decimal, String) {
  case value {
    Calculated(_, _, value, _, _, _, _) -> Ok(value)
    Unperformed(_, _, reason, _) -> Error(reason)
  }
}

pub fn output_lexeme(value: Expression) -> Result(String, String) {
  case value {
    Calculated(_, _, _, lexeme, _, _, _) -> Ok(lexeme)
    Unperformed(_, _, reason, _) -> Error(reason)
  }
}

pub fn operation_id(value: Expression) -> String {
  case value {
    Calculated(id, _, _, _, _, _, _) | Unperformed(id, _, _, _) -> id
  }
}

pub fn formula_variant(value: Expression) -> String {
  case value {
    Calculated(_, variant, _, _, _, _, _) | Unperformed(_, variant, _, _) ->
      variant
  }
}

pub fn output_scale(value: RoundingSpec) -> Int {
  value.output_scale
}

pub fn rounding_mode(value: RoundingSpec) -> RoundingMode {
  value.rounding_mode
}

pub fn cost_operation_id(value: CostResult) -> String {
  let CostResult(operation_id, _, _, _, _, _) = value
  operation_id
}

pub fn cost_components(value: CostResult) -> List(CostComponent) {
  let CostResult(_, components, _, _, _, _) = value
  components
}

pub fn known_subtotal(value: CostResult) -> Expression {
  let CostResult(_, _, expression, _, _, _) = value
  expression
}

pub fn total_cost(value: CostResult) -> Expression {
  let CostResult(_, _, _, expression, _, _) = value
  expression
}

pub fn known_cost_per_quantity(value: CostResult) -> Expression {
  let CostResult(_, _, _, _, expression, _) = value
  expression
}

pub fn unknown_component_ids(value: CostResult) -> List(String) {
  let CostResult(_, _, _, _, _, ids) = value
  ids
}
