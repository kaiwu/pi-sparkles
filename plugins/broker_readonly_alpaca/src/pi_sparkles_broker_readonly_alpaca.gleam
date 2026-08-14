import finance_broker_review
import finance_broker_review/decode
import gleam/javascript/promise.{type Promise}
import pi
import pi/schema
import pi/tool
import pi_sparkles_broker_readonly_alpaca/domain

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  tool.register(
    api,
    "review_alpaca_activity_import",
    "Review an Alpaca activity import",
    "Validate bounded caller-owned Alpaca account activity without network access or credentials; optional Alpaca network breadth is absent and every result is track_partial",
    "Supply hashes instead of raw account identifiers. This tool only reviews supplied facts and lifecycle observations.",
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
    schema.Required("mode", schema.string_enum(["account_activity_import"])),
    schema.Required("environment", schema.string_enum(["paper", "live"])),
    schema.Required("accountReference", hash_schema()),
    schema.Required("track", schema.string_enum(["us"])),
    schema.Required("listingId", bounded_string(1, 500)),
    schema.Required("mic", bounded_string(1, 50)),
    schema.Required("sourceContentHash", hash_schema()),
    schema.Required(
      "facts",
      schema.array(fact_schema()) |> schema.with_array_length(0, 200),
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
