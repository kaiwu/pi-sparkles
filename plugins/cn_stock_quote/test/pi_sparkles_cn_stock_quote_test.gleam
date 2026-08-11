import finance_core/time
import finance_eastmoney/quote as eastmoney_quote
import finance_provenance/hash
import finance_tushare/daily as tushare_daily
import gleam/json
import gleam/string
import gleeunit
import gleeunit/should
import pi_sparkles_cn_stock_quote/domain

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn both_adapters_keep_one_schema_and_honest_observation_kind_test() {
  let eastmoney_plan = plan("eastmoney", date(2026, 8, 5))
  let assert Ok(eastmoney_query) = domain.eastmoney_plan(eastmoney_plan)
  let eastmoney_body =
    "{\"rc\":0,\"data\":{\"f43\":130645,\"f44\":133380,\"f45\":130350,\"f46\":132836,\"f47\":42689,\"f51\":146120,\"f52\":119552,\"f57\":\"600519\",\"f58\":\"贵州茅台\",\"f59\":2,\"f60\":132836,\"f86\":1785917510}}"
  let assert Ok(eastmoney) =
    eastmoney_quote.decode(eastmoney_body, for: eastmoney_query)
  let assert Ok(eastmoney_digest) = hash.text(eastmoney_body)
  let assert Ok(eastmoney_output) =
    domain.assemble_eastmoney(
      eastmoney_plan,
      eastmoney,
      instant(),
      string.byte_size(eastmoney_body),
      eastmoney_digest,
    )
  let eastmoney_json = domain.details(eastmoney_output) |> json.to_string
  eastmoney_json
  |> string.contains("\"observationKind\":\"vendor_quote_snapshot\"")
  |> should.be_true
  eastmoney_json |> string.contains("\"bid\":null") |> should.be_true

  let tushare_plan = plan("tushare", date(2026, 8, 5))
  let assert Ok(tushare_query) = domain.tushare_plan(tushare_plan)
  let tushare_body =
    "{\"code\":0,\"msg\":\"\",\"data\":{\"fields\":[\"ts_code\",\"trade_date\",\"open\",\"high\",\"low\",\"close\",\"pre_close\",\"change\",\"pct_chg\",\"vol\",\"amount\"],\"items\":[[\"600519.SH\",\"20260805\",1328.3600,1333.80,1303.50,1306.45,1328.36,-21.91,-1.6494,42689.00,5600615.349]]}}"
  let assert Ok(tushare) =
    tushare_daily.decode(tushare_body, for: tushare_query)
  let assert Ok(tushare_digest) = hash.text(tushare_body)
  let assert Ok(tushare_output) =
    domain.assemble_tushare(
      tushare_plan,
      tushare,
      instant(),
      string.byte_size(tushare_body),
      tushare_digest,
    )
  let tushare_json = domain.details(tushare_output) |> json.to_string
  tushare_json
  |> string.contains("\"observationKind\":\"end_of_day_daily_bar_snapshot\"")
  |> should.be_true
  tushare_json
  |> string.contains("\"fallbackPerformed\":false")
  |> should.be_true
}

pub fn date_and_provider_mismatches_fail_closed_test() {
  domain.tushare_plan(plan("eastmoney", date(2026, 8, 5)))
  |> should.equal(Error(domain.ProviderMismatch))
  domain.plan(
    "cn",
    "auto",
    "sse",
    "600519",
    "a_share",
    "evidence",
    date(2026, 8, 5),
  )
  |> should.equal(Error(domain.InvalidProvider))
}

fn plan(provider: String, date: time.Date) -> domain.Plan {
  let assert Ok(value) =
    domain.plan(
      "cn",
      provider,
      "sse",
      "600519",
      "a_share",
      "evidence:listing:600519",
      date,
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
