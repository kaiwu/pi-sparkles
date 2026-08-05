import finance_core/currency
import finance_core/decimal
import finance_core/identifier
import finance_core/market
import finance_core/time
import finance_listing/listing
import finance_market_accounting
import finance_market_accounting/fact
import finance_market_accounting/json as accounting_json
import finance_market_accounting/mapping
import finance_market_documents/document
import finance_provenance/identity as provenance_identity
import finance_track
import gleam/option.{Some}
import gleam/result
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn package_is_experimental_test() {
  finance_market_accounting.status()
  |> should.equal(finance_market_accounting.Experimental)
}

pub fn exact_lexeme_and_reported_scale_survive_explicit_normalization_test() {
  let value = accounting_fact("100.00", "营业收入")
  value
  |> fact.value
  |> fact.raw_numeric
  |> should.equal(Some("100.00"))
  value
  |> fact.reported_scale
  |> fact.scale_label
  |> should.equal("万元")
  value
  |> fact.normalized_numeric
  |> result.map(decimal.to_string)
  |> should.equal(Ok("1000000"))
}

pub fn executable_mapping_preserves_duplicate_ambiguity_test() {
  let assert Ok(metric) =
    mapping.new(
      name: "revenue",
      accepted_line_codes: ["revenue"],
      unit_kind: mapping.Monetary,
      period_kind: mapping.DurationFact,
      method: "direct reported consolidated duration fact",
    )
  let first = accounting_fact("100.00", "营业收入")
  let second = accounting_fact("101.00", "营业收入（更正）")
  mapping.resolve(
    metric,
    listing_key(),
    fact.Duration(civil(2024, 1, 1), civil(2024, 12, 31)),
    fact.Consolidated,
    [first, second],
  )
  |> should.equal(identifier.Ambiguous(first, second, []))
}

pub fn wire_round_trip_preserves_exact_numeric_lexeme_scale_and_unicode_test() {
  let original = accounting_fact("9007199254740993.0100", "营业收入（更正）")
  let encoded = accounting_json.encode(original)
  let assert Ok(decoded) = accounting_json.decode(encoded)

  decoded |> should.equal(original)
  decoded
  |> fact.value
  |> fact.raw_numeric
  |> should.equal(Some("9007199254740993.0100"))
  decoded
  |> fact.reported_scale
  |> fact.scale_label
  |> should.equal("万元")
  decoded
  |> fact.listing
  |> listing.track
  |> should.equal(finance_track.Cn)
}

pub fn numeric_wire_value_must_be_a_string_and_version_is_strict_test() {
  accounting_json.decode("{\"schemaVersion\":2}") |> should.be_error
  let unsafe =
    accounting_json.encode(accounting_fact("100.00", "营业收入"))
    |> string.replace("\"value\":\"100.00\"", "\"value\":100.00")
  accounting_json.decode(unsafe) |> should.be_error
}

fn accounting_fact(raw: String, label: String) -> fact.Fact {
  let assert Ok(value) = fact.numeric(raw)
  let assert Ok(scale) = fact.scale("万元", exact("10000"))
  let assert Ok(cny) = currency.from_code("CNY")
  let assert Ok(document_id) = document.document_id("synthetic-report")
  let assert Ok(result) =
    fact.new(
      listing: listing_key(),
      document_id: document_id,
      line_code: Some("revenue"),
      original_label: label,
      value: value,
      reported_unit: "万元",
      scale: scale,
      normalized_unit: Some(market.Currency(cny)),
      accounting_standard: "synthetic_standard",
      statement_scope: fact.Consolidated,
      period: fact.Duration(civil(2024, 1, 1), civil(2024, 12, 31)),
      report_class: "annual",
      audit_state: fact.Audited,
      restatement_state: fact.Original,
      evidence_id: evidence_id(),
    )
  result
}

fn listing_key() -> listing.Key {
  let assert Ok(instrument) = identifier.instrument_id("accounting-issuer")
  let assert Ok(symbol) = identifier.symbol("600000")
  let assert Ok(mic) = identifier.mic("XSHG")
  listing.new(finance_track.Cn, instrument, symbol, mic)
}

fn evidence_id() -> provenance_identity.EvidenceId {
  let assert Ok(hash) = provenance_identity.sha256(string.repeat("a", 64))
  provenance_identity.evidence_id(hash)
}

fn civil(year: Int, month: Int, day: Int) -> time.Date {
  let assert Ok(value) = time.date(year, month, day)
  value
}

fn exact(value: String) -> decimal.Decimal {
  let assert Ok(parsed) = decimal.parse(value)
  parsed
}
