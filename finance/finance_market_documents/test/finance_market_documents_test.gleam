import finance_core/identifier
import finance_core/source
import finance_core/time
import finance_listing/listing
import finance_market_documents
import finance_market_documents/document
import finance_market_documents/json as document_json
import finance_provenance/identity
import finance_track
import gleam/option.{None, Some}
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn package_is_experimental_test() {
  finance_market_documents.status()
  |> should.equal(finance_market_documents.Experimental)
}

pub fn unicode_originals_and_correction_lineage_are_preserved_test() {
  let original = market_document("公告-原始", "年度报告", "原始中文内容", 1000)
  let corrected = market_document("公告-更正", "年度报告（更正）", "更正后的中文内容", 2000)
  document.original_title(original) |> should.equal("年度报告")
  document.original_text(original) |> should.equal(Some("原始中文内容"))

  let assert Ok(link) =
    document.relation(
      document.Correction,
      original,
      corrected,
      evidence_id("3"),
    )
  document.relation_earlier(link)
  |> document.document_id_value
  |> should.equal("公告-原始")
  document.relation_later(link)
  |> document.document_id_value
  |> should.equal("公告-更正")
}

pub fn track_and_translation_mismatches_fail_closed_test() {
  let cn = market_document("cn", "中文", "内容", 1000)
  let same_language = market_document("cn-2", "更正", "内容", 2000)
  document.relation(document.Translation, cn, same_language, evidence_id("4"))
  |> should.equal(Error(document.LanguageMustDiffer))

  let assert Ok(id) = document.document_id("bad-track")
  document.new(
    id: id,
    track: finance_track.Hk,
    issuer: listing_key(),
    kind: "announcement",
    original_title: "錯誤軌道",
    original_text: None,
    language: "zh-HK",
    published_at: instant(1000),
    period: None,
    source: source_ref(),
    evidence_id: evidence_id("5"),
  )
  |> should.equal(Error(document.TrackMismatch))
}

pub fn versioned_wire_round_trip_preserves_cn_unicode_and_identity_test() {
  let original = market_document("公告-2024-年度", "2024年年度报告（更正）", "收入：一百万元", 2000)
  let encoded = document_json.encode(original)
  let assert Ok(decoded) = document_json.decode(encoded)

  decoded |> should.equal(original)
  document.original_title(decoded) |> should.equal("2024年年度报告（更正）")
  decoded
  |> document.issuer
  |> listing.track
  |> should.equal(finance_track.Cn)
}

pub fn unknown_document_wire_version_fails_closed_test() {
  document_json.decode("{\"schemaVersion\":2}")
  |> should.be_error
}

fn market_document(
  id_value: String,
  title: String,
  text: String,
  published: Int,
) -> document.Document {
  let assert Ok(id) = document.document_id(id_value)
  let assert Ok(value) =
    document.new(
      id: id,
      track: finance_track.Cn,
      issuer: listing_key(),
      kind: "periodic_report",
      original_title: title,
      original_text: Some(text),
      language: "zh-CN",
      published_at: instant(published),
      period: None,
      source: source_ref(),
      evidence_id: evidence_id(id_value),
    )
  value
}

fn listing_key() -> listing.Key {
  let assert Ok(instrument) = identifier.instrument_id("cn-document-issuer")
  let assert Ok(symbol) = identifier.symbol("000001")
  let assert Ok(mic) = identifier.mic("XSHG")
  listing.new(finance_track.Cn, instrument, symbol, mic)
}

fn source_ref() -> source.SourceRef {
  let assert Ok(value) =
    source.new("synthetic-documents", "fixture/document", source.Synthetic)
  value
}

fn evidence_id(seed: String) -> identity.EvidenceId {
  let _ = seed
  let assert Ok(hash) = identity.sha256(string.repeat("a", 64))
  identity.evidence_id(hash)
}

fn instant(value: Int) -> time.Instant {
  let assert Ok(parsed) = time.instant(value)
  parsed
}
