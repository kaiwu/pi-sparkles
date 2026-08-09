import gleam/javascript/promise.{type Promise}
import pi
import pi/schema
import pi/tool
import pi_sparkles_backtest/decode
import pi_sparkles_backtest/domain

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  tool.register(
    api,
    "submit_run",
    "Execute one bounded completed-daily replay",
    "Verify one exact finance_replay run definition and ordered canonical event script, then execute the deterministic fold under explicit event, byte, wall-time, session, and cancellation limits",
    "Supply the complete immutable script; this local stateless operation does not enqueue, persist, fetch, search, judge, or deploy a run",
    tool.parameters(run_schema(), decode.submit_run()),
    tool.Parallel,
    fn(_id, input, _signal, _updates, _ctx) {
      case domain.submit_run(input) {
        Ok(value) ->
          tool.text_result(value.summary, value.details)
          |> promise.resolve
        Error(error) -> tool.reject(domain.error_message(error))
      }
    },
  )
  tool.register(
    api,
    "inspect_events",
    "Page retained replay events",
    "Reconstruct the exact bounded replay and page only its retained core event stream in fold order with stable state handles and optional canonical envelopes",
    "Supply the same immutable run declaration plus an exact page; the plugin reads no ambient or prior tool state",
    tool.parameters(inspect_schema(), decode.inspect_events()),
    tool.Parallel,
    fn(_id, input, _signal, _updates, _ctx) {
      case domain.inspect_events(input) {
        Ok(value) ->
          tool.text_result(value.summary, value.details)
          |> promise.resolve
        Error(error) -> tool.reject(domain.error_message(error))
      }
    },
  )
  tool.register(
    api,
    "export_manifest",
    "Export a bounded reproduction page",
    "Reconstruct the exact replay, bind primary receipts from its verified definition, construct the canonical finance_replay reproduction manifest, and export a bounded canonical event-JSONL page",
    "Supply all reproduction metadata and export limits explicitly; the plugin returns bytes but writes no files and makes no origin, quality, or research claim",
    tool.parameters(export_schema(), decode.export_manifest()),
    tool.Parallel,
    fn(_id, input, _signal, _updates, _ctx) {
      case domain.export_manifest(input) {
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
    schema.Required("run", run_schema()),
    schema.Required("offset", bounded_integer(0.0, 10_000.0)),
    schema.Required("limit", bounded_integer(1.0, 200.0)),
    schema.Required("includePayloads", schema.boolean()),
  ])
}

fn export_schema() -> schema.Schema {
  schema.object([
    schema.Required("run", run_schema()),
    schema.Required("manifest", manifest_schema()),
    schema.Required("offset", bounded_integer(0.0, 10_000.0)),
    schema.Required("maximumEvents", bounded_integer(1.0, 200.0)),
    schema.Required("maximumCharacters", bounded_integer(1.0, 10_000_000.0)),
  ])
}

fn run_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "cadencePolicy",
      schema.literal_string("caller_declared_completed_daily_cash_equity_v1"),
    ),
    schema.Required("definition", definition_schema()),
    schema.Required(
      "events",
      schema.array(event_schema()) |> schema.with_array_length(0, 10_000),
    ),
    schema.Required("budget", budget_schema()),
    schema.Required("cancellation", cancellation_schema()),
  ])
}

fn definition_schema() -> schema.Schema {
  schema.object([
    schema.Required("canonicalJson", bounded_string(1, 2_000_000)),
    schema.Required("contentHash", hash_schema()),
  ])
}

fn event_schema() -> schema.Schema {
  schema.object([
    schema.Required("canonicalJson", bounded_string(1, 200_000)),
    schema.Required("contentHash", hash_schema()),
    schema.Required(
      "elapsedMilliseconds",
      bounded_integer(0.0, 9_007_199_254_740_991.0),
    ),
    schema.Required("sessionIncrement", bounded_integer(0.0, 1.0)),
  ])
}

fn budget_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "maximumEvents",
      bounded_integer(1.0, 9_007_199_254_740_991.0),
    ),
    schema.Required(
      "maximumBytes",
      bounded_integer(1.0, 9_007_199_254_740_991.0),
    ),
    schema.Required(
      "maximumWallTimeMilliseconds",
      bounded_integer(1.0, 9_007_199_254_740_991.0),
    ),
    schema.Required(
      "maximumSessions",
      bounded_integer(1.0, 9_007_199_254_740_991.0),
    ),
  ])
}

