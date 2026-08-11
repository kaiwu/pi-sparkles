import finance_provenance/hash
import finance_provenance/identity
import finance_research_calculation as calculation
import gleam/json
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

fn request(operation: String, operands: String) -> String {
  "{\"schemaVersion\":1,\"contractId\":\"stock_growth_v1\",\"track\":\"us\",\"requestId\":\"growth-1\",\"subject\":{\"issuerId\":\"CIK1\",\"listingId\":\"US1\",\"mic\":\"XNAS\",\"shareClass\":\"common\"},\"operation\":\""
  <> operation
  <> "\",\"outputUnit\":\"ratio\",\"outputScale\":6,\"rounding\":\"half_even\",\"coherenceKey\":\"FY2025:10-K\",\"operands\":"
  <> operands
  <> ",\"assumptions\":[\"caller selected periods\"]}"
}

fn operand(name: String, value: String) -> String {
  "{\"name\":\""
  <> name
  <> "\",\"exactLexeme\":\""
  <> value
  <> "\",\"marketTrack\":\"us\",\"mic\":\"XNAS\",\"unit\":\"USD\",\"currency\":\"USD\",\"periodStart\":\"2025-01-01\",\"periodEnd\":\"2025-12-31\",\"accession\":\"0001\",\"taxonomy\":\"us-gaap\",\"tag\":\"Revenue\",\"contextKey\":\"FY2025:10-K\",\"sourceReceipt\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"}"
}

pub fn percent_change_is_exact_and_receipt_bound_test() {
  let bytes =
    request(
      "percent_change",
      "["
        <> operand("current", "125.00")
        <> ","
        <> operand("prior", "100.00")
        <> "]",
    )
  let assert Ok(digest) = hash.text(bytes)
  let assert Ok(value) =
    calculation.calculate(
      calculation.Descriptor("stock_growth_v1", "us", ["XNAS"], [
        "percent_change",
      ]),
      calculation.input("growth.json", identity.sha256_value(digest)),
      bytes,
    )
  calculation.summary(value) |> string.contains("0.25") |> should.be_true
  calculation.details(value)
  |> json.to_string
  |> string.contains("canonicalContentHash")
  |> should.be_true
}

pub fn zero_prior_and_cross_context_fail_closed_test() {
  let bytes =
    request(
      "percent_change",
      "[" <> operand("current", "125") <> "," <> operand("prior", "0") <> "]",
    )
  let assert Ok(digest) = hash.text(bytes)
  calculation.calculate(
    calculation.Descriptor("stock_growth_v1", "us", ["XNAS"], ["percent_change"]),
    calculation.input("growth.json", identity.sha256_value(digest)),
    bytes,
  )
  |> should.be_error
}
