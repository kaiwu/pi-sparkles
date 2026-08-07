import finance_core/decimal
import finance_core/time
import finance_provenance/hash
import finance_provenance/identity.{type Sha256}
import finance_risk/bound.{type Bound, type Intersection, type Projection}
import finance_risk/calculation.{type Expression}
import finance_risk/cost.{type Estimate}
import finance_risk/heat.{type Heat}
import finance_risk/request.{type InputReference, type Request}
import finance_track
import gleam/json.{type Json}
import gleam/list
import gleam/result
import gleam/string

pub const request_schema_version = 1

pub const semantic_schema_version = 1

pub const implementation_version = "finance_risk/0.1.0"

pub opaque type Envelope {
  Envelope(payload: Json, canonical_content_hash: Sha256)
}

pub type ResultItem {
  ExpressionResult(value: Expression)
  BoundResult(value: Bound)
  IntersectionResult(value: Intersection)
  HeatResult(value: Heat)
  CostResult(value: Estimate)
}

pub type ReceiptError {
  HashFailure
  TooManyResults(received: Int, maximum: Int)
  ResultNotRequested(operation_id: String)
}

pub fn request_receipt(value: Request) -> Result(Envelope, ReceiptError) {
  envelope(request_payload(value))
}

pub fn semantic_result_receipt(
  request request_value: Request,
  results result_values: List(ResultItem),
) -> Result(Envelope, ReceiptError) {
  let budgets = request.execution_budgets(request_value)
  case list.length(result_values) > request.maximum_outputs(budgets) {
    True ->
      Error(TooManyResults(
        list.length(result_values),
        request.maximum_outputs(budgets),
      ))
    False -> {
      use _ <- result.try(validate_result_ids(request_value, result_values))
      use request_envelope <- result.try(request_receipt(request_value))
      use input_hash <- result.try(
        hash_json(inputs_json(request.ordered_inputs(request_value))),
      )
      envelope(semantic_payload(
        request_value,
        result_values,
        request_envelope.canonical_content_hash,
        input_hash,
      ))
    }
  }
}

pub fn encode(value: Envelope) -> String {
  json.object([
    #("payload", value.payload),
    #(
      "canonical_content_hash",
      value.canonical_content_hash
        |> identity.sha256_value
        |> json.string,
    ),
  ])
  |> json.to_string
}

pub fn payload_text(value: Envelope) -> String {
  value.payload |> json.to_string
}

pub fn canonical_content_hash(value: Envelope) -> Sha256 {
  value.canonical_content_hash
}

pub fn verify(value: Envelope) -> Bool {
  case hash.text(json.to_string(value.payload)) {
    Ok(actual) -> actual == value.canonical_content_hash
    Error(_) -> False
  }
}

fn envelope(payload: Json) -> Result(Envelope, ReceiptError) {
  case hash.text(json.to_string(payload)) {
    Ok(value) -> Ok(Envelope(payload, value))
    Error(_) -> Error(HashFailure)
  }
}

fn hash_json(value: Json) -> Result(Sha256, ReceiptError) {
  case hash.text(json.to_string(value)) {
    Ok(value) -> Ok(value)
    Error(_) -> Error(HashFailure)
  }
}

