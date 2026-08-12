import finance_multi_asset/common
import finance_multi_asset/fx
import finance_provenance/hash
import finance_provenance/identity
import gleam/json
import gleam/option.{None, Some}
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn known_fact_requires_an_exact_raw_lexeme_test() {
  common.validate_fact(
    "price",
    common.Fact("known", None, "USD", 100, None, [], [sha_text("price")]),
  )
  |> should.be_error
}

pub fn conflicting_fact_retains_at_least_two_alternatives_test() {
  common.validate_fact(
    "price",
    common.Fact(
      "conflicting",
      None,
      "USD",
      100,
      Some("sources disagree"),
      ["10"],
      [sha_text("price")],
    ),
  )
  |> should.be_error
}

pub fn source_receipt_must_be_a_sha256_digest_test() {
  common.validate_source(common.Source(
    "fixture",
    "scripted_fixture",
    "fixture://t5",
    100,
    110,
    "local",
    "rights-safe",
    "complete fixture",
    "original",
    "not-a-digest",
  ))
  |> should.be_error
}

pub fn packet_hash_and_contract_are_both_verified_test() {
  let packet =
    json.object([
      #("schemaVersion", json.int(1)),
      #("contractId", json.string("fx_ecb_v1")),
      #("operation", json.string("calculate")),
    ])
    |> json.to_string
  common.verify_packet(packet, sha_text(packet), "wrong_v1", "calculate")
  |> should.be_error
  common.verify_packet(packet, sha_text("different"), "fx_ecb_v1", "calculate")
  |> should.be_error
}

pub fn ecb_cross_rate_is_same_date_reference_only_test() {
  let packet =
    json.object([
      #("schemaVersion", json.int(1)),
      #("contractId", json.string("fx_ecb_v1")),
      #("operation", json.string("calculate")),
      #("source", source_json("ecb")),
      #("effectiveDate", json.string("2026-08-11")),
      #("publicationAtUnixMilliseconds", json.int(1000)),
      #("targetCalendarReceipt", json.string(sha_text("target"))),
      #("pivotCurrency", json.string("EUR")),
      #("baseCurrency", json.string("USD")),
      #("quoteCurrency", json.string("CNY")),
      #("amount", fact_json("100", "USD", "amount", 1000)),
      #("basePerPivot", fact_json("1.25", "USD_per_EUR", "usd", 1000)),
      #("quotePerPivot", fact_json("7.5", "CNY_per_EUR", "cny", 1000)),
    ])
    |> json.to_string
  let assert Ok(response) = fx.calculate(packet, sha_text(packet))
  let text = response |> common.details |> json.to_string
  text |> string.contains("\"value\":\"6\"") |> should.be_true
  text |> string.contains("\"value\":\"600\"") |> should.be_true
  text
  |> string.contains("ecb_reference_not_executable_quote")
  |> should.be_true
  text
  |> string.contains("content_binding_only_not_origin_authentication")
  |> should.be_true
}

fn source_json(id: String) -> json.Json {
  json.object([
    #("sourceId", json.string(id)),
    #("sourceKind", json.string("scripted_fixture")),
    #("sourceUri", json.string("fixture://t5/" <> id)),
    #("observedAtUnixMilliseconds", json.int(1000)),
    #("retrievedAtUnixMilliseconds", json.int(1100)),
    #("entitlement", json.string("local fixture analysis")),
    #("licence", json.string("rights-safe fixture")),
    #("coverage", json.string("complete acceptance sample")),
    #("correctionState", json.string("original")),
    #("receipt", json.string(sha_text("source:" <> id))),
  ])
}

fn fact_json(
  raw: String,
  unit: String,
  id: String,
  observed: Int,
) -> json.Json {
  json.object([
    #("state", json.string("known")),
    #("raw", json.string(raw)),
    #("unit", json.string(unit)),
    #("observedAtUnixMilliseconds", json.int(observed)),
    #("reason", json.null()),
    #("alternatives", json.array([], json.string)),
    #("receipts", json.array([sha_text("fact:" <> id)], json.string)),
  ])
}

fn sha_text(value: String) -> String {
  let assert Ok(value) = hash.text(value)
  identity.sha256_value(value)
}
