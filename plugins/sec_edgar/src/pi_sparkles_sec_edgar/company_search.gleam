import finance_sec/response.{type Company}
import gleam/int
import gleam/list
import gleam/order
import gleam/string

pub opaque type Plan {
  Plan(query: String, limit: Int)
}

pub type PlanError {
  EmptyQuery
  QueryTooLong
  InvalidLimit
}

pub type MatchReason {
  ExactTicker
  TickerPrefix
  ExactTitle
  TitleContains
  TickerContains
}

pub type Match {
  Match(company: Company, reason: MatchReason)
}

type Ranked {
  Ranked(score: Int, company: Company)
}

pub fn plan(query: String, limit: Int) -> Result(Plan, PlanError) {
  let normalized = query |> string.trim |> string.uppercase
  case
    normalized == "",
    string.length(normalized) > 200,
    limit < 1 || limit > 25
  {
    True, _, _ -> Error(EmptyQuery)
    _, True, _ -> Error(QueryTooLong)
    _, _, True -> Error(InvalidLimit)
    False, False, False -> Ok(Plan(normalized, limit))
  }
}

pub fn find(companies: List(Company), plan: Plan) -> List(Match) {
  let Plan(query, limit) = plan
  companies
  |> list.filter_map(fn(company) {
    case rank(company, query) {
      Error(_) -> Error(Nil)
      Ok(score) -> Ok(Ranked(score, company))
    }
  })
  |> list.sort(by: compare_ranked)
  |> list.take(limit)
  |> list.map(fn(ranked) {
    let Ranked(score, company) = ranked
    Match(company, reason(score))
  })
}

pub fn reason_name(value: MatchReason) -> String {
  case value {
    ExactTicker -> "exact_ticker"
    TickerPrefix -> "ticker_prefix"
    ExactTitle -> "exact_title"
    TitleContains -> "title_contains"
    TickerContains -> "ticker_contains"
  }
}

fn rank(company: Company, query: String) -> Result(Int, Nil) {
  let ticker = string.uppercase(company.ticker)
  let title = string.uppercase(company.title)
  case
    ticker == query,
    string.starts_with(ticker, query),
    title == query,
    string.contains(title, query),
    string.contains(ticker, query)
  {
    True, _, _, _, _ -> Ok(0)
    _, True, _, _, _ -> Ok(1)
    _, _, True, _, _ -> Ok(2)
    _, _, _, True, _ -> Ok(3)
    _, _, _, _, True -> Ok(4)
    False, False, False, False, False -> Error(Nil)
  }
}

fn reason(score: Int) -> MatchReason {
  case score {
    0 -> ExactTicker
    1 -> TickerPrefix
    2 -> ExactTitle
    3 -> TitleContains
    _ -> TickerContains
  }
}

fn compare_ranked(left: Ranked, right: Ranked) -> order.Order {
  let Ranked(left_score, left_company) = left
  let Ranked(right_score, right_company) = right
  case int.compare(left_score, right_score) {
    order.Eq -> string.compare(left_company.ticker, right_company.ticker)
    other -> other
  }
}
