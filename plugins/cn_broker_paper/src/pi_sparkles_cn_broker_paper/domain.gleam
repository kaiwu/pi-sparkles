import finance_broker_review
import finance_broker_review/decode.{type ReviewInput}

pub fn run(
  input: ReviewInput,
) -> Result(finance_broker_review.Review, finance_broker_review.ReviewError) {
  finance_broker_review.review(
    input,
    "cn_paper_evidence",
    "cn",
    [
      #("deterministic_scenario", "local_simulation"),
      #("external_paper_receipt_import", "external_paper"),
    ],
    [
      "named_cn_broker_readonly_contract",
      "authenticated_cn_intraday_feed",
      "external_paper_provider_conformance",
    ],
  )
}
