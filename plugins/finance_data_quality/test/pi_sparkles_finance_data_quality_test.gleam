import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/string
import gleeunit
import gleeunit/should
import pi_sparkles_finance_data_quality/decode
import pi_sparkles_finance_data_quality/domain

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn exact_three_track_scope_is_retained_test() {
  let assert Ok(cn) = domain.run(empty_input("cn", "XSHG", Some("600519")))
  let assert Ok(hk) = domain.run(empty_input("hk", "XHKG", Some("00700")))
  let assert Ok(us) = domain.run(empty_input("us", "XNAS", Some("AAPL")))

  contains(details(cn), "\"track\":\"cn\"")
  contains(details(cn), "\"timezone\":\"Asia/Shanghai\"")
  contains(details(hk), "\"track\":\"hk\"")
  contains(details(hk), "\"mic\":\"XHKG\"")
  contains(details(us), "\"track\":\"us\"")
  contains(details(us), "\"symbol\":\"AAPL\"")
}

pub fn exact_agreement_disagreement_missing_and_freshness_are_mechanical_test() {
  let assert Ok(response) = domain.run(comparison_input())
  let text = details(response)

  contains(text, "\"coordinates\":3")
  contains(text, "\"missingExpectedCoordinates\":1")
  contains(text, "\"fresh\":2")
  contains(text, "\"stale\":2")
  contains(text, "\"exactAgreements\":1")
  contains(text, "\"exactDisagreements\":1")
  contains(text, "\"state\":\"exact_agreement\"")
  contains(text, "\"state\":\"exact_disagreement\"")
  contains(text, "\"overallVerdict\":null")
  contains(text, "\"assessmentStatus\":\"findings_only_no_quality_verdict\"")
}

pub fn same_source_duplicates_are_retained_without_resolution_test() {
  let base = comparison_input()
  let duplicated =
    decode.FactInput(
      "alpha:t1:duplicate",
      "2026-08-10T10:00:00Z",
      "last_price",
      "alpha",
      1600,
      1700,
      usd_price_unit(),
      raw_adjustment(),
      observed("100.000"),
    )
  let assert Ok(response) =
    domain.run(
      decode.Input(..base, facts: list_append(base.facts, [duplicated])),
    )
  let text = details(response)

  contains(text, "\"duplicateSourceGroups\":1")
  contains(text, "\"classification\":\"exact_repeated_fact\"")
  contains(text, "alpha:t1:duplicate")
  contains(text, "\"reason\":\"duplicate_provider_rows\"")
  contains(text, "\"resolution\":\"not_performed\"")
}

pub fn unit_and_adjustment_incompatibility_block_provider_comparison_test() {
  let base = comparison_input()
  let first = fact("alpha:u", "unit", "close", "alpha", "10", 1600)
  let different_unit =
    decode.FactInput(
      "beta:u",
      "unit",
      "close",
      "beta",
      1600,
      1700,
      decode.UnitInput("currency_per_share", Some("HKD"), None),
      raw_adjustment(),
      observed("10"),
    )
  let adjusted =
    decode.FactInput(
      "beta:a",
      "adjustment",
      "close",
      "beta",
      1600,
      1700,
      usd_price_unit(),
      decode.AdjustmentInput("split_adjusted", None, None),
      observed("10"),
    )
  let raw = fact("alpha:a", "adjustment", "close", "alpha", "10", 1600)
  let assert Ok(response) =
    domain.run(
      decode.Input(..base, expected_coordinates: [], facts: [
        first,
        different_unit,
        raw,
        adjusted,
      ]),
    )
  let text = details(response)

  contains(text, "\"unitIncompatibleCoordinates\":1")
  contains(text, "\"adjustmentIncompatibleCoordinates\":1")
  contains(text, "\"state\":\"incompatible_context\"")
  contains(text, "\"reason\":\"unit_incompatibility\"")
  contains(text, "\"reason\":\"adjustment_incompatibility\"")
  contains(text, "\"coercion\":\"not_performed\"")
}

pub fn unavailable_conflicting_and_unknown_context_remain_indeterminate_test() {
  let base = comparison_input()
  let unavailable =
    decode.FactInput(
      "alpha:x",
      "x",
      "close",
      "alpha",
      1600,
      1700,
      usd_price_unit(),
      raw_adjustment(),
      decode.ValueInput("unavailable", None, Some("not_reported"), []),
    )
  let conflicting =
    decode.FactInput(
      "beta:x",
      "x",
      "close",
      "beta",
      1600,
      1700,
      usd_price_unit(),
      raw_adjustment(),
      decode.ValueInput("conflicting", None, Some("two_rows"), [
        decode.AlternativeInput("10", string.repeat("c", 64)),
        decode.AlternativeInput("11", string.repeat("d", 64)),
      ]),
    )
  let unknown_alpha =
    decode.FactInput(
      "alpha:y",
      "y",
      "ratio",
      "alpha",
      1600,
      1700,
      decode.UnitInput("unknown", None, None),
      decode.AdjustmentInput("unknown", None, None),
      observed("1"),
    )
  let unknown_beta =
    decode.FactInput(
      "beta:y",
      "y",
      "ratio",
      "beta",
      1600,
      1700,
      decode.UnitInput("unknown", None, None),
      decode.AdjustmentInput("unknown", None, None),
      observed("1"),
    )
  let assert Ok(response) =
    domain.run(
      decode.Input(..base, expected_coordinates: [], facts: [
        unavailable,
        conflicting,
        unknown_alpha,
        unknown_beta,
      ]),
    )
  let text = details(response)

  contains(text, "\"state\":\"unavailable\"")
  contains(text, "\"state\":\"conflicting\"")
  contains(text, "\"reason\":\"unavailable_or_conflicting_provider_fact\"")
  contains(text, "\"reason\":\"unknown_unit_or_adjustment\"")
  contains(text, "\"correctnessVerdict\":null")
}

