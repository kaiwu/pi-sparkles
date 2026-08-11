import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/string
import gleeunit
import gleeunit/should
import pi_sparkles_stock_market_calendar/decode
import pi_sparkles_stock_market_calendar/domain

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn exact_three_track_scope_timezone_and_canonical_observation_are_retained_test() {
  let assert Ok(cn) =
    domain.run(input(
      "cn",
      "XSHG",
      "market",
      None,
      [status("cn-status", "continuous", "alpha")],
      [source_input("alpha", "cn-provider", "a")],
      decode.PageInput(0, 100),
    ))
  let assert Ok(hk) =
    domain.run(input(
      "hk",
      "XHKG",
      "market",
      None,
      [status("hk-status", "continuous", "alpha")],
      [source_input("alpha", "hk-provider", "b")],
      decode.PageInput(0, 100),
    ))
  let assert Ok(us) =
    domain.run(input(
      "us",
      "XNAS",
      "listing",
      Some("AAPL"),
      [status("us-status", "pre_market", "alpha")],
      [source_input("alpha", "us-provider", "c")],
      decode.PageInput(0, 100),
    ))

  contains(details(cn), "\"track\":\"cn\"")
  contains(details(cn), "\"timezone\":\"Asia/Shanghai\"")
  contains(details(hk), "\"timezone\":\"Asia/Hong_Kong\"")
  contains(details(us), "\"timezone\":\"America/New_York\"")
  contains(details(us), "\"symbol\":\"AAPL\"")
  contains(details(us), "\"freshness\":\"unknown_not_assessed\"")
  contains(details(us), "\"session\":\"pre_market\"")
}

pub fn shortened_schedule_and_half_open_phase_matches_are_mechanical_test() {
  let facts = [
    schedule("short-day", "regular_shortened", "alpha"),
    phase(
      "opening",
      "opening_auction",
      "2026-08-11T09:15:00",
      "2026-08-11T09:30:00",
      "alpha",
    ),
    phase(
      "continuous",
      "continuous",
      "2026-08-11T09:30:00",
      "2026-08-11T11:30:00",
      "alpha",
    ),
  ]
  let assert Ok(response) =
    domain.run(input(
      "cn",
      "XSHG",
      "market",
      None,
      facts,
      [source_input("alpha", "exchange-plan", "a")],
      decode.PageInput(0, 100),
    ))
  let text = details(response)

  contains(text, "\"explicitShortenedScheduleFactIds\":[\"short-day\"]")
  contains(text, "\"activeObservedPhases\":[{\"factId\":\"continuous\"")
  excludes(text, "\"activeObservedPhases\":[{\"factId\":\"opening\"")
  contains(text, "\"factId\":\"opening\",\"kind\":\"phase\"")
  contains(text, "\"queryIntervalRelation\":\"query_at_or_after_interval_end\"")
  contains(text, "half_open_local_start_inclusive_end_exclusive")
}

pub fn agreement_disagreement_and_single_listing_halt_are_not_resolved_test() {
  let facts = [
    schedule("schedule-a", "regular_full", "alpha"),
    schedule("schedule-b", "regular_full", "beta"),
    status("status-a", "continuous", "alpha"),
    status("status-b", "midday_break", "beta"),
    halt("halt-a", "not_halted", "alpha"),
  ]
  let assert Ok(response) =
    domain.run(input(
      "hk",
      "XHKG",
      "listing",
      Some("00700"),
      facts,
      [
        source_input("alpha", "provider-alpha", "a"),
        source_input("beta", "provider-beta", "b"),
      ],
      decode.PageInput(0, 100),
    ))
  let text = details(response)

  contains(text, "\"scheduleReports\":{\"state\":\"exact_agreement\"")
  contains(text, "\"marketStatusReports\":{\"state\":\"exact_disagreement\"")
  contains(text, "\"listingHaltReports\":{\"state\":\"single_report\"")
  contains(text, "\"sourceSelection\":\"not_performed\"")
  contains(text, "\"inferredListingHalt\":null")
  contains(text, "\"correctnessVerdict\":null")
}

