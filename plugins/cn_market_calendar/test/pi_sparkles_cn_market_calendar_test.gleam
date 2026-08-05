import finance_calendar/calendar
import finance_core/time
import gleeunit
import gleeunit/should
import pi_sparkles_cn_market_calendar/query

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn exact_venue_and_coverage_are_required_test() {
  query.venue_from_name("SSE") |> should.equal(Error(query.InvalidVenue))
  let assert Ok(date) = time.date(2026, 10, 2)
  let assert Ok(value) = query.run(venue: query.Sse, on: date)
  value.day |> should.equal(calendar.Closed("national_day"))

  let assert Ok(outside) = time.date(2027, 1, 4)
  query.run(venue: query.Sse, on: outside) |> should.be_error
}
