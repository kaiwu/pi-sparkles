import finance_provenance/hash
import finance_provenance/identity
import finance_transcript
import gleam/json
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn licensed_exact_search_and_excerpt_test() {
  let bytes = packet("licensed_for_user")
  let assert Ok(digest) = hash.text(bytes)
  let assert Ok(value) =
    finance_transcript.load(identity.sha256_value(digest), bytes)
  let assert Ok(found) =
    finance_transcript.search(value, "guidance", False, 0, 10)
  found |> json.to_string |> string.contains("seg-2") |> should.be_true
  let assert Ok(excerpt) = finance_transcript.excerpt(value, "seg-2", 1)
  excerpt |> json.to_string |> string.contains("seg-1") |> should.be_true
}

pub fn missing_rights_and_wrong_hash_fail_closed_test() {
  let bytes = packet("unknown")
  let assert Ok(digest) = hash.text(bytes)
  finance_transcript.load(identity.sha256_value(digest), bytes)
  |> should.equal(Error(finance_transcript.RightsNotPermitted))
  finance_transcript.load(
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    bytes,
  )
  |> should.equal(Error(finance_transcript.ContentHashMismatch))
}

fn packet(rights: String) -> String {
  let transcript = "Welcome\nWe raised guidance"
  let assert Ok(content_hash) = hash.text(transcript)
  "{\"schemaVersion\":1,\"contractId\":\"earnings_transcript_v1\",\"track\":\"us\",\"subject\":{\"issuerId\":\"CIK1\",\"listingId\":\"US1\",\"mic\":\"XNAS\"},\"event\":{\"eventId\":\"q2-call\",\"fiscalPeriod\":\"2026-Q2\",\"occurredAt\":\"2026-08-01T20:00:00Z\"},\"source\":{\"provider\":\"licensed-vendor\",\"sourceKind\":\"prepared-and-qa\",\"publishedAt\":\"2026-08-01T22:00:00Z\",\"retrievedAt\":\"2026-08-02T00:00:00Z\",\"language\":\"en\",\"rights\":\""
  <> rights
  <> "\",\"sourceUrl\":\"https://vendor/1\",\"correctionOf\":null,\"contentSha256\":\""
  <> identity.sha256_value(content_hash)
  <> "\"},\"segments\":[{\"segmentId\":\"seg-1\",\"ordinal\":0,\"speakerId\":\"operator\",\"speakerName\":\"Operator\",\"speakerRole\":\"operator\",\"speakerState\":\"known\",\"startOffset\":0,\"endOffset\":7,\"text\":\"Welcome\"},{\"segmentId\":\"seg-2\",\"ordinal\":1,\"speakerId\":\"ceo\",\"speakerName\":\"A. CEO\",\"speakerRole\":\"chief_executive\",\"speakerState\":\"known\",\"startOffset\":8,\"endOffset\":26,\"text\":\"We raised guidance\"}],\"omissions\":[]}"
}
