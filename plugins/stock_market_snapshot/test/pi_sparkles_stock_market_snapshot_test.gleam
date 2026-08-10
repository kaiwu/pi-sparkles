import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit
import gleeunit/should
import pi_sparkles_stock_market_snapshot/decode
import pi_sparkles_stock_market_snapshot/domain

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn exact_cn_hk_us_snapshots_retain_track_market_and_timezone_test() {
  let assert Ok(cn) = domain.run(input("cn", "XSHG", "CNY"))
  let assert Ok(hk) = domain.run(input("hk", "XHKG", "HKD"))
  let assert Ok(us) = domain.run(input("us", "XNAS", "USD"))

  contains(details(cn), "\"track\":\"cn\"")
  contains(details(cn), "\"timezone\":\"Asia/Shanghai\"")
  contains(details(hk), "\"track\":\"hk\"")
  contains(details(hk), "\"mic\":\"XHKG\"")
  contains(details(us), "\"track\":\"us\"")
  contains(details(us), "\"marketScope\":\"us_stock_market_snapshot\"")
}

pub fn exact_breadth_group_fractions_extrema_and_paging_are_mechanical_test() {
  let assert Ok(response) = domain.run(input("us", "XNAS", "USD"))
  let text = details(response)
  contains(text, "\"totalMembers\":5")
  contains(text, "\"observedPriceMembers\":3")
  contains(text, "\"advancing\":1")
  contains(text, "\"declining\":1")
  contains(text, "\"unchanged\":1")
  contains(text, "\"unavailable\":1")
  contains(text, "\"conflicting\":1")
  contains(text, "\"advancing\":\"0.3333\"")
  contains(text, "\"id\":\"technology\"")
  contains(text, "\"changeFraction\":\"0.1\"")
  contains(text, "\"changeFraction\":\"-0.1\"")
  contains(text, "\"nextOffset\":2")
  contains(text, "exact_maximum_and_minimum_with_input_order_ties")
  excludes(text, "recommend")
}

pub fn partial_and_unknown_coverage_remain_explicit_unverified_facts_test() {
  let base = input("hk", "XHKG", "HKD")
  let snapshot = base.snapshot
  let assert Ok(partial) =
    domain.run(
      decode.Input(
        ..base,
        snapshot: decode.SnapshotInput(
          ..snapshot,
          coverage: decode.CoverageInput(
            "partial",
            Some(10),
            Some("provider_page_budget_exhausted"),
          ),
        ),
      ),
    )
  let partial_text = details(partial)
  contains(partial_text, "\"state\":\"partial\"")
  contains(partial_text, "\"expectedMembers\":10")
  contains(partial_text, "provider_page_budget_exhausted")
  contains(partial_text, "caller_or_provider_adapter_declared_unverified")

  let assert Ok(unknown) =
    domain.run(
      decode.Input(
        ..base,
        snapshot: decode.SnapshotInput(
          ..snapshot,
          coverage: decode.CoverageInput(
            "unknown",
            None,
            Some("membership_denominator_unavailable"),
          ),
        ),
      ),
    )
  contains(details(unknown), "\"state\":\"unknown\"")
  contains(details(unknown), "\"expectedMembers\":null")
}

pub fn unavailable_and_conflicting_prices_are_retained_not_resolved_test() {
  let base = input("cn", "XSHE", "CNY")
  let assert Ok(response) =
    domain.run(decode.Input(..base, page: decode.PageInput(3, 2)))
  let text = details(response)
  contains(text, "\"state\":\"unavailable\"")
  contains(text, "halted_without_price")
  contains(text, "\"state\":\"conflicting\"")
  contains(text, "conflicting_provider_rows")
  contains(text, "\"rawCurrent\":\"70.00\"")
  contains(text, "\"evidenceId\":\"" <> hash("b") <> "\"")
  contains(text, "\"direction\":null")
}

