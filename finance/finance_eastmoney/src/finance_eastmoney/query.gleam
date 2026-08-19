import finance_calendar/date
import finance_core/time
import finance_track
import gleam/int
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

pub opaque type CnOverviewQuery {
  CnOverviewQuery
}

pub opaque type CnMoversQuery {
  CnMoversQuery(limit: Int)
}

pub opaque type CnSectorIndex {
  CnSectorIndex(
    market: Market,
    code: String,
    label: String,
    official_name: String,
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

pub fn cn_overview(
  track track: finance_track.Track,
) -> Result(CnOverviewQuery, QueryError) {
  case track {
    finance_track.Cn -> Ok(CnOverviewQuery)
    _ -> Error(TrackMarketMismatch)
  }
}

pub fn cn_overview_secids(_query: CnOverviewQuery) -> String {
  "1.000001,0.399001,0.399006,1.000300,1.000688"
}

pub fn cn_movers(
  track track: finance_track.Track,
  limit limit: Int,
) -> Result(CnMoversQuery, QueryError) {
  case track, limit >= 1 && limit <= 50 {
    finance_track.Cn, True -> Ok(CnMoversQuery(limit))
    finance_track.Cn, False -> Error(InvalidLimit)
    _, _ -> Error(TrackMarketMismatch)
  }
}

pub fn cn_movers_limit(query: CnMoversQuery) -> Int {
  query.limit
}

pub fn cn_movers_provider_filter(_query: CnMoversQuery) -> String {
  "m:0+t:6,m:0+t:80,m:1+t:2,m:1+t:23,m:0+t:81+s:2048"
}

pub fn cn_movers_profile_id(_query: CnMoversQuery) -> String {
  "eastmoney_cn_a_share_listing_categories_v1"
}

pub fn cn_movers_source_reference(query: CnMoversQuery) -> String {
  "https://push2.eastmoney.com/api/qt/clist/get?pn=1&pz="
  <> int.to_string(query.limit)
  <> "&po=1&np=1&fltt=2&invt=2&fid=f3&fs="
  <> cn_movers_provider_filter(query)
}

/// The pinned CSI 800 level-one industry profile used by the CN sector tool.
///
/// This is deliberately not the legacy ten-index projection: financials and
/// real estate remain separate, and the combined 000934 index is excluded.
pub fn cn_sector_indices() -> List(CnSectorIndex) {
  [
    CnSectorIndex(CnSse, "000928", "energy", "中证能源指数"),
    CnSectorIndex(CnSse, "000929", "materials", "中证原材料指数"),
    CnSectorIndex(CnSse, "000930", "industrials", "中证工业指数"),
    CnSectorIndex(CnSse, "000931", "consumer_discretionary", "中证可选消费指数"),
    CnSectorIndex(CnSse, "000932", "consumer_staples", "中证主要消费指数"),
    CnSectorIndex(CnSse, "000933", "health_care", "中证医药卫生指数"),
    CnSectorIndex(CnSse, "000974", "financials", "中证800金融指数"),
    CnSectorIndex(CnSzse, "399965", "real_estate", "中证800地产指数"),
    CnSectorIndex(CnSse, "000935", "information_technology", "中证信息技术指数"),
    CnSectorIndex(CnSse, "000936", "communication_services", "中证通信业务指数"),
    CnSectorIndex(CnSse, "000937", "utilities", "中证公用事业指数"),
  ]
}

pub fn cn_sector_profile_id() -> String {
  "csi_800_level_one_v1_3_pinned_2022_04"
}

pub fn cn_sector_profile_source() -> String {
  "https://oss-ch.csindex.com.cn/static/html/csindex/public/uploads/indices/detail/files/zh_CN/000841_Index_Methodology_cn.pdf"
}

pub fn cn_sector_market(value: CnSectorIndex) -> Market {
  value.market
}

pub fn cn_sector_code(value: CnSectorIndex) -> String {
  value.code
}

pub fn cn_sector_label(value: CnSectorIndex) -> String {
  value.label
}

pub fn cn_sector_official_name(value: CnSectorIndex) -> String {
  value.official_name
}

pub fn cn_sector_history(
  index: CnSectorIndex,
  start_date: time.Date,
  end_date: time.Date,
  limit: Int,
) -> Result(HistoryQuery, QueryError) {
  history(
    finance_track.Cn,
    index.market,
    index.code,
    start_date,
    end_date,
    limit,
  )
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

pub fn history_source_reference(value: HistoryQuery) -> String {
  "https://push2his.eastmoney.com/api/qt/stock/kline/get?secid="
  <> secid(value.market, value.code)
  <> "&klt=101&fqt=0&beg="
  <> compact_date(value.start_date)
  <> "&end="
  <> compact_date(value.end_date)
  <> "&lmt="
  <> int.to_string(value.limit)
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

fn compact_date(value: time.Date) -> String {
  let #(year, month, day) = time.date_parts(value)
  int.to_string(year) <> two_digits(month) <> two_digits(day)
}

fn two_digits(value: Int) -> String {
  case value < 10 {
    True -> "0" <> int.to_string(value)
    False -> int.to_string(value)
  }
}
