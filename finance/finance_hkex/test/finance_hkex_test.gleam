import finance_authority_snapshot/artifact
import finance_core/source
import finance_core/time
import finance_hkex
import finance_hkex/board_meeting
import finance_hkex/board_meeting_runtime
import finance_hkex/current_security_reference
import finance_hkex/discovery_runtime
import finance_hkex/full_list
import finance_hkex/listing_runtime
import finance_hkex/recent_listing
import finance_hkex/recent_listing_reference
import finance_hkex/request
import finance_hkex/response
import finance_hkex/runtime
import finance_hkex/securities_runtime
import finance_hkex/security_search
import finance_hkex/title_search
import finance_http/binary_response
import finance_http/request as http_request
import finance_http/response as http_response
import finance_track
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
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
    "callback({\"more\":\"1\",\"stockInfo\":[{\"stockId\":7609,\"code\":\"00700\",\"name\":\"TENCENT\"}]});"
  let assert Ok([security]) = security_search.decode(fixture)
  let assert Ok(page) = security_search.decode_page(fixture)

  http_request.path(request_value) |> should.equal("/search/prefix.do")
  http_request.maximum_response_bytes(request_value) |> should.equal(2_000_000)
  http_request.query(request_value)
  |> list.any(fn(parameter) {
    parameter
    == http_request.QueryParameter("callback", "callback", http_request.Public)
  })
  |> should.be_true
  http_request.query(request_value)
  |> list.any(fn(parameter) {
    parameter
    == http_request.QueryParameter("name", "00700", http_request.Public)
  })
  |> should.be_true
  security_search.stock_id(security) |> should.equal(7609)
  security_search.code(security) |> should.equal("00700")
  security_search.page_more(page) |> should.equal("1")
}

pub fn full_list_request_and_runtime_are_exact_binary_boundaries_test() {
  let assert Ok(access) =
    finance_hkex.access("pi-sparkles/0.1", "research@example.com")
  let assert Ok(value) = request.full_list(access)

  http_request.method(value) |> should.equal(http_request.Get)
  http_request.origin(value) |> should.equal("https://www.hkex.com.hk")
  http_request.path(value) |> should.equal(request.full_list_path)
  http_request.maximum_response_bytes(value) |> should.equal(2_000_000)
  time.duration_milliseconds(http_request.timeout(value))
  |> should.equal(30_000)
  securities_runtime.new(access) |> should.be_ok
}

