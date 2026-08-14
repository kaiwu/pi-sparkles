import finance_broker_review
import finance_local_import
import finance_provenance/hash
import finance_provenance/identity
import gleam/json
import gleam/string
import gleeunit
import gleeunit/should
import pi_sparkles_broker_live/import_contract

const hash_a = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

const hash_b = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

pub fn main() {
  gleeunit.main()
}

pub fn exact_content_bound_receipt_import_returns_only_normalized_review_test() {
  let text =
    fixture(
      import_contract.contract_version,
      "external_execution_receipt_import",
    )
  let expected = text_hash(text)
  let outcome =
    import_contract.decode_loaded(text, string.byte_size(text), expected)
  let assert import_contract.Imported(review) = outcome
  let details = finance_broker_review.details(review) |> json.to_string

  details
  |> string.contains("\"sourceContentHashVerifiedAgainstBytes\":true")
  |> should.be_true
  details |> string.contains("\"networkPerformed\":false") |> should.be_true
  details |> string.contains(text) |> should.be_false
}

pub fn mismatched_hash_and_byte_count_fail_before_decoding_test() {
  let text =
    fixture(
      import_contract.contract_version,
      "external_execution_receipt_import",
    )
  import_contract.decode_loaded(text, string.byte_size(text), hash_a)
  |> should.equal(import_contract.ContentHashMismatch)
  import_contract.decode_loaded(
    text,
    string.byte_size(text) + 1,
    text_hash(text),
  )
  |> should.equal(import_contract.ByteCountMismatch)
  import_contract.decode_loaded(text, string.byte_size(text), "invalid")
  |> should.equal(import_contract.InvalidExpectedHash)
}

pub fn contract_version_and_mode_are_exact_test() {
  let wrong_version =
    fixture("future_contract", "external_execution_receipt_import")
  import_contract.decode_loaded(
    wrong_version,
    string.byte_size(wrong_version),
    text_hash(wrong_version),
  )
  |> should.equal(import_contract.UnsupportedContractVersion("future_contract"))

  let handoff =
    fixture(import_contract.contract_version, "non_executable_handoff")
  import_contract.decode_loaded(
    handoff,
    string.byte_size(handoff),
    text_hash(handoff),
  )
  |> should.equal(import_contract.UnsupportedImportMode(
    "non_executable_handoff",
  ))
}

pub fn read_failures_never_become_empty_successes_test() {
  import_contract.from_read_outcome(
    finance_local_import.Truncated(100, 200),
    hash_a,
  )
  |> should.equal(import_contract.Truncated(100, 200))
  import_contract.from_read_outcome(finance_local_import.Cancelled, hash_a)
  |> should.equal(import_contract.Cancelled)
  import_contract.from_read_outcome(finance_local_import.InvalidUtf8, hash_a)
  |> should.equal(import_contract.InvalidUtf8)
  import_contract.from_read_outcome(
    finance_local_import.Failure("symbolic_link_not_supported"),
    hash_a,
  )
  |> should.equal(import_contract.ReadFailure("symbolic_link_not_supported"))
}

fn fixture(version: String, mode: String) -> String {
  "{\"contractVersion\":\""
  <> version
  <> "\",\"operationId\":\"local-import\",\"mode\":\""
  <> mode
  <> "\",\"environment\":\"external_live\",\"accountReference\":\""
  <> hash_a
  <> "\",\"track\":\"hk\",\"listingId\":\"HK.00700\",\"mic\":\"XHKG\",\"facts\":[{\"name\":\"cash_available\",\"state\":\"known\",\"value\":\"1000\",\"unit\":\"HKD\",\"sourceReference\":\""
  <> hash_b
  <> "\"}],\"events\":[],\"missingCapabilities\":[]}"
}

fn text_hash(value: String) -> String {
  let assert Ok(value) = hash.text(value)
  identity.sha256_value(value)
}
