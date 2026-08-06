import finance_core/time
import finance_market_alpaca/query as alpaca_query
import finance_ohlcv
import finance_us_ohlcv/assessment
import gleam/list
import gleam/option.{None}
import gleeunit
import gleeunit/should
import pi_sparkles_us_ohlcv_gaps/query

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn exact_copied_receipts_produce_a_complete_classification_test() {
  let assert Ok(value) =
    query.run(input(assessment.Complete, source_reference()))
  assessment.venue(value) |> should.equal(assessment.Nyse)
  assessment.assessed_date_count(value) |> should.equal(7)
  let gaps = assessment.gaps(value)
  gaps |> list.length |> should.equal(5)
  let assert [_, _, _, suspended, omitted] = gaps
  assessment.gap_state(suspended) |> should.equal(finance_ohlcv.Suspension)
  assessment.gap_state(omitted) |> should.equal(finance_ohlcv.ProviderOmission)
}

pub fn source_identity_and_complete_pagination_are_mandatory_test() {
  query.run(input(assessment.Complete, "https://example.test/wrong"))
  |> should.equal(Error(query.SourceReferenceMismatch))

  query.run(input(
    assessment.Incomplete("truncated_by_page_budget"),
    source_reference(),
  ))
  |> should.equal(
    Error(
      query.InvalidAssessment(assessment.IncompleteProviderCoverage(
        "truncated_by_page_budget",
      )),
    ),
  )
}

fn input(
  pagination: assessment.ProviderCompleteness,
  reference: String,
) -> query.Input {
  query.Input(
    venue: assessment.Nyse,
    instrument_id: "figi:BBG000BLNNH6",
    symbol: "IBM",
    listing_start: civil(2026, 1, 1),
    listing_end: None,
    listing_evidence: "authority:listing:IBM:XNYS:2026",
    start_date: civil(2026, 6, 18),
    end_date: civil(2026, 6, 24),
    identity_as_of: civil(2026, 6, 25),
    feed: alpaca_query.Sip,
    pagination: pagination,
    source_reference: reference,
    request_ids: ["request-one", "request-two"],
    bar_dates: [civil(2026, 6, 18), civil(2026, 6, 24)],
    statuses: [
      query.StatusInput(
        civil(2026, 6, 22),
        assessment.Suspended,
        "authority:nyse-halt:IBM:2026-06-22",
      ),
      query.StatusInput(
        civil(2026, 6, 23),
        assessment.Trading,
        "authority:nyse-status:IBM:2026-06-23",
      ),
    ],
  )
}

fn source_reference() -> String {
  let assert Ok(plan) =
    alpaca_query.daily_bars(
      "IBM",
      civil(2026, 6, 18),
      civil(2026, 6, 24),
      civil(2026, 6, 25),
      alpaca_query.Sip,
      1,
      1,
      1,
    )
  alpaca_query.daily_bars_source_reference(plan)
}

fn civil(year: Int, month: Int, day: Int) -> time.Date {
  let assert Ok(value) = time.date(year, month, day)
  value
}