pub fn track_venue_duplicate_listing_and_group_conflicts_fail_closed_test() {
  case domain.run(input("cn", "XNAS", "CNY")) {
    Error(domain.InvalidField("market.mic", _)) -> Nil
    _ -> should.fail()
  }

  let base = input("us", "XNAS", "USD")
  let first = list_first(base.members)
  let second = list_second(base.members)
  case
    domain.run(
      decode.Input(
        ..base,
        members: [
          first,
          decode.MemberInput(..second, listing_id: first.listing_id),
        ],
        snapshot: decode.SnapshotInput(
          ..base.snapshot,
          coverage: decode.CoverageInput("complete", Some(2), None),
        ),
      ),
    )
  {
    Error(domain.InvalidField("members", _)) -> Nil
    _ -> should.fail()
  }

  let technology = decode.GroupInput("sector", "technology", "Technology")
  let changed = decode.GroupInput("sector", "technology", "Tech renamed")
  case
    domain.run(
      decode.Input(
        ..base,
        members: [
          decode.MemberInput(..first, groups: [technology]),
          decode.MemberInput(..second, groups: [changed]),
        ],
        snapshot: decode.SnapshotInput(
          ..base.snapshot,
          coverage: decode.CoverageInput("complete", Some(2), None),
        ),
      ),
    )
  {
    Error(domain.InvalidField("members.groups", _)) -> Nil
    _ -> should.fail()
  }
}

pub fn invalid_coverage_time_price_and_measurement_variants_fail_closed_test() {
  let base = input("us", "XNYS", "USD")
  let snapshot = base.snapshot
  case
    domain.run(
      decode.Input(
        ..base,
        snapshot: decode.SnapshotInput(
          ..snapshot,
          coverage: decode.CoverageInput("complete", Some(6), None),
        ),
      ),
    )
  {
    Error(domain.InvalidField("snapshot.coverage.expectedMembers", _)) -> Nil
    _ -> should.fail()
  }
  case
    domain.run(
      decode.Input(
        ..base,
        snapshot: decode.SnapshotInput(..snapshot, retrieved_at_unix_ms: 999),
      ),
    )
  {
    Error(domain.InvalidField("snapshot.retrievedAtUnixMilliseconds", _)) -> Nil
    _ -> should.fail()
  }
  let first = list_first(base.members)
  let price = first.price
  case
    domain.run(
      decode.Input(
        ..base,
        members: [
          decode.MemberInput(
            ..first,
            price: decode.PriceInput(..price, raw_previous_close: Some("0")),
          ),
        ],
        snapshot: decode.SnapshotInput(
          ..snapshot,
          coverage: decode.CoverageInput("complete", Some(1), None),
        ),
      ),
    )
  {
    Error(domain.InvalidField("members[0].price.rawPreviousClose", _)) -> Nil
    _ -> should.fail()
  }
  case
    domain.run(
      decode.Input(
        ..base,
        members: [
          decode.MemberInput(
            ..first,
            volume: decode.MeasurementInput(
              "reported",
              Some("100"),
              Some("shares"),
              Some("invented_method"),
              None,
            ),
          ),
        ],
        snapshot: decode.SnapshotInput(
          ..snapshot,
          coverage: decode.CoverageInput("complete", Some(1), None),
        ),
      ),
    )
  {
    Error(domain.InvalidField("members[0].volume", _)) -> Nil
    _ -> should.fail()
  }
}

pub fn receipt_entitlement_licence_and_redacted_source_survive_test() {
  let base = input("hk", "XHKG", "HKD")
  let source = base.source
  let assert Ok(response) =
    domain.run(
      decode.Input(
        ..base,
        source: decode.SourceInput(
          ..source,
          reference: "https://user:password@example.test/snapshot?api_key=do-not-leak#fragment",
          entitlement: decode.EntitlementInput("delayed", Some(900_000)),
        ),
      ),
    )
  let text = details(response)
  excludes(text, "do-not-leak")
  excludes(text, "user:password")
  excludes(text, "#fragment")
  contains(text, "\"referenceRedacted\":true")
  contains(text, "\"state\":\"delayed\"")
  contains(text, "\"delayMilliseconds\":900000")
  contains(text, "\"evidenceId\":\"" <> hash("a") <> "\"")
  contains(text, "\"redistribution\":\"no_redistribution\"")
  contains(text, "\"receiptBinding\":\"caller_supplied_unverified\"")
}

