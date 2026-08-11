import finance_research_calculation as calculation

pub fn descriptor() -> calculation.Descriptor {
  calculation.Descriptor(
    "cn_stock_financials_v1",
    "cn",
    ["XSHG", "XSHE", "XBSE"],
    ["net_margin"],
  )
}
