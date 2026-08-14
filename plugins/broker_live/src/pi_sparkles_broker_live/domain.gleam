import finance_broker_review
import finance_broker_review/decode.{
  type ExplicitCapabilityInput, type ReviewInput, ExplicitCapabilityInput,
}
import gleam/result

pub fn run(
  input: ExplicitCapabilityInput,
) -> Result(finance_broker_review.Review, finance_broker_review.ReviewError) {
  let ExplicitCapabilityInput(provider, review) = input
  use _ <- result.try(validate_mode(review, provider))
  finance_broker_review.review_explicit_capability(
    review,
    provider,
    "any",
    allowed_modes(),
  )
}

pub fn run_content_bound(
  input: ExplicitCapabilityInput,
) -> Result(finance_broker_review.Review, finance_broker_review.ReviewError) {
  let ExplicitCapabilityInput(provider, review) = input
  use _ <- result.try(validate_mode(review, provider))
  finance_broker_review.review_explicit_capability_content_bound(
    review,
    provider,
    "any",
    allowed_modes(),
  )
}

fn validate_mode(
  input: ReviewInput,
  provider: String,
) -> Result(Nil, finance_broker_review.ReviewError) {
  use _ <- result.try(case input.mode {
    "non_executable_handoff" ->
      finance_broker_review.require_unique_known_fact_names(input, [
        "broker_provider",
        "read_only_authority",
        "provider_capability_receipt",
        "instruction_side",
        "instruction_kind",
        "quantity",
        "quantity_unit",
        "time_in_force",
        "plan_fingerprint",
        "rule_reference",
      ])
    "external_execution_receipt_import" ->
      finance_broker_review.require_unique_known_fact_names(input, [
        "broker_provider",
        "read_only_authority",
        "entitlement_scope",
        "capability_scope",
        "handoff_receipt",
        "external_execution_receipt",
      ])
    _ -> Ok(Nil)
  })
  use _ <- result.try(finance_broker_review.require_unique_known_fact(
    input,
    "broker_provider",
    provider,
    "provider_identifier",
  ))
  finance_broker_review.require_unique_known_fact(
    input,
    "read_only_authority",
    "read_only",
    "authority_scope",
  )
}

fn allowed_modes() -> List(#(String, String)) {
  [
    #("non_executable_handoff", "external_paper"),
    #("non_executable_handoff", "external_live"),
    #("external_execution_receipt_import", "external_paper"),
    #("external_execution_receipt_import", "external_live"),
  ]
}
