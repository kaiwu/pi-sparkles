import finance_research_contract as research

pub fn descriptor() -> research.Descriptor {
  research.Descriptor(
    "cn_stock_connect_v1",
    "cn",
    ["XSHG", "XSHE"],
    ["eligibility", "quota", "status_change"],
    ["program", "direction", "status", "effective_date"],
  )
}
