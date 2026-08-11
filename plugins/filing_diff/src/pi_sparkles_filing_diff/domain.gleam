import finance_research_diff as diff
import gleam/option

pub fn descriptor() -> diff.Descriptor {
  diff.Descriptor(
    "filing_diff_v1",
    "us",
    ["XNYS", "XNAS"],
    [
      "10-K",
      "10-K/A",
      "10-Q",
      "10-Q/A",
      "8-K",
      "8-K/A",
      "20-F",
      "20-F/A",
      "6-K",
      "6-K/A",
    ],
    option.None,
  )
}
