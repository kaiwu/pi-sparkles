import finance_core/decimal
import finance_core/time
import finance_execution/calculation.{type CostResult, type Expression}
import finance_execution/capability.{type Capability}
import finance_execution/fact.{type Fact}
import finance_execution/fill.{type Aggregate, type Fill}
import finance_execution/instruction.{type DesiredInstruction}
import finance_execution/lifecycle.{type Projection}
import finance_execution/request.{type InputReference, type Request}
import finance_execution/session.{type Comparison}
import finance_execution/simulation.{type BranchResult, type SweepResult}
import finance_provenance/hash
import finance_provenance/identity.{type Sha256}
import finance_track
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub const request_schema_version = 1

pub const semantic_schema_version = 1

pub const implementation_version = "finance_execution/0.1.0"

pub opaque type Envelope {
  Envelope(payload: Json, canonical_content_hash: Sha256)
}

pub type ResultItem {
  CapabilityResult(
    operation_id: String,
    fact_id: String,
    value: Fact(Capability),
  )
  SweepResult(operation_id: String, value: SweepResult)
  BranchResult(operation_id: String, value: BranchResult)
  LifecycleResult(operation_id: String, value: Projection)
  FillAggregateResult(operation_id: String, value: Aggregate)
  CalculationResult(value: Expression)
  CostCalculationResult(value: CostResult)
  SessionComparisonResult(operation_id: String, value: Comparison)
}

pub type ReceiptError {
  HashFailure
  TooManyResults(received: Int, maximum: Int)
  TooManyEvents(received: Int, maximum: Int)
  TooManyFills(received: Int, maximum: Int)
  TooManyBranches(received: Int, maximum: Int)
  ResultNotRequested(operation_id: String)
}

pub fn request_receipt(value: Request) -> Result(Envelope, ReceiptError) {
  envelope(request_payload(value))
}

pub fn semantic_result_receipt(
  request request_value: Request,
  results result_values: List(ResultItem),
) -> Result(Envelope, ReceiptError) {
  use _ <- result.try(validate_result_budgets(request_value, result_values))
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
  let desired = request.desired_instruction(value)
  let references = request.references(value)
  let budgets = request.budgets(value)
  let request.ReferenceSet(
    capability_references,
    rule_references,
    calendar_references,
    market_event_references,
    lifecycle_references,
    position_references,
    risk_receipt_references,
    cost_receipt_references,
    fx_receipts,
  ) = references
  json.object([
    #("schema", json.string("pi-sparkles/execution-information-request")),
    #("schema_version", json.int(request_schema_version)),
    #(
      "instruction_receipt_hash",
      desired
        |> instruction.instruction_receipt
        |> identity.sha256_value
        |> json.string,
    ),
    #("desired_instruction", desired_instruction_json(desired)),
    #(
      "ordered_operation_ids",
      value
        |> request.ordered_operations
        |> list.map(request.operation_id)
        |> json.array(json.string),
    ),
    #(
      "formula_model_variants",
      json.array(request.ordered_operations(value), operation_json),
    ),
    #("account_scope", json.string(instruction.account_scope(desired))),
    #(
      "track",
      desired |> instruction.track |> finance_track.name |> json.string,
    ),
    #("listing_id", json.string(instruction.listing_id(desired))),
    #("mic", json.string(instruction.mic(desired))),
    #("session_scope", json.string(request.session_scope(value))),
    #("date_time_scope", json.string(request.date_time_scope(value))),
    #("capability_references", hashes_json(capability_references)),
    #("rule_references", hashes_json(rule_references)),
    #("calendar_references", hashes_json(calendar_references)),
    #("market_event_references", hashes_json(market_event_references)),
    #("lifecycle_references", hashes_json(lifecycle_references)),
    #("position_references", hashes_json(position_references)),
    #("risk_receipt_references", hashes_json(risk_receipt_references)),
    #("cost_receipt_references", hashes_json(cost_receipt_references)),
    #("fx_receipts", hashes_json(fx_receipts)),
    #("ordered_input_lexemes", inputs_json(request.ordered_inputs(value))),
    #("simulation_policy", pairs_json(request.simulation_policy(value))),
    #("trigger_policy", pairs_json(request.trigger_policy(value))),
    #("fill_policy", pairs_json(request.fill_policy(value))),
    #("cost_policy", pairs_json(request.cost_policy(value))),
    #("benchmark_policy", pairs_json(request.benchmark_policy(value))),
    #("rounding_policy", rounding_json(request.rounding_policy(value))),
    #("currency_policy", json.string(request.currency_policy(value))),
    #("branch_policy", branch_policy_json(request.branch_policy(value))),
    #(
      "requested_summary_fields",
      json.array(request.requested_summary_fields(value), json.string),
    ),
    #("budgets", budgets_json(budgets)),
    #(
      "available_operations",
      json.array(request.available_operations(value), json.string),
    ),
  ])
}

