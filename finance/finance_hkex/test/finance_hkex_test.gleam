import finance_authority_snapshot/artifact
import finance_core/source
import finance_core/time
import finance_hkex
import finance_hkex/request
import finance_hkex/response
import finance_hkex/runtime
import finance_http/binary_response
import finance_http/request as http_request
import finance_http/response as http_response
import finance_track
import gleam/list
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn known_hkexnews_document_is_exact_identified_and_bounded_test() {
  let assert Ok(access) =
    finance_hkex.access("pi-sparkles/0.1", "research@example.com")
  let assert Ok(document) = finance_hkex.document(2026, 3, 31, "2026033103673")
  let assert Ok(value) = request.document(access, document)

  finance_hkex.path(document)
  |> should.equal("/listedco/listconews/sehk/2026/0331/2026033103673.pdf")
  finance_hkex.canonical_url(document)
  |> should.equal(
    "https://www1.hkexnews.hk/listedco/listconews/sehk/2026/0331/2026033103673.pdf",
  )
  http_request.method(value) |> should.equal(http_request.Get)
  http_request.origin(value) |> should.equal("https://www1.hkexnews.hk")
  http_request.path(value) |> should.equal(finance_hkex.path(document))
  http_request.maximum_response_bytes(value) |> should.equal(25_000_000)
  time.duration_milliseconds(http_request.timeout(value))
  |> should.equal(20_000)
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

pub fn document_reference_proves_identifier_date_coherence_test() {
  finance_hkex.document(2026, 2, 29, "2026022903673")
  |> should.equal(Error(finance_hkex.InvalidDate))
  finance_hkex.document(2026, 3, 31, "2026033003673")
  |> should.equal(Error(finance_hkex.IdentifierDateMismatch("20260331")))
  finance_hkex.document(2026, 3, 31, "not-an-id")
  |> should.equal(Error(finance_hkex.InvalidIdentifier))
}

pub fn pdf_is_captured_as_hkexnews_exchange_evidence_test() {
  let assert Ok(document) = finance_hkex.document(2026, 3, 31, "2026033103673")
  let assert Ok(raw) = pdf_response()
  let assert Ok(value) = response.capture(document, raw, instant(1000))

  artifact.track(value) |> should.equal(finance_track.Hk)
  artifact.authority_id(value) |> should.equal("hk_hkexnews")
  artifact.source(value) |> source.provider |> should.equal("HKEXnews")
  artifact.source(value) |> source.kind |> should.equal(source.Exchange)
  artifact.retrieval_route(value) |> should.equal("direct:HKEXnews")
}

pub fn runtime_is_scoped_to_one_exact_document_path_test() {
  let assert Ok(access) =
    finance_hkex.access("pi-sparkles/0.1", "research@example.com")
  let assert Ok(document) = finance_hkex.document(2026, 3, 31, "2026033103673")
  runtime.new(access, document) |> should.be_ok
}

fn pdf_response() -> Result(
  binary_response.Response,
  binary_response.ResponseError,
) {
  binary_response.new(
    200,
    [http_response.Header("content-type", "application/pdf")],
    "JVBERi0=",
    5,
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "255044462d",
    duration(5),
  )
}

fn instant(value: Int) -> time.Instant {
  let assert Ok(parsed) = time.instant(value)
  parsed
}

fn duration(value: Int) -> time.Duration {
  let assert Ok(parsed) = time.duration(value)
  parsed
}
