import finance_provenance/hash
import finance_provenance/identity
import finance_text_analysis/rumor
import finance_text_analysis/sentiment
import gleam/json
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn lexicon_exposes_exact_positive_and_negative_spans_test() {
  let text = "growth risk"
  let assert Ok(text_hash) = hash.text(text)
  let bytes =
    "{\"schemaVersion\":1,\"contractId\":\"finance_sentiment_v1\",\"model\":\"finance_lexicon_v1\",\"aggregationPolicy\":\"sum\",\"documents\":[{\"documentId\":\"d1\",\"sourceIdentity\":\"issuer-release\",\"language\":\"en\",\"rights\":\"public_record\",\"publishedAt\":\"2026-08-01\",\"retrievedAt\":\"2026-08-02\",\"text\":\"growth risk\",\"textSha256\":\""
    <> identity.sha256_value(text_hash)
    <> "\",\"tokens\":[{\"text\":\"growth\",\"startOffset\":0,\"endOffset\":6},{\"text\":\"risk\",\"startOffset\":7,\"endOffset\":11}]}]}"
  let assert Ok(packet_hash) = hash.text(bytes)
  let assert Ok(value) =
    sentiment.analyze(identity.sha256_value(packet_hash), bytes)
  let output = sentiment.details(value) |> json.to_string
  output |> string.contains("\"positive\":1") |> should.be_true
  output |> string.contains("\"negative\":-1") |> should.be_true
}

pub fn claim_sources_classify_independently_without_truth_verdict_test() {
  let bytes = rumor_packet()
  let assert Ok(digest) = hash.text(bytes)
  let assert Ok(value) = rumor.check(identity.sha256_value(digest), bytes)
  let output = rumor.details(value) |> json.to_string
  output |> string.contains("\"relation\":\"supports\"") |> should.be_true
  output |> string.contains("\"relation\":\"contradicts\"") |> should.be_true
  output |> string.contains("\"aggregateVerdict\":null") |> should.be_true
}

fn rumor_packet() -> String {
  "{\"schemaVersion\":1,\"contractId\":\"finance_rumor_check_v1\",\"claim\":{\"claimId\":\"c1\",\"text\":\"Issuer raised guidance\",\"entities\":[\"issuer-1\"],\"predicate\":\"guidance_direction\",\"valueLexeme\":\"raised\",\"unit\":null,\"effectiveDate\":\"2026-Q3\",\"jurisdiction\":\"US\",\"claimant\":\"poster-1\",\"claimantSource\":\"social-post-1\",\"extractionConfidence\":\"caller_supplied:0.8\"},\"searchScope\":[\"issuer releases through cutoff\",\"SEC filings through cutoff\"],\"cutoff\":\"2026-08-02T00:00:00Z\",\"omissions\":[],\"evidence\":[{\"evidenceId\":\"e1\",\"sourceIdentity\":\"issuer-release\",\"authorityRole\":\"issuer_statement\",\"publishedAt\":\"2026-08-01\",\"retrievedAt\":\"2026-08-02\",\"accessState\":\"accessible\",\"independenceId\":\"issuer\",\"circularSources\":[],\"sourceUrl\":\"https://issuer/1\",\"passages\":[{\"passageId\":\"p1\",\"text\":\"Guidance raised\",\"startOffset\":0,\"endOffset\":15}],\"assertions\":[{\"predicate\":\"guidance_direction\",\"valueLexeme\":\"raised\",\"unit\":null,\"negated\":false,\"exclusive\":true,\"passageId\":\"p1\"}]},{\"evidenceId\":\"e2\",\"sourceIdentity\":\"filing\",\"authorityRole\":\"official_repository\",\"publishedAt\":\"2026-08-01\",\"retrievedAt\":\"2026-08-02\",\"accessState\":\"accessible\",\"independenceId\":\"issuer\",\"circularSources\":[\"issuer-release\"],\"sourceUrl\":\"https://sec/1\",\"passages\":[{\"passageId\":\"p2\",\"text\":\"Guidance unchanged\",\"startOffset\":0,\"endOffset\":18}],\"assertions\":[{\"predicate\":\"guidance_direction\",\"valueLexeme\":\"unchanged\",\"unit\":null,\"negated\":false,\"exclusive\":true,\"passageId\":\"p2\"}]}]}"
}
