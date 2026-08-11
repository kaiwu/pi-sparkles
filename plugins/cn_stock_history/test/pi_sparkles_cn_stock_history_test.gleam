import finance_core/time
import finance_eastmoney/history as eastmoney_history
import finance_provenance/hash
import finance_tushare/daily as tushare_daily
import gleam/json
import gleam/string
import gleeunit
import gleeunit/should
import pi_sparkles_cn_stock_history/domain

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn both_adapters_project_one_stable_product_contract_test() {
  let eastmoney_plan = plan("eastmoney")
  let assert Ok(eastmoney_query) = domain.eastmoney_plan(eastmoney_plan)
  let assert Ok(eastmoney) =
    eastmoney_history.decode(eastmoney_fixture(), for: eastmoney_query)
  let assert Ok(eastmoney_digest) = hash.text(eastmoney_fixture())
  let assert Ok(eastmoney_output) =
    domain.assemble_eastmoney(
      eastmoney_plan,
      eastmoney,
      instant(),
      string.byte_size(eastmoney_fixture()),
      eastmoney_digest,
    )
  let eastmoney_json = domain.details(eastmoney_output) |> json.to_string
  eastmoney_json
  |> string.contains("\"selectedProvider\":\"eastmoney\"")
  |> should.be_true
  eastmoney_json
  |> string.contains("\"fallbackPerformed\":false")
  |> should.be_true
  eastmoney_json |> string.contains("\"canonicalSha256\"") |> should.be_true

  let tushare_plan = plan("tushare")
  let assert Ok(tushare_query) = domain.tushare_plan(tushare_plan)
  let assert Ok(tushare) =
    tushare_daily.decode(tushare_fixture(), for: tushare_query)
  let assert Ok(tushare_digest) = hash.text(tushare_fixture())
  let assert Ok(tushare_output) =
    domain.assemble_tushare(
      tushare_plan,
      tushare,
      instant(),
      string.byte_size(tushare_fixture()),
      tushare_digest,
    )
  let tushare_json = domain.details(tushare_output) |> json.to_string
  tushare_json
  |> string.contains("\"selectedProvider\":\"tushare_pro\"")
  |> should.be_true
  tushare_json
  |> string.contains("\"volumeUnit\":\"provider_lot_手\"")
  |> should.be_true
  tushare_json
  |> string.contains("\"amountUnit\":\"thousand_cny\"")
  |> should.be_true
}

pub fn provider_selection_and_identity_are_fail_closed_test() {
  domain.plan(
    "cn",
    "automatic",
    "sse",
    "600519",
    "a_share",
    "evidence",
    date(2026, 8, 1),
    date(2026, 8, 5),
    10,
  )
  |> should.equal(Error(domain.InvalidProvider))
  domain.plan(
    "cn",
    "eastmoney",
    "sse",
    "600519",
    "unknown",
    "evidence",
    date(2026, 8, 1),
    date(2026, 8, 5),
    10,
  )
  |> should.equal(Error(domain.UnsupportedShareClass))
  domain.tushare_plan(plan("eastmoney"))
  |> should.equal(Error(domain.ProviderMismatch))
}

fn plan(provider: String) -> domain.Plan {
  let assert Ok(value) =
    domain.plan(
      "cn",
      provider,
      "sse",
      "600519",
      "a_share",
      "evidence:listing:600519",
      date(2026, 8, 1),
      date(2026, 8, 5),
      10,
    )
  value
}

fn date(year: Int, month: Int, day: Int) -> time.Date {
  let assert Ok(value) = time.date(year, month, day)
  value
}

fn instant() -> time.Instant {
  let assert Ok(value) = time.instant(1_786_438_800_000)
  value
}

fn eastmoney_fixture() -> String {
  "{\"rc\":0,\"data\":{\"code\":\"600519\",\"market\":1,\"name\":\"贵州茅台\",\"decimal\":2,\"klines\":[\"2026-08-03,1350.60,1358.98,1363.35,1346.00,36147,4898665275.00,1.28,0.62,8.38,0.29\",\"2026-08-04,1350.06,1328.36,1350.94,1328.36,37450,5004070406.00,1.66,-2.25,-30.62,0.30\"]}}"
}

fn tushare_fixture() -> String {
  "{\"code\":0,\"msg\":\"\",\"data\":{\"fields\":[\"ts_code\",\"trade_date\",\"open\",\"high\",\"low\",\"close\",\"pre_close\",\"change\",\"pct_chg\",\"vol\",\"amount\"],\"items\":[[\"600519.SH\",\"20260805\",1328.3600,1333.80,1303.50,1306.45,1328.36,-21.91,-1.6494,42689.00,5600615.349],[\"600519.SH\",\"20260804\",1350.06,1350.94,1328.36,1328.36,1358.98,-30.62,-2.2532,37450,5004070.406]]}}"
}