fn semantic_payload(
  request_value: Request,
  results: List(ResultItem),
  request_hash: Sha256,
  input_hash: Sha256,
) -> Json {
  let inputs = request.ordered_inputs(request_value)
  let desired = request.desired_instruction(request_value)
  let lifecycle_results =
    results
    |> list.filter_map(fn(value) {
      case value {
        LifecycleResult(_, projection) -> Ok(projection)
        _ -> Error(Nil)
      }
    })
  let aggregate_results =
    results
    |> list.filter_map(fn(value) {
      case value {
        FillAggregateResult(_, aggregate) -> Ok(aggregate)
        _ -> Error(Nil)
      }
    })
  let calculations =
    results
    |> list.filter_map(fn(value) {
      case value {
        CalculationResult(expression) -> Ok(expression)
        _ -> Error(Nil)
      }
    })
  json.object([
    #("schema", json.string("pi-sparkles/execution-information-receipt")),
    #("schema_version", json.int(semantic_schema_version)),
    #(
      "request_receipt_hash",
      request_hash |> identity.sha256_value |> json.string,
    ),
    #("implementation_version", json.string(implementation_version)),
    #("input_content_hash", input_hash |> identity.sha256_value |> json.string),
    #("ordered_input_lexemes", inputs_json(inputs)),
    #("selected_models_and_expression_trees", json.array(results, result_json)),
    #("desired_instruction", desired_instruction_json(desired)),
    #(
      "capability_candidates",
      results
        |> list.filter_map(fn(value) {
          case value {
            CapabilityResult(_, fact_id, capability) ->
              Ok(capability_fact_json(fact_id, capability))
            _ -> Error(Nil)
          }
        })
        |> json.array(fn(value) { value }),
    ),
    #("selected_encoding", json.null()),
    #(
      "per_level_simulation_steps",
      results
        |> list.filter_map(fn(value) {
          case value {
            SweepResult(_, sweep) -> Ok(sweep_json(sweep))
            _ -> Error(Nil)
          }
        })
        |> json.array(fn(value) { value }),
    ),
    #(
      "per_event_simulation_steps",
      json.array([], fn(value) { json.string(value) }),
    ),
    #("triggers", json.array([], fn(value) { json.string(value) })),
    #("activations", json.array([], fn(value) { json.string(value) })),
    #(
      "lifecycle_events",
      lifecycle_results
        |> list.flat_map(lifecycle.ordered_events)
        |> json.array(event_json),
    ),
    #(
      "fills",
      lifecycle_results
        |> list.flat_map(lifecycle.ordered_fills)
        |> json.array(fill_json),
    ),
    #(
      "remainders",
      results
        |> list.filter_map(fn(value) {
          case value {
            SweepResult(operation_id, sweep) ->
              Ok(
                json.object([
                  #("operation_id", json.string(operation_id)),
                  #(
                    "remaining_quantity",
                    sweep
                      |> simulation.remaining_quantity
                      |> decimal.to_string
                      |> json.string,
                  ),
                ]),
              )
            _ -> Error(Nil)
          }
        })
        |> json.array(fn(value) { value }),
    ),
    #(
      "branches",
      results
        |> list.filter_map(fn(value) {
          case value {
            BranchResult(operation_id, branches) ->
              Ok(
                json.object([
                  #("operation_id", json.string(operation_id)),
                  #("value", branch_result_json(branches)),
                ]),
              )
            _ -> Error(Nil)
          }
        })
        |> json.array(fn(value) { value }),
    ),
    #("aggregate_calculations", json.array(aggregate_results, aggregate_json)),
    #(
      "cost_calculations",
      results
        |> list.filter_map(fn(value) {
          case value {
            CostCalculationResult(cost) -> Ok(cost)
            _ -> Error(Nil)
          }
        })
        |> json.array(cost_json),
    ),
    #(
      "benchmark_calculations",
      calculations
        |> list.filter(fn(value) {
          let variant = calculation.formula_variant(value)
          string.contains(variant, "shortfall")
          || string.contains(variant, "slippage")
          || string.contains(variant, "spread")
        })
        |> json.array(expression_json),
    ),
    #(
      "latency_calculations",
      calculations
        |> list.filter(fn(value) {
          value |> calculation.formula_variant |> string.contains("latency")
        })
        |> json.array(expression_json),
    ),
    #("unknown_facts", inputs_by_state(inputs, "unknown")),
    #("conflict_facts", inputs_by_state(inputs, "conflicting")),
    #("decode_failure_facts", inputs_by_state(inputs, "decode_failure")),
    #(
      "mechanical_check_facts",
      json.array([], fn(value) { json.string(value) }),
    ),
    #(
      "unperformed_expressions",
      calculations
        |> list.filter(fn(value) {
          case value {
            calculation.Unperformed(_, _, _, _) -> True
            calculation.Calculated(_, _, _, _, _, _, _) -> False
          }
        })
        |> json.array(expression_json),
    ),
    #(
      "retained_alternatives",
      inputs
        |> list.filter(fn(value) { !list.is_empty(value.retained_alternatives) })
        |> json.array(input_json),
    ),
    #(
      "selection_instruction_receipts",
      selection_receipts_json(request.branch_policy(request_value)),
    ),
    #("evidence_roots", evidence_roots_json(lifecycle_results)),
    #(
      "available_operations",
      json.array(request.available_operations(request_value), json.string),
    ),
  ])
}

