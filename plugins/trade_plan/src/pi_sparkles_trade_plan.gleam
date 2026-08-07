import gleam/javascript/promise.{type Promise}
import pi
import pi/schema
import pi/tool
import pi_sparkles_trade_plan/decode
import pi_sparkles_trade_plan/domain

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  register_loss(api)
  register_bounds(api)
  register_grid(api)
  promise.resolve(Nil)
}

fn register_loss(api: pi.ExtensionApi) -> Nil {
  tool.register(
    api,
    "plan_loss",
    "Calculate exact long planned loss",
    "Calculate long_planned_loss_per_unit_v1 for exact caller-supplied entry and stop facts, preserving provenance and unavailable operands without a plan or quantity decision",
    "Supply the exact facts and policies; the LLM interprets the mechanical result and chooses every follow-up",
    tool.parameters(loss_schema(), decode.plan_loss()),
    tool.Parallel,
    fn(_id, input, _signal, _updates, _ctx) { complete(domain.run_loss(input)) },
  )
}

fn register_bounds(api: pi.ExtensionApi) -> Nil {
  tool.register(
    api,
    "plan_bounds",
    "Calculate independent quantity bounds",
    "Calculate every explicitly named amount-over-denominator bound on one supplied trade-unit fact and only an explicitly requested intersection; return raw, whole-share, and grid facts without selecting a constraint or quantity",
    "Supply every bound, fact, grid, and optional intersection explicitly; the LLM chooses what the results mean",
    tool.parameters(bounds_schema(), decode.plan_bounds()),
    tool.Parallel,
    fn(_id, input, _signal, _updates, _ctx) {
      complete(domain.run_bounds(input))
    },
  )
}

fn register_grid(api: pi.ExtensionApi) -> Nil {
  tool.register(
    api,
    "plan_grid_projection",
    "Project one bound onto a supplied quantity grid",
    "Calculate one exact bound and project it onto one exact caller-supplied trade-unit fact; return raw and projection evidence without a selected or recommended quantity",
    "Supply the exact bound calculation and trade-unit fact selected by the LLM",
    tool.parameters(grid_schema(), decode.plan_grid_projection()),
    tool.Parallel,
    fn(_id, input, _signal, _updates, _ctx) { complete(domain.run_grid(input)) },
  )
}

fn complete(
  value: Result(domain.Response, domain.DomainError),
) -> Promise(tool.ToolResult) {
  case value {
    Ok(value) ->
      tool.text_result(domain.summary(value), domain.details(value))
      |> promise.resolve
    Error(error) -> tool.reject(domain.error_message(error))
  }
}

fn loss_schema() -> schema.Schema {
  schema.object([
    schema.Required("common", common_schema()),
    schema.Required("operationId", bounded_string(1, 500)),
    schema.Required("entry", decimal_fact_schema()),
    schema.Required("stop", decimal_fact_schema()),
  ])
}

fn bounds_schema() -> schema.Schema {
  schema.object([
    schema.Required("common", common_schema()),
    schema.Required(
      "bounds",
      schema.array(bound_schema()) |> schema.with_array_length(1, 50),
    ),
    schema.Required("tradeUnit", trade_unit_fact_schema()),
    schema.Required("intersection", intersection_schema()),
  ])
}

fn grid_schema() -> schema.Schema {
  schema.object([
    schema.Required("common", common_schema()),
    schema.Required("bound", bound_schema()),
    schema.Required("tradeUnit", trade_unit_fact_schema()),
  ])
}

fn common_schema() -> schema.Schema {
  schema.object([
    schema.Required("context", context_schema()),
    schema.Required("rounding", rounding_schema()),
    schema.Required("branchPolicy", branch_policy_schema()),
    schema.Required(
      "maximumOperations",
      schema.integer() |> schema.with_number_range(1.0, 100.0),
    ),
    schema.Required(
      "maximumOutputs",
      schema.integer() |> schema.with_number_range(1.0, 100.0),
    ),
    schema.Required("projection", schema.string_enum(["compact", "receipt"])),
  ])
}

fn context_schema() -> schema.Schema {
  schema.object([
    schema.Required("instructionRef", hash_schema()),
    schema.Required("accountScope", bounded_string(1, 500)),
    schema.Required("portfolioScope", bounded_string(1, 500)),
    schema.Required("track", schema.string_enum(["cn", "hk", "us"])),
    schema.Required("listingId", bounded_string(1, 500)),
    schema.Required("asOfUnixMilliseconds", schema.integer()),
    schema.Required("nativeCurrency", bounded_string(3, 3)),
    schema.Required(
      "evidenceRoots",
      schema.array(hash_schema()) |> schema.with_array_length(0, 500),
    ),
  ])
}

fn rounding_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "mode",
      schema.string_enum([
        "toward_zero",
        "away_from_zero",
        "half_up",
        "half_even",
      ]),
    ),
    schema.Required("policy", schema.string_enum(["final_only"])),
    schema.Required(
      "outputScale",
      schema.integer() |> schema.with_number_range(0.0, 30.0),
    ),
    schema.Required(
      "intermediateScale",
      schema.integer() |> schema.with_number_range(0.0, 30.0),
    ),
  ])
}

fn branch_policy_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "kind",
      schema.string_enum(["all_branches", "selected_branch"]),
    ),
    schema.Optional("branchId", schema.nullable(bounded_string(1, 500))),
    schema.Optional("instructionRef", schema.nullable(hash_schema())),
  ])
  |> schema.described(
    "all_branches forbids branch fields; selected_branch requires branchId and instructionRef",
  )
}

