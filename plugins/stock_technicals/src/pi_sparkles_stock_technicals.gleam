import finance_indicators/chart_handoff
import gleam/javascript/promise.{type Promise}
import pi
import pi/raw
import pi/schema
import pi/tool
import pi_sparkles_stock_technicals/decode
import pi_sparkles_stock_technicals/domain
import pi_sparkles_stock_technicals/handoff
import pi_sparkles_stock_technicals/return_comparison

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  register_sma(api)
  register_rsi(api)
  register_atr(api)
  register_return_comparison(api)
  promise.resolve(Nil)
}

fn register_return_comparison(api: pi.ExtensionApi) -> Nil {
  tool.register_compact(
    api,
    "compare_series_returns",
    "Compare exact receipt-bound series returns",
    "Verify an explicit content-bound multi-series handoff and mechanically calculate latest-session, five-session, and requested-window relative returns without selecting a provider, universe, identity, or source",
    "Use after an acquisition tool supplies comparisonInput and expectedInputSha256. Copy both unchanged; this calculator makes no network request and its ordering is only over the caller-selected input series, not proof of market completeness or a recommendation",
    tool.parameters(return_comparison_schema(), return_comparison.decoder()),
    tool.Parallel,
    fn(_id, input, _signal, _updates, _ctx) {
      case return_comparison.run(input) {
        Ok(output) ->
          tool.text_result(
            return_comparison.model_content(output),
            return_comparison.details(output),
          )
          |> promise.resolve
        Error(error) -> tool.reject(return_comparison.error_message(error))
      }
    },
  )
}

fn register_sma(api: pi.ExtensionApi) -> Nil {
  tool.register_compact(
    api,
    "sma",
    "Exact simple moving average",
    "Calculate explicitly requested sma_v1 values over exact caller-supplied observations or one verified active-session OHLCV series receipt. When CN, HK, or US history/OHLCV rows are available, use SMA evidence for ordinary buy-now, sell-timing, entry, exit, trend, or timing questions even when the user does not name an indicator or explicitly request tools; call this tool instead of writing or executing calculation code",
    "When history returns seriesReceipt, pass only seriesReceipt plus calculation and projection; omit context and observations and never copy the CSV rows. Use context plus observations only for an external series with no session receipt. Omit instructionRef unless a real retained hash already exists—the plugin derives it, so never calculate it with a script",
    tool.parameters(sma_schema(), decode.sma()),
    tool.Parallel,
    fn(_id, input, _signal, _updates, ctx) {
      case handoff.resolve_sma(input, ctx) {
        Ok(value) -> complete(api, domain.run_sma(value))
        Error(message) -> tool.reject(message)
      }
    },
  )
}

fn register_rsi(api: pi.ExtensionApi) -> Nil {
  tool.register_compact(
    api,
    "rsi",
    "Exact Wilder RSI",
    "Calculate explicitly requested rsi_wilder_v1 values over exact caller-supplied observations or one verified active-session OHLCV series receipt. When CN, HK, or US history/OHLCV rows are available, use RSI evidence for ordinary buy-now, sell-timing, entry, exit, momentum, or timing questions even when the user does not name an indicator or explicitly request tools; call this tool instead of writing or executing calculation code",
    "When history returns seriesReceipt, pass only seriesReceipt plus calculation and projection; omit context and observations and never copy the CSV rows. Use context plus observations only for an external series with no session receipt. Omit instructionRef unless a real retained hash already exists—the plugin derives it, so never calculate it with a script",
    tool.parameters(rsi_schema(), decode.rsi()),
    tool.Parallel,
    fn(_id, input, _signal, _updates, ctx) {
      case handoff.resolve_rsi(input, ctx) {
        Ok(value) -> complete(api, domain.run_rsi(value))
        Error(message) -> tool.reject(message)
      }
    },
  )
}

fn register_atr(api: pi.ExtensionApi) -> Nil {
  tool.register_compact(
    api,
    "atr",
    "Exact Wilder ATR",
    "Calculate explicitly requested atr_wilder_v1 values over exact caller-supplied high/low/close facts or one verified active-session OHLCV series receipt. When CN, HK, or US history/OHLCV rows are available, use ATR evidence for ordinary buy-now, sell-timing, stop, target, volatility, or timing questions even when the user does not name an indicator or explicitly request tools; call this tool instead of writing or executing calculation code",
    "When history returns seriesReceipt, pass only seriesReceipt plus calculation and projection; omit context and bars and never copy the CSV rows. Use context plus bars only for an external series with no session receipt. Omit instructionRef unless a real retained hash already exists—the plugin derives it, so never calculate it with a script",
    tool.parameters(atr_schema(), decode.atr()),
    tool.Parallel,
    fn(_id, input, _signal, _updates, ctx) {
      case handoff.resolve_atr(input, ctx) {
        Ok(value) -> complete(api, domain.run_atr(value))
        Error(message) -> tool.reject(message)
      }
    },
  )
}

