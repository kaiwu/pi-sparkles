import finance_authority_snapshot/artifact
import finance_core/source
import finance_core/time
import finance_hkex
import finance_hkex/discovery_runtime
import finance_hkex/request
import finance_hkex/response
import finance_hkex/runtime
import finance_hkex/security_search
import finance_hkex/title_search
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

pub fn public_security_lookup_is_bounded_jsonp_and_exact_test() {
  let assert Ok(access) =
    finance_hkex.access("pi-sparkles/0.1", "research@example.com")
  let assert Ok(query) = security_search.query("00700")
  let assert Ok(request_value) = request.security_prefix(access, query)
  let fixture =
    "pi_sparkles({\"more\":\"1\",\"stockInfo\":[{\"stockId\":7609,\"code\":\"00700\",\"name\":\"TENCENT\"}]});"
  let assert Ok([security]) = security_search.decode(fixture)

  http_request.path(request_value) |> should.equal("/search/prefix.do")
  http_request.maximum_response_bytes(request_value) |> should.equal(2_000_000)
  http_request.query(request_value)
  |> list.any(fn(parameter) {
    parameter
    == http_request.QueryParameter("name", "00700", http_request.Public)
  })
  |> should.be_true
  security_search.stock_id(security) |> should.equal(7609)
  security_search.code(security) |> should.equal("00700")
}

pub fn title_search_preserves_identity_document_and_initial_page_gap_test() {
  let assert Ok(access) =
    finance_hkex.access("pi-sparkles/0.1", "research@example.com")
  let assert Ok(plan) = title_search.plan(7609, "00700", 1)
  let assert Ok(request_value) = request.titles(access, plan)
  let fixture =
    "<html><input id=\"stockId\" type=\"hidden\" value=\"7609\" /><input id=\"stockCode\" type=\"hidden\" value=\"00700 TENCENT\" /><div class=\"total-records\">Total records found: 259 </div><table><tr><td class=\"text-right text-end release-time\"><span class=\"mobile-list-heading\">Release Time: </span>09/07/2026 17:58</td><td class=\"text-right text-end stock-short-code\"><span class=\"mobile-list-heading\">Stock Code: </span>00700<br/>80700</td><td class=\"stock-short-name\"><span class=\"mobile-list-heading\">Stock Short Name: </span>TENCENT<br/>TENCENT-R</td><td><div class=\"headline\">Next Day Disclosure Returns - [Share Buyback]<br/></div><div class=\"doc-link\"><a href=\"/listedco/listconews/sehk/2026/0709/2026070900827.pdf\" rel=\"noopener noreferrer\" target=\"_blank\">Next Day Disclosure Return &amp; Notice</a> (<span class=\"attachment_filesize\">89KB</span>)</div></td></tr></table></html>"
  let assert Ok(page) = title_search.decode(fixture, plan)
  let assert [document] = title_search.documents(page)

  http_request.path(request_value) |> should.equal("/search/titlesearch.xhtml")
  http_request.maximum_response_bytes(request_value) |> should.equal(8_000_000)
  title_search.requested_code(page) |> should.equal("00700")
  title_search.requested_name(page) |> should.equal("TENCENT")
  title_search.total_records(page) |> should.equal(259)
  title_search.truncated(page) |> should.be_true
  title_search.codes(document) |> should.equal(["00700", "80700"])
  title_search.names(document) |> should.equal(["TENCENT", "TENCENT-R"])
  title_search.title(document)
  |> should.equal("Next Day Disclosure Return & Notice")
  title_search.reference(document)
  |> finance_hkex.canonical_url
  |> should.equal(
    "https://www1.hkexnews.hk/listedco/listconews/sehk/2026/0709/2026070900827.pdf",
  )
}

pub fn discovery_decoders_reject_wrappers_and_identity_mismatch_test() {
  security_search.query("700")
  |> should.equal(Error(security_search.InvalidCode))
  security_search.decode("callback({\"more\":\"1\",\"stockInfo\":[]});")
  |> should.equal(Error(security_search.InvalidJsonp))
  let assert Ok(plan) = title_search.plan(7609, "00700", 10)
  title_search.decode(
    "<input id=\"stockId\" type=\"hidden\" value=\"1\" /><input id=\"stockCode\" type=\"hidden\" value=\"00001 OTHER\" /><div class=\"total-records\">Total records found: 0 </div>",
    plan,
  )
  |> should.equal(Error(title_search.InvalidSearchIdentity))
}

pub fn discovery_runtime_is_allowlisted_test() {
  let assert Ok(access) =
    finance_hkex.access("pi-sparkles/0.1", "research@example.com")
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

fn instant(value: Int) -> time.Instant {
  let assert Ok(parsed) = time.instant(value)
  parsed
}

fn duration(value: Int) -> time.Duration {
  let assert Ok(parsed) = time.duration(value)
  parsed
}