pub fn invalid_track_time_reference_and_conflict_variants_fail_closed_test() {
  case domain.run(empty_input("cn", "XNAS", Some("AAPL"))) {
    Error(domain.InvalidField("scope.mic", _)) -> Nil
    _ -> should.fail()
  }

  let base = comparison_input()
  let future = fact("future", "future", "close", "alpha", "10", 2100)
  case domain.run(decode.Input(..base, facts: [future])) {
    Error(domain.InvalidField("facts[0].asOfUnixMilliseconds", _)) -> Nil
    _ -> should.fail()
  }

  let unknown_source =
    decode.FactInput(..future, as_of_unix_ms: 1600, source_id: "missing")
  case domain.run(decode.Input(..base, facts: [unknown_source])) {
    Error(domain.InvalidField("facts[0].sourceId", _)) -> Nil
    _ -> should.fail()
  }

  let identical_conflict =
    decode.FactInput(
      ..future,
      as_of_unix_ms: 1600,
      value: decode.ValueInput("conflicting", None, Some("same_value"), [
        decode.AlternativeInput("10.0", string.repeat("e", 64)),
        decode.AlternativeInput("10.00", string.repeat("f", 64)),
      ]),
    )
  case domain.run(decode.Input(..base, facts: [identical_conflict])) {
    Error(domain.InvalidField("facts[0].value.alternatives", _)) -> Nil
    _ -> should.fail()
  }
}

pub fn expected_then_first_seen_order_paging_and_redaction_are_stable_test() {
  let base = comparison_input()
  let sources = base.sources
  let first = sources |> first_source
  let redacted =
    decode.SourceInput(
      ..first,
      reference: "https://user:password@example.test/quotes?api_key=secret#fragment",
    )
  let assert [_, beta] = sources
  let assert Ok(response) =
    domain.run(
      decode.Input(
        ..base,
        sources: [redacted, beta],
        facts: list_append(base.facts, [
          fact("alpha:additional", "additional", "close", "alpha", "9", 1600),
        ]),
        page: decode.PageInput(3, 1),
      ),
    )
  let text = details(response)

  contains(text, "\"observationKey\":\"additional\"")
  contains(text, "\"nextOffset\":null")
  contains(text, "\"referenceRedacted\":true")
  excludes(text, "secret")
  excludes(text, "user:password")
  excludes(text, "#fragment")
}

fn comparison_input() -> decode.Input {
  decode.Input(
    "us",
    decode.ScopeInput("listing", "listing:AAPL:XNAS", "XNAS", Some("AAPL")),
    decode.FreshnessPolicyInput("assess", Some(2000), Some(500), None),
    [
      decode.CoordinateInput("2026-08-10T10:00:00Z", "last_price"),
      decode.CoordinateInput("2026-08-10T10:01:00Z", "last_price"),
      decode.CoordinateInput("2026-08-10T10:02:00Z", "last_price"),
    ],
    [
      source_input("alpha", "alpha-provider", "a"),
      source_input("beta", "beta-provider", "b"),
    ],
    [
      fact(
        "alpha:t1",
        "2026-08-10T10:00:00Z",
        "last_price",
        "alpha",
        "100.00",
        1600,
      ),
      fact("beta:t1", "2026-08-10T10:00:00Z", "last_price", "beta", "100", 1600),
      fact(
        "alpha:t2",
        "2026-08-10T10:01:00Z",
        "last_price",
        "alpha",
        "101",
        1000,
      ),
      fact("beta:t2", "2026-08-10T10:01:00Z", "last_price", "beta", "102", 1000),
    ],
    decode.PageInput(0, 100),
  )
}

fn empty_input(
  track: String,
  mic: String,
  symbol: Option(String),
) -> decode.Input {
  decode.Input(
    track,
    decode.ScopeInput("listing", "listing:fixture:" <> mic, mic, symbol),
    decode.FreshnessPolicyInput(
      "not_assessed",
      None,
      None,
      Some("historical_series"),
    ),
    [],
    [source_input("alpha", "alpha-provider", "a")],
    [],
    decode.PageInput(0, 100),
  )
}

fn fact(
  fact_id: String,
  key: String,
  metric: String,
  source_id: String,
  value: String,
  as_of: Int,
) -> decode.FactInput {
  decode.FactInput(
    fact_id,
    key,
    metric,
    source_id,
    as_of,
    as_of + 100,
    usd_price_unit(),
    raw_adjustment(),
    observed(value),
  )
}

fn observed(value: String) -> decode.ValueInput {
  decode.ValueInput("observed", Some(value), None, [])
}

fn usd_price_unit() -> decode.UnitInput {
  decode.UnitInput("currency_per_share", Some("USD"), None)
}

fn raw_adjustment() -> decode.AdjustmentInput {
  decode.AdjustmentInput("raw", None, None)
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
    decode.EntitlementInput("delayed", Some(900_000)),
    decode.LicenceInput(
      "fixture-local-analysis",
      "no_redistribution",
      Some("caller supplied"),
    ),
    string.repeat(hash_character, 64),
  )
}

fn first_source(values: List(decode.SourceInput)) -> decode.SourceInput {
  let assert [first, ..] = values
  first
}

fn list_append(left: List(value), right: List(value)) -> List(value) {
  case left {
    [] -> right
    [first, ..rest] -> [first, ..list_append(rest, right)]
  }
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
