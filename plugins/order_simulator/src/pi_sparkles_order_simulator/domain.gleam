import finance_core/currency
import finance_core/decimal
import finance_core/time
import finance_execution/calculation
import finance_execution/fact
import finance_execution/instruction
import finance_execution/receipt
import finance_execution/request
import finance_execution/simulation
import finance_provenance/identity
import finance_track
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import pi_sparkles_order_simulator/decode

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

type PreparedPolicy {
  PreparedPolicy(
    capability_policy: String,
    session_scope: String,
    date_time_scope: String,
    currency_policy: String,
    rounding: calculation.RoundingSpec,
    rounding_mode: decimal.RoundingMode,
    references: request.ReferenceSet,
    budgets: request.Budgets,
    projection: OutputProjection,
    maximum_bytes: Int,
  )
}

type SimulationOutcome {
  Performed(simulation.BranchResult)
  Unperformed(reason: String)
}

pub fn summary(value: Response) -> String {
  value.summary
}

pub fn details(value: Response) -> Json {
  value.details
}

pub fn error_message(value: DomainError) -> String {
  case value {
    InvalidField(field, reason) ->
      "Invalid explicit order-simulation field " <> field <> ": " <> reason
    CoreFailure(operation, reason) ->
      "Requested order simulation "
      <> operation
      <> " could not be represented: "
      <> reason
  }
}

pub fn run(value: decode.SimulationInput) -> Result(Response, DomainError) {
  use _ <- result.try(trimmed("operationId", value.operation_id))
  use desired <- result.try(desired_instruction(value.instruction))
  use bar <- result.try(bar_fact("bar", value.bar))
  use supported <- result.try(bool_fact(
    "desiredOrderSupported",
    value.desired_order_supported,
  ))
  use policy <- result.try(prepare_policy(value.policy))
  use operation <- result.try(
    request.operation(
      value.operation_id,
      simulation.bar_possible_paths_v1,
      [
        #("calculation_policy", "limit_touch_v1"),
        #("capability_policy", policy.capability_policy),
        #(
          "desired_behavior",
          desired |> instruction.order_behavior |> instruction.behavior_name,
        ),
      ],
      instruction.instruction_receipt(desired),
      ["completed_daily_bar", "desired_order_supported"],
    )
    |> result.map_error(fn(error) {
      CoreFailure(value.operation_id, string.inspect(error))
    }),
  )
  let inputs = [
    request.input_reference("completed_daily_bar", bar),
    request.input_reference("desired_order_supported", supported),
  ]
  use request_value <- result.try(
    request.request(
      desired,
      [operation],
      inputs,
      policy.references,
      policy.session_scope,
      policy.date_time_scope,
      [
        #("model", simulation.bar_possible_paths_v1),
        #("calculation_policy", "limit_touch_v1"),
        #("bar_resolution", "completed_daily_ohlc_v1"),
        #("capability_policy", policy.capability_policy),
      ],
      [],
      [],
      [],
      [],
      policy.rounding,
      policy.currency_policy,
      request.AllBranches,
      ["all_compatible_branches", "compatible_price_ranges"],
      policy.budgets,
      available_operations(),
    )
    |> result.map_error(fn(error) {
      CoreFailure(value.operation_id, string.inspect(error))
    }),
  )
  let outcome = simulate(desired, bar, supported, policy.capability_policy)
  let result_items = case outcome {
    Performed(branches) -> [receipt.BranchResult(value.operation_id, branches)]
    Unperformed(_) -> []
  }
  use request_receipt <- result.try(
    receipt.request_receipt(request_value)
    |> result.map_error(fn(error) {
      CoreFailure(value.operation_id, string.inspect(error))
    }),
  )
  use semantic_receipt <- result.try(
    receipt.semantic_result_receipt(request_value, result_items)
    |> result.map_error(fn(error) {
      CoreFailure(value.operation_id, string.inspect(error))
    }),
  )
  let request_envelope = receipt.encode(request_receipt)
  let semantic_envelope = receipt.encode(semantic_receipt)
  let receipt_bytes =
    string.byte_size(request_envelope) + string.byte_size(semantic_envelope)
  use _ <- result.try(case receipt_bytes <= policy.maximum_bytes {
    True -> Ok(Nil)
    False ->
      Error(CoreFailure(
        value.operation_id,
        "maximum_bytes exceeded by canonical request and semantic envelopes: "
          <> string.inspect(receipt_bytes),
      ))
  })
  let request_handle =
    request_receipt |> receipt.canonical_content_hash |> identity.sha256_value
  let semantic_handle =
    semantic_receipt |> receipt.canonical_content_hash |> identity.sha256_value
  let receipt_fields = case policy.projection {
    Compact -> []
    Receipt -> [
      #("requestReceiptEnvelope", json.string(request_envelope)),
      #("semanticReceiptEnvelope", json.string(semantic_envelope)),
    ]
  }
  Ok(Response(
    case outcome {
      Performed(_) -> "Returned every compatible completed-daily bar branch"
      Unperformed(_) ->
        "Returned an exact unperformed completed-daily bar simulation"
    },
    json.object(list.append(
      [
        #("schemaVersion", json.int(1)),
        #("operation", json.string("simulate_bar_paths")),
        #("operationId", json.string(value.operation_id)),
        #("instruction", desired_instruction_json(desired)),
        #(
          "inputs",
          json.object([
            #("bar", bar_fact_json(bar)),
            #("desiredOrderSupported", bool_fact_json(supported)),
          ]),
        ),
        #("policy", policy_json(value.policy, policy.rounding_mode)),
        #("result", outcome_json(outcome)),
        #("counts", counts_json(bar, supported, outcome)),
        #("requestReceiptHandle", json.string(request_handle)),
        #("semanticReceiptHandle", json.string(semantic_handle)),
        #("receiptEnvelopesIncluded", json.bool(policy.projection == Receipt)),
        #("receiptEnvelopeBytes", json.int(receipt_bytes)),
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
              "A completed-daily bar supplies no intraday sequence, queue, or proof that the desired order filled.",
              "Compatible branches and receipt hashes do not prove capability truth, provider origin, source authenticity, execution quality, authorization, correctness, or professional sufficiency.",
              "The LLM selects every order, fact, capability policy, branch interpretation, and next operation; this stateless shell performs no provider, broker, storage, paper, or live mutation effect.",
            ],
            json.string,
          ),
        ),
      ],
      receipt_fields,
    )),
  ))
}

