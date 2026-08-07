import finance_calendar/date
import finance_core/time.{type Date}
import gleam/int
import gleam/list
import gleam/order.{Gt}
import gleam/string

pub type Feed {
  Iex
  Sip
}

/// The caller-selected Alpaca Trading API environment for read-only asset
/// discovery. No environment is a fallback for another.
pub type TradingEnvironment {
  Paper
  Live
}

pub type AssetStatusFilter {
  Active
  Inactive
  AllStatuses
}

pub type AssetExchange {
  Amex
  Arca
  Bats
  Nyse
  Nasdaq
  NyseArca
  Otc
}

pub opaque type DailyBarsQuery {
  DailyBarsQuery(
    symbol: String,
    start_date: Date,
    end_date: Date,
    as_of_date: Date,
    feed: Feed,
    page_size: Int,
    maximum_pages: Int,
    maximum_bars: Int,
  )
}

pub opaque type LatestQuoteQuery {
  LatestQuoteQuery(symbol: String, feed: Feed)
}

pub opaque type AssetUniverseQuery {
  AssetUniverseQuery(
    environment: TradingEnvironment,
    status: AssetStatusFilter,
    exchange: AssetExchange,
    maximum_assets: Int,
  )
}

pub type QueryError {
  InvalidSymbol
  InvalidDateRange
  InvalidPageSize
  InvalidMaximumPages
  InvalidMaximumBars
  InvalidMaximumAssets
}

pub fn daily_bars(
  symbol symbol: String,
  start_date start_date: Date,
  end_date end_date: Date,
  as_of_date as_of_date: Date,
  feed feed: Feed,
  page_size page_size: Int,
  maximum_pages maximum_pages: Int,
  maximum_bars maximum_bars: Int,
) -> Result(DailyBarsQuery, QueryError) {
  case
    valid_symbol(symbol),
    date.compare(start_date, end_date),
    page_size >= 1 && page_size <= 1000,
    maximum_pages >= 1 && maximum_pages <= 10,
    maximum_bars >= 1 && maximum_bars <= 5000
  {
    False, _, _, _, _ -> Error(InvalidSymbol)
    _, Gt, _, _, _ -> Error(InvalidDateRange)
    _, _, False, _, _ -> Error(InvalidPageSize)
    _, _, _, False, _ -> Error(InvalidMaximumPages)
    _, _, _, _, False -> Error(InvalidMaximumBars)
    True, _, True, True, True ->
      Ok(DailyBarsQuery(
        symbol,
        start_date,
        end_date,
        as_of_date,
        feed,
        page_size,
        maximum_pages,
        maximum_bars,
      ))
  }
}

pub fn latest_quote(
  symbol symbol: String,
  feed feed: Feed,
) -> Result(LatestQuoteQuery, QueryError) {
  case valid_symbol(symbol) {
    True -> Ok(LatestQuoteQuery(symbol, feed))
    False -> Error(InvalidSymbol)
  }
}

pub fn asset_universe(
  environment environment_value: TradingEnvironment,
  status status_value: AssetStatusFilter,
  exchange exchange_value: AssetExchange,
  maximum_assets maximum_asset_count: Int,
) -> Result(AssetUniverseQuery, QueryError) {
  case maximum_asset_count >= 1 && maximum_asset_count <= 20_000 {
    True ->
      Ok(AssetUniverseQuery(
        environment_value,
        status_value,
        exchange_value,
        maximum_asset_count,
      ))
    False -> Error(InvalidMaximumAssets)
  }
}

pub fn asset_environment(value: AssetUniverseQuery) -> TradingEnvironment {
  value.environment
}

pub fn asset_status(value: AssetUniverseQuery) -> AssetStatusFilter {
  value.status
}

pub fn asset_exchange(value: AssetUniverseQuery) -> AssetExchange {
  value.exchange
}

pub fn maximum_assets(value: AssetUniverseQuery) -> Int {
  value.maximum_assets
}

pub fn trading_origin(value: TradingEnvironment) -> String {
  case value {
    Paper -> "https://paper-api.alpaca.markets"
    Live -> "https://api.alpaca.markets"
  }
}

pub fn asset_status_name(value: AssetStatusFilter) -> String {
  case value {
    Active -> "active"
    Inactive -> "inactive"
    AllStatuses -> "all"
  }
}

pub fn asset_exchange_name(value: AssetExchange) -> String {
  case value {
    Amex -> "AMEX"
    Arca -> "ARCA"
    Bats -> "BATS"
    Nyse -> "NYSE"
    Nasdaq -> "NASDAQ"
    NyseArca -> "NYSEARCA"
    Otc -> "OTC"
  }
}

pub fn quote_symbol(value: LatestQuoteQuery) -> String {
  value.symbol
}

pub fn quote_feed(value: LatestQuoteQuery) -> Feed {
  value.feed
}

pub fn symbol(value: DailyBarsQuery) -> String {
  value.symbol
}

pub fn start_date(value: DailyBarsQuery) -> Date {
  value.start_date
}

pub fn end_date(value: DailyBarsQuery) -> Date {
  value.end_date
}

pub fn as_of_date(value: DailyBarsQuery) -> Date {
  value.as_of_date
}

pub fn feed(value: DailyBarsQuery) -> Feed {
  value.feed
}

pub fn feed_name(value: Feed) -> String {
  case value {
    Iex -> "iex"
    Sip -> "sip"
  }
}

pub fn page_size(value: DailyBarsQuery) -> Int {
  value.page_size
}

pub fn maximum_pages(value: DailyBarsQuery) -> Int {
  value.maximum_pages
}

pub fn maximum_bars(value: DailyBarsQuery) -> Int {
  value.maximum_bars
}

/// Stable evidence reference for the exact daily-bars plan. Runtime-only page
/// tokens and caller budgets are deliberately excluded from source identity.
pub fn daily_bars_source_reference(value: DailyBarsQuery) -> String {
  "https://data.alpaca.markets/v2/stocks/bars?symbols="
  <> symbol(value)
  <> "&timeframe=1Day&start="
  <> date_text(start_date(value))
  <> "&end="
  <> date_text(end_date(value))
  <> "&adjustment=raw&feed="
  <> feed_name(feed(value))
  <> "&currency=USD&sort=asc&asof="
  <> date_text(as_of_date(value))
}

/// Stable evidence reference for the exact read-only asset-universe request.
/// Alpaca exposes no historical as-of parameter on this endpoint.
pub fn asset_universe_source_reference(value: AssetUniverseQuery) -> String {
  trading_origin(asset_environment(value))
  <> "/v2/assets?status="
  <> asset_status_name(asset_status(value))
  <> "&asset_class=us_equity&exchange="
  <> asset_exchange_name(asset_exchange(value))
}

pub fn date_text(value: Date) -> String {
  let #(year, month, day) = time.date_parts(value)
  int_text(year) <> "-" <> two_digits(month) <> "-" <> two_digits(day)
}

fn valid_symbol(value: String) -> Bool {
  value != ""
  && value == string.uppercase(value)
  && string.length(value) <= 20
  && {
    value
    |> string.to_graphemes
    |> list.all(fn(character) {
      string.contains("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-", character)
    })
  }
}

fn two_digits(value: Int) -> String {
  case value < 10 {
    True -> "0" <> int_text(value)
    False -> int_text(value)
  }
}

fn int_text(value: Int) -> String {
  int.to_string(value)
}
