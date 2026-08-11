import finance_provenance/hash
import finance_provenance/identity
import gleam/json
import gleam/string
import gleeunit
import gleeunit/should
import pi_sparkles_cn_stock_research_report/report

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn chinese_original_and_labelled_translation_compose_test() {
  let bytes = packet()
  let assert Ok(digest) = hash.text(bytes)
  let assert Ok(value) = report.compose(identity.sha256_value(digest), bytes)
  let assert Ok(details) = report.inspect(value, 0, 20)
  let text = json.to_string(details)
  text |> string.contains("\"originalChineseSectionCount\":1") |> should.be_true
  text |> string.contains("\"translationSectionCount\":1") |> should.be_true
}

pub fn unlabelled_non_chinese_section_fails_closed_test() {
  let bytes =
    string.replace(
      packet(),
      "\"translation\":{\"originalSectionId\":\"financials-zh\",\"translator\":\"model-x\",\"translatedAt\":\"2026-08-02T00:00:00Z\",\"sourceSpan\":\"0:20\"}",
      "\"translation\":null",
    )
  let assert Ok(digest) = hash.text(bytes)
  report.compose(identity.sha256_value(digest), bytes)
  |> should.equal(Error(report.InvalidTranslation))
}

fn packet() -> String {
  let sha = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  "{\"schemaVersion\":1,\"contractId\":\"cn_stock_research_report_v1\",\"track\":\"cn\",\"subject\":{\"issuerId\":\"91310000\",\"listingId\":\"600000\",\"mic\":\"XSHG\",\"shareClass\":\"A\"},\"asOfDate\":\"2026-08-01\",\"sections\":[{\"sectionId\":\"financials-zh\",\"kind\":\"financials\",\"language\":\"zh-CN\",\"receiptId\":\"receipt-1\",\"sourceRole\":\"issuer_filing\",\"contentSha256\":\""
  <> sha
  <> "\",\"translation\":null,\"facts\":[{\"name\":\"营业收入\",\"state\":\"known\",\"valueLexeme\":\"1000000.00\",\"unit\":\"CNY\",\"sourceHandle\":\"receipt-1#income\"}],\"conflicts\":[],\"omissions\":[]},{\"sectionId\":\"financials-en\",\"kind\":\"financials\",\"language\":\"en\",\"receiptId\":\"receipt-2\",\"sourceRole\":\"labelled_translation\",\"contentSha256\":\""
  <> sha
  <> "\",\"translation\":{\"originalSectionId\":\"financials-zh\",\"translator\":\"model-x\",\"translatedAt\":\"2026-08-02T00:00:00Z\",\"sourceSpan\":\"0:20\"},\"facts\":[{\"name\":\"Revenue\",\"state\":\"known\",\"valueLexeme\":\"1000000.00\",\"unit\":\"CNY\",\"sourceHandle\":\"receipt-1#income\"}],\"conflicts\":[],\"omissions\":[]}],\"omissions\":[\"valuation not supplied\"]}"
}
