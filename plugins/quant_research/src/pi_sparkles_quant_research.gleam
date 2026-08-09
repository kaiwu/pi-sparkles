import gleam/javascript/promise.{type Promise}
import pi
import pi/schema
import pi/tool
import pi_sparkles_quant_research/decode
import pi_sparkles_quant_research/domain

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  tool.register(
    api,
    "inspect_trial_ledger",
    "Inspect an exact research trial population",
    "Verify one attributed hypothesis and reconstruct one caller-declared complete append-only finance_replay trial population with exact status counts, stable paging, failures, unknowns, receipts, and optional payload drill-down",
    "Supply every trial event and expected state count explicitly; the plugin does not prune, search, grade, or choose a trial",
    tool.parameters(inspect_schema(), decode.inspect_trial_ledger()),
    tool.Parallel,
    fn(_id, input, _signal, _updates, _ctx) {
      case domain.inspect_trial_ledger(input) {
        Ok(value) ->
          tool.text_result(value.summary, value.details)
          |> promise.resolve
        Error(error) -> tool.reject(domain.error_message(error))
      }
    },
  )
  tool.register(
    api,
    "request_metric",
    "Calculate one exact requested replay metric",
    "Execute one caller-selected finance_replay net-return, win/loss/tie, drawdown-series, or trade-list calculation with exact metadata, operands, receipts, policies, and unperformed facts",
    "Supply the metric kind and every calculation policy and operand; the plugin does not choose or interpret a metric",
    tool.parameters(metric_schema(), decode.request_metric()),
    tool.Parallel,
    fn(_id, input, _signal, _updates, _ctx) {
      case domain.request_metric(input) {
        Ok(value) ->
          tool.text_result(value.summary, value.details)
          |> promise.resolve
        Error(error) -> tool.reject(domain.error_message(error))
      }
    },
  )
  tool.register(
    api,
    "compare_runs",
    "Compare two exact replay runs",
    "Verify two canonical finance_replay run definitions and report mechanical definition and caller-supplied output differences with both receipt sets retained",
    "Supply both exact definitions and output projections; the plugin does not attribute causality, prefer a run, or make a research conclusion",
    tool.parameters(compare_schema(), decode.compare_runs()),
    tool.Parallel,
    fn(_id, input, _signal, _updates, _ctx) {
      case domain.compare_runs(input) {
        Ok(value) ->
          tool.text_result(value.summary, value.details)
          |> promise.resolve
        Error(error) -> tool.reject(domain.error_message(error))
      }
    },
  )
  promise.resolve(Nil)
}

fn inspect_schema() -> schema.Schema {
  schema.object([
    schema.Required("hypothesis", hypothesis_schema()),
    schema.Required("populationId", bounded_string(1, 2000)),
    schema.Required(
      "completenessPolicy",
      schema.string_enum(["caller_declared_complete_population_v1"]),
    ),
    schema.Required("expectedCounts", counts_schema()),
    schema.Required(
      "events",
      schema.array(ledger_event_schema()) |> schema.with_array_length(0, 1000),
    ),
    schema.Required("includeHypothesisText", schema.boolean()),
    schema.Required("includeTrialPayloads", schema.boolean()),
    schema.Required("offset", bounded_integer(0.0, 1000.0)),
    schema.Required("limit", bounded_integer(1.0, 200.0)),
  ])
}

fn hypothesis_schema() -> schema.Schema {
  schema.object([
    schema.Required("hypothesisId", bounded_string(1, 4096)),
    schema.Required("version", bounded_string(1, 4096)),
    schema.Required("contentHash", hash_schema()),
    schema.Required("author", author_schema()),
    schema.Optional("authorId", schema.nullable(bounded_string(1, 4096))),
    schema.Required("declaredTimeUnixMilliseconds", safe_integer()),
    schema.Required("text", bounded_string(1, 65_536)),
    schema.Optional(
      "structuredExpression",
      schema.nullable(bounded_string(1, 65_536)),
    ),
    schema.Optional("targetValue", schema.nullable(bounded_string(1, 4096))),
    schema.Optional("populationRef", schema.nullable(hash_schema())),
    schema.Required(
      "featureRefs",
      schema.array(hash_schema()) |> schema.with_array_length(0, 1000),
    ),
    schema.Optional("strategyRef", schema.nullable(hash_schema())),
    schema.Optional(
      "sourceCutoffUnixMilliseconds",
      schema.nullable(safe_integer()),
    ),
    schema.Required(
      "supportingRefs",
      schema.array(hash_schema()) |> schema.with_array_length(0, 1000),
    ),
    schema.Required(
      "privacy",
      schema.string_enum(["private", "research_context", "exportable"]),
    ),
    schema.Required(
      "exportClassification",
      schema.string_enum(["local_only", "review_visible", "exportable"]),
    ),
  ])
}

