import finance_core/time
import finance_http/request
import finance_market_alpaca
import finance_market_alpaca/assets
import finance_market_alpaca/bars
import finance_market_alpaca/query
import finance_market_alpaca/quotes
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
  query.daily_bars_source_reference(plan)
  |> should.equal(
    "https://data.alpaca.markets/v2/stocks/bars?symbols=AAPL&timeframe=1Day&start=2024-08-01&end=2024-08-02&adjustment=raw&feed=sip&currency=USD&sort=asc&asof=2024-08-05",
  )
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

pub fn latest_quote_request_has_explicit_feed_and_small_response_budget_test() {
  let assert Ok(plan) = query.latest_quote("AAPL", query.Sip)
  let assert Ok(value) = provider_request.latest_quote(access(), plan)
  request.path(value) |> should.equal(provider_request.latest_quotes_path)
  request.maximum_response_bytes(value) |> should.equal(250_000)
  [
    request.QueryParameter("symbols", "AAPL", request.Public),
    request.QueryParameter("feed", "sip", request.Public),
    request.QueryParameter("currency", "USD", request.Public),
  ]
  |> list.all(fn(expected) { request.query(value) |> list.contains(expected) })
  |> should.be_true
  request.safe_key(value)
  |> string.contains("secret-key")
  |> should.be_false
}

pub fn asset_universe_request_keeps_environment_filters_and_budget_explicit_test() {
  let plan = asset_plan(2)
  query.asset_universe_source_reference(plan)
  |> should.equal(
    "https://paper-api.alpaca.markets/v2/assets?status=active&asset_class=us_equity&exchange=NASDAQ",
  )
  let assert Ok(value) = provider_request.asset_universe(access(), plan)
  request.origin(value)
  |> should.equal(query.trading_origin(query.Paper))
  request.path(value) |> should.equal(provider_request.assets_path)
  request.maximum_response_bytes(value) |> should.equal(15_000_000)
  [
    request.QueryParameter("status", "active", request.Public),
    request.QueryParameter("asset_class", "us_equity", request.Public),
    request.QueryParameter("exchange", "NASDAQ", request.Public),
  ]
  |> list.all(fn(expected) { request.query(value) |> list.contains(expected) })
  |> should.be_true
  request.safe_key(value)
  |> string.contains("secret-key")
  |> should.be_false

  query.asset_universe(query.Live, query.AllStatuses, query.Nyse, 0)
  |> should.equal(Error(query.InvalidMaximumAssets))
}

pub fn asset_snapshot_preserves_provider_rows_flags_order_and_discrepancies_test() {
  let assert Ok(snapshot) =
    assets.decode_snapshot(asset_fixture(), for: asset_plan(2))
  let assert [first, second] = assets.rows(snapshot)
  assets.id(first) |> should.equal("asset-aapl")
  assets.asset_class(first) |> should.equal("us_equity")
  assets.exchange(first) |> should.equal("NASDAQ")
  assets.symbol(first) |> should.equal("AAPL")
  assets.name(first) |> should.equal("Apple Inc. Common Stock")
  assets.status(first) |> should.equal("active")
  assets.tradable(first) |> should.be_true
  assets.marginable(first) |> should.be_true
  assets.shortable(first) |> should.be_true
  assets.easy_to_borrow(first) |> should.be_true
  assets.fractionable(first) |> should.be_true
  assets.attributes(first) |> should.equal(["has_options"])

  // The active request and inactive returned row remain visible together. The
  // decoder does not decide whether the row is usable or discard it.
  assets.symbol(second) |> should.equal("MSFT")
  assets.status(second) |> should.equal("inactive")
  assets.tradable(second) |> should.be_false
  assets.attributes(second) |> should.equal([])
}

pub fn asset_snapshot_rejects_only_malformed_or_over_budget_structure_test() {
  assets.decode_snapshot(asset_fixture(), for: asset_plan(1))
  |> should.equal(Error(assets.TooManyAssets(1, 2)))
  assets.decode_snapshot(
    string.replace(asset_fixture(), "\"tradable\":true", "\"tradable\":\"yes\""),
    for: asset_plan(2),
  )
  |> should.be_error
}

pub fn quote_decoder_preserves_exact_tokens_and_market_codes_test() {
  let assert Ok(plan) = query.latest_quote("AAPL", query.Iex)
  let assert Ok(value) = quotes.decode(quote_fixture(), for: plan)
  quotes.bid_price(value) |> should.equal("189.1000")
  quotes.ask_price(value) |> should.equal("189.1200")
  quotes.bid_size(value) |> should.equal("7")
  quotes.ask_exchange(value) |> should.equal("V")
  quotes.conditions(value) |> should.equal(["R"])
  quotes.tape(value) |> should.equal("C")
  time.unix_milliseconds(quotes.at(value)) |> should.equal(1_722_974_399_123)
}

pub fn quote_decoder_rejects_symbol_timestamp_and_negative_values_test() {
  let assert Ok(plan) = query.latest_quote("AAPL", query.Iex)
  quotes.decode(
    string.replace(quote_fixture(), "\"AAPL\"", "\"MSFT\""),
    for: plan,
  )
  |> should.equal(Error(quotes.UnexpectedSymbols))
  quotes.decode(
    string.replace(quote_fixture(), "189.1000", "-189.1000"),
    for: plan,
  )
  |> should.be_error
  quotes.decode(
    string.replace(quote_fixture(), "19:59:59.123456789Z", "19:59:59+00:00"),
    for: plan,
  )
  |> should.be_error
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

fn asset_plan(maximum_assets: Int) -> query.AssetUniverseQuery {
  let assert Ok(value) =
    query.asset_universe(
      query.Paper,
      query.Active,
      query.Nasdaq,
      maximum_assets,
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

fn quote_fixture() -> String {
  "{\"quotes\":{\"AAPL\":{\"ap\":189.1200,\"as\":4,\"ax\":\"V\",\"bp\":189.1000,\"bs\":7,\"bx\":\"V\",\"c\":[\"R\"],\"t\":\"2024-08-06T19:59:59.123456789Z\",\"z\":\"C\"}}}"
}

fn asset_fixture() -> String {
  "[{\"id\":\"asset-aapl\",\"class\":\"us_equity\",\"exchange\":\"NASDAQ\",\"symbol\":\"AAPL\",\"name\":\"Apple Inc. Common Stock\",\"status\":\"active\",\"tradable\":true,\"marginable\":true,\"shortable\":true,\"easy_to_borrow\":true,\"fractionable\":true,\"attributes\":[\"has_options\"]},{\"id\":\"asset-msft\",\"class\":\"us_equity\",\"exchange\":\"NASDAQ\",\"symbol\":\"MSFT\",\"name\":\"Microsoft Corporation Common Stock\",\"status\":\"inactive\",\"tradable\":false,\"marginable\":false,\"shortable\":false,\"easy_to_borrow\":false,\"fractionable\":false}]"
}