pub fn full_list_decoder_preserves_exact_current_exchange_profile_test() {
  let assert Ok(value) =
    full_list.decode(
      "00700",
      content_types_fixture(),
      workbook_fixture(),
      relationships_fixture(),
      shared_strings_fixture(),
      worksheet_fixture("TENCENT &amp; HOLDINGS"),
    )
  let assert [profile] = full_list.candidates(value)

  time.date_parts(full_list.updated_as(value)) |> should.equal(#(2026, 8, 6))
  full_list.resolution(value) |> should.equal("unique")
  full_list.code(profile) |> should.equal("00700")
  full_list.name(profile) |> should.equal("TENCENT & HOLDINGS")
  full_list.category(profile) |> should.equal("Equity")
  full_list.subcategory(profile)
  |> should.equal("Equity Securities (Main Board)")
  full_list.board(profile) |> should.equal(Some("main_board"))
  full_list.board_lot(profile) |> should.equal("100")
  full_list.isin(profile) |> should.equal("KYG875721634")
  full_list.spread_table(profile) |> should.equal("1 ")
  full_list.trading_currency(profile) |> should.equal("HKD")
  full_list.rmb_counter(profile) |> should.equal("80700")
}

pub fn recent_listing_request_runtime_and_decoder_are_exact_test() {
  let assert Ok(access) =
    finance_hkex.access("pi-sparkles/0.1", "research@example.com")
  let assert Ok(request_value) = request.recent_listings(access)
  let fixture = recent_listing_fixture("New Listing")
  let assert Ok(page) = recent_listing.decode(fixture, "03308")
  let assert [event] = recent_listing.candidates(page)

  http_request.method(request_value) |> should.equal(http_request.Get)
  http_request.origin(request_value) |> should.equal("https://www.hkex.com.hk")
  http_request.path(request_value) |> should.equal(request.recent_listings_path)
  http_request.maximum_response_bytes(request_value) |> should.equal(4_000_000)
  time.duration_milliseconds(http_request.timeout(request_value))
  |> should.equal(30_000)
  http_request.query(request_value)
  |> list.any(fn(parameter) {
    parameter
    == http_request.QueryParameter("sc_lang", "en", http_request.Public)
  })
  |> should.be_true
  listing_runtime.new(access) |> should.be_ok
  time.date_parts(recent_listing.updated_as(page))
  |> should.equal(#(2026, 8, 6))
  recent_listing.resolution(page) |> should.equal("unique")
  recent_listing.event_date(event)
  |> time.date_parts
  |> should.equal(#(2026, 7, 30))
  recent_listing.short_name(event) |> should.equal("ZJ INNOLIGHT")
  recent_listing.code(event) |> should.equal("03308")
  recent_listing.board_lot(event) |> should.equal("50")
  recent_listing.ccass_marker(event) |> should.equal("#")
  recent_listing.short_sell_marker(event) |> should.equal("H")
  recent_listing.stamp_duty_marker(event) |> should.equal("S")
  recent_listing.auction_marker(event) |> should.equal("%")
  recent_listing.corporate_action(event) |> should.equal("New Listing")
  recent_listing.listing_effective_from(event)
  |> should.equal(Some(event |> recent_listing.event_date))
}

pub fn recent_listing_claim_fails_closed_for_tentative_or_other_actions_test() {
  let fixture = recent_listing_fixture("New Listing")
  let assert Ok(tentative_page) = recent_listing.decode(fixture, "02261")
  let assert [tentative] = recent_listing.candidates(tentative_page)
  recent_listing.tentative(tentative) |> should.be_true
  recent_listing.listing_effective_from(tentative) |> should.equal(None)

  let assert Ok(other_page) =
    recent_listing.decode(
      recent_listing_fixture("Share Consolidation"),
      "03308",
    )
  let assert [other] = recent_listing.candidates(other_page)
  recent_listing.listing_effective_from(other) |> should.equal(None)
}

pub fn recent_listing_reference_binds_page_and_narrow_listing_claim_test() {
  let fixture = recent_listing_fixture("New Listing")
  let changed_fixture = recent_listing_fixture("Share Consolidation")
  let assert Ok(query) = security_search.query("03308")
  let assert Ok(response_value) = html_response(fixture)
  let assert Ok(changed_response) = html_response(changed_fixture)
  let assert Ok(reference) =
    recent_listing_reference.capture(query, response_value, instant(1000))
  let assert Ok(changed) =
    recent_listing_reference.capture(query, changed_response, instant(1000))

  recent_listing_reference.query_code(reference) |> should.equal("03308")
  recent_listing_reference.resolution(reference) |> should.equal("unique")
  recent_listing_reference.source_reference(reference)
  |> should.equal(
    "https://www.hkex.com.hk/Services/Trading/Securities/Trading-News/Newly-Listed-Securities?sc_lang=en",
  )
  recent_listing_reference.response_byte_length(reference)
  |> should.equal(string.byte_size(fixture))
  recent_listing_reference.content_sha256(reference)
  |> string.length
  |> should.equal(64)
  recent_listing_reference.canonical_text(reference)
  |> string.contains("\"listing_effective_from\":\"2026-07-30\"")
  |> should.be_true
  recent_listing_reference.canonical_text(reference)
  |> string.contains("\"trading_status\":null")
  |> should.be_true
  recent_listing_reference.canonical_digest(reference)
  |> should.not_equal(recent_listing_reference.canonical_digest(changed))
}

pub fn recent_listing_decoder_rejects_header_and_duplicate_drift_test() {
  recent_listing.decode(
    recent_listing_fixture("New Listing")
      |> string.replace("Board Lot", "Lot Size"),
    "03308",
  )
  |> should.equal(Error(recent_listing.HeaderMismatch))
  recent_listing.decode(
    recent_listing_fixture("New Listing")
      |> string.replace(
        "</tbody>",
        recent_listing_row("30/07/2026", "ZJ INNOLIGHT", "03308", "New Listing")
          <> "</tbody>",
      ),
    "03308",
  )
  |> should.equal(Error(recent_listing.DuplicateCode("03308")))
}

pub fn board_meeting_request_runtime_and_decoder_preserve_raw_rows_test() {
  let assert Ok(access) =
    finance_hkex.access("pi-sparkles/0.1", "research@example.com")
  let assert Ok(request_value) =
    request.board_meetings(access, finance_hkex.MainBoard)
  let assert Ok(page) =
    board_meeting.decode(board_meeting_fixture(), finance_hkex.MainBoard)
  let assert [first, second] = page.events

  http_request.method(request_value) |> should.equal(http_request.Get)
  http_request.origin(request_value)
  |> should.equal("https://www3.hkexnews.hk")
  http_request.path(request_value)
  |> should.equal("/reports/bmn/ebmn.htm")
  http_request.maximum_response_bytes(request_value) |> should.equal(2_000_000)
  time.duration_milliseconds(http_request.timeout(request_value))
  |> should.equal(30_000)
  board_meeting_runtime.new(access) |> should.be_ok
  time.date_parts(page.page_date) |> should.equal(#(2026, 8, 6))
  page.board |> should.equal(finance_hkex.MainBoard)
  first.source_code |> should.equal("743")
  first.code |> should.equal("00743")
  first.short_name |> should.equal("ASIA CEMENT CH")
  first.purpose |> should.equal("INT RES/DIV")
  first.period |> should.equal("6-MTH-ENDED30/06/26")
  second.source_code |> should.equal("80016")
  second.code |> should.equal("80016")
}

pub fn board_meeting_capture_binds_scope_and_page_content_test() {
  let fixture = board_meeting_fixture()
  let changed = string.replace(fixture, "INT RES/DIV", "DIVIDEND")
  let assert Ok(response_value) = html_response(fixture)
  let assert Ok(changed_response) = html_response(changed)
  let assert Ok(captured) =
    board_meeting.capture(finance_hkex.MainBoard, response_value, instant(1000))
  let assert Ok(changed_capture) =
    board_meeting.capture(
      finance_hkex.MainBoard,
      changed_response,
      instant(1000),
    )

  captured.source_reference
  |> should.equal("https://www3.hkexnews.hk/reports/bmn/ebmn.htm")
  captured.response_byte_length |> should.equal(string.byte_size(fixture))
  captured.content_sha256 |> string.length |> should.equal(64)
  captured.canonical_digest |> string.length |> should.equal(64)
  captured.canonical_digest
  |> should.not_equal(changed_capture.canonical_digest)
}

pub fn board_meeting_decoder_rejects_semantic_and_header_drift_test() {
  board_meeting.decode(
    board_meeting_fixture()
      |> string.replace("This list may not be exhaustive", "Complete list"),
    finance_hkex.MainBoard,
  )
  |> should.equal(Error(board_meeting.InvalidEnvelope))
  board_meeting.decode(
    board_meeting_fixture()
      |> string.replace(">Purpose</font>", ">Agenda</font>"),
    finance_hkex.MainBoard,
  )
  |> should.equal(Error(board_meeting.HeaderMismatch))
  board_meeting.decode(
    board_meeting_fixture()
      |> string.replace("07/08/2026", "2026-08-07"),
    finance_hkex.MainBoard,
  )
  |> should.equal(Error(board_meeting.InvalidEventRow))
}

pub fn current_security_reference_binds_exact_response_and_unknown_claims_test() {
  let fixture =
    "callback({\"more\":\"1\",\"stockInfo\":[{\"stockId\":7609,\"code\":\"00700\",\"name\":\"TENCENT\"}]});"
  let changed_fixture =
    "callback({\"more\":\"1\",\"stockInfo\":[{\"stockId\":7609,\"code\":\"00700\",\"name\":\"TENCENT HOLDINGS\"}]});"
  let assert Ok(query) = security_search.query("00700")
  let assert Ok(response_value) = text_response(fixture)
  let assert Ok(changed_response) = text_response(changed_fixture)
  let assert Ok(reference) =
    current_security_reference.capture(query, response_value, instant(1000))
  let assert Ok(changed) =
    current_security_reference.capture(query, changed_response, instant(1000))

  current_security_reference.query_code(reference) |> should.equal("00700")
  current_security_reference.resolution(reference) |> should.equal("unique")
  current_security_reference.provider_more_marker(reference)
  |> should.equal("1")
  current_security_reference.source_reference(reference)
  |> should.equal(
    "https://www1.hkexnews.hk/search/prefix.do?callback=callback&lang=EN&type=A&name=00700&market=SEHK",
  )
  current_security_reference.response_byte_length(reference)
  |> should.equal(string.byte_size(fixture))
  current_security_reference.content_sha256(reference)
  |> string.length
  |> should.equal(64)
  current_security_reference.canonical_text(reference)
  |> string.contains("\"trading_status\":null")
  |> should.be_true
  current_security_reference.canonical_digest(reference)
  |> should.not_equal(current_security_reference.canonical_digest(changed))
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
  security_search.decode("pi_sparkles({\"more\":\"1\",\"stockInfo\":[]});")
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

fn text_response(
  body: String,
) -> Result(http_response.Response, http_response.ResponseError) {
  http_response.new(
    200,
    [http_response.Header("content-type", "application/javascript")],
    body,
    string.byte_size(body),
    duration(5),
  )
}

fn html_response(
  body: String,
) -> Result(http_response.Response, http_response.ResponseError) {
  http_response.new(
    200,
    [http_response.Header("content-type", "text/html; charset=utf-8")],
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

fn recent_listing_fixture(action: String) -> String {
  "<html><h2>Newly Listed Securities</h2>"
  <> "Newly Listed and/or Traded Securities in the Current&nbsp;Two Weeks"
  <> "<table class=\"table migrate\" cellspacing=\"0\"><thead><tr>"
  <> recent_listing_header("Date of Listing / Traded")
  <> recent_listing_header("Stock Short Name")
  <> recent_listing_header("Stock Code")
  <> recent_listing_header("Board Lot")
  <> recent_listing_header("Remarks")
  <> recent_listing_header("")
  <> recent_listing_header("")
  <> recent_listing_header("")
  <> recent_listing_header("Corresponding Corporate Action")
  <> recent_listing_header("Related Stock Code")
  <> "</tr></thead><tbody>"
  <> recent_listing_row("07/08/2026*", "NASN TECH", "02261", "New Listing")
  <> recent_listing_row("30/07/2026", "ZJ INNOLIGHT", "03308", action)
  <> "</tbody></table>* Being the tentative date of&nbsp;listing / traded"
  <> "<p class=\"loadMore__timetag\">Updated 06 Aug 2026</p></html>"
}

fn board_meeting_fixture() -> String {
  "<html><span id=\"Title2\">Board Meeting Notifications</span>"
  <> "<font class=textfont><br/>Date : 06/08/2026<br/><br/>"
  <> "The following table is a consolidated list of board meeting dates<br/>announced by listed issuers.  This list may not be exhaustive<br/>and is for reference only."
  <> "<br/>Note: only the start date of the board meeting will be updated</font>"
  <> "<table class=textfont><tr><td><font>BM Date</font></td>"
  <> "<td><font></font></td><td><font>Stock Short Name<td><font>&nbsp;Code</font></td>"
  <> "<td><font>Purpose</font></td><td><font>Period</font></td></font></td></tr>"
  <> board_meeting_row(
    "07/08/2026",
    "ASIA CEMENT CH",
    "743",
    "INT RES/DIV",
    "6-MTH-ENDED30/06/26",
  )
  <> board_meeting_row(
    "10/09/2026",
    "SHK PPT-R",
    "80016",
    "FIN RES/DIV",
    "Y.E.30/06/26",
  )
  <> "</table></html>"
}

fn board_meeting_row(
  date: String,
  name: String,
  code: String,
  purpose: String,
  period: String,
) -> String {
  "<tr><td width=75 valign=top><font>"
  <> date
  <> "</font></td><td width=30 valign=top align=right><font></font></td>"
  <> "<td width=120 valign=top><font>"
  <> name
  <> "</font></td><td width=50 valign=top><font>&nbsp;"
  <> code
  <> "</font></td><td width=140 valign=top><font>"
  <> purpose
  <> "</font></td><td valign=top><font>"
  <> period
  <> "</font></td></tr>"
}

fn recent_listing_header(value: String) -> String {
  "<th style=\"text-align: center;\"><strong><span>"
  <> value
  <> "</span></strong></th>"
}

fn recent_listing_row(
  date: String,
  name: String,
  code: String,
  action: String,
) -> String {
  "<tr><td style=\"text-align: center;\">"
  <> date
  <> "</td><td><a href=\"/quote\">"
  <> name
  <> "</a></td><td>"
  <> code
  <> "</td><td>50</td><td>#</td><td>H</td><td>S</td><td>%</td><td>"
  <> action
  <> "</td><td></td></tr>"
}

fn content_types_fixture() -> String {
  "<Types><Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/><Override PartName=\"/xl/worksheets/sheet1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/><Override PartName=\"/xl/sharedStrings.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml\"/></Types>"
}

fn workbook_fixture() -> String {
  "<x:workbook><x:sheets><x:sheet name=\"ListOfSecurities\" sheetId=\"1\" r:id=\"rId1\" /></x:sheets></x:workbook>"
}

fn relationships_fixture() -> String {
  "<Relationships><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet1.xml\"/></Relationships>"
}

fn shared_strings_fixture() -> String {
  "<x:sst><x:si><x:t>Spread Table</x:t></x:si></x:sst>"
}

fn worksheet_fixture(name: String) -> String {
  let headers = [
    #("A", "Stock Code"),
    #("B", "Name of Securities"),
    #("C", "Category"),
    #("D", "Sub-Category"),
    #("E", "Board Lot"),
    #("F", "ISIN"),
    #("G", "Expiry Date"),
    #("H", "Subject to Stamp Duty"),
    #("I", "Shortsell Eligible"),
    #("J", "CAS Eligible"),
    #("K", "VCM Eligible"),
    #("L", "Admitted to CCASS"),
    #("M", "Debt Securities Board Lot (Nominal)"),
    #("N", "Debt Securities Investor Type"),
    #("O", "POS Eligible"),
    #("P", "4"),
    #("Q", "Trading Currency"),
    #("R", "RMB Counter"),
  ]
  let values = [
    #("A", "00700"),
    #("B", name),
    #("C", "Equity"),
    #("D", "Equity Securities (Main Board)"),
    #("E", "100"),
    #("F", "KYG875721634"),
    #("G", ""),
    #("H", "Y"),
    #("I", "Y"),
    #("J", "Y"),
    #("K", "Y"),
    #("L", "Y"),
    #("M", ""),
    #("N", ""),
    #("O", "Y"),
    #("P", "1 "),
    #("Q", "HKD"),
    #("R", "80700"),
  ]
  "<x:worksheet><x:sheetData>"
  <> xml_row(2, [#("A", "Updated as at 06/08/2026")])
  <> xml_row(3, headers)
  <> xml_row(4, values)
  <> "</x:sheetData></x:worksheet>"
}

fn xml_row(number: Int, values: List(#(String, String))) -> String {
  "<x:row r=\""
  <> int.to_string(number)
  <> "\">"
  <> {
    values
    |> list.map(fn(value) {
      let #(column, text) = value
      "<x:c r=\""
      <> column
      <> int.to_string(number)
      <> "\" t=\"str\"><x:v>"
      <> text
      <> "</x:v></x:c>"
    })
    |> string.join("")
  }
  <> "</x:row>"
}
