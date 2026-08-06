import finance_core/adjustment
import finance_core/currency
import finance_core/decimal
import finance_core/market
import finance_core/observation
import finance_core/source
import finance_core/time
import finance_ohlcv
import finance_series/series
import gleam/list
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn exact_values_and_observation_envelopes_are_preserved_test() {
  let batch =
    batch([bar(1_722_470_400_000, "100.00", "101.50", "99.25", "101.00")])
  finance_ohlcv.observations(batch) |> list.length |> should.equal(1)
  let assert [observed] = finance_ohlcv.observations(batch)
  finance_ohlcv.raw(finance_ohlcv.open(observed.value))
  |> should.equal("100.00")
  finance_ohlcv.normalized(finance_ohlcv.open(observed.value))
  |> decimal.to_string
  |> should.equal("100")
  observed.adjustment |> should.equal(Some(adjustment.Raw))
  observed.entitlement |> should.equal(observation.EndOfDay)
}

pub fn date_only_bars_retain_a_distinct_ordering_anchor_test() {
  let assert Ok(value) =
    finance_ohlcv.date_bar(
      "2024-08-01",
      civil(2024, 8, 1),
      exact("100.00"),
      exact("101.00"),
      exact("99.00"),
      exact("100.50"),
      exact("10"),
      None,
      None,
    )
  finance_ohlcv.source_timestamp(value) |> should.equal("2024-08-01")
  finance_ohlcv.time_basis(value)
  |> should.equal(finance_ohlcv.SessionDateAnchor)
  finance_ohlcv.at(value)
  |> time.unix_milliseconds
  |> should.equal(1_722_470_400_000)
}

pub fn invalid_bar_geometry_and_negative_volume_fail_closed_test() {
  finance_ohlcv.bar(
    "2024-08-01T04:00:00Z",
    instant(1_722_470_400_000),
    civil(2024, 8, 1),
    exact("100"),
    exact("99"),
    exact("98"),
    exact("100"),
    exact("10"),
    None,
    None,
  )
  |> should.equal(Error(finance_ohlcv.HighBelowPrice))

  finance_ohlcv.bar(
    "2024-08-01T04:00:00Z",
    instant(1_722_470_400_000),
    civil(2024, 8, 1),
    exact("100"),
    exact("101"),
    exact("99"),
    exact("100"),
    exact("-1"),
    None,
    None,
  )
  |> should.equal(Error(finance_ohlcv.NegativeVolume))

  finance_ohlcv.bar(
    "2024-08-01T04:00:00Z",
    instant(1_722_470_400_000),
    civil(2024, 8, 1),
    exact("100"),
    exact("101"),
    exact("99"),
    exact("100"),
    exact("1"),
    None,
    Some(exact("102")),
  )
  |> should.equal(Error(finance_ohlcv.VwapAboveHigh))
}

pub fn exact_duplicates_collapse_but_conflicts_and_reordering_fail_test() {
  let first = bar(1_722_470_400_000, "100", "101", "99", "100")
  let second = bar(1_722_556_800_000, "101", "103", "100", "102")
  let duplicate_batch = batch([first, first, second])
  finance_ohlcv.duplicates_collapsed(duplicate_batch) |> should.equal(1)
  finance_ohlcv.observations(duplicate_batch) |> list.length |> should.equal(2)

  make_batch([second, first]) |> should.be_error
  let conflict = bar(1_722_470_400_000, "100", "102", "99", "101")
  make_batch([first, conflict])
  |> should.equal(
    Error(finance_ohlcv.ConflictingDuplicate(instant(1_722_470_400_000))),
  )
}

pub fn close_returns_use_exact_series_math_test() {
  let value =
    batch([
      bar(1_722_470_400_000, "100", "101", "99", "100"),
      bar(1_722_556_800_000, "105", "111", "104", "110"),
    ])
  let assert Ok(returns) =
    finance_ohlcv.simple_returns(value, scale: 6, rounding: decimal.HalfEven)
  returns
  |> series.present_values
  |> list.map(fn(point) { decimal.to_string(point.1) })
  |> should.equal(["0.1"])
}

fn batch(bars) -> finance_ohlcv.Batch {
  let assert Ok(value) = make_batch(bars)
  value
}

fn make_batch(bars) {
  let assert Ok(zone) = time.timezone("America/New_York")
  let assert Ok(usd) = currency.from_code("USD")
  let assert Ok(source_ref) =
    source.new(
      "alpaca",
      "https://data.alpaca.markets/v2/stocks/bars",
      source.LicensedVendor,
    )
  finance_ohlcv.batch(
    bars,
    retrieved_at: instant(1_800_000_000_000),
    timezone: zone,
    currency: usd,
    volume_unit: finance_ohlcv.Shares,
    adjustment: adjustment.Raw,
    session: market.Regular,
    source: source_ref,
    expected_provider: "alpaca",
    pagination: finance_ohlcv.AllPages,
    calendar: finance_ohlcv.CalendarNotAssessed("us_calendar_unavailable"),
  )
}

fn bar(at, open, high, low, close) -> finance_ohlcv.Bar {
  let assert Ok(value) =
    finance_ohlcv.bar(
      "2024-08-01T04:00:00Z",
      instant(at),
      civil(2024, 8, 1),
      exact(open),
      exact(high),
      exact(low),
      exact(close),
      exact("1000"),
      None,
      None,
    )
  value
}

fn exact(value: String) -> finance_ohlcv.ExactValue {
  let assert Ok(parsed) = finance_ohlcv.exact(value)
  parsed
}

fn instant(milliseconds: Int) -> time.Instant {
  let assert Ok(value) = time.instant(milliseconds)
  value
}

fn civil(year: Int, month: Int, day: Int) -> time.Date {
  let assert Ok(value) = time.date(year, month, day)
  value
}