fn complete(
  api: pi.ExtensionApi,
  value: Result(domain.Response, domain.DomainError),
) -> Promise(tool.ToolResult) {
  case value {
    Ok(value) -> {
      let handoff = domain.chart_handoff(value)
      pi.append_entry(
        api,
        chart_handoff.event_type,
        raw.dynamic(chart_handoff.encode(handoff)),
      )
      tool.text_result(domain.model_content(value), domain.details(value))
      |> promise.resolve
    }
    Error(error) -> tool.reject(domain.error_message(error))
  }
}

fn sma_schema() -> schema.Schema {
  schema.object([
    schema.Optional("seriesReceipt", series_receipt_schema()),
    schema.Optional("context", context_schema()),
    schema.Required("calculation", sma_calculation_schema()),
    schema.Required("projection", projection_schema()),
    schema.Optional(
      "observations",
      schema.array(observation_schema()) |> schema.with_array_length(1, 2000),
    ),
  ])
}

fn rsi_schema() -> schema.Schema {
  schema.object([
    schema.Optional("seriesReceipt", series_receipt_schema()),
    schema.Optional("context", context_schema()),
    schema.Required("calculation", rsi_calculation_schema()),
    schema.Required("projection", projection_schema()),
    schema.Optional(
      "observations",
      schema.array(observation_schema()) |> schema.with_array_length(1, 2000),
    ),
  ])
}

fn atr_schema() -> schema.Schema {
  schema.object([
    schema.Optional("seriesReceipt", series_receipt_schema()),
    schema.Optional("context", context_schema()),
    schema.Required("calculation", atr_calculation_schema()),
    schema.Required("projection", projection_schema()),
    schema.Optional(
      "bars",
      schema.array(bar_schema()) |> schema.with_array_length(1, 2000),
    ),
  ])
}

fn series_receipt_schema() -> schema.Schema {
  hash_schema()
  |> schema.described(
    "Exact seriesReceipt returned by a history tool in this active Pi/DSH session. When present, omit context and observations/bars; the plugin verifies and resolves the stored OHLCV rows without model-side copying",
  )
}

fn return_comparison_schema() -> schema.Schema {
  schema.object([
    schema.Required("expectedInputSha256", hash_schema()),
    schema.Required(
      "comparisonInput",
      schema.object([
        schema.Required(
          "schema",
          schema.string_enum(["pi-sparkles/series-return-comparison-input"]),
        ),
        schema.Required(
          "schemaVersion",
          schema.integer() |> schema.with_number_range(1.0, 1.0),
        ),
        schema.Required("track", schema.string_enum(["cn", "hk", "us"])),
        schema.Required("sourceProfile", bounded_string(1, 500)),
        schema.Required("requestedStartDate", date_schema()),
        schema.Required("requestedEndDate", date_schema()),
        schema.Required(
          "series",
          schema.array(return_series_schema())
            |> schema.with_array_length(2, 50),
        ),
      ]),
    ),
  ])
}

fn return_series_schema() -> schema.Schema {
  schema.object([
    schema.Required("seriesId", bounded_string(1, 200)),
    schema.Required("label", bounded_string(1, 500)),
    schema.Required("unit", bounded_string(1, 200)),
    schema.Required("authorityLabel", bounded_string(1, 500)),
    schema.Required("providerName", bounded_string(1, 500)),
    schema.Required(
      "source",
      schema.object([
        schema.Required("provider", bounded_string(1, 200)),
        schema.Required("sourceReference", bounded_string(1, 4000)),
        schema.Required("acquisitionReceipt", hash_schema()),
        schema.Required("retrievalTimeUnixMilliseconds", schema.integer()),
        schema.Required(
          "responseBytes",
          schema.integer() |> schema.with_number_range(1.0, 2_000_000.0),
        ),
      ]),
    ),
    schema.Required(
      "observations",
      schema.array(
        schema.object([
          schema.Required(
            "role",
            schema.string_enum([
              "window_start",
              "five_sessions_ago",
              "previous_session",
              "latest",
            ]),
          ),
          schema.Required("date", date_schema()),
          schema.Required("value", bounded_string(1, 500)),
        ]),
      )
        |> schema.with_array_length(4, 4),
    ),
    schema.Required(
      "availableObservationCount",
      schema.integer() |> schema.with_number_range(6.0, 2000.0),
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
    schema.Optional("label", bounded_string(1, 500)),
    schema.Optional("instructionRef", hash_schema()),
    schema.Required(
      "evidenceRoots",
      schema.array(hash_schema()) |> schema.with_array_length(0, 2000),
    ),
  ])
  |> schema.described(
    "Exact input basis supplied by the LLM; this tool does not adjust observations. raw, split_adjusted, dividend_adjusted, and total_return forbid label and instructionRef: omit those properties entirely, never send null. provider_defined requires label and forbids instructionRef; llm_projection requires both. For raw basis, evidenceRoots may be empty or contain source evidence accidentally copied during handoff; such roots are preserved as context evidence, not treated as adjustment factors",
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
    "Caller-selected output projection; priorOffset is one-based from 1 through 2000 and counts calculated values newest-first, so use 1 for the newest calculated value and never 0",
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
