import gleam/javascript/promise.{type Promise}
import pi
import pi/schema
import pi/tool
import pi_sparkles_stock_technicals/decode
import pi_sparkles_stock_technicals/domain

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  register_sma(api)
  register_rsi(api)
  register_atr(api)
  promise.resolve(Nil)
}

fn register_sma(api: pi.ExtensionApi) -> Nil {
  tool.register(
    api,
    "sma",
    "Exact simple moving average",
    "Calculate explicitly requested sma_v1 values over exact caller-supplied observations. When CN, HK, or US history/OHLCV rows are available, use SMA evidence for ordinary buy-now, sell-timing, entry, exit, trend, or timing questions even when the user does not name an indicator or explicitly request tools; call this tool instead of writing or executing calculation code",
    "Map the returned CSV close column to observations for relevant current-data-dependent opinions and copy its model-visible source/receipt metadata; omit instructionRef unless a real retained hash already exists—the plugin derives it, so never calculate it with a script",
    tool.parameters(sma_schema(), decode.sma()),
    tool.Parallel,
    fn(_id, input, _signal, _updates, _ctx) { complete(domain.run_sma(input)) },
  )
}

fn register_rsi(api: pi.ExtensionApi) -> Nil {
  tool.register(
    api,
    "rsi",
    "Exact Wilder RSI",
    "Calculate explicitly requested rsi_wilder_v1 values over exact caller-supplied observations. When CN, HK, or US history/OHLCV rows are available, use RSI evidence for ordinary buy-now, sell-timing, entry, exit, momentum, or timing questions even when the user does not name an indicator or explicitly request tools; call this tool instead of writing or executing calculation code",
    "Map the returned CSV close column to observations for relevant current-data-dependent opinions and copy its model-visible source/receipt metadata; omit instructionRef unless a real retained hash already exists—the plugin derives it, so never calculate it with a script",
    tool.parameters(rsi_schema(), decode.rsi()),
    tool.Parallel,
    fn(_id, input, _signal, _updates, _ctx) { complete(domain.run_rsi(input)) },
  )
}

fn register_atr(api: pi.ExtensionApi) -> Nil {
  tool.register(
    api,
    "atr",
    "Exact Wilder ATR",
    "Calculate explicitly requested atr_wilder_v1 values over exact caller-supplied high/low/close facts. When CN, HK, or US history/OHLCV rows are available, use ATR evidence for ordinary buy-now, sell-timing, stop, target, volatility, or timing questions even when the user does not name an indicator or explicitly request tools; call this tool instead of writing or executing calculation code",
    "Map the returned CSV high, low, and close columns to bars for relevant current-data-dependent opinions and copy its model-visible source/receipt metadata; omit instructionRef unless a real retained hash already exists—the plugin derives it, so never calculate it with a script",
    tool.parameters(atr_schema(), decode.atr()),
    tool.Parallel,
    fn(_id, input, _signal, _updates, _ctx) { complete(domain.run_atr(input)) },
  )
}

fn complete(
  value: Result(domain.Response, domain.DomainError),
) -> Promise(tool.ToolResult) {
  case value {
    Ok(value) ->
      tool.text_result(domain.model_content(value), domain.details(value))
      |> promise.resolve
    Error(error) -> tool.reject(domain.error_message(error))
  }
}

fn sma_schema() -> schema.Schema {
  schema.object([
    schema.Required("context", context_schema()),
    schema.Required("calculation", sma_calculation_schema()),
    schema.Required("projection", projection_schema()),
    schema.Required(
      "observations",
      schema.array(observation_schema()) |> schema.with_array_length(1, 2000),
    ),
  ])
}

fn rsi_schema() -> schema.Schema {
  schema.object([
    schema.Required("context", context_schema()),
    schema.Required("calculation", rsi_calculation_schema()),
    schema.Required("projection", projection_schema()),
    schema.Required(
      "observations",
      schema.array(observation_schema()) |> schema.with_array_length(1, 2000),
    ),
  ])
}

fn atr_schema() -> schema.Schema {
  schema.object([
    schema.Required("context", context_schema()),
    schema.Required("calculation", atr_calculation_schema()),
    schema.Required("projection", projection_schema()),
    schema.Required(
      "bars",
      schema.array(bar_schema()) |> schema.with_array_length(1, 2000),
    ),
  ])
}