fn ledger_event_schema() -> schema.Schema {
  schema.object([
    schema.Required("ledgerEventId", bounded_string(1, 4096)),
    schema.Required("trial", trial_definition_schema()),
    schema.Required("status", status_schema()),
    schema.Required("startTimeUnixMilliseconds", safe_integer()),
    schema.Required("endTime", fact_schema(safe_integer(), 1000)),
    schema.Required(
      "outputReceiptHashes",
      schema.array(hash_schema()) |> schema.with_array_length(0, 1000),
    ),
    schema.Required(
      "errorFacts",
      schema.array(bounded_string(1, 4096))
        |> schema.with_array_length(0, 1000),
    ),
    schema.Required("effectReceiptHash", hash_schema()),
    schema.Required("idempotencyKey", bounded_string(1, 4096)),
  ])
}

fn trial_definition_schema() -> schema.Schema {
  schema.object([
    schema.Required("trialId", bounded_string(1, 4096)),
    schema.Optional("parentTrialId", schema.nullable(bounded_string(1, 4096))),
    schema.Optional("batchId", schema.nullable(bounded_string(1, 4096))),
    schema.Required("runDefinitionHash", hash_schema()),
    schema.Required(
      "parameterValues",
      schema.array(parameter_schema()) |> schema.with_array_length(0, 1000),
    ),
    schema.Required(
      "trialRationale",
      fact_schema(bounded_string(1, 4096), 1000),
    ),
    schema.Required("partitionRef", hash_schema()),
    schema.Required(
      "modelRefs",
      schema.array(hash_schema()) |> schema.with_array_length(0, 1000),
    ),
    schema.Required("seed", fact_schema(bounded_string(1, 4096), 1000)),
    schema.Required(
      "metricRefs",
      schema.array(hash_schema()) |> schema.with_array_length(0, 1000),
    ),
    schema.Required(
      "budgetRefs",
      schema.array(hash_schema()) |> schema.with_array_length(0, 1000),
    ),
    schema.Required("author", author_schema()),
    schema.Required("declaredTimeUnixMilliseconds", safe_integer()),
    schema.Required(
      "privacy",
      schema.string_enum(["private", "research_context", "exportable"]),
    ),
  ])
}

fn parameter_schema() -> schema.Schema {
  schema.object([
    schema.Required("name", bounded_string(1, 4096)),
    schema.Required("exactValue", bounded_string(1, 4096)),
    schema.Required("author", author_schema()),
    schema.Required("sourceReceipt", fact_schema(hash_schema(), 1000)),
  ])
}

fn author_schema() -> schema.Schema {
  schema.object([
    schema.Required("kind", schema.string_enum(["llm", "user", "imported"])),
    schema.Optional("importSource", schema.nullable(bounded_string(1, 4096))),
  ])
}

fn status_schema() -> schema.Schema {
  schema.one_of([
    schema.object([
      schema.Required("state", schema.literal_string("completed")),
    ]),
    schema.object([
      schema.Required("state", schema.literal_string("failed")),
      schema.Required("reason", bounded_string(1, 4096)),
    ]),
    schema.object([
      schema.Required("state", schema.literal_string("cancelled")),
      schema.Required("atUnixMilliseconds", safe_integer()),
      schema.Required("by", bounded_string(1, 4096)),
    ]),
    schema.object([
      schema.Required("state", schema.literal_string("truncated")),
      schema.Required("reason", bounded_string(1, 4096)),
    ]),
    schema.object([
      schema.Required("state", schema.literal_string("duplicate_of")),
      schema.Required("existingTrialId", bounded_string(1, 4096)),
    ]),
    schema.object([
      schema.Required("state", schema.literal_string("unperformed")),
      schema.Required("reason", bounded_string(1, 4096)),
    ]),
  ])
}

fn counts_schema() -> schema.Schema {
  schema.object([
    schema.Required("total", bounded_integer(0.0, 1000.0)),
    schema.Required("completed", bounded_integer(0.0, 1000.0)),
    schema.Required("failed", bounded_integer(0.0, 1000.0)),
    schema.Required("cancelled", bounded_integer(0.0, 1000.0)),
    schema.Required("truncated", bounded_integer(0.0, 1000.0)),
    schema.Required("duplicate", bounded_integer(0.0, 1000.0)),
    schema.Required("unperformed", bounded_integer(0.0, 1000.0)),
  ])
}

fn metric_schema() -> schema.Schema {
  schema.object([
    schema.Required("metadata", metadata_schema()),
    schema.Required("request", metric_request_schema()),
  ])
}

fn metadata_schema() -> schema.Schema {
  schema.object([
    schema.Required("requestId", bounded_string(1, 4096)),
    schema.Required("formula", bounded_string(1, 65_536)),
    schema.Required("formulaVersion", bounded_string(1, 4096)),
    schema.Required("unit", bounded_string(1, 4096)),
    schema.Required("scale", bounded_integer(0.0, 100.0)),
    schema.Required(
      "rounding",
      schema.string_enum([
        "toward_zero",
        "away_from_zero",
        "half_up",
        "half_even",
      ]),
    ),
    schema.Required("missingConflictPolicy", bounded_string(1, 4096)),
    schema.Required("samplePopulation", bounded_string(1, 65_536)),
    schema.Required("ordering", bounded_string(1, 4096)),
    schema.Required("benchmark", fact_schema(hash_schema(), 1000)),
    schema.Required(
      "sourceReceipts",
      schema.array(hash_schema()) |> schema.with_array_length(0, 1000),
    ),
  ])
}

