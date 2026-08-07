import finance_core/currency
import finance_core/decimal
import finance_core/time
import finance_provenance/identity
import finance_risk/bound
import finance_risk/calculation
import finance_risk/fact
import finance_risk/receipt
import finance_risk/request
import finance_track
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import pi_sparkles_trade_plan/decode

pub opaque type Response {
  Response(summary: String, details: Json)
}

pub type DomainError {
  InvalidField(field: String, reason: String)
  CoreFailure(operation: String, reason: String)
}

type OutputProjection {
  Compact
  Receipt
}

type PreparedCommon {
  PreparedCommon(
    instruction_ref: identity.Sha256,
    context: request.Context,
    rounding: calculation.RoundingSpec,
    branch_policy: request.BranchPolicy,
    budgets: request.ExecutionBudgets,
    projection: OutputProjection,
  )
}

type PreparedDenominator {
  PreparedDenominator(
    expression: calculation.Expression,
    inputs: List(request.InputReference),
    input_ids: List(String),
    parameters: List(#(String, String)),
  )
}

type PreparedBound {
  PreparedBound(
    value: bound.Bound,
    operation: request.OperationSpec,
    inputs: List(request.InputReference),
  )
}

const maximum_bounds = 50

pub fn summary(value: Response) -> String {
  value.summary
}

pub fn details(value: Response) -> Json {
  value.details
}

pub fn error_message(value: DomainError) -> String {
  case value {
    InvalidField(field, reason) ->
      "Invalid explicit trade-plan field " <> field <> ": " <> reason
    CoreFailure(operation, reason) ->
      "Requested trade-plan calculation "
      <> operation
      <> " could not be represented: "
      <> reason
  }
}

pub fn run_loss(value: decode.LossInput) -> Result(Response, DomainError) {
  use common <- result.try(prepare_common(value.common))
  use _ <- result.try(trimmed("operationId", value.operation_id))
  use entry <- result.try(decimal_fact("entry", value.entry))
  use stop <- result.try(decimal_fact("stop", value.stop))
  use operation <- result.try(
    operation(
      value.operation_id,
      "long_planned_loss_per_unit_v1",
      [],
      common.instruction_ref,
      ["entry", "stop"],
    ),
  )
  let expression =
    calculation.planned_loss_per_unit(
      value.operation_id,
      entry,
      stop,
      common.rounding,
    )
  finish(
    common,
    "plan_loss",
    [operation],
    [
      request.input_reference("entry", entry),
      request.input_reference("stop", stop),
    ],
    [],
    [],
    [receipt.ExpressionResult(expression)],
    json.object([
      #("plannedLoss", expression_json(expression)),
      #(
        "inputFacts",
        json.object([
          #("entry", decimal_fact_input_json(value.entry)),
          #("stop", decimal_fact_input_json(value.stop)),
        ]),
      ),
    ]),
    "Returned the exact requested long planned-loss expression",
  )
}

pub fn run_bounds(value: decode.BoundsInput) -> Result(Response, DomainError) {
  use common <- result.try(prepare_common(value.common))
  use _ <- result.try(list_count("bounds", value.bounds, 1, maximum_bounds))
  use _ <- result.try(unique_bound_ids(value.bounds))
  use trade_unit <- result.try(trade_unit_fact("tradeUnit", value.trade_unit))
  use prepared <- result.try(
    list.try_map(value.bounds, fn(item) {
      prepare_bound(item, trade_unit, common)
    }),
  )
  use intersection <- result.try(prepare_intersection(
    value.intersection,
    prepared,
    common.instruction_ref,
  ))
  let base_operations = list.map(prepared, fn(value) { value.operation })
  let base_inputs = prepared |> list.flat_map(fn(value) { value.inputs })
  let base_results =
    prepared |> list.map(fn(value) { receipt.BoundResult(value.value) })
  let #(operations, results, intersection_json_value) = case intersection {
    None -> #(base_operations, base_results, json.null())
    Some(#(operation, value)) -> #(
      list.append(base_operations, [operation]),
      list.append(base_results, [receipt.IntersectionResult(value)]),
      intersection_json(value),
    )
  }
  finish(
    common,
    "plan_bounds",
    operations,
    list.append(base_inputs, [request.input_reference("trade_unit", trade_unit)]),
    list.map(value.bounds, fn(value) { value.bound_id }),
    [],
    results,
    json.object([
      #(
        "bounds",
        prepared
          |> list.map(fn(value) { value.value })
          |> json.array(bound_json),
      ),
      #("requestedIntersection", intersection_json_value),
      #(
        "inputFacts",
        json.object([
          #("bounds", json.array(value.bounds, bound_input_facts_json)),
          #("tradeUnit", trade_unit_fact_input_json(value.trade_unit)),
        ]),
      ),
    ]),
    "Returned every independently requested quantity bound",
  )
}

