import finance_broker_review
import finance_broker_review/decode.{type ReviewInput}

pub fn run(
  input: ReviewInput,
) -> Result(finance_broker_review.Review, finance_broker_review.ReviewError) {
  finance_broker_review.review(
    input,
    "alpaca",
    "us",
    [
      #("account_activity_import", "paper"),
      #("account_activity_import", "live"),
    ],
    [
      "alpaca_network_adapter_on_hold",
      "read_only_key_scope_validation",
      "opt_in_provider_conformance",
    ],
  )
}
