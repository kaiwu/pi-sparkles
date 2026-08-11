import finance_provenance/hash
import finance_provenance/identity
import finance_research_diff as diff
import gleam/json
import gleam/option.{None}
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn exact_section_change_and_hash_test() {
  let left_text = "Revenue  100"
  let right_text = "Revenue 120"
  let assert Ok(left_hash) = hash.text(left_text)
  let assert Ok(right_hash) = hash.text(right_text)
  let packet =
    packet(identity.sha256_value(left_hash), identity.sha256_value(right_hash))
  let assert Ok(packet_hash) = hash.text(packet)
  let assert Ok(value) =
    diff.compare(descriptor(), identity.sha256_value(packet_hash), packet)
  diff.summary(value)
  |> string.contains("1 exact section change")
  |> should.be_true
  let assert Ok(details) = diff.drill_change(value, "replace:income")
  details |> json.to_string |> string.contains("Revenue 120") |> should.be_true
}

pub fn wrong_document_hash_fails_closed_test() {
  let packet =
    packet(
      "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    )
  let assert Ok(packet_hash) = hash.text(packet)
  diff.compare(descriptor(), identity.sha256_value(packet_hash), packet)
  |> should.equal(Error(diff.InvalidDocumentHash("left")))
}

fn descriptor() -> diff.Descriptor {
  diff.Descriptor("filing_diff_v1", "us", ["XNAS"], ["10-K", "10-K/A"], None)
}

fn packet(left_hash: String, right_hash: String) -> String {
  "{\"schemaVersion\":1,\"contractId\":\"filing_diff_v1\",\"track\":\"us\",\"subject\":{\"issuerId\":\"CIK0000320193\",\"listingId\":\"US0378331005\",\"mic\":\"XNAS\"},\"view\":\"raw\",\"algorithmVersion\":\"exact_section_v1\",\"left\":{\"documentId\":\"doc-1\",\"form\":\"10-K\",\"accessionOrEventId\":\"0001\",\"publishedAt\":\"2025-01-01T00:00:00Z\",\"effectiveDate\":\"2024-12-31\",\"correctionOf\":null,\"language\":\"en\",\"sourceUrl\":\"https://sec.gov/1\",\"rights\":\"public_filing\",\"contentSha256\":\""
  <> left_hash
  <> "\",\"sections\":[{\"sectionId\":\"income\",\"kind\":\"section\",\"title\":\"Income\",\"ordinal\":0,\"startOffset\":0,\"endOffset\":12,\"rawText\":\"Revenue  100\"}],\"omissions\":[]},\"right\":{\"documentId\":\"doc-2\",\"form\":\"10-K/A\",\"accessionOrEventId\":\"0002\",\"publishedAt\":\"2025-01-02T00:00:00Z\",\"effectiveDate\":\"2024-12-31\",\"correctionOf\":\"doc-1\",\"language\":\"en\",\"sourceUrl\":\"https://sec.gov/2\",\"rights\":\"public_filing\",\"contentSha256\":\""
  <> right_hash
  <> "\",\"sections\":[{\"sectionId\":\"income\",\"kind\":\"section\",\"title\":\"Income\",\"ordinal\":0,\"startOffset\":0,\"endOffset\":11,\"rawText\":\"Revenue 120\"}],\"omissions\":[]}}"
}
