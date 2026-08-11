import finance_research_contract as research

pub fn descriptor() -> research.Descriptor {
  research.Descriptor(
    "company_governance_v1",
    "us",
    ["XNYS", "XNAS"],
    [
      "board",
      "committee",
      "beneficial_ownership",
      "compensation",
      "auditor",
      "related_party",
      "capital_allocation",
      "restatement",
      "litigation",
    ],
    ["source_document", "period", "information_state"],
  )
}
