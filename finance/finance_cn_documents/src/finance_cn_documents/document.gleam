import finance_cn_identity/identity
import finance_core/source.{type SourceRef}
import finance_core/time.{type Instant}
import finance_market_documents/document as market_document
import finance_provenance/identity as provenance_identity
import finance_track
import gleam/option.{type Option}
import gleam/result

pub type Kind {
  PeriodicReport
  PerformanceForecast
  PreliminaryResults
  AdHocAnnouncement
  ExchangeInquiry
  RegulatoryDocument
}

pub type Language {
  SimplifiedChinese
  TraditionalChinese
  English
  OtherLanguage(String)
}

pub opaque type Document {
  Document(kind: Kind, language: Language, value: market_document.Document)
}

pub fn new(
  id id_value: market_document.DocumentId,
  issuer issuer_listing: identity.Listing,
  kind kind_value: Kind,
  original_title title: String,
  original_text text: Option(String),
  language language_value: Language,
  published_at published: Instant,
  period report_period: Option(market_document.Period),
  source source_ref: SourceRef,
  evidence_id evidence: provenance_identity.EvidenceId,
) -> Result(Document, market_document.DocumentError) {
  market_document.new(
    id: id_value,
    track: finance_track.Cn,
    issuer: identity.key(issuer_listing),
    kind: kind_name(kind_value),
    original_title: title,
    original_text: text,
    language: language_name(language_value),
    published_at: published,
    period: report_period,
    source: source_ref,
    evidence_id: evidence,
  )
  |> result.map(fn(value) { Document(kind_value, language_value, value) })
}

pub fn kind(value: Document) -> Kind {
  value.kind
}

pub fn language(value: Document) -> Language {
  value.language
}

pub fn common(value: Document) -> market_document.Document {
  value.value
}

pub fn kind_name(value: Kind) -> String {
  case value {
    PeriodicReport -> "periodic_report"
    PerformanceForecast -> "performance_forecast"
    PreliminaryResults -> "preliminary_results"
    AdHocAnnouncement -> "ad_hoc_announcement"
    ExchangeInquiry -> "exchange_inquiry"
    RegulatoryDocument -> "regulatory_document"
  }
}

pub fn language_name(value: Language) -> String {
  case value {
    SimplifiedChinese -> "zh-CN"
    TraditionalChinese -> "zh-Hant"
    English -> "en"
    OtherLanguage(name) -> name
  }
}
