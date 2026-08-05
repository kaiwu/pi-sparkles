import finance_authority_snapshot/snapshot
import finance_core/source
import finance_core/time
import finance_http/request as http_request
import finance_http/response as http_response
import finance_sfc
import finance_sfc/request
import finance_sfc/response
import finance_sfc/runtime
import finance_track
import gleam/list
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn access_and_request_are_identified_allowlisted_and_bounded_test() {
  finance_sfc.access("", "research@example.com")
  |> should.equal(Error(finance_sfc.InvalidProduct))
  let assert Ok(access) =
    finance_sfc.access("pi-sparkles/0.1", "research@example.com")
  let assert Ok(value) = request.press_releases(access)

  http_request.method(value) |> should.equal(http_request.Get)
  http_request.origin(value) |> should.equal("https://www.sfc.hk")
  http_request.path(value)
  |> should.equal("/en/RSS-Feeds/Press-releases")
  http_request.maximum_response_bytes(value) |> should.equal(1_000_000)
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

pub fn official_rss_is_captured_as_hk_sfc_evidence_test() {
  let body = "<rss><channel><title>SFC Press releases</title></channel></rss>"
  let assert Ok(duration) = time.duration(10)
  let assert Ok(raw) =
    http_response.new(
      200,
      [http_response.Header("content-type", "application/xml; charset=utf-8")],
      body,
      string.byte_size(body),
      duration,
    )
  let retrieved = instant(1000)
  let assert Ok(value) = response.capture_press_releases(raw, retrieved)

  snapshot.track(value) |> should.equal(finance_track.Hk)
  snapshot.authority_id(value) |> should.equal("hk_sfc")
  snapshot.source(value) |> source.provider |> should.equal("SFC")
  snapshot.body(value) |> should.equal(body)
}

pub fn wrong_media_fails_before_semantic_parsing_test() {
  let body = "<html>not the feed</html>"
  let assert Ok(duration) = time.duration(10)
  let assert Ok(raw) =
    http_response.new(
      200,
      [http_response.Header("content-type", "text/html")],
      body,
      string.byte_size(body),
      duration,
    )
  response.capture_press_releases(raw, instant(1000))
  |> should.equal(Error(snapshot.UnsupportedMediaType("text/html")))
}

pub fn runtime_has_a_valid_bounded_profile_test() {
  let assert Ok(access) =
    finance_sfc.access("pi-sparkles/0.1", "research@example.com")
  runtime.new(access) |> should.be_ok
}

fn instant(value: Int) -> time.Instant {
  let assert Ok(parsed) = time.instant(value)
  parsed
}