fn bound_schema() -> schema.Schema {
  schema.object([
    schema.Required("boundId", bounded_string(1, 500)),
    schema.Required("formulaVariant", bound_formula_schema()),
    schema.Required("numeratorName", bounded_string(1, 500)),
    schema.Required("numerator", decimal_fact_schema()),
    schema.Required("denominator", denominator_schema()),
  ])
}

fn bound_formula_schema() -> schema.Schema {
  schema.string_enum([
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
  ])
}

fn denominator_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "kind",
      schema.string_enum([
        "long_planned_loss_per_unit_v1",
        "supplied_denominator_v1",
      ]),
    ),
    schema.Optional("operandName", schema.nullable(bounded_string(1, 500))),
    schema.Optional(
      "formulaVariant",
      schema.nullable(
        schema.string_enum([
          "desired_entry_value_v1",
          "gap_loss_per_unit_supplied_v1",
          "supplied_loss_per_unit_v1",
          "supplied_denominator_v1",
        ]),
      ),
    ),
    schema.Optional("outputUnit", schema.nullable(bounded_string(1, 500))),
    schema.Optional("value", schema.nullable(decimal_fact_schema())),
    schema.Optional("entry", schema.nullable(decimal_fact_schema())),
    schema.Optional("stop", schema.nullable(decimal_fact_schema())),
  ])
  |> schema.described(
    "planned-loss kind requires only entry+stop; supplied kind requires only operandName+formulaVariant+outputUnit+value",
  )
}

fn intersection_schema() -> schema.Schema {
  schema.object([
    schema.Required("state", schema.string_enum(["not_requested", "requested"])),
    schema.Optional("operationId", schema.nullable(bounded_string(1, 500))),
    schema.Required(
      "selectedBoundIds",
      schema.array(bounded_string(1, 500)) |> schema.with_array_length(0, 50),
    ),
  ])
  |> schema.described(
    "not_requested requires an empty ID list and no operationId; requested requires both",
  )
}

fn decimal_fact_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "state",
      schema.string_enum([
        "known",
        "unknown",
        "not_obtained",
        "conflicting",
        "decode_failure",
      ]),
    ),
    schema.Optional("value", schema.nullable(bounded_string(1, 500))),
    schema.Optional("source", schema.nullable(source_schema())),
    schema.Optional("reason", schema.nullable(bounded_string(1, 4000))),
    schema.Optional("raw", schema.nullable(bounded_string(1, 4000))),
    schema.Optional(
      "alternatives",
      schema.array(decimal_sourced_schema()) |> schema.with_array_length(0, 20),
    ),
  ])
  |> schema.described(
    "Fact state determines the exact required fields; conflicting requires 2-20 alternatives",
  )
}

fn decimal_sourced_schema() -> schema.Schema {
  schema.object([
    schema.Required("value", bounded_string(1, 500)),
    schema.Required("source", source_schema()),
  ])
}

fn trade_unit_fact_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "state",
      schema.string_enum([
        "known",
        "unknown",
        "not_obtained",
        "conflicting",
        "decode_failure",
      ]),
    ),
    schema.Optional("value", schema.nullable(trade_unit_value_schema())),
    schema.Optional("source", schema.nullable(source_schema())),
    schema.Optional("reason", schema.nullable(bounded_string(1, 4000))),
    schema.Optional("raw", schema.nullable(bounded_string(1, 4000))),
    schema.Optional(
      "alternatives",
      schema.array(trade_unit_sourced_schema())
        |> schema.with_array_length(0, 20),
    ),
  ])
  |> schema.described(
    "Fact state determines the exact required fields; conflicting requires 2-20 alternatives",
  )
}

fn trade_unit_value_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "minimum",
      schema.integer() |> schema.with_number_range(1.0, 9_007_199_254_740_991.0),
    ),
    schema.Required(
      "increment",
      schema.integer() |> schema.with_number_range(1.0, 9_007_199_254_740_991.0),
    ),
  ])
}

fn trade_unit_sourced_schema() -> schema.Schema {
  schema.object([
    schema.Required("value", trade_unit_value_schema()),
    schema.Required("source", source_schema()),
  ])
}

fn source_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "kind",
      schema.string_enum([
        "provider_observation",
        "market_rule",
        "custodian_observation",
        "caller_declared",
        "llm_instruction",
        "calculated",
      ]),
    ),
    schema.Required("reference", hash_schema()),
    schema.Required("effectiveAtUnixMilliseconds", schema.integer()),
    schema.Required("retrievedAtUnixMilliseconds", schema.integer()),
    schema.Required("currency", bounded_string(1, 20)),
    schema.Required("unit", bounded_string(1, 200)),
    schema.Required("sourceLexeme", bounded_string(1, 4000)),
    schema.Required("scope", bounded_string(1, 1000)),
    schema.Required(
      "retainedAlternatives",
      schema.array(bounded_string(1, 1000)) |> schema.with_array_length(0, 100),
    ),
  ])
}

fn hash_schema() -> schema.Schema {
  schema.string() |> schema.with_string_length(64, 64)
}

fn bounded_string(minimum: Int, maximum: Int) -> schema.Schema {
  schema.string() |> schema.with_string_length(minimum, maximum)
}
