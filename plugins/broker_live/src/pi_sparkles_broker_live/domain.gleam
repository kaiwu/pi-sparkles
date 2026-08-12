import finance_broker_review
import finance_broker_review/decode.{type ReviewInput}
import gleam/result

pub fn run(
  input: ReviewInput,
) -> Result(finance_broker_review.Review, finance_broker_review.ReviewError) {
  use _ <- result.try(case input.mode {
    "non_executable_handoff" ->
      finance_broker_review.require_unique_known_fact_names(input, [
        "instruction_side",
        "instruction_kind",
        "quantity",
        "quantity_unit",
        "time_in_force",
        "plan_fingerprint",
        "rule_reference",
      ])
    _ -> Ok(Nil)
  })
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