fn request_payload(value: Request) -> Json {
  let context = request.request_context(value)
  let budgets = request.execution_budgets(value)
  json.object([
    #("schema", json.string("pi-sparkles/risk-calculation-request")),
    #("schema_version", json.int(request_schema_version)),
    #(
      "instruction_receipt_hash",
      value |> request.instruction_ref |> identity.sha256_value |> json.string,
    ),
    #(
      "requested_operations",
      json.array(request.operations(value), operation_json),
    ),
    #("account_scope", json.string(request.account_scope(context))),
    #("portfolio_scope", json.string(request.portfolio_scope(context))),
    #(
      "track",
      context |> request.context_track |> finance_track.name |> json.string,
    ),
    #("listing_id", json.string(request.listing_id(context))),
    #(
      "as_of_time_unix_ms",
      context |> request.as_of_time |> time.unix_milliseconds |> json.int,
    ),
    #("native_currency", json.string(request.context_currency(context))),
    #("input_fact_references", inputs_json(request.ordered_inputs(value))),
    #(
      "selected_budgets",
      json.array(request.selected_budget_ids(value), json.string),
    ),
    #(
      "selected_scenarios",
      json.array(request.selected_scenario_ids(value), json.string),
    ),
    #(
      "selected_cost_model",
      json.array(request.selected_cost_component_ids(value), json.string),
    ),
    #(
      "quantity_projection_policy",
      value
        |> request.projection_policy
        |> projection_policy_name
        |> json.string,
    ),
    #("rounding_policy", rounding_json(request.request_rounding(value))),
    #(
      "currency_policy",
      value |> request.currency_policy |> currency_policy_name |> json.string,
    ),
    #("fx_receipts", json.array([], fn(value) { json.string(value) })),
    #("branch_policy", branch_policy_json(request.branch_policy(value))),
    #(
      "aggregation_policy",
      json.array(request.aggregation_policies(value), json.string),
    ),
    #(
      "requested_summary_fields",
      json.array(request.requested_summary_fields(value), json.string),
    ),
    #(
      "budgets",
      json.object([
        #("maximum_outputs", json.int(request.maximum_outputs(budgets))),
        #("maximum_operations", json.int(request.maximum_operations(budgets))),
      ]),
    ),
    #("evidence_roots", roots_json(request.evidence_roots(context))),
    #(
      "available_operations",
      json.array(request.available_operations(value), json.string),
    ),
  ])
}

fn semantic_payload(
  request_value: Request,
  result_values: List(ResultItem),
  request_hash: Sha256,
  input_hash: Sha256,
) -> Json {
  let context = request.request_context(request_value)
  let expressions = result_values |> list.flat_map(result_expressions)
  let calculated = list.filter(expressions, expression_is_calculated)
  let unperformed =
    list.filter(expressions, fn(value) { !expression_is_calculated(value) })
  let inputs = request.ordered_inputs(request_value)
  json.object([
    #("schema", json.string("pi-sparkles/risk-calculation-receipt")),
    #("schema_version", json.int(semantic_schema_version)),
    #(
      "request_receipt_hash",
      request_hash |> identity.sha256_value |> json.string,
    ),
    #("implementation_version", json.string(implementation_version)),
    #("input_content_hash", input_hash |> identity.sha256_value |> json.string),
    #("ordered_input_lexemes", inputs_json(inputs)),
    #("formulas_and_expression_trees", json.array(result_values, result_json)),
    #(
      "intermediate_values",
      json.array(calculated, expression_intermediates_json),
    ),
    #(
      "native_units_and_currencies",
      json.array(calculated, expression_unit_json),
    ),
    #(
      "converted_units_and_currencies",
      json.array([], fn(value) { json.string(value) }),
    ),
    #(
      "per_constraint_bounds",
      result_values
        |> list.filter_map(fn(value) {
          case value {
            BoundResult(bound) -> Ok(bound_json(bound))
            _ -> Error(Nil)
          }
        })
        |> json.array(fn(value) { value }),
    ),
    #(
      "scenario_losses",
      expressions
        |> list.filter(fn(value) {
          value |> calculation.formula_variant |> string.contains("gap")
        })
        |> json.array(expression_json),
    ),
    #(
      "cost_components",
      result_values
        |> list.filter_map(fn(value) {
          case value {
            CostResult(estimate) -> Ok(cost_json(estimate))
            _ -> Error(Nil)
          }
        })
        |> json.array(fn(value) { value }),
    ),
    #(
      "position_contributions",
      result_values
        |> list.filter_map(fn(value) {
          case value {
            HeatResult(heat) -> Ok(heat_json(heat))
            _ -> Error(Nil)
          }
        })
        |> json.array(fn(value) { value }),
    ),
    #("calculated_outputs", json.array(calculated, expression_json)),
    #("unperformed_expressions", json.array(unperformed, expression_json)),
    #("unknown_facts", inputs_by_state(inputs, "unknown")),
    #("conflict_facts", inputs_by_state(inputs, "conflicting")),
    #("decode_failure_facts", inputs_by_state(inputs, "decode_failure")),
    #(
      "mechanical_check_facts",
      json.array([], fn(value) { json.string(value) }),
    ),
    #(
      "retained_alternatives",
      inputs
        |> list.filter(fn(value) { !list.is_empty(value.retained_alternatives) })
        |> json.array(input_json),
    ),
    #(
      "selection_instructions",
      branch_policy_json(request.branch_policy(request_value)),
    ),
    #("evidence_roots", roots_json(request.evidence_roots(context))),
    #(
      "available_operations",
      json.array(request.available_operations(request_value), json.string),
    ),
  ])
}

