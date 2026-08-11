import gleam/json
import gleam/option.{None, Some}
import gleam/string
import gleeunit
import gleeunit/should
import pi_sparkles_stock_order_book/decode
import pi_sparkles_stock_order_book/domain

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn three_tracks_and_exact_canonical_candidates_are_retained_test() {
  let assert Ok(cn) = domain.run(input_for("cn", "XSHG", "CNY", "600000"))
  let assert Ok(hk) = domain.run(input_for("hk", "XHKG", "HKD", "00700"))
  let assert Ok(us) = domain.run(input_for("us", "XNAS", "USD", "AAPL"))

  contains(details(cn), "\"timezone\":\"Asia/Shanghai\"")
  contains(details(hk), "\"timezone\":\"Asia/Hong_Kong\"")
  contains(details(us), "\"timezone\":\"America/New_York\"")
  contains(details(hk), "\"rawPrice\":\"10.5000\"")
  contains(details(hk), "\"normalizedPrice\":\"10.5\"")
  contains(details(hk), "\"rawSize\":\"00100.00\"")
  contains(details(hk), "\"normalizedSize\":\"100\"")
  contains(details(hk), "\"freshness\":\"unknown_not_assessed\"")
  contains(details(hk), "\"displayedOnly\":true")
  contains(details(hk), "\"executablePricePromise\":false")
}

pub fn unavailable_conflicting_gap_and_reset_states_remain_unresolved_test() {
  let conflicting =
    decode.SideInput("conflicting", None, Some("two source rows"), [
      alternative("10.60", "200", "XHKG", "c"),
      alternative("10.61", "180", "XHKG", "d"),
    ])
  let missing = decode.SideInput("unavailable", None, Some("not reported"), [])
  let first =
    decode.ReportInput(
      ..report("gap-report", "alpha", missing, conflicting, "XHKG"),
      gap: decode.GapInput("sequence_gap", Some(13), Some(15), None),
    )
  let second =
    decode.ReportInput(
      ..report(
        "reset-report",
        "alpha",
        observed("10.50", "100", "XHKG"),
        observed("10.60", "200", "XHKG"),
        "XHKG",
      ),
      gap: decode.GapInput("sequence_reset", Some(900), Some(1), None),
    )
  let base = input_for("hk", "XHKG", "HKD", "00700")
  let assert Ok(response) =
    domain.run(decode.Input(..base, reports: [first, second]))
  let text = details(response)

  contains(text, "\"bidStates\":{\"observed\":1,\"unavailable\":1")
  contains(
    text,
    "\"askStates\":{\"observed\":1,\"unavailable\":0,\"conflicting\":1",
  )
  contains(text, "\"reportedSequenceGaps\":1")
  contains(text, "\"reportedSequenceResets\":1")
  contains(text, "\"state\":\"conflicting\"")
  contains(text, "\"resolution\":\"not_performed\"")
  contains(text, "\"gapRepair\":\"not_performed\"")
}

pub fn consolidation_and_provider_defined_aggregation_are_exact_declarations_test() {
  let base = input_for("us", "XNAS", "USD", "AAPL")
  let consolidated =
    decode.AggregationInput(
      "consolidated",
      [venue("mic", "XNAS"), venue("provider_code", "ARCX")],
      "declared_partial",
      None,
      None,
    )
  let provider_defined =
    decode.AggregationInput(
      "provider_defined",
      [venue("provider_code", "P-BEST")],
      "unknown",
      Some("vendor-best-v2"),
      None,
    )
  let reports = [
    decode.ReportInput(
      ..report(
        "consolidated",
        "alpha",
        observed_with_kind("25.01", "50", "mic", "XNAS"),
        observed_with_kind("25.02", "60", "provider_code", "ARCX"),
        "XNAS",
      ),
      aggregation: consolidated,
    ),
    decode.ReportInput(
      ..report(
        "provider-defined",
        "alpha",
        observed_with_kind("25.01", "50", "provider_code", "P-BEST"),
        observed_with_kind("25.02", "60", "provider_code", "P-BEST"),
        "XNAS",
      ),
      aggregation: provider_defined,
    ),
  ]
  let assert Ok(response) = domain.run(decode.Input(..base, reports: reports))
  let text = details(response)

  contains(text, "\"kind\":\"consolidated\"")
  contains(text, "\"coverage\":\"declared_partial\"")
  contains(text, "\"kind\":\"provider_defined\"")
  contains(text, "\"methodLabel\":\"vendor-best-v2\"")
  contains(text, "\"nbboClaim\":false")
}

