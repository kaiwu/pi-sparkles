import finance_sec
import finance_sec/response.{Company, Filing, Submissions}
import gleam/list
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should
import pi_sparkles_sec_edgar/company_search
import pi_sparkles_sec_edgar/filing_selection

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn company_search_is_ranked_and_bounded_test() {
  let assert Ok(apple) = finance_sec.cik("320193")
  let assert Ok(appfolio) = finance_sec.cik("1433195")
  let companies = [
    Company(appfolio, "APPF", "AppFolio, Inc."),
    Company(apple, "AAPL", "Apple Inc."),
  ]
  let assert Ok(plan) = company_search.plan("aapl", 1)
  let assert [match] = company_search.find(companies, plan)
  match.company.ticker |> should.equal("AAPL")
  match.reason |> should.equal(company_search.ExactTicker)
}

pub fn company_search_rejects_invalid_plans_test() {
  company_search.plan(" ", 10)
  |> should.equal(Error(company_search.EmptyQuery))
  company_search.plan("AAPL", 0)
  |> should.equal(Error(company_search.InvalidLimit))
}

pub fn filing_selection_filters_without_reordering_test() {
  let assert Ok(cik) = finance_sec.cik("320193")
  let quarterly = Filing("q", "2025-08-01", "2025-06-28", "10-Q", "q.htm")
  let current = Filing("k", "2025-08-02", "", "8-K", "k.htm")
  let submissions =
    Submissions(cik, "Apple Inc.", ["AAPL"], ["Nasdaq"], [
      current,
      quarterly,
    ])
  let assert Ok(plan) = filing_selection.plan(Some("10-q"), 10)
  filing_selection.select(submissions, plan) |> should.equal([quarterly])
  filing_selection.plan(None, 51)
  |> should.equal(Error(filing_selection.InvalidLimit))
}

pub fn match_reason_names_are_stable_test() {
  [
    company_search.ExactTicker,
    company_search.TickerPrefix,
    company_search.ExactTitle,
    company_search.TitleContains,
    company_search.TickerContains,
  ]
  |> list.map(company_search.reason_name)
  |> should.equal([
    "exact_ticker",
    "ticker_prefix",
    "exact_title",
    "title_contains",
    "ticker_contains",
  ])
}
