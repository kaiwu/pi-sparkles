import finance_research_contract as research

pub fn descriptor() -> research.Descriptor {
  research.Descriptor(
    "industry_research_v1",
    "us",
    ["XNYS", "XNAS"],
    [
      "taxonomy",
      "market_structure",
      "participant",
      "value_chain",
      "capacity",
      "supply_demand",
      "regulation",
      "metric",
      "revision",
    ],
    ["taxonomy_code", "effective_date", "source_document"],
  )
}
