import gleam/string

pub fn workflow(request: String) -> String {
  [
    "Build a US cited company brief for: " <> request,
    "",
    "Use only these installed read-only evidence tools where applicable:",
    "1. us_stock_quote with an explicit iex or sip feed.",
    "2. us_stock_ohlcv with explicit dates, symbol as-of date, feed, and budgets.",
    "3. sec_company_submissions for bounded recent filing metadata.",
    "4. stock_fundamental_period for a small declared metric set and exact period end.",
    "",
    "Do not choose among ambiguous fundamental candidates. Pass only unique exact receipt fields to us_company_brief, list every unavailable or ambiguous capability in missingCapabilities, and add no uncited model facts. The final compositor is deterministic and network-free.",
  ]
  |> string.join("\n")
}
