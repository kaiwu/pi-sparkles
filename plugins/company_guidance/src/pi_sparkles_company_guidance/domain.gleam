import finance_research_calculation as calculation

pub fn descriptor() -> calculation.Descriptor {
  calculation.Descriptor("company_guidance_v1", "us", ["XNYS", "XNAS"], [
    "difference",
    "percent_change",
  ])
}