fn operation_json(value: request.OperationSpec) -> Json {
  json.object([
    #("operation_id", json.string(request.operation_id(value))),
    #("formula_variant", json.string(request.formula_variant(value))),
    #(
      "ordered_parameters",
      value
        |> request.ordered_parameters
        |> list.sort(fn(left, right) { string.compare(left.0, right.0) })
        |> json.array(fn(parameter) {
          json.object([
            #("name", json.string(parameter.0)),
            #("value", json.string(parameter.1)),
          ])
        }),
    ),
    #(
      "instruction_ref",
      value
        |> request.operation_instruction_ref
        |> identity.sha256_value
        |> json.string,
    ),
    #("input_fact_ids", json.array(request.input_fact_ids(value), json.string)),
  ])
}

fn inputs_json(values: List(InputReference)) -> Json {
  json.array(values, input_json)
}

fn input_json(value: InputReference) -> Json {
  json.object([
    #("fact_id", json.string(value.fact_id)),
    #("state", json.string(value.state)),
    #("source_kinds", json.array(value.source_kinds, json.string)),
    #(
      "source_references",
      value.source_references
        |> list.map(identity.sha256_value)
        |> json.array(json.string),
    ),
    #(
      "effective_times_unix_ms",
      value.effective_times
        |> list.map(time.unix_milliseconds)
        |> json.array(json.int),
    ),
    #(
      "retrieval_times_unix_ms",
      value.retrieval_times
        |> list.map(time.unix_milliseconds)
        |> json.array(json.int),
    ),
    #("source_lexemes", json.array(value.source_lexemes, json.string)),
    #("currencies", json.array(value.currencies, json.string)),
    #("units", json.array(value.units, json.string)),
    #("scopes", json.array(value.scopes, json.string)),
    #(
      "retained_alternatives",
      json.array(value.retained_alternatives, json.string),
    ),
  ])
}

fn result_json(value: ResultItem) -> Json {
  case value {
    ExpressionResult(expression) ->
      json.object([
        #("kind", json.string("expression")),
        #("value", expression_json(expression)),
      ])
    BoundResult(bound) ->
      json.object([
        #("kind", json.string("quantity_bound")),
        #("value", bound_json(bound)),
      ])
    IntersectionResult(intersection) ->
      json.object([
        #("kind", json.string("requested_intersection")),
        #("value", intersection_json(intersection)),
      ])
    HeatResult(heat) ->
      json.object([
        #("kind", json.string("portfolio_decomposition")),
        #("value", heat_json(heat)),
      ])
    CostResult(estimate) ->
      json.object([
        #("kind", json.string("cost_decomposition")),
        #("value", cost_json(estimate)),
      ])
  }
}

fn expression_json(value: Expression) -> Json {
  case value {
    calculation.Calculated(
      operation_id,
      formula_variant,
      _,
      output_lexeme,
      currency,
      unit,
      operands,
      intermediate_values,
    ) ->
      json.object([
        #("operation_id", json.string(operation_id)),
        #("formula_variant", json.string(formula_variant)),
        #("state", json.string("calculated")),
        #("value", json.string(output_lexeme)),
        #("currency", json.string(currency)),
        #("unit", json.string(unit)),
        #("ordered_operands", json.array(operands, operand_json)),
        #(
          "intermediate_values",
          json.array(intermediate_values, intermediate_json),
        ),
      ])
    calculation.Unperformed(operation_id, formula_variant, reason, operands) ->
      json.object([
        #("operation_id", json.string(operation_id)),
        #("formula_variant", json.string(formula_variant)),
        #("state", json.string("unperformed")),
        #("reason", json.string(reason)),
        #("ordered_operands", json.array(operands, operand_json)),
      ])
  }
}

