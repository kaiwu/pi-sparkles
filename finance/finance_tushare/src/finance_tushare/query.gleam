import finance_calendar/date
import finance_core/time
import finance_track
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{Gt}
import gleam/string

pub type Exchange {
  Sse
  Szse
  Bse
}

pub type ListStatus {
  Listed
  Delisted
  Paused
}

pub opaque type StockBasicQuery {
  StockBasicQuery(
    exchange: Option(Exchange),
    code: Option(String),
    name: Option(String),
    list_status: ListStatus,
    limit: Int,
  )
}

pub opaque type DailyQuery {
  DailyQuery(
    exchange: Exchange,
    code: String,
    start_date: time.Date,
    end_date: time.Date,
    limit: Int,
  )
}

pub opaque type DatedSecurityQuery {
  DatedSecurityQuery(
    exchange: Exchange,
    code: String,
    start_date: time.Date,
    end_date: time.Date,
    limit: Int,
  )
}

pub opaque type SecurityQuery {
  SecurityQuery(exchange: Exchange, code: String, limit: Int)
}

pub type QueryError {
  TrackMismatch
  InvalidCode
  ExchangeRequiredForCode
  InvalidDateRange
  InvalidLimit
}

pub fn stock_basic(
  track track: finance_track.Track,
  exchange exchange: Option(Exchange),
  code code: Option(String),
  list_status list_status: ListStatus,
  limit limit: Int,
) -> Result(StockBasicQuery, QueryError) {
  case track, code, exchange, valid_limit(limit, 6000) {
    finance_track.Cn, Some(_), None, _ -> Error(ExchangeRequiredForCode)
    finance_track.Cn, Some(code), Some(exchange), True ->
      case valid_code(code) {
        True ->
          Ok(StockBasicQuery(
            Some(exchange),
            Some(code),
            None,
            list_status,
            limit,
          ))
        False -> Error(InvalidCode)
      }
    finance_track.Cn, None, _, True ->
      Ok(StockBasicQuery(exchange, None, None, list_status, limit))
    finance_track.Cn, _, _, False -> Error(InvalidLimit)
    _, _, _, _ -> Error(TrackMismatch)
  }
}

pub fn stock_basic_name(
  track track: finance_track.Track,
  exchange exchange: Option(Exchange),
  name name: String,
  list_status list_status: ListStatus,
  limit limit: Int,
) -> Result(StockBasicQuery, QueryError) {
  case track == finance_track.Cn, valid_name(name), valid_limit(limit, 6000) {
    False, _, _ -> Error(TrackMismatch)
    _, False, _ -> Error(InvalidCode)
    _, _, False -> Error(InvalidLimit)
    True, True, True ->
      Ok(StockBasicQuery(exchange, None, Some(name), list_status, limit))
  }
}

pub fn daily(
  track track: finance_track.Track,
  exchange exchange: Exchange,
  code code: String,
  start_date start_date: time.Date,
  end_date end_date: time.Date,
  limit limit: Int,
) -> Result(DailyQuery, QueryError) {
  case
    track,
    valid_code(code),
    date.compare(start_date, end_date),
    valid_limit(limit, 6000)
  {
    finance_track.Cn, True, order, True if order != Gt ->
      Ok(DailyQuery(exchange, code, start_date, end_date, limit))
    finance_track.Cn, False, _, _ -> Error(InvalidCode)
    finance_track.Cn, _, Gt, _ -> Error(InvalidDateRange)
    finance_track.Cn, _, _, False -> Error(InvalidLimit)
    _, _, _, _ -> Error(TrackMismatch)
  }
}

pub fn dated_security(
  track track: finance_track.Track,
  exchange exchange: Exchange,
  code code: String,
  start_date start_date: time.Date,
  end_date end_date: time.Date,
  limit limit: Int,
) -> Result(DatedSecurityQuery, QueryError) {
  case
    track,
    valid_code(code),
    date.compare(start_date, end_date),
    valid_limit(limit, 3500)
  {
    finance_track.Cn, True, order, True if order != Gt ->
      Ok(DatedSecurityQuery(exchange, code, start_date, end_date, limit))
    finance_track.Cn, False, _, _ -> Error(InvalidCode)
    finance_track.Cn, _, Gt, _ -> Error(InvalidDateRange)
    finance_track.Cn, _, _, False -> Error(InvalidLimit)
    _, _, _, _ -> Error(TrackMismatch)
  }
}

