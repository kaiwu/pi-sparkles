import finance_cn_documents/document as cn_document
import finance_cn_identity/identity
import finance_core/market.{type Unit}
import finance_market_accounting/fact as market_fact
import finance_market_documents/document as market_document
import gleam/option.{type Option}

pub type Standard {
  ChineseAccountingStandards
  InternationalFinancialReportingStandards
  OtherStandard(String)
}

pub type ReportClass {
  FirstQuarter
  SemiAnnual
  ThirdQuarter
  Annual
  Preliminary
  Forecast
  OtherReportClass(String)
}

pub opaque type Fact {
  Fact(standard: Standard, report_class: ReportClass, value: market_fact.Fact)
}

pub type FactError {
  DocumentIssuerMismatch
  InvalidFact(market_fact.FactError)
}

pub fn new(
  listing listing_value: identity.Listing,
  document document_value: cn_document.Document,
  line_code line_code_value: Option(String),
  original_label label: String,
  value reported_value: market_fact.ReportedValue,
  reported_unit reported_unit_value: String,
  scale scale_value: market_fact.Scale,
  normalized_unit normalized_unit_value: Option(Unit),
  standard standard_value: Standard,
  statement_scope scope: market_fact.StatementScope,
  period period_value: market_fact.Period,
  report_class report_class_value: ReportClass,
  audit_state audit: market_fact.AuditState,
  restatement_state restatement: market_fact.RestatementState,
) -> Result(Fact, FactError) {
  let source_document = cn_document.common(document_value)
  case market_document.issuer(source_document) == identity.key(listing_value) {
    False -> Error(DocumentIssuerMismatch)
    True ->
      case
        market_fact.new(
          listing: identity.key(listing_value),
          document_id: market_document.id(source_document),
          line_code: line_code_value,
          original_label: label,
          value: reported_value,
          reported_unit: reported_unit_value,
          scale: scale_value,
          normalized_unit: normalized_unit_value,
          accounting_standard: standard_name(standard_value),
          statement_scope: scope,
          period: period_value,
          report_class: report_class_name(report_class_value),
          audit_state: audit,
          restatement_state: restatement,
          evidence_id: market_document.evidence_id(source_document),
        )
      {
        Ok(value) -> Ok(Fact(standard_value, report_class_value, value))
        Error(error) -> Error(InvalidFact(error))
      }
  }
}

pub fn standard(value: Fact) -> Standard {
  value.standard
}

pub fn report_class(value: Fact) -> ReportClass {
  value.report_class
}

pub fn common(value: Fact) -> market_fact.Fact {
  value.value
}

pub fn standard_name(value: Standard) -> String {
  case value {
    ChineseAccountingStandards -> "chinese_accounting_standards"
    InternationalFinancialReportingStandards -> "ifrs"
    OtherStandard(name) -> name
  }
}

pub fn report_class_name(value: ReportClass) -> String {
  case value {
    FirstQuarter -> "first_quarter"
    SemiAnnual -> "semi_annual"
    ThirdQuarter -> "third_quarter"
    Annual -> "annual"
    Preliminary -> "preliminary"
    Forecast -> "forecast"
    OtherReportClass(name) -> name
  }
}
