import finance_core/time
import finance_hkex
import finance_hkex/board_meeting
import gleam/json
import gleam/string
import gleeunit
import gleeunit/should
import pi_sparkles_stock_earnings_calendar/domain

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn exact_hk_plan_accepts_only_requested_board_and_canonical_range_test() {
  let assert Ok(value) =
    domain.plan("hk", "XHKG", "main", "00743", "2026-08-01", "2026-09-30")

  value.board |> should.equal(finance_hkex.MainBoard)
  value.code |> should.equal("00743")
  domain.plan("cn", "XHKG", "main", "00743", "2026-08-01", "2026-09-30")
  |> should.equal(Error(domain.WrongTrack("cn")))
  domain.plan("hk", "XNAS", "main", "00743", "2026-08-01", "2026-09-30")
  |> should.equal(Error(domain.WrongVenue("XNAS")))
  domain.plan("hk", "XHKG", "other", "00743", "2026-08-01", "2026-09-30")
  |> should.equal(Error(domain.InvalidBoard("other")))
}

pub fn plan_rejects_invalid_identity_dates_and_reversed_range_test() {
  domain.plan("hk", "XHKG", "gem", "743", "2026-08-01", "2026-09-30")
  |> should.equal(Error(domain.InvalidCode))
  domain.plan("hk", "XHKG", "gem", "00743", "2026-8-01", "2026-09-30")
  |> should.equal(Error(domain.InvalidStartDate))
  domain.plan("hk", "XHKG", "gem", "00743", "2026-08-01", "2026-02-30")
  |> should.equal(Error(domain.InvalidEndDate))
  domain.plan("hk", "XHKG", "gem", "00743", "2026-10-01", "2026-09-30")
  |> should.equal(Error(domain.ReversedRange))
}

pub fn result_rows_are_retained_and_non_result_rows_are_visible_test() {
  let assert Ok(plan) =
    domain.plan("hk", "XHKG", "main", "00743", "2026-08-01", "2026-09-30")
  let captured =
    capture([
      event(2026, 9, 10, "743", "RESULTS/DIV", "Y.E.30/06/26"),
      event(2026, 8, 7, "743", "INT RES/DIV", "6-MTH-ENDED30/06/26"),
      event(2026, 8, 8, "743", "SPECIAL DIVIDEND", ""),
      event(2026, 8, 9, "700", "INT RES", "6-MTH-ENDED30/06/26"),
    ])
  let assert Ok(output) = domain.run(plan, captured)
  let encoded = json.to_string(output.details)

  encoded |> string.contains("\"matchedCount\":2") |> should.be_true
  encoded
  |> string.contains("\"excludedSourceRowCount\":1")
  |> should.be_true
  encoded
  |> string.contains("\"nextBoardMeetingDate\":\"2026-08-07\"")
  |> should.be_true
  encoded
  |> string.contains("\"purpose\":\"SPECIAL DIVIDEND\"")
  |> should.be_true
  encoded
  |> string.contains("\"publicationTimestamp\":null")
  |> should.be_true
  output.summary
  |> string.contains("not publication timestamps")
  |> should.be_true
}

pub fn quarter_result_marker_is_mechanical_and_raw_purpose_is_preserved_test() {
  let assert Ok(plan) =
    domain.plan("hk", "XHKG", "gem", "08290", "2026-08-01", "2026-08-31")
  let assert Ok(output) =
    domain.run(
      plan,
      capture_on(finance_hkex.Gem, [
        event(2026, 8, 18, "8290", "2ND QUARTER RES", "6-MTH-ENDED30/06/26"),
      ]),
    )
  let encoded = json.to_string(output.details)

  encoded |> string.contains("\"resolution\":\"unique\"") |> should.be_true
  encoded
  |> string.contains("\"purpose\":\"2ND QUARTER RES\"")
  |> should.be_true
}

pub fn no_match_does_not_turn_non_exhaustive_page_into_absence_test() {
  let assert Ok(plan) =
    domain.plan("hk", "XHKG", "main", "00700", "2026-08-01", "2026-08-31")
  let assert Ok(output) = domain.run(plan, capture([]))
  let encoded = json.to_string(output.details)

  encoded
  |> string.contains("\"resolution\":\"no_match_on_non_exhaustive_page\"")
  |> should.be_true
  encoded |> string.contains("\"absenceClaim\":false") |> should.be_true
  encoded
  |> string.contains("\"completeness\":\"not_exhaustive_reference_only\"")
  |> should.be_true
  output.summary
  |> string.contains("No result-related row was found")
  |> should.be_true
}

pub fn duplicate_source_rows_remain_multiple_test() {
  let assert Ok(plan) =
    domain.plan("hk", "XHKG", "main", "00743", "2026-08-01", "2026-08-31")
  let row = event(2026, 8, 7, "743", "INT RES/DIV", "6-MTH-ENDED30/06/26")
  let assert Ok(output) = domain.run(plan, capture([row, row]))

  output.details
  |> json.to_string
  |> string.contains("\"resolution\":\"multiple_preserved\"")
  |> should.be_true
}

pub fn captured_board_must_equal_requested_board_test() {
  let assert Ok(plan) =
    domain.plan("hk", "XHKG", "main", "00743", "2026-08-01", "2026-08-31")

  domain.run(plan, capture_on(finance_hkex.Gem, []))
  |> should.equal(Error(domain.MismatchedBoard))
}

fn capture(events: List(board_meeting.Event)) -> board_meeting.Capture {
  capture_on(finance_hkex.MainBoard, events)
}

fn capture_on(
  board: finance_hkex.Board,
  events: List(board_meeting.Event),
) -> board_meeting.Capture {
  let assert Ok(retrieved_at) = time.instant(1_786_118_400_000)
  board_meeting.Capture(
    page: board_meeting.Page(date(2026, 8, 6), board, events),
    source_reference: "https://www3.hkexnews.hk/reports/bmn/ebmn.htm",
    retrieved_at: retrieved_at,
    evidence_id: "evidence-1",
    source_fingerprint: "source-1",
    media_type: "text/html",
    response_byte_length: 100,
    content_sha256: string.repeat("a", 64),
    canonical_digest: string.repeat("b", 64),
  )
}

fn event(
  year: Int,
  month: Int,
  day: Int,
  source_code: String,
  purpose: String,
  period: String,
) -> board_meeting.Event {
  board_meeting.Event(
    board_meeting_date: date(year, month, day),
    short_name: "TEST ISSUER",
    source_code: source_code,
    code: string.repeat("0", 5 - string.length(source_code)) <> source_code,
    purpose: purpose,
    period: period,
  )
}

fn date(year: Int, month: Int, day: Int) -> time.Date {
  let assert Ok(value) = time.date(year, month, day)
  value
}
