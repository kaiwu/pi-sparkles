import finance_research_calculation as calculation

pub fn descriptor() -> calculation.Descriptor {
  calculation.Descriptor("stock_comps_v1", "us", ["XNYS", "XNAS"], ["ratio"])
}
