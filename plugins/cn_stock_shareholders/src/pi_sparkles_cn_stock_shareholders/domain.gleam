import finance_research_contract as research

pub fn descriptor() -> research.Descriptor {
  research.Descriptor(
    "cn_stock_shareholders_v1",
    "cn",
    ["XSHG", "XSHE", "XBSE"],
    ["top_shareholder", "top_tradable_holder", "shareholder_count"],
    ["holder_label", "report_date", "source_document"],
  )
}
