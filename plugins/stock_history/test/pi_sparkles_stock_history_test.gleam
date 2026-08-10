import gleam/json
import gleam/option.{None, Some}
import gleam/string
import gleeunit
import gleeunit/should
import pi_sparkles_stock_history/decode
import pi_sparkles_stock_history/domain

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn exact_cn_hk_us_daily_series_retain_track_scope_and_lexemes_test() {
  let assert Ok(cn) = domain.run(input("cn", "XSHG", "600519", "CNY"))
  let assert Ok(hk) = domain.run(input("hk", "XHKG", "00700", "HKD"))
  let assert Ok(us) = domain.run(input("us", "XNAS", "AAPL", "USD"))

  contains(details(cn), "\"track\":\"cn\"")
  contains(details(cn), "\"timezone\":\"Asia/Shanghai\"")
  contains(details(hk), "\"track\":\"hk\"")
  contains(details(hk), "\"mic\":\"XHKG\"")
  contains(details(us), "\"track\":\"us\"")
  contains(details(us), "\"open\":\"189.1000\"")
  contains(details(us), "\"open\":\"189.1\"")
  contains(details(us), "\"volume\":\"100.00\"")
  contains(details(us), "\"volume\":\"100\"")
  contains(details(us), "\"nextOffset\":1")
}

pub fn declared_metadata_gaps_and_provider_adjustment_survive_unverified_test() {
  let base = input("us", "XNYS", "IBM", "USD")
  let batch = base.batch
  let source = base.source
  let adjusted =
    decode.AdjustmentInput(
      "provider_adjusted",
      Some("fixture-adapter"),
      Some("vendor split and dividend basis v2"),
    )
  let assessed =
    decode.CalendarInput("assessed", None, [
      decode.GapInput(
        "2026-08-05",
        "market_closure",
        Some("https://example.test/calendar?token=secret"),
      ),
    ])
  let assert Ok(response) =
    domain.run(
      decode.Input(
        ..base,
        batch: decode.BatchInput(
          ..batch,
          adjustment: adjusted,
          calendar: assessed,
        ),
        source: decode.SourceInput(
          ..source,
          entitlement: decode.EntitlementInput("delayed", Some(900_000)),
        ),
        page: decode.PageInput(0, 200),
      ),
    )
  let text = details(response)
  contains(text, "\"kind\":\"provider_adjusted\"")
  contains(text, "vendor split and dividend basis v2")
  contains(text, "\"state\":\"market_closure\"")
  contains(text, "\"state\":\"delayed\"")
  contains(text, "\"evidenceId\":\"" <> receipt() <> "\"")
  contains(text, "\"receiptBinding\":\"caller_supplied_unverified\"")
  excludes(text, "secret")
}

pub fn exact_duplicates_collapse_before_bounded_output_test() {
  let base = input("hk", "XHKG", "00700", "HKD")
  let first = first_bar()
  let assert Ok(response) =
    domain.run(
      decode.Input(..base, bars: [first, first], page: decode.PageInput(0, 200)),
    )
  let text = details(response)
  contains(text, "\"inputRowCount\":2")
  contains(text, "\"observationCount\":1")
  contains(text, "\"duplicatesCollapsed\":1")
}

pub fn track_date_time_basis_and_geometry_errors_fail_closed_test() {
  case domain.run(input("cn", "XNAS", "AAPL", "USD")) {
    Error(domain.InvalidField("listing.mic", _)) -> Nil
    _ -> should.fail()
  }

  let base = input("us", "XNAS", "AAPL", "USD")
  let anchored = first_bar()
  case
    domain.run(
      decode.Input(..base, bars: [
        decode.BarInput(..anchored, source_timestamp: "not-the-session-date"),
      ]),
    )
  {
    Error(domain.InvalidField("bars[0].sourceTimestamp", _)) -> Nil
    _ -> should.fail()
  }

  case
    domain.run(
      decode.Input(..base, bars: [decode.BarInput(..anchored, raw_high: "180")]),
    )
  {
    Error(domain.InvalidField("bars[0]", _)) -> Nil
    _ -> should.fail()
  }

  case
    domain.run(
      decode.Input(..base, range: decode.RangeInput("2026-08-04", "2026-08-03")),
    )
  {
    Error(domain.InvalidField("range", _)) -> Nil
    _ -> should.fail()
  }
}