fn desired_instruction_json(value: DesiredInstruction) -> Json {
  json.object([
    #("instruction_id", json.string(instruction.instruction_id(value))),
    #(
      "instruction_receipt",
      value
        |> instruction.instruction_receipt
        |> identity.sha256_value
        |> json.string,
    ),
    #("track", value |> instruction.track |> finance_track.name |> json.string),
    #("listing_id", json.string(instruction.listing_id(value))),
    #("mic", json.string(instruction.mic(value))),
    #("account_scope", json.string(instruction.account_scope(value))),
    #("currency", json.string(instruction.currency(value))),
    #("side", value |> instruction.side |> instruction.side_name |> json.string),
    #("intent", intent_json(instruction.intent(value))),
    #(
      "quantity",
      value |> instruction.quantity |> decimal.to_string |> json.string,
    ),
    #(
      "quantity_unit",
      value
        |> instruction.quantity_unit
        |> instruction.quantity_unit_name
        |> json.string,
    ),
    #("order_behavior", behavior_json(instruction.order_behavior(value))),
    #(
      "time_in_force",
      value
        |> instruction.time_in_force
        |> instruction.time_in_force_name
        |> json.string,
    ),
    #(
      "requested_session",
      session_option_json(instruction.requested_session(value)),
    ),
    #(
      "activation_time",
      instant_option_json(instruction.activation_time(value)),
    ),
    #("expiry_time", instant_option_json(instruction.expiry_time(value))),
    #("timezone", json.string(instruction.timezone(value))),
    #("rule_references", hashes_json(instruction.rule_references(value))),
    #(
      "capability_references",
      hashes_json(instruction.capability_references(value)),
    ),
    #("account_references", hashes_json(instruction.account_references(value))),
    #(
      "retained_alternatives",
      alternatives_json(instruction.retained_alternatives(value)),
    ),
  ])
}

fn behavior_json(value: instruction.OrderBehavior) -> Json {
  case value {
    instruction.Market -> json.object([#("kind", json.string("market"))])
    instruction.Limit(price) ->
      json.object([
        #("kind", json.string("limit")),
        #("limit_price", price |> decimal.to_string |> json.string),
      ])
    instruction.Stop(trigger, basis) ->
      json.object([
        #("kind", json.string("stop")),
        #("trigger_price", trigger |> decimal.to_string |> json.string),
        #("trigger_basis", trigger_basis_json(basis)),
      ])
    instruction.StopLimit(trigger, basis, limit) ->
      json.object([
        #("kind", json.string("stop_limit")),
        #("trigger_price", trigger |> decimal.to_string |> json.string),
        #("trigger_basis", trigger_basis_json(basis)),
        #("limit_price", limit |> decimal.to_string |> json.string),
      ])
    instruction.Auction(phase) ->
      json.object([
        #("kind", json.string("auction")),
        #("phase", json.string(phase)),
      ])
    instruction.MarketOnClose ->
      json.object([#("kind", json.string("market_on_close"))])
    instruction.LimitOnClose(price) ->
      json.object([
        #("kind", json.string("limit_on_close")),
        #("limit_price", price |> decimal.to_string |> json.string),
      ])
    instruction.TrailingStop(amount, reference, cadence) ->
      json.object([
        #("kind", json.string("trailing_stop")),
        #("amount_or_fraction", amount |> decimal.to_string |> json.string),
        #("reference", json.string(reference)),
        #("cadence", json.string(cadence)),
      ])
  }
}

fn trigger_basis_json(value: instruction.TriggerBasis) -> Json {
  case value {
    instruction.LastSale -> json.string("last_sale")
    instruction.Bid -> json.string("bid")
    instruction.Ask -> json.string("ask")
    instruction.Midpoint -> json.string("midpoint")
    instruction.Mark -> json.string("mark")
    instruction.Index(id) ->
      json.object([#("kind", json.string("index")), #("id", json.string(id))])
    instruction.ProviderDefined(label) ->
      json.object([
        #("kind", json.string("provider_defined")),
        #("label", json.string(label)),
      ])
  }
}

fn result_json(value: ResultItem) -> Json {
  let #(operation_id, kind, result_value) = case value {
    CapabilityResult(id, fact_id, capability) -> #(
      id,
      "capability_fact",
      capability_fact_json(fact_id, capability),
    )
    SweepResult(id, sweep) -> #(id, "visible_depth_sweep", sweep_json(sweep))
    BranchResult(id, branches) -> #(
      id,
      "possible_paths",
      branch_result_json(branches),
    )
    LifecycleResult(id, projection) -> #(
      id,
      "lifecycle",
      lifecycle_json(projection),
    )
    FillAggregateResult(id, aggregate) -> #(
      id,
      "fill_aggregate",
      aggregate_json(aggregate),
    )
    CalculationResult(expression) -> #(
      calculation.operation_id(expression),
      "calculation",
      expression_json(expression),
    )
    CostCalculationResult(cost) -> #(
      calculation.cost_operation_id(cost),
      "cost_calculation",
      cost_json(cost),
    )
    SessionComparisonResult(id, comparison) -> #(
      id,
      "session_comparison",
      session_comparison_json(comparison),
    )
  }
  json.object([
    #("operation_id", json.string(operation_id)),
    #("kind", json.string(kind)),
    #("value", result_value),
  ])
}

