import finance_broker_review
import finance_broker_review/decode.{type ReviewInput}

pub fn run(
  input: ReviewInput,
) -> Result(finance_broker_review.Review, finance_broker_review.ReviewError) {
  finance_broker_review.review(
    input,
    "alpaca_paper_evidence",
    "us",
    [
      #("deterministic_scenario", "local_simulation"),
      #("external_paper_receipt_import", "alpaca_paper"),
    ],
    [
      "alpaca_network_adapter_on_hold",
      "alpaca_paper_provider_conformance",
      "named_fill_model_execution",
    ],
  )
}