fn simulate(
  desired: instruction.DesiredInstruction,
  bar: fact.Fact(simulation.DailyBar),
  supported: fact.Fact(Bool),
  capability_policy: String,
) -> SimulationOutcome {
  case capability_precondition(capability_policy, supported) {
    Error(reason) -> Unperformed(reason)
    Ok(Nil) ->
      case instruction.order_behavior(desired) {
        instruction.Limit(price) ->
          case fact.known_value(bar) {
            Ok(sourced) ->
              Performed(simulation.limit_possible_paths(
                fact.sourced_value(sourced),
                instruction.side(desired),
                price,
              ))
            Error(reason) ->
              Unperformed("completed_daily_bar_unavailable:" <> reason)
          }
        _ -> Unperformed("unsupported_desired_behavior_for_limit_touch_v1")
      }
  }
}

fn capability_precondition(
  policy: String,
  supported: fact.Fact(Bool),
) -> Result(Nil, String) {
  case policy {
    "record_only_v1" -> Ok(Nil)
    "require_known_true_v1" ->
      case fact.known_value(supported) {
        Ok(sourced) ->
          case fact.sourced_value(sourced) {
            True -> Ok(Nil)
            False ->
              Error("desired_order_supported=false_under_require_known_true_v1")
          }
        Error(reason) -> Error("desired_order_support_unavailable:" <> reason)
      }
    _ -> Error("unsupported_capability_policy")
  }
}