fn capability_fact_json(fact_id: String, value: Fact(Capability)) -> Json {
  let details = case fact.known_value(value) {
    Error(reason) -> json.object([#("reason", json.string(reason))])
    Ok(sourced) -> {
      let capability = fact.sourced_value(sourced)
      json.object([
        #("provider_id", json.string(capability.provider_id(capability))),
        #("account_id", json.string(capability.account_id(capability))),
        #(
          "track",
          capability |> capability.track |> finance_track.name |> json.string,
        ),
        #(
          "supported_order_types",
          capability
            |> capability.supported_order_types
            |> json.array(fn(order_type) {
              json.object([
                #("code", json.string(capability.native_code(order_type))),
                #(
                  "required_fields",
                  json.array(
                    capability.required_fields(order_type),
                    json.string,
                  ),
                ),
                #(
                  "optional_fields",
                  json.array(
                    capability.optional_fields(order_type),
                    json.string,
                  ),
                ),
              ])
            }),
        ),
        #(
          "supported_sides",
          capability
            |> capability.supported_sides
            |> list.map(instruction.side_name)
            |> json.array(json.string),
        ),
        #(
          "supported_time_in_force",
          capability
            |> capability.supported_time_in_force
            |> list.map(instruction.time_in_force_name)
            |> json.array(json.string),
        ),
      ])
    }
  }
  json.object([
    #("fact_id", json.string(fact_id)),
    #("state", value |> fact.state_name |> json.string),
    #("details", details),
  ])
}

fn sweep_json(value: SweepResult) -> Json {
  json.object([
    #("model", json.string(simulation.result_model(value))),
    #(
      "result_kind",
      value
        |> simulation.result_kind
        |> simulation.result_kind_name
        |> json.string,
    ),
    #(
      "snapshot_receipt",
      value
        |> simulation.snapshot_receipt
        |> identity.sha256_value
        |> json.string,
    ),
    #(
      "side",
      value |> simulation.sweep_side |> instruction.side_name |> json.string,
    ),
    #(
      "limit_price",
      value |> simulation.limit_price |> decimal.to_string |> json.string,
    ),
    #(
      "price_budget",
      value |> simulation.price_budget |> decimal.to_string |> json.string,
    ),
    #(
      "requested_quantity",
      value |> simulation.requested_quantity |> decimal.to_string |> json.string,
    ),
    #("maximum_depth_levels", json.int(simulation.maximum_depth_levels(value))),
    #("steps", value |> simulation.steps |> json.array(depth_step_json)),
    #(
      "filled_quantity",
      value |> simulation.filled_quantity |> decimal.to_string |> json.string,
    ),
    #(
      "remaining_quantity",
      value |> simulation.remaining_quantity |> decimal.to_string |> json.string,
    ),
    #("fill_notional", json.string(simulation.fill_notional_lexeme(value))),
    #(
      "weighted_fill_price",
      weighted_price_json(simulation.weighted_fill_price(value)),
    ),
    #("depth_exhausted", json.bool(simulation.depth_exhausted(value))),
    #("stopped_by_limit", json.bool(simulation.stopped_by_limit(value))),
    #("stop", value |> simulation.sweep_stop |> sweep_stop_name |> json.string),
  ])
}

