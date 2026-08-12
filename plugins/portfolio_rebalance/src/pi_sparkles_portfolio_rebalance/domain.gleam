import finance_portfolio_review as review

pub fn descriptor() -> review.Descriptor {
  review.Descriptor("portfolio_rebalance_v1", ["compute_rebalance"])
}
