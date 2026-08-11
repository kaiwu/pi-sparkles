import finance_research_contract as research

pub fn descriptor() -> research.Descriptor {
  research.Descriptor(
    "cn_stock_margin_v1",
    "cn",
    ["XSHG", "XSHE", "XBSE"],
    [
      "eligibility",
      "financing_balance",
      "financing_purchase",
      "financing_repayment",
      "securities_lending_balance",
      "securities_lending_sale",
      "market_aggregate",
    ],
    ["field_label", "value", "observation_date"],
  )
}
