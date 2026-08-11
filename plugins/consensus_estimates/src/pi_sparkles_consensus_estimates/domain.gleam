import finance_research_calculation as calculation

pub fn descriptor() -> calculation.Descriptor {
  calculation.Descriptor("consensus_estimates_v1", "us", ["XNYS", "XNAS"], [
    "mean",
    "difference",
    "percent_change",
  ])
}
