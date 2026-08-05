import finance_cn_documents
import finance_cn_documents/document as cn_document
import finance_cn_identity/identity
import finance_core/currency
import finance_core/identifier
import finance_core/instrument
import finance_core/source
import finance_core/time
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
  finance_cn_documents.status()
  |> should.equal(finance_cn_documents.Experimental)
}

pub fn chinese_original_is_controlling_and_translation_is_a_distinct_document_test() {
  let original = cn_doc("cn-original", "年度报告", cn_document.SimplifiedChinese)
  let translated =
    cn_doc("cn-translation", "Annual report", cn_document.English)
  original
  |> cn_document.common
  |> document.original_title
  |> should.equal("年度报告")

  let assert Ok(link) =
    document.relation(
      document.Translation,
      cn_document.common(original),
      cn_document.common(translated),
      evidence_id("c"),
    )
  document.relation_kind(link) |> should.equal(document.Translation)
}

fn cn_doc(
  id_value: String,
  title: String,
  language: cn_document.Language,
) -> cn_document.Document {
  let assert Ok(id) = document.document_id(id_value)
  let assert Ok(value) =
    cn_document.new(
      id: id,
      issuer: listing(),
      kind: cn_document.PeriodicReport,
      original_title: title,
      original_text: Some(title <> "正文"),
      language: language,
      published_at: instant(case language {
        cn_document.English -> 2000
        _ -> 1000
      }),
      period: None,
      source: source_ref(),
      evidence_id: evidence_id(id_value),
    )
  value
}

fn listing() -> identity.Listing {
  let assert Ok(id) = identifier.instrument_id("cn-doc-listing")
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

fn source_ref() -> source.SourceRef {
  let assert Ok(value) =
    source.new("synthetic-cn-docs", "fixture/cn", source.Synthetic)
  value
}

fn evidence_id(seed: String) -> provenance_identity.EvidenceId {
  let character = string.first(seed) |> result.unwrap("c")
  let assert Ok(hash) = provenance_identity.sha256(string.repeat(character, 64))
  provenance_identity.evidence_id(hash)
}

fn instant(value: Int) -> time.Instant {
  let assert Ok(parsed) = time.instant(value)
  parsed
}