fn prepare_policy(
  value: decode.PolicyInput,
) -> Result(PreparedPolicy, DomainError) {
  use _ <- result.try(exact(
    "policy.model",
    value.model,
    simulation.bar_possible_paths_v1,
  ))
  use _ <- result.try(exact(
    "policy.calculationPolicy",
    value.calculation_policy,
    "limit_touch_v1",
  ))
  use _ <- result.try(case value.capability_policy {
    "record_only_v1" | "require_known_true_v1" -> Ok(Nil)
    _ ->
      Error(InvalidField(
        "policy.capabilityPolicy",
        "expected record_only_v1 or require_known_true_v1",
      ))
  })
  use _ <- result.try(exact(
    "policy.branchPolicy",
    value.branch_policy,
    "all_branches",
  ))
  use _ <- result.try(trimmed("policy.sessionScope", value.session_scope))
  use _ <- result.try(trimmed("policy.dateTimeScope", value.date_time_scope))
  use _ <- result.try(trimmed("policy.currencyPolicy", value.currency_policy))
  use _ <- result.try(integer_range(
    "policy.rounding.outputScale",
    value.rounding.output_scale,
    0,
    30,
  ))
  use rounding_mode_value <- result.try(rounding_mode(value.rounding.mode))
  use rounding_value <- result.try(
    calculation.rounding(value.rounding.output_scale, rounding_mode_value)
    |> result.map_error(fn(error) {
      InvalidField("policy.rounding", string.inspect(error))
    }),
  )
  use references <- result.try(reference_set(value.references))
  use _ <- result.try(integer_range(
    "policy.maximumBranches",
    value.maximum_branches,
    1,
    100,
  ))
  use _ <- result.try(integer_range(
    "policy.maximumOutputs",
    value.maximum_outputs,
    1,
    100,
  ))
  use _ <- result.try(integer_range(
    "policy.maximumBytes",
    value.maximum_bytes,
    1,
    1_000_000,
  ))
  use _ <- result.try(integer_range(
    "policy.maximumOperations",
    value.maximum_operations,
    1,
    100,
  ))
  use projection <- result.try(output_projection(value.projection))
  Ok(PreparedPolicy(
    value.capability_policy,
    value.session_scope,
    value.date_time_scope,
    value.currency_policy,
    rounding_value,
    rounding_mode_value,
    references,
    request.Budgets(
      1,
      1,
      value.maximum_branches,
      1,
      value.maximum_outputs,
      value.maximum_bytes,
      value.maximum_operations,
    ),
    projection,
    value.maximum_bytes,
  ))
}

fn desired_instruction(
  value: decode.InstructionInput,
) -> Result(instruction.DesiredInstruction, DomainError) {
  use receipt_hash <- result.try(sha(
    "instruction.instructionReceipt",
    value.instruction_receipt,
  ))
  use track_value <- result.try(track(value.track))
  use _ <- result.try(
    currency.from_code(value.currency)
    |> result.map_error(fn(_) {
      InvalidField(
        "instruction.currency",
        "expected a three-letter currency code",
      )
    }),
  )
  use side <- result.try(side(value.side))
  use intent <- result.try(intent(value.intent))
  use _ <- result.try(long_only_intent(side, intent))
  use quantity <- result.try(parse_decimal(
    "instruction.quantity",
    value.quantity,
  ))
  use quantity_unit <- result.try(quantity_unit(value.quantity_unit))
  use behavior <- result.try(order_behavior(value.order_behavior))
  use tif <- result.try(time_in_force(value.time_in_force))
  use session <- result.try(requested_session(value.requested_session))
  use activation <- result.try(optional_instant(
    "instruction.activationTimeUnixMilliseconds",
    value.activation_time_unix_ms,
  ))
  use expiry <- result.try(optional_instant(
    "instruction.expiryTimeUnixMilliseconds",
    value.expiry_time_unix_ms,
  ))
  use _ <- result.try(
    time.timezone(value.timezone)
    |> result.map_error(fn(_) {
      InvalidField("instruction.timezone", "expected UTC or an IANA timezone")
    }),
  )
  use rule_references <- result.try(hash_list(
    "instruction.ruleReferences[]",
    value.rule_references,
  ))
  use capability_references <- result.try(hash_list(
    "instruction.capabilityReferences[]",
    value.capability_references,
  ))
  use account_references <- result.try(hash_list(
    "instruction.accountReferences[]",
    value.account_references,
  ))
  use alternatives <- result.try(retained_alternatives(
    value.retained_alternatives,
  ))
  instruction.desired(
    value.instruction_id,
    receipt_hash,
    track_value,
    value.listing_id,
    value.mic,
    value.account_scope,
    value.currency,
    side,
    intent,
    quantity,
    quantity_unit,
    behavior,
    tif,
    session,
    activation,
    expiry,
    value.timezone,
    rule_references,
    capability_references,
    account_references,
    alternatives,
  )
  |> result.map_error(fn(error) {
    InvalidField("instruction", string.inspect(error))
  })
}

