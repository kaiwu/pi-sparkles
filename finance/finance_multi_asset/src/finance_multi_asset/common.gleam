import finance_core/decimal.{type Decimal}
import finance_math/exact
import finance_provenance/hash
import finance_provenance/identity
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub type Error {
  InvalidJson
  ContentHashMismatch
  WrongSchema
  WrongContract(expected: String, received: String)
  WrongOperation(expected: String, received: String)
  InvalidField(field: String, reason: String)
  InvalidReceipt(field: String)
  CalculationUnperformed(reason: String)
  BudgetExceeded(field: String, received: Int, maximum: Int)
}

pub type Metadata {
  Metadata(schema_version: Int, contract_id: String, operation: String)
}

pub type Source {
  Source(
    source_id: String,
    source_kind: String,
    source_uri: String,
    observed_at_unix_ms: Int,
    retrieved_at_unix_ms: Int,
    entitlement: String,
    licence: String,
    coverage: String,
    correction_state: String,
    receipt: String,
  )
}

pub type Fact {
  Fact(
    state: String,
    raw: Option(String),
    unit: String,
    observed_at_unix_ms: Int,
    reason: Option(String),
    alternatives: List(String),
    receipts: List(String),
  )
}

pub type Response {
  Response(summary: String, details: json.Json)
}

pub fn summary(value: Response) -> String {
  value.summary
}

pub fn details(value: Response) -> json.Json {
  value.details
}

pub fn response(
  contract_id: String,
  operation: String,
  input_hash: String,
  summary: String,
  fields: List(#(String, json.Json)),
) -> Response {
  let receipt = result_receipt(contract_id, operation, input_hash)
  Response(
    summary,
    json.object([
      #("schemaVersion", json.int(1)),
      #("contractId", json.string(contract_id)),
      #("operation", json.string(operation)),
      #("decisionOwner", json.string("llm_or_user")),
      #("inputContentHash", json.string(input_hash)),
      #("resultReceipt", json.string(receipt)),
      #(
        "receiptAuthentication",
        json.string("content_binding_only_not_origin_authentication"),
      ),
      #("result", json.object(fields)),
    ]),
  )
}

pub fn error_message(error: Error) -> String {
  case error {
    InvalidJson -> "Multi-asset packet is not valid versioned JSON"
    ContentHashMismatch -> "Multi-asset packet does not match expectedSha256"
    WrongSchema -> "Multi-asset packet schemaVersion must be 1"
    WrongContract(expected, received) ->
      "Multi-asset packet contractId must be "
      <> expected
      <> ", received "
      <> received
    WrongOperation(expected, received) ->
      "Multi-asset packet operation must be "
      <> expected
      <> ", received "
      <> received
    InvalidField(field, reason) ->
      "Invalid multi-asset field " <> field <> ": " <> reason
    InvalidReceipt(field) ->
      "Multi-asset field "
      <> field
      <> " must be exactly 64 hexadecimal SHA-256 characters"
    CalculationUnperformed(reason) ->
      "Multi-asset calculation is unperformed: " <> reason
    BudgetExceeded(field, received, maximum) ->
      field
      <> " budget exceeded: received "
      <> int.to_string(received)
      <> ", maximum "
      <> int.to_string(maximum)
  }
}

