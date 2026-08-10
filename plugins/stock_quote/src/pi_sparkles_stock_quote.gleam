import gleam/javascript/promise.{type Promise}
import pi
import pi/schema
import pi/tool
import pi_sparkles_stock_quote/decode
import pi_sparkles_stock_quote/domain

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  tool.register(
    api,
    "stock_quote",
    "Inspect one exact three-track quote observation",
    "Validate and project one caller or provider-adapter best bid/ask observation for an exact cn, hk, or us listing and MIC while retaining source lexemes, times, feed, entitlement, licence, receipt, and unknown facts",
    "Supply every quote and source fact explicitly; the tool performs no fetch, provider choice, fallback, freshness judgment, conflict reconciliation, signal, rank, or trade action",
    tool.parameters(input_schema(), decode.input()),
    tool.Parallel,
    fn(_id, input, _signal, _updates, _ctx) {
      case domain.run(input) {
        Ok(value) ->
          tool.text_result(domain.summary(value), domain.details(value))
          |> promise.resolve
        Error(error) -> tool.reject(domain.error_message(error))
      }
    },
  )
  promise.resolve(Nil)
}

fn input_schema() -> schema.Schema {
  schema.object([
    schema.Required("track", schema.string_enum(["cn", "hk", "us"])),
    schema.Required(
      "listing",
      schema.object([
        schema.Required("listingId", bounded_string(1, 2000)),
        schema.Required("mic", bounded_string(4, 4)),
        schema.Required("symbol", bounded_string(1, 100)),
      ]),
    ),
    schema.Required(
      "quote",
      schema.object([
        schema.Required("providerTimestamp", bounded_string(1, 100)),
        schema.Required(
          "asOfUnixMilliseconds",
          bounded_integer(0.0, 9_007_199_254_740_991.0),
        ),
        schema.Required(
          "retrievedAtUnixMilliseconds",
          bounded_integer(0.0, 9_007_199_254_740_991.0),
        ),
        schema.Required("currency", bounded_string(3, 3)),
        schema.Required("bid", side_schema()),
        schema.Required("ask", side_schema()),
        schema.Required(
          "conditionCodes",
          schema.array(bounded_string(1, 40))
            |> schema.with_array_length(0, 100),
        ),
        schema.Required("tape", bounded_string(1, 40)),
        schema.Required(
          "sizeUnit",
          schema.string_enum(["provider_reported_unverified"]),
        ),
      ]),
    ),
    schema.Required("source", source_schema()),
  ])
}

fn side_schema() -> schema.Schema {
  schema.object([
    schema.Required("exchange", bounded_string(1, 40)),
    schema.Required("rawPrice", bounded_string(1, 500)),
    schema.Required("rawSize", bounded_string(1, 500)),
  ])
}

fn source_schema() -> schema.Schema {
  schema.object([
    schema.Required("provider", bounded_string(1, 200)),
    schema.Required("reference", bounded_string(1, 8000)),
    schema.Required(
      "kind",
      schema.string_enum([
        "official",
        "exchange",
        "regulator",
        "licensed_vendor",
        "user_supplied",
        "synthetic",
        "other",
      ]),
    ),
    schema.Optional("otherKind", schema.nullable(bounded_string(1, 200))),
    schema.Required("feed", bounded_string(1, 200)),
    schema.Required("entitlement", entitlement_schema()),
    schema.Required(
      "licence",
      schema.object([
        schema.Required("label", bounded_string(1, 500)),
        schema.Required(
          "redistribution",
          schema.string_enum([
            "public_domain",
            "attribution_required",
            "internal_use_only",
            "no_redistribution",
            "unknown",
          ]),
        ),
        schema.Optional("notes", schema.nullable(bounded_string(1, 4000))),
      ]),
    ),
    schema.Required("receiptHash", hash_schema()),
  ])
}

fn entitlement_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "state",
      schema.string_enum(["real_time", "delayed", "end_of_day", "unknown"]),
    ),
    schema.Optional(
      "delayMilliseconds",
      schema.nullable(bounded_integer(1.0, 9_007_199_254_740_991.0)),
    ),
  ])
  |> schema.described(
    "delayed requires delayMilliseconds; all other states forbid it",
  )
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