fn cancellation_schema() -> schema.Schema {
  schema.one_of([
    schema.object([
      schema.Required("kind", schema.literal_string("continue")),
    ]),
    schema.object([
      schema.Required("kind", schema.literal_string("cancel_before")),
      schema.Required(
        "replayClock",
        bounded_integer(0.0, 9_007_199_254_740_991.0),
      ),
      schema.Required(
        "cancelledAtUnixMilliseconds",
        bounded_integer(0.0 -. 9_007_199_254_740_991.0, 9_007_199_254_740_991.0),
      ),
      schema.Required("cancelledBy", bounded_string(1, 65_536)),
    ]),
  ])
}

fn manifest_schema() -> schema.Schema {
  schema.object([
    schema.Required("manifestId", bounded_string(1, 65_536)),
    schema.Required(
      "environmentVersions",
      schema.array(environment_schema())
        |> schema.with_array_length(0, 10_000),
    ),
    schema.Required(
      "trialIds",
      schema.array(bounded_string(1, 65_536))
        |> schema.with_array_length(0, 10_000),
    ),
    schema.Required(
      "orderedSourceHashes",
      schema.array(hash_schema()) |> schema.with_array_length(0, 10_000),
    ),
    schema.Required(
      "transformationReceipts",
      schema.array(hash_schema()) |> schema.with_array_length(0, 10_000),
    ),
    schema.Required(
      "calendarReceipts",
      schema.array(hash_schema()) |> schema.with_array_length(0, 10_000),
    ),
    schema.Required(
      "ruleReceipts",
      schema.array(hash_schema()) |> schema.with_array_length(0, 10_000),
    ),
    schema.Required(
      "corporateActionReceipts",
      schema.array(hash_schema()) |> schema.with_array_length(0, 10_000),
    ),
    schema.Required(
      "costReceipts",
      schema.array(hash_schema()) |> schema.with_array_length(0, 10_000),
    ),
    schema.Required(
      "seedAndRandomStreamFacts",
      schema.array(bounded_string(1, 65_536))
        |> schema.with_array_length(0, 10_000),
    ),
    schema.Required(
      "additionalEffectFacts",
      schema.array(bounded_string(1, 65_536))
        |> schema.with_array_length(0, 10_000),
    ),
    schema.Required(
      "outputReceiptHashes",
      schema.array(hash_schema()) |> schema.with_array_length(0, 10_000),
    ),
    schema.Required(
      "checkpointHashes",
      schema.array(hash_schema()) |> schema.with_array_length(0, 10_000),
    ),
    schema.Required(
      "entitlementLimitations",
      schema.array(bounded_string(1, 65_536))
        |> schema.with_array_length(0, 10_000),
    ),
    schema.Required(
      "omittedDependencies",
      schema.array(dependency_schema()) |> schema.with_array_length(0, 10_000),
    ),
    schema.Required(
      "unknownDependencies",
      schema.array(dependency_schema()) |> schema.with_array_length(0, 10_000),
    ),
    schema.Required(
      "conflictingDependencies",
      schema.array(dependency_schema()) |> schema.with_array_length(0, 10_000),
    ),
    schema.Required("exportProvenance", bounded_string(1, 65_536)),
    schema.Required("privacyPolicy", bounded_string(1, 65_536)),
  ])
}

fn environment_schema() -> schema.Schema {
  schema.object([
    schema.Required("name", bounded_string(1, 65_536)),
    schema.Required("version", bounded_string(1, 65_536)),
    schema.Required("semantic", schema.boolean()),
  ])
}

fn dependency_schema() -> schema.Schema {
  schema.object([
    schema.Required("receiptHash", fact_schema(hash_schema(), 10_000)),
    schema.Required("reason", bounded_string(1, 65_536)),
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
      schema.Required("reason", bounded_string(1, 65_536)),
    ]),
    schema.object([
      schema.Required("state", schema.literal_string("decode_failure")),
      schema.Required("raw", bounded_string(1, 65_536)),
      schema.Required("reason", bounded_string(1, 65_536)),
    ]),
  ])
}

fn reason_fact_schema(state: String) -> schema.Schema {
  schema.object([
    schema.Required("state", schema.literal_string(state)),
    schema.Required("reason", bounded_string(1, 65_536)),
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
