import finance_core/time
import finance_provenance/hash
import finance_tushare/stock_basic
import gleam/json
import gleam/option.{None, Some}
import gleam/string
import gleeunit
import gleeunit/should
import pi_sparkles_cn_stock_symbols/domain

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn code_search_requires_venue_and_name_search_preserves_candidates_test() {
  domain.search_plan("cn", "code", "600519", None, "listed", 20)
  |> should.equal(Error(domain.ExactCodeRequiresVenue))
  let assert Ok(plan) =
    domain.search_plan("cn", "name", "贵州茅台", Some("sse"), "listed", 20)
  let body = stock_fixture()
  let assert Ok(values) =
    stock_basic.decode(body, for: domain.search_query(plan))
  let assert Ok(digest) = hash.text(body)
  let output =
    domain.assemble_search(
      plan,
      values,
      instant(),
      string.byte_size(body),
      digest,
    )
  let text = output |> domain.details |> json.to_string
  text |> string.contains("\"venueMic\":\"XSHG\"") |> should.be_true
  text |> string.contains("\"board\":\"main\"") |> should.be_true
  text
  |> string.contains("vendor_reported_not_exchange_authenticated")
  |> should.be_true
}

pub fn alias_history_retains_effective_intervals_test() {
  let assert Ok(plan) =
    domain.alias_plan("cn", "sse", "600519", "evidence:listing:600519", 10)
  let body =
    "{\"code\":0,\"msg\":\"\",\"data\":{\"fields\":[\"ts_code\",\"name\",\"start_date\",\"end_date\",\"ann_date\",\"change_reason\"],\"items\":[[\"600519.SH\",\"贵州茅台\",\"20010827\",null,\"20010820\",\"上市\"]]}}"
  let assert Ok(digest) = hash.text(body)
  let assert Ok(output) =
    domain.decode_aliases(plan, body, instant(), string.byte_size(body), digest)
  let text = output |> domain.details |> json.to_string
  text |> string.contains("\"effectiveStart\":\"20010827\"") |> should.be_true
  text |> string.contains("\"effectiveEnd\":null") |> should.be_true
}

fn stock_fixture() -> String {
  "{\"code\":0,\"msg\":\"\",\"data\":{\"fields\":[\"ts_code\",\"symbol\",\"name\",\"fullname\",\"cnspell\",\"market\",\"exchange\",\"curr_type\",\"list_status\",\"list_date\",\"delist_date\"],\"items\":[[\"600519.SH\",\"600519\",\"贵州茅台\",\"贵州茅台酒股份有限公司\",\"gzmt\",\"主板\",\"SSE\",\"CNY\",\"L\",\"20010827\",null]]}}"
}

fn instant() -> time.Instant {
  let assert Ok(value) = time.instant(1_786_438_800_000)
  value
}
