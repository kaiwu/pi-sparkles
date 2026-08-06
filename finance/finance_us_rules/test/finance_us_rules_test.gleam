import finance_core/decimal
import finance_core/identifier
import finance_core/source
import finance_core/time
import finance_listing/effective
import finance_listing/listing
import finance_track
import finance_us_rules
import finance_us_rules/official
import gleam/option.{Some}
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn package_is_experimental_test() {
  finance_us_rules.status() |> should.equal(finance_us_rules.Experimental)
}

pub fn exact_listing_venue_and_reviewed_interval_are_retained_test() {
  let assert Ok(value) = profile(official.Nyse, "1.00", civil(2026, 8, 6))
  let key = official.listing(value)

  listing.track(key) |> should.equal(finance_track.Us)
  key
  |> listing.instrument_id
  |> identifier.instrument_id_value
  |> should.equal("figi:BBG000BLNNH6")
  key |> listing.symbol |> identifier.symbol_value |> should.equal("IBM")
  key |> listing.mic |> identifier.mic_value |> should.equal("XNYS")
  official.venue(value) |> should.equal(official.Nyse)

  let interval = official.effective(value)
  effective.start(interval) |> should.equal(civil(2026, 6, 11))
  effective.end(interval) |> should.equal(Some(civil(2027, 10, 31)))
}

pub fn dollar_boundary_selects_exact_current_increment_test() {
  let assert Ok(below) = profile(official.Nasdaq, "0.9999", civil(2026, 8, 6))
  let assert Ok(at_one) = profile(official.Nasdaq, "1.0000", civil(2026, 8, 6))

  below
  |> official.selected_price_band
  |> should.equal(official.BelowOneDollar)
  below
  |> official.minimum_price_increment
  |> decimal.to_string
  |> should.equal("0.0001")
  at_one
  |> official.selected_price_band
  |> should.equal(official.AtOrAboveOneDollar)
  at_one
  |> official.minimum_price_increment
  |> decimal.to_string
  |> should.equal("0.01")
}

pub fn exchange_and_sec_sources_remain_separate_test() {
  let assert Ok(value) = profile(official.Nasdaq, "42.50", civil(2026, 8, 6))
  source.provider(official.exchange_source(value))
  |> should.equal("The Nasdaq Stock Market")
  source.reference(official.exchange_source(value))
  |> should.equal(
    "https://listingcenter.nasdaq.com/rulebook/nasdaq/rules/nasdaq-equity-2",
  )
  source.provider(official.sec_relief_source(value))
  |> should.equal("U.S. Securities and Exchange Commission")
  source.reference(official.sec_relief_source(value))
  |> should.equal("https://www.sec.gov/files/rules/exorders/2026/34-105656.pdf")
  official.clauses(value)
  |> should.equal([
    "nasdaq_equity_2_section_5_a_2_i",
    "sec_release_34_105656",
  ])
}

pub fn unsupported_identity_scope_price_and_date_fail_closed_test() {
  official.regular_displayed_nms_quote(
    venue: official.Nyse,
    instrument_id: "bare-id",
    symbol: "IBM",
    currency: "USD",
    security_class: "nms_stock",
    market_status: "normal",
    regime: "regular_displayed_quote",
    on: civil(2026, 8, 6),
    nominal_price: exact("10"),
  )
  |> should.equal(Error(official.InvalidInstrumentId))

  official.regular_displayed_nms_quote(
    venue: official.Nyse,
    instrument_id: "figi:BBG000BLNNH6",
    symbol: "ibm",
    currency: "USD",
    security_class: "nms_stock",
    market_status: "normal",
    regime: "regular_displayed_quote",
    on: civil(2026, 8, 6),
    nominal_price: exact("10"),
  )
  |> should.equal(Error(official.InvalidSymbol))

  let assert Error(outside) =
    official.regular_displayed_nms_quote(
      venue: official.Nyse,
      instrument_id: "figi:BBG000BLNNH6",
      symbol: "IBM",
      currency: "USD",
      security_class: "nms_stock",
      market_status: "normal",
      regime: "regular_displayed_quote",
      on: civil(2027, 11, 1),
      nominal_price: exact("10"),
    )
  outside |> should.equal(official.OutsideReviewedInterval)

  let assert Error(non_positive) =
    profile(official.Nyse, "0", civil(2026, 8, 6))
  non_positive |> should.equal(official.NonPositivePrice)
}

fn profile(
  venue: official.Venue,
  price: String,
  date: time.Date,
) -> Result(official.Profile, official.ProfileError) {
  let #(instrument_id, symbol) = case venue {
    official.Nyse -> #("figi:BBG000BLNNH6", "IBM")
    official.Nasdaq -> #("figi:BBG000B9XRY4", "AAPL")
  }
  official.regular_displayed_nms_quote(
    venue: venue,
    instrument_id: instrument_id,
    symbol: symbol,
    currency: "USD",
    security_class: "nms_stock",
    market_status: "normal",
    regime: "regular_displayed_quote",
    on: date,
    nominal_price: exact(price),
  )
}

fn civil(year: Int, month: Int, day: Int) -> time.Date {
  let assert Ok(value) = time.date(year, month, day)
  value
}

fn exact(value: String) -> decimal.Decimal {
  let assert Ok(parsed) = decimal.parse(value)
  parsed
}
