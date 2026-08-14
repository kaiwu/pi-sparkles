import finance_broker_review
import finance_broker_review/decode
import gleam/javascript/promise.{type Promise}
import pi
import pi/schema
import pi/tool
import pi_sparkles_cn_broker_readonly/domain

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  tool.register(
    api,
    "review_cn_broker_activity",
    "Review one explicit CN broker capability packet",
    "Validate bounded mainland account, cash, settlement, position, order, fill, capability, entitlement, and lifecycle evidence supplied by one explicitly selected external read-only provider capability",
    "The provider is a required external dependency. Supply normalized redacted evidence and hashes; this package ships no OpenD, SDK, credential, provider adapter, network transport, or broker mutation surface.",
    tool.parameters(input_schema(), decode.explicit_capability_input()),
    tool.Parallel,
    fn(_id, input, signal, _updates, _ctx) {
      case tool.is_cancelled(signal) {
        True -> tool.reject("CN broker read-only review was cancelled")
        False ->
          case domain.run(input) {
            Ok(value) ->
              tool.text_result(
                finance_broker_review.summary(value),
                finance_broker_review.details(value),
              )
              |> promise.resolve
            Error(error) ->
              tool.reject(finance_broker_review.error_message(error))
          }
      }
    },
  )
  promise.resolve(Nil)
}

fn input_schema() -> schema.Schema {
  schema.object([
    schema.Required("provider", bounded_string(1, 100)),
    schema.Required("operationId", bounded_string(1, 500)),
    schema.Required(
      "mode",
      schema.string_enum(["read_only_capability", "caller_owned_export"]),
    ),
    schema.Required(
      "environment",
      schema.string_enum(["external_live", "caller_export"]),
    ),
    schema.Required("accountReference", hash_schema()),
    schema.Required("track", schema.string_enum(["cn"])),
    schema.Required("listingId", bounded_string(1, 500)),
    schema.Required("mic", schema.string_enum(["XSHG", "XSHE", "XBSE"])),
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
