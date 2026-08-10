import gleam/javascript/promise.{type Promise}
import pi
import pi/schema
import pi/tool
import pi_sparkles_stock_history/decode
import pi_sparkles_stock_history/domain

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  tool.register(
    api,
    "stock_bars",
    "Inspect one exact bounded three-track daily OHLCV series",
    "Validate and page one caller or provider-adapter daily OHLCV series for an exact cn, hk, or us listing and MIC while retaining raw lexemes, time basis, adjustment, calendar gaps, source receipt, entitlement, licence, and unknown facts",
    "Supply every bar and source fact explicitly; the tool performs no fetch, provider choice, fallback, calendar inference, gap repair, interpolation, return calculation, signal, rank, or trade action",
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
      "range",
      schema.object([
        schema.Required("startDate", bounded_string(10, 10)),
        schema.Required("endDate", bounded_string(10, 10)),
      ]),
    ),
    schema.Required("batch", batch_schema()),
    schema.Required(
      "bars",
      schema.array(bar_schema()) |> schema.with_array_length(0, 2000),
    ),
    schema.Required("source", source_schema()),
    schema.Required(
      "page",
      schema.object([
        schema.Required("offset", bounded_integer(0.0, 2000.0)),
        schema.Required("limit", bounded_integer(1.0, 200.0)),
      ]),
    ),
  ])
}

fn batch_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "retrievedAtUnixMilliseconds",
      bounded_integer(0.0, 9_007_199_254_740_991.0),
    ),
    schema.Required("currency", bounded_string(3, 3)),
    schema.Required("volumeUnit", schema.string_enum(["shares", "unknown"])),
    schema.Required(
      "adjustment",
      schema.object([
        schema.Required(
          "kind",
          schema.string_enum([
            "raw",
            "split_adjusted",
            "dividend_adjusted",
            "total_return_adjusted",
            "provider_adjusted",
          ]),
        ),
        schema.Optional("provider", schema.nullable(bounded_string(1, 200))),
        schema.Optional("basis", schema.nullable(bounded_string(1, 500))),
      ])
        |> schema.described(
          "provider_adjusted requires provider and basis; other kinds forbid both",
        ),
    ),
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
      "pagination",
      schema.object([
        schema.Required(
          "state",
          schema.string_enum([
            "complete",
            "truncated_by_page_budget",
            "truncated_by_bar_budget",
          ]),
        ),
        schema.Optional(
          "maximum",
          schema.nullable(bounded_integer(1.0, 2000.0)),
        ),
      ])
        |> schema.described(
          "complete forbids maximum; truncated states require their positive maximum",
        ),
    ),
    schema.Required(
      "calendar",
      schema.object([
        schema.Required(
          "state",
          schema.string_enum(["not_assessed", "assessed"]),
        ),
        schema.Optional("reason", schema.nullable(bounded_string(1, 200))),
        schema.Required(
          "gaps",
          schema.array(gap_schema()) |> schema.with_array_length(0, 2000),
        ),
      ])
        |> schema.described(
          "not_assessed requires a lower-snake-case reason and no gaps; assessed forbids reason",
        ),
    ),
  ])
}

fn gap_schema() -> schema.Schema {
  schema.object([
    schema.Required("sessionDate", bounded_string(10, 10)),
    schema.Required(
      "state",
      schema.string_enum([
        "market_closure",
        "suspension",
        "provider_omission",
        "unavailable_history",
      ]),
    ),
    schema.Optional(
      "evidenceReference",
      schema.nullable(bounded_string(1, 8000)),
    ),
  ])
}

fn bar_schema() -> schema.Schema {
  schema.object([
    schema.Required("sessionDate", bounded_string(10, 10)),
    schema.Required("sourceTimestamp", bounded_string(1, 100)),
    schema.Required(
      "timeBasis",
      schema.string_enum(["source_instant", "session_date_anchor"]),
    ),
    schema.Optional(
      "atUnixMilliseconds",
      schema.nullable(bounded_integer(0.0, 9_007_199_254_740_991.0)),
    ),
    schema.Required("rawOpen", bounded_string(1, 500)),
    schema.Required("rawHigh", bounded_string(1, 500)),
    schema.Required("rawLow", bounded_string(1, 500)),
    schema.Required("rawClose", bounded_string(1, 500)),
    schema.Required("rawVolume", bounded_string(1, 500)),
    schema.Optional("rawTradeCount", schema.nullable(bounded_string(1, 500))),
    schema.Optional("rawVwap", schema.nullable(bounded_string(1, 500))),
  ])
  |> schema.described(
    "source_instant requires atUnixMilliseconds; session_date_anchor forbids it and requires sourceTimestamp to equal sessionDate",
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
