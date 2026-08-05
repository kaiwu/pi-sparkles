import finance_calendar/date
import finance_core/time
import finance_track
import gleam/list
import gleam/order.{Gt}
import gleam/string

pub type Market {
  CnSse
  CnSzse
  CnBse
  Hk
}

pub opaque type QuoteQuery {
  QuoteQuery(market: Market, code: String)
}

pub opaque type HistoryQuery {
  HistoryQuery(
    market: Market,
    code: String,
    start_date: time.Date,
    end_date: time.Date,
    limit: Int,
  )
}

pub opaque type IncomeQuery {
  IncomeQuery(
    track: finance_track.Track,
    market: Market,
    code: String,
    report_date: time.Date,
  )
}

pub type QueryError {
  InvalidCode
  TrackMarketMismatch
  InvalidDateRange
  InvalidLimit
}

pub fn quote(
  track track: finance_track.Track,
  market market: Market,
  code code: String,
) -> Result(QuoteQuery, QueryError) {
  case compatible(track, market), valid_code(market, code) {
    False, _ -> Error(TrackMarketMismatch)
    _, False -> Error(InvalidCode)
    True, True -> Ok(QuoteQuery(market, code))
  }
}

pub fn history(
  track track: finance_track.Track,
  market market: Market,
  code code: String,
  start_date start_date: time.Date,
  end_date end_date: time.Date,
  limit limit: Int,
) -> Result(HistoryQuery, QueryError) {
  case
    compatible(track, market),
    valid_code(market, code),
    date.compare(start_date, end_date),
    limit >= 1 && limit <= 1000
  {
    False, _, _, _ -> Error(TrackMarketMismatch)
    _, False, _, _ -> Error(InvalidCode)
    _, _, Gt, _ -> Error(InvalidDateRange)
    _, _, _, False -> Error(InvalidLimit)
    True, True, _, True ->
      Ok(HistoryQuery(market, code, start_date, end_date, limit))
  }
}

pub fn income_statement(
  track track: finance_track.Track,
  market market: Market,
  code code: String,
  report_date report_date: time.Date,
) -> Result(IncomeQuery, QueryError) {
  case compatible(track, market), valid_code(market, code) {
    False, _ -> Error(TrackMarketMismatch)
    _, False -> Error(InvalidCode)
    True, True -> Ok(IncomeQuery(track, market, code, report_date))
  }
}

pub fn quote_market(value: QuoteQuery) -> Market {
  value.market
}

pub fn quote_code(value: QuoteQuery) -> String {
  value.code
}

pub fn history_market(value: HistoryQuery) -> Market {
  value.market
}

pub fn history_code(value: HistoryQuery) -> String {
  value.code
}

pub fn history_start(value: HistoryQuery) -> time.Date {
  value.start_date
}

pub fn history_end(value: HistoryQuery) -> time.Date {
  value.end_date
}

pub fn history_limit(value: HistoryQuery) -> Int {
  value.limit
}

pub fn income_track(value: IncomeQuery) -> finance_track.Track {
  value.track
}

pub fn income_market(value: IncomeQuery) -> Market {
  value.market
}

pub fn income_code(value: IncomeQuery) -> String {
  value.code
}

pub fn income_report_date(value: IncomeQuery) -> time.Date {
  value.report_date
}

pub fn market_name(value: Market) -> String {
  case value {
    CnSse -> "cn_sse"
    CnSzse -> "cn_szse"
    CnBse -> "cn_bse"
    Hk -> "hk"
  }
}

pub fn secid(market: Market, code: String) -> String {
  case market {
    CnSse -> "1." <> code
    CnSzse | CnBse -> "0." <> code
    Hk -> "116." <> code
  }
}

fn compatible(track: finance_track.Track, market: Market) -> Bool {
  case track, market {
    finance_track.Cn, CnSse
    | finance_track.Cn, CnSzse
    | finance_track.Cn, CnBse
    | finance_track.Hk, Hk
    -> True
    _, _ -> False
  }
}

fn valid_code(market: Market, code: String) -> Bool {
  let expected = case market {
    Hk -> 5
    CnSse | CnSzse | CnBse -> 6
  }
  string.length(code) == expected
  && code
  |> string.to_graphemes
  |> list.all(fn(character) { string.contains("0123456789", character) })
}