pub fn run_grid(value: decode.GridInput) -> Result(Response, DomainError) {
  use common <- result.try(prepare_common(value.common))
  use trade_unit <- result.try(trade_unit_fact("tradeUnit", value.trade_unit))
  use prepared <- result.try(prepare_bound(value.bound, trade_unit, common))
  finish(
    common,
    "plan_grid_projection",
    [prepared.operation],
    list.append(prepared.inputs, [
      request.input_reference("trade_unit", trade_unit),
    ]),
    [value.bound.bound_id],
    [],
    [receipt.BoundResult(prepared.value)],
    json.object([
      #("bound", bound_json(prepared.value)),
      #(
        "inputFacts",
        json.object([
          #("bound", bound_input_facts_json(value.bound)),
          #("tradeUnit", trade_unit_fact_input_json(value.trade_unit)),
        ]),
      ),
    ]),
    "Returned the one explicitly supplied bound and supplied-grid projection",
  )
}

fn prepare_common(
  value: decode.CommonInput,
) -> Result(PreparedCommon, DomainError) {
  use instruction_ref <- result.try(sha(
    "common.context.instructionRef",
    value.context.instruction_ref,
  ))
  use track <- result.try(track(value.context.track))
  use as_of <- result.try(instant(
    "common.context.asOfUnixMilliseconds",
    value.context.as_of_unix_ms,
  ))
  use _ <- result.try(
    currency.from_code(value.context.native_currency)
    |> result.map_error(fn(_) {
      InvalidField(
        "common.context.nativeCurrency",
        "expected a three-letter currency code",
      )
    }),
  )
  use roots <- result.try(
    list.try_map(value.context.evidence_roots, fn(value) {
      use digest <- result.try(sha("common.context.evidenceRoots[]", value))
      Ok(identity.evidence_id(digest))
    }),
  )
  use context <- result.try(
    request.context(
      value.context.account_scope,
      value.context.portfolio_scope,
      track,
      value.context.listing_id,
      as_of,
      value.context.native_currency,
      roots,
    )
    |> result.map_error(fn(error) {
      InvalidField("common.context", string.inspect(error))
    }),
  )
  use rounding <- result.try(rounding(value.rounding))
  use branch_policy <- result.try(branch_policy(value.branch_policy))
  use _ <- result.try(integer_range(
    "common.maximumOperations",
    value.maximum_operations,
    1,
    100,
  ))
  use _ <- result.try(integer_range(
    "common.maximumOutputs",
    value.maximum_outputs,
    1,
    100,
  ))
  use projection <- result.try(output_projection(value.projection))
  Ok(PreparedCommon(
    instruction_ref,
    context,
    rounding,
    branch_policy,
    request.ExecutionBudgets(value.maximum_outputs, value.maximum_operations),
    projection,
  ))
}

fn prepare_bound(
  value: decode.BoundInput,
  trade_unit: fact.Fact(bound.TradeUnit),
  common: PreparedCommon,
) -> Result(PreparedBound, DomainError) {
  use _ <- result.try(trimmed("bounds[].boundId", value.bound_id))
  use _ <- result.try(bound_formula(value.formula_variant))
  use _ <- result.try(trimmed("bounds[].numeratorName", value.numerator_name))
  let prefix = "bound:" <> value.bound_id <> ":"
  use numerator <- result.try(decimal_fact(
    "bounds[].numerator",
    value.numerator,
  ))
  use denominator <- result.try(denominator(
    prefix,
    value.denominator,
    common.rounding,
  ))
  let numerator_id = prefix <> "numerator"
  let trade_unit_id = "trade_unit"
  let input_ids =
    [numerator_id, ..denominator.input_ids] |> list.append([trade_unit_id])
  let parameters = [
    #("denominator_kind", value.denominator.kind),
    #("numerator_name", value.numerator_name),
    ..denominator.parameters
  ]
  use operation <- result.try(operation(
    value.bound_id,
    value.formula_variant,
    parameters,
    common.instruction_ref,
    input_ids,
  ))
  let calculated =
    bound.quantity_bound(
      value.bound_id,
      value.formula_variant,
      value.numerator_name,
      numerator,
      denominator.expression,
      trade_unit,
      common.rounding,
    )
  Ok(
    PreparedBound(calculated, operation, [
      request.input_reference(numerator_id, numerator),
      ..denominator.inputs
    ]),
  )
}