fn input(track: String, mic: String, currency: String) -> decode.Input {
  let members = members(mic)
  decode.Input(
    track,
    decode.MarketInput(
      mic,
      "venue",
      "primary_supplied_universe",
      "Fixture market",
    ),
    decode.SnapshotInput(
      "2026-08-10T10:00:00.123456789Z",
      1000,
      2000,
      currency,
      decode.SessionInput("regular", None),
      decode.CoverageInput("complete", Some(list.length(members)), None),
    ),
    members,
    decode.CalculationInput(4, "half_even", 10),
    decode.SourceInput(
      "fixture-adapter",
      "https://example.test/snapshot?mic=" <> mic,
      "licensed_vendor",
      None,
      "fixture-snapshot",
      decode.EntitlementInput("real_time", None),
      decode.LicenceInput(
        "fixture-local-analysis",
        "no_redistribution",
        Some("caller supplied"),
      ),
      hash("a"),
    ),
    decode.PageInput(0, 2),
  )
}

fn members(mic: String) -> List(decode.MemberInput) {
  let market_group =
    decode.GroupInput("index", "supplied_market", "Supplied market")
  let technology = decode.GroupInput("sector", "technology", "Technology")
  let finance = decode.GroupInput("sector", "finance", "Finance")
  [
    observed_member("listing:A", mic, "AAA", "110.00", "100.00", [
      market_group,
      technology,
    ]),
    observed_member("listing:B", mic, "BBB", "90.00", "100.00", [
      market_group,
      technology,
    ]),
    observed_member("listing:C", mic, "CCC", "50.000", "50.00", [
      market_group,
      finance,
    ]),
    decode.MemberInput(
      "listing:D",
      mic,
      "DDD",
      None,
      [market_group, finance],
      decode.PriceInput(
        "unavailable",
        None,
        None,
        Some("halted_without_price"),
        [],
      ),
      unavailable("not_reported"),
      unavailable("not_reported"),
    ),
    decode.MemberInput(
      "listing:E",
      mic,
      "EEE",
      None,
      [market_group],
      decode.PriceInput(
        "conflicting",
        None,
        None,
        Some("conflicting_provider_rows"),
        [
          decode.PriceAlternativeInput("70.00", "65.00", hash("b")),
          decode.PriceAlternativeInput("71.00", "65.00", hash("c")),
        ],
      ),
      unavailable("conflicting_rows"),
      unavailable("not_reported"),
    ),
  ]
}

fn observed_member(
  listing_id: String,
  mic: String,
  symbol: String,
  current: String,
  previous: String,
  groups: List(decode.GroupInput),
) -> decode.MemberInput {
  decode.MemberInput(
    listing_id,
    mic,
    symbol,
    None,
    groups,
    decode.PriceInput("observed", Some(current), Some(previous), None, []),
    decode.MeasurementInput(
      "reported",
      Some("100.00"),
      Some("shares"),
      None,
      None,
    ),
    decode.MeasurementInput(
      "reported",
      Some("0.2000"),
      Some("fraction"),
      Some("provider_reported_realized_20_day"),
      None,
    ),
  )
}

fn unavailable(reason: String) -> decode.MeasurementInput {
  decode.MeasurementInput("unavailable", None, None, None, Some(reason))
}

fn list_first(values: List(decode.MemberInput)) -> decode.MemberInput {
  let assert [value, ..] = values
  value
}

fn list_second(values: List(decode.MemberInput)) -> decode.MemberInput {
  let assert [_, value, ..] = values
  value
}

fn hash(character: String) -> String {
  string.repeat(character, 64)
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