pub fn decode_packet(
  bytes: String,
  expected_sha256: String,
  contract_id: String,
  operation: String,
  decoder: decode.Decoder(value),
) -> Result(#(value, String), Error) {
  use input_hash <- result.try(verify_packet(
    bytes,
    expected_sha256,
    contract_id,
    operation,
  ))
  use value <- result.try(parse(bytes, decoder))
  Ok(#(value, input_hash))
}

pub fn verify_packet(
  bytes: String,
  expected_sha256: String,
  contract_id: String,
  operation: String,
) -> Result(String, Error) {
  use actual <- result.try(case hash.text(bytes) {
    Ok(value) -> Ok(identity.sha256_value(value))
    Error(_) -> Error(ContentHashMismatch)
  })
  use _ <- result.try(case actual == expected_sha256 {
    True -> Ok(Nil)
    False -> Error(ContentHashMismatch)
  })
  use metadata <- result.try(parse(bytes, metadata_decoder()))
  use _ <- result.try(case metadata.schema_version == 1 {
    True -> Ok(Nil)
    False -> Error(WrongSchema)
  })
  use _ <- result.try(case metadata.contract_id == contract_id {
    True -> Ok(Nil)
    False -> Error(WrongContract(contract_id, metadata.contract_id))
  })
  use _ <- result.try(case metadata.operation == operation {
    True -> Ok(Nil)
    False -> Error(WrongOperation(operation, metadata.operation))
  })
  Ok(actual)
}

pub fn parse(
  bytes: String,
  decoder: decode.Decoder(value),
) -> Result(value, Error) {
  json.parse(bytes, decoder) |> result.map_error(fn(_) { InvalidJson })
}

pub fn metadata_decoder() -> decode.Decoder(Metadata) {
  use schema_version <- decode.field("schemaVersion", decode.int)
  use contract_id <- decode.field("contractId", decode.string)
  use operation <- decode.field("operation", decode.string)
  decode.success(Metadata(schema_version, contract_id, operation))
}

pub fn source_decoder() -> decode.Decoder(Source) {
  use source_id <- decode.field("sourceId", decode.string)
  use source_kind <- decode.field("sourceKind", decode.string)
  use source_uri <- decode.field("sourceUri", decode.string)
  use observed <- decode.field("observedAtUnixMilliseconds", decode.int)
  use retrieved <- decode.field("retrievedAtUnixMilliseconds", decode.int)
  use entitlement <- decode.field("entitlement", decode.string)
  use licence <- decode.field("licence", decode.string)
  use coverage <- decode.field("coverage", decode.string)
  use correction <- decode.field("correctionState", decode.string)
  use receipt <- decode.field("receipt", decode.string)
  decode.success(Source(
    source_id,
    source_kind,
    source_uri,
    observed,
    retrieved,
    entitlement,
    licence,
    coverage,
    correction,
    receipt,
  ))
}

pub fn fact_decoder() -> decode.Decoder(Fact) {
  use state <- decode.field("state", decode.string)
  use raw <- decode.optional_field("raw", None, decode.optional(decode.string))
  use unit <- decode.field("unit", decode.string)
  use observed <- decode.field("observedAtUnixMilliseconds", decode.int)
  use reason <- decode.optional_field(
    "reason",
    None,
    decode.optional(decode.string),
  )
  use alternatives <- decode.optional_field(
    "alternatives",
    [],
    decode.list(of: decode.string),
  )
  use receipts <- decode.field("receipts", decode.list(of: decode.string))
  decode.success(Fact(
    state,
    raw,
    unit,
    observed,
    reason,
    alternatives,
    receipts,
  ))
}

pub fn validate_source(source: Source) -> Result(Nil, Error) {
  use _ <- result.try(non_empty("source.sourceId", source.source_id))
  use _ <- result.try(
    one_of("source.sourceKind", source.source_kind, [
      "official_public",
      "licensed_provider",
      "user_owned_import",
      "scripted_fixture",
    ]),
  )
  use _ <- result.try(non_empty("source.sourceUri", source.source_uri))
  use _ <- result.try(non_empty("source.entitlement", source.entitlement))
  use _ <- result.try(non_empty("source.licence", source.licence))
  use _ <- result.try(non_empty("source.coverage", source.coverage))
  use _ <- result.try(non_empty(
    "source.correctionState",
    source.correction_state,
  ))
  use _ <- result.try(non_negative(
    "source.observedAtUnixMilliseconds",
    source.observed_at_unix_ms,
  ))
  use _ <- result.try(non_negative(
    "source.retrievedAtUnixMilliseconds",
    source.retrieved_at_unix_ms,
  ))
  receipt("source.receipt", source.receipt)
}

pub fn validate_fact(field: String, fact: Fact) -> Result(Nil, Error) {
  use _ <- result.try(
    one_of(field <> ".state", fact.state, [
      "known",
      "unknown",
      "conflicting",
      "not_applicable",
    ]),
  )
  use _ <- result.try(non_empty(field <> ".unit", fact.unit))
  use _ <- result.try(non_negative(
    field <> ".observedAtUnixMilliseconds",
    fact.observed_at_unix_ms,
  ))
  use _ <- result.try(case fact.receipts {
    [] -> Error(InvalidField(field <> ".receipts", "must not be empty"))
    receipts -> validate_receipts(field <> ".receipts", receipts)
  })
  case fact.state, fact.raw, fact.reason, fact.alternatives {
    "known", Some(raw), _, _ -> non_empty(field <> ".raw", raw)
    "known", None, _, _ ->
      Error(InvalidField(field <> ".raw", "known fact requires raw"))
    "unknown", _, Some(reason), _ -> non_empty(field <> ".reason", reason)
    "unknown", _, None, _ ->
      Error(InvalidField(field <> ".reason", "unknown fact requires reason"))
    "conflicting", _, _, [_, _, ..] -> Ok(Nil)
    "conflicting", _, _, _ ->
      Error(InvalidField(
        field <> ".alternatives",
        "conflicting fact requires at least two alternatives",
      ))
    "not_applicable", _, Some(reason), _ ->
      non_empty(field <> ".reason", reason)
    "not_applicable", _, None, _ ->
      Error(InvalidField(
        field <> ".reason",
        "not_applicable fact requires reason",
      ))
    _, _, _, _ -> Ok(Nil)
  }
}

pub fn fact_decimal(field: String, fact: Fact) -> Result(Decimal, Error) {
  use _ <- result.try(validate_fact(field, fact))
  case fact.state, fact.raw {
    "known", Some(raw) ->
      decimal.parse(raw)
      |> result.map_error(fn(_) {
        InvalidField(field <> ".raw", "must be an exact decimal lexeme")
      })
    _, _ -> Error(CalculationUnperformed(field <> " is " <> fact.state))
  }
}

pub fn fact_json(fact: Fact) -> json.Json {
  json.object([
    #("state", json.string(fact.state)),
    #("raw", option_string_json(fact.raw)),
    #("unit", json.string(fact.unit)),
    #("observedAtUnixMilliseconds", json.int(fact.observed_at_unix_ms)),
    #("reason", option_string_json(fact.reason)),
    #("alternatives", json.array(fact.alternatives, json.string)),
    #("receipts", json.array(fact.receipts, json.string)),
  ])
}

pub fn source_json(source: Source) -> json.Json {
  json.object([
    #("sourceId", json.string(source.source_id)),
    #("sourceKind", json.string(source.source_kind)),
    #("sourceUri", json.string(source.source_uri)),
    #("observedAtUnixMilliseconds", json.int(source.observed_at_unix_ms)),
    #("retrievedAtUnixMilliseconds", json.int(source.retrieved_at_unix_ms)),
    #("entitlement", json.string(source.entitlement)),
    #("licence", json.string(source.licence)),
    #("coverage", json.string(source.coverage)),
    #("correctionState", json.string(source.correction_state)),
    #("receipt", json.string(source.receipt)),
  ])
}

pub fn calculation_json(
  formula: String,
  value: Result(Decimal, Error),
  unit: String,
  leaves: List(#(String, json.Json)),
) -> json.Json {
  case value {
    Ok(decimal_value) ->
      json.object([
        #("state", json.string("calculated")),
        #("formula", json.string(formula)),
        #("value", json.string(decimal.to_string(decimal_value))),
        #("unit", json.string(unit)),
        #("leaves", json.object(leaves)),
        #("rounding", json.string("half_even")),
      ])
    Error(error) ->
      json.object([
        #("state", json.string("unperformed")),
        #("formula", json.string(formula)),
        #("reason", json.string(error_message(error))),
        #("unit", json.string(unit)),
        #("leaves", json.object(leaves)),
      ])
  }
}

pub fn ratio(
  numerator: Decimal,
  denominator: Decimal,
  scale: Int,
) -> Result(Decimal, Error) {
  exact.ratio(numerator, denominator, scale, decimal.HalfEven)
  |> result.map_error(fn(_) { CalculationUnperformed("division_by_zero") })
}

pub fn percentage(
  numerator: Decimal,
  denominator: Decimal,
  scale: Int,
) -> Result(Decimal, Error) {
  exact.percentage(numerator, denominator, scale, decimal.HalfEven)
  |> result.map_error(fn(_) { CalculationUnperformed("division_by_zero") })
}

pub fn decimal_json(value: Decimal) -> json.Json {
  value |> decimal.to_string |> json.string
}

pub fn decimal_float(value: Decimal) -> Result(Float, Error) {
  let text = decimal.to_string(value)
  let float_text = case string.contains(text, ".") {
    True -> text
    False -> text <> ".0"
  }
  float.parse(float_text)
  |> result.map_error(fn(_) {
    CalculationUnperformed("exact decimal is outside finite float range")
  })
}

pub fn option_string_json(value: Option(String)) -> json.Json {
  case value {
    Some(text) -> json.string(text)
    None -> json.null()
  }
}

pub fn non_empty(field: String, value: String) -> Result(Nil, Error) {
  case string.trim(value) == "" {
    True -> Error(InvalidField(field, "must not be empty"))
    False -> Ok(Nil)
  }
}

pub fn non_negative(field: String, value: Int) -> Result(Nil, Error) {
  case value >= 0 {
    True -> Ok(Nil)
    False -> Error(InvalidField(field, "must be non-negative"))
  }
}

pub fn positive(field: String, value: Int) -> Result(Nil, Error) {
  case value > 0 {
    True -> Ok(Nil)
    False -> Error(InvalidField(field, "must be positive"))
  }
}

pub fn one_of(
  field: String,
  value: String,
  allowed: List(String),
) -> Result(Nil, Error) {
  case list.contains(allowed, value) {
    True -> Ok(Nil)
    False ->
      Error(InvalidField(field, "must be one of " <> string.join(allowed, ",")))
  }
}

pub fn receipt(field: String, value: String) -> Result(Nil, Error) {
  case identity.sha256(value) {
    Ok(_) -> Ok(Nil)
    Error(_) -> Error(InvalidReceipt(field))
  }
}

pub fn validate_receipts(
  field: String,
  receipts: List(String),
) -> Result(Nil, Error) {
  receipts
  |> list.index_map(fn(value, index) {
    receipt(field <> "[" <> int.to_string(index) <> "]", value)
  })
  |> list.try_map(fn(value) { value })
  |> result.map(fn(_) { Nil })
}

pub fn date(field: String, value: String) -> Result(Nil, Error) {
  case
    string.length(value) == 10,
    string.slice(value, at_index: 4, length: 1) == "-",
    string.slice(value, at_index: 7, length: 1) == "-"
  {
    True, True, True -> Ok(Nil)
    _, _, _ -> Error(InvalidField(field, "must be canonical YYYY-MM-DD"))
  }
}

fn result_receipt(
  contract_id: String,
  operation: String,
  input_hash: String,
) -> String {
  let assert Ok(value) =
    hash.text(
      "finance_multi_asset_v1|"
      <> contract_id
      <> "|"
      <> operation
      <> "|"
      <> input_hash,
    )
  identity.sha256_value(value)
}
