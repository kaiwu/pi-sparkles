import gleam/json
import gleam/string
import gleeunit
import gleeunit/should
import pi_sparkles_finance_calendar/domain

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn all_six_exact_track_mic_pairs_keep_their_venue_sources_test() {
  let assert Ok(xshg) =
    domain.inspect_session(domain.InspectInput("cn", "XSHG", "2026-03-10"))
  let assert Ok(xshe) =
    domain.inspect_session(domain.InspectInput("cn", "XSHE", "2026-03-10"))
  let assert Ok(xbse) =
    domain.inspect_session(domain.InspectInput("cn", "XBSE", "2026-03-10"))
  let assert Ok(xhkg) =
    domain.inspect_session(domain.InspectInput("hk", "XHKG", "2026-03-10"))
  let assert Ok(xnys) =
    domain.inspect_session(domain.InspectInput("us", "XNYS", "2026-03-10"))
  let assert Ok(xnas) =
    domain.inspect_session(domain.InspectInput("us", "XNAS", "2026-03-10"))

  let xshg_text = json.to_string(xshg.details)
  xshg_text |> string.contains("\"track\":\"cn\"") |> should.be_true
  xshg_text |> string.contains("\"venue\":\"XSHG\"") |> should.be_true
  xshg_text |> string.contains("\"provider\":\"sse\"") |> should.be_true

  let xshe_text = json.to_string(xshe.details)
  xshe_text |> string.contains("\"venue\":\"XSHE\"") |> should.be_true
  xshe_text |> string.contains("\"provider\":\"szse\"") |> should.be_true

  let xbse_text = json.to_string(xbse.details)
  xbse_text |> string.contains("\"venue\":\"XBSE\"") |> should.be_true
  xbse_text |> string.contains("\"provider\":\"bse\"") |> should.be_true

  let xhkg_text = json.to_string(xhkg.details)
  xhkg_text |> string.contains("\"track\":\"hk\"") |> should.be_true
  xhkg_text |> string.contains("\"venue\":\"XHKG\"") |> should.be_true
  xhkg_text |> string.contains("\"provider\":\"hkex\"") |> should.be_true

  let xnys_text = json.to_string(xnys.details)
  xnys_text |> string.contains("\"track\":\"us\"") |> should.be_true
  xnys_text |> string.contains("\"venue\":\"XNYS\"") |> should.be_true
  xnys_text |> string.contains("\"provider\":\"nyse\"") |> should.be_true

  let xnas_text = json.to_string(xnas.details)
  xnas_text |> string.contains("\"venue\":\"XNAS\"") |> should.be_true
  xnas_text |> string.contains("\"provider\":\"nasdaq\"") |> should.be_true
}

pub fn inspect_preserves_cn_ordered_phases_and_closed_day_reason_test() {
  let assert Ok(open) =
    domain.inspect_session(domain.InspectInput("cn", "XSHG", "2026-02-24"))
  let open_text = json.to_string(open.details)
  open_text
  |> string.contains("\"sessionType\":\"regular_full\"")
  |> should.be_true
  open_text
  |> string.contains(
    "\"label\":\"opening_call_auction\",\"opensAt\":\"09:15\",\"closesAt\":\"09:25\"",
  )
  |> should.be_true
  open_text
  |> string.contains(
    "\"label\":\"continuous_auction_morning\",\"opensAt\":\"09:30\",\"closesAt\":\"11:30\"",
  )
  |> should.be_true
  open_text
  |> string.contains(
    "\"label\":\"continuous_auction_afternoon\",\"opensAt\":\"13:00\",\"closesAt\":\"14:57\"",
  )
  |> should.be_true
  open_text
  |> string.contains(
    "\"label\":\"closing_call_auction\",\"opensAt\":\"14:57\",\"closesAt\":\"15:00\"",
  )
  |> should.be_true

  let assert Ok(closed) =
    domain.inspect_session(domain.InspectInput("cn", "XSHG", "2026-02-20"))
  let closed_text = json.to_string(closed.details)
  closed_text
  |> string.contains("\"closureKind\":\"published_full_closure\"")
  |> should.be_true
  closed_text
  |> string.contains("\"reason\":\"spring_festival\"")
  |> should.be_true
}

pub fn hk_half_day_and_us_early_close_remain_shortened_with_exact_phases_test() {
  let assert Ok(hk) =
    domain.inspect_session(domain.InspectInput("hk", "XHKG", "2026-12-24"))
  let hk_text = json.to_string(hk.details)
  hk_text
  |> string.contains("\"sessionType\":\"regular_shortened\"")
  |> should.be_true
  hk_text
  |> string.contains(
    "\"label\":\"continuous_morning\",\"opensAt\":\"09:30\",\"closesAt\":\"12:00\"",
  )
  |> should.be_true
  hk_text |> string.contains("continuous_afternoon") |> should.be_false

  let assert Ok(us) =
    domain.inspect_session(domain.InspectInput("us", "XNYS", "2026-11-27"))
  let us_text = json.to_string(us.details)
  us_text
  |> string.contains("\"sessionType\":\"regular_shortened\"")
  |> should.be_true
  us_text
  |> string.contains(
    "\"label\":\"regular_market_early_close\",\"opensAt\":\"09:30\",\"closesAt\":\"13:00\"",
  )
  |> should.be_true
}

