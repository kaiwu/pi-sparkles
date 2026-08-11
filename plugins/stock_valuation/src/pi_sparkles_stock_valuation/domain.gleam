import finance_research_calculation as calculation

pub fn descriptor() -> calculation.Descriptor {
  calculation.Descriptor("stock_valuation_v1", "us", ["XNYS", "XNAS"], [
    "enterprise_to_equity_per_share",
  ])
}
