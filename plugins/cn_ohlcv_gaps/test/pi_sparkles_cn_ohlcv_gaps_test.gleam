import finance_cn_identity/identity as cn_identity
import finance_cn_ohlcv/assessment
import finance_cn_ohlcv/gap_receipt
import finance_core/currency
import finance_core/time
import finance_ohlcv
import finance_ohlcv/gap_assessment
import finance_provenance/hash
import finance_provenance/identity
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit
import gleeunit/should
import pi_sparkles_cn_ohlcv_gaps/query

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn exact_cn_receipts_produce_complete_classification_test() {
  let assert Ok(value) = execute(input(gap_receipt.Complete))
  assessment.venue(value) |> should.equal(cn_identity.Sse)
  assessment.assessed_date_count(value) |> should.equal(7)
  let gaps = value |> assessment.classification |> gap_assessment.gaps
  gaps |> list.length |> should.equal(5)
  let assert [_, _, _, suspended, omitted] = gaps
  gap_assessment.gap_state(suspended) |> should.equal(finance_ohlcv.Suspension)
  gap_assessment.gap_state(omitted)
  |> should.equal(finance_ohlcv.ProviderOmission)
}

pub fn provider_identity_and_complete_coverage_are_mandatory_test() {
  let signed = input(gap_receipt.Complete)
  let wrong_listing = query.Input(..signed, code: "000001")
  execute(wrong_listing)
  |> should.equal(Error(query.ProviderIdentityMismatch))

  execute(input(gap_receipt.TruncatedByBarBudget))
  |> should.equal(
    Error(
      query.InvalidAssessment(
        assessment.InvalidAssessment(gap_assessment.IncompleteProviderCoverage(
          "truncated_by_bar_budget",
        )),
      ),
    ),
  )
}

pub fn changed_cn_projection_fails_its_original_digest_test() {
  let signed = input(gap_receipt.Complete)
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

fn input(pagination: gap_receipt.Pagination) -> query.Input {
  let assert Ok(cny) = currency.from_code("CNY")
  let unsigned =
    query.Input(
      venue: cn_identity.Sse,
      board: cn_identity.SseMainBoard,
      share_class: cn_identity.AShare,
      currency: cny,
      code: "600519",
      instrument_id: "cninfo:10002602",
      listing_start: civil(2026, 1, 1),
      listing_end: None,
      listing_evidence: "authority:listing:600519:XSHG:2026",
      provider_receipt: query.ProviderInput(
        schema: gap_receipt.schema_name,
        schema_version: gap_receipt.schema_version,
        digest_algorithm: gap_receipt.digest_algorithm,
        digest: string.repeat("0", 64),
        provider: "eastmoney",
        venue: cn_identity.Sse,
        board: cn_identity.SseMainBoard,
        share_class: cn_identity.AShare,
        currency: cny,
        code: "600519",
        start_date: civil(2026, 6, 18),
        end_date: civil(2026, 6, 24),
        limit: 250,
        source_reference: source_reference(),
        retrieved_at: instant(1_775_000_000_000),
        pagination: pagination,
        pages: [
          query.PageInput(1, Some("request-one"), 500, string.repeat("a", 64)),
        ],
        bar_dates: [civil(2026, 6, 18), civil(2026, 6, 24)],
      ),
      statuses: [
        query.StatusInput(
          civil(2026, 6, 22),
          gap_assessment.Suspended,
          "authority:sse-halt:600519:2026-06-22",
        ),
        query.StatusInput(
          civil(2026, 6, 23),
          gap_assessment.Trading,
          "authority:sse-status:600519:2026-06-23",
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
  "https://push2his.eastmoney.com/api/qt/stock/kline/get?secid=1.600519&klt=101&fqt=0&beg=20260618&end=20260624&lmt=250"
}

fn civil(year: Int, month: Int, day: Int) -> time.Date {
  let assert Ok(value) = time.date(year, month, day)
  value
}

fn instant(milliseconds: Int) -> time.Instant {
  let assert Ok(value) = time.instant(milliseconds)
  value
}
