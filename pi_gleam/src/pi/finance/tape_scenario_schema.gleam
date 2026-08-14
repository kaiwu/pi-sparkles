import gleam/int
import pi/schema

/// Shared Pi schema for the provider-neutral transaction-tape possible-fill
/// input. Provider-specific shells narrow provider, track, and MIC values.
pub fn input(
  provider: schema.Schema,
  tracks: List(String),
  mics: List(String),
) -> schema.Schema {
  schema.object([
    schema.Required("operationId", bounded_string(1, 500)),
    schema.Required("provider", provider),
    schema.Required("track", schema.string_enum(tracks)),
    schema.Required("listingId", bounded_string(1, 500)),
    schema.Required("mic", schema.string_enum(mics)),
    schema.Required("sessionId", bounded_string(1, 500)),
    schema.Required("currency", bounded_string(3, 20)),
    schema.Required("timezone", bounded_string(1, 100)),
    schema.Required("entitlement", bounded_string(1, 500)),
    schema.Required("licence", bounded_string(1, 1000)),
    schema.Required("providerReceiptHash", hash_schema()),
    schema.Required(
      "coverage",
      schema.string_enum([
        "provider_declared_complete",
        "bounded_partial",
        "unknown",
      ]),
    ),
    schema.Optional("coverageReason", schema.nullable(bounded_string(1, 500))),
    schema.Required(
      "documentedConditionCodes",
      schema.array(bounded_string(1, 200)) |> schema.with_array_length(0, 100),
    ),
    schema.Required("conditionReferenceHash", hash_schema()),
    schema.Required("instructionId", bounded_string(1, 500)),
    schema.Required("instructionReceiptHash", hash_schema()),
    schema.Required("accountReference", hash_schema()),
    schema.Required("side", schema.string_enum(["buy", "sell"])),
    schema.Required("quantity", bounded_string(1, 500)),
    schema.Required("limitPrice", bounded_string(1, 500)),
    schema.Optional(
      "activationUnixMilliseconds",
      schema.nullable(unix_milliseconds()),
    ),
    schema.Optional(
      "expiryUnixMilliseconds",
      schema.nullable(unix_milliseconds()),
    ),
    schema.Required(
      "ruleReferences",
      schema.array(hash_schema()) |> schema.with_array_length(1, 50),
    ),
    schema.Required(
      "capabilityReferences",
      schema.array(hash_schema()) |> schema.with_array_length(1, 50),
    ),
    schema.Required(
      "eligibleVenueLexemes",
      schema.array(bounded_string(1, 200)) |> schema.with_array_length(1, 50),
    ),
    schema.Required(
      "eligibleConditionCodes",
      schema.array(bounded_string(1, 200)) |> schema.with_array_length(0, 100),
    ),
    schema.Required("allowUnconditionedEvents", schema.boolean()),
    schema.Required("maximumEvents", bounded_integer(1, 10_000)),
    schema.Required(
      "events",
      schema.array(event_schema()) |> schema.with_array_length(1, 10_000),
    ),
  ])
}

fn event_schema() -> schema.Schema {
  schema.object([
    schema.Required("eventId", bounded_string(1, 500)),
    schema.Required("tradeId", bounded_string(1, 500)),
    schema.Required("price", bounded_string(1, 500)),
    schema.Required("size", bounded_string(1, 500)),
    schema.Required("venueLexeme", bounded_string(1, 200)),
    schema.Required(
      "conditionCodes",
      schema.array(bounded_string(1, 200)) |> schema.with_array_length(0, 100),
    ),
    schema.Optional(
      "exchangeUnixMilliseconds",
      schema.nullable(unix_milliseconds()),
    ),
    schema.Optional(
      "providerUnixMilliseconds",
      schema.nullable(unix_milliseconds()),
    ),
    schema.Required("retrievedUnixMilliseconds", unix_milliseconds()),
    schema.Required("sequenceScope", bounded_string(1, 200)),
    schema.Required("sequence", bounded_string(1, 500)),
    schema.Required("rawReceiptHash", hash_schema()),
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
