import finance_broker_review
import finance_broker_review/decode.{
  type ExplicitCapabilityInput, ExplicitCapabilityInput,
}
import gleam/result

const provider_fact = "broker_provider"

pub fn run(
  input: ExplicitCapabilityInput,
) -> Result(finance_broker_review.Review, finance_broker_review.ReviewError) {
  let ExplicitCapabilityInput(provider, review) = input
  use _ <- result.try(
    finance_broker_review.require_unique_known_fact_names(review, [
      provider_fact,
      "listing_board",
      "share_class",
      "native_currency",
      "settlement_cycle",
      "capability_scope",
      "entitlement_scope",
      "read_only_authority",
    ]),
  )
  use _ <- result.try(finance_broker_review.require_unique_known_fact(
    review,
    provider_fact,
    provider,
    "provider_identifier",
  ))
  use _ <- result.try(finance_broker_review.require_unique_known_fact(
    review,
    "native_currency",
    "CNY",
    "iso_4217",
  ))
  use _ <- result.try(finance_broker_review.require_unique_known_fact(
    review,
    "read_only_authority",
    "read_only",
    "authority_scope",
  ))
  finance_broker_review.review_explicit_capability(review, provider, "cn", [
    #("read_only_capability", "external_live"),
    #("caller_owned_export", "caller_export"),
  ])
}