pub fn track_and_aggregation_venue_mismatches_fail_closed_test() {
  let wrong_track = input_for("cn", "XNAS", "CNY", "600000")
  case domain.run(wrong_track) {
    Error(domain.InvalidField("listing.mic", _)) -> Nil
    _ -> should.fail()
  }

  let base = input_for("hk", "XHKG", "HKD", "00700")
  let bad_report =
    report(
      "bad-venue",
      "alpha",
      observed_with_kind("10", "20", "provider_code", "NOT-IN-SET"),
      observed("11", "30", "XHKG"),
      "XHKG",
    )
  case domain.run(decode.Input(..base, reports: [bad_report])) {
    Error(domain.InvalidField("reports[0].bid", _)) -> Nil
    _ -> should.fail()
  }
}

pub fn malformed_conflicts_and_clock_order_fail_closed_test() {
  let duplicated =
    decode.SideInput("conflicting", None, Some("duplicate rows"), [
      alternative("10.60", "200", "XHKG", "c"),
      alternative("10.60", "200", "XHKG", "d"),
    ])
  let base = input_for("hk", "XHKG", "HKD", "00700")
  let duplicate_report =
    report(
      "duplicate",
      "alpha",
      observed("10.5", "100", "XHKG"),
      duplicated,
      "XHKG",
    )
  case domain.run(decode.Input(..base, reports: [duplicate_report])) {
    Error(domain.InvalidField("reports[0].ask.alternatives", _)) -> Nil
    _ -> should.fail()
  }

  let reversed_clock =
    decode.ReportInput(
      ..report(
        "clock",
        "alpha",
        observed("10.5", "100", "XHKG"),
        observed("10.6", "100", "XHKG"),
        "XHKG",
      ),
      provider_time_unix_ms: 200,
      received_at_unix_ms: 100,
    )
  case domain.run(decode.Input(..base, reports: [reversed_clock])) {
    Error(domain.InvalidField("reports[0].receivedAtUnixMilliseconds", _)) ->
      Nil
    _ -> should.fail()
  }
}

pub fn explicit_unknown_stream_and_aggregation_states_are_preserved_test() {
  let base = input_for("us", "XNYS", "USD", "IBM")
  let unknown_report =
    decode.ReportInput(
      ..report(
        "unknown-stream",
        "alpha",
        observed_with_kind("100.00", "5", "provider_code", "VENDOR-X"),
        decode.SideInput("unavailable", None, Some("ask withheld"), []),
        "XNYS",
      ),
      exchange_time: decode.ExchangeTimeInput(
        "unknown",
        None,
        None,
        Some("feed has no exchange clock"),
      ),
      sequence: decode.SequenceInput(
        "unknown",
        None,
        "unknown",
        Some("feed unsequenced"),
      ),
      gap: decode.GapInput("unknown", None, None, Some("continuity unknown")),
      aggregation: decode.AggregationInput(
        "unknown",
        [],
        "unknown",
        None,
        Some("aggregation metadata absent"),
      ),
      size_unit: decode.SizeUnitInput(
        "unknown",
        None,
        Some("provider omitted semantics"),
      ),
    )
  let assert Ok(response) =
    domain.run(decode.Input(..base, reports: [unknown_report]))
  let text = details(response)

  contains(text, "feed has no exchange clock")
  contains(text, "feed unsequenced")
  contains(text, "continuity unknown")
  contains(text, "aggregation metadata absent")
  contains(text, "provider omitted semantics")
  contains(text, "\"continuityProven\":false")
}

