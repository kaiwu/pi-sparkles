import gleam/javascript/promise.{type Promise}
import pi
import pi/schema
import pi/tool
import pi_sparkles_stock_market_calendar/decode
import pi_sparkles_stock_market_calendar/domain

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  tool.register(
    api,
    "stock_session_status",
    "Inspect one exact three-track stock session status packet",
    "Validate one caller or provider-adapter cn, hk, or us track/MIC query and retain exact schedule, phase, market-status, and listing-halt observations with mechanical agreement and active-interval facts",
    "Supply every source and fact explicitly; the tool performs no fetch, venue or provider choice, calendar completion, inferred phase or halt, scheduling, alert, readiness judgment, or trade action",
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
      "scope",
      schema.object([
        schema.Required("kind", schema.string_enum(["market", "listing"])),
        schema.Required("scopeId", bounded_string(1, 2000)),
        schema.Required("mic", bounded_string(4, 4)),
        schema.Optional("symbol", schema.nullable(bounded_string(1, 100))),
      ])
        |> schema.described(
          "market forbids symbol; listing requires the exact caller-supplied symbol",
        ),
    ),
    schema.Required(
      "query",
      schema.object([
        schema.Required("date", bounded_string(10, 10)),
        schema.Required("localTime", bounded_string(8, 8)),
        schema.Required("timezone", bounded_string(1, 100)),
        schema.Required(
          "atUnixMilliseconds",
          bounded_integer(0.0, 9_007_199_254_740_991.0),
        ),
      ])
        |> schema.described(
          "Canonical Gregorian date, HH:MM:SS MIC-local time, exact venue timezone, and caller-declared Unix instant",
        ),
    ),
    schema.Required(
      "sources",
      schema.array(source_schema()) |> schema.with_array_length(1, 25),
    ),
    schema.Required(
      "facts",
      schema.array(fact_schema()) |> schema.with_array_length(1, 500),
    ),
    schema.Required(
      "page",
      schema.object([
        schema.Required("offset", bounded_integer(0.0, 500.0)),
        schema.Required("limit", bounded_integer(1.0, 100.0)),
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
    schema.Required("coverage", coverage_schema()),
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

fn coverage_schema() -> schema.Schema {
  schema.object([
    schema.Required("state", schema.string_enum(["exact_range", "unknown"])),
    schema.Optional(
      "startUnixMilliseconds",
      schema.nullable(bounded_integer(0.0, 9_007_199_254_740_991.0)),
    ),
    schema.Optional(
      "endUnixMilliseconds",
      schema.nullable(bounded_integer(0.0, 9_007_199_254_740_991.0)),
    ),
    schema.Optional("reason", schema.nullable(bounded_string(1, 500))),
  ])
  |> schema.described(
    "exact_range requires inclusive start/end only; unknown requires reason only",
  )
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

fn fact_schema() -> schema.Schema {
  schema.object([
    schema.Required("factId", bounded_string(1, 500)),
    schema.Required(
      "kind",
      schema.string_enum([
        "schedule",
        "phase",
        "market_status",
        "listing_halt",
      ]),
    ),
    schema.Required("sourceId", bounded_string(1, 200)),
    schema.Optional("date", schema.nullable(bounded_string(10, 10))),
    schema.Required(
      "asOfUnixMilliseconds",
      bounded_integer(0.0, 9_007_199_254_740_991.0),
    ),
    schema.Required(
      "retrievedAtUnixMilliseconds",
      bounded_integer(0.0, 9_007_199_254_740_991.0),
    ),
    schema.Required("value", value_schema()),
  ])
  |> schema.described(
    "schedule requires query date; other kinds forbid date; listing_halt requires listing scope",
  )
}

fn value_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "state",
      schema.string_enum(["observed", "unavailable", "conflicting"]),
    ),
    schema.Optional("category", schema.nullable(bounded_string(1, 100))),
    schema.Optional("otherLabel", schema.nullable(bounded_string(1, 200))),
    schema.Optional("startsAtLocal", schema.nullable(bounded_string(19, 19))),
    schema.Optional("endsAtLocal", schema.nullable(bounded_string(19, 19))),
    schema.Optional("reason", schema.nullable(bounded_string(1, 500))),
    schema.Required(
      "alternatives",
      schema.array(alternative_schema()) |> schema.with_array_length(0, 10),
    ),
  ])
  |> schema.described(
    "observed requires one direct typed value; unavailable requires reason only; conflicting requires reason and two to ten distinct typed alternatives",
  )
}

fn alternative_schema() -> schema.Schema {
  schema.object([
    schema.Required("category", bounded_string(1, 100)),
    schema.Optional("otherLabel", schema.nullable(bounded_string(1, 200))),
    schema.Optional("startsAtLocal", schema.nullable(bounded_string(19, 19))),
    schema.Optional("endsAtLocal", schema.nullable(bounded_string(19, 19))),
    schema.Required("evidenceId", hash_schema()),
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
