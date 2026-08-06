import finance_core/decimal
import finance_core/time
import finance_eastmoney
import finance_eastmoney/fundamentals
import finance_eastmoney/history
import finance_eastmoney/query
import finance_eastmoney/quote
import finance_eastmoney/request as provider_request
import finance_http/request
import finance_track
import gleam/list
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn track_and_exact_code_are_part_of_the_query_contract_test() {
  query.quote(finance_track.Cn, query.Hk, "00700")
  |> should.equal(Error(query.TrackMarketMismatch))
  query.quote(finance_track.Hk, query.Hk, "700")
  |> should.equal(Error(query.InvalidCode))
  query.quote(finance_track.Hk, query.Hk, "00700") |> should.be_ok
}

pub fn requests_are_caller_identified_bounded_and_unadjusted_test() {
  let access = access()
  let assert Ok(quote_plan) =
    query.quote(finance_track.Cn, query.CnBse, "920079")
  let assert Ok(quote_request) = provider_request.quote(access, quote_plan)
  request.origin(quote_request) |> should.equal(provider_request.quote_origin)
  request.maximum_response_bytes(quote_request) |> should.equal(100_000)
  request.headers(quote_request)
  |> list.contains(request.Header(
    "user-agent",
    "pi-sparkles-test test@example.test",
    request.Public,
  ))
  |> should.be_true

  let assert Ok(history_plan) =
    query.history(
      finance_track.Hk,
      query.Hk,
      "00700",
      civil(2026, 8, 1),
      civil(2026, 8, 5),
      10,
    )
  let assert Ok(history_request) =
    provider_request.history(access, history_plan)
  request.maximum_response_bytes(history_request) |> should.equal(2_000_000)
  request.query(history_request)
  |> list.contains(request.QueryParameter("fqt", "0", request.Public))
  |> should.be_true
  request.query(history_request)
  |> list.contains(request.QueryParameter("secid", "116.00700", request.Public))
  |> should.be_true
  query.history_source_reference(history_plan)
  |> should.equal(
    "https://push2his.eastmoney.com/api/qt/stock/kline/get?secid=116.00700&klt=101&fqt=0&beg=20260801&end=20260805&lmt=10",
  )
}

pub fn quote_decoder_uses_integer_scale_and_preserves_hk_precision_test() {
  let assert Ok(cn_plan) = query.quote(finance_track.Cn, query.CnSse, "600519")
  let assert Ok(cn) = quote.decode(cn_quote_fixture(), for: cn_plan)
  quote.last(cn) |> should.equal("1306.45")
  quote.price_limit_up(cn) |> should.equal(Some("1461.20"))

  let assert Ok(hk_plan) = query.quote(finance_track.Hk, query.Hk, "00700")
  let assert Ok(hk) = quote.decode(hk_quote_fixture(), for: hk_plan)
  quote.last(hk) |> should.equal("492.200")
  quote.price_limit_up(hk) |> should.equal(None)

  quote.decode(cn_quote_fixture(), for: hk_plan) |> should.be_error
}

pub fn history_decoder_preserves_exact_lexemes_and_bounds_test() {
  let assert Ok(plan) =
    query.history(
      finance_track.Cn,
      query.CnSse,
      "600519",
      civil(2026, 8, 1),
      civil(2026, 8, 5),
      3,
    )
  let assert Ok(value) = history.decode(history_fixture(), for: plan)
  history.bars(value) |> list.length |> should.equal(3)
  let assert [first, ..] = history.bars(value)
  history.open(first) |> should.equal("1350.60")
  history.amount(first) |> should.equal("4898665275.00")

  let assert Ok(short_plan) =
    query.history(
      finance_track.Cn,
      query.CnSse,
      "600519",
      civil(2026, 8, 1),
      civil(2026, 8, 5),
      2,
    )
  history.decode(history_fixture(), for: short_plan)
  |> should.equal(Error(history.TooManyBars(2, 3)))
}

