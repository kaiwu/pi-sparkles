import finance_core/time
import finance_http/request
import finance_market_alpaca
import finance_market_alpaca/assets
import finance_market_alpaca/bars
import finance_market_alpaca/corporate_actions
import finance_market_alpaca/news
import finance_market_alpaca/query
import finance_market_alpaca/quotes
import finance_market_alpaca/request as provider_request
import gleam/list
import gleam/option.{None, Some}
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

pub fn news_query_requires_exact_utc_range_symbol_and_budgets_test() {
  let assert Ok(value) =
    news.query(
      "AAPL",
      "2026-07-01T00:00:00Z",
      "2026-07-31T23:59:59.999Z",
      50,
      2,
      80,
    )
  value.symbol |> should.equal("AAPL")
  value.maximum_articles |> should.equal(80)

  news.query("aapl", "2026-07-01T00:00:00Z", "2026-07-02T00:00:00Z", 50, 2, 80)
  |> should.equal(Error(news.InvalidSymbol))
  news.query(
    "AAPL",
    "2026-07-01T00:00:00+08:00",
    "2026-07-02T00:00:00Z",
    50,
    2,
    80,
  )
  |> should.equal(Error(news.InvalidStartTimestamp))
  news.query("AAPL", "2026-01-01T00:00:00Z", "2026-02-02T00:00:00Z", 50, 2, 80)
  |> should.equal(Error(news.RangeTooLarge))
}

pub fn news_request_is_metadata_only_ascending_bounded_and_secret_test() {
  let plan = news_plan()
  let assert Ok(value) = provider_request.news(access(), plan, 20, Some("next"))
  request.path(value) |> should.equal(provider_request.news_path)
  request.maximum_response_bytes(value) |> should.equal(2_000_000)
  [
    request.QueryParameter("start", plan.start_at, request.Public),
    request.QueryParameter("end", plan.end_at, request.Public),
    request.QueryParameter("sort", "asc", request.Public),
    request.QueryParameter("symbols", "AAPL", request.Public),
    request.QueryParameter("limit", "20", request.Public),
    request.QueryParameter("include_content", "false", request.Public),
    request.QueryParameter("exclude_contentless", "false", request.Public),
    request.QueryParameter("page_token", "next", request.Public),
  ]
  |> list.all(fn(expected) { request.query(value) |> list.contains(expected) })
  |> should.be_true
  request.safe_key(value)
  |> string.contains("secret-key")
  |> should.be_false
}

pub fn news_decoder_preserves_metadata_and_withholds_text_payload_shape_test() {
  let body =
    "{\"news\":[{\"id\":101,\"headline\":\"Exact headline\",\"summary\":\"Licensed summary\",\"author\":\"Benzinga Newsdesk\",\"created_at\":\"2026-07-02T10:00:00.123456Z\",\"updated_at\":\"2026-07-02T10:01:00Z\",\"url\":\"https://www.benzinga.com/news/101\",\"symbols\":[\"AAPL\",\"MSFT\"],\"source\":\"benzinga\",\"images\":[{\"size\":\"small\",\"url\":\"https://example.test/image\"}]}],\"next_page_token\":null}"
  let assert Ok(page) = news.decode_page(body, news_plan(), 10)
  let assert [article] = page.articles
  article.id |> should.equal(101)
  article.headline |> should.equal("Exact headline")
  article.created_at |> should.equal("2026-07-02T10:00:00.123456Z")
  article.summary_present |> should.be_true
  article.content_present |> should.be_false
  article.image_count |> should.equal(1)
  page.next_page_token |> should.equal(None)
}

