import finance_core/time
import finance_provenance/hash
import gleam/json
import gleam/string
import gleeunit
import gleeunit/should
import pi_sparkles_cn_stock_corporate_actions/domain

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn dividend_rows_preserve_terms_dates_and_missing_currency_test() {
  let plan = plan()
  let body =
    "{\"code\":0,\"msg\":\"\",\"data\":{\"fields\":[\"ts_code\",\"end_date\",\"ann_date\",\"div_proc\",\"stk_div\",\"stk_bo_rate\",\"stk_co_rate\",\"cash_div\",\"cash_div_tax\",\"record_date\",\"ex_date\",\"pay_date\",\"div_listdate\",\"imp_ann_date\",\"base_date\",\"base_share\"],\"items\":[[\"600519.SH\",\"20251231\",\"20260330\",\"预案\",0.0,0.0,0.0,23.8810,27.6000,null,null,null,null,null,null,125619.78]]}}"
  let assert Ok(digest) = hash.text(body)
  let assert Ok(output) =
    domain.decode_and_assemble(
      plan,
      body,
      instant(),
      string.byte_size(body),
      digest,
    )
  let text = domain.details(output) |> json.to_string
  text
  |> string.contains("\"cashDividendAfterTaxPerShare\":\"23.8810\"")
  |> should.be_true
  text |> string.contains("\"cashDividendCurrency\":null") |> should.be_true
  text |> string.contains("\"rights_issue\"") |> should.be_true
}

pub fn unsupported_identity_context_fails_closed_test() {
  domain.plan("hk", "sse", "600519", "a_share", "evidence", 100)
  |> should.equal(Error(domain.WrongTrack))
  domain.plan("cn", "sse", "600519", "cdr", "evidence", 100)
  |> should.equal(Error(domain.UnsupportedShareClass))
}

fn plan() -> domain.Plan {
  let assert Ok(value) =
    domain.plan(
      "cn",
      "sse",
      "600519",
      "a_share",
      "evidence:listing:600519",
      100,
    )
  value
}

fn instant() -> time.Instant {
  let assert Ok(value) = time.instant(1_786_438_800_000)
  value
}
