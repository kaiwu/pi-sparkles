import finance_broker_review
import finance_broker_review/decode.{type ReviewInput}

pub fn run(
  input: ReviewInput,
) -> Result(finance_broker_review.Review, finance_broker_review.ReviewError) {
  finance_broker_review.review(
    input,
    "ibkr",
    "us",
    [
      #("account_activity_import", "paper"),
      #("account_activity_import", "live"),
    ],
    [
      "ibkr_network_adapter_on_hold",
      "read_only_gateway_scope_validation",
      "opt_in_provider_conformance",
    ],
  )
}
