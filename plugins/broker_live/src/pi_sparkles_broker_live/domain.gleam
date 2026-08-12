import finance_broker_review
import finance_broker_review/decode.{type ReviewInput}

pub fn run(
  input: ReviewInput,
) -> Result(finance_broker_review.Review, finance_broker_review.ReviewError) {
  finance_broker_review.review(
    input,
    "caller_selected_external_broker",
    "any",
    [
      #("non_executable_handoff", "external_paper"),
      #("non_executable_handoff", "external_live"),
      #("external_execution_receipt_import", "external_paper"),
      #("external_execution_receipt_import", "external_live"),
    ],
    [
      "provider_network_observation",
      "provider_rights_review",
      "live_sequence_conformance",
    ],
  )
}