fn metric_request_schema() -> schema.Schema {
  schema.one_of([
    schema.object([
      schema.Required("kind", schema.literal_string("net_return")),
      schema.Required("denominator", fact_schema(decimal_input_schema(), 1000)),
      schema.Required("endingValue", fact_schema(decimal_input_schema(), 1000)),
    ]),
    schema.object([
      schema.Required("kind", schema.literal_string("win_loss_counts")),
      schema.Required(
        "trades",
        schema.array(trade_pnl_schema()) |> schema.with_array_length(1, 10_000),
      ),
      schema.Required("zeroPolicy", bounded_string(1, 4096)),
    ]),
    schema.object([
      schema.Required("kind", schema.literal_string("drawdown_series")),
      schema.Required(
        "points",
        schema.array(equity_point_schema())
          |> schema.with_array_length(1, 10_000),
      ),
      schema.Required("peakConvention", bounded_string(1, 4096)),
    ]),
    schema.object([
      schema.Required("kind", schema.literal_string("trade_list")),
      schema.Required(
        "trades",
        schema.array(trade_schema()) |> schema.with_array_length(0, 10_000),
      ),
    ]),
  ])
}

fn decimal_input_schema() -> schema.Schema {
  schema.object([
    schema.Required("name", bounded_string(1, 4096)),
    schema.Required("exactLexeme", bounded_string(1, 4096)),
    schema.Required("sourceReceipt", hash_schema()),
  ])
}

fn trade_pnl_schema() -> schema.Schema {
  schema.object([
    schema.Required("tradeId", bounded_string(1, 4096)),
    schema.Required("netPnlLexeme", bounded_string(1, 4096)),
    schema.Required("sourceReceipt", hash_schema()),
  ])
}

fn equity_point_schema() -> schema.Schema {
  schema.object([
    schema.Required("label", bounded_string(1, 4096)),
    schema.Required("value", decimal_input_schema()),
  ])
}

fn trade_schema() -> schema.Schema {
  schema.object([
    schema.Required("tradeId", bounded_string(1, 4096)),
    schema.Required("instructionReceipt", hash_schema()),
    schema.Required(
      "lifecycleReceipts",
      schema.array(hash_schema()) |> schema.with_array_length(0, 1000),
    ),
    schema.Required("exactPayload", bounded_string(1, 65_536)),
  ])
}

fn compare_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "comparisonPolicy",
      schema.string_enum(["caller_selected_exact_runs_and_outputs_v1"]),
    ),
    schema.Required("leftDefinition", definition_schema()),
    schema.Required("rightDefinition", definition_schema()),
    schema.Required(
      "leftOutputs",
      schema.array(output_schema()) |> schema.with_array_length(0, 1000),
    ),
    schema.Required(
      "rightOutputs",
      schema.array(output_schema()) |> schema.with_array_length(0, 1000),
    ),
  ])
}

fn definition_schema() -> schema.Schema {
  schema.object([
    schema.Required("canonicalJson", bounded_string(1, 2_000_000)),
    schema.Required("contentHash", hash_schema()),
  ])
}

fn output_schema() -> schema.Schema {
  schema.object([
    schema.Required("name", bounded_string(1, 4096)),
    schema.Required("exactValue", bounded_string(1, 65_536)),
    schema.Required("sourceReceipt", hash_schema()),
  ])
}

fn fact_schema(
  value: schema.Schema,
  maximum_alternatives: Int,
) -> schema.Schema {
  schema.one_of([
    schema.object([
      schema.Required("state", schema.literal_string("known")),
      schema.Required("value", value),
    ]),
    reason_fact_schema("unknown"),
    reason_fact_schema("not_obtained"),
    reason_fact_schema("not_applicable"),
    schema.object([
      schema.Required("state", schema.literal_string("conflicting")),
      schema.Required(
        "alternatives",
        schema.array(value)
          |> schema.with_array_length(1, maximum_alternatives),
      ),
      schema.Required("reason", bounded_string(1, 4096)),
    ]),
    schema.object([
      schema.Required("state", schema.literal_string("decode_failure")),
      schema.Required("raw", bounded_string(1, 65_536)),
      schema.Required("reason", bounded_string(1, 4096)),
    ]),
  ])
}

fn reason_fact_schema(state: String) -> schema.Schema {
  schema.object([
    schema.Required("state", schema.literal_string(state)),
    schema.Required("reason", bounded_string(1, 4096)),
  ])
}

fn hash_schema() -> schema.Schema {
  schema.string() |> schema.with_string_length(64, 64)
}

fn bounded_string(minimum: Int, maximum: Int) -> schema.Schema {
  schema.string() |> schema.with_string_length(minimum, maximum)
}

fn bounded_integer(minimum: Float, maximum: Float) -> schema.Schema {
  schema.integer() |> schema.with_number_range(minimum, maximum)
}

fn safe_integer() -> schema.Schema {
  bounded_integer(0.0 -. 9_007_199_254_740_991.0, 9_007_199_254_740_991.0)
}
