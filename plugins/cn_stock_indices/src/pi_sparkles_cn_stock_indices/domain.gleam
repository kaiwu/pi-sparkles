import finance_research_contract as research

pub fn descriptor() -> research.Descriptor {
  research.Descriptor(
    "cn_stock_indices_v1",
    "cn",
    ["XSHG", "XSHE", "XBSE"],
    ["index_identity", "constituent", "rebalance"],
    ["index_code", "effective_date", "knowledge_date"],
  )
}
