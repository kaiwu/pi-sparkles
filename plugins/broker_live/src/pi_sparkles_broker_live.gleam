import finance_broker_review
import finance_broker_review/decode
import finance_local_import
import gleam/dynamic.{type Dynamic}
import gleam/javascript/promise.{type Promise}
import pi
import pi/schema
import pi/tool
import pi_sparkles_broker_live/domain
import pi_sparkles_broker_live/import_contract

const maximum_local_import_bytes = 250_000

/// Unregistered caller-owned local import. Exact bytes are content-bound and
/// decoded to a bounded review before this promise resolves; raw text is never
/// returned or registered as a Pi tool result.
pub fn review_local_execution_file(
  path: String,
  expected_content_hash: String,
  maximum_bytes: Int,
  signal: Dynamic,
) -> Promise(import_contract.LocalImportOutcome) {
  case maximum_bytes >= 1 && maximum_bytes <= maximum_local_import_bytes {
    False ->
      import_contract.ReadFailure("invalid_read_budget") |> promise.resolve
    True ->
      finance_local_import.read(path, maximum_bytes, signal)
      |> promise.map(fn(outcome) {
        import_contract.from_read_outcome(outcome, expected_content_hash)
      })
  }
}

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  tool.register(
    api,
    "review_external_execution_evidence",
    "Create or review non-executing evidence",
    "Content-bind a non-executable external handoff or review a caller-owned execution receipt; this legacy-named plugin has no network or broker authority and every result is track_partial",
    "For a handoff, supply no events and include exact instruction facts. For a receipt import, preserve provider status lexemes and hashed references.",
    tool.parameters(review_schema(), decode.review_input()),
    tool.Parallel,
    fn(_id, input, _signal, _updates, _ctx) {
      case domain.run(input) {
        Ok(value) ->
          tool.text_result(
            finance_broker_review.summary(value),
            finance_broker_review.details(value),
          )
          |> promise.resolve
        Error(error) -> tool.reject(finance_broker_review.error_message(error))
      }
    },
  )
  promise.resolve(Nil)
}

fn review_schema() -> schema.Schema {
  schema.object([
    schema.Required("operationId", bounded_string(1, 500)),
    schema.Required(
      "mode",
      schema.string_enum([
        "non_executable_handoff",
        "external_execution_receipt_import",
      ]),
    ),
    schema.Required(
      "environment",
      schema.string_enum(["external_paper", "external_live"]),
    ),
    schema.Required("accountReference", hash_schema()),
    schema.Required("track", schema.string_enum(["cn", "hk", "us"])),
    schema.Required("listingId", bounded_string(1, 500)),
    schema.Required("mic", bounded_string(1, 50)),
    schema.Required("sourceContentHash", hash_schema()),
    schema.Required(
      "facts",
      schema.array(fact_schema()) |> schema.with_array_length(1, 200),
    ),
    schema.Required(
      "events",
      schema.array(event_schema()) |> schema.with_array_length(0, 500),
    ),
    schema.Required(
      "missingCapabilities",
      schema.array(bounded_string(1, 200)) |> schema.with_array_length(0, 100),
    ),
  ])
}

fn fact_schema() -> schema.Schema {
  schema.object([
    schema.Required("name", bounded_string(1, 200)),
    schema.Required(
      "state",
      schema.string_enum([
        "known",
        "unknown",
        "unavailable",
        "conflicting",
        "not_applicable",
      ]),
    ),
    schema.Optional("value", schema.nullable(bounded_string(1, 4000))),
    schema.Optional("unit", schema.nullable(bounded_string(1, 100))),
    schema.Required("sourceReference", hash_schema()),
  ])
}

fn event_schema() -> schema.Schema {
  schema.object([
    schema.Required("eventReference", hash_schema()),
    schema.Required("statusLexeme", bounded_string(1, 500)),
    schema.Required(
      "occurredAtUnixMilliseconds",
      schema.integer() |> schema.with_number_range(0.0, 9_007_199_254_740_991.0),
    ),
    schema.Required("sourceReference", hash_schema()),
  ])
}

fn bounded_string(minimum: Int, maximum: Int) -> schema.Schema {
  schema.string() |> schema.with_string_length(minimum, maximum)
}

fn hash_schema() -> schema.Schema {
  bounded_string(64, 64)
}
