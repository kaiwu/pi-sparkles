import finance_peer_set
import finance_provenance/hash
import finance_provenance/identity
import gleam/json
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn accepted_rejected_unresolved_are_mechanical_and_preserved_test() {
  let bytes = packet()
  let assert Ok(digest) = hash.text(bytes)
  let assert Ok(value) =
    finance_peer_set.project(identity.sha256_value(digest), bytes)
  let assert Ok(page) = finance_peer_set.inspect(value, 0, 10)
  let text = json.to_string(page)
  text |> string.contains("\"acceptedCount\":1") |> should.be_true
  text |> string.contains("\"rejectedCount\":1") |> should.be_true
  text |> string.contains("\"unresolvedCount\":1") |> should.be_true
}

pub fn missing_predicate_fails_closed_test() {
  let bytes =
    string.replace(
      packet(),
      "{\"predicateId\":\"currency\",\"state\":\"unknown\",\"observedValue\":null,\"sourceReceipt\":\"sha:3\"}",
      "",
    )
  let assert Ok(digest) = hash.text(bytes)
  finance_peer_set.project(identity.sha256_value(digest), bytes)
  |> should.be_error
}

fn packet() -> String {
  "{\"schemaVersion\":1,\"contractId\":\"stock_peers_v1\",\"track\":\"us\",\"target\":{\"issuerId\":\"CIK1\",\"listingId\":\"US1\",\"mic\":\"XNAS\",\"shareClass\":\"common\"},\"evidenceDate\":\"2026-08-01\",\"predicates\":[{\"predicateId\":\"industry\",\"label\":\"Same industry\",\"rule\":\"exact caller classification overlap\"},{\"predicateId\":\"currency\",\"label\":\"Same reporting currency\",\"rule\":\"exact ISO currency equality\"}],\"candidates\":[{\"candidateId\":\"a\",\"subject\":{\"issuerId\":\"CIK2\",\"listingId\":\"US2\",\"mic\":\"XNYS\",\"shareClass\":\"common\"},\"classifications\":[\"software\"],\"currency\":\"USD\",\"fiscalPeriod\":\"2025-FY\",\"facts\":[{\"predicateId\":\"industry\",\"state\":\"observed_true\",\"observedValue\":\"software\",\"sourceReceipt\":\"sha:1\"},{\"predicateId\":\"currency\",\"state\":\"observed_true\",\"observedValue\":\"USD\",\"sourceReceipt\":\"sha:2\"}]},{\"candidateId\":\"b\",\"subject\":{\"issuerId\":\"CIK3\",\"listingId\":\"US3\",\"mic\":\"XNAS\",\"shareClass\":\"common\"},\"classifications\":[\"hardware\"],\"currency\":\"USD\",\"fiscalPeriod\":\"2025-FY\",\"facts\":[{\"predicateId\":\"industry\",\"state\":\"observed_false\",\"observedValue\":\"hardware\",\"sourceReceipt\":\"sha:1\"},{\"predicateId\":\"currency\",\"state\":\"observed_true\",\"observedValue\":\"USD\",\"sourceReceipt\":\"sha:2\"}]},{\"candidateId\":\"c\",\"subject\":{\"issuerId\":\"CIK4\",\"listingId\":\"US4\",\"mic\":\"XNAS\",\"shareClass\":\"common\"},\"classifications\":[],\"currency\":\"USD\",\"fiscalPeriod\":\"2025-FY\",\"facts\":[{\"predicateId\":\"industry\",\"state\":\"unknown\",\"observedValue\":null,\"sourceReceipt\":\"sha:1\"},{\"predicateId\":\"currency\",\"state\":\"unknown\",\"observedValue\":null,\"sourceReceipt\":\"sha:3\"}]}],\"omissions\":[\"segment data not supplied\"]}"
}
