import finance_research_calculation as calculation

pub fn descriptor() -> calculation.Descriptor {
  calculation.Descriptor("earnings_release_v1", "us", ["XNYS", "XNAS"], [
    "difference",
    "percent_change",
  ])
}
