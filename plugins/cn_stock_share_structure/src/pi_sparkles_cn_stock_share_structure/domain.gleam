import finance_research_contract as research

pub fn descriptor() -> research.Descriptor {
  research.Descriptor(
    "cn_stock_share_structure_v1",
    "cn",
    ["XSHG", "XSHE", "XBSE"],
    ["share_capital", "share_class", "reconciliation"],
    ["quantity", "unit", "denominator_scope", "report_date"],
  )
}