fn order_behavior(
  value: decode.OrderBehaviorInput,
) -> Result(instruction.OrderBehavior, DomainError) {
  case
    value.kind,
    value.price,
    value.trigger_price,
    value.trigger_basis,
    value.phase,
    value.trail_value,
    value.trail_reference,
    value.trail_cadence
  {
    "market", None, None, None, None, None, None, None -> Ok(instruction.Market)
    "limit", Some(price), None, None, None, None, None, None -> {
      use parsed <- result.try(parse_decimal(
        "instruction.orderBehavior.price",
        price,
      ))
      Ok(instruction.Limit(parsed))
    }
    "stop", None, Some(trigger), Some(basis), None, None, None, None -> {
      use parsed <- result.try(parse_decimal(
        "instruction.orderBehavior.triggerPrice",
        trigger,
      ))
      use parsed_basis <- result.try(trigger_basis(basis))
      Ok(instruction.Stop(parsed, parsed_basis))
    }
    "stop_limit",
      Some(price),
      Some(trigger),
      Some(basis),
      None,
      None,
      None,
      None
    -> {
      use parsed_price <- result.try(parse_decimal(
        "instruction.orderBehavior.price",
        price,
      ))
      use parsed_trigger <- result.try(parse_decimal(
        "instruction.orderBehavior.triggerPrice",
        trigger,
      ))
      use parsed_basis <- result.try(trigger_basis(basis))
      Ok(instruction.StopLimit(parsed_trigger, parsed_basis, parsed_price))
    }
    "auction", None, None, None, Some(phase), None, None, None -> {
      use _ <- result.try(trimmed("instruction.orderBehavior.phase", phase))
      Ok(instruction.Auction(phase))
    }
    "market_on_close", None, None, None, None, None, None, None ->
      Ok(instruction.MarketOnClose)
    "limit_on_close", Some(price), None, None, None, None, None, None -> {
      use parsed <- result.try(parse_decimal(
        "instruction.orderBehavior.price",
        price,
      ))
      Ok(instruction.LimitOnClose(parsed))
    }
    "trailing_stop",
      None,
      None,
      None,
      None,
      Some(amount),
      Some(reference),
      Some(cadence)
    -> {
      use parsed <- result.try(parse_decimal(
        "instruction.orderBehavior.trailValue",
        amount,
      ))
      use _ <- result.try(trimmed(
        "instruction.orderBehavior.trailReference",
        reference,
      ))
      use _ <- result.try(trimmed(
        "instruction.orderBehavior.trailCadence",
        cadence,
      ))
      Ok(instruction.TrailingStop(parsed, reference, cadence))
    }
    _, _, _, _, _, _, _, _ ->
      Error(InvalidField(
        "instruction.orderBehavior",
        "desired behavior must supply exactly the fields required by its kind",
      ))
  }
}

fn trigger_basis(
  value: decode.TriggerBasisInput,
) -> Result(instruction.TriggerBasis, DomainError) {
  case value.kind, value.label {
    "last_sale", None -> Ok(instruction.LastSale)
    "bid", None -> Ok(instruction.Bid)
    "ask", None -> Ok(instruction.Ask)
    "midpoint", None -> Ok(instruction.Midpoint)
    "mark", None -> Ok(instruction.Mark)
    "index", Some(label) -> {
      use _ <- result.try(trimmed(
        "instruction.orderBehavior.triggerBasis.label",
        label,
      ))
      Ok(instruction.Index(label))
    }
    "provider_defined", Some(label) -> {
      use _ <- result.try(trimmed(
        "instruction.orderBehavior.triggerBasis.label",
        label,
      ))
      Ok(instruction.ProviderDefined(label))
    }
    _, _ ->
      Error(InvalidField(
        "instruction.orderBehavior.triggerBasis",
        "index/provider_defined require label; other variants forbid it",
      ))
  }
}

fn time_in_force(
  value: decode.TimeInForceInput,
) -> Result(instruction.TimeInForce, DomainError) {
  case value.kind, value.expiry_unix_ms {
    "day", None -> Ok(instruction.Day)
    "gtc", None -> Ok(instruction.Gtc)
    "ioc", None -> Ok(instruction.Ioc)
    "fok", None -> Ok(instruction.Fok)
    "auction_only", None -> Ok(instruction.AuctionOnly)
    "extended_hours", None -> Ok(instruction.ExtendedHours)
    "gtd", Some(expiry) -> {
      use parsed <- result.try(instant(
        "instruction.timeInForce.expiryUnixMilliseconds",
        expiry,
      ))
      Ok(instruction.Gtd(parsed))
    }
    _, _ ->
      Error(InvalidField(
        "instruction.timeInForce",
        "gtd requires expiryUnixMilliseconds; other variants forbid it",
      ))
  }
}

fn retained_alternatives(
  value: decode.RetainedAlternativesInput,
) -> Result(instruction.RetainedAlternatives, DomainError) {
  case value.state, value.values, value.reason {
    "known", values, None -> {
      use _ <- result.try(
        list.try_map(values, fn(value) {
          trimmed("instruction.retainedAlternatives.values[]", value)
        }),
      )
      Ok(instruction.KnownAlternatives(values))
    }
    "not_applicable", [], Some(reason) -> {
      use _ <- result.try(trimmed(
        "instruction.retainedAlternatives.reason",
        reason,
      ))
      Ok(instruction.AlternativesNotApplicable(reason))
    }
    _, _, _ ->
      Error(InvalidField(
        "instruction.retainedAlternatives",
        "known forbids reason; not_applicable requires an empty value list and reason",
      ))
  }
}