fn denominator(
  prefix: String,
  value: decode.DenominatorInput,
  rounding: calculation.RoundingSpec,
) -> Result(PreparedDenominator, DomainError) {
  case
    value.kind,
    value.operand_name,
    value.formula_variant,
    value.output_unit,
    value.value,
    value.entry,
    value.stop
  {
    "long_planned_loss_per_unit_v1",
      None,
      None,
      None,
      None,
      Some(entry),
      Some(stop)
    -> {
      use entry <- result.try(decimal_fact("bounds[].denominator.entry", entry))
      use stop <- result.try(decimal_fact("bounds[].denominator.stop", stop))
      let entry_id = prefix <> "entry"
      let stop_id = prefix <> "stop"
      Ok(
        PreparedDenominator(
          calculation.planned_loss_per_unit(
            prefix <> "denominator",
            entry,
            stop,
            rounding,
          ),
          [
            request.input_reference(entry_id, entry),
            request.input_reference(stop_id, stop),
          ],
          [entry_id, stop_id],
          [#("denominator_formula", "long_planned_loss_per_unit_v1")],
        ),
      )
    }
    "supplied_denominator_v1",
      Some(name),
      Some(formula),
      Some(unit),
      Some(input),
      None,
      None
    -> {
      use _ <- result.try(trimmed("bounds[].denominator.operandName", name))
      use _ <- result.try(denominator_formula(formula))
      use _ <- result.try(trimmed("bounds[].denominator.outputUnit", unit))
      use value <- result.try(decimal_fact("bounds[].denominator.value", input))
      let id = prefix <> "denominator"
      Ok(
        PreparedDenominator(
          calculation.fact_value(id, formula, name, value, unit, rounding),
          [request.input_reference(id, value)],
          [id],
          [
            #("denominator_formula", formula),
            #("denominator_operand", name),
            #("denominator_output_unit", unit),
          ],
        ),
      )
    }
    _, _, _, _, _, _, _ ->
      Error(InvalidField(
        "bounds[].denominator",
        "variant must supply exactly the fields required by its kind",
      ))
  }
}

fn prepare_intersection(
  value: decode.IntersectionInput,
  bounds: List(PreparedBound),
  instruction_ref: identity.Sha256,
) -> Result(Option(#(request.OperationSpec, bound.Intersection)), DomainError) {
  case value.state, value.operation_id, value.selected_bound_ids {
    "not_requested", None, [] -> Ok(None)
    "requested", Some(operation_id), ids -> {
      use _ <- result.try(trimmed("intersection.operationId", operation_id))
      use _ <- result.try(list_count(
        "intersection.selectedBoundIds",
        ids,
        1,
        maximum_bounds,
      ))
      use _ <- result.try(unique_strings("intersection.selectedBoundIds", ids))
      use selected <- result.try(
        list.try_map(ids, fn(id) {
          case
            list.find(bounds, fn(value) { bound.bound_id(value.value) == id })
          {
            Ok(value) -> Ok(value.value)
            Error(_) ->
              Error(InvalidField(
                "intersection.selectedBoundIds",
                "every selected ID must name a bound in the same request",
              ))
          }
        }),
      )
      use operation <- result.try(
        operation(
          operation_id,
          "requested_grid_intersection_v1",
          [#("selected_bound_ids", string.join(ids, with: ","))],
          instruction_ref,
          [],
        ),
      )
      Ok(
        Some(#(operation, bound.requested_intersection(operation_id, selected))),
      )
    }
    _, _, _ ->
      Error(InvalidField(
        "intersection",
        "not_requested forbids fields; requested requires operationId and selectedBoundIds",
      ))
  }
}

fn finish(
  common: PreparedCommon,
  tool_operation: String,
  operations: List(request.OperationSpec),
  inputs: List(request.InputReference),
  selected_budget_ids: List(String),
  aggregation_policies: List(String),
  results: List(receipt.ResultItem),
  compact_result: Json,
  summary: String,
) -> Result(Response, DomainError) {
  use request_value <- result.try(
    request.request(
      common.instruction_ref,
      common.context,
      operations,
      inputs,
      selected_budget_ids,
      [],
      [],
      bound.FloorToIncrement,
      common.rounding,
      request.NativeCurrency,
      common.branch_policy,
      aggregation_policies,
      [],
      common.budgets,
      available_operations(),
    )
    |> result.map_error(fn(error) {
      CoreFailure(tool_operation, string.inspect(error))
    }),
  )
  use request_receipt <- result.try(
    receipt.request_receipt(request_value)
    |> result.map_error(fn(error) {
      CoreFailure(tool_operation, string.inspect(error))
    }),
  )
  use semantic_receipt <- result.try(
    receipt.semantic_result_receipt(request_value, results)
    |> result.map_error(fn(error) {
      CoreFailure(tool_operation, string.inspect(error))
    }),
  )
  let expressions = result_expressions(results)
  let request_handle =
    request_receipt |> receipt.canonical_content_hash |> identity.sha256_value
  let semantic_handle =
    semantic_receipt |> receipt.canonical_content_hash |> identity.sha256_value
  let receipt_fields = case common.projection {
    Compact -> []
    Receipt -> [
      #("requestReceiptEnvelope", json.string(receipt.encode(request_receipt))),
      #(
        "semanticReceiptEnvelope",
        json.string(receipt.encode(semantic_receipt)),
      ),
    ]
  }
  Ok(Response(
    summary,
    json.object(list.append(
      [
        #("schemaVersion", json.int(1)),
        #("operation", json.string(tool_operation)),
        #("context", context_json(common.context)),
        #("rounding", rounding_json(common.rounding)),
        #("branchPolicy", branch_json(common.branch_policy)),
        #(
          "projection",
          json.string(case common.projection {
            Compact -> "compact"
            Receipt -> "receipt"
          }),
        ),
        #("result", compact_result),
        #("counts", counts_json(inputs, expressions)),
        #("requestReceiptHandle", json.string(request_handle)),
        #("semanticReceiptHandle", json.string(semantic_handle)),
        #("receiptEnvelopesIncluded", json.bool(common.projection == Receipt)),
        #(
          "availableOperations",
          json.array(available_operations(), json.string),
        ),
        #("decisionOwner", json.string("llm")),
        #(
          "pluginDecisionFields",
          json.array([], fn(value: String) { json.string(value) }),
        ),
        #(
          "limitations",
          json.array(
            [
              "Arithmetic and receipt hashes do not prove correctness, prudence, source truth, authorization, or professional sufficiency.",
              "Every budget, denominator, constraint, branch, trade-unit fact, intersection, quantity interpretation, and next action remains LLM-selected.",
              "This stateless long-only calculation shell does not fetch accounts, persist plans, predict fills, or submit orders.",
            ],
            json.string,
          ),
        ),
      ],
      receipt_fields,
    )),
  ))
}

