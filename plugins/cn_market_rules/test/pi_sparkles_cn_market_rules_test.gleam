import finance_cn_rules/official
import finance_core/decimal
import finance_core/time
import gleeunit
import gleeunit/should
import pi_sparkles_cn_market_rules/query

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn exact_venue_board_and_regime_are_required_test() {
  query.venue_from_name("SSE") |> should.equal(Error(query.InvalidVenue))
  let assert Ok(date) = time.date(2026, 8, 5)
  let assert Ok(value) =
    query.run(
      venue: official.Szse,
      board: official.ChiNext,
      regime: "established_normal_equity",
      on: date,
    )
  value
  |> official.daily_price_limit
  |> decimal.to_string
  |> should.equal("0.2")
  query.run(
    venue: official.Sse,
    board: official.ChiNext,
    regime: "established_normal_equity",
    on: date,
  )
  |> should.be_error
  query.run(
    venue: official.Sse,
    board: official.MainBoard,
    regime: "ipo_first_five",
    on: date,
  )
  |> should.equal(Error(query.InvalidRegime))
}
