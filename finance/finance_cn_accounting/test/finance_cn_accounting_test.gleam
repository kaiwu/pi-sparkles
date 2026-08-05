import finance_cn_accounting
import finance_cn_accounting/fact as cn_fact
import finance_cn_documents/document as cn_document
import finance_cn_identity/identity
import finance_core/currency
import finance_core/decimal
import finance_core/identifier
import finance_core/instrument
import finance_core/market
import finance_core/source
import finance_core/time
import finance_market_accounting/fact
import finance_market_documents/document
import finance_provenance/identity as provenance_identity
import gleam/option.{None, Some}
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn package_is_experimental_test() {
  finance_cn_accounting.status()
  |> should.equal(finance_cn_accounting.Experimental)
}

pub fn cn_fact_retains_chinese_scale_scope_audit_and_exact_lexeme_test() {
  let listing = mainland_listing("cn-accounting")
  let document = report(listing, "cn-report")
  let assert Ok(value) = fact.numeric("12345678901234567890.00")
  let assert Ok(scale) = fact.scale("万股", exact("10000"))
  let assert Ok(result) =
    cn_fact.new(
      listing: listing,
      document: document,
      line_code: Some("shares"),
      original_label: "期末普通股股份总数",
      value: value,
      reported_unit: "万股",
      scale: scale,
      normalized_unit: Some(market.Shares),
      standard: cn_fact.ChineseAccountingStandards,
      statement_scope: fact.ParentCompany,
      period: fact.Instant(civil(2024, 12, 31)),
      report_class: cn_fact.Annual,
      audit_state: fact.Audited,
      restatement_state: fact.Restated,
    )
  result
  |> cn_fact.common
  |> fact.value
  |> fact.raw_numeric
  |> should.equal(Some("12345678901234567890.00"))
  result
  |> cn_fact.common
  |> fact.reported_scale
  |> fact.scale_label
  |> should.equal("万股")
  result
  |> cn_fact.common
  |> fact.statement_scope
  |> should.equal(fact.ParentCompany)
}

pub fn accounting_fact_cannot_cross_issuer_test() {
  let first = mainland_listing("cn-first")
  let second = mainland_listing("cn-second")
  let document = report(first, "cn-report")
  let assert Ok(value) = fact.numeric("1")
  let assert Ok(scale) = fact.scale("元", exact("1"))
  let assert Ok(cny) = currency.from_code("CNY")
  cn_fact.new(
    listing: second,
    document: document,
    line_code: Some("revenue"),
    original_label: "营业收入",
    value: value,
    reported_unit: "元",
    scale: scale,
    normalized_unit: Some(market.Currency(cny)),
    standard: cn_fact.ChineseAccountingStandards,
    statement_scope: fact.Consolidated,
    period: fact.Duration(civil(2024, 1, 1), civil(2024, 12, 31)),
    report_class: cn_fact.Annual,
    audit_state: fact.Audited,
    restatement_state: fact.Original,
  )
  |> should.equal(Error(cn_fact.DocumentIssuerMismatch))
}

fn mainland_listing(id_value: String) -> identity.Listing {
  let assert Ok(id) = identifier.instrument_id(id_value)
  let assert Ok(cny) = currency.from_code("CNY")
  let assert Ok(value) =
    identity.new(
      id,
      "600000",
      identity.Sse,
      identity.SseMainBoard,
      identity.AShare,
      cny,
      instrument.Active,
    )
  value
}

fn report(listing: identity.Listing, id_value: String) -> cn_document.Document {
  let assert Ok(id) = document.document_id(id_value)
  let assert Ok(value) =
    cn_document.new(
      id: id,
      issuer: listing,
      kind: cn_document.PeriodicReport,
      original_title: "年度报告",
      original_text: None,
      language: cn_document.SimplifiedChinese,
      published_at: instant(1000),
      period: None,
      source: source_ref(),
      evidence_id: evidence_id(),
    )
  value
}

fn source_ref() -> source.SourceRef {
  let assert Ok(value) =
    source.new("synthetic-cn-accounting", "fixture/cn", source.Synthetic)
  value
}

fn evidence_id() -> provenance_identity.EvidenceId {
  let assert Ok(hash) = provenance_identity.sha256(string.repeat("c", 64))
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