pub fn holiday_range_excludes_weekends_and_pages_in_stable_date_order_test() {
  let first_input =
    domain.HolidaysInput("cn", "XSHG", "2026-01-01", "2026-01-04", 0, 1)
  let second_input = domain.HolidaysInput(..first_input, offset: 1)
  let assert Ok(first) = domain.list_holidays(first_input)
  let assert Ok(second) = domain.list_holidays(second_input)
  let first_text = json.to_string(first.details)
  let second_text = json.to_string(second.details)

  first_text
  |> string.contains(
    "\"rangeId\":\"cn:XSHG:official-2026-v1:2026-01-01:2026-01-04\"",
  )
  |> should.be_true
  second_text
  |> string.contains(
    "\"rangeId\":\"cn:XSHG:official-2026-v1:2026-01-01:2026-01-04\"",
  )
  |> should.be_true
  first_text |> string.contains("\"matchedCount\":2") |> should.be_true
  first_text |> string.contains("\"nextOffset\":1") |> should.be_true
  first_text |> string.contains("\"date\":\"2026-01-01\"") |> should.be_true
  first_text |> string.contains("2026-01-02") |> should.be_false
  second_text |> string.contains("\"nextOffset\":null") |> should.be_true
  second_text |> string.contains("\"date\":\"2026-01-02\"") |> should.be_true
  second_text |> string.contains("2026-01-03") |> should.be_false
  second_text |> string.contains("weekly_closure") |> should.be_false
}

pub fn next_session_is_strictly_later_and_retains_shortened_session_test() {
  let assert Ok(cn) =
    domain.next_session(domain.NextInput("cn", "XSHE", "2026-02-20"))
  let cn_text = json.to_string(cn.details)
  cn_text |> string.contains("\"date\":\"2026-02-24\"") |> should.be_true
  cn_text |> string.contains("\"availability\":\"available\"") |> should.be_true

  let assert Ok(us) =
    domain.next_session(domain.NextInput("us", "XNAS", "2026-11-26"))
  let us_text = json.to_string(us.details)
  us_text |> string.contains("\"date\":\"2026-11-27\"") |> should.be_true
  us_text
  |> string.contains("\"sessionType\":\"regular_shortened\"")
  |> should.be_true
}

pub fn next_session_reports_bounded_unavailability_at_coverage_end_test() {
  let assert Ok(response) =
    domain.next_session(domain.NextInput("hk", "XHKG", "2026-12-31"))
  let text = json.to_string(response.details)
  text
  |> string.contains("\"availability\":\"unavailable\"")
  |> should.be_true
  text
  |> string.contains("\"unavailableReason\":\"no_later_open_date_in_coverage\"")
  |> should.be_true
  text |> string.contains("\"session\":null") |> should.be_true
}

pub fn mismatched_track_invalid_date_range_page_and_coverage_fail_closed_test() {
  domain.inspect_session(domain.InspectInput("cn", "XHKG", "2026-03-10"))
  |> should.equal(Error(domain.InvalidTrackVenue("cn", "XHKG")))
  domain.inspect_session(domain.InspectInput("us", "XNYS", "2026-3-10"))
  |> should.equal(Error(domain.InvalidDate("date", "2026-3-10")))
  domain.list_holidays(domain.HolidaysInput(
    "hk",
    "XHKG",
    "2026-02-01",
    "2026-01-01",
    0,
    10,
  ))
  |> should.equal(Error(domain.InvalidRange("2026-02-01", "2026-01-01")))
  domain.list_holidays(domain.HolidaysInput(
    "us",
    "XNYS",
    "2026-01-01",
    "2026-01-04",
    2,
    10,
  ))
  |> should.equal(Error(domain.InvalidPage(2, 10, 1)))
  domain.next_session(domain.NextInput("us", "XNYS", "2027-01-01"))
  |> should.equal(
    Error(domain.OutsideCoverage(
      "after",
      "2026-01-01",
      "2026-12-31",
      "2027-01-01",
    )),
  )
}

pub fn results_keep_calendar_authority_and_decision_boundary_explicit_test() {
  let assert Ok(response) =
    domain.inspect_session(domain.InspectInput("us", "XNYS", "2026-03-10"))
  let text = json.to_string(response.details)
  text
  |> string.contains(
    "\"coverage\":{\"start\":\"2026-01-01\",\"end\":\"2026-12-31\"}",
  )
  |> should.be_true
  text
  |> string.contains("\"redistribution\":\"unknown_redistribution\"")
  |> should.be_true
  text |> string.contains("\"decisionOwner\":\"llm\"") |> should.be_true
  text |> string.contains("\"pluginDecisionFields\":[]") |> should.be_true
  text |> string.contains("\"recommended\"") |> should.be_false
  text |> string.contains("\"nextAction\"") |> should.be_false
  text |> string.contains("\"schedule\"") |> should.be_false
}
