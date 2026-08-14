import finance_broker_review
import finance_broker_review/decode.{
  type ExplicitCapabilityInput, ExplicitCapabilityInput,
}
import gleam/result

pub fn run(
  input: ExplicitCapabilityInput,
) -> Result(finance_broker_review.Review, finance_broker_review.ReviewError) {
  let ExplicitCapabilityInput(provider, review) = input
  use _ <- result.try(
    finance_broker_review.require_unique_known_fact_names(review, [
      "broker_provider",
      "capability_scope",
      "entitlement_scope",
      "read_only_authority",
      "paper_environment",
    ]),
  )
  use _ <- result.try(finance_broker_review.require_unique_known_fact(
    review,
    "broker_provider",
    provider,
    "provider_identifier",
  ))
  use _ <- result.try(finance_broker_review.require_unique_known_fact(
    review,
    "read_only_authority",
    "read_only",
    "authority_scope",
  ))
  finance_broker_review.review_explicit_capability(review, provider, "cn", [
    #("external_paper_receipt", "external_paper"),
  ])
}
