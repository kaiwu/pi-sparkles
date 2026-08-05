import finance_calendar/calendar
import finance_core/time
import gleam/list
import gleeunit
import gleeunit/should
import pi_sparkles_hk_market_calendar/query

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn half_days_and_coverage_are_preserved_test() {
  let assert Ok(date) = time.date(2026, 12, 24)
  let assert Ok(value) = query.run(on: date)
  let assert calendar.Open(sessions) = value.day
  list.length(sessions) |> should.equal(2)

  let assert Ok(outside) = time.date(2027, 1, 4)
  query.run(on: outside) |> should.be_error
}
