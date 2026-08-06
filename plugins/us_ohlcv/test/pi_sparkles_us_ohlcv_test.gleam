import finance_core/time
import finance_market_alpaca/bars
import finance_market_alpaca/query
import finance_ohlcv
import gleeunit
import gleeunit/should
import pi_sparkles_us_ohlcv/normalization

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn alpaca_raw_page_normalizes_into_exact_canonical_batch_test() {
  let plan = plan()
  let assert Ok(page) = bars.decode_page(fixture(), for: plan, page_limit: 2)
  let assert Ok(batch) =
    normalization.batch(
      plan,
      bars.bars(page),
      instant(1_800_000_000_000),
      finance_ohlcv.AllPages,
    )
  let assert [first, second] = finance_ohlcv.observations(batch)
  finance_ohlcv.raw(finance_ohlcv.open(first.value))
  |> should.equal("185.6200")
  finance_ohlcv.raw(finance_ohlcv.close(second.value))
  |> should.equal("189.840")
  finance_ohlcv.duplicates_collapsed(batch) |> should.equal(0)
  finance_ohlcv.calendar_assessment(batch)
  |> should.equal(finance_ohlcv.CalendarNotAssessed(
    "reviewed_us_calendar_and_status_source_not_composed",
  ))
}

fn plan() -> query.DailyBarsQuery {
  let assert Ok(value) =
    query.daily_bars(
      "AAPL",
      civil(2024, 8, 1),
      civil(2024, 8, 2),
      civil(2024, 8, 5),
      query.Iex,
      100,
      2,
      200,
    )
  value
}

fn civil(year: Int, month: Int, day: Int) -> time.Date {
  let assert Ok(value) = time.date(year, month, day)
  value
}

fn instant(milliseconds: Int) -> time.Instant {
  let assert Ok(value) = time.instant(milliseconds)
  value
}

fn fixture() -> String {
  "{\"bars\":{\"AAPL\":[{\"c\":187.12,\"h\":188.10,\"l\":184.22,\"n\":612345,\"o\":185.6200,\"t\":\"2024-08-01T04:00:00Z\",\"v\":50292117,\"vw\":186.432100},{\"c\":189.840,\"h\":190.01,\"l\":186.31,\"n\":598765,\"o\":186.90,\"t\":\"2024-08-02T04:00:00Z\",\"v\":49910111,\"vw\":188.7654}]},\"next_page_token\":null}"
}