fn decimal_fact(
  field_name: String,
  value: decode.DecimalFactInput,
) -> Result(fact.Fact(decimal.Decimal), DomainError) {
  case
    value.state,
    value.value,
    value.source,
    value.reason,
    value.raw,
    value.alternatives
  {
    "known", Some(raw), Some(source_input), None, None, [] -> {
      use parsed <- result.try(parse_decimal(field_name <> ".value", raw))
      use source <- result.try(source(field_name <> ".source", source_input))
      Ok(fact.known(parsed, source))
    }
    "unknown", None, Some(source_input), Some(reason), None, [] -> {
      use source <- result.try(source(field_name <> ".source", source_input))
      use _ <- result.try(trimmed(field_name <> ".reason", reason))
      Ok(fact.Unknown(source, reason))
    }
    "not_obtained", None, Some(source_input), Some(reason), None, [] -> {
      use source <- result.try(source(field_name <> ".source", source_input))
      use _ <- result.try(trimmed(field_name <> ".reason", reason))
      Ok(fact.NotObtained(source, reason))
    }
    "conflicting", None, None, None, None, alternatives -> {
      use _ <- result.try(list_count(
        field_name <> ".alternatives",
        alternatives,
        2,
        20,
      ))
      use parsed <- result.try(
        list.try_map(alternatives, fn(value) {
          use number <- result.try(parse_decimal(
            field_name <> ".alternatives[].value",
            value.value,
          ))
          use source <- result.try(source(
            field_name <> ".alternatives[].source",
            value.source,
          ))
          Ok(fact.Sourced(number, source))
        }),
      )
      fact.conflicting(parsed)
      |> result.map_error(fn(error) {
        InvalidField(field_name, string.inspect(error))
      })
    }
    "decode_failure", None, Some(source_input), Some(reason), Some(raw), [] -> {
      use source <- result.try(source(field_name <> ".source", source_input))
      use _ <- result.try(trimmed(field_name <> ".reason", reason))
      Ok(fact.DecodeFailure(source, raw, reason))
    }
    _, _, _, _, _, _ ->
      Error(InvalidField(
        field_name,
        "fact state must supply exactly its required value/source/reason/raw/alternatives fields",
      ))
  }
}

