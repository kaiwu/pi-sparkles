import finance_authority_snapshot/artifact
import finance_cninfo
import finance_cninfo/current_security_reference
import finance_cninfo/disclosure
import finance_cninfo/discovery_runtime
import finance_cninfo/request
import finance_cninfo/response
import finance_cninfo/runtime
import finance_cninfo/security_master
import finance_core/identifier
import finance_core/source
import finance_core/time
import finance_http/binary_response
import finance_http/request as http_request
import finance_http/response as http_response
import finance_track
import gleam/list
import gleam/option.{Some}
import gleam/string
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

pub fn public_security_master_is_bounded_and_preserves_candidates_test() {
  let assert Ok(access) =
    finance_cninfo.access("pi-sparkles/0.1", "research@example.com")
  let assert Ok(request_value) = request.security_master(access)
  let fixture =
    "{\"stockList\":[{\"code\":\"000001\",\"pinyin\":\"payh\",\"category\":\"A股\",\"orgId\":\"gssz0000001\",\"zwjc\":\"平安银行\"}]}"
  let assert Ok(values) = security_master.decode(fixture)
  let assert identifier.Unique(value) =
    security_master.resolve_code(values, code: "000001")

  http_request.origin(request_value)
  |> should.equal("https://www.cninfo.com.cn")
  http_request.path(request_value)
  |> should.equal("/new/data/szse_stock.json")
  http_request.maximum_response_bytes(request_value) |> should.equal(5_000_000)
  security_master.organization_id(value) |> should.equal("gssz0000001")
  security_master.short_name(value) |> should.equal("平安银行")
}

pub fn current_security_reference_binds_repository_snapshot_and_unknown_venue_test() {
  let fixture =
    "{\"stockList\":[{\"code\":\"000001\",\"pinyin\":\"payh\",\"category\":\"A股\",\"orgId\":\"gssz0000001\",\"zwjc\":\"平安银行\"}]}"
  let changed_fixture =
    "{\"stockList\":[{\"code\":\"000001\",\"pinyin\":\"payh\",\"category\":\"A股\",\"orgId\":\"gssz0000001\",\"zwjc\":\"平安银行股份有限公司\"}]}"
  let assert Ok(response_value) = text_response(fixture)
  let assert Ok(changed_response) = text_response(changed_fixture)
  let assert Ok(reference) =
    current_security_reference.capture("000001", response_value, instant(1000))
  let assert Ok(changed) =
    current_security_reference.capture(
      "000001",
      changed_response,
      instant(1000),
    )

  current_security_reference.query_code(reference) |> should.equal("000001")
  current_security_reference.resolution(reference) |> should.equal("unique")
  current_security_reference.source_reference(reference)
  |> should.equal("https://www.cninfo.com.cn/new/data/szse_stock.json")
  current_security_reference.response_byte_length(reference)
  |> should.equal(string.byte_size(fixture))
  current_security_reference.content_sha256(reference)
  |> string.length
  |> should.equal(64)
  current_security_reference.canonical_text(reference)
  |> string.contains("\"venue_mic\":null")
  |> should.be_true
  current_security_reference.canonical_digest(reference)
  |> should.not_equal(current_security_reference.canonical_digest(changed))
}

pub fn announcement_query_is_repeatable_bounded_and_exact_identified_test() {
  let assert Ok(access) =
    finance_cninfo.access("pi-sparkles/0.1", "research@example.com")
  let assert Ok(start) = time.date(2025, 1, 1)
  let assert Ok(end) = time.date(2026, 8, 5)
  let assert Ok(plan) =
    disclosure.query(
      code: "000001",
      organization_id: "gssz0000001",
      start_date: start,
      end_date: end,
      category: disclosure.AnnualReport,
      page: 1,
      page_size: 3,
    )
  let assert Ok(request_value) = request.announcements(access, plan)
  let fixture =
    "{\"totalAnnouncement\":1,\"totalpages\":1,\"hasMore\":false,\"announcements\":[{\"secCode\":\"000001\",\"secName\":\"平安银行\",\"orgId\":\"gssz0000001\",\"announcementId\":\"1225022887\",\"announcementTitle\":\"2025年年度报告\",\"announcementTime\":1774022400000,\"adjunctUrl\":\"finalpage/2026-03-21/1225022887.PDF\",\"adjunctSize\":1930,\"announcementType\":\"01010503||010112||010301\"}]}"
  let assert Ok(page) = disclosure.decode_page(fixture)
  let assert [announcement] = disclosure.announcements(page)
  let assert Some(http_request.TextBody(_, body)) =
    http_request.body(request_value)

  http_request.method(request_value) |> should.equal(http_request.Post)
  http_request.idempotency(request_value)
  |> should.equal(http_request.RepeatableRead)
  http_request.maximum_response_bytes(request_value) |> should.equal(5_000_000)
  string.contains(body, "stock=000001%2Cgssz0000001") |> should.be_true
  string.contains(body, "category=category_ndbg_szsh") |> should.be_true
  disclosure.announcement_id(announcement) |> should.equal("1225022887")
  disclosure.announcement_document(announcement)
  |> finance_cninfo.canonical_url
  |> should.equal(
    "https://static.cninfo.com.cn/finalpage/2026-03-21/1225022887.PDF",
  )
}

pub fn discovery_decoders_reject_identity_mismatch_test() {
  security_master.decode(
    "{\"stockList\":[{\"code\":\"1\",\"pinyin\":\"x\",\"category\":\"A股\",\"orgId\":\"org\",\"zwjc\":\"名称\"}]}",
  )
  |> should.be_error
  disclosure.decode_page(
    "{\"totalAnnouncement\":1,\"totalpages\":1,\"hasMore\":false,\"announcements\":[{\"secCode\":\"000001\",\"secName\":\"平安银行\",\"orgId\":\"gssz0000001\",\"announcementId\":\"1225022887\",\"announcementTitle\":\"年报\",\"announcementTime\":1,\"adjunctUrl\":\"finalpage/2026-03-21/1225022886.PDF\",\"adjunctSize\":1,\"announcementType\":null}]}",
  )
  |> should.be_error
}

pub fn discovery_runtime_is_allowlisted_test() {
  let assert Ok(access) =
    finance_cninfo.access("pi-sparkles/0.1", "research@example.com")
  discovery_runtime.new(access) |> should.be_ok
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

fn text_response(
  body: String,
) -> Result(http_response.Response, http_response.ResponseError) {
  http_response.new(
    200,
    [http_response.Header("content-type", "application/json")],
    body,
    string.byte_size(body),
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
