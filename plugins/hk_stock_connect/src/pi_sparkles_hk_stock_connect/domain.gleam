import finance_research_contract as research

pub fn descriptor() -> research.Descriptor {
  research.Descriptor(
    "hk_stock_connect_v1",
    "hk",
    ["XHKG"],
    ["eligibility", "quota", "status_change"],
    ["program", "direction", "status", "effective_date"],
  )
}
