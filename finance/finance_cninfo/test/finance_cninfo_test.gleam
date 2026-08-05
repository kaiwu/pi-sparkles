import finance_authority_snapshot/artifact
import finance_cninfo
import finance_cninfo/request
import finance_cninfo/response
import finance_cninfo/runtime
import finance_core/source
import finance_core/time
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

pub fn known_cninfo_document_is_exact_identified_and_bounded_test() {
  let assert Ok(access) =
    finance_cninfo.access("pi-sparkles/0.1", "research@example.com")
  let assert Ok(document) = finance_cninfo.document(2025, 8, 4, "1224386249")
  let assert Ok(value) = request.document(access, document)

  finance_cninfo.path(document)
  |> should.equal("/finalpage/2025-08-04/1224386249.PDF")
  finance_cninfo.canonical_url(document)
  |> should.equal(
    "https://static.cninfo.com.cn/finalpage/2025-08-04/1224386249.PDF",
  )
  http_request.method(value) |> should.equal(http_request.Get)
  http_request.origin(value) |> should.equal("https://static.cninfo.com.cn")
  http_request.path(value) |> should.equal(finance_cninfo.path(document))
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

pub fn document_reference_rejects_invalid_date_and_identifier_test() {
  finance_cninfo.document(2025, 2, 29, "1224386249")
  |> should.equal(Error(finance_cninfo.InvalidDate))
  finance_cninfo.document(2025, 8, 4, "../../secret")
  |> should.equal(Error(finance_cninfo.InvalidIdentifier))
  finance_cninfo.document(2025, 8, 4, "122438624")
  |> should.equal(Error(finance_cninfo.InvalidIdentifier))
}

pub fn pdf_is_captured_as_cninfo_repository_evidence_test() {
  let assert Ok(document) = finance_cninfo.document(2025, 8, 4, "1224386249")
  let assert Ok(raw) = pdf_response()
  let assert Ok(value) = response.capture(document, raw, instant(1000))

  artifact.track(value) |> should.equal(finance_track.Cn)
  artifact.authority_id(value) |> should.equal("cn_cninfo")
  artifact.source(value) |> source.provider |> should.equal("CNINFO")
  artifact.source(value) |> source.kind |> should.equal(source.Official)
  artifact.retrieval_route(value)
  |> should.equal("direct:CNINFO repository")
}

pub fn runtime_is_scoped_to_one_exact_document_path_test() {
  let assert Ok(access) =
    finance_cninfo.access("pi-sparkles/0.1", "research@example.com")
  let assert Ok(document) = finance_cninfo.document(2025, 8, 4, "1224386249")
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
