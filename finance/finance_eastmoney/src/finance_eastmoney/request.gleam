import finance_core/time
import finance_eastmoney.{type Access}
import finance_eastmoney/query as market_query
import finance_http/request
import gleam/int
import gleam/option.{None}
import gleam/result

pub const quote_origin = "https://push2.eastmoney.com"

pub const history_origin = "https://push2his.eastmoney.com"

pub const cn_fundamentals_origin = "https://datacenter-web.eastmoney.com"

pub const hk_fundamentals_origin = "https://datacenter.eastmoney.com"

pub const quote_path = "/api/qt/stock/get"

pub const cn_overview_path = "/api/qt/ulist.np/get"

pub const cn_movers_path = "/api/qt/clist/get"

pub const history_path = "/api/qt/stock/kline/get"

pub const cn_fundamentals_path = "/api/data/v1/get"

pub const hk_fundamentals_path = "/securities/api/data/v1/get"

pub type RequestError {
  InvalidHttp(request.RequestError)
  InvalidAccess(finance_eastmoney.AccessError)
}

pub fn quote(
  access: Access,
  plan: market_query.QuoteQuery,
) -> Result(request.Request, RequestError) {
  use base <- result.try(base_request(quote_origin, quote_path, 100_000))
  use value <- result.try(public_query(
    base,
    "secid",
    market_query.secid(
      market_query.quote_market(plan),
      market_query.quote_code(plan),
    ),
  ))
  use value <- result.try(public_query(value, "fltt", "1"))
  use value <- result.try(public_query(value, "invt", "2"))
  use value <- result.try(public_query(
    value,
    "fields",
    "f43,f44,f45,f46,f47,f51,f52,f57,f58,f59,f60,f86",
  ))
  finance_eastmoney.authorize(access, value) |> result.map_error(InvalidAccess)
}

pub fn cn_overview(
  access: Access,
  plan: market_query.CnOverviewQuery,
) -> Result(request.Request, RequestError) {
  use base <- result.try(base_request(quote_origin, cn_overview_path, 200_000))
  use value <- result.try(public_query(base, "fltt", "1"))
  use value <- result.try(public_query(value, "invt", "2"))
  use value <- result.try(public_query(
    value,
    "secids",
    market_query.cn_overview_secids(plan),
  ))
  use value <- result.try(public_query(
    value,
    "fields",
    "f2,f3,f4,f5,f6,f12,f13,f14,f15,f16,f17,f18,f104,f105,f106",
  ))
  finance_eastmoney.authorize(access, value) |> result.map_error(InvalidAccess)
}

pub fn cn_movers(
  access: Access,
  plan: market_query.CnMoversQuery,
) -> Result(request.Request, RequestError) {
  use base <- result.try(base_request(quote_origin, cn_movers_path, 250_000))
  use value <- result.try(public_query(base, "pn", "1"))
  use value <- result.try(public_query(
    value,
    "pz",
    int.to_string(market_query.cn_movers_limit(plan)),
  ))
  use value <- result.try(public_query(value, "po", "1"))
  use value <- result.try(public_query(value, "np", "1"))
  use value <- result.try(public_query(value, "fltt", "2"))
  use value <- result.try(public_query(value, "invt", "2"))
  use value <- result.try(public_query(value, "fid", "f3"))
  use value <- result.try(public_query(
    value,
    "fs",
    market_query.cn_movers_provider_filter(plan),
  ))
  use value <- result.try(public_query(
    value,
    "fields",
    "f2,f3,f4,f5,f6,f8,f12,f13,f14,f15,f16,f17,f18,f20,f21",
  ))
  finance_eastmoney.authorize(access, value) |> result.map_error(InvalidAccess)
}

pub fn history(
  access: Access,
  plan: market_query.HistoryQuery,
) -> Result(request.Request, RequestError) {
  use base <- result.try(base_request(history_origin, history_path, 2_000_000))
  use value <- result.try(public_query(
    base,
    "secid",
    market_query.secid(
      market_query.history_market(plan),
      market_query.history_code(plan),
    ),
  ))
  use value <- result.try(public_query(value, "fields1", "f1,f2,f3,f4,f5,f6"))
  use value <- result.try(public_query(
    value,
    "fields2",
    "f51,f52,f53,f54,f55,f56,f57,f58,f59,f60,f61",
  ))
  use value <- result.try(public_query(value, "klt", "101"))
  use value <- result.try(public_query(value, "fqt", "0"))
  use value <- result.try(public_query(
    value,
    "beg",
    compact_date(market_query.history_start(plan)),
  ))
  use value <- result.try(public_query(
    value,
    "end",
    compact_date(market_query.history_end(plan)),
  ))
  use value <- result.try(public_query(
    value,
    "lmt",
    int.to_string(market_query.history_limit(plan)),
  ))
  finance_eastmoney.authorize(access, value) |> result.map_error(InvalidAccess)
}