pub fn cn_income_decoder_preserves_tokens_mappings_and_formula_leaves_test() {
  let assert Ok(plan) =
    query.income_statement(
      finance_track.Cn,
      query.CnSse,
      "600519",
      civil(2024, 12, 31),
    )
  let assert Ok(value) =
    fundamentals.decode_cn_income(
      cn_income_fixture(),
      for: plan,
      declared_currency: "CNY",
    )
  fundamentals.report_start(value) |> should.equal(None)
  fundamentals.currency_evidence(value)
  |> should.equal(fundamentals.CallerDeclared)
  let assert Ok(revenue) = fundamentals.resolve(value, fundamentals.Revenue)
  revenue.fact.raw_value |> should.equal("174144069958.2500")
  revenue.mapping.accepted_line_codes
  |> should.equal(["TOTAL_OPERATE_INCOME"])

  let assert Ok(derived) = fundamentals.net_margin(value, scale: 6)
  derived.calculation.input_names
  |> should.equal(["net_income_attributable_to_parent", "revenue"])
  decimal.to_string(derived.calculation.value) |> should.equal("49.515408")
}

pub fn hk_income_decoder_strictly_joins_context_and_preserves_tokens_test() {
  let assert Ok(plan) =
    query.income_statement(
      finance_track.Hk,
      query.Hk,
      "00700",
      civil(2024, 12, 31),
    )
  let assert Ok(context) =
    fundamentals.decode_hk_context(hk_context_fixture(), for: plan)
  let assert Ok(value) =
    fundamentals.decode_hk_income(
      hk_income_fixture(),
      for: plan,
      context: context,
    )
  fundamentals.report_start(value) |> should.equal(Some("2024-01-01"))
  fundamentals.reported_currency(value) |> should.equal("人民币")
  fundamentals.normalized_currency(value) |> should.equal(Some("CNY"))
  let assert Ok(revenue) = fundamentals.resolve(value, fundamentals.Revenue)
  revenue.fact.raw_value |> should.equal("652498000000.00")
  revenue.fact.original_label |> should.equal("营业额")

  let assert Ok(derived) = fundamentals.net_margin(value, scale: 6)
  decimal.to_string(derived.calculation.value) |> should.equal("29.74308")
}

pub fn fundamental_requests_are_bounded_and_track_specific_test() {
  let access = access()
  let assert Ok(cn_plan) =
    query.income_statement(
      finance_track.Cn,
      query.CnBse,
      "920079",
      civil(2025, 12, 31),
    )
  let assert Ok(cn_request) =
    provider_request.cn_income_statement(access, cn_plan)
  request.origin(cn_request)
  |> should.equal(provider_request.cn_fundamentals_origin)
  request.maximum_response_bytes(cn_request) |> should.equal(250_000)
  request.query(cn_request)
  |> list.contains(request.QueryParameter(
    "filter",
    "(SECURITY_CODE=\"920079\")(REPORT_DATE='2025-12-31')",
    request.Public,
  ))
  |> should.be_true

  let assert Ok(hk_plan) =
    query.income_statement(
      finance_track.Hk,
      query.Hk,
      "00700",
      civil(2024, 12, 31),
    )
  let assert Ok(hk_request) =
    provider_request.hk_income_statement(access, hk_plan)
  request.origin(hk_request)
  |> should.equal(provider_request.hk_fundamentals_origin)
  request.maximum_response_bytes(hk_request) |> should.equal(350_000)
}

fn access() -> finance_eastmoney.Access {
  let assert Ok(value) =
    finance_eastmoney.access("pi-sparkles-test", "test@example.test")
  value
}

fn civil(year: Int, month: Int, day: Int) -> time.Date {
  let assert Ok(value) = time.date(year, month, day)
  value
}

