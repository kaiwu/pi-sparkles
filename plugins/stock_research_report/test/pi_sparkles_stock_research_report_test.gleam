import gleam/list
import gleam/option.{Some}
import gleam/string
import gleeunit
import gleeunit/should
import pi_sparkles_stock_research_report/report

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn exact_receipts_render_with_stable_evidence_roots_test() {
  let assert Ok(brief) =
    report.build(
      identity(),
      quotes: [quote()],
      histories: [history()],
      filings: [filing()],
      fundamentals: [fundamental()],
      missing_capabilities: ["effective US market rules are unavailable"],
    )
  let rendered = report.render(brief)
  rendered |> string.contains("189.1000 × 7") |> should.be_true
  rendered |> string.contains("revenue | 383285000000 USD") |> should.be_true
  report.citations(brief) |> list.length |> should.equal(4)
}

pub fn mismatched_sources_and_duplicate_metrics_fail_closed_test() {
  let bad_quote =
    report.QuoteReceipt(
      report.Iex,
      "2024-08-06T19:59:59Z",
      1_800_000_000_000,
      "V",
      "189.1",
      "7",
      "V",
      "189.2",
      "4",
      ["R"],
      "C",
      Some("request"),
      "credentialed_iex_latest",
      "https://data.alpaca.markets/v2/stocks/quotes/latest?symbols=MSFT&feed=iex&currency=USD",
    )
  report.build(
    identity(),
    quotes: [bad_quote],
    histories: [],
    filings: [],
    fundamentals: [],
    missing_capabilities: [],
  )
  |> should.equal(Error(report.InvalidQuoteSource))

  report.build(
    identity(),
    quotes: [],
    histories: [],
    filings: [],
    fundamentals: [fundamental(), fundamental()],
    missing_capabilities: [],
  )
  |> should.equal(Error(report.DuplicateFundamental("revenue")))
}

pub fn missing_sections_are_explicit_test() {
  let assert Ok(brief) =
    report.build(
      identity(),
      quotes: [],
      histories: [],
      filings: [],
      fundamentals: [],
      missing_capabilities: ["quote unavailable", "fundamentals ambiguous"],
    )
  report.render(brief)
  |> string.contains("fundamentals ambiguous")
  |> should.be_true
}

pub fn future_as_of_and_changed_canonical_values_fail_closed_test() {
  report.build(
    report.Identity("Apple Inc.", "AAPL", "0000320193", "2024-01-01"),
    quotes: [],
    histories: [],
    filings: [filing()],
    fundamentals: [],
    missing_capabilities: [],
  )
  |> should.equal(Error(report.InvalidFiling(0)))

  let changed =
    report.FundamentalReceipt(
      "revenue",
      "383285000000",
      "383285000001",
      "USD",
      "annual",
      Some("2023-10-01"),
      "2024-09-28",
      "RevenueFromContractWithCustomerExcludingAssessedTax",
      "0000320193-24-000123",
      "10-K",
      "2024-11-01",
      "https://data.sec.gov/api/xbrl/companyfacts/CIK0000320193.json",
    )
  report.build(
    identity(),
    quotes: [],
    histories: [],
    filings: [],
    fundamentals: [changed],
    missing_capabilities: [],
  )
  |> should.equal(Error(report.InvalidFundamental(0)))
}

fn identity() -> report.Identity {
  report.Identity("Apple Inc.", "AAPL", "0000320193", "2026-08-06")
}

fn quote() -> report.QuoteReceipt {
  report.QuoteReceipt(
    report.Iex,
    "2024-08-06T19:59:59.123456789Z",
    1_800_000_000_000,
    "V",
    "189.1000",
    "7",
    "V",
    "189.1200",
    "4",
    ["R"],
    "C",
    Some("quote-request-one"),
    "credentialed_iex_latest",
    "https://data.alpaca.markets/v2/stocks/quotes/latest?symbols=AAPL&feed=iex&currency=USD",
  )
}

fn history() -> report.HistoryReceipt {
  report.HistoryReceipt(
    report.Iex,
    "2024-08-01",
    "2024-08-05",
    3,
    "complete",
    "calendar_not_assessed",
    "https://data.alpaca.markets/v2/stocks/bars?symbols=AAPL&timeframe=1Day&start=2024-08-01&end=2024-08-05&adjustment=raw&feed=iex&currency=USD&sort=asc&asof=2024-08-06",
  )
}

fn filing() -> report.FilingReceipt {
  report.FilingReceipt(
    "0000320193-24-000123",
    "2024-08-02",
    "2024-06-29",
    "10-Q",
    "aapl-20240629.htm",
    "https://data.sec.gov/submissions/CIK0000320193.json",
  )
}

fn fundamental() -> report.FundamentalReceipt {
  report.FundamentalReceipt(
    "revenue",
    "383285000000",
    "383285000000",
    "USD",
    "annual",
    Some("2023-10-01"),
    "2024-09-28",
    "RevenueFromContractWithCustomerExcludingAssessedTax",
    "0000320193-24-000123",
    "10-K",
    "2024-11-01",
    "https://data.sec.gov/api/xbrl/companyfacts/CIK0000320193.json",
  )
}