fn bar_fact(
  field_name: String,
  value: decode.BarFactInput,
) -> Result(fact.Fact(simulation.DailyBar), DomainError) {
  case
    value.state,
    value.value,
    value.source,
    value.reason,
    value.raw,
    value.alternatives
  {
    "known", Some(raw), Some(source_input), None, None, [] -> {
      use parsed <- result.try(daily_bar(field_name <> ".value", raw))
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
      use sourced <- result.try(
        list.try_map(alternatives, fn(alternative) {
          use parsed <- result.try(daily_bar(
            field_name <> ".alternatives[].value",
            alternative.value,
          ))
          use source <- result.try(source(
            field_name <> ".alternatives[].source",
            alternative.source,
          ))
          Ok(fact.Sourced(parsed, source))
        }),
      )
      fact.conflicting(sourced)
      |> result.map_error(fn(error) {
        InvalidField(field_name, string.inspect(error))
      })
    }
    "decode_failure", None, Some(source_input), Some(reason), Some(raw), [] -> {
      use source <- result.try(source(field_name <> ".source", source_input))
      use _ <- result.try(trimmed(field_name <> ".reason", reason))
      Ok(fact.DecodeFailure(source, raw, reason))
    }
    "not_applicable", None, Some(source_input), Some(reason), None, [] -> {
      use source <- result.try(source(field_name <> ".source", source_input))
      use _ <- result.try(trimmed(field_name <> ".reason", reason))
      Ok(fact.NotApplicable(source, reason))
    }
    _, _, _, _, _, _ ->
      Error(InvalidField(
        field_name,
        "fact state must supply exactly its required value/source/reason/raw/alternatives fields",
      ))
  }
}

fn bool_fact(
  field_name: String,
  value: decode.BoolFactInput,
) -> Result(fact.Fact(Bool), DomainError) {
  case
    value.state,
    value.value,
    value.source,
    value.reason,
    value.raw,
    value.alternatives
  {
    "known", Some(raw), Some(source_input), None, None, [] -> {
      use source <- result.try(source(field_name <> ".source", source_input))
      Ok(fact.known(raw, source))
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
      use sourced <- result.try(
        list.try_map(alternatives, fn(alternative) {
          use source <- result.try(source(
            field_name <> ".alternatives[].source",
            alternative.source,
          ))
          Ok(fact.Sourced(alternative.value, source))
        }),
      )
      fact.conflicting(sourced)
      |> result.map_error(fn(error) {
        InvalidField(field_name, string.inspect(error))
      })
    }
    "decode_failure", None, Some(source_input), Some(reason), Some(raw), [] -> {
      use source <- result.try(source(field_name <> ".source", source_input))
      use _ <- result.try(trimmed(field_name <> ".reason", reason))
      Ok(fact.DecodeFailure(source, raw, reason))
    }
    "not_applicable", None, Some(source_input), Some(reason), None, [] -> {
      use source <- result.try(source(field_name <> ".source", source_input))
      use _ <- result.try(trimmed(field_name <> ".reason", reason))
      Ok(fact.NotApplicable(source, reason))
    }
    _, _, _, _, _, _ ->
      Error(InvalidField(
        field_name,
        "fact state must supply exactly its required value/source/reason/raw/alternatives fields",
      ))
  }
}

