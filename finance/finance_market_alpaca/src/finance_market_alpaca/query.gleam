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

pub type QueryError {
  InvalidSymbol
  InvalidDateRange
  InvalidPageSize
  InvalidMaximumPages
  InvalidMaximumBars
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
