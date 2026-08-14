import gleam/int
import gleam/javascript/promise.{type Promise}
import pi
import pi/schema
import pi/tool
import pi_sparkles_stock_tape/decode
import pi_sparkles_stock_tape/domain

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  tool.register(
    api,
    "stock_tape",
    "Review one exact bounded transaction tape",
    "Validate a provider-capability packet for one cn, hk, or us listing/session and return exact event ordering, sequence, correction/cancel lineage, clock, condition, coverage, and receipt facts with stable bounded paging",
    "The provider is an explicit external dependency. Supply its packet and content receipt; this package ships no OpenD, SDK, credential, adapter, quote, order book, signal, or broker mutation surface.",
    tool.parameters(input_schema(), decode.input()),
    tool.Parallel,
    fn(_id, input, signal, _updates, _ctx) {
      case tool.is_cancelled(signal) {
        True -> tool.reject("Transaction-tape review was cancelled")
        False ->
          case domain.run(input) {
            Ok(value) ->
              tool.text_result(domain.summary(value), domain.details(value))
              |> promise.resolve
            Error(error) -> tool.reject(domain.error_message(error))
          }
      }
    },
  )
  promise.resolve(Nil)
}

fn input_schema() -> schema.Schema {
  schema.object([
    schema.Required("track", schema.string_enum(["cn", "hk", "us"])),
    schema.Required("listingId", bounded_string(1, 500)),
    schema.Required("mic", bounded_string(4, 4)),
    schema.Required("sessionId", bounded_string(1, 500)),
    schema.Required("provider", bounded_string(1, 200)),
    schema.Required("feed", bounded_string(1, 200)),
    schema.Required("entitlement", bounded_string(1, 500)),
    schema.Required("licence", bounded_string(1, 1000)),
    schema.Required("providerReceiptHash", hash_schema()),
    schema.Required("coverage", coverage_schema()),
    schema.Required("conditionCoverage", condition_coverage_schema()),
    schema.Required("maximumEvents", bounded_integer(1, 10_000)),
    schema.Required(
      "events",
      schema.array(event_schema()) |> schema.with_array_length(1, 10_000),
    ),
    schema.Required(
      "page",
      schema.object([
        schema.Required("offset", bounded_integer(0, 10_000)),
        schema.Required("limit", bounded_integer(1, 1000)),
      ]),
    ),
  ])
}

fn coverage_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "state",
      schema.string_enum([
        "provider_declared_complete",
        "bounded_partial",
        "unknown",
      ]),
    ),
    schema.Optional("referenceHash", schema.nullable(hash_schema())),
    schema.Optional("reason", schema.nullable(bounded_string(1, 500))),
  ])
}

fn condition_coverage_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "state",
      schema.string_enum(["documented", "partially_documented", "undocumented"]),
    ),
    schema.Required(
      "codes",
      schema.array(bounded_string(1, 200)) |> schema.with_array_length(0, 100),
    ),
    schema.Optional("referenceHash", schema.nullable(hash_schema())),
    schema.Optional("reason", schema.nullable(bounded_string(1, 500))),
  ])
}

fn event_schema() -> schema.Schema {
  schema.object([
    schema.Required("eventId", bounded_string(1, 500)),
    schema.Required("tradeId", bounded_string(1, 500)),
    schema.Required("kind", kind_schema()),
    schema.Required("price", lexeme_schema()),
    schema.Required("size", lexeme_schema()),
    schema.Required(
      "conditionCodes",
      schema.array(bounded_string(1, 200)) |> schema.with_array_length(0, 100),
    ),
    schema.Required("venueLexeme", bounded_string(1, 200)),
    schema.Required("clocks", clocks_schema()),
    schema.Required("sequence", sequence_schema()),
    schema.Required("rawReceiptHash", hash_schema()),
  ])
}

fn kind_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "state",
      schema.string_enum(["original", "correction", "cancel"]),
    ),
    schema.Optional("referenceEventId", schema.nullable(bounded_string(1, 500))),
    schema.Optional("referenceTradeId", schema.nullable(bounded_string(1, 500))),
  ])
}

fn lexeme_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "state",
      schema.string_enum(["known", "unavailable", "conflicting"]),
    ),
    schema.Optional("value", schema.nullable(bounded_string(1, 500))),
    schema.Required(
      "values",
      schema.array(bounded_string(1, 500)) |> schema.with_array_length(0, 10),
    ),
    schema.Optional("reason", schema.nullable(bounded_string(1, 500))),
  ])
}

fn clocks_schema() -> schema.Schema {
  schema.object([
    schema.Optional(
      "exchangeUnixMilliseconds",
      schema.nullable(unix_milliseconds()),
    ),
    schema.Optional(
      "providerUnixMilliseconds",
      schema.nullable(unix_milliseconds()),
    ),
    schema.Required("retrievedUnixMilliseconds", unix_milliseconds()),
  ])
}

fn sequence_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "state",
      schema.string_enum(["sequenced", "reset", "unavailable", "conflicting"]),
    ),
    schema.Optional("scope", schema.nullable(bounded_string(1, 200))),
    schema.Optional("value", schema.nullable(bounded_string(1, 500))),
    schema.Required(
      "values",
      schema.array(bounded_string(1, 500)) |> schema.with_array_length(0, 10),
    ),
    schema.Optional("declaredPrevious", schema.nullable(bounded_string(1, 500))),
    schema.Optional("reason", schema.nullable(bounded_string(1, 500))),
  ])
}

fn unix_milliseconds() -> schema.Schema {
  bounded_integer(0, 8_640_000_000_000_000)
}

fn bounded_integer(minimum: Int, maximum: Int) -> schema.Schema {
  schema.integer()
  |> schema.with_number_range(int.to_float(minimum), int.to_float(maximum))
}

fn bounded_string(minimum: Int, maximum: Int) -> schema.Schema {
  schema.string() |> schema.with_string_length(minimum, maximum)
}

fn hash_schema() -> schema.Schema {
  bounded_string(64, 64)
}