pub fn paging_currency_mismatch_and_source_redaction_are_visible_test() {
  let base = input_for("hk", "XHKG", "HKD", "00700")
  let secret_source =
    decode.SourceInput(
      ..source_input("alpha", "a"),
      reference: "https://user:password@example.test/book?api_key=secret#fragment",
    )
  let first =
    report(
      "first",
      "alpha",
      observed("10", "10", "XHKG"),
      observed("11", "10", "XHKG"),
      "XHKG",
    )
  let second =
    decode.ReportInput(
      ..report(
        "second",
        "alpha",
        observed("12", "10", "XHKG"),
        observed("13", "10", "XHKG"),
        "XHKG",
      ),
      currency: "USD",
    )
  let assert Ok(response) =
    domain.run(
      decode.Input(
        ..base,
        sources: [secret_source],
        reports: [first, second],
        page: decode.PageInput(1, 1),
      ),
    )
  let text = details(response)

  contains(text, "\"reportId\":\"second\"")
  excludes(text, "\"reportId\":\"first\",\"sourceId\"")
  contains(text, "\"currencyMatchesListing\":false")
  contains(text, "\"nextOffset\":null")
  contains(text, "\"referenceRedacted\":true")
  excludes(text, "secret")
  excludes(text, "user:password")
  excludes(text, "#fragment")
}

fn input_for(
  track: String,
  mic: String,
  currency: String,
  symbol: String,
) -> decode.Input {
  decode.Input(
    track,
    decode.ListingInput(
      "listing:" <> symbol <> ":" <> mic,
      mic,
      symbol,
      currency,
    ),
    [source_input("alpha", "a")],
    [
      decode.ReportInput(
        ..report(
          "report-1",
          "alpha",
          observed("10.5000", "00100.00", mic),
          observed("10.6000", "00200.00", mic),
          mic,
        ),
        currency: currency,
      ),
    ],
    decode.PageInput(0, 50),
  )
}

fn source_input(
  source_id: String,
  receipt_character: String,
) -> decode.SourceInput {
  decode.SourceInput(
    source_id,
    "fixture-provider",
    "https://example.test/top-of-book",
    "licensed_vendor",
    None,
    "fixture-feed",
    decode.EntitlementInput("delayed", Some(900_000)),
    decode.LicenceInput(
      "fixture-local-analysis",
      "no_redistribution",
      Some("caller supplied"),
    ),
    string.repeat(receipt_character, 64),
  )
}

fn report(
  report_id: String,
  source_id: String,
  bid: decode.SideInput,
  ask: decode.SideInput,
  mic: String,
) -> decode.ReportInput {
  decode.ReportInput(
    report_id,
    source_id,
    "HKD",
    "2026-08-11T09:30:00.100+08:00",
    100,
    110,
    decode.ExchangeTimeInput(
      "reported",
      Some(90),
      Some("2026-08-11T09:30:00.090+08:00"),
      None,
    ),
    decode.SequenceInput("reported", Some(12), "listing", None),
    decode.GapInput("no_gap_reported", None, None, None),
    decode.AggregationInput(
      "single_venue",
      [venue("mic", mic)],
      "declared_complete",
      None,
      None,
    ),
    decode.SizeUnitInput("shares", None, None),
    ["regular"],
    bid,
    ask,
  )
}

fn observed(
  raw_price: String,
  raw_size: String,
  mic: String,
) -> decode.SideInput {
  observed_with_kind(raw_price, raw_size, "mic", mic)
}

fn observed_with_kind(
  raw_price: String,
  raw_size: String,
  venue_kind: String,
  venue_code: String,
) -> decode.SideInput {
  decode.SideInput(
    "observed",
    Some(decode.CandidateInput(
      raw_price,
      raw_size,
      venue(venue_kind, venue_code),
    )),
    None,
    [],
  )
}

fn alternative(
  raw_price: String,
  raw_size: String,
  mic: String,
  receipt_character: String,
) -> decode.AlternativeInput {
  decode.AlternativeInput(
    raw_price,
    raw_size,
    venue("mic", mic),
    string.repeat(receipt_character, 64),
  )
}

fn venue(kind: String, code: String) -> decode.VenueInput {
  decode.VenueInput(kind, code)
}

fn details(value: domain.Response) -> String {
  value |> domain.details |> json.to_string
}

fn contains(value: String, expected: String) {
  value |> string.contains(expected) |> should.be_true
}

fn excludes(value: String, expected: String) {
  value |> string.contains(expected) |> should.be_false
}
