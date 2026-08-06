import finance_core/time
import finance_market_alpaca/query as alpaca_query
import finance_ohlcv
import finance_provenance/hash
import finance_provenance/identity
import finance_us_ohlcv/assessment
import finance_us_ohlcv/gap_receipt
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit
import gleeunit/should
import pi_sparkles_us_ohlcv_gaps/query

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn exact_copied_receipts_produce_a_complete_classification_test() {
  let assert Ok(value) =
    execute(input(gap_receipt.Complete, source_reference()))
  assessment.venue(value) |> should.equal(assessment.Nyse)
  assessment.assessed_date_count(value) |> should.equal(7)
  let gaps = assessment.gaps(value)
  gaps |> list.length |> should.equal(5)
  let assert [_, _, _, suspended, omitted] = gaps
  assessment.gap_state(suspended) |> should.equal(finance_ohlcv.Suspension)
  assessment.gap_state(omitted) |> should.equal(finance_ohlcv.ProviderOmission)
}

pub fn source_identity_and_complete_pagination_are_mandatory_test() {
  execute(input(gap_receipt.Complete, "https://example.test/wrong"))
  |> should.equal(Error(query.SourceReferenceMismatch))

  execute(input(gap_receipt.TruncatedByPageBudget, source_reference()))
  |> should.equal(
    Error(
      query.InvalidAssessment(assessment.IncompleteProviderCoverage(
        "truncated_by_page_budget",
      )),
    ),
  )
}

pub fn a_changed_projection_fails_its_original_digest_test() {
  let signed = input(gap_receipt.Complete, source_reference())
  let provider = signed.provider_receipt
  let tampered =
    query.Input(
      ..signed,
      provider_receipt: query.ProviderInput(..provider, bar_dates: [
        civil(2026, 6, 18),
      ]),
    )
  let assert Ok(canonical) = query.canonical_receipt(tampered)
  let assert Ok(actual) = hash.text(canonical)
  query.run(tampered, actual)
  |> should.equal(Error(query.ReceiptDigestMismatch))
}

fn input(pagination: gap_receipt.Pagination, reference: String) -> query.Input {
  let unsigned =
    query.Input(
      venue: assessment.Nyse,
      instrument_id: "figi:BBG000BLNNH6",
      listing_start: civil(2026, 1, 1),
      listing_end: None,
      listing_evidence: "authority:listing:IBM:XNYS:2026",
      provider_receipt: query.ProviderInput(
        schema: gap_receipt.schema_name,
        schema_version: gap_receipt.schema_version,
        digest_algorithm: gap_receipt.digest_algorithm,
        digest: string.repeat("0", 64),
        provider: "alpaca",
        symbol: "IBM",
        start_date: civil(2026, 6, 18),
        end_date: civil(2026, 6, 24),
        identity_as_of: civil(2026, 6, 25),
        feed: alpaca_query.Sip,
        source_reference: reference,
        retrieved_at: instant(1_775_000_000_000),
        pagination: pagination,
        pages: [
          query.PageInput(1, Some("request-one"), 100, string.repeat("a", 64)),
          query.PageInput(2, Some("request-two"), 200, string.repeat("b", 64)),
        ],
        bar_dates: [civil(2026, 6, 18), civil(2026, 6, 24)],
      ),
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
  let assert Ok(canonical) = query.canonical_receipt(unsigned)
  let assert Ok(digest) = hash.text(canonical)
  let provider = unsigned.provider_receipt
  query.Input(
    ..unsigned,
    provider_receipt: query.ProviderInput(
      ..provider,
      digest: identity.sha256_value(digest),
    ),
  )
}

fn execute(
  input: query.Input,
) -> Result(assessment.Assessment, query.QueryError) {
  let assert Ok(canonical) = query.canonical_receipt(input)
  let assert Ok(actual) = hash.text(canonical)
  query.run(input, actual)
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

fn instant(milliseconds: Int) -> time.Instant {
  let assert Ok(value) = time.instant(milliseconds)
  value
}
