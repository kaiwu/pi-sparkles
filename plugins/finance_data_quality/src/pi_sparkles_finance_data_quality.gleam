import gleam/javascript/promise.{type Promise}
import pi
import pi/schema
import pi/tool
import pi_sparkles_finance_data_quality/decode
import pi_sparkles_finance_data_quality/domain

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  tool.register(
    api,
    "data_quality_check",
    "Inspect one exact three-track observation compatibility packet",
    "Mechanically report explicit omissions, same-source duplicates, caller-selected as-of-age freshness, unit or adjustment incompatibility, and exact cross-provider agreement or disagreement while retaining every source, receipt, entitlement, licence, unavailable, and conflicting fact",
    "Supply exact expected coordinates and canonical fact metadata; the tool performs no fetch, identity or receipt authentication, inferred-calendar gap detection, provider selection or score, repair, interpolation, correctness verdict, signal, or trade action",
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
        schema.Required("kind", schema.string_enum(["listing", "market"])),
        schema.Required("scopeId", bounded_string(1, 2000)),
        schema.Required("mic", bounded_string(4, 4)),
        schema.Optional("symbol", schema.nullable(bounded_string(1, 100))),
      ])
        |> schema.described(
          "listing requires symbol; market forbids symbol; scopeId and MIC are caller-supplied unverified identity",
        ),
    ),
    schema.Required("freshnessPolicy", freshness_policy_schema()),
    schema.Required(
      "expectedCoordinates",
      schema.array(coordinate_schema()) |> schema.with_array_length(0, 1000),
    ),
    schema.Required(
      "sources",
      schema.array(source_schema()) |> schema.with_array_length(1, 50),
    ),
    schema.Required(
      "facts",
      schema.array(fact_schema()) |> schema.with_array_length(0, 1000),
    ),
    schema.Required(
      "page",
      schema.object([
        schema.Required("offset", bounded_integer(0.0, 2000.0)),
        schema.Required("limit", bounded_integer(1.0, 100.0)),
      ]),
    ),
  ])
}

fn freshness_policy_schema() -> schema.Schema {
  schema.object([
    schema.Required("state", schema.string_enum(["assess", "not_assessed"])),
    schema.Optional(
      "evaluatedAtUnixMilliseconds",
      schema.nullable(bounded_integer(0.0, 9_007_199_254_740_991.0)),
    ),
    schema.Optional(
      "maximumAgeMilliseconds",
      schema.nullable(bounded_integer(0.0, 9_007_199_254_740_991.0)),
    ),
    schema.Optional("reason", schema.nullable(bounded_string(1, 500))),
  ])
  |> schema.described(
    "assess requires evaluation time and maximum age only; not_assessed requires reason only",
  )
}

fn coordinate_schema() -> schema.Schema {
  schema.object([
    schema.Required("observationKey", bounded_string(1, 500)),
    schema.Required("metric", bounded_string(1, 200)),
  ])
}

fn fact_schema() -> schema.Schema {
  schema.object([
    schema.Required("factId", bounded_string(1, 500)),
    schema.Required("observationKey", bounded_string(1, 500)),
    schema.Required("metric", bounded_string(1, 200)),
    schema.Required("sourceId", bounded_string(1, 200)),
    schema.Required(
      "asOfUnixMilliseconds",
      bounded_integer(0.0, 9_007_199_254_740_991.0),
    ),
    schema.Required(
      "retrievedAtUnixMilliseconds",
      bounded_integer(0.0, 9_007_199_254_740_991.0),
    ),
    schema.Required("unit", unit_schema()),
    schema.Required("adjustment", adjustment_schema()),
    schema.Required("value", value_schema()),
  ])
}

fn unit_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "kind",
      schema.string_enum([
        "scalar",
        "currency",
        "currency_per_share",
        "shares",
        "contracts",
        "percent",
        "basis_points",
        "ratio",
        "other",
        "unknown",
      ]),
    ),
    schema.Optional("currencyCode", schema.nullable(bounded_string(3, 3))),
    schema.Optional("otherLabel", schema.nullable(bounded_string(1, 200))),
  ])
  |> schema.described(
    "currency kinds require currencyCode; other requires otherLabel; all remaining kinds forbid both",
  )
}

fn adjustment_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "kind",
      schema.string_enum([
        "raw",
        "split_adjusted",
        "dividend_adjusted",
        "total_return_adjusted",
        "provider_adjusted",
        "not_applicable",
        "unknown",
      ]),
    ),
    schema.Optional("provider", schema.nullable(bounded_string(1, 200))),
    schema.Optional("basis", schema.nullable(bounded_string(1, 500))),
  ])
  |> schema.described(
    "provider_adjusted requires provider and basis; all other states forbid both",
  )
}

fn value_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "state",
      schema.string_enum(["observed", "unavailable", "conflicting"]),
    ),
    schema.Optional("rawValue", schema.nullable(bounded_string(1, 500))),
    schema.Optional("reason", schema.nullable(bounded_string(1, 500))),
    schema.Required(
      "alternatives",
      schema.array(
        schema.object([
          schema.Required("rawValue", bounded_string(1, 500)),
          schema.Required("evidenceId", hash_schema()),
        ]),
      )
        |> schema.with_array_length(0, 10),
    ),
  ])
  |> schema.described(
    "observed requires rawValue only; unavailable requires reason only; conflicting requires reason and two to ten distinct exact alternatives",
  )
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

fn hash_schema() -> schema.Schema {
  schema.string() |> schema.with_string_length(64, 64)
}

fn bounded_string(minimum: Int, maximum: Int) -> schema.Schema {
  schema.string() |> schema.with_string_length(minimum, maximum)
}

fn bounded_integer(minimum: Float, maximum: Float) -> schema.Schema {
  schema.integer() |> schema.with_number_range(minimum, maximum)
}