pub fn security(
  track track: finance_track.Track,
  exchange exchange: Exchange,
  code code: String,
  limit limit: Int,
) -> Result(SecurityQuery, QueryError) {
  case track, valid_code(code), valid_limit(limit, 6000) {
    finance_track.Cn, True, True -> Ok(SecurityQuery(exchange, code, limit))
    finance_track.Cn, False, _ -> Error(InvalidCode)
    finance_track.Cn, _, False -> Error(InvalidLimit)
    _, _, _ -> Error(TrackMismatch)
  }
}

pub fn stock_basic_exchange(value: StockBasicQuery) -> Option(Exchange) {
  value.exchange
}

pub fn stock_basic_code(value: StockBasicQuery) -> Option(String) {
  value.code
}

pub fn stock_basic_name_query(value: StockBasicQuery) -> Option(String) {
  value.name
}

pub fn stock_basic_status(value: StockBasicQuery) -> ListStatus {
  value.list_status
}

pub fn stock_basic_limit(value: StockBasicQuery) -> Int {
  value.limit
}

pub fn daily_exchange(value: DailyQuery) -> Exchange {
  value.exchange
}

pub fn daily_code(value: DailyQuery) -> String {
  value.code
}

pub fn daily_start(value: DailyQuery) -> time.Date {
  value.start_date
}

pub fn daily_end(value: DailyQuery) -> time.Date {
  value.end_date
}

pub fn daily_limit(value: DailyQuery) -> Int {
  value.limit
}

/// Credential-free reference for receipts and diagnostics.
pub fn daily_source_reference(value: DailyQuery) -> String {
  "https://api.tushare.pro/?api_name=daily&ts_code="
  <> ts_code(value.exchange, value.code)
  <> "&start_date="
  <> compact_date(value.start_date)
  <> "&end_date="
  <> compact_date(value.end_date)
}

pub fn dated_exchange(value: DatedSecurityQuery) -> Exchange {
  value.exchange
}

pub fn dated_code(value: DatedSecurityQuery) -> String {
  value.code
}

pub fn dated_start(value: DatedSecurityQuery) -> time.Date {
  value.start_date
}

pub fn dated_end(value: DatedSecurityQuery) -> time.Date {
  value.end_date
}

pub fn dated_limit(value: DatedSecurityQuery) -> Int {
  value.limit
}

pub fn security_exchange(value: SecurityQuery) -> Exchange {
  value.exchange
}

pub fn security_code(value: SecurityQuery) -> String {
  value.code
}

pub fn security_limit(value: SecurityQuery) -> Int {
  value.limit
}

pub fn dated_source_reference(
  value: DatedSecurityQuery,
  api_name: String,
) -> String {
  "https://api.tushare.pro/?api_name="
  <> api_name
  <> "&ts_code="
  <> ts_code(value.exchange, value.code)
  <> "&start_date="
  <> compact_date(value.start_date)
  <> "&end_date="
  <> compact_date(value.end_date)
}

pub fn security_source_reference(
  value: SecurityQuery,
  api_name: String,
) -> String {
  "https://api.tushare.pro/?api_name="
  <> api_name
  <> "&ts_code="
  <> ts_code(value.exchange, value.code)
}

pub fn ts_code(exchange: Exchange, code: String) -> String {
  code <> "." <> exchange_suffix(exchange)
}

pub fn exchange_name(value: Exchange) -> String {
  case value {
    Sse -> "SSE"
    Szse -> "SZSE"
    Bse -> "BSE"
  }
}

pub fn exchange_suffix(value: Exchange) -> String {
  case value {
    Sse -> "SH"
    Szse -> "SZ"
    Bse -> "BJ"
  }
}

pub fn list_status_name(value: ListStatus) -> String {
  case value {
    Listed -> "L"
    Delisted -> "D"
    Paused -> "P"
  }
}

pub fn compact_date(value: time.Date) -> String {
  let #(year, month, day) = time.date_parts(value)
  int.to_string(year) <> two_digits(month) <> two_digits(day)
}

fn valid_limit(value: Int, maximum: Int) -> Bool {
  value >= 1 && value <= maximum
}

fn valid_code(value: String) -> Bool {
  string.length(value) == 6
  && value
  |> string.to_graphemes
  |> list.all(fn(character) { string.contains("0123456789", character) })
}

fn valid_name(value: String) -> Bool {
  value != ""
  && string.trim(value) == value
  && string.length(value) <= 100
  && !string.contains(value, "\r")
  && !string.contains(value, "\n")
}

fn two_digits(value: Int) -> String {
  case value < 10 {
    True -> "0" <> int.to_string(value)
    False -> int.to_string(value)
  }
}
