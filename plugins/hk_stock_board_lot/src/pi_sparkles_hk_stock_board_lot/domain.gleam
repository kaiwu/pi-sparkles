import finance_research_contract as research

pub fn descriptor() -> research.Descriptor {
  research.Descriptor(
    "hk_stock_board_lot_v1",
    "hk",
    ["XHKG"],
    ["board_lot", "odd_lot_context", "correction"],
    ["lot_quantity", "effective_from", "source_rule"],
  )
}
