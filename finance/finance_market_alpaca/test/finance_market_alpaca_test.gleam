import finance_core/time
import finance_http/request
import finance_market_alpaca
import finance_market_alpaca/bars
import finance_market_alpaca/query
import finance_market_alpaca/request as provider_request
import gleam/list
import gleam/option.{Some}
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn query_requires_exact_symbol_feed_identity_and_budgets_test() {
  query.daily_bars(
    "aapl",
    civil(2024, 8, 1),
    civil(2024, 8, 2),
    civil(2024, 8, 2),
    query.Iex,
    100,
    2,
    200,
  )
  |> should.equal(Error(query.InvalidSymbol))
  query.daily_bars(
    "AAPL",
    civil(2024, 8, 2),
    civil(2024, 8, 1),
    civil(2024, 8, 2),
    query.Iex,
    100,
    2,
    200,
  )
  |> should.equal(Error(query.InvalidDateRange))
}

pub fn request_is_raw_usd_ascending_bounded_and_secret_test() {
  let plan = plan(query.Sip)
  let assert Ok(value) =
    provider_request.daily_bars(access(), plan, 100, Some("page-two"))
  request.origin(value) |> should.equal(provider_request.origin)
  request.path(value) |> should.equal(provider_request.bars_path)
  request.maximum_response_bytes(value) |> should.equal(5_000_000)
  [
    request.QueryParameter("symbols", "AAPL", request.Public),
    request.QueryParameter("timeframe", "1Day", request.Public),
    request.QueryParameter("adjustment", "raw", request.Public),
    request.QueryParameter("feed", "sip", request.Public),
    request.QueryParameter("currency", "USD", request.Public),
    request.QueryParameter("sort", "asc", request.Public),
    request.QueryParameter("asof", "2024-08-05", request.Public),
    request.QueryParameter("page_token", "page-two", request.Public),
  ]
  |> list.all(fn(expected) { request.query(value) |> list.contains(expected) })
  |> should.be_true
  request.headers(value)
  |> list.contains(request.Header("apca-api-key-id", "key-id", request.Secret))
  |> should.be_true
  request.safe_key(value)
  |> string.contains("secret-key")
  |> should.be_false
}

pub fn decoder_preserves_source_lexemes_timestamp_and_pagination_test() {
  let assert Ok(page) =
    bars.decode_page(page_fixture(), for: plan(query.Iex), page_limit: 2)
  bars.next_page_token(page) |> should.equal(Some("next-token"))
  let assert [first, second] = bars.bars(page)
  bars.open(first) |> should.equal("185.6200")
  bars.volume(first) |> should.equal("50292117")
  bars.trade_count(first) |> should.equal("612345")
  bars.timestamp(second) |> should.equal("2024-08-02T04:00:00Z")
  time.unix_milliseconds(bars.at(second)) |> should.equal(1_722_571_200_000)
}

pub fn decoder_rejects_symbol_range_order_and_page_overflow_test() {
  bars.decode_page(
    string.replace(page_fixture(), "\"AAPL\"", "\"MSFT\""),
    for: plan(query.Iex),
    page_limit: 2,
  )
  |> should.equal(Error(bars.UnexpectedSymbols))
  bars.decode_page(page_fixture(), for: plan(query.Iex), page_limit: 1)
  |> should.equal(Error(bars.TooManyBars(1, 2)))
  bars.decode_page(reversed_fixture(), for: plan(query.Iex), page_limit: 2)
  |> should.equal(Error(bars.OutOfOrder(1)))
  bars.decode_page(
    string.replace(page_fixture(), "2024-08-01T04:00:00Z", "2024-8-1T04:00:00Z"),
    for: plan(query.Iex),
    page_limit: 2,
  )
  |> should.be_error
  bars.decode_page(
    string.replace(page_fixture(), "50292117", "50292117.5"),
    for: plan(query.Iex),
    page_limit: 2,
  )
  |> should.be_error
}

fn access() -> finance_market_alpaca.Access {
  let assert Ok(value) =
    finance_market_alpaca.access(
      "key-id",
      "secret-key",
      "pi-sparkles-test/0.1",
      "test@example.test",
    )
  value
}

fn plan(feed: query.Feed) -> query.DailyBarsQuery {
  let assert Ok(value) =
    query.daily_bars(
      "AAPL",
      civil(2024, 8, 1),
      civil(2024, 8, 2),
      civil(2024, 8, 5),
      feed,
      100,
      2,
      200,
    )
  value
}

fn civil(year: Int, month: Int, day: Int) -> time.Date {
  let assert Ok(value) = time.date(year, month, day)
  value
}

fn page_fixture() -> String {
  "{\"bars\":{\"AAPL\":[{\"c\":187.12,\"h\":188.10,\"l\":184.22,\"n\":612345,\"o\":185.6200,\"t\":\"2024-08-01T04:00:00Z\",\"v\":50292117,\"vw\":186.432100},{\"c\":189.84,\"h\":190.01,\"l\":186.31,\"n\":598765,\"o\":186.90,\"t\":\"2024-08-02T04:00:00Z\",\"v\":49910111,\"vw\":188.7654}]},\"next_page_token\":\"next-token\"}"
}

fn reversed_fixture() -> String {
  "{\"bars\":{\"AAPL\":[{\"c\":189.84,\"h\":190.01,\"l\":186.31,\"n\":598765,\"o\":186.90,\"t\":\"2024-08-02T04:00:00Z\",\"v\":49910111,\"vw\":188.7654},{\"c\":187.12,\"h\":188.10,\"l\":184.22,\"n\":612345,\"o\":185.6200,\"t\":\"2024-08-01T04:00:00Z\",\"v\":50292117,\"vw\":186.432100}]},\"next_page_token\":null}"
}
