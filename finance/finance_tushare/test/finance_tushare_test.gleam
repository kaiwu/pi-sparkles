import finance_core/time
import finance_http/request as http_request
import finance_track
import finance_tushare
import finance_tushare/daily
import finance_tushare/query
import finance_tushare/request
import finance_tushare/response
import finance_tushare/stock_basic
import finance_tushare/table
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn query_requires_cn_and_explicit_exchange_for_exact_code_test() {
  query.stock_basic(finance_track.Hk, None, None, query.Listed, 100)
  |> should.equal(Error(query.TrackMismatch))
  query.stock_basic(finance_track.Cn, None, Some("600519"), query.Listed, 100)
  |> should.equal(Error(query.ExchangeRequiredForCode))
  let assert Ok(plan) =
    query.stock_basic(
      finance_track.Cn,
      Some(query.Sse),
      Some("600519"),
      query.Listed,
      100,
    )
  query.stock_basic_code(plan) |> should.equal(Some("600519"))
}

pub fn request_is_bounded_repeatable_and_secret_safe_test() {
  let access = access()
  let assert Ok(plan) =
    query.daily(
      finance_track.Cn,
      query.Sse,
      "600519",
      civil(2026, 8, 1),
      civil(2026, 8, 5),
      100,
    )
  let assert Ok(value) = request.daily(access, plan)
  http_request.origin(value) |> should.equal(request.origin)
  http_request.method(value) |> should.equal(http_request.Post)
  http_request.can_retry(value) |> should.be_true
  http_request.maximum_response_bytes(value) |> should.equal(2_000_000)
  let safe = http_request.safe_key(value)
  safe |> string.contains("test-secret-token") |> should.be_false
  safe |> string.contains("[REDACTED]") |> should.be_true
  let assert Some(http_request.TextBody(_, body)) = http_request.body(value)
  body |> string.contains("test-secret-token") |> should.be_true
  body |> string.contains("600519.SH") |> should.be_true
  query.daily_source_reference(plan)
  |> should.equal(
    "https://api.tushare.pro/?api_name=daily&ts_code=600519.SH&start_date=20260801&end_date=20260805",
  )
}

pub fn daily_decoder_preserves_numeric_lexemes_and_units_test() {
  let assert Ok(plan) =
    query.daily(
      finance_track.Cn,
      query.Sse,
      "600519",
      civil(2026, 8, 1),
      civil(2026, 8, 5),
      3,
    )
  let assert Ok(value) = daily.decode(daily_fixture(), for: plan)
  daily.ts_code(value) |> should.equal("600519.SH")
  daily.bars(value) |> list.length |> should.equal(2)
  let assert [newest, _] = daily.bars(value)
  daily.open(newest) |> should.equal("1328.3600")
  daily.volume_lots(newest) |> should.equal("42689.00")
  daily.amount_thousand_cny(newest) |> should.equal("5600615.349")
}

pub fn stock_basic_decoder_enforces_query_identity_test() {
  let assert Ok(plan) =
    query.stock_basic(
      finance_track.Cn,
      Some(query.Sse),
      Some("600519"),
      query.Listed,
      10,
    )
  let assert Ok(values) = stock_basic.decode(stock_basic_fixture(), for: plan)
  let assert [security] = values
  stock_basic.name(security) |> should.equal("贵州茅台")
  stock_basic.delist_date(security) |> should.equal(None)

  let mismatched =
    string.replace(stock_basic_fixture(), "600519.SH", "000001.SZ")
  stock_basic.decode(mismatched, for: plan) |> should.be_error
}

pub fn provider_error_and_field_reordering_fail_closed_test() {
  let assert Ok(plan) =
    query.daily(
      finance_track.Cn,
      query.Sse,
      "600519",
      civil(2026, 8, 1),
      civil(2026, 8, 5),
      3,
    )
  daily.decode(
    "{\"code\":-2001,\"msg\":\"permission denied\",\"data\":{\"fields\":[],\"items\":[]}}",
    for: plan,
  )
  |> should.be_error
  daily.decode(
    string.replace(
      daily_fixture(),
      "\"ts_code\",\"trade_date\"",
      "\"trade_date\",\"ts_code\"",
    ),
    for: plan,
  )
  |> should.be_error
}

pub fn structured_reference_endpoints_share_secret_safe_bounded_transport_test() {
  let access = access()
  let assert Ok(security) =
    query.security(finance_track.Cn, query.Sse, "600519", 100)
  let assert Ok(dividend_request) = request.dividend(access, security)
  http_request.safe_key(dividend_request)
  |> string.contains("test-secret-token")
  |> should.be_false
  let assert Some(http_request.TextBody(_, body)) =
    http_request.body(dividend_request)
  body |> string.contains("\"api_name\":\"dividend\"") |> should.be_true
  body |> string.contains("600519.SH") |> should.be_true

  let assert Ok(dated) =
    query.dated_security(
      finance_track.Cn,
      query.Sse,
      "600519",
      civil(2026, 1, 1),
      civil(2026, 8, 5),
      100,
    )
  let assert Ok(forecast_request) = request.forecast(access, dated)
  let assert Some(http_request.TextBody(_, forecast_body)) =
    http_request.body(forecast_request)
  forecast_body |> string.contains("20260101") |> should.be_true
  forecast_body |> string.contains("20260805") |> should.be_true
}

pub fn table_decoder_preserves_null_text_and_numeric_cells_test() {
  let fixture =
    "{\"code\":0,\"msg\":\"\",\"data\":{\"fields\":[\"ts_code\",\"ratio\",\"note\"],\"items\":[[\"600519.SH\",0.1000,null]]}}"
  let assert Ok(value) = table.decode(fixture, ["ts_code", "ratio", "note"], 1)
  let assert [[code, ratio, note]] = table.rows(value)
  response.text(code) |> should.equal(Ok("600519.SH"))
  response.scalar(ratio) |> should.equal(Ok("0.1000"))
  response.optional_text(note) |> should.equal(Ok(None))
  table.decode(fixture, ["ratio", "ts_code", "note"], 1)
  |> should.equal(Error(table.UnexpectedFields))
}

fn access() -> finance_tushare.Access {
  let assert Ok(value) = finance_tushare.access("test-secret-token")
  value
}

fn civil(year: Int, month: Int, day: Int) -> time.Date {
  let assert Ok(value) = time.date(year, month, day)
  value
}

fn daily_fixture() -> String {
  "{\"code\":0,\"msg\":\"\",\"data\":{\"fields\":[\"ts_code\",\"trade_date\",\"open\",\"high\",\"low\",\"close\",\"pre_close\",\"change\",\"pct_chg\",\"vol\",\"amount\"],\"items\":[[\"600519.SH\",\"20260805\",1328.3600,1333.80,1303.50,1306.45,1328.36,-21.91,-1.6494,42689.00,5600615.349],[\"600519.SH\",\"20260804\",1350.06,1350.94,1328.36,1328.36,1358.98,-30.62,-2.2532,37450,5004070.406]]}}"
}

fn stock_basic_fixture() -> String {
  "{\"code\":0,\"msg\":\"\",\"data\":{\"fields\":[\"ts_code\",\"symbol\",\"name\",\"fullname\",\"cnspell\",\"market\",\"exchange\",\"curr_type\",\"list_status\",\"list_date\",\"delist_date\"],\"items\":[[\"600519.SH\",\"600519\",\"贵州茅台\",\"贵州茅台酒股份有限公司\",\"gzmt\",\"主板\",\"SSE\",\"CNY\",\"L\",\"20010827\",null]]}}"
}
