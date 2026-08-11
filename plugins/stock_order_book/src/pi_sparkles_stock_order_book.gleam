import gleam/javascript/promise.{type Promise}
import pi
import pi/schema
import pi/tool
import pi_sparkles_stock_order_book/decode
import pi_sparkles_stock_order_book/domain

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  tool.register(
    api,
    "stock_top_of_book",
    "Inspect one exact three-track top-of-book packet",
    "Validate one caller or provider-adapter cn, hk, or us listing packet and retain observed, unavailable, or conflicting bid/ask candidates with exact venue, time, sequence/gap, aggregation, rights, and receipt facts",
    "Supply every source and report explicitly; displayed size is neither durable nor an executable-price or fill promise, and the tool performs no fetch, report merge, gap repair, book reconstruction, source choice, signal, or trade action",
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
        schema.Required("currency", bounded_string(3, 3)),
      ]),
    ),
    schema.Required(
      "sources",
      schema.array(source_schema()) |> schema.with_array_length(1, 25),
    ),
    schema.Required(
      "reports",
      schema.array(report_schema()) |> schema.with_array_length(1, 100),
    ),
    schema.Required(
      "page",
      schema.object([
        schema.Required("offset", bounded_integer(0.0, 100.0)),
        schema.Required("limit", bounded_integer(1.0, 50.0)),
      ]),
    ),
  ])
}

fn source_schema() -> schema.Schema {
  schema.object([
    schema.Required("sourceId", bounded_string(1, 200)),
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

fn report_schema() -> schema.Schema {
  schema.object([
    schema.Required("reportId", bounded_string(1, 500)),
    schema.Required("sourceId", bounded_string(1, 200)),
    schema.Required("currency", bounded_string(3, 3)),
    schema.Required("providerTimestamp", bounded_string(1, 500)),
    schema.Required(
      "providerTimeUnixMilliseconds",
      bounded_integer(0.0, 9_007_199_254_740_991.0),
    ),
    schema.Required(
      "receivedAtUnixMilliseconds",
      bounded_integer(0.0, 9_007_199_254_740_991.0),
    ),
    schema.Required("exchangeTime", exchange_time_schema()),
    schema.Required("sequence", sequence_schema()),
    schema.Required("gap", gap_schema()),
    schema.Required("aggregation", aggregation_schema()),
    schema.Required("sizeUnit", size_unit_schema()),
    schema.Required(
      "conditionCodes",
      schema.array(bounded_string(1, 200)) |> schema.with_array_length(0, 100),
    ),
    schema.Required("bid", side_schema()),
    schema.Required("ask", side_schema()),
  ])
}

fn exchange_time_schema() -> schema.Schema {
  schema.object([
    schema.Required("state", schema.string_enum(["reported", "unknown"])),
    schema.Optional(
      "unixMilliseconds",
      schema.nullable(bounded_integer(0.0, 9_007_199_254_740_991.0)),
    ),
    schema.Optional("sourceLexeme", schema.nullable(bounded_string(1, 500))),
    schema.Optional("reason", schema.nullable(bounded_string(1, 500))),
  ])
  |> schema.described(
    "reported requires unixMilliseconds and sourceLexeme; unknown requires reason",
  )
}

fn sequence_schema() -> schema.Schema {
  schema.object([
    schema.Required("state", schema.string_enum(["reported", "unknown"])),
    schema.Optional(
      "value",
      schema.nullable(bounded_integer(0.0, 9_007_199_254_740_991.0)),
    ),
    schema.Required(
      "scope",
      schema.string_enum(["listing", "feed_global", "unknown"]),
    ),
    schema.Optional("reason", schema.nullable(bounded_string(1, 500))),
  ])
}

fn gap_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "state",
      schema.string_enum([
        "no_gap_reported",
        "sequence_gap",
        "sequence_reset",
        "unknown",
      ]),
    ),
    schema.Optional(
      "fromSequence",
      schema.nullable(bounded_integer(0.0, 9_007_199_254_740_991.0)),
    ),
    schema.Optional(
      "toSequence",
      schema.nullable(bounded_integer(0.0, 9_007_199_254_740_991.0)),
    ),
    schema.Optional("reason", schema.nullable(bounded_string(1, 500))),
  ])
}

fn aggregation_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "kind",
      schema.string_enum([
        "single_venue",
        "consolidated",
        "provider_defined",
        "unknown",
      ]),
    ),
    schema.Required(
      "venues",
      schema.array(venue_schema()) |> schema.with_array_length(0, 25),
    ),
    schema.Required(
      "coverage",
      schema.string_enum([
        "declared_complete",
        "declared_partial",
        "unknown",
      ]),
    ),
    schema.Optional("methodLabel", schema.nullable(bounded_string(1, 500))),
    schema.Optional("reason", schema.nullable(bounded_string(1, 500))),
  ])
}

fn size_unit_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "kind",
      schema.string_enum(["shares", "round_lots", "provider_units", "unknown"]),
    ),
    schema.Optional("label", schema.nullable(bounded_string(1, 200))),
    schema.Optional("reason", schema.nullable(bounded_string(1, 500))),
  ])
}

fn side_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "state",
      schema.string_enum(["observed", "unavailable", "conflicting"]),
    ),
    schema.Optional("candidate", schema.nullable(candidate_schema())),
    schema.Optional("reason", schema.nullable(bounded_string(1, 500))),
    schema.Required(
      "alternatives",
      schema.array(alternative_schema()) |> schema.with_array_length(0, 10),
    ),
  ])
}

fn candidate_schema() -> schema.Schema {
  schema.object([
    schema.Required("rawPrice", bounded_string(1, 500)),
    schema.Required("rawSize", bounded_string(1, 500)),
    schema.Required("venue", venue_schema()),
  ])
}

fn alternative_schema() -> schema.Schema {
  schema.object([
    schema.Required("rawPrice", bounded_string(1, 500)),
    schema.Required("rawSize", bounded_string(1, 500)),
    schema.Required("venue", venue_schema()),
    schema.Required("evidenceId", hash_schema()),
  ])
}

fn venue_schema() -> schema.Schema {
  schema.object([
    schema.Required("kind", schema.string_enum(["mic", "provider_code"])),
    schema.Required("code", bounded_string(1, 100)),
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