fn depth_step_json(value: simulation.DepthStep) -> Json {
  let simulation.DepthStep(
    level_number,
    price,
    price_lexeme,
    displayed_quantity,
    displayed_lexeme,
    filled_quantity,
    remaining_quantity,
    action,
  ) = value
  json.object([
    #("level_number", json.int(level_number)),
    #("price", price |> decimal.to_string |> json.string),
    #("price_lexeme", json.string(price_lexeme)),
    #(
      "displayed_quantity",
      displayed_quantity |> decimal.to_string |> json.string,
    ),
    #("displayed_quantity_lexeme", json.string(displayed_lexeme)),
    #("filled_quantity", filled_quantity |> decimal.to_string |> json.string),
    #(
      "remaining_quantity",
      remaining_quantity |> decimal.to_string |> json.string,
    ),
    #("action", step_action_json(action)),
  ])
}

fn branch_result_json(value: BranchResult) -> Json {
  json.object([
    #("model", json.string(simulation.branch_model(value))),
    #(
      "result_kind",
      value
        |> simulation.branch_result_kind
        |> simulation.result_kind_name
        |> json.string,
    ),
    #("branches", value |> simulation.branches |> json.array(branch_json)),
  ])
}

fn branch_json(value: simulation.SimulationBranch) -> Json {
  let simulation.SimulationBranch(id, outcome, price_range, note) = value
  json.object([
    #("branch_id", json.string(id)),
    #("outcome", outcome |> simulation.branch_outcome_name |> json.string),
    #("compatible_price_range", decimal_range_json(price_range)),
    #("note", json.string(note)),
  ])
}

fn lifecycle_json(value: Projection) -> Json {
  json.object([
    #(
      "ordered_events",
      value |> lifecycle.ordered_events |> json.array(event_json),
    ),
    #("state", value |> lifecycle.state |> lifecycle.state_name |> json.string),
    #(
      "cumulative_filled",
      value |> lifecycle.cumulative_filled |> decimal.to_string |> json.string,
    ),
    #(
      "remaining_quantity",
      value |> lifecycle.remaining_quantity |> decimal.to_string |> json.string,
    ),
    #(
      "fill_after_cancel_request",
      json.bool(lifecycle.fill_after_cancel_request(value)),
    ),
  ])
}

fn event_json(value: lifecycle.Event) -> Json {
  json.object([
    #("event_id", json.string(lifecycle.event_id(value))),
    #(
      "client_instruction_id",
      json.string(lifecycle.client_instruction_id(value)),
    ),
    #(
      "event_time_unix_ms",
      value |> lifecycle.event_time |> time.unix_milliseconds |> json.int,
    ),
    #(
      "source_reference",
      value
        |> lifecycle.source_reference
        |> identity.sha256_value
        |> json.string,
    ),
    #("kind", event_kind_json(lifecycle.event_kind(value))),
  ])
}

