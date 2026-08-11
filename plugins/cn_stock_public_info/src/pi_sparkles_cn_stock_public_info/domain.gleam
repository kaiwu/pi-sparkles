import finance_research_contract as research

pub fn descriptor() -> research.Descriptor {
  research.Descriptor(
    "cn_stock_public_info_v1",
    "cn",
    ["XSHG", "XSHE", "XBSE"],
    ["unusual_movement", "dragon_tiger_seat"],
    ["published_reason", "trade_window", "amount"],
  )
}
