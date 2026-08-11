import finance_research_contract as research

pub fn descriptor() -> research.Descriptor {
  research.Descriptor(
    "cn_stock_pledges_v1",
    "cn",
    ["XSHG", "XSHE", "XBSE"],
    ["pledge", "release", "freeze"],
    ["holder_label", "quantity", "event_date"],
  )
}