pub fn news_decoder_fails_closed_on_source_identity_order_and_shape_test() {
  let wrong_source =
    "{\"news\":[{\"id\":101,\"headline\":\"Exact headline\",\"author\":\"Desk\",\"created_at\":\"2026-07-02T10:00:00Z\",\"updated_at\":\"2026-07-02T10:01:00Z\",\"url\":\"https://example.test/101\",\"symbols\":[\"AAPL\"],\"source\":\"unknown\"}],\"next_page_token\":null}"
  news.decode_page(wrong_source, news_plan(), 10)
  |> should.equal(Error(news.UnexpectedSource(101, "unknown")))

  let missing_symbol =
    string.replace(wrong_source, "\"AAPL\"", "\"MSFT\"")
    |> string.replace("\"unknown\"", "\"benzinga\"")
  news.decode_page(missing_symbol, news_plan(), 10)
  |> should.equal(Error(news.MissingQuerySymbol(101)))

  let unknown_shape =
    string.replace(
      string.replace(wrong_source, "\"unknown\"", "\"benzinga\""),
      "\"next_page_token\":null",
      "\"next_page_token\":null,\"unexpected\":true",
    )
  case news.decode_page(unknown_shape, news_plan(), 10) {
    Error(news.InvalidJson(_)) -> Nil
    _ -> should.fail()
  }
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

pub fn corporate_actions_query_and_request_are_exact_us_process_date_scope_test() {
  corporate_actions.query(
    "aapl",
    "037833100",
    civil(2024, 8, 1),
    civil(2024, 8, 5),
    [corporate_actions.CashDividendType],
    corporate_actions.Complete,
    100,
    2,
    200,
  )
  |> should.equal(Error(corporate_actions.InvalidSymbol))
  corporate_actions.query(
    "AAPL",
    "037833100",
    civil(2024, 8, 1),
    civil(2024, 8, 5),
    [
      corporate_actions.CashDividendType,
      corporate_actions.CashDividendType,
    ],
    corporate_actions.Complete,
    100,
    2,
    200,
  )
  |> should.equal(
    Error(corporate_actions.DuplicateType(corporate_actions.CashDividendType)),
  )

  let plan = corporate_plan(corporate_actions.All)
  let assert Ok(value) =
    provider_request.corporate_actions(access(), plan, 5, Some("page-two"))
  request.origin(value) |> should.equal(provider_request.origin)
  request.path(value) |> should.equal(provider_request.corporate_actions_path)
  request.maximum_response_bytes(value) |> should.equal(5_000_000)
  [
    request.QueryParameter("symbols", "AAPL", request.Public),
    request.QueryParameter("cusips", "037833100", request.Public),
    request.QueryParameter(
      "types",
      "cash_dividend,stock_dividend,forward_split,reverse_split,name_change",
      request.Public,
    ),
    request.QueryParameter("region", "us", request.Public),
    request.QueryParameter("start", "2024-08-01", request.Public),
    request.QueryParameter("end", "2024-08-05", request.Public),
    request.QueryParameter("limit", "5", request.Public),
    request.QueryParameter("data_quality", "all", request.Public),
    request.QueryParameter("sort", "asc", request.Public),
    request.QueryParameter("page_token", "page-two", request.Public),
  ]
  |> list.all(fn(expected) { request.query(value) |> list.contains(expected) })
  |> should.be_true
}

pub fn corporate_actions_decoder_preserves_source_fields_and_numeric_lexemes_test() {
  let assert Ok(page) =
    corporate_actions.decode_page(
      corporate_actions_fixture(),
      corporate_plan(corporate_actions.All),
      5,
    )
  page.next_page_token |> should.equal(Some("next-actions"))
  let assert [cash] = page.cash_dividends
  cash.id |> should.equal("cash-1")
  cash.rate |> should.equal(Some("0.2400"))
  cash.currency |> should.equal(Some("USD"))
  cash.due_bill_on_date |> should.equal(Some("2024-08-01"))
  let assert [stock] = page.stock_dividends
  stock.rate |> should.equal(Some("0.050"))
  let assert [forward] = page.forward_splits
  forward.old_rate |> should.equal(Some("1"))
  forward.new_rate |> should.equal(Some("4.000"))
  let assert [reverse] = page.reverse_splits
  reverse.symbol |> should.equal(Some("AAPL"))
  reverse.new_symbol |> should.equal(Some("APLC"))
  reverse.old_cusip |> should.equal(Some("037833100"))
  reverse.new_cusip |> should.equal(Some("037833209"))
  let assert [name_change] = page.name_changes
  name_change.old_symbol |> should.equal(Some("AAPL"))
  name_change.new_symbol |> should.equal(Some("APPL"))
  name_change.currency |> should.equal(Some(""))
}

pub fn corporate_actions_decoder_rejects_drift_scope_and_budget_violations_test() {
  let fixture = corporate_actions_fixture()
  corporate_actions.decode_page(
    fixture,
    corporate_plan(corporate_actions.All),
    4,
  )
  |> should.equal(Error(corporate_actions.TooManyActions(4, 5)))
  corporate_actions.decode_page(fixture, cash_only_corporate_plan(), 5)
  |> should.equal(
    Error(corporate_actions.UnexpectedActionType(
      corporate_actions.StockDividendType,
    )),
  )
  corporate_actions.decode_page(
    string.replace(fixture, "2024-08-01", "2024-8-1"),
    corporate_plan(corporate_actions.All),
    5,
  )
  |> should.be_error
  corporate_actions.decode_page(
    string.replace(fixture, "0.2400", "\"0.2400\""),
    corporate_plan(corporate_actions.All),
    5,
  )
  |> should.be_error
  corporate_actions.decode_page(
    string.replace(fixture, "2024-08-05", "2024-08-06"),
    corporate_plan(corporate_actions.All),
    5,
  )
  |> should.equal(Error(corporate_actions.ProcessDateOutsideRange))
  corporate_actions.decode_page(
    string.replace(fixture, "name_changes", "cash_mergers"),
    corporate_plan(corporate_actions.All),
    5,
  )
  |> should.be_error
  corporate_actions.decode_page(
    string.replace(
      fixture,
      "{\"corporate_actions\":",
      "{\"metadata\":{},\"corporate_actions\":",
    ),
    corporate_plan(corporate_actions.All),
    5,
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

fn news_plan() -> news.Query {
  let assert Ok(value) =
    news.query(
      "AAPL",
      "2026-07-01T00:00:00Z",
      "2026-07-31T23:59:59.999Z",
      50,
      2,
      80,
    )
  value
}

fn corporate_plan(
  data_quality: corporate_actions.DataQuality,
) -> corporate_actions.Query {
  let assert Ok(value) =
    corporate_actions.query(
      "AAPL",
      "037833100",
      civil(2024, 8, 1),
      civil(2024, 8, 5),
      [
        corporate_actions.CashDividendType,
        corporate_actions.StockDividendType,
        corporate_actions.ForwardSplitType,
        corporate_actions.ReverseSplitType,
        corporate_actions.NameChangeType,
      ],
      data_quality,
      100,
      2,
      200,
    )
  value
}

fn cash_only_corporate_plan() -> corporate_actions.Query {
  let assert Ok(value) =
    corporate_actions.query(
      "AAPL",
      "037833100",
      civil(2024, 8, 1),
      civil(2024, 8, 5),
      [corporate_actions.CashDividendType],
      corporate_actions.Complete,
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

fn quote_fixture() -> String {
  "{\"quotes\":{\"AAPL\":{\"ap\":189.1200,\"as\":4,\"ax\":\"V\",\"bp\":189.1000,\"bs\":7,\"bx\":\"V\",\"c\":[\"R\"],\"t\":\"2024-08-06T19:59:59.123456789Z\",\"z\":\"C\"}}}"
}

fn asset_fixture() -> String {
  "[{\"id\":\"asset-aapl\",\"class\":\"us_equity\",\"exchange\":\"NASDAQ\",\"symbol\":\"AAPL\",\"name\":\"Apple Inc. Common Stock\",\"status\":\"active\",\"tradable\":true,\"marginable\":true,\"shortable\":true,\"easy_to_borrow\":true,\"fractionable\":true,\"attributes\":[\"has_options\"]},{\"id\":\"asset-msft\",\"class\":\"us_equity\",\"exchange\":\"NASDAQ\",\"symbol\":\"MSFT\",\"name\":\"Microsoft Corporation Common Stock\",\"status\":\"inactive\",\"tradable\":false,\"marginable\":false,\"shortable\":false,\"easy_to_borrow\":false,\"fractionable\":false}]"
}

fn corporate_actions_fixture() -> String {
  "{\"corporate_actions\":{\"cash_dividends\":[{\"id\":\"cash-1\",\"symbol\":\"AAPL\",\"cusip\":\"037833100\",\"isin\":\"US0378331005\",\"rate\":0.2400,\"special\":false,\"foreign\":false,\"process_date\":\"2024-08-01\",\"ex_date\":\"2024-08-01\",\"record_date\":\"2024-08-02\",\"payable_date\":\"2024-08-08\",\"due_bill_on_date\":\"2024-08-01\",\"due_bill_off_date\":null,\"currency\":\"USD\",\"sub_type\":null}],\"stock_dividends\":[{\"id\":\"stock-1\",\"symbol\":\"AAPL\",\"cusip\":\"037833100\",\"rate\":0.050,\"process_date\":\"2024-08-02\",\"ex_date\":\"2024-08-02\"}],\"forward_splits\":[{\"id\":\"forward-1\",\"symbol\":\"AAPL\",\"cusip\":\"037833100\",\"old_rate\":1,\"new_rate\":4.000,\"process_date\":\"2024-08-03\",\"ex_date\":\"2024-08-03\"}],\"reverse_splits\":[{\"id\":\"reverse-1\",\"symbol\":\"AAPL\",\"new_symbol\":\"APLC\",\"old_cusip\":\"037833100\",\"new_cusip\":\"037833209\",\"old_rate\":10,\"new_rate\":1,\"process_date\":\"2024-08-04\",\"ex_date\":\"2024-08-04\"}],\"name_changes\":[{\"id\":\"name-1\",\"old_symbol\":\"AAPL\",\"new_symbol\":\"APPL\",\"old_cusip\":\"037833100\",\"new_cusip\":\"037833308\",\"process_date\":\"2024-08-05\",\"currency\":\"\"}]},\"next_page_token\":\"next-actions\"}"
}
