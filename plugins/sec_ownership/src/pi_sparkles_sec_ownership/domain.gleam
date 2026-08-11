import finance_research_contract as research

pub fn descriptor() -> research.Descriptor {
  research.Descriptor(
    "sec_ownership_v1",
    "us",
    ["XNYS", "XNAS"],
    ["schedule_13d", "schedule_13g", "form_13f", "amendment"],
    ["accession", "filer", "security_id", "quantity"],
  )
}
