import finance_research_contract as research

pub fn descriptor() -> research.Descriptor {
  research.Descriptor(
    "cn_stock_restricted_shares_v1",
    "cn",
    ["XSHG", "XSHE", "XBSE"],
    ["unlock_plan", "unlock_actual", "unlock_revision"],
    ["quantity", "state", "announcement_date"],
  )
}