fn trade_unit_fact(
  field_name: String,
  value: decode.TradeUnitFactInput,
) -> Result(fact.Fact(bound.TradeUnit), DomainError) {
  case
    value.state,
    value.value,
    value.source,
    value.reason,
    value.raw,
    value.alternatives
  {
    "known", Some(raw), Some(source_input), None, None, [] -> {
      use parsed <- result.try(trade_unit(field_name <> ".value", raw))
      use source <- result.try(source(field_name <> ".source", source_input))
      Ok(fact.known(parsed, source))
    }
    "unknown", None, Some(source_input), Some(reason), None, [] -> {
      use source <- result.try(source(field_name <> ".source", source_input))
      use _ <- result.try(trimmed(field_name <> ".reason", reason))
      Ok(fact.Unknown(source, reason))
    }
    "not_obtained", None, Some(source_input), Some(reason), None, [] -> {
      use source <- result.try(source(field_name <> ".source", source_input))
      use _ <- result.try(trimmed(field_name <> ".reason", reason))
      Ok(fact.NotObtained(source, reason))
    }
    "conflicting", None, None, None, None, alternatives -> {
      use _ <- result.try(list_count(
        field_name <> ".alternatives",
        alternatives,
        2,
        20,
      ))
      use parsed <- result.try(
        list.try_map(alternatives, fn(value) {
          use grid <- result.try(trade_unit(
            field_name <> ".alternatives[].value",
            value.value,
          ))
          use source <- result.try(source(
            field_name <> ".alternatives[].source",
            value.source,
          ))
          Ok(fact.Sourced(grid, source))
        }),
      )
      fact.conflicting(parsed)
      |> result.map_error(fn(error) {
        InvalidField(field_name, string.inspect(error))
      })
    }
    "decode_failure", None, Some(source_input), Some(reason), Some(raw), [] -> {
      use source <- result.try(source(field_name <> ".source", source_input))
      use _ <- result.try(trimmed(field_name <> ".reason", reason))
      Ok(fact.DecodeFailure(source, raw, reason))
    }
    _, _, _, _, _, _ ->
      Error(InvalidField(
        field_name,
        "fact state must supply exactly its required value/source/reason/raw/alternatives fields",
      ))
  }
}

fn source(
  field_name: String,
  value: decode.SourceInput,
) -> Result(fact.Source, DomainError) {
  use kind <- result.try(source_kind(field_name <> ".kind", value.kind))
  use reference <- result.try(sha(field_name <> ".reference", value.reference))
  use effective_at <- result.try(instant(
    field_name <> ".effectiveAtUnixMilliseconds",
    value.effective_at_unix_ms,
  ))
  use retrieved_at <- result.try(instant(
    field_name <> ".retrievedAtUnixMilliseconds",
    value.retrieved_at_unix_ms,
  ))
  use _ <- result.try(trimmed(
    field_name <> ".sourceLexeme",
    value.source_lexeme,
  ))
  use _ <- result.try(text_list(
    field_name <> ".retainedAlternatives",
    value.retained_alternatives,
  ))
  fact.source(
    kind,
    reference,
    effective_at,
    retrieved_at,
    value.currency,
    value.unit,
    value.source_lexeme,
    value.scope,
    value.retained_alternatives,
  )
  |> result.map_error(fn(error) {
    InvalidField(field_name, string.inspect(error))
  })
}

fn bound_input_facts_json(value: decode.BoundInput) -> Json {
  json.object([
    #("boundId", json.string(value.bound_id)),
    #("numerator", decimal_fact_input_json(value.numerator)),
    #("denominator", denominator_input_facts_json(value.denominator)),
  ])
}

fn denominator_input_facts_json(value: decode.DenominatorInput) -> Json {
  json.object([
    #("kind", json.string(value.kind)),
    #("value", json.nullable(value.value, decimal_fact_input_json)),
    #("entry", json.nullable(value.entry, decimal_fact_input_json)),
    #("stop", json.nullable(value.stop, decimal_fact_input_json)),
  ])
}

fn decimal_fact_input_json(value: decode.DecimalFactInput) -> Json {
  json.object([
    #("state", json.string(value.state)),
    #("value", json.nullable(value.value, json.string)),
    #("source", json.nullable(value.source, source_input_json)),
    #("reason", json.nullable(value.reason, json.string)),
    #("raw", json.nullable(value.raw, json.string)),
    #(
      "alternatives",
      json.array(value.alternatives, fn(value) {
        json.object([
          #("value", json.string(value.value)),
          #("source", source_input_json(value.source)),
        ])
      }),
    ),
  ])
}

fn trade_unit_fact_input_json(value: decode.TradeUnitFactInput) -> Json {
  json.object([
    #("state", json.string(value.state)),
    #("value", json.nullable(value.value, trade_unit_value_input_json)),
    #("source", json.nullable(value.source, source_input_json)),
    #("reason", json.nullable(value.reason, json.string)),
    #("raw", json.nullable(value.raw, json.string)),
    #(
      "alternatives",
      json.array(value.alternatives, fn(value) {
        json.object([
          #("value", trade_unit_value_input_json(value.value)),
          #("source", source_input_json(value.source)),
        ])
      }),
    ),
  ])
}

fn trade_unit_value_input_json(value: decode.TradeUnitValueInput) -> Json {
  json.object([
    #("minimum", json.int(value.minimum)),
    #("increment", json.int(value.increment)),
  ])
}

