import finance_research_calculation as calculation

pub fn descriptor() -> calculation.Descriptor {
  calculation.Descriptor("hk_stock_ah_comparison_v1", "hk", ["XHKG"], [
    "premium_discount_fx",
  ])
}
