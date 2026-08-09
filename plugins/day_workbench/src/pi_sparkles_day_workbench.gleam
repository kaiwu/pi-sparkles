import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/json.{type Json}
import gleam/result
import pi
import pi/schema
import pi/tool
import pi_sparkles_day_workbench/calculation
import pi_sparkles_day_workbench/decode
import pi_sparkles_day_workbench/packet
import pi_sparkles_day_workbench/workflow

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  register_inspect(api)
  register_calculate(api)
  register_transition(api)
  promise.resolve(Nil)
}

fn register_inspect(api: pi.ExtensionApi) -> Nil {
  tool.register(
    api,
    "day_inspect",
    "Inspect exact intraday evidence",
    "Validate one content-bound caller-supplied intraday packet and return exact identity, caller-attested licence and entitlement, phase, sequence, freshness, integrity, evidence-matrix, and optional paged event facts without acquiring a feed or selecting an action",
    "Treat every provider, real-time, licence, and acquisition claim as caller-attested rather than authenticated; integrity is mechanical and every interpretation remains with the LLM or user",
    tool.parameters(inspect_schema(), decode.inspect()),
    tool.Parallel,
    fn(_id, input, signal, _updates, _ctx) {
      case tool.is_cancelled(signal) {
        True -> tool.reject("Day evidence inspection was cancelled")
        False -> inspect(input)
      }
    },
  )
}

fn register_calculate(api: pi.ExtensionApi) -> Nil {
  tool.register(
    api,
    "day_calculate",
    "Calculate one exact intraday fact",
    "Validate one content-bound caller-supplied intraday packet and perform exactly one requested spread, midpoint, displayed-notional, change, range, volume, turnover, VWAP, or depth calculation with explicit window, filter, scale, rounding, operands, and source event receipts",
    "A calculated value is only a mechanical fact; gaps, conflicts, incompleteness, missing operands, corrections, and zero denominators remain unperformed rather than signals or fallbacks",
    tool.parameters(calculation_schema(), decode.calculation()),
    tool.Parallel,
    fn(_id, input, signal, _updates, _ctx) {
      case tool.is_cancelled(signal) {
        True -> tool.reject("Day calculation was cancelled")
        False -> calculate(input)
      }
    },
  )
}

fn register_transition(api: pi.ExtensionApi) -> Nil {
  tool.register(
    api,
    "day_transition",
    "Advance an explicit day-workflow state",
    "Validate and apply one typed LLM/user declaration or evidence-backed mechanical fact to caller-retained content-bound workflow state, returning a canonical next-state payload and receipt without ambient storage, automatic judgment, or order/account mutation",
    "Ready means only evidence_available; retain each returned state payload and hash per exact workflowId and branchId, and never treat a state as approval, authorization, recommendation, or automatic closeout",
    tool.parameters(transition_schema(), decode.transition()),
    tool.Parallel,
    fn(_id, input, signal, _updates, _ctx) {
      case tool.is_cancelled(signal) {
        True -> tool.reject("Day workflow transition was cancelled")
        False ->
          complete(
            workflow.transition(input),
            "Applied an explicit caller-retained day-workflow transition; inspect its information-state meaning and forbidden claims.",
          )
      }
    },
  )
}

fn inspect(input: decode.InspectInput) -> Promise(tool.ToolResult) {
  complete(
    inspect_details(input),
    "Validated caller-supplied intraday evidence; inspect identity, claim verification, integrity, freshness, phase, and omissions before any LLM/user decision.",
  )
}

fn inspect_details(input: decode.InspectInput) -> Result(Json, String) {
  let decode.InspectInput(
    payload,
    content_hash,
    maximum_events,
    as_of,
    freshness_cutoff,
    include_events,
    include_source_lexemes,
    offset,
    limit,
  ) = input
  use _ <- result.try(case as_of >= 0 && freshness_cutoff >= 0 {
    True -> Ok(Nil)
    False -> Error("inspection times must be non-negative")
  })
  use _ <- result.try(case freshness_cutoff <= as_of {
    True -> Ok(Nil)
    False -> Error("freshness cutoff must not follow as-of time")
  })
  use _ <- result.try(case offset >= 0 {
    True -> Ok(Nil)
    False -> Error("offset must be non-negative")
  })
  use _ <- result.try(case limit >= 1 && limit <= packet.maximum_output_rows {
    True -> Ok(Nil)
    False -> Error("limit must be between 1 and 1000")
  })
  use packet_value <- result.try(packet.parse(
    payload,
    content_hash,
    maximum_events,
  ))
  packet.inspect(packet_value, as_of, freshness_cutoff)
  |> packet.inspection_json(
    include_events,
    include_source_lexemes,
    offset,
    limit,
  )
  |> Ok
}

fn calculate(input: decode.CalculationInput) -> Promise(tool.ToolResult) {
  complete(
    calculation_details(input),
    "Performed exactly one requested intraday calculation when its evidence laws held; the result is not a signal, recommendation, authorization, fill claim, or next action.",
  )
}

