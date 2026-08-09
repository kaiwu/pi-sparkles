import gleam/javascript/promise.{type Promise}
import pi
import pi/schema
import pi/tool
import pi_sparkles_order_simulator/decode
import pi_sparkles_order_simulator/domain

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  tool.register(
    api,
    "simulate_bar_paths",
    "Enumerate completed-daily bar paths",
    "Run finance_execution bar_possible_paths_v1 for one exact desired order and supplied completed-daily bar, returning every compatible branch without predicting or selecting a fill",
    "Supply the exact desired instruction, sourced bar, capability support fact, and caller-selected policies; the LLM interprets every branch",
    tool.parameters(simulation_schema(), decode.simulate_bar_paths()),
    tool.Parallel,
    fn(_id, input, _signal, _updates, _ctx) {
      case domain.run(input) {
        Ok(value) ->
          tool.text_result(domain.summary(value), domain.details(value))
          |> promise.resolve
        Error(error) -> tool.reject(domain.error_message(error))
      }
    },
  )
  promise.resolve(Nil)
}

fn simulation_schema() -> schema.Schema {
  schema.object([
    schema.Required("operationId", bounded_string(1, 500)),
    schema.Required("instruction", instruction_schema()),
    schema.Required("bar", bar_fact_schema()),
    schema.Required("desiredOrderSupported", bool_fact_schema()),
    schema.Required("policy", policy_schema()),
  ])
}

fn instruction_schema() -> schema.Schema {
  schema.object([
    schema.Required("instructionId", bounded_string(1, 500)),
    schema.Required("instructionReceipt", hash_schema()),
    schema.Required("track", schema.string_enum(["cn", "hk", "us"])),
    schema.Required("listingId", bounded_string(1, 500)),
    schema.Required("mic", bounded_string(1, 50)),
    schema.Required("accountScope", bounded_string(1, 500)),
    schema.Required("currency", bounded_string(3, 3)),
    schema.Required("side", schema.string_enum(["buy", "sell"])),
    schema.Optional(
      "intent",
      schema.nullable(schema.string_enum(["open", "close", "reduce"])),
    ),
    schema.Required("quantity", bounded_string(1, 500)),
    schema.Required(
      "quantityUnit",
      schema.string_enum(["shares", "lots", "currency_notional"]),
    ),
    schema.Required("orderBehavior", order_behavior_schema()),
    schema.Required("timeInForce", time_in_force_schema()),
    schema.Optional(
      "requestedSession",
      schema.nullable(
        schema.string_enum([
          "pre_open_auction",
          "regular",
          "closing_auction",
          "extended",
        ]),
      ),
    ),
    schema.Optional(
      "activationTimeUnixMilliseconds",
      schema.nullable(schema.integer()),
    ),
    schema.Optional(
      "expiryTimeUnixMilliseconds",
      schema.nullable(schema.integer()),
    ),
    schema.Required("timezone", bounded_string(1, 200)),
    schema.Required("ruleReferences", hash_array(0, 500)),
    schema.Required("capabilityReferences", hash_array(0, 500)),
    schema.Required("accountReferences", hash_array(1, 500)),
    schema.Required("retainedAlternatives", retained_alternatives_schema()),
  ])
}

fn order_behavior_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "kind",
      schema.string_enum([
        "market",
        "limit",
        "stop",
        "stop_limit",
        "auction",
        "market_on_close",
        "limit_on_close",
        "trailing_stop",
      ]),
    ),
    schema.Optional("price", schema.nullable(bounded_string(1, 500))),
    schema.Optional("triggerPrice", schema.nullable(bounded_string(1, 500))),
    schema.Optional("triggerBasis", schema.nullable(trigger_basis_schema())),
    schema.Optional("phase", schema.nullable(bounded_string(1, 500))),
    schema.Optional("trailValue", schema.nullable(bounded_string(1, 500))),
    schema.Optional("trailReference", schema.nullable(bounded_string(1, 500))),
    schema.Optional("trailCadence", schema.nullable(bounded_string(1, 500))),
  ])
  |> schema.described(
    "Each desired behavior must supply exactly its variant fields; only limit is performed by this first simulation slice",
  )
}

fn trigger_basis_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "kind",
      schema.string_enum([
        "last_sale",
        "bid",
        "ask",
        "midpoint",
        "mark",
        "index",
        "provider_defined",
      ]),
    ),
    schema.Optional("label", schema.nullable(bounded_string(1, 500))),
  ])
}

fn time_in_force_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "kind",
      schema.string_enum([
        "day",
        "gtc",
        "ioc",
        "fok",
        "gtd",
        "auction_only",
        "extended_hours",
      ]),
    ),
    schema.Optional("expiryUnixMilliseconds", schema.nullable(schema.integer())),
  ])
  |> schema.described("gtd requires expiry; every other variant forbids it")
}

fn retained_alternatives_schema() -> schema.Schema {
  schema.object([
    schema.Required("state", schema.string_enum(["known", "not_applicable"])),
    schema.Required(
      "values",
      schema.array(bounded_string(1, 1000)) |> schema.with_array_length(0, 100),
    ),
    schema.Optional("reason", schema.nullable(bounded_string(1, 4000))),
  ])
  |> schema.described(
    "known requires values and no reason; not_applicable requires no values and one reason",
  )
}

