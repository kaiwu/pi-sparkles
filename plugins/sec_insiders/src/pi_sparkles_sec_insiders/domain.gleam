import finance_research_contract as research

pub fn descriptor() -> research.Descriptor {
  research.Descriptor(
    "sec_insiders_v1",
    "us",
    ["XNYS", "XNAS"],
    ["form3_holding", "form4_transaction", "form5_transaction", "amendment"],
    ["accession", "reporting_owner", "transaction_code", "quantity"],
  )
}