fn calculation_details(input: decode.CalculationInput) -> Result(Json, String) {
  let decode.CalculationInput(
    payload,
    content_hash,
    maximum_events,
    selected_calculation,
    start,
    finish,
    scale,
    rounding,
    filter,
  ) = input
  use packet_value <- result.try(packet.parse(
    payload,
    content_hash,
    maximum_events,
  ))
  calculation.run(
    packet_value,
    selected_calculation,
    start,
    finish,
    scale,
    rounding,
    filter,
  )
}

fn complete(
  outcome: Result(Json, String),
  summary: String,
) -> Promise(tool.ToolResult) {
  case outcome {
    Ok(details) -> tool.text_result(summary, details) |> promise.resolve
    Error(message) -> tool.reject(message)
  }
}

fn inspect_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "packetPayload",
      bounded_string(1, packet.maximum_payload_bytes),
    ),
    schema.Required("packetHash", hash_schema()),
    schema.Required("maximumEvents", bounded_integer(1, packet.maximum_events)),
    schema.Required("asOfUnixMilliseconds", unix_milliseconds()),
    schema.Required("freshnessCutoffUnixMilliseconds", unix_milliseconds()),
    schema.Required("includeEvents", schema.boolean()),
    schema.Required("includeSourceLexemes", schema.boolean()),
    schema.Required("offset", bounded_integer(0, packet.maximum_events)),
    schema.Required("limit", bounded_integer(1, packet.maximum_output_rows)),
  ])
}

fn calculation_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "packetPayload",
      bounded_string(1, packet.maximum_payload_bytes),
    ),
    schema.Required("packetHash", hash_schema()),
    schema.Required("maximumEvents", bounded_integer(1, packet.maximum_events)),
    schema.Required(
      "calculation",
      schema.string_enum([
        "quoted_spread",
        "quoted_spread_percent",
        "midpoint",
        "displayed_bid_notional",
        "displayed_ask_notional",
        "quote_change",
        "trade_change",
        "opening_range",
        "session_high",
        "session_low",
        "cumulative_volume",
        "cumulative_turnover",
        "vwap",
        "session_range_percent",
        "depth_imbalance",
        "depth_weighted_bid",
        "depth_weighted_ask",
      ]),
    ),
    schema.Required("windowStartUnixMilliseconds", unix_milliseconds()),
    schema.Required("windowEndUnixMilliseconds", unix_milliseconds()),
    schema.Required("scale", bounded_integer(0, 18)),
    schema.Required(
      "rounding",
      schema.string_enum([
        "toward_zero",
        "away_from_zero",
        "half_up",
        "half_even",
      ]),
    ),
    schema.Required("eventFilter", event_filter_schema()),
  ])
}

fn event_filter_schema() -> schema.Schema {
  schema.object([
    schema.Required("includeOddLots", schema.boolean()),
    schema.Required("includeOffExchange", schema.boolean()),
    schema.Required(
      "includedConditionCodes",
      schema.array(bounded_string(1, 200))
        |> schema.with_array_length(0, packet.maximum_condition_codes),
    ),
  ])
}

fn transition_schema() -> schema.Schema {
  schema.object([
    schema.Optional(
      "currentStatePayload",
      schema.nullable(bounded_string(1, 200_000)),
    ),
    schema.Optional("currentStateHash", schema.nullable(hash_schema())),
    schema.Required("workflowId", bounded_string(1, 200)),
    schema.Required("branchId", bounded_string(1, 200)),
    schema.Required("transitionId", bounded_string(1, 200)),
    schema.Required("idempotencyKey", bounded_string(1, 200)),
    schema.Required(
      "eventKind",
      schema.string_enum([
        "initialize_preparation",
        "begin_acquisition",
        "evidence_available",
        "declare_plan",
        "modify_plan",
        "cancel_plan",
        "begin_monitoring",
        "declare_entry_intent",
        "declare_exit_intent",
        "cancel_intent",
        "session_close_approaching",
        "declare_closeout",
        "declare_abort",
        "session_ended",
        "declare_review",
        "record_review",
      ]),
    ),
    schema.Required(
      "origin",
      schema.string_enum(["llm_authored", "user_authored", "mechanical_fact"]),
    ),
    schema.Required("occurredAtUnixMilliseconds", unix_milliseconds()),
    schema.Required("payload", bounded_string(0, 20_000)),
    schema.Required("payloadHash", hash_schema()),
    schema.Required(
      "evidenceReferences",
      schema.array(hash_schema()) |> schema.with_array_length(0, 50),
    ),
    schema.Required(
      "executionReceiptReferences",
      schema.array(hash_schema()) |> schema.with_array_length(0, 50),
    ),
  ])
}

fn unix_milliseconds() -> schema.Schema {
  bounded_integer(0, 9_007_199_254_740_991)
}

fn hash_schema() -> schema.Schema {
  bounded_string(64, 64)
}

fn bounded_string(minimum: Int, maximum: Int) -> schema.Schema {
  schema.string() |> schema.with_string_length(minimum, maximum)
}

fn bounded_integer(minimum: Int, maximum: Int) -> schema.Schema {
  schema.integer()
  |> schema.with_number_range(int.to_float(minimum), int.to_float(maximum))
}