fn bar_fact_schema() -> schema.Schema {
  schema.object([
    schema.Required("state", fact_state_schema()),
    schema.Optional("value", schema.nullable(bar_schema())),
    schema.Optional("source", schema.nullable(source_schema())),
    schema.Optional("reason", schema.nullable(bounded_string(1, 4000))),
    schema.Optional("raw", schema.nullable(bounded_string(1, 4000))),
    schema.Optional(
      "alternatives",
      schema.array(bar_sourced_schema()) |> schema.with_array_length(0, 20),
    ),
  ])
  |> schema.described(
    "known requires value+source; conflicting requires 2-20 sourced alternatives; other states require their exact source/reason/raw fields",
  )
}

fn bar_schema() -> schema.Schema {
  schema.object([
    schema.Required("open", bounded_string(1, 500)),
    schema.Required("high", bounded_string(1, 500)),
    schema.Required("low", bounded_string(1, 500)),
    schema.Required("close", bounded_string(1, 500)),
  ])
}

fn bar_sourced_schema() -> schema.Schema {
  schema.object([
    schema.Required("value", bar_schema()),
    schema.Required("source", source_schema()),
  ])
}

fn bool_fact_schema() -> schema.Schema {
  schema.object([
    schema.Required("state", fact_state_schema()),
    schema.Optional("value", schema.nullable(schema.boolean())),
    schema.Optional("source", schema.nullable(source_schema())),
    schema.Optional("reason", schema.nullable(bounded_string(1, 4000))),
    schema.Optional("raw", schema.nullable(bounded_string(1, 4000))),
    schema.Optional(
      "alternatives",
      schema.array(bool_sourced_schema()) |> schema.with_array_length(0, 20),
    ),
  ])
}

fn bool_sourced_schema() -> schema.Schema {
  schema.object([
    schema.Required("value", schema.boolean()),
    schema.Required("source", source_schema()),
  ])
}

fn fact_state_schema() -> schema.Schema {
  schema.string_enum([
    "known",
    "unknown",
    "not_obtained",
    "conflicting",
    "decode_failure",
    "not_applicable",
  ])
}

fn source_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "kind",
      schema.string_enum([
        "broker_observation",
        "exchange_observation",
        "provider_observation",
        "external_documentation",
        "market_rule",
        "calendar_observation",
        "caller_declared",
        "llm_instruction",
        "calculated",
      ]),
    ),
    schema.Required("reference", hash_schema()),
    schema.Required("effectiveAtUnixMilliseconds", schema.integer()),
    schema.Required("retrievedAtUnixMilliseconds", schema.integer()),
    schema.Required("currency", bounded_string(1, 50)),
    schema.Required("unit", bounded_string(1, 100)),
    schema.Required("sourceLexeme", bounded_string(0, 4000)),
    schema.Required("scope", bounded_string(1, 1000)),
    schema.Required(
      "retainedAlternatives",
      schema.array(bounded_string(1, 1000)) |> schema.with_array_length(0, 100),
    ),
  ])
}

fn policy_schema() -> schema.Schema {
  schema.object([
    schema.Required("model", schema.string_enum(["bar_possible_paths_v1"])),
    schema.Required("calculationPolicy", schema.string_enum(["limit_touch_v1"])),
    schema.Required(
      "capabilityPolicy",
      schema.string_enum(["record_only_v1", "require_known_true_v1"]),
    ),
    schema.Required("branchPolicy", schema.string_enum(["all_branches"])),
    schema.Required("sessionScope", bounded_string(1, 500)),
    schema.Required("dateTimeScope", bounded_string(1, 500)),
    schema.Required("currencyPolicy", bounded_string(1, 500)),
    schema.Required("rounding", rounding_schema()),
    schema.Required("references", reference_set_schema()),
    schema.Required(
      "maximumBranches",
      schema.integer() |> schema.with_number_range(1.0, 100.0),
    ),
    schema.Required(
      "maximumOutputs",
      schema.integer() |> schema.with_number_range(1.0, 100.0),
    ),
    schema.Required(
      "maximumBytes",
      schema.integer() |> schema.with_number_range(1.0, 1_000_000.0),
    ),
    schema.Required(
      "maximumOperations",
      schema.integer() |> schema.with_number_range(1.0, 100.0),
    ),
    schema.Required("projection", schema.string_enum(["compact", "receipt"])),
  ])
}

fn rounding_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "outputScale",
      schema.integer() |> schema.with_number_range(0.0, 30.0),
    ),
    schema.Required(
      "mode",
      schema.string_enum([
        "toward_zero",
        "away_from_zero",
        "half_up",
        "half_even",
      ]),
    ),
  ])
}

fn reference_set_schema() -> schema.Schema {
  schema.object([
    schema.Required("capabilityReferences", hash_array(0, 500)),
    schema.Required("ruleReferences", hash_array(0, 500)),
    schema.Required("calendarReferences", hash_array(0, 500)),
    schema.Required("marketEventReferences", hash_array(0, 500)),
    schema.Required("lifecycleReferences", hash_array(0, 500)),
    schema.Required("positionReferences", hash_array(0, 500)),
    schema.Required("riskReceiptReferences", hash_array(0, 500)),
    schema.Required("costReceiptReferences", hash_array(0, 500)),
    schema.Required("fxReceipts", hash_array(0, 500)),
  ])
}

fn bounded_string(minimum: Int, maximum: Int) -> schema.Schema {
  schema.string() |> schema.with_string_length(minimum, maximum)
}

fn hash_schema() -> schema.Schema {
  bounded_string(64, 64)
}

fn hash_array(minimum: Int, maximum: Int) -> schema.Schema {
  schema.array(hash_schema()) |> schema.with_array_length(minimum, maximum)
}
