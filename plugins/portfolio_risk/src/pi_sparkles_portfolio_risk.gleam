import gleam/javascript/promise.{type Promise}
import pi
import pi/schema
import pi/tool
import pi_sparkles_portfolio_risk/decode
import pi_sparkles_portfolio_risk/domain

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  tool.register(
    api,
    "portfolio_risk",
    "Calculate exact portfolio exposure and heat",
    "Calculate only explicitly requested long-only, single-currency exposure, weight, signed mark-minus-stop heat, contribution, reconciliation, temporal, unknown, and conflict facts over caller-supplied position and account inputs",
    "Supply exact facts, formula variants, information policy, denominator, rounding, and requested fields; the LLM owns every threshold, interpretation, response, and next operation",
    tool.parameters(input_schema(), decode.portfolio_risk()),
    tool.Parallel,
    fn(_id, input, _signal, _updates, _ctx) {
      case domain.run(input) {
        Ok(output) ->
          tool.text_result(output.summary, output.details)
          |> promise.resolve
        Error(error) -> tool.reject(domain.error_message(error))
      }
    },
  )
  promise.resolve(Nil)
}

fn input_schema() -> schema.Schema {
  schema.object([
    schema.Required("portfolioId", bounded_string(1, 500)),
    schema.Required("instructionRef", hash_schema()),
    schema.Required("account", account_schema()),
    schema.Required(
      "positions",
      schema.array(position_schema()) |> schema.with_array_length(0, 500),
    ),
    schema.Required("calculation", calculation_schema()),
    schema.Required(
      "requestedSummaryFields",
      schema.array(
        schema.string_enum([
          "position_count",
          "gross_market_exposure",
          "net_market_exposure",
          "portfolio_heat",
          "heat_pct",
          "largest_position_weight",
          "position_contributions",
          "reconciliation",
          "temporal_coherence",
          "unknown_count",
          "conflict_count",
          "receipt_handle",
        ]),
      )
        |> schema.with_array_length(1, 12),
    ),
    schema.Required("projection", schema.string_enum(["compact", "receipt"])),
  ])
}

fn account_schema() -> schema.Schema {
  schema.object([
    schema.Required("accountId", bounded_string(1, 500)),
    schema.Required("netLiquidationValue", decimal_fact_schema()),
    schema.Optional("cashBalance", schema.nullable(decimal_fact_schema())),
    schema.Optional("liabilities", schema.nullable(decimal_fact_schema())),
    schema.Required("accountCurrency", bounded_string(3, 3)),
    schema.Required("asOfUnixMilliseconds", safe_integer()),
    schema.Required(
      "sourceKind",
      schema.string_enum(["custodian_observation", "caller_declared"]),
    ),
    schema.Required("sourceReceipt", hash_schema()),
  ])
}

fn position_schema() -> schema.Schema {
  schema.object([
    schema.Required("positionId", bounded_string(1, 500)),
    schema.Required("listingId", bounded_string(1, 500)),
    schema.Required("mic", bounded_string(4, 4)),
    schema.Required("track", schema.string_enum(["cn", "hk", "us"])),
    schema.Required("direction", schema.string_enum(["long", "short"])),
    schema.Required("quantity", decimal_fact_schema()),
    schema.Required("quantityUnit", schema.string_enum(["shares", "lots"])),
    schema.Optional("lotSize", schema.nullable(decimal_fact_schema())),
    schema.Required("currentMark", decimal_fact_schema()),
    schema.Optional("markTimeUnixMilliseconds", schema.nullable(safe_integer())),
    schema.Optional("costBasis", schema.nullable(decimal_fact_schema())),
    schema.Required("desiredStop", decimal_fact_schema()),
    schema.Optional("stopTimeUnixMilliseconds", schema.nullable(safe_integer())),
    schema.Optional("entryPrice", schema.nullable(decimal_fact_schema())),
    schema.Required("positionCurrency", bounded_string(3, 3)),
    schema.Required("asOfUnixMilliseconds", safe_integer()),
  ])
}

fn calculation_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "informationPolicy",
      schema.string_enum(["partial_totals_v1", "all_or_nothing_v1"]),
    ),
    schema.Optional(
      "maxStalenessSeconds",
      schema.nullable(
        schema.integer() |> schema.with_number_range(0.0, 2_147_483_647.0),
      ),
    ),
    schema.Required(
      "heatVariant",
      schema.string_enum(["heat_mark_basis_v1", "heat_entry_basis_v1"]),
    ),
    schema.Optional(
      "heatDenominator",
      schema.nullable(heat_denominator_schema()),
    ),
    schema.Required(
      "positionWeightFormat",
      schema.string_enum(["fraction_v1", "percentage_v1"]),
    ),
    schema.Required(
      "roundingMode",
      schema.string_enum([
        "toward_zero",
        "away_from_zero",
        "half_up",
        "half_even",
      ]),
    ),
    schema.Required(
      "currencyScale",
      schema.integer() |> schema.with_number_range(0.0, 30.0),
    ),
    schema.Required(
      "weightScale",
      schema.integer() |> schema.with_number_range(0.0, 30.0),
    ),
    schema.Required(
      "percentageScale",
      schema.integer() |> schema.with_number_range(0.0, 30.0),
    ),
    schema.Required(
      "intermediateScale",
      schema.integer() |> schema.with_number_range(0.0, 30.0),
    ),
  ])
}

fn heat_denominator_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "kind",
      schema.string_enum(["denom_nlv_v1", "denom_gross_v1", "denom_caller_v1"]),
    ),
    schema.Optional("callerCapital", schema.nullable(decimal_fact_schema())),
  ])
  |> schema.described(
    "denom_caller_v1 requires callerCapital; the other variants forbid it",
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
    "Fact state determines the exact fields; conflicting requires 2-20 alternatives",
  )
}

fn decimal_sourced_schema() -> schema.Schema {
  schema.object([
    schema.Required("value", bounded_string(1, 500)),
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
      ]),
    ),
    schema.Required("reference", hash_schema()),
    schema.Required("effectiveAtUnixMilliseconds", safe_integer()),
    schema.Required("retrievedAtUnixMilliseconds", safe_integer()),
    schema.Required("currency", bounded_string(1, 20)),
    schema.Required("unit", bounded_string(1, 100)),
    schema.Required("sourceLexeme", bounded_string(0, 4000)),
    schema.Required("scope", bounded_string(1, 1000)),
    schema.Required(
      "retainedAlternatives",
      schema.array(bounded_string(1, 4000)) |> schema.with_array_length(0, 20),
    ),
  ])
}

fn hash_schema() -> schema.Schema {
  schema.string() |> schema.with_string_length(64, 64)
}

fn safe_integer() -> schema.Schema {
  schema.integer()
  |> schema.with_number_range(-9_007_199_254_740_991.0, 9_007_199_254_740_991.0)
}

fn bounded_string(minimum: Int, maximum: Int) -> schema.Schema {
  schema.string() |> schema.with_string_length(minimum, maximum)
}