fn source_input_json(value: decode.SourceInput) -> Json {
  json.object([
    #("kind", json.string(value.kind)),
    #("reference", json.string(value.reference)),
    #("effectiveAtUnixMilliseconds", json.int(value.effective_at_unix_ms)),
    #("retrievedAtUnixMilliseconds", json.int(value.retrieved_at_unix_ms)),
    #("currency", json.string(value.currency)),
    #("unit", json.string(value.unit)),
    #("sourceLexeme", json.string(value.source_lexeme)),
    #("scope", json.string(value.scope)),
    #(
      "retainedAlternatives",
      json.array(value.retained_alternatives, json.string),
    ),
  ])
}

fn trade_unit(
  field_name: String,
  value: decode.TradeUnitValueInput,
) -> Result(bound.TradeUnit, DomainError) {
  bound.trade_unit(value.minimum, value.increment)
  |> result.map_error(fn(error) {
    InvalidField(field_name, string.inspect(error))
  })
}

fn rounding(
  value: decode.RoundingInput,
) -> Result(calculation.RoundingSpec, DomainError) {
  use _ <- result.try(exact(
    "common.rounding.policy",
    value.policy,
    "final_only",
  ))
  use mode <- result.try(rounding_mode(value.mode))
  use _ <- result.try(integer_range(
    "common.rounding.outputScale",
    value.output_scale,
    0,
    30,
  ))
  use _ <- result.try(integer_range(
    "common.rounding.intermediateScale",
    value.intermediate_scale,
    0,
    30,
  ))
  calculation.rounding(value.output_scale, value.intermediate_scale, mode)
  |> result.map_error(fn(error) {
    InvalidField("common.rounding", string.inspect(error))
  })
}

fn branch_policy(
  value: decode.BranchPolicyInput,
) -> Result(request.BranchPolicy, DomainError) {
  case value.kind, value.branch_id, value.instruction_ref {
    "all_branches", None, None -> Ok(request.AllBranches)
    "selected_branch", Some(branch_id), Some(reference) -> {
      use _ <- result.try(trimmed("common.branchPolicy.branchId", branch_id))
      use digest <- result.try(sha(
        "common.branchPolicy.instructionRef",
        reference,
      ))
      Ok(request.SelectedBranch(branch_id, digest))
    }
    _, _, _ ->
      Error(InvalidField(
        "common.branchPolicy",
        "all_branches forbids branch fields; selected_branch requires branchId and instructionRef",
      ))
  }
}

fn operation(
  id: String,
  formula: String,
  parameters: List(#(String, String)),
  instruction_ref: identity.Sha256,
  input_ids: List(String),
) -> Result(request.OperationSpec, DomainError) {
  request.operation(id, formula, parameters, instruction_ref, input_ids)
  |> result.map_error(fn(error) {
    InvalidField("operation", string.inspect(error))
  })
}

fn expression_json(value: calculation.Expression) -> Json {
  case value {
    calculation.Calculated(
      operation_id,
      formula_variant,
      _,
      output,
      currency,
      unit,
      operands,
      intermediates,
    ) ->
      json.object([
        #("operationId", json.string(operation_id)),
        #("formulaVariant", json.string(formula_variant)),
        #("state", json.string("calculated")),
        #("value", json.string(output)),
        #("currency", json.string(currency)),
        #("unit", json.string(unit)),
        #("orderedOperands", json.array(operands, operand_json)),
        #("intermediateValues", json.array(intermediates, intermediate_json)),
      ])
    calculation.Unperformed(operation_id, formula_variant, reason, operands) ->
      json.object([
        #("operationId", json.string(operation_id)),
        #("formulaVariant", json.string(formula_variant)),
        #("state", json.string("unperformed")),
        #("reason", json.string(reason)),
        #("orderedOperands", json.array(operands, operand_json)),
      ])
  }
}

fn operand_json(value: calculation.Operand) -> Json {
  json.object([
    #("name", json.string(value.name)),
    #("state", json.string(value.state)),
    #("sourceReferences", json.array(value.source_references, json.string)),
    #("sourceLexemes", json.array(value.source_lexemes, json.string)),
    #("currencies", json.array(value.currencies, json.string)),
    #("units", json.array(value.units, json.string)),
    #(
      "retainedAlternatives",
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

fn bound_json(value: bound.Bound) -> Json {
  json.object([
    #("boundId", json.string(bound.bound_id(value))),
    #("formulaVariant", json.string(bound.formula_variant(value))),
    #("rawDecimal", expression_json(bound.raw(value))),
    #("wholeShare", projection_json(bound.whole_share_projection(value))),
    #("gridProjected", projection_json(bound.grid_projection(value))),
  ])
}

fn projection_json(value: bound.Projection) -> Json {
  case value {
    bound.Projected(quantity, minimum, increment, bound.FloorToIncrement) ->
      json.object([
        #("state", json.string("projected")),
        #("quantity", json.int(quantity)),
        #("minimum", json.int(minimum)),
        #("increment", json.int(increment)),
        #("policy", json.string("floor_to_increment")),
      ])
    bound.ProjectionUnperformed(reason) ->
      json.object([
        #("state", json.string("unperformed")),
        #("reason", json.string(reason)),
      ])
  }
}

fn intersection_json(value: bound.Intersection) -> Json {
  let result = case bound.intersection_value(value) {
    bound.IntersectionCalculated(quantity, tightest) ->
      json.object([
        #("state", json.string("calculated")),
        #("quantity", json.int(quantity)),
        #("tightestBoundIds", json.array(tightest, json.string)),
      ])
    bound.IntersectionUnperformed(reason) ->
      json.object([
        #("state", json.string("unperformed")),
        #("reason", json.string(reason)),
      ])
  }
  json.object([
    #("operationId", json.string(bound.intersection_operation_id(value))),
    #(
      "selectedBoundIds",
      json.array(bound.selected_bound_ids(value), json.string),
    ),
    #("value", result),
  ])
}

fn context_json(value: request.Context) -> Json {
  json.object([
    #("accountScope", json.string(request.account_scope(value))),
    #("portfolioScope", json.string(request.portfolio_scope(value))),
    #(
      "track",
      value |> request.context_track |> finance_track.name |> json.string,
    ),
    #("listingId", json.string(request.listing_id(value))),
    #(
      "asOfUnixMilliseconds",
      value |> request.as_of_time |> time.unix_milliseconds |> json.int,
    ),
    #("nativeCurrency", json.string(request.context_currency(value))),
    #(
      "evidenceRoots",
      value
        |> request.evidence_roots
        |> json.array(fn(id) { json.string(identity.evidence_id_value(id)) }),
    ),
  ])
}