pub fn unavailable_and_conflicting_phase_alternatives_remain_explicit_test() {
  let conflicting_phase =
    decode.FactInput(
      "phase-conflict",
      "phase",
      "alpha",
      None,
      900,
      950,
      decode.ValueInput(
        "conflicting",
        None,
        None,
        None,
        None,
        Some("two notices"),
        [
          decode.AlternativeInput(
            "opening_auction",
            None,
            Some("2026-08-11T09:15:00"),
            Some("2026-08-11T09:31:00"),
            string.repeat("d", 64),
          ),
          decode.AlternativeInput(
            "continuous",
            None,
            Some("2026-08-11T09:30:00"),
            Some("2026-08-11T11:30:00"),
            string.repeat("e", 64),
          ),
        ],
      ),
    )
  let unavailable_status =
    decode.FactInput(
      "status-missing",
      "market_status",
      "beta",
      None,
      900,
      950,
      decode.ValueInput(
        "unavailable",
        None,
        None,
        None,
        None,
        Some("feed omitted status"),
        [],
      ),
    )
  let assert Ok(response) =
    domain.run(input(
      "us",
      "XNYS",
      "market",
      None,
      [conflicting_phase, unavailable_status],
      [
        source_input("alpha", "provider-alpha", "a"),
        source_input("beta", "provider-beta", "b"),
      ],
      decode.PageInput(0, 100),
    ))
  let text = details(response)

  contains(text, "\"marketStatusReports\":{\"state\":\"indeterminate\"")
  contains(text, "unavailable_or_conflicting_reported_fact")
  contains(text, "\"activeConflictingPhaseAlternatives\":[")
  contains(text, "\"factId\":\"phase-conflict\"")
  contains(text, "\"conflictResolution\":\"not_performed\"")
  contains(text, "\"resolution\":\"not_performed\"")
}

pub fn track_time_scope_and_listing_halt_mismatches_fail_closed_test() {
  let wrong_track =
    input(
      "cn",
      "XNAS",
      "market",
      None,
      [status("status", "continuous", "alpha")],
      [source_input("alpha", "provider", "a")],
      decode.PageInput(0, 100),
    )
  case domain.run(wrong_track) {
    Error(domain.InvalidField("scope.mic", _)) -> Nil
    _ -> should.fail()
  }

  let base =
    input(
      "cn",
      "XSHG",
      "market",
      None,
      [status("status", "continuous", "alpha")],
      [source_input("alpha", "provider", "a")],
      decode.PageInput(0, 100),
    )
  let bad_time =
    decode.Input(
      ..base,
      query: decode.QueryInput("2026-08-11", "9:30:00", "Asia/Shanghai", 1000),
    )
  case domain.run(bad_time) {
    Error(domain.InvalidField("query.localTime", _)) -> Nil
    _ -> should.fail()
  }

  let market_halt =
    decode.Input(..base, facts: [halt("halt", "halted", "alpha")])
  case domain.run(market_halt) {
    Error(domain.InvalidField("facts[0].kind", _)) -> Nil
    _ -> should.fail()
  }
}

pub fn coverage_paging_temporal_relation_and_redaction_are_visible_test() {
  let source =
    decode.SourceInput(
      ..source_input("alpha", "provider", "a"),
      reference: "https://user:password@example.test/status?api_key=secret#fragment",
      coverage: decode.CoverageInput("exact_range", Some(0), Some(999), None),
    )
  let facts = [
    schedule("schedule", "regular_full", "alpha"),
    status("status-before", "continuous", "alpha"),
    decode.FactInput(
      ..status("status-after", "closed", "alpha"),
      as_of_unix_ms: 1100,
      retrieved_at_unix_ms: 1200,
    ),
  ]
  let assert Ok(response) =
    domain.run(input(
      "us",
      "XNAS",
      "market",
      None,
      facts,
      [source],
      decode.PageInput(1, 1),
    ))
  let text = details(response)

  contains(text, "\"factId\":\"status-before\"")
  excludes(text, "\"factId\":\"schedule\",\"kind\"")
  contains(text, "\"nextOffset\":2")
  contains(text, "\"coversQuery\":false")
  contains(text, "\"queryTemporalRelation\":\"before_query\"")
  contains(text, "\"referenceRedacted\":true")
  excludes(text, "secret")
  excludes(text, "user:password")
  excludes(text, "#fragment")
}

