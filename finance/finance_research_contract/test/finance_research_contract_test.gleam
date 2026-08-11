import finance_provenance/hash
import finance_provenance/identity
import finance_research_contract as contract
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

fn descriptor() -> contract.Descriptor {
  contract.Descriptor(
    "sec_insiders_v1",
    "us",
    ["XNYS", "XNAS"],
    ["form4_transaction", "form4_amendment"],
    ["accession", "quantity"],
  )
}

fn packet() -> String {
  "{\"schemaVersion\":1,\"contractId\":\"sec_insiders_v1\",\"track\":\"us\",\"subject\":{\"issuerId\":\"CIK0000320193\",\"listingId\":\"US0378331005\",\"mic\":\"XNAS\",\"shareClass\":\"common\"},\"source\":{\"provider\":\"SEC EDGAR\",\"authorityRole\":\"official_filing_repository\",\"documentId\":\"0001\",\"publishedAt\":\"2026-08-01T00:00:00Z\",\"retrievedAt\":\"2026-08-11T00:00:00Z\",\"language\":\"en\",\"rights\":\"public_filing\",\"sourceUrl\":\"https://www.sec.gov/Archives/0001\"},\"records\":[{\"recordId\":\"tx-1\",\"kind\":\"form4_transaction\",\"effectiveAt\":\"2026-07-31\",\"publishedAt\":\"2026-08-01T00:00:00Z\",\"correctionOf\":null,\"fields\":[{\"name\":\"accession\",\"state\":\"known\",\"valueLexeme\":\"0001\",\"unit\":null,\"sourceSpan\":\"header\"},{\"name\":\"quantity\",\"state\":\"known\",\"valueLexeme\":\"1000.0000\",\"unit\":\"shares\",\"sourceSpan\":\"transactionAmounts\"}]}],\"omissions\":[\"footnote interpretation not performed\"]}"
}

pub fn exact_packet_inspects_and_drills_test() {
  let bytes = packet()
  let assert Ok(digest) = hash.text(bytes)
  let digest = identity.sha256_value(digest)
  let assert Ok(page) =
    contract.inspect(
      descriptor(),
      contract.input("fixture.json", digest, 0, 10),
      bytes,
    )
  contract.summary(page)
  |> string.contains("1 exact record")
  |> should.be_true
  let assert Ok(drill) =
    contract.drill(
      descriptor(),
      contract.drill_input("fixture.json", digest, "tx-1"),
      bytes,
    )
  contract.summary(drill) |> string.contains("tx-1") |> should.be_true
}

pub fn wrong_track_and_hash_fail_closed_test() {
  let bytes = packet()
  contract.inspect(
    contract.Descriptor(
      "sec_insiders_v1",
      "cn",
      ["XNAS"],
      ["form4_transaction"],
      ["accession", "quantity"],
    ),
    contract.input(
      "fixture.json",
      "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      0,
      10,
    ),
    bytes,
  )
  |> should.be_error
}
