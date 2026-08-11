import finance_research_contract as research

pub fn descriptor() -> research.Descriptor {
  research.Descriptor(
    "hk_stock_corporate_actions_v1",
    "hk",
    ["XHKG"],
    [
      "cash_dividend",
      "stock_dividend",
      "split",
      "consolidation",
      "rights_issue",
      "bonus_issue",
    ],
    ["action_id", "announcement_date", "terms"],
  )
}