pub fn duplicate_ids_bad_schedule_and_invalid_conflict_fail_closed_test() {
  let one = schedule("duplicate", "regular_full", "alpha")
  let base =
    input(
      "cn",
      "XSHG",
      "market",
      None,
      [one],
      [source_input("alpha", "provider", "a")],
      decode.PageInput(0, 100),
    )
  case domain.run(decode.Input(..base, facts: [one, one])) {
    Error(domain.InvalidField("facts", _)) -> Nil
    _ -> should.fail()
  }

  let repeated_source_reports = [
    status("status-one", "continuous", "alpha"),
    status("status-two", "continuous", "alpha"),
  ]
  let assert Ok(repeated_response) =
    domain.run(decode.Input(..base, facts: repeated_source_reports))
  contains(details(repeated_response), "duplicate_source_reports")

  let wrong_date = decode.FactInput(..one, date: Some("2026-08-12"))
  case domain.run(decode.Input(..base, facts: [wrong_date])) {
    Error(domain.InvalidField("facts[0].date", _)) -> Nil
    _ -> should.fail()
  }

  let bad_phase =
    phase(
      "bad-phase",
      "continuous",
      "2026-08-11T10:00:00",
      "2026-08-11T09:00:00",
      "alpha",
    )
  case domain.run(decode.Input(..base, facts: [bad_phase])) {
    Error(domain.InvalidField("facts[0].value", _)) -> Nil
    _ -> should.fail()
  }

  let same_conflict =
    decode.FactInput(
      "same-conflict",
      "market_status",
      "alpha",
      None,
      900,
      950,
      decode.ValueInput(
        "conflicting",
        None,
        None,
        None,
        None,
        Some("duplicate"),
        [
          decode.AlternativeInput(
            "continuous",
            None,
            None,
            None,
            string.repeat("e", 64),
          ),
          decode.AlternativeInput(
            "continuous",
            None,
            None,
            None,
            string.repeat("f", 64),
          ),
        ],
      ),
    )
  case domain.run(decode.Input(..base, facts: [same_conflict])) {
    Error(domain.InvalidField("facts[0].value.alternatives", _)) -> Nil
    _ -> should.fail()
  }
}

fn input(
  track: String,
  mic: String,
  scope_kind: String,
  symbol: Option(String),
  facts: List(decode.FactInput),
  sources: List(decode.SourceInput),
  page: decode.PageInput,
) -> decode.Input {
  decode.Input(
    track,
    decode.ScopeInput(scope_kind, "scope:fixture:" <> mic, mic, symbol),
    decode.QueryInput("2026-08-11", "09:30:00", timezone(track), 1000),
    sources,
    facts,
    page,
  )
}

fn timezone(track: String) -> String {
  case track {
    "cn" -> "Asia/Shanghai"
    "hk" -> "Asia/Hong_Kong"
    "us" -> "America/New_York"
    _ -> "Asia/Shanghai"
  }
}

fn source_input(
  source_id: String,
  provider: String,
  hash_character: String,
) -> decode.SourceInput {
  decode.SourceInput(
    source_id,
    provider,
    "https://example.test/" <> source_id,
    "licensed_vendor",
    None,
    "fixture-feed",
    decode.CoverageInput("exact_range", Some(0), Some(2000), None),
    decode.EntitlementInput("delayed", Some(900_000)),
    decode.LicenceInput(
      "fixture-local-analysis",
      "no_redistribution",
      Some("caller supplied"),
    ),
    string.repeat(hash_character, 64),
  )
}

fn schedule(
  fact_id: String,
  category: String,
  source_id: String,
) -> decode.FactInput {
  decode.FactInput(
    fact_id,
    "schedule",
    source_id,
    Some("2026-08-11"),
    900,
    950,
    observed(category, None, None),
  )
}

fn status(
  fact_id: String,
  category: String,
  source_id: String,
) -> decode.FactInput {
  decode.FactInput(
    fact_id,
    "market_status",
    source_id,
    None,
    900,
    950,
    observed(category, None, None),
  )
}

fn halt(
  fact_id: String,
  category: String,
  source_id: String,
) -> decode.FactInput {
  decode.FactInput(
    fact_id,
    "listing_halt",
    source_id,
    None,
    900,
    950,
    observed(category, None, None),
  )
}

fn phase(
  fact_id: String,
  category: String,
  starts: String,
  ends: String,
  source_id: String,
) -> decode.FactInput {
  decode.FactInput(
    fact_id,
    "phase",
    source_id,
    None,
    900,
    950,
    observed(category, Some(starts), Some(ends)),
  )
}

fn observed(
  category: String,
  starts: Option(String),
  ends: Option(String),
) -> decode.ValueInput {
  decode.ValueInput("observed", Some(category), None, starts, ends, None, [])
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
