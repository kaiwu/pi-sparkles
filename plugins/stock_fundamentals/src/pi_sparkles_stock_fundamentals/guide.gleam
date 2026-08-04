import gleam/string

/// A compact, network-free guide to the plugin's public workflow.
pub fn text() -> String {
  [
    "Stock fundamentals (SEC, read-only)",
    "",
    "Start: use stock_fundamental_period for one of revenue, net_income, assets, cash_and_equivalents, operating_cash_flow, capital_expenditures_reported, or diluted_weighted_average_shares.",
    "Calculated: stock_fundamental_metric supports free_cash_flow, net_margin, and diluted_eps.",
    "History: use stock_fundamental_trend, stock_fundamental_growth, or a stock_fundamental_ttm tool.",
    "",
    "If a result is ambiguous, inspect its candidates and retry with an exact accession. Use stock_fundamental_definitions for the complete mapping rules.",
  ]
  |> string.join("\n")
}
