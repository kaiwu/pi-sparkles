import finance_calendar/calendar
import finance_core/time
import gleeunit
import gleeunit/should
import pi_sparkles_us_market_calendar/query

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn exact_venue_and_coverage_are_required_test() {
  query.venue_from_name("NYSE") |> should.equal(Error(query.InvalidVenue))

  let assert Ok(closed_date) = time.date(2026, 6, 19)
  let assert Ok(closed) = query.run(venue: query.Nasdaq, on: closed_date)
  closed.day
  |> should.equal(calendar.Closed("juneteenth_national_independence_day"))

  let assert Ok(outside) = time.date(2027, 1, 4)
  query.run(venue: query.Nyse, on: outside) |> should.be_error
}

pub fn both_venues_preserve_the_early_close_test() {
  let assert Ok(date) = time.date(2026, 12, 24)
  let assert Ok(nyse) = query.run(venue: query.Nyse, on: date)
  let assert Ok(nasdaq) = query.run(venue: query.Nasdaq, on: date)
  let assert calendar.Open(nyse_sessions) = nyse.day
  let assert calendar.Open(nasdaq_sessions) = nasdaq.day
  nyse_sessions |> should.equal(nasdaq_sessions)
}
