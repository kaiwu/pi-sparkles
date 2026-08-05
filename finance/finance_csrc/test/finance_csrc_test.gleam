import finance_authority_snapshot/snapshot
import finance_core/source
import finance_core/time
import finance_csrc
import finance_csrc/request
import finance_csrc/response
import finance_csrc/runtime
import finance_http/request as http_request
import finance_http/response as http_response
import finance_track
import gleam/list
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn request_is_identified_allowlisted_and_bounded_test() {
  finance_csrc.access("pi-sparkles/0.1", "bad\ncontact")
  |> should.equal(Error(finance_csrc.InvalidContact))
  let assert Ok(access) =
    finance_csrc.access("pi-sparkles/0.1", "research@example.com")
  let assert Ok(value) = request.snapshot(access, finance_csrc.MarketMonthly)

  http_request.method(value) |> should.equal(http_request.Get)
  http_request.origin(value) |> should.equal("https://www.csrc.gov.cn")
  http_request.path(value)
  |> should.equal("/csrc/c100120/common_list.shtml")
  http_request.maximum_response_bytes(value) |> should.equal(2_000_000)
  time.duration_milliseconds(http_request.timeout(value))
  |> should.equal(15_000)
  http_request.headers(value)
  |> list.any(fn(header) {
    header
    == http_request.Header(
      "user-agent",
      "pi-sparkles/0.1 research@example.com",
      http_request.Public,
    )
  })
  |> should.be_true
}

pub fn official_html_is_captured_as_cn_csrc_evidence_test() {
  let body = "<html><title>证券市场月报</title><li>2026年6月统计数据</li></html>"
  let assert Ok(duration) = time.duration(10)
  let assert Ok(raw) =
    http_response.new(
      200,
      [http_response.Header("content-type", "text/html; charset=utf-8")],
      body,
      string.byte_size(body),
      duration,
    )
  let assert Ok(value) =
    response.capture(finance_csrc.MarketMonthly, raw, instant(1000))

  snapshot.track(value) |> should.equal(finance_track.Cn)
  snapshot.authority_id(value) |> should.equal("cn_csrc")
  snapshot.source(value) |> source.provider |> should.equal("CSRC")
  snapshot.source(value)
  |> source.reference
  |> should.equal("https://www.csrc.gov.cn/csrc/c100120/common_list.shtml")
  snapshot.body(value) |> should.equal(body)
}

pub fn non_success_status_is_not_saved_as_evidence_test() {
  let body = "service unavailable"
  let assert Ok(duration) = time.duration(10)
  let assert Ok(raw) =
    http_response.new(
      503,
      [http_response.Header("content-type", "text/html")],
      body,
      string.byte_size(body),
      duration,
    )
  response.capture(finance_csrc.MarketWeekly, raw, instant(1000))
  |> should.equal(Error(snapshot.UnexpectedStatus(503)))
}

pub fn runtime_has_a_valid_bounded_profile_test() {
  let assert Ok(access) =
    finance_csrc.access("pi-sparkles/0.1", "research@example.com")
  runtime.new(access) |> should.be_ok
}

fn instant(value: Int) -> time.Instant {
  let assert Ok(parsed) = time.instant(value)
  parsed
}