fn rounding_json(value: calculation.RoundingSpec) -> Json {
  json.object([
    #("outputScale", json.int(calculation.output_scale(value))),
    #("intermediateScale", json.int(calculation.intermediate_scale(value))),
    #("mode", json.string(rounding_mode_name(calculation.rounding_mode(value)))),
    #("policy", json.string("final_only")),
  ])
}

fn branch_json(value: request.BranchPolicy) -> Json {
  case value {
    request.AllBranches -> json.object([#("kind", json.string("all_branches"))])
    request.SelectedBranch(branch_id, instruction_ref) ->
      json.object([
        #("kind", json.string("selected_branch")),
        #("branchId", json.string(branch_id)),
        #("instructionRef", json.string(identity.sha256_value(instruction_ref))),
      ])
  }
}

fn counts_json(
  inputs: List(request.InputReference),
  expressions: List(calculation.Expression),
) -> Json {
  json.object([
    #("calculatedExpressions", json.int(count_calculated(expressions))),
    #(
      "unperformedExpressions",
      json.int(list.length(expressions) - count_calculated(expressions)),
    ),
    #("unknownInputs", json.int(count_state(inputs, "unknown"))),
    #("notObtainedInputs", json.int(count_state(inputs, "not_obtained"))),
    #("conflictingInputs", json.int(count_state(inputs, "conflicting"))),
    #("decodeFailureInputs", json.int(count_state(inputs, "decode_failure"))),
  ])
}

fn result_expressions(
  values: List(receipt.ResultItem),
) -> List(calculation.Expression) {
  values
  |> list.filter_map(fn(value) {
    case value {
      receipt.ExpressionResult(value) -> Ok(value)
      receipt.BoundResult(value) -> Ok(bound.raw(value))
      _ -> Error(Nil)
    }
  })
}

fn count_calculated(values: List(calculation.Expression)) -> Int {
  values
  |> list.filter(fn(value) {
    case value {
      calculation.Calculated(_, _, _, _, _, _, _, _) -> True
      calculation.Unperformed(_, _, _, _) -> False
    }
  })
  |> list.length
}

fn count_state(values: List(request.InputReference), state: String) -> Int {
  values |> list.filter(fn(value) { value.state == state }) |> list.length
}

fn available_operations() -> List(String) {
  ["plan_loss", "plan_bounds", "plan_grid_projection"]
}

fn output_projection(value: String) -> Result(OutputProjection, DomainError) {
  case value {
    "compact" -> Ok(Compact)
    "receipt" -> Ok(Receipt)
    _ -> Error(InvalidField("common.projection", "expected compact or receipt"))
  }
}

fn source_kind(
  field_name: String,
  value: String,
) -> Result(fact.SourceKind, DomainError) {
  case value {
    "provider_observation" -> Ok(fact.ProviderObservation)
    "market_rule" -> Ok(fact.MarketRule)
    "custodian_observation" -> Ok(fact.CustodianObservation)
    "caller_declared" -> Ok(fact.CallerDeclared)
    "llm_instruction" -> Ok(fact.LlmInstruction)
    "calculated" -> Ok(fact.Calculated)
    _ -> Error(InvalidField(field_name, "unsupported explicit source kind"))
  }
}

fn track(value: String) -> Result(finance_track.Track, DomainError) {
  case value {
    "cn" -> Ok(finance_track.Cn)
    "hk" -> Ok(finance_track.Hk)
    "us" -> Ok(finance_track.Us)
    _ -> InvalidField("common.context.track", "expected cn, hk, or us") |> Error
  }
}

fn rounding_mode(value: String) -> Result(decimal.RoundingMode, DomainError) {
  case value {
    "toward_zero" -> Ok(decimal.TowardZero)
    "away_from_zero" -> Ok(decimal.AwayFromZero)
    "half_up" -> Ok(decimal.HalfUp)
    "half_even" -> Ok(decimal.HalfEven)
    _ ->
      Error(InvalidField(
        "common.rounding.mode",
        "unsupported explicit rounding mode",
      ))
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

fn bound_formula(value: String) -> Result(Nil, DomainError) {
  case
    list.contains(
      [
        "stop_budget_bound_v1",
        "gap_budget_bound_v1",
        "notional_ceiling_bound_v1",
        "cash_ceiling_bound_v1",
        "buying_power_ceiling_bound_v1",
        "portfolio_heat_bound_v1",
        "fee_inclusive_bound_v1",
        "concentration_bound_v1",
        "leverage_bound_v1",
        "liquidity_bound_v1",
        "declared_amount_bound_v1",
        "user_defined_bound_v1",
      ],
      value,
    )
  {
    True -> Ok(Nil)
    False ->
      Error(InvalidField(
        "bounds[].formulaVariant",
        "unsupported explicit amount-over-denominator formula",
      ))
  }
}

fn denominator_formula(value: String) -> Result(Nil, DomainError) {
  case
    list.contains(
      [
        "desired_entry_value_v1",
        "gap_loss_per_unit_supplied_v1",
        "supplied_loss_per_unit_v1",
        "supplied_denominator_v1",
      ],
      value,
    )
  {
    True -> Ok(Nil)
    False ->
      Error(InvalidField(
        "bounds[].denominator.formulaVariant",
        "unsupported supplied denominator formula",
      ))
  }
}

fn unique_bound_ids(
  values: List(decode.BoundInput),
) -> Result(Nil, DomainError) {
  unique_strings(
    "bounds[].boundId",
    list.map(values, fn(value) { value.bound_id }),
  )
}

fn unique_strings(
  field_name: String,
  values: List(String),
) -> Result(Nil, DomainError) {
  case values {
    [] -> Ok(Nil)
    [first, ..rest] ->
      case list.contains(rest, first) {
        True ->
          Error(InvalidField(field_name, "duplicate values are not allowed"))
        False -> unique_strings(field_name, rest)
      }
  }
}

fn sha(
  field_name: String,
  value: String,
) -> Result(identity.Sha256, DomainError) {
  identity.sha256(value)
  |> result.map_error(fn(_) {
    InvalidField(field_name, "expected an exact SHA-256 hexadecimal string")
  })
}

fn instant(
  field_name: String,
  value: Int,
) -> Result(time.Instant, DomainError) {
  time.instant(value)
  |> result.map_error(fn(_) {
    InvalidField(field_name, "instant is outside the supported range")
  })
}

fn parse_decimal(
  field_name: String,
  value: String,
) -> Result(decimal.Decimal, DomainError) {
  decimal.parse(value)
  |> result.map_error(fn(_) {
    InvalidField(field_name, "expected an exact decimal string")
  })
}

fn exact(
  field_name: String,
  actual: String,
  expected: String,
) -> Result(Nil, DomainError) {
  case actual == expected {
    True -> Ok(Nil)
    False ->
      Error(InvalidField(field_name, "first slice requires " <> expected))
  }
}

fn integer_range(
  field_name: String,
  value: Int,
  minimum: Int,
  maximum: Int,
) -> Result(Nil, DomainError) {
  case value >= minimum && value <= maximum {
    True -> Ok(Nil)
    False ->
      Error(InvalidField(
        field_name,
        "expected an integer from "
          <> int.to_string(minimum)
          <> " through "
          <> int.to_string(maximum),
      ))
  }
}

fn list_count(
  field_name: String,
  values: List(value),
  minimum: Int,
  maximum: Int,
) -> Result(Nil, DomainError) {
  integer_range(field_name, list.length(values), minimum, maximum)
}

fn trimmed(field_name: String, value: String) -> Result(Nil, DomainError) {
  case value != "" && string.trim(value) == value {
    True -> Ok(Nil)
    False -> Error(InvalidField(field_name, "expected trimmed non-empty text"))
  }
}

fn text_list(
  field_name: String,
  values: List(String),
) -> Result(Nil, DomainError) {
  list.try_each(values, fn(value) { trimmed(field_name <> "[]", value) })
}
