import finance_core/currency
import finance_core/decimal
import finance_core/identifier
import finance_core/instrument
import finance_core/market
import finance_core/source
import finance_core/time
import finance_hk_accounting
import finance_hk_accounting/fact as hk_fact
import finance_hk_documents/document as hk_document
import finance_hk_identity/identity
import finance_market_accounting/fact
import finance_market_documents/document
import finance_provenance/identity as provenance_identity
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn package_is_experimental_test() {
  finance_hk_accounting.status()
  |> should.equal(finance_hk_accounting.Experimental)
}

pub fn hk_fact_retains_parallel_language_label_standard_and_scale_test() {
  let listing = hk_listing()
  let document = report(listing)
  let assert Ok(value) = fact.numeric("42.500")
  let assert Ok(scale) = fact.scale("HK$ million", exact("1000000"))
  let assert Ok(hkd) = currency.from_code("HKD")
  let assert Ok(accounting_fact) =
    hk_fact.new(
      listing: listing,
      document: document,
      line_code: Some("revenue"),
      original_label: "收入",
      value: value,
      reported_unit: "HK$ million",
      scale: scale,
      normalized_unit: Some(market.Currency(hkd)),
      standard: hk_fact.HongKongFinancialReportingStandards,
      statement_scope: fact.Consolidated,
      period: fact.Duration(civil(2024, 1, 1), civil(2024, 12, 31)),
      report_class: hk_fact.Annual,
      audit_state: fact.Audited,
      restatement_state: fact.Original,
    )
  accounting_fact |> hk_fact.common |> fact.original_label |> should.equal("收入")
  accounting_fact
  |> hk_fact.common
  |> fact.value
  |> fact.raw_numeric
  |> should.equal(Some("42.500"))
  accounting_fact
  |> hk_fact.common
  |> fact.normalized_numeric
  |> result.map(decimal.to_string)
  |> should.equal(Ok("42500000"))
}

fn hk_listing() -> identity.Listing {
  let assert Ok(id) = identifier.instrument_id("hk-accounting")
  let assert Ok(hkd) = currency.from_code("HKD")
  let assert Ok(value) =
    identity.new(
      id,
      "00001",
      identity.MainBoard,
      identity.OrdinaryShare,
      hkd,
      instrument.Active,
    )
  value
}

fn report(listing: identity.Listing) -> hk_document.Document {
  let assert Ok(id) = document.document_id("hk-report")
  let assert Ok(value) =
    hk_document.new(
      id: id,
      issuer: listing,
      kind: hk_document.FinancialReport,
      original_title: "年度報告",
      original_text: None,
      language: hk_document.TraditionalChinese,
      published_at: instant(1000),
      period: None,
      source: source_ref(),
      evidence_id: evidence_id(),
    )
  value
}

fn source_ref() -> source.SourceRef {
  let assert Ok(value) =
    source.new("synthetic-hk-accounting", "fixture/hk", source.Synthetic)
  value
}

fn evidence_id() -> provenance_identity.EvidenceId {
  let assert Ok(hash) = provenance_identity.sha256(string.repeat("d", 64))
  provenance_identity.evidence_id(hash)
}

fn instant(value: Int) -> time.Instant {
  let assert Ok(parsed) = time.instant(value)
  parsed
}

fn civil(year: Int, month: Int, day: Int) -> time.Date {
  let assert Ok(value) = time.date(year, month, day)
  value
}

fn exact(value: String) -> decimal.Decimal {
  let assert Ok(parsed) = decimal.parse(value)
  parsed
}
