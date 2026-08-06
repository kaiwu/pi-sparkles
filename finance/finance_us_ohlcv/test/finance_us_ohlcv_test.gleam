import finance_core/identifier
import finance_core/time
import finance_listing/effective
import finance_listing/listing
import finance_ohlcv
import finance_track
import finance_us_ohlcv
import finance_us_ohlcv/assessment
import gleam/list
import gleam/option.{None}
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn package_is_experimental_test() {
  finance_us_ohlcv.status() |> should.equal(finance_us_ohlcv.Experimental)
}

pub fn closure_suspension_and_provider_omission_keep_separate_evidence_test() {
  let listing_receipt = nyse_listing(civil(2026, 1, 1))
  let provider_receipt = complete_provider()
  let assert Ok(suspended) =
    assessment.status_receipt(
      civil(2026, 6, 22),
      assessment.Suspended,
      "authority:nyse-halt:IBM:2026-06-22",
    )
  let assert Ok(trading) =
    assessment.status_receipt(
      civil(2026, 6, 23),
      assessment.Trading,
      "authority:nyse-status:IBM:2026-06-23",
    )
  let assert Ok(value) =
    assessment.assess(
      assessment.Nyse,
      listing_receipt,
      civil(2026, 6, 18),
      civil(2026, 6, 24),
      [civil(2026, 6, 18), civil(2026, 6, 24)],
      [suspended, trading],
      provider_receipt,
    )

  assessment.assessed_date_count(value) |> should.equal(7)
  assessment.returned_bar_dates(value) |> list.length |> should.equal(2)
  let gaps = assessment.gaps(value)
  gaps |> list.length |> should.equal(5)
  let assert [juneteenth, saturday, sunday, suspension, omission] = gaps
  assessment.gap_state(juneteenth) |> should.equal(finance_ohlcv.MarketClosure)
  assessment.gap_state(saturday) |> should.equal(finance_ohlcv.MarketClosure)
  assessment.gap_state(sunday) |> should.equal(finance_ohlcv.MarketClosure)
  assessment.gap_state(suspension) |> should.equal(finance_ohlcv.Suspension)
  assessment.gap_state(omission) |> should.equal(finance_ohlcv.ProviderOmission)
  assessment.gap_evidence(suspension) |> list.length |> should.equal(3)
  assessment.gap_evidence(omission) |> list.length |> should.equal(4)
}

pub fn open_date_before_listing_is_unavailable_history_test() {
  let listing_receipt = nyse_listing(civil(2026, 7, 6))
  let assert Ok(value) =
    assessment.assess(
      assessment.Nyse,
      listing_receipt,
      civil(2026, 7, 2),
      civil(2026, 7, 6),
      [civil(2026, 7, 6)],
      [],
      complete_provider(),
    )
  let assert [unavailable, friday, saturday, sunday] = assessment.gaps(value)
  assessment.gap_date(unavailable) |> should.equal(civil(2026, 7, 2))
  assessment.gap_state(unavailable)
  |> should.equal(finance_ohlcv.UnavailableHistory)
  assessment.gap_state(friday) |> should.equal(finance_ohlcv.MarketClosure)
  assessment.gap_state(saturday) |> should.equal(finance_ohlcv.MarketClosure)
  assessment.gap_state(sunday) |> should.equal(finance_ohlcv.MarketClosure)
}

pub fn incomplete_or_unexplained_provider_gaps_fail_closed_test() {
  let listing_receipt = nyse_listing(civil(2026, 1, 1))
  let assert Ok(incomplete) =
    assessment.provider_receipt(
      "alpaca",
      "https://data.alpaca.markets/v2/stocks/bars?fixture=incomplete",
      ["request-one"],
      assessment.Incomplete("truncated_by_page_budget"),
    )
  assessment.assess(
    assessment.Nyse,
    listing_receipt,
    civil(2026, 6, 22),
    civil(2026, 6, 22),
    [],
    [],
    incomplete,
  )
  |> should.equal(
    Error(assessment.IncompleteProviderCoverage("truncated_by_page_budget")),
  )

  assessment.assess(
    assessment.Nyse,
    listing_receipt,
    civil(2026, 6, 22),
    civil(2026, 6, 22),
    [],
    [],
    complete_provider(),
  )
  |> should.equal(Error(assessment.MissingStatusReceipt(civil(2026, 6, 22))))
}

pub fn bars_and_status_receipts_cannot_conflict_with_calendar_or_each_other_test() {
  let listing_receipt = nyse_listing(civil(2026, 1, 1))
  assessment.assess(
    assessment.Nyse,
    listing_receipt,
    civil(2026, 6, 19),
    civil(2026, 6, 19),
    [civil(2026, 6, 19)],
    [],
    complete_provider(),
  )
  |> should.equal(Error(assessment.BarOnMarketClosure(civil(2026, 6, 19))))

  let assert Ok(status) =
    assessment.status_receipt(
      civil(2026, 6, 22),
      assessment.Trading,
      "authority:nyse-status:IBM:2026-06-22",
    )
  assessment.assess(
    assessment.Nyse,
    listing_receipt,
    civil(2026, 6, 22),
    civil(2026, 6, 22),
    [civil(2026, 6, 22)],
    [status],
    complete_provider(),
  )
  |> should.equal(Error(assessment.StatusForReturnedBar(civil(2026, 6, 22))))
}

pub fn exact_track_mic_and_venue_are_not_relabelled_test() {
  let key = listing_key(finance_track.Us, "XNAS")
  let assert Ok(interval) = effective.new(civil(2026, 1, 1), None)
  assessment.listing_receipt(
    assessment.Nyse,
    key,
    interval,
    "authority:listing:IBM:XNAS",
  )
  |> should.equal(Error(assessment.VenueMicMismatch("XNYS", "XNAS")))

  let nasdaq_listing = {
    let assert Ok(value) =
      assessment.listing_receipt(
        assessment.Nasdaq,
        key,
        interval,
        "authority:listing:IBM:XNAS",
      )
    value
  }
  assessment.assess(
    assessment.Nyse,
    nasdaq_listing,
    civil(2026, 6, 22),
    civil(2026, 6, 22),
    [civil(2026, 6, 22)],
    [],
    complete_provider(),
  )
  |> should.equal(Error(assessment.ListingVenueMismatch))
}

fn nyse_listing(starts: time.Date) -> assessment.ListingReceipt {
  let key = listing_key(finance_track.Us, "XNYS")
  let assert Ok(interval) = effective.new(starts, None)
  let assert Ok(value) =
    assessment.listing_receipt(
      assessment.Nyse,
      key,
      interval,
      "authority:listing:IBM:XNYS:2026",
    )
  value
}

fn complete_provider() -> assessment.ProviderReceipt {
  let assert Ok(value) =
    assessment.provider_receipt(
      "alpaca",
      "https://data.alpaca.markets/v2/stocks/bars?fixture=complete",
      ["request-one", "request-two"],
      assessment.Complete,
    )
  value
}

fn listing_key(track: finance_track.Track, mic_value: String) -> listing.Key {
  let assert Ok(instrument_id) = identifier.instrument_id("figi:BBG000BLNNH6")
  let assert Ok(symbol) = identifier.symbol("IBM")
  let assert Ok(mic) = identifier.mic(mic_value)
  listing.new(track, instrument_id, symbol, mic)
}

fn civil(year: Int, month: Int, day: Int) -> time.Date {
  let assert Ok(value) = time.date(year, month, day)
  value
}
