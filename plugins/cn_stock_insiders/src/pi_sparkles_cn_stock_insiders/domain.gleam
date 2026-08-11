import finance_research_contract as research

pub fn descriptor() -> research.Descriptor {
  research.Descriptor(
    "cn_stock_insiders_v1",
    "cn",
    ["XSHG", "XSHE", "XBSE"],
    [
      "increase_plan",
      "reduction_plan",
      "transaction",
      "completion",
      "cancellation",
    ],
    ["holder_label", "event_type", "announcement_date"],
  )
}