fn context_schema() -> schema.Schema {
  schema.object([
    schema.Optional(
      "instructionRef",
      schema.nullable(hash_schema())
        |> schema.described(
          "Optional SHA-256 of a retained caller/LLM instruction. Omit it during ordinary history-to-indicator handoff; the plugin derives a deterministic reference from the canonical calculation request",
        ),
    ),
    schema.Required("track", schema.string_enum(["cn", "hk", "us"])),
    schema.Required("instrumentId", bounded_string(1, 200)),
    schema.Required("mic", bounded_string(1, 20)),
    schema.Required("timezone", bounded_string(1, 100)),
    schema.Required("dateStart", date_schema()),
    schema.Required("dateEnd", date_schema()),
    schema.Required("source", source_schema()),
    schema.Required(
      "inputField",
      bounded_string(1, 100)
        |> schema.described(
          "Exact caller-selected field or named input projection",
        ),
    ),
    schema.Required("inputUnit", unit_schema()),
    schema.Required("basis", basis_schema()),
    schema.Required(
      "retainedAlternatives",
      schema.array(bounded_string(1, 2000))
        |> schema.with_array_length(0, 2000),
    ),
    schema.Required(
      "gapFacts",
      schema.array(bounded_string(1, 2000))
        |> schema.with_array_length(0, 2000),
    ),
    schema.Required(
      "evidenceRoots",
      schema.array(hash_schema()) |> schema.with_array_length(0, 2000),
    ),
  ])
}

fn source_schema() -> schema.Schema {
  schema.object([
    schema.Required("provider", bounded_string(1, 200)),
    schema.Required("sourceReference", bounded_string(1, 4000)),
    schema.Required("acquisitionReceipt", hash_schema()),
    schema.Required("retrievalTimeUnixMilliseconds", schema.integer()),
    schema.Optional(
      "sourceCutoffUnixMilliseconds",
      schema.nullable(schema.integer()),
    ),
  ])
}

fn unit_schema() -> schema.Schema {
  schema.object([
    schema.Required("state", schema.string_enum(["known", "unknown"])),
    schema.Optional("label", schema.nullable(bounded_string(1, 200))),
    schema.Optional("reason", schema.nullable(bounded_string(1, 1000))),
  ])
  |> schema.described(
    "Known requires label; unknown requires reason. The plugin does not infer a unit.",
  )
}

fn basis_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "kind",
      schema.string_enum([
        "raw",
        "split_adjusted",
        "dividend_adjusted",
        "total_return",
        "provider_defined",
        "llm_projection",
      ]),
    ),
    schema.Optional("label", schema.nullable(bounded_string(1, 500))),
    schema.Optional("instructionRef", schema.nullable(hash_schema())),
    schema.Required(
      "evidenceRoots",
      schema.array(hash_schema()) |> schema.with_array_length(0, 2000),
    ),
  ])
  |> schema.described(
    "Exact input basis supplied by the LLM; this tool does not adjust observations. For raw basis, evidenceRoots may be empty or contain source evidence accidentally copied during handoff; such roots are preserved as context evidence, not treated as adjustment factors",
  )
}

fn sma_calculation_schema() -> schema.Schema {
  schema.object([
    schema.Required("formulaVariant", schema.string_enum(["sma_v1"])),
    schema.Required("period", bounded_period()),
    schema.Required("windowVariant", schema.string_enum(["slot_window_v1"])),
    schema.Required("parseablePolicy", parseable_schema()),
    schema.Required("rounding", rounding_schema()),
    ..rounding_alias_schema()
  ])
}

fn rsi_calculation_schema() -> schema.Schema {
  schema.object([
    schema.Required("formulaVariant", schema.string_enum(["rsi_wilder_v1"])),
    schema.Required("period", bounded_period()),
    schema.Required("windowVariant", schema.string_enum(["slot_window_v1"])),
    schema.Required("seedVariant", schema.string_enum(["seed_wilder_first_n"])),
    schema.Required("gapPolicy", schema.string_enum(["stop_at_gap_v1"])),
    schema.Required(
      "zeroZeroConvention",
      schema.string_enum(["zero_zero_unperformed_v1"]),
    ),
    schema.Required("parseablePolicy", parseable_schema()),
    schema.Required("rounding", rounding_schema()),
    ..rounding_alias_schema()
  ])
}