pub fn returned_bar_and_calendar_gap_cannot_claim_the_same_date_test() {
  let base = input("cn", "XSHE", "000001", "CNY")
  let batch = base.batch
  let calendar =
    decode.CalendarInput("assessed", None, [
      decode.GapInput("2026-08-03", "suspension", None),
    ])
  case
    domain.run(
      decode.Input(
        ..base,
        batch: decode.BatchInput(..batch, calendar: calendar),
      ),
    )
  {
    Error(domain.InvalidField("batch.calendar.gaps", _)) -> Nil
    _ -> should.fail()
  }
}

pub fn one_daily_session_date_cannot_hide_multiple_distinct_rows_test() {
  let base = input("us", "XNYS", "IBM", "USD")
  let first = source_instant_bar(1000, "189.10")
  let second = source_instant_bar(2000, "189.20")
  case domain.run(decode.Input(..base, bars: [first, second])) {
    Error(domain.InvalidField("bars", _)) -> Nil
    _ -> should.fail()
  }
}

pub fn source_secrets_are_redacted_before_projection_test() {
  let base = input("hk", "XHKG", "00700", "HKD")
  let source = base.source
  let assert Ok(response) =
    domain.run(
      decode.Input(
        ..base,
        source: decode.SourceInput(
          ..source,
          reference: "https://user:password@example.test/bars?api_key=do-not-leak#fragment",
        ),
      ),
    )
  let text = details(response)
  excludes(text, "do-not-leak")
  excludes(text, "user:password")
  excludes(text, "#fragment")
  contains(text, "\"referenceRedacted\":true")
}

fn input(
  track: String,
  mic: String,
  symbol: String,
  currency: String,
) -> decode.Input {
  decode.Input(
    track,
    decode.ListingInput("listing:" <> symbol, mic, symbol),
    decode.RangeInput("2026-08-03", "2026-08-05"),
    decode.BatchInput(
      2_000_000_000_000,
      currency,
      "shares",
      decode.AdjustmentInput("raw", None, None),
      decode.SessionInput("regular", None),
      decode.PaginationInput("complete", None),
      decode.CalendarInput("not_assessed", Some("calendar_unavailable"), []),
    ),
    [first_bar(), second_bar()],
    decode.SourceInput(
      "fixture-adapter",
      "https://example.test/bars?symbol=" <> symbol,
      "licensed_vendor",
      None,
      "fixture-daily",
      decode.EntitlementInput("end_of_day", None),
      decode.LicenceInput(
        "fixture-contract",
        "no_redistribution",
        Some("local analysis only"),
      ),
      receipt(),
    ),
    decode.PageInput(0, 1),
  )
}

fn first_bar() -> decode.BarInput {
  decode.BarInput(
    "2026-08-03",
    "2026-08-03",
    "session_date_anchor",
    None,
    "189.1000",
    "190.0000",
    "188.5000",
    "189.5000",
    "100.00",
    Some("7"),
    Some("189.4000"),
  )
}

fn second_bar() -> decode.BarInput {
  decode.BarInput(
    "2026-08-04",
    "2026-08-04",
    "session_date_anchor",
    None,
    "189.5000",
    "191.0000",
    "189.0000",
    "190.5000",
    "200",
    None,
    None,
  )
}

fn source_instant_bar(at: Int, close: String) -> decode.BarInput {
  decode.BarInput(
    "2026-08-03",
    "2026-08-03T16:00:00Z",
    "source_instant",
    Some(at),
    "189.00",
    "190.00",
    "188.00",
    close,
    "100",
    None,
    None,
  )
}

fn receipt() -> String {
  string.repeat("a", 64)
}

fn details(value: domain.Response) -> String {
  value |> domain.details |> json.to_string
}

fn contains(value: String, expected: String) -> Nil {
  value |> string.contains(expected) |> should.be_true
}

fn excludes(value: String, expected: String) -> Nil {
  value |> string.contains(expected) |> should.be_false
}
