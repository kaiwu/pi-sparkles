import finance_broker_review
import finance_broker_review/decode.{type ReviewInput}

pub fn run(
  input: ReviewInput,
) -> Result(finance_broker_review.Review, finance_broker_review.ReviewError) {
  finance_broker_review.review(
    input,
    "ibkr_paper_evidence",
    "us",
    [
      #("deterministic_scenario", "local_simulation"),
      #("external_paper_receipt_import", "ibkr_paper"),
    ],
    [
      "ibkr_network_adapter_on_hold",
      "ibkr_paper_provider_conformance",
      "named_fill_model_execution",
    ],
  )
}