fn atr_calculation_schema() -> schema.Schema {
  schema.object([
    schema.Required("formulaVariant", schema.string_enum(["atr_wilder_v1"])),
    schema.Required("period", bounded_period()),
    schema.Required("windowVariant", schema.string_enum(["slot_window_v1"])),
    schema.Required(
      "seedVariant",
      schema.string_enum(["seed_wilder_tr_mean_v1"]),
    ),
    schema.Required("firstTrueRange", schema.string_enum(["tr_first_hl_v1"])),
    schema.Required("gapPolicy", schema.string_enum(["stop_at_gap_v1"])),
    schema.Required("parseablePolicy", parseable_schema()),
    schema.Required("rounding", rounding_schema()),
    ..rounding_alias_schema()
  ])
}

fn rounding_alias_schema() -> List(schema.Property) {
  [
    schema.Optional(
      "policy",
      schema.nullable(schema.string_enum(["per_step"]))
        |> schema.described(
          "Compatibility alias sometimes repeated by an LLM; when present it must match rounding.policy",
        ),
    ),
    schema.Optional(
      "outputScale",
      schema.nullable(schema.integer() |> schema.with_number_range(0.0, 30.0))
        |> schema.described(
          "Compatibility alias sometimes repeated by an LLM; when present it must match rounding.outputScale",
        ),
    ),
    schema.Optional(
      "intermediateScale",
      schema.nullable(schema.integer() |> schema.with_number_range(0.0, 30.0))
        |> schema.described(
          "Compatibility alias sometimes repeated by an LLM; when present it must match rounding.intermediateScale",
        ),
    ),
  ]
}

fn parseable_schema() -> schema.Schema {
  schema.string_enum([
    "include_parseable_with_checks",
    "exclude_parseable_with_checks",
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
    schema.Required("policy", schema.string_enum(["per_step"])),
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

fn projection_schema() -> schema.Schema {
  schema.object([
    schema.Required("kind", schema.string_enum(["compact", "intermediate"])),
    schema.Required(
      "priorOffset",
      schema.integer() |> schema.with_number_range(1.0, 2000.0),
    ),
  ])
  |> schema.described(
    "Caller-selected output projection; prior offset counts calculated values newest-first",
  )
}

fn observation_schema() -> schema.Schema {
  schema.object([
    schema.Required("date", date_schema()),
    schema.Required("value", fact_schema()),
  ])
}

fn bar_schema() -> schema.Schema {
  schema.object([
    schema.Required("date", date_schema()),
    schema.Required("high", fact_schema()),
    schema.Required("low", fact_schema()),
    schema.Required("close", fact_schema()),
  ])
}

fn fact_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "state",
      schema.string_enum([
        "known",
        "parseable_with_failed_checks",
        "unknown",
        "not_obtained",
        "decode_failure",
        "conflicting",
      ]),
    ),
    schema.Optional("raw", schema.nullable(bounded_string(1, 500))),
    schema.Optional("reason", schema.nullable(bounded_string(1, 2000))),
    schema.Optional(
      "failedChecks",
      schema.array(bounded_string(1, 500)) |> schema.with_array_length(0, 100),
    ),
    schema.Optional(
      "alternatives",
      schema.array(alternative_schema()) |> schema.with_array_length(0, 100),
    ),
  ])
  |> schema.described(
    "Exact numeric fact; state determines which optional evidence fields are required",
  )
}

fn alternative_schema() -> schema.Schema {
  schema.object([
    schema.Required("raw", bounded_string(1, 500)),
    schema.Required("sourceReference", bounded_string(1, 4000)),
  ])
}

fn bounded_period() -> schema.Schema {
  schema.integer() |> schema.with_number_range(1.0, 2000.0)
}

fn hash_schema() -> schema.Schema {
  schema.string() |> schema.with_string_length(64, 64)
}

fn date_schema() -> schema.Schema {
  schema.string()
  |> schema.with_string_length(10, 10)
  |> schema.described("Exact Gregorian date in YYYY-MM-DD form")
}

fn bounded_string(minimum: Int, maximum: Int) -> schema.Schema {
  schema.string() |> schema.with_string_length(minimum, maximum)
}
