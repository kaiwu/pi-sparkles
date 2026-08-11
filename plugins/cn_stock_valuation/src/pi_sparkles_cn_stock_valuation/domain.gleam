import finance_research_calculation as calculation

pub fn descriptor() -> calculation.Descriptor {
  calculation.Descriptor(
    "cn_stock_valuation_v1",
    "cn",
    ["XSHG", "XSHE", "XBSE"],
    ["enterprise_to_equity_per_share"],
  )
}