fn daily_bar(
  field_name: String,
  value: decode.BarValueInput,
) -> Result(simulation.DailyBar, DomainError) {
  use open <- result.try(parse_decimal(field_name <> ".open", value.open))
  use high <- result.try(parse_decimal(field_name <> ".high", value.high))
  use low <- result.try(parse_decimal(field_name <> ".low", value.low))
  use close <- result.try(parse_decimal(field_name <> ".close", value.close))
  simulation.daily_bar(open, high, low, close)
  |> result.map_error(fn(error) {
    InvalidField(field_name, string.inspect(error))
  })
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
  use _ <- result.try(
    list.try_map(value.retained_alternatives, fn(value) {
      trimmed(field_name <> ".retainedAlternatives[]", value)
    }),
  )
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

fn reference_set(
  value: decode.ReferenceSetInput,
) -> Result(request.ReferenceSet, DomainError) {
  use capability <- result.try(hash_list(
    "policy.references.capabilityReferences[]",
    value.capability_references,
  ))
  use rules <- result.try(hash_list(
    "policy.references.ruleReferences[]",
    value.rule_references,
  ))
  use calendars <- result.try(hash_list(
    "policy.references.calendarReferences[]",
    value.calendar_references,
  ))
  use market_events <- result.try(hash_list(
    "policy.references.marketEventReferences[]",
    value.market_event_references,
  ))
  use lifecycle <- result.try(hash_list(
    "policy.references.lifecycleReferences[]",
    value.lifecycle_references,
  ))
  use positions <- result.try(hash_list(
    "policy.references.positionReferences[]",
    value.position_references,
  ))
  use risk <- result.try(hash_list(
    "policy.references.riskReceiptReferences[]",
    value.risk_receipt_references,
  ))
  use cost <- result.try(hash_list(
    "policy.references.costReceiptReferences[]",
    value.cost_receipt_references,
  ))
  use fx <- result.try(hash_list(
    "policy.references.fxReceipts[]",
    value.fx_receipts,
  ))
  Ok(request.ReferenceSet(
    capability,
    rules,
    calendars,
    market_events,
    lifecycle,
    positions,
    risk,
    cost,
    fx,
  ))
}

fn outcome_json(value: SimulationOutcome) -> Json {
  case value {
    Unperformed(reason) ->
      json.object([
        #("state", json.string("unperformed")),
        #("model", json.string(simulation.bar_possible_paths_v1)),
        #("reason", json.string(reason)),
        #("branches", json.array([], fn(value: Json) { value })),
      ])
    Performed(branches) ->
      json.object([
        #("state", json.string("performed")),
        #("model", json.string(simulation.branch_model(branches))),
        #(
          "resultKind",
          branches
            |> simulation.branch_result_kind
            |> simulation.result_kind_name
            |> json.string,
        ),
        #(
          "branches",
          branches |> simulation.branches |> json.array(branch_json),
        ),
      ])
  }
}

fn branch_json(value: simulation.SimulationBranch) -> Json {
  let simulation.SimulationBranch(id, outcome, price_range, note) = value
  let outcome_name = simulation.branch_outcome_name(outcome)
  json.object([
    #("branchId", json.string(id)),
    #("outcome", json.string(outcome_name)),
    #("fillCompatibility", json.string(outcome_name)),
    #("compatiblePriceRange", decimal_range_json(price_range)),
    #("note", json.string(note)),
  ])
}

fn decimal_range_json(
  value: Option(#(decimal.Decimal, decimal.Decimal)),
) -> Json {
  case value {
    None -> json.null()
    Some(#(minimum, maximum)) ->
      json.object([
        #("minimum", minimum |> decimal.to_string |> json.string),
        #("maximum", maximum |> decimal.to_string |> json.string),
      ])
  }
}

fn desired_instruction_json(value: instruction.DesiredInstruction) -> Json {
  json.object([
    #("instructionId", value |> instruction.instruction_id |> json.string),
    #(
      "instructionReceipt",
      value
        |> instruction.instruction_receipt
        |> identity.sha256_value
        |> json.string,
    ),
    #("track", value |> instruction.track |> finance_track.name |> json.string),
    #("listingId", value |> instruction.listing_id |> json.string),
    #("mic", value |> instruction.mic |> json.string),
    #("accountScope", value |> instruction.account_scope |> json.string),
    #("currency", value |> instruction.currency |> json.string),
    #("side", value |> instruction.side |> instruction.side_name |> json.string),
    #(
      "quantity",
      value |> instruction.quantity |> decimal.to_string |> json.string,
    ),
    #(
      "quantityUnit",
      value
        |> instruction.quantity_unit
        |> instruction.quantity_unit_name
        |> json.string,
    ),
    #(
      "desiredBehavior",
      value
        |> instruction.order_behavior
        |> instruction.behavior_name
        |> json.string,
    ),
    #(
      "timeInForce",
      value
        |> instruction.time_in_force
        |> instruction.time_in_force_name
        |> json.string,
    ),
    #("timezone", value |> instruction.timezone |> json.string),
    #("ruleReferences", value |> instruction.rule_references |> hashes_json),
    #(
      "capabilityReferences",
      value |> instruction.capability_references |> hashes_json,
    ),
    #(
      "accountReferences",
      value |> instruction.account_references |> hashes_json,
    ),
  ])
}

fn hashes_json(values: List(identity.Sha256)) -> Json {
  values |> list.map(identity.sha256_value) |> json.array(json.string)
}

