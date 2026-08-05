import finance_core/currency
import finance_core/identifier
import finance_core/instrument
import finance_core/source
import finance_core/time
import finance_hk_documents
import finance_hk_documents/document as hk_document
import finance_hk_identity/identity
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
  finance_hk_documents.status()
  |> should.equal(finance_hk_documents.Experimental)
}

pub fn parallel_language_publications_keep_both_identities_test() {
  let chinese = hk_doc("hk-zh", "全年業績", hk_document.TraditionalChinese, 1000)
  let english = hk_doc("hk-en", "Annual results", hk_document.English, 1000)
  let assert Ok(link) =
    document.relation(
      document.ParallelLanguage,
      hk_document.common(chinese),
      hk_document.common(english),
      evidence_id("e"),
    )
  document.relation_kind(link) |> should.equal(document.ParallelLanguage)
}

fn hk_doc(
  id_value: String,
  title: String,
  language: hk_document.Language,
  published: Int,
) -> hk_document.Document {
  let assert Ok(id) = document.document_id(id_value)
  let assert Ok(value) =
    hk_document.new(
      id: id,
      issuer: listing(),
      kind: hk_document.ResultsAnnouncement,
      original_title: title,
      original_text: Some(title <> "正文"),
      language: language,
      published_at: instant(published),
      period: None,
      source: source_ref(),
      evidence_id: evidence_id(id_value),
    )
  value
}

fn listing() -> identity.Listing {
  let assert Ok(id) = identifier.instrument_id("hk-doc-listing")
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

fn source_ref() -> source.SourceRef {
  let assert Ok(value) =
    source.new("synthetic-hk-docs", "fixture/hk", source.Synthetic)
  value
}

fn evidence_id(seed: String) -> provenance_identity.EvidenceId {
  let _ = seed
  let assert Ok(hash) = provenance_identity.sha256(string.repeat("e", 64))
  provenance_identity.evidence_id(hash)
}

fn instant(value: Int) -> time.Instant {
  let assert Ok(parsed) = time.instant(value)
  parsed
}
