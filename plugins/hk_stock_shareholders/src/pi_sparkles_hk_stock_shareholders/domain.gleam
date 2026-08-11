import finance_research_contract as research

pub fn descriptor() -> research.Descriptor {
  research.Descriptor(
    "hk_stock_shareholders_v1",
    "hk",
    ["XHKG"],
    ["substantial_shareholder_notice", "amendment"],
    ["holder_label", "event_date", "disclosure_date"],
  )
}