fn bar_fact_json(value: fact.Fact(simulation.DailyBar)) -> Json {
  fact_json(value, fn(bar) {
    let simulation.DailyBar(open, high, low, close) = bar
    json.object([
      #("open", open |> decimal.to_string |> json.string),
      #("high", high |> decimal.to_string |> json.string),
      #("low", low |> decimal.to_string |> json.string),
      #("close", close |> decimal.to_string |> json.string),
    ])
  })
}

fn bool_fact_json(value: fact.Fact(Bool)) -> Json {
  fact_json(value, json.bool)
}

fn fact_json(value: fact.Fact(value), encode: fn(value) -> Json) -> Json {
  case value {
    fact.Known(fact.Sourced(item, source)) ->
      json.object([
        #("state", json.string("known")),
        #("value", encode(item)),
        #("source", source_json(source)),
      ])
    fact.Unknown(source, reason) ->
      unavailable_fact_json("unknown", source, reason, None)
    fact.NotObtained(source, reason) ->
      unavailable_fact_json("not_obtained", source, reason, None)
    fact.DecodeFailure(source, raw, reason) ->
      unavailable_fact_json("decode_failure", source, reason, Some(raw))
    fact.NotApplicable(source, reason) ->
      unavailable_fact_json("not_applicable", source, reason, None)
    fact.Conflicting(alternatives) ->
      json.object([
        #("state", json.string("conflicting")),
        #(
          "alternatives",
          alternatives
            |> json.array(fn(value) {
              json.object([
                #("value", value |> fact.sourced_value |> encode),
                #("source", value |> fact.sourced_source |> source_json),
              ])
            }),
        ),
      ])
  }
}

fn unavailable_fact_json(
  state: String,
  source: fact.Source,
  reason: String,
  raw: Option(String),
) -> Json {
  json.object([
    #("state", json.string(state)),
    #("source", source_json(source)),
    #("reason", json.string(reason)),
    #("raw", case raw {
      None -> json.null()
      Some(value) -> json.string(value)
    }),
  ])
}

fn source_json(value: fact.Source) -> Json {
  json.object([
    #("kind", value |> fact.source_kind |> fact.source_kind_name |> json.string),
    #(
      "reference",
      value |> fact.source_reference |> identity.sha256_value |> json.string,
    ),
    #(
      "effectiveAtUnixMilliseconds",
      value |> fact.effective_at |> time.unix_milliseconds |> json.int,
    ),
    #(
      "retrievedAtUnixMilliseconds",
      value |> fact.retrieved_at |> time.unix_milliseconds |> json.int,
    ),
    #("currency", value |> fact.currency |> json.string),
    #("unit", value |> fact.unit |> json.string),
    #("sourceLexeme", value |> fact.source_lexeme |> json.string),
    #("scope", value |> fact.scope |> json.string),
    #(
      "retainedAlternatives",
      value |> fact.retained_alternatives |> json.array(json.string),
    ),
  ])
}

fn policy_json(value: decode.PolicyInput, mode: decimal.RoundingMode) -> Json {
  json.object([
    #("model", json.string(value.model)),
    #("calculationPolicy", json.string(value.calculation_policy)),
    #("capabilityPolicy", json.string(value.capability_policy)),
    #("branchPolicy", json.string(value.branch_policy)),
    #("sessionScope", json.string(value.session_scope)),
    #("dateTimeScope", json.string(value.date_time_scope)),
    #("currencyPolicy", json.string(value.currency_policy)),
    #(
      "rounding",
      json.object([
        #("outputScale", json.int(value.rounding.output_scale)),
        #("mode", json.string(rounding_mode_name(mode))),
      ]),
    ),
    #(
      "budgets",
      json.object([
        #("maximumBranches", json.int(value.maximum_branches)),
        #("maximumOutputs", json.int(value.maximum_outputs)),
        #("maximumBytes", json.int(value.maximum_bytes)),
        #("maximumOperations", json.int(value.maximum_operations)),
      ]),
    ),
    #("projection", json.string(value.projection)),
  ])
}

fn counts_json(
  bar: fact.Fact(simulation.DailyBar),
  supported: fact.Fact(Bool),
  outcome: SimulationOutcome,
) -> Json {
  let states = [fact.state_name(bar), fact.state_name(supported)]
  let branch_count = case outcome {
    Performed(branches) -> branches |> simulation.branches |> list.length
    Unperformed(_) -> 0
  }
  json.object([
    #("branches", json.int(branch_count)),
    #("unknownInputs", json.int(count_state(states, "unknown"))),
    #("notObtainedInputs", json.int(count_state(states, "not_obtained"))),
    #("conflictingInputs", json.int(count_state(states, "conflicting"))),
    #("decodeFailureInputs", json.int(count_state(states, "decode_failure"))),
    #("notApplicableInputs", json.int(count_state(states, "not_applicable"))),
  ])
}

