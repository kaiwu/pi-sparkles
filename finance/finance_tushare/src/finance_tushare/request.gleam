import finance_core/time
import finance_http/request
import finance_tushare.{type Access}
import finance_tushare/query as provider_query
import gleam/list
import gleam/option.{None, Some}
import gleam/result

pub const origin = "https://api.tushare.pro"

pub const path = "/"

pub const stock_basic_api = "stock_basic"

pub const daily_api = "daily"

pub const namechange_api = "namechange"

pub const dividend_api = "dividend"

pub const forecast_api = "forecast"

pub const express_api = "express"

pub const disclosure_date_api = "disclosure_date"

pub const announcements_api = "anns_d"

pub const stock_basic_fields = [
  "ts_code",
  "symbol",
  "name",
  "fullname",
  "cnspell",
  "market",
  "exchange",
  "curr_type",
  "list_status",
  "list_date",
  "delist_date",
]

pub const daily_fields = [
  "ts_code",
  "trade_date",
  "open",
  "high",
  "low",
  "close",
  "pre_close",
  "change",
  "pct_chg",
  "vol",
  "amount",
]

pub const namechange_fields = [
  "ts_code", "name", "start_date", "end_date", "ann_date", "change_reason",
]

pub const dividend_fields = [
  "ts_code", "end_date", "ann_date", "div_proc", "stk_div", "stk_bo_rate",
  "stk_co_rate", "cash_div", "cash_div_tax", "record_date", "ex_date",
  "pay_date", "div_listdate", "imp_ann_date", "base_date", "base_share",
]

pub const forecast_fields = [
  "ts_code", "ann_date", "end_date", "type", "p_change_min", "p_change_max",
  "net_profit_min", "net_profit_max", "last_parent_net", "first_ann_date",
  "summary", "change_reason",
]

pub const express_fields = [
  "ts_code", "ann_date", "end_date", "revenue", "operate_profit", "total_profit",
  "n_income", "total_assets", "total_hldr_eqy_exc_min_int", "diluted_eps",
  "diluted_roe", "perf_summary", "is_audit", "remark",
]

pub const disclosure_date_fields = [
  "ts_code", "ann_date", "end_date", "pre_date", "actual_date", "modify_date",
]

pub const announcement_fields = [
  "ann_date", "ts_code", "name", "title", "url", "rec_time",
]

pub type RequestError {
  InvalidHttp(request.RequestError)
  InvalidAccess(finance_tushare.AccessError)
}

pub fn stock_basic(
  access: Access,
  plan: provider_query.StockBasicQuery,
) -> Result(request.Request, RequestError) {
  use base <- result.try(base_request(2_000_000))
  let exchange_params = case provider_query.stock_basic_exchange(plan) {
    None -> []
    Some(value) -> [#("exchange", provider_query.exchange_name(value))]
  }
  let code_params = case
    provider_query.stock_basic_exchange(plan),
    provider_query.stock_basic_code(plan)
  {
    Some(exchange), Some(code) -> [
      #("ts_code", provider_query.ts_code(exchange, code)),
    ]
    _, _ -> []
  }
  let name_params = case provider_query.stock_basic_name_query(plan) {
    None -> []
    Some(value) -> [#("name", value)]
  }
  finance_tushare.authorize_query(
    access,
    base,
    stock_basic_api,
    list.append(
      [
        #(
          "list_status",
          provider_query.list_status_name(provider_query.stock_basic_status(
            plan,
          )),
        ),
      ],
      list.append(exchange_params, list.append(code_params, name_params)),
    ),
    stock_basic_fields,
  )
  |> result.map_error(InvalidAccess)
}

pub fn daily(
  access: Access,
  plan: provider_query.DailyQuery,
) -> Result(request.Request, RequestError) {
  use base <- result.try(base_request(2_000_000))
  finance_tushare.authorize_query(
    access,
    base,
    daily_api,
    [
      #(
        "ts_code",
        provider_query.ts_code(
          provider_query.daily_exchange(plan),
          provider_query.daily_code(plan),
        ),
      ),
      #(
        "start_date",
        provider_query.compact_date(provider_query.daily_start(plan)),
      ),
      #("end_date", provider_query.compact_date(provider_query.daily_end(plan))),
    ],
    daily_fields,
  )
  |> result.map_error(InvalidAccess)
}

pub fn namechange(access: Access, plan: provider_query.SecurityQuery) {
  security_request(access, plan, namechange_api, namechange_fields)
}

pub fn dividend(access: Access, plan: provider_query.SecurityQuery) {
  security_request(access, plan, dividend_api, dividend_fields)
}

pub fn disclosure_dates(access: Access, plan: provider_query.SecurityQuery) {
  security_request(access, plan, disclosure_date_api, disclosure_date_fields)
}

pub fn forecast(access: Access, plan: provider_query.DatedSecurityQuery) {
  dated_request(access, plan, forecast_api, forecast_fields)
}

pub fn express(access: Access, plan: provider_query.DatedSecurityQuery) {
  dated_request(access, plan, express_api, express_fields)
}

pub fn announcements(access: Access, plan: provider_query.DatedSecurityQuery) {
  dated_request(access, plan, announcements_api, announcement_fields)
}

fn security_request(
  access: Access,
  plan: provider_query.SecurityQuery,
  api_name: String,
  fields: List(String),
) -> Result(request.Request, RequestError) {
  use base <- result.try(base_request(2_000_000))
  finance_tushare.authorize_query(
    access,
    base,
    api_name,
    [
      #(
        "ts_code",
        provider_query.ts_code(
          provider_query.security_exchange(plan),
          provider_query.security_code(plan),
        ),
      ),
    ],
    fields,
  )
  |> result.map_error(InvalidAccess)
}

fn dated_request(
  access: Access,
  plan: provider_query.DatedSecurityQuery,
  api_name: String,
  fields: List(String),
) -> Result(request.Request, RequestError) {
  use base <- result.try(base_request(2_000_000))
  finance_tushare.authorize_query(
    access,
    base,
    api_name,
    [
      #(
        "ts_code",
        provider_query.ts_code(
          provider_query.dated_exchange(plan),
          provider_query.dated_code(plan),
        ),
      ),
      #(
        "start_date",
        provider_query.compact_date(provider_query.dated_start(plan)),
      ),
      #("end_date", provider_query.compact_date(provider_query.dated_end(plan))),
    ],
    fields,
  )
  |> result.map_error(InvalidAccess)
}

fn base_request(maximum_bytes: Int) -> Result(request.Request, RequestError) {
  let assert Ok(timeout) = time.duration(15_000)
  use base <- result.try(
    request.new(request.Post, origin, path, None)
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
