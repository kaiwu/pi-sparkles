import finance_research_calculation as calculation

pub fn descriptor() -> calculation.Descriptor {
  calculation.Descriptor(
    "cn_stock_block_trades_v1",
    "cn",
    ["XSHG", "XSHE", "XBSE"],
    ["percent_change"],
  )
}