fn count_state(values: List(String), state: String) -> Int {
  values |> list.filter(fn(value) { value == state }) |> list.length
}

fn available_operations() -> List(String) {
  [
    "simulate_bar_paths",
    "supply_bar",
    "supply_capability_fact",
    "calculate_all_branches",
    "inspect_branch",
  ]
}

fn output_projection(value: String) -> Result(OutputProjection, DomainError) {
  case value {
    "compact" -> Ok(Compact)
    "receipt" -> Ok(Receipt)
    _ -> Error(InvalidField("policy.projection", "expected compact or receipt"))
  }
}

fn source_kind(
  field_name: String,
  value: String,
) -> Result(fact.SourceKind, DomainError) {
  case value {
    "broker_observation" -> Ok(fact.BrokerObservation)
    "exchange_observation" -> Ok(fact.ExchangeObservation)
    "provider_observation" -> Ok(fact.ProviderObservation)
    "external_documentation" -> Ok(fact.ExternalDocumentation)
    "market_rule" -> Ok(fact.MarketRule)
    "calendar_observation" -> Ok(fact.CalendarObservation)
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
    _ -> Error(InvalidField("instruction.track", "expected cn, hk, or us"))
  }
}

fn side(value: String) -> Result(instruction.Side, DomainError) {
  case value {
    "buy" -> Ok(instruction.Buy)
    "sell" -> Ok(instruction.Sell)
    _ -> Error(InvalidField("instruction.side", "expected buy or sell"))
  }
}

fn intent(
  value: Option(String),
) -> Result(Option(instruction.Intent), DomainError) {
  case value {
    None -> Ok(None)
    Some("open") -> Ok(Some(instruction.Open))
    Some("close") -> Ok(Some(instruction.Close))
    Some("reduce") -> Ok(Some(instruction.Reduce))
    Some(_) ->
      Error(InvalidField(
        "instruction.intent",
        "expected open, close, or reduce",
      ))
  }
}

fn long_only_intent(
  side: instruction.Side,
  intent: Option(instruction.Intent),
) -> Result(Nil, DomainError) {
  case side, intent {
    instruction.Sell, Some(instruction.Open) ->
      Error(InvalidField(
        "instruction.intent",
        "the first long-only cash-equity slice forbids sell/open",
      ))
    _, _ -> Ok(Nil)
  }
}

fn quantity_unit(
  value: String,
) -> Result(instruction.QuantityUnit, DomainError) {
  case value {
    "shares" -> Ok(instruction.Shares)
    "lots" -> Ok(instruction.Lots)
    "currency_notional" -> Ok(instruction.CurrencyNotional)
    _ ->
      Error(InvalidField(
        "instruction.quantityUnit",
        "expected shares, lots, or currency_notional",
      ))
  }
}

fn requested_session(
  value: Option(String),
) -> Result(Option(instruction.RequestedSession), DomainError) {
  case value {
    None -> Ok(None)
    Some("pre_open_auction") -> Ok(Some(instruction.PreOpenAuction))
    Some("regular") -> Ok(Some(instruction.Regular))
    Some("closing_auction") -> Ok(Some(instruction.ClosingAuction))
    Some("extended") -> Ok(Some(instruction.Extended))
    Some(_) ->
      Error(InvalidField(
        "instruction.requestedSession",
        "unsupported requested session",
      ))
  }
}

fn rounding_mode(value: String) -> Result(decimal.RoundingMode, DomainError) {
  case value {
    "toward_zero" -> Ok(decimal.TowardZero)
    "away_from_zero" -> Ok(decimal.AwayFromZero)
    "half_up" -> Ok(decimal.HalfUp)
    "half_even" -> Ok(decimal.HalfEven)
    _ ->
      Error(InvalidField("policy.rounding.mode", "unsupported rounding mode"))
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

fn hash_list(
  field_name: String,
  values: List(String),
) -> Result(List(identity.Sha256), DomainError) {
  list.try_map(values, fn(value) { sha(field_name, value) })
}

fn optional_instant(
  field_name: String,
  value: Option(Int),
) -> Result(Option(time.Instant), DomainError) {
  case value {
    None -> Ok(None)
    Some(value) -> instant(field_name, value) |> result.map(Some)
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

fn trimmed(field_name: String, value: String) -> Result(Nil, DomainError) {
  case value != "" && string.trim(value) == value {
    True -> Ok(Nil)
    False -> Error(InvalidField(field_name, "must be non-empty trimmed text"))
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
        "expected an integer within the declared bounded range",
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