fn cn_quote_fixture() -> String {
  "{\"rc\":0,\"data\":{\"f43\":130645,\"f44\":133380,\"f45\":130350,\"f46\":132836,\"f47\":42689,\"f51\":146120,\"f52\":119552,\"f57\":\"600519\",\"f58\":\"贵州茅台\",\"f59\":2,\"f60\":132836,\"f86\":1785917510}}"
}

fn hk_quote_fixture() -> String {
  "{\"rc\":0,\"data\":{\"f43\":492200,\"f44\":497800,\"f45\":482200,\"f46\":493400,\"f47\":25662478,\"f57\":\"00700\",\"f58\":\"腾讯控股\",\"f59\":3,\"f60\":487600,\"f86\":1785917339}}"
}

fn history_fixture() -> String {
  "{\"rc\":0,\"data\":{\"code\":\"600519\",\"market\":1,\"name\":\"贵州茅台\",\"decimal\":2,\"klines\":[\"2026-08-03,1350.60,1358.98,1363.35,1346.00,36147,4898665275.00,1.28,0.62,8.38,0.29\",\"2026-08-04,1350.06,1328.36,1350.94,1328.36,37450,5004070406.00,1.66,-2.25,-30.62,0.30\",\"2026-08-05,1328.36,1306.45,1333.80,1303.50,42689,5600615349.00,2.28,-1.65,-21.91,0.34\"]}}"
}

fn cn_income_fixture() -> String {
  "{\"success\":true,\"result\":{\"data\":[{\"SECURITY_CODE\":\"600519\",\"SECURITY_NAME_ABBR\":\"贵州茅台\",\"ORG_CODE\":\"10002602\",\"DATE_TYPE_CODE\":\"001\",\"REPORT_TYPE_CODE\":\"001\",\"DATA_STATE\":\"2\",\"NOTICE_DATE\":\"2025-04-03 00:00:00\",\"REPORT_DATE\":\"2024-12-31 00:00:00\",\"PARENT_NETPROFIT\":86228146421.62,\"TOTAL_OPERATE_INCOME\":174144069958.2500}]}}"
}

fn hk_context_fixture() -> String {
  "{\"success\":true,\"result\":{\"data\":[{\"REPORT_LIST\":[{\"SECURITY_CODE\":\"00700\",\"SECURITY_NAME_ABBR\":\"腾讯控股\",\"START_DATE\":\"2024-01-01 00:00:00\",\"REPORT_DATE\":\"2024-12-31 00:00:00\",\"FISCAL_YEAR\":\"12-31\",\"CURRENCY\":\"人民币\",\"ACCOUNT_STANDARD\":\"国际会计准则\",\"REPORT_TYPE\":\"年报\"}]}]}}"
}

fn hk_income_fixture() -> String {
  "{\"success\":true,\"result\":{\"data\":[{\"SECURITY_CODE\":\"00700\",\"SECURITY_NAME_ABBR\":\"腾讯控股\",\"ORG_CODE\":\"10009066\",\"REPORT_DATE\":\"2024-12-31 00:00:00\",\"DATE_TYPE_CODE\":\"001\",\"FISCAL_YEAR\":\"12-31\",\"START_DATE\":\"2024-01-01 00:00:00\",\"STD_ITEM_CODE\":\"004001001\",\"STD_ITEM_NAME\":\"营业额\",\"AMOUNT\":652498000000.00},{\"SECURITY_CODE\":\"00700\",\"SECURITY_NAME_ABBR\":\"腾讯控股\",\"ORG_CODE\":\"10009066\",\"REPORT_DATE\":\"2024-12-31 00:00:00\",\"DATE_TYPE_CODE\":\"001\",\"FISCAL_YEAR\":\"12-31\",\"START_DATE\":\"2024-01-01 00:00:00\",\"STD_ITEM_CODE\":\"004025002\",\"STD_ITEM_NAME\":\"股东应占溢利\",\"AMOUNT\":194073000000}]}}"
}