fn event_kind_json(value: lifecycle.EventKind) -> Json {
  let base = lifecycle.event_kind_name(value)
  case value {
    lifecycle.BrokerRejected(code, text)
    | lifecycle.ExchangeRejected(code, text)
    | lifecycle.CancelRejected(code, text)
    | lifecycle.ReplaceRejected(code, text) ->
      json.object([
        #("name", json.string(base)),
        #("code", json.string(code)),
        #("text", json.string(text)),
      ])
    lifecycle.PartiallyFilled(fill) ->
      json.object([
        #("name", json.string(base)),
        #("fill", fill_json(fill)),
      ])
    lifecycle.FullyFilled(fills) ->
      json.object([
        #("name", json.string(base)),
        #("fills", json.array(fills, fill_json)),
      ])
    lifecycle.StatusUnknown(reason) ->
      json.object([
        #("name", json.string(base)),
        #("reason", json.string(reason)),
      ])
    _ -> json.object([#("name", json.string(base))])
  }
}

fn fill_json(value: Fill) -> Json {
  json.object([
    #("fill_id", json.string(fill.fill_id(value))),
    #("broker_order_id", string_option_json(fill.broker_order_id(value))),
    #("exchange_order_id", string_option_json(fill.exchange_order_id(value))),
    #("client_instruction_id", json.string(fill.client_instruction_id(value))),
    #("listing_id", json.string(fill.listing_id(value))),
    #("venue_route", json.string(fill.venue_route(value))),
    #("account_id", json.string(fill.account_id(value))),
    #("side", value |> fill.side |> instruction.side_name |> json.string),
    #("quantity", value |> fill.quantity |> decimal.to_string |> json.string),
    #("quantity_lexeme", json.string(fill.quantity_lexeme(value))),
    #("quantity_unit", json.string(fill.quantity_unit(value))),
    #("price", value |> fill.price |> decimal.to_string |> json.string),
    #("price_lexeme", json.string(fill.price_lexeme(value))),
    #("currency", json.string(fill.currency(value))),
    #(
      "retrieval_timestamp_unix_ms",
      value |> fill.retrieval_timestamp |> time.unix_milliseconds |> json.int,
    ),
    #("fill_kind", value |> fill.kind |> fill.fill_kind_name |> json.string),
    #(
      "raw_receipt_hash",
      value |> fill.raw_receipt_hash |> identity.sha256_value |> json.string,
    ),
    #(
      "source_reference",
      value |> fill.source_reference |> identity.sha256_value |> json.string,
    ),
    #("entitlement", json.string(fill.entitlement(value))),
    #("licence", json.string(fill.licence(value))),
    #(
      "evidence_roots",
      value
        |> fill.evidence_roots
        |> list.map(identity.evidence_id_value)
        |> json.array(json.string),
    ),
    #(
      "correction_lineage",
      json.array(fill.correction_lineage(value), json.string),
    ),
    #("bust_lineage", json.array(fill.bust_lineage(value), json.string)),
  ])
}

fn aggregate_json(value: Aggregate) -> Json {
  json.object([
    #("ordered_fills", value |> fill.ordered_fills |> json.array(fill_json)),
    #(
      "cumulative_quantity",
      aggregate_value_json(fill.cumulative_quantity(value)),
    ),
    #("total_notional", aggregate_value_json(fill.total_notional(value))),
    #(
      "weighted_fill_price",
      aggregate_value_json(fill.weighted_fill_price(value)),
    ),
    #("currency", json.string(fill.aggregate_currency(value))),
    #("quantity_unit", json.string(fill.aggregate_quantity_unit(value))),
    #(
      "result_kind",
      value |> fill.aggregate_result_kind |> fill.fill_kind_name |> json.string,
    ),
  ])
}

fn aggregate_value_json(value: fill.AggregateValue) -> Json {
  case value {
    fill.AggregateCalculated(_, lexeme) ->
      json.object([
        #("state", json.string("calculated")),
        #("value", json.string(lexeme)),
      ])
    fill.AggregateUnperformed(reason) ->
      json.object([
        #("state", json.string("unperformed")),
        #("reason", json.string(reason)),
      ])
  }
}

fn expression_json(value: Expression) -> Json {
  case value {
    calculation.Calculated(id, variant, _, lexeme, currency, unit, operands) ->
      json.object([
        #("operation_id", json.string(id)),
        #("formula_variant", json.string(variant)),
        #("state", json.string("calculated")),
        #("value", json.string(lexeme)),
        #("currency", json.string(currency)),
        #("unit", json.string(unit)),
        #("ordered_operands", json.array(operands, operand_json)),
      ])
    calculation.Unperformed(id, variant, reason, operands) ->
      json.object([
        #("operation_id", json.string(id)),
        #("formula_variant", json.string(variant)),
        #("state", json.string("unperformed")),
        #("reason", json.string(reason)),
        #("ordered_operands", json.array(operands, operand_json)),
      ])
  }
}

fn operand_json(value: calculation.Operand) -> Json {
  let calculation.Operand(name, state, references, lexemes, currencies, units) =
    value
  json.object([
    #("name", json.string(name)),
    #("state", json.string(state)),
    #("source_references", json.array(references, json.string)),
    #("source_lexemes", json.array(lexemes, json.string)),
    #("currencies", json.array(currencies, json.string)),
    #("units", json.array(units, json.string)),
  ])
}

fn cost_json(value: CostResult) -> Json {
  json.object([
    #("operation_id", json.string(calculation.cost_operation_id(value))),
    #("known_subtotal", expression_json(calculation.known_subtotal(value))),
    #("total", expression_json(calculation.total_cost(value))),
    #(
      "known_cost_per_quantity",
      expression_json(calculation.known_cost_per_quantity(value)),
    ),
    #(
      "unknown_component_ids",
      json.array(calculation.unknown_component_ids(value), json.string),
    ),
  ])
}