pub fn cn_income_statement(
  access: Access,
  plan: market_query.IncomeQuery,
) -> Result(request.Request, RequestError) {
  use base <- result.try(base_request(
    cn_fundamentals_origin,
    cn_fundamentals_path,
    250_000,
  ))
  use value <- result.try(public_query(base, "reportName", "RPT_DMSK_FN_INCOME"))
  use value <- result.try(public_query(
    value,
    "columns",
    "SECUCODE,SECURITY_CODE,SECURITY_NAME_ABBR,ORG_CODE,DATE_TYPE_CODE,REPORT_TYPE_CODE,DATA_STATE,NOTICE_DATE,REPORT_DATE,PARENT_NETPROFIT,TOTAL_OPERATE_INCOME",
  ))
  use value <- result.try(public_query(value, "pageNumber", "1"))
  use value <- result.try(public_query(value, "pageSize", "2"))
  use value <- result.try(public_query(value, "sortColumns", "NOTICE_DATE"))
  use value <- result.try(public_query(value, "sortTypes", "-1"))
  use value <- result.try(public_query(
    value,
    "filter",
    "(SECURITY_CODE=\""
      <> market_query.income_code(plan)
      <> "\")(REPORT_DATE='"
      <> date_text(market_query.income_report_date(plan))
      <> "')",
  ))
  finance_eastmoney.authorize(access, value) |> result.map_error(InvalidAccess)
}

pub fn hk_income_context(
  access: Access,
  plan: market_query.IncomeQuery,
) -> Result(request.Request, RequestError) {
  use base <- result.try(base_request(
    hk_fundamentals_origin,
    hk_fundamentals_path,
    350_000,
  ))
  use value <- result.try(public_query(
    base,
    "reportName",
    "RPT_CUSTOM_HKSK_APPFN_CASHFLOW_SUMMARY",
  ))
  use value <- result.try(public_query(
    value,
    "columns",
    "SECUCODE,SECURITY_CODE,SECURITY_NAME_ABBR,START_DATE,REPORT_DATE,FISCAL_YEAR,CURRENCY,ACCOUNT_STANDARD,REPORT_TYPE",
  ))
  use value <- result.try(public_query(
    value,
    "filter",
    "(SECUCODE=\"" <> market_query.income_code(plan) <> ".HK\")",
  ))
  use value <- result.try(public_query(value, "source", "F10"))
  use value <- result.try(public_query(value, "client", "PC"))
  finance_eastmoney.authorize(access, value) |> result.map_error(InvalidAccess)
}

pub fn hk_income_statement(
  access: Access,
  plan: market_query.IncomeQuery,
) -> Result(request.Request, RequestError) {
  use base <- result.try(base_request(
    hk_fundamentals_origin,
    hk_fundamentals_path,
    350_000,
  ))
  use value <- result.try(public_query(
    base,
    "reportName",
    "RPT_HKF10_FN_INCOME_PC",
  ))
  use value <- result.try(public_query(
    value,
    "columns",
    "SECUCODE,SECURITY_CODE,SECURITY_NAME_ABBR,ORG_CODE,REPORT_DATE,DATE_TYPE_CODE,FISCAL_YEAR,START_DATE,STD_ITEM_CODE,STD_ITEM_NAME,AMOUNT",
  ))
  use value <- result.try(public_query(value, "quoteColumns", ""))
  use value <- result.try(public_query(
    value,
    "filter",
    "(SECUCODE=\""
      <> market_query.income_code(plan)
      <> ".HK\")(REPORT_DATE in ('"
      <> date_text(market_query.income_report_date(plan))
      <> "'))",
  ))
  use value <- result.try(public_query(value, "pageNumber", "1"))
  use value <- result.try(public_query(value, "pageSize", "200"))
  use value <- result.try(public_query(value, "sortTypes", "-1,1"))
  use value <- result.try(public_query(
    value,
    "sortColumns",
    "REPORT_DATE,STD_ITEM_CODE",
  ))
  use value <- result.try(public_query(value, "source", "F10"))
  use value <- result.try(public_query(value, "client", "PC"))
  finance_eastmoney.authorize(access, value) |> result.map_error(InvalidAccess)
}

fn base_request(
  origin: String,
  path: String,
  maximum_bytes: Int,
) -> Result(request.Request, RequestError) {
  let assert Ok(timeout) = time.duration(15_000)
  use base <- result.try(
    request.new(request.Get, origin, path, None)
    |> result.map_error(InvalidHttp),
  )
  use accepted <- result.try(
    request.with_header(
      base,
      name: "Accept",
      value: "application/json",
      sensitivity: request.Public,
    )
    |> result.map_error(InvalidHttp),
  )
  request.with_limits(
    accepted,
    timeout: timeout,
    maximum_response_bytes: maximum_bytes,
  )
  |> result.map_error(InvalidHttp)
}

fn public_query(
  value: request.Request,
  name: String,
  parameter: String,
) -> Result(request.Request, RequestError) {
  request.with_query(value, name, parameter, request.Public)
  |> result.map_error(InvalidHttp)
}

fn compact_date(value: time.Date) -> String {
  let #(year, month, day) = time.date_parts(value)
  int.to_string(year) <> two_digits(month) <> two_digits(day)
}

fn date_text(value: time.Date) -> String {
  let #(year, month, day) = time.date_parts(value)
  int.to_string(year) <> "-" <> two_digits(month) <> "-" <> two_digits(day)
}

fn two_digits(value: Int) -> String {
  case value < 10 {
    True -> "0" <> int.to_string(value)
    False -> int.to_string(value)
  }
}
