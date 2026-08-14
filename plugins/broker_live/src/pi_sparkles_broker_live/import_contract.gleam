import finance_broker_review.{type Review}
import finance_broker_review/decode
import finance_local_import
import finance_provenance/hash
import finance_provenance/identity
import gleam/json
import gleam/string
import pi_sparkles_broker_live/domain

pub const contract_version = "broker_local_execution_import_v1"

pub type LocalImportOutcome {
  Imported(review: Review)
  Truncated(retained_bytes: Int, total_bytes: Int)
  Cancelled
  Missing
  InvalidUtf8
  ReadFailure(code: String)
  InvalidReadResult
  InvalidExpectedHash
  ContentHashMismatch
  ByteCountMismatch
  InvalidJson
  UnsupportedContractVersion(received: String)
  UnsupportedImportMode(received: String)
  ReviewRejected(message: String)
}

pub fn from_read_outcome(
  outcome: finance_local_import.Outcome,
  expected_content_hash: String,
) -> LocalImportOutcome {
  case outcome {
    finance_local_import.Loaded(text, byte_count) ->
      decode_loaded(text, byte_count, expected_content_hash)
    finance_local_import.Truncated(retained, total) ->
      Truncated(retained, total)
    finance_local_import.Cancelled -> Cancelled
    finance_local_import.Missing -> Missing
    finance_local_import.InvalidUtf8 -> InvalidUtf8
    finance_local_import.Failure(code) -> ReadFailure(code)
    finance_local_import.InvalidResult -> InvalidReadResult
  }
}

pub fn decode_loaded(
  text: String,
  byte_count: Int,
  expected_content_hash: String,
) -> LocalImportOutcome {
  case identity.sha256(expected_content_hash) {
    Error(_) -> InvalidExpectedHash
    Ok(expected) ->
      case string.byte_size(text) == byte_count {
        False -> ByteCountMismatch
        True ->
          case hash.text(text) {
            Error(_) -> InvalidReadResult
            Ok(actual) if actual != expected -> ContentHashMismatch
            Ok(_) -> decode_verified(text, identity.sha256_value(expected))
          }
      }
  }
}

fn decode_verified(text: String, content_hash: String) -> LocalImportOutcome {
  case json.parse(text, decode.bound_review_input(content_hash)) {
    Error(_) -> InvalidJson
    Ok(decode.BoundReviewInput(version, _input))
      if version != contract_version
    -> UnsupportedContractVersion(version)
    Ok(decode.BoundReviewInput(_, input))
      if input.mode != "external_execution_receipt_import"
    -> UnsupportedImportMode(input.mode)
    Ok(decode.BoundReviewInput(_, input)) ->
      case domain.run_content_bound(input) {
        Ok(review) -> Imported(review)
        Error(error) ->
          ReviewRejected(finance_broker_review.error_message(error))
      }
  }
}