fn session_comparison_json(value: Comparison) -> Json {
  case value {
    session.Compared(timestamp, phase, intervals, in_window) ->
      json.object([
        #("state", json.string("compared")),
        #("timestamp_unix_ms", timestamp |> time.unix_milliseconds |> json.int),
        #("requested_phase", json.string(phase)),
        #(
          "matching_intervals",
          intervals
            |> json.array(fn(interval) {
              let session.PhaseInterval(name, starts, ends, source) = interval
              json.object([
                #("phase", json.string(name)),
                #(
                  "starts_at_unix_ms",
                  starts |> time.unix_milliseconds |> json.int,
                ),
                #("ends_at_unix_ms", ends |> time.unix_milliseconds |> json.int),
                #(
                  "source_reference",
                  source |> identity.sha256_value |> json.string,
                ),
              ])
            }),
        ),
        #("in_window", json.bool(in_window)),
      ])
    session.ComparisonUnperformed(timestamp, phase, reason) ->
      json.object([
        #("state", json.string("unperformed")),
        #("timestamp_unix_ms", timestamp |> time.unix_milliseconds |> json.int),
        #("requested_phase", json.string(phase)),
        #("reason", json.string(reason)),
      ])
  }
}

fn operation_json(value: request.OperationSpec) -> Json {
  json.object([
    #("operation_id", json.string(request.operation_id(value))),
    #(
      "model_or_formula_variant",
      json.string(request.model_or_formula_variant(value)),
    ),
    #("ordered_parameters", pairs_json(request.ordered_parameters(value))),
    #(
      "instruction_reference",
      value
        |> request.operation_instruction_reference
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
    #("source_references", hashes_json(value.source_references)),
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

fn inputs_by_state(values: List(InputReference), state: String) -> Json {
  values
  |> list.filter(fn(value) { value.state == state })
  |> json.array(input_json)
}

fn validate_result_budgets(
  request_value: Request,
  results: List(ResultItem),
) -> Result(Nil, ReceiptError) {
  let budgets = request.budgets(request_value)
  let events =
    results
    |> list.fold(0, fn(total, value) {
      case value {
        LifecycleResult(_, projection) ->
          total + list.length(lifecycle.ordered_events(projection))
        _ -> total
      }
    })
  let fills =
    results
    |> list.fold(0, fn(total, value) {
      case value {
        LifecycleResult(_, projection) ->
          total + list.length(lifecycle.ordered_fills(projection))
        FillAggregateResult(_, aggregate) ->
          total + list.length(fill.ordered_fills(aggregate))
        _ -> total
      }
    })
  let branches =
    results
    |> list.fold(0, fn(total, value) {
      case value {
        BranchResult(_, result) ->
          total + list.length(simulation.branches(result))
        _ -> total
      }
    })
  case
    list.length(results) > request.max_outputs(budgets),
    events > request.max_events(budgets),
    fills > request.max_fills(budgets),
    branches > request.max_branches(budgets)
  {
    True, _, _, _ ->
      Error(TooManyResults(list.length(results), request.max_outputs(budgets)))
    _, True, _, _ -> Error(TooManyEvents(events, request.max_events(budgets)))
    _, _, True, _ -> Error(TooManyFills(fills, request.max_fills(budgets)))
    _, _, _, True ->
      Error(TooManyBranches(branches, request.max_branches(budgets)))
    False, False, False, False -> Ok(Nil)
  }
}

fn validate_result_ids(
  request_value: Request,
  values: List(ResultItem),
) -> Result(Nil, ReceiptError) {
  let requested =
    request.ordered_operations(request_value) |> list.map(request.operation_id)
  case values {
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

fn result_operation_id(value: ResultItem) -> String {
  case value {
    CapabilityResult(id, _, _)
    | SweepResult(id, _)
    | BranchResult(id, _)
    | LifecycleResult(id, _)
    | FillAggregateResult(id, _)
    | SessionComparisonResult(id, _) -> id
    CalculationResult(expression) -> calculation.operation_id(expression)
    CostCalculationResult(cost) -> calculation.cost_operation_id(cost)
  }
}

fn evidence_roots_json(values: List(Projection)) -> Json {
  values
  |> list.flat_map(lifecycle.ordered_fills)
  |> list.flat_map(fill.evidence_roots)
  |> list.map(identity.evidence_id_value)
  |> json.array(json.string)
}

fn pairs_json(values: List(#(String, String))) -> Json {
  values
  |> list.sort(fn(left, right) { string.compare(left.0, right.0) })
  |> json.array(fn(value) {
    json.object([
      #("name", json.string(value.0)),
      #("value", json.string(value.1)),
    ])
  })
}

fn hashes_json(values: List(Sha256)) -> Json {
  values
  |> list.map(identity.sha256_value)
  |> json.array(json.string)
}

fn budgets_json(value: request.Budgets) -> Json {
  json.object([
    #("max_events", json.int(request.max_events(value))),
    #("max_depth_levels", json.int(request.max_depth_levels(value))),
    #("max_branches", json.int(request.max_branches(value))),
    #("max_fills", json.int(request.max_fills(value))),
    #("max_outputs", json.int(request.max_outputs(value))),
    #("max_bytes", json.int(request.max_bytes(value))),
    #("max_operations", json.int(request.max_operations(value))),
  ])
}

fn rounding_json(value: calculation.RoundingSpec) -> Json {
  json.object([
    #("output_scale", json.int(calculation.output_scale(value))),
    #(
      "rounding_mode",
      value |> calculation.rounding_mode |> rounding_mode_name |> json.string,
    ),
  ])
}

fn rounding_mode_name(value: decimal.RoundingMode) -> String {
  case value {
    decimal.TowardZero -> "toward_zero"
    decimal.AwayFromZero -> "away_from_zero"
    decimal.HalfUp -> "half_up"
    decimal.HalfEven -> "half_even"
  }
}

fn branch_policy_json(value: request.BranchPolicy) -> Json {
  case value {
    request.AllBranches -> json.object([#("kind", json.string("all_branches"))])
    request.SelectedBranch(branch_id, reference) ->
      json.object([
        #("kind", json.string("selected_branch")),
        #("branch_id", json.string(branch_id)),
        #(
          "instruction_reference",
          reference |> identity.sha256_value |> json.string,
        ),
      ])
  }
}

fn selection_receipts_json(value: request.BranchPolicy) -> Json {
  case value {
    request.AllBranches -> json.array([], fn(value) { json.string(value) })
    request.SelectedBranch(_, reference) -> hashes_json([reference])
  }
}

fn intent_json(value: Option(instruction.Intent)) -> Json {
  case value {
    None -> json.null()
    Some(instruction.Open) -> json.string("open")
    Some(instruction.Close) -> json.string("close")
    Some(instruction.Reduce) -> json.string("reduce")
  }
}

fn session_option_json(value: Option(instruction.RequestedSession)) -> Json {
  case value {
    None -> json.null()
    Some(instruction.PreOpenAuction) -> json.string("pre_open_auction")
    Some(instruction.Regular) -> json.string("regular")
    Some(instruction.ClosingAuction) -> json.string("closing_auction")
    Some(instruction.Extended) -> json.string("extended")
  }
}

fn instant_option_json(value: Option(time.Instant)) -> Json {
  case value {
    None -> json.null()
    Some(value) -> value |> time.unix_milliseconds |> json.int
  }
}

fn string_option_json(value: Option(String)) -> Json {
  case value {
    None -> json.null()
    Some(value) -> json.string(value)
  }
}

fn alternatives_json(value: instruction.RetainedAlternatives) -> Json {
  case value {
    instruction.KnownAlternatives(values) ->
      json.object([
        #("state", json.string("known")),
        #("values", json.array(values, json.string)),
      ])
    instruction.AlternativesNotApplicable(reason) ->
      json.object([
        #("state", json.string("not_applicable")),
        #("reason", json.string(reason)),
      ])
  }
}

fn weighted_price_json(value: simulation.WeightedPrice) -> Json {
  case value {
    simulation.WeightedPriceCalculated(_, lexeme) ->
      json.object([
        #("state", json.string("calculated")),
        #("value", json.string(lexeme)),
      ])
    simulation.WeightedPriceUnperformed(reason) ->
      json.object([
        #("state", json.string("unperformed")),
        #("reason", json.string(reason)),
      ])
  }
}

fn step_action_json(value: simulation.StepAction) -> Json {
  case value {
    simulation.Consumed -> json.object([#("kind", json.string("consumed"))])
    simulation.Stopped(stop) ->
      json.object([
        #("kind", json.string("stopped")),
        #("reason", stop |> sweep_stop_name |> json.string),
      ])
  }
}

fn sweep_stop_name(value: simulation.SweepStop) -> String {
  case value {
    simulation.QuantitySatisfied -> "quantity_satisfied"
    simulation.LimitConstraint -> "limit_constraint"
    simulation.PriceBudgetConstraint -> "price_budget_constraint"
    simulation.DepthBudgetExhausted -> "depth_budget_exhausted"
    simulation.VisibleSnapshotExhausted -> "visible_snapshot_exhausted"
  }
}

fn decimal_range_json(
  value: Option(#(decimal.Decimal, decimal.Decimal)),
) -> Json {
  case value {
    None -> json.null()
    Some(#(low, high)) ->
      json.array([low, high], fn(value) {
        value |> decimal.to_string |> json.string
      })
  }
}