fn operand_json(value: calculation.Operand) -> Json {
  json.object([
    #("name", json.string(value.name)),
    #("state", json.string(value.state)),
    #("source_references", json.array(value.source_references, json.string)),
    #("source_lexemes", json.array(value.source_lexemes, json.string)),
    #("currencies", json.array(value.currencies, json.string)),
    #("units", json.array(value.units, json.string)),
    #(
      "retained_alternatives",
      json.array(value.retained_alternatives, json.string),
    ),
  ])
}

fn intermediate_json(value: calculation.Intermediate) -> Json {
  json.object([
    #("name", json.string(value.name)),
    #("value", json.string(value.value)),
  ])
}

fn expression_intermediates_json(value: Expression) -> Json {
  case value {
    calculation.Calculated(operation_id, _, _, _, _, _, _, intermediates) ->
      json.object([
        #("operation_id", json.string(operation_id)),
        #("values", json.array(intermediates, intermediate_json)),
      ])
    calculation.Unperformed(operation_id, _, _, _) ->
      json.object([
        #("operation_id", json.string(operation_id)),
        #("values", json.array([], fn(value) { json.string(value) })),
      ])
  }
}

fn expression_unit_json(value: Expression) -> Json {
  case value {
    calculation.Calculated(operation_id, _, _, _, currency, unit, _, _) ->
      json.object([
        #("operation_id", json.string(operation_id)),
        #("currency", json.string(currency)),
        #("unit", json.string(unit)),
      ])
    calculation.Unperformed(operation_id, _, _, _) ->
      json.object([#("operation_id", json.string(operation_id))])
  }
}

fn bound_json(value: Bound) -> Json {
  json.object([
    #("bound_id", json.string(bound.bound_id(value))),
    #("formula_variant", json.string(bound.formula_variant(value))),
    #("raw_decimal", expression_json(bound.raw(value))),
    #("whole_share", projection_json(bound.whole_share_projection(value))),
    #("grid_projected", projection_json(bound.grid_projection(value))),
  ])
}

fn projection_json(value: Projection) -> Json {
  case value {
    bound.Projected(quantity, minimum, increment, policy) ->
      json.object([
        #("state", json.string("projected")),
        #("quantity", json.int(quantity)),
        #("minimum", json.int(minimum)),
        #("increment", json.int(increment)),
        #("policy", json.string(projection_policy_name(policy))),
      ])
    bound.ProjectionUnperformed(reason) ->
      json.object([
        #("state", json.string("unperformed")),
        #("reason", json.string(reason)),
      ])
  }
}

fn intersection_json(value: Intersection) -> Json {
  let state = case bound.intersection_value(value) {
    bound.IntersectionCalculated(quantity, tightest) ->
      json.object([
        #("state", json.string("calculated")),
        #("quantity", json.int(quantity)),
        #("tightest_bound_ids", json.array(tightest, json.string)),
      ])
    bound.IntersectionUnperformed(reason) ->
      json.object([
        #("state", json.string("unperformed")),
        #("reason", json.string(reason)),
      ])
  }
  json.object([
    #("operation_id", json.string(bound.intersection_operation_id(value))),
    #(
      "selected_bound_ids",
      json.array(bound.selected_bound_ids(value), json.string),
    ),
    #("value", state),
  ])
}

fn heat_json(value: Heat) -> Json {
  json.object([
    #("operation_id", json.string(heat.operation_id(value))),
    #("formula_variant", json.string(heat.formula_variant(value))),
    #("currency", json.string(heat.currency(value))),
    #(
      "contributions",
      value
        |> heat.contributions
        |> json.array(fn(contribution) {
          json.object([
            #(
              "position_id",
              contribution |> heat.contribution_position_id |> json.string,
            ),
            #(
              "expression",
              contribution |> heat.contribution_expression |> expression_json,
            ),
          ])
        }),
    ),
    #("total", expression_json(heat.total(value))),
  ])
}

