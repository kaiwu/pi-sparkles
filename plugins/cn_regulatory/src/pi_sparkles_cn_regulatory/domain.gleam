import finance_research_contract as research

pub fn descriptor() -> research.Descriptor {
  research.Descriptor(
    "cn_regulatory_v1",
    "cn",
    ["XSHG", "XSHE", "XBSE"],
    [
      "rule",
      "inquiry_letter",
      "supervision_letter",
      "disciplinary_action",
      "enforcement_release",
    ],
    ["authority", "document_id", "original_title", "published_date"],
  )
}
