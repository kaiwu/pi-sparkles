import gleam/javascript/promise.{type Promise}
import pi
import pi/schema
import pi/tool
import pi_sparkles_stock_market_snapshot/decode
import pi_sparkles_stock_market_snapshot/domain

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  tool.register(
    api,
    "market_snapshot",
    "Inspect one exact three-track point-in-time market breadth packet",
    "Validate one caller or provider-adapter cn, hk, or us market/MIC snapshot and calculate exact overall and group advance/decline/unchanged facts plus tie-preserving supplied-row change extrema while retaining partial, unavailable, conflicting, source, entitlement, and licence facts",
    "Supply every member and source fact explicitly; the tool performs no fetch, provider choice, cross-track fallback, membership completion, fund-flow inference, forecast, investment ranking, signal, or trade action",
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
      "market",
      schema.object([
        schema.Required("mic", bounded_string(4, 4)),
        schema.Required(
          "scopeKind",
          schema.string_enum(["venue", "index", "sector", "industry", "other"]),
        ),
        schema.Required("scopeId", bounded_string(1, 200)),
        schema.Required("label", bounded_string(1, 500)),
      ]),
    ),
    schema.Required("snapshot", snapshot_schema()),
    schema.Required(
      "members",
      schema.array(member_schema()) |> schema.with_array_length(0, 1000),
    ),
    schema.Required(
      "calculation",
      schema.object([
        schema.Required("changeFractionScale", bounded_integer(0.0, 18.0)),
        schema.Required(
          "rounding",
          schema.string_enum([
            "half_even",
            "half_up",
            "toward_zero",
            "away_from_zero",
          ]),
        ),
        schema.Required("extremaLimit", bounded_integer(1.0, 50.0)),
      ]),
    ),
    schema.Required("source", source_schema()),
    schema.Required(
      "page",
      schema.object([
        schema.Required("offset", bounded_integer(0.0, 1000.0)),
        schema.Required("limit", bounded_integer(1.0, 200.0)),
      ]),
    ),
  ])
}

fn snapshot_schema() -> schema.Schema {
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
    schema.Required(
      "session",
      schema.object([
        schema.Required(
          "state",
          schema.string_enum([
            "pre_market",
            "regular",
            "after_hours",
            "auction",
            "closed",
            "other",
          ]),
        ),
        schema.Optional("otherLabel", schema.nullable(bounded_string(1, 200))),
      ])
        |> schema.described("other requires otherLabel; other states forbid it"),
    ),
    schema.Required(
      "coverage",
      schema.object([
        schema.Required(
          "state",
          schema.string_enum(["complete", "partial", "unknown"]),
        ),
        schema.Optional(
          "expectedMembers",
          schema.nullable(bounded_integer(0.0, 1_000_000.0)),
        ),
        schema.Optional("reason", schema.nullable(bounded_string(1, 500))),
      ])
        |> schema.described(
          "complete requires expectedMembers equal to supplied rows and forbids reason; partial requires a larger expectedMembers plus reason; unknown requires reason and forbids expectedMembers",
        ),
    ),
  ])
}

fn member_schema() -> schema.Schema {
  schema.object([
    schema.Required("listingId", bounded_string(1, 2000)),
    schema.Required("mic", bounded_string(4, 4)),
    schema.Required("symbol", bounded_string(1, 100)),
    schema.Optional("label", schema.nullable(bounded_string(1, 500))),
    schema.Required(
      "groups",
      schema.array(
        schema.object([
          schema.Required(
            "kind",
            schema.string_enum(["index", "sector", "industry", "other"]),
          ),
          schema.Required("id", bounded_string(1, 200)),
          schema.Required("label", bounded_string(1, 500)),
        ]),
      )
        |> schema.with_array_length(0, 10),
    ),
    schema.Required("price", price_schema()),
    schema.Required("volume", measurement_schema()),
    schema.Required("volatility", measurement_schema()),
  ])
}

fn price_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "state",
      schema.string_enum(["observed", "unavailable", "conflicting"]),
    ),
    schema.Optional("rawCurrent", schema.nullable(bounded_string(1, 500))),
    schema.Optional("rawPreviousClose", schema.nullable(bounded_string(1, 500))),
    schema.Optional("reason", schema.nullable(bounded_string(1, 500))),
    schema.Required(
      "alternatives",
      schema.array(
        schema.object([
          schema.Required("rawCurrent", bounded_string(1, 500)),
          schema.Required("rawPreviousClose", bounded_string(1, 500)),
          schema.Required("evidenceId", hash_schema()),
        ]),
      )
        |> schema.with_array_length(0, 10),
    ),
  ])
  |> schema.described(
    "observed requires direct current/previous values only; unavailable requires reason only; conflicting requires reason and at least two alternatives only",
  )
}

fn measurement_schema() -> schema.Schema {
  schema.object([
    schema.Required("state", schema.string_enum(["reported", "unavailable"])),
    schema.Optional("rawValue", schema.nullable(bounded_string(1, 500))),
    schema.Optional("unit", schema.nullable(bounded_string(1, 100))),
    schema.Optional("method", schema.nullable(bounded_string(1, 200))),
    schema.Optional("reason", schema.nullable(bounded_string(1, 500))),
  ])
  |> schema.described(
    "reported requires the measurement-specific fields and forbids reason; unavailable requires reason and forbids value/unit/method",
  )
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