fn cost_json(value: Estimate) -> Json {
  json.object([
    #("operation_id", json.string(cost.operation_id(value))),
    #("side", json.string(side_name(cost.estimate_side(value)))),
    #("currency", json.string(cost.currency(value))),
    #(
      "components",
      value
        |> cost.components
        |> json.array(fn(component) {
          json.object([
            #("component_id", json.string(cost.component_id(component))),
            #("side", json.string(side_name(cost.component_side(component)))),
            #(
              "expression",
              component |> cost.component_expression |> expression_json,
            ),
          ])
        }),
    ),
    #("known_subtotal", expression_json(cost.known_subtotal(value))),
    #("total", expression_json(cost.total(value))),
  ])
}

fn result_expressions(value: ResultItem) -> List(Expression) {
  case value {
    ExpressionResult(expression) -> [expression]
    BoundResult(bound) -> [bound.raw(bound)]
    IntersectionResult(_) -> []
    HeatResult(heat) -> [
      heat.total(heat),
      ..heat.contributions(heat)
      |> list.map(heat.contribution_expression)
    ]
    CostResult(estimate) -> [
      cost.total(estimate),
      cost.known_subtotal(estimate),
      ..cost.components(estimate)
      |> list.map(cost.component_expression)
    ]
  }
}

fn result_operation_id(value: ResultItem) -> String {
  case value {
    ExpressionResult(expression) -> calculation.operation_id(expression)
    BoundResult(bound) -> bound.bound_id(bound)
    IntersectionResult(intersection) ->
      bound.intersection_operation_id(intersection)
    HeatResult(heat) -> heat.operation_id(heat)
    CostResult(estimate) -> cost.operation_id(estimate)
  }
}

fn validate_result_ids(
  request_value: Request,
  result_values: List(ResultItem),
) -> Result(Nil, ReceiptError) {
  let requested =
    request.operations(request_value) |> list.map(request.operation_id)
  case result_values {
    [] -> Ok(Nil)
    [first, ..rest] -> {
      let id = result_operation_id(first)
      case list.contains(requested, id) {
        True -> validate_result_ids(request_value, rest)
        False -> Error(ResultNotRequested(id))
      }
    }
  }
}

fn expression_is_calculated(value: Expression) -> Bool {
  case value {
    calculation.Calculated(_, _, _, _, _, _, _, _) -> True
    calculation.Unperformed(_, _, _, _) -> False
  }
}

fn inputs_by_state(values: List(InputReference), state: String) -> Json {
  values
  |> list.filter(fn(value) { value.state == state })
  |> json.array(input_json)
}

fn rounding_json(value: calculation.RoundingSpec) -> Json {
  json.object([
    #("output_scale", json.int(calculation.output_scale(value))),
    #("intermediate_scale", json.int(calculation.intermediate_scale(value))),
    #(
      "rounding_mode",
      value |> calculation.rounding_mode |> rounding_mode_name |> json.string,
    ),
    #("rounding_policy", json.string("final_only")),
  ])
}

fn projection_policy_name(value: bound.ProjectionPolicy) -> String {
  case value {
    bound.FloorToIncrement -> "floor_to_increment"
  }
}

fn currency_policy_name(value: request.CurrencyPolicy) -> String {
  case value {
    request.NativeCurrency -> "native"
  }
}

fn branch_policy_json(value: request.BranchPolicy) -> Json {
  case value {
    request.AllBranches -> json.object([#("kind", json.string("all_branches"))])
    request.SelectedBranch(branch_id, instruction_ref) ->
      json.object([
        #("kind", json.string("selected_branch")),
        #("branch_id", json.string(branch_id)),
        #(
          "instruction_ref",
          instruction_ref |> identity.sha256_value |> json.string,
        ),
      ])
  }
}

fn rounding_mode_name(value: decimal.RoundingMode) -> String {
  case value {
    decimal.TowardZero -> "toward_zero"
    decimal.AwayFromZero -> "away_from_zero"
    decimal.HalfUp -> "half_up"
    decimal.HalfEven -> "half_even"
  }
}

fn side_name(value: cost.Side) -> String {
  case value {
    cost.Buy -> "buy"
    cost.Sell -> "sell"
  }
}

fn roots_json(values: List(identity.EvidenceId)) -> Json {
  values
  |> list.map(identity.evidence_id_value)
  |> json.array(json.string)
}
