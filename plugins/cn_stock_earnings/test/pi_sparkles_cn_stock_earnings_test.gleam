import finance_core/time
import finance_provenance/hash
import gleam/json
import gleam/string
import gleeunit
import gleeunit/should
import pi_sparkles_cn_stock_earnings/domain

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn forecast_and_express_remain_distinct_exact_event_classes_test() {
  let forecast = plan("forecast")
  let forecast_body =
    "{\"code\":0,\"msg\":\"\",\"data\":{\"fields\":[\"ts_code\",\"ann_date\",\"end_date\",\"type\",\"p_change_min\",\"p_change_max\",\"net_profit_min\",\"net_profit_max\",\"last_parent_net\",\"first_ann_date\",\"summary\",\"change_reason\"],\"items\":[[\"600519.SH\",\"20260131\",\"20251231\",\"预增\",10.0000,20.0000,800000.00,900000.00,700000.00,\"20260131\",\"摘要\",\"原因\"]]}}"
  let text = output(forecast, forecast_body)
  text |> string.contains("\"eventClass\":\"forecast\"") |> should.be_true
  text
  |> string.contains("\"netProfitMinTenThousandCny\":\"800000.00\"")
  |> should.be_true

  let express = plan("express_report")
  let express_body =
    "{\"code\":0,\"msg\":\"\",\"data\":{\"fields\":[\"ts_code\",\"ann_date\",\"end_date\",\"revenue\",\"operate_profit\",\"total_profit\",\"n_income\",\"total_assets\",\"total_hldr_eqy_exc_min_int\",\"diluted_eps\",\"diluted_roe\",\"perf_summary\",\"is_audit\",\"remark\"],\"items\":[[\"600519.SH\",\"20260228\",\"20251231\",180000000000.00,90000000000.00,100000000000.00,80000000000.00,300000000000.00,250000000000.00,65.50,35.20,\"快报\",0, null]]}}"
  let express_text = output(express, express_body)
  express_text
  |> string.contains("\"eventClass\":\"express_report\"")
  |> should.be_true
  express_text
  |> string.contains("\"auditFlagProviderCode\":\"0\"")
  |> should.be_true
}

pub fn invalid_class_and_track_fail_closed_test() {
  domain.plan(
    "cn",
    "sse",
    "600519",
    "a_share",
    "evidence",
    "periodic_report",
    date(),
    date(),
    100,
  )
  |> should.equal(Error(domain.InvalidEventClass))
  domain.plan(
    "us",
    "sse",
    "600519",
    "a_share",
    "evidence",
    "forecast",
    date(),
    date(),
    100,
  )
  |> should.equal(Error(domain.WrongTrack))
}

fn plan(class: String) -> domain.Plan {
  let assert Ok(value) =
    domain.plan(
      "cn",
      "sse",
      "600519",
      "a_share",
      "evidence:listing:600519",
      class,
      date(),
      date(),
      100,
    )
  value
}

fn output(plan: domain.Plan, body: String) -> String {
  let assert Ok(digest) = hash.text(body)
  let assert Ok(value) =
    domain.decode_and_assemble(
      plan,
      body,
      instant(),
      string.byte_size(body),
      digest,
    )
  value |> domain.details |> json.to_string
}

fn date() -> time.Date {
  let assert Ok(value) = time.date(2026, 1, 31)
  value
}

fn instant() -> time.Instant {
  let assert Ok(value) = time.instant(1_786_438_800_000)
  value
}
