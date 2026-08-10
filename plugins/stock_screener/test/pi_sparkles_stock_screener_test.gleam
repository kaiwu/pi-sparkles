import finance_core/time
import finance_market_alpaca/assets
import finance_market_alpaca/query
import finance_provenance/hash as provenance_hash
import finance_provenance/identity
import finance_replay/fact
import finance_replay/manifest
import finance_track
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit
import gleeunit/should
import pi_sparkles_stock_screener/decode as screen_decode
import pi_sparkles_stock_screener/domain
import pi_sparkles_stock_screener/membership as membership_projection
import pi_sparkles_stock_screener/membership_decode
import pi_sparkles_stock_screener/screen

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn input_keeps_every_provider_filter_caller_selected_test() {
  let assert Ok(input) = domain.input("live", "all", "NYSE", 200)
  let plan = domain.plan(input)
  query.asset_environment(plan) |> should.equal(query.Live)
  query.asset_status(plan) |> should.equal(query.AllStatuses)
  query.asset_exchange(plan) |> should.equal(query.Nyse)
  query.maximum_assets(plan) |> should.equal(200)

  domain.input("automatic", "all", "NYSE", 200)
  |> should.equal(Error(domain.InvalidEnvironment))
  domain.input("live", "eligible", "NYSE", 200)
  |> should.equal(Error(domain.InvalidStatus))
  domain.input("live", "all", "XNAS", 200)
  |> should.equal(Error(domain.InvalidExchange))
  domain.input("live", "all", "NYSE", 0)
  |> should.equal(Error(domain.InvalidMaximumAssets))
}

pub fn result_preserves_provider_rows_without_a_plugin_decision_test() {
  let assert Ok(input) = domain.input("paper", "active", "NASDAQ", 10)
  let plan = domain.plan(input)
  let assert Ok(snapshot) = assets.decode_snapshot(fixture(), for: plan)
  let encoded =
    domain.result_json(plan, snapshot, instant(1000), None, sha("a"), sha("b"))
    |> json.to_string
  encoded |> string.contains("provider_returned_row") |> should.be_true
  encoded |> string.contains("\"status\":\"inactive\"") |> should.be_true
  encoded |> string.contains("\"tradable\":false") |> should.be_true
  encoded |> string.contains("\"decisionOwner\":\"llm\"") |> should.be_true
  encoded |> string.contains("\"pluginDecisionFields\":[]") |> should.be_true
  encoded |> string.contains("\"rank\"") |> should.be_false
  encoded |> string.contains("\"qualified\"") |> should.be_false
  encoded |> string.contains("\"selected\"") |> should.be_false
}

pub fn screen_partitions_matched_not_matched_and_unresolved_rows_test() {
  let input =
    screen_input(
      [
        row("listing:A", "obs-a", known_value("close", "price", "12", "obs-a")),
        row("listing:B", "obs-b", known_value("close", "price", "8", "obs-b")),
        row(
          "listing:C",
          "obs-c",
          unavailable_value("close", "price", "provider field absent", "obs-c"),
        ),
      ],
      [predicate("close-above-10", "close", "greater_than", "10", "price")],
      "all",
      0,
      10,
    )
  let assert Ok(response) = screen.run(input)
  let text = response.details |> json.to_string
  text
  |> string.contains(
    "\"relationCounts\":{\"matched\":1,\"notMatched\":1,\"unresolved\":1,\"total\":3}",
  )
  |> should.be_true
  text |> string.contains("\"relation\":\"matched\"") |> should.be_true
  text |> string.contains("\"relation\":\"not_matched\"") |> should.be_true
  text |> string.contains("\"relation\":\"unresolved\"") |> should.be_true
  text |> string.contains("\"state\":\"observed_true\"") |> should.be_true
  text |> string.contains("\"state\":\"observed_false\"") |> should.be_true
  text
  |> string.contains("\"reason\":\"unknown:provider field absent\"")
  |> should.be_true
}

pub fn screen_supports_all_six_exact_decimal_operators_test() {
  let values = [
    known_value("gt", "ratio", "10.01", "obs-a"),
    known_value("gte", "ratio", "10.00", "obs-a"),
    known_value("lt", "ratio", "9.99", "obs-a"),
    known_value("lte", "ratio", "10", "obs-a"),
    known_value("eq", "ratio", "10.000", "obs-a"),
    known_value("neq", "ratio", "9", "obs-a"),
  ]
  let predicates = [
    predicate("p-gt", "gt", "greater_than", "10", "ratio"),
    predicate("p-gte", "gte", "greater_than_or_equal", "10", "ratio"),
    predicate("p-lt", "lt", "less_than", "10", "ratio"),
    predicate("p-lte", "lte", "less_than_or_equal", "10", "ratio"),
    predicate("p-eq", "eq", "equal", "10", "ratio"),
    predicate("p-neq", "neq", "not_equal", "10", "ratio"),
  ]
  let assert Ok(response) =
    screen.run(screen_input(
      [row_with_values("listing:A", "obs-a", values)],
      predicates,
      "matched",
      0,
      10,
    ))
  let text = response.details |> json.to_string
  text |> string.contains("\"matched\":1") |> should.be_true
  text |> string.contains("\"returnedCount\":1") |> should.be_true
  text
  |> string.split("\"state\":\"observed_true\"")
  |> list.length
  |> should.equal(7)
}

pub fn conflicting_alternatives_and_unit_mismatch_stay_unresolved_test() {
  let conflicting =
    screen_decode.ValueInput(
      "rsi",
      "index_points",
      "technical_receipt",
      500,
      [sha_text("technical")],
      screen_decode.FactInput(
        "conflicting",
        None,
        Some("two exact outputs were supplied"),
        ["29.5", "31.0"],
      ),
    )
  let wrong_unit = known_value("rsi", "percent", "31", "obs-b")
  let rows = [
    row("listing:A", "obs-a", conflicting),
    row("listing:B", "obs-b", wrong_unit),
  ]
  let assert Ok(response) =
    screen.run(screen_input(
      rows,
      [predicate("rsi-over-30", "rsi", "greater_than", "30", "index_points")],
      "unresolved",
      0,
      10,
    ))
  let text = response.details |> json.to_string
  text |> string.contains("\"unresolved\":2") |> should.be_true
  text |> string.contains("\"state\":\"conflicting\"") |> should.be_true
  text |> string.contains("\"raw\":\"29.5\"") |> should.be_true
  text |> string.contains("\"raw\":\"31.0\"") |> should.be_true
  text
  |> string.contains("\"reason\":\"operand_unit_mismatch\"")
  |> should.be_true
}

pub fn late_and_unbound_evidence_are_visible_not_false_test() {
  let late =
    screen_decode.ValueInput(
      "close",
      "price",
      "dataset_observation",
      1001,
      [sha_text("obs-a")],
      screen_decode.FactInput("known", Some("12"), None, []),
    )
  let unbound =
    screen_decode.ValueInput(
      "close",
      "price",
      "dataset_observation",
      500,
      [sha_text("unrelated")],
      screen_decode.FactInput("known", Some("12"), None, []),
    )
  let assert Ok(response) =
    screen.run(screen_input(
      [row("listing:A", "obs-a", late), row("listing:B", "obs-b", unbound)],
      [predicate("close", "close", "greater_than", "10", "price")],
      "unresolved",
      0,
      10,
    ))
  let text = response.details |> json.to_string
  text
  |> string.contains("\"reason\":\"value_known_after_source_cutoff\"")
  |> should.be_true
  text
  |> string.contains(
    "\"reason\":\"dataset_fact_does_not_cite_selected_observation_hash\"",
  )
  |> should.be_true
  text |> string.contains("\"state\":\"observed_false\"") |> should.be_false
}

pub fn canonical_handles_track_and_coverage_fail_closed_test() {
  let base =
    screen_input(
      [row("listing:A", "obs-a", known_value("close", "price", "12", "obs-a"))],
      [predicate("close", "close", "greater_than", "10", "price")],
      "all",
      0,
      10,
    )
  let bad_hash_context =
    screen_decode.ContextInput(
      ..base.context,
      universe: screen_decode.ManifestInput(
        ..base.context.universe,
        manifest_hash: string.repeat("f", 64),
      ),
    )
  case
    screen.run(screen_decode.ScreenInput(..base, context: bad_hash_context))
  {
    Error(screen.ManifestHashMismatch("universe", _, _)) -> Nil
    _ -> should.fail()
  }

  let bad_track_context =
    screen_decode.ContextInput(..base.context, track: "cn")
  case
    screen.run(screen_decode.ScreenInput(..base, context: bad_track_context))
  {
    Error(screen.InvalidField("context.universe", _)) -> Nil
    _ -> should.fail()
  }

  let bad_range_context =
    screen_decode.ContextInput(..base.context, date_start: "2026-01-31")
  case
    screen.run(screen_decode.ScreenInput(..base, context: bad_range_context))
  {
    Error(screen.InvalidField("context.date range versus dataset coverage", _)) ->
      Nil
    _ -> should.fail()
  }
}

pub fn stable_receipts_ignore_page_and_partition_but_bind_semantics_test() {
  let rows = [
    row("listing:A", "obs-a", known_value("close", "price", "12", "obs-a")),
    row("listing:B", "obs-b", known_value("close", "price", "8", "obs-b")),
    row(
      "listing:C",
      "obs-c",
      unavailable_value("close", "price", "absent", "obs-c"),
    ),
  ]
  let predicates = [predicate("close", "close", "greater_than", "10", "price")]
  let assert Ok(first) = screen.run(screen_input(rows, predicates, "all", 0, 1))
  let assert Ok(second) =
    screen.run(screen_input(rows, predicates, "unresolved", 0, 10))
  result_handle(first, "requestReceiptHandle")
  |> should.equal(result_handle(second, "requestReceiptHandle"))
  result_handle(first, "semanticReceiptHandle")
  |> should.equal(result_handle(second, "semanticReceiptHandle"))
  first.details
  |> json.to_string
  |> string.contains("\"nextOffset\":1")
  |> should.be_true

  let changed = [predicate("close", "close", "greater_than", "11", "price")]
  let assert Ok(changed_response) =
    screen.run(screen_input(rows, changed, "all", 0, 10))
  result_handle(first, "requestReceiptHandle")
  |> should.not_equal(result_handle(changed_response, "requestReceiptHandle"))
}

pub fn duplicate_ids_bad_policy_and_offset_fail_without_fallback_test() {
  let duplicate = predicate("same", "close", "greater_than", "10", "price")
  let base =
    screen_input(
      [row("listing:A", "obs-a", known_value("close", "price", "12", "obs-a"))],
      [duplicate, duplicate],
      "all",
      0,
      10,
    )
  case screen.run(base) {
    Error(screen.InvalidField("predicates[].id", _)) -> Nil
    _ -> should.fail()
  }

  let unique = screen_decode.ScreenInput(..base, predicates: [duplicate])
  let wrong_policy =
    screen_decode.RelationInput(
      ..unique.relation,
      match_policy: "missing_is_false",
    )
  case screen.run(screen_decode.ScreenInput(..unique, relation: wrong_policy)) {
    Error(screen.InvalidField("relation.matchPolicy", _)) -> Nil
    _ -> should.fail()
  }

  let offset = screen_decode.PageInput(..unique.page, offset: 2)
  case screen.run(screen_decode.ScreenInput(..unique, page: offset)) {
    Error(screen.InvalidField("page.offset", _)) -> Nil
    _ -> should.fail()
  }
}

pub fn screen_emits_mechanical_facts_without_decision_or_ranking_fields_test() {
  let assert Ok(response) =
    screen.run(screen_input(
      [row("listing:A", "obs-a", known_value("close", "price", "12", "obs-a"))],
      [predicate("close", "close", "greater_than", "10", "price")],
      "matched",
      0,
      10,
    ))
  let text = response.details |> json.to_string
  text |> string.contains("\"decisionOwner\":\"llm\"") |> should.be_true
  text |> string.contains("\"pluginDecisionFields\":[]") |> should.be_true
  text |> string.contains("\"qualified\"") |> should.be_false
  text |> string.contains("\"recommended\"") |> should.be_false
  text |> string.contains("\"rank\"") |> should.be_false
  text |> string.contains("\"nextAction\"") |> should.be_false
}

pub fn universe_projection_preserves_cn_hk_us_and_exact_relations_test() {
  let tracks = [
    #(finance_track.Cn, "XSHG"),
    #(finance_track.Hk, "XHKG"),
    #(finance_track.Us, "XNAS"),
  ]
  list.each(tracks, fn(track_and_mic) {
    let #(track, mic) = track_and_mic
    let universe =
      projection_manifest(track, mic, [
        projection_membership(
          track,
          mic,
          "listing:member",
          date_value(2020, 1, 1),
          fact.NotApplicable("membership remains open"),
          fact.Known(instant(100)),
        ),
        projection_membership(
          track,
          mic,
          "listing:ended",
          date_value(2020, 1, 1),
          fact.Known(date_value(2026, 2, 23)),
          fact.Known(instant(100)),
        ),
        projection_membership(
          track,
          mic,
          "listing:late",
          date_value(2020, 1, 1),
          fact.NotApplicable("membership remains open"),
          fact.Known(instant(1100)),
        ),
      ])
    let assert Ok(response) =
      membership_projection.run(projection_input(track, universe, "all", 0, 10))
    let text = response.details |> json.to_string
    text
    |> string.contains("\"track\":\"" <> finance_track.name(track) <> "\"")
    |> should.be_true
    text
    |> string.contains(
      "\"relationCounts\":{\"member\":1,\"notMember\":1,\"unresolved\":1,\"total\":3}",
    )
    |> should.be_true
    text
    |> string.contains("\"reason\":\"membership_known_after_cutoff\"")
    |> should.be_true
  })
}

pub fn universe_projection_handles_reentry_and_overlapping_active_events_test() {
  let track = finance_track.Hk
  let mic = "XHKG"
  let universe =
    projection_manifest(track, mic, [
      projection_membership(
        track,
        mic,
        "listing:reentered",
        date_value(2020, 1, 1),
        fact.Known(date_value(2024, 12, 31)),
        fact.Known(instant(100)),
      ),
      projection_membership(
        track,
        mic,
        "listing:reentered",
        date_value(2025, 1, 2),
        fact.NotApplicable("membership remains open"),
        fact.Known(instant(200)),
      ),
      projection_membership(
        track,
        mic,
        "listing:overlap",
        date_value(2020, 1, 1),
        fact.NotApplicable("membership remains open"),
        fact.Known(instant(100)),
      ),
      projection_membership(
        track,
        mic,
        "listing:overlap",
        date_value(2021, 1, 1),
        fact.NotApplicable("membership remains open"),
        fact.Known(instant(200)),
      ),
    ])
  let assert Ok(response) =
    membership_projection.run(projection_input(track, universe, "all", 0, 10))
  let text = response.details |> json.to_string
  text
  |> string.contains(
    "\"relationCounts\":{\"member\":1,\"notMember\":0,\"unresolved\":1,\"total\":2}",
  )
  |> should.be_true
  text
  |> string.contains(
    "\"relationReason\":\"multiple_active_membership_events_for_exact_listing\"",
  )
  |> should.be_true
}

pub fn universe_projection_hash_canonicality_track_and_coverage_fail_closed_test() {
  let universe =
    projection_manifest(finance_track.Cn, "XSHG", [
      projection_membership(
        finance_track.Cn,
        "XSHG",
        "listing:A",
        date_value(2020, 1, 1),
        fact.NotApplicable("membership remains open"),
        fact.Known(instant(100)),
      ),
    ])
  let base = projection_input(finance_track.Cn, universe, "all", 0, 10)
  let membership_decode.Input(track, date, cutoff, manifest_input, page) = base
  case
    membership_projection.run(membership_decode.Input(
      track,
      date,
      cutoff,
      membership_decode.ManifestInput(
        manifest_input.manifest_json,
        string.repeat("f", 64),
      ),
      page,
    ))
  {
    Error(membership_projection.ManifestHashMismatch(_, _)) -> Nil
    _ -> should.fail()
  }
  case
    membership_projection.run(membership_decode.Input(
      "hk",
      date,
      cutoff,
      manifest_input,
      page,
    ))
  {
    Error(membership_projection.InvalidField("universe", _)) -> Nil
    _ -> should.fail()
  }
  case
    membership_projection.run(membership_decode.Input(
      track,
      "2026-03-01",
      cutoff,
      manifest_input,
      page,
    ))
  {
    Error(membership_projection.InvalidField("effectiveDate", _)) -> Nil
    _ -> should.fail()
  }
  case
    membership_projection.run(membership_decode.Input(
      track,
      date,
      cutoff,
      membership_decode.ManifestInput(
        manifest_input.manifest_json <> " ",
        manifest_input.manifest_hash,
      ),
      page,
    ))
  {
    Error(membership_projection.ManifestNotCanonical) -> Nil
    _ -> should.fail()
  }
}

pub fn universe_projection_page_does_not_change_projection_handle_test() {
  let universe =
    projection_manifest(finance_track.Us, "XNAS", [
      projection_membership(
        finance_track.Us,
        "XNAS",
        "listing:A",
        date_value(2020, 1, 1),
        fact.NotApplicable("membership remains open"),
        fact.Known(instant(100)),
      ),
      projection_membership(
        finance_track.Us,
        "XNAS",
        "listing:B",
        date_value(2020, 1, 1),
        fact.NotApplicable("membership remains open"),
        fact.Known(instant(100)),
      ),
    ])
  let assert Ok(first) =
    membership_projection.run(projection_input(
      finance_track.Us,
      universe,
      "all",
      0,
      1,
    ))
  let assert Ok(second) =
    membership_projection.run(projection_input(
      finance_track.Us,
      universe,
      "member",
      1,
      1,
    ))
  projection_handle(first)
  |> should.equal(projection_handle(second))
  let text = first.details |> json.to_string
  text |> string.contains("\"nextOffset\":1") |> should.be_true
  text |> string.contains("\"decisionOwner\":\"llm\"") |> should.be_true
  text |> string.contains("\"pluginDecisionFields\":[]") |> should.be_true
}

pub fn screen_accepts_one_active_reentry_event_and_rejects_late_membership_test() {
  let base =
    screen_input(
      [row("listing:A", "obs-a", known_value("close", "price", "12", "obs-a"))],
      [predicate("close", "close", "greater_than", "10", "price")],
      "all",
      0,
      10,
    )
  let historical =
    projection_manifest(finance_track.Us, "XNAS", [
      projection_membership(
        finance_track.Us,
        "XNAS",
        "listing:A",
        date_value(2020, 1, 1),
        fact.Known(date_value(2024, 12, 31)),
        fact.Known(instant(100)),
      ),
      projection_membership(
        finance_track.Us,
        "XNAS",
        "listing:A",
        date_value(2025, 1, 2),
        fact.NotApplicable("membership remains open"),
        fact.Known(instant(200)),
      ),
    ])
  let historical_context =
    screen_decode.ContextInput(
      ..base.context,
      universe: screen_decode.ManifestInput(
        manifest.encode_universe(historical),
        historical |> manifest.universe_digest |> identity.sha256_value,
      ),
    )
  let assert Ok(active) =
    screen.run(screen_decode.ScreenInput(..base, context: historical_context))
  active.details
  |> json.to_string
  |> string.contains("\"relation\":\"matched\"")
  |> should.be_true

  let late =
    projection_manifest(finance_track.Us, "XNAS", [
      projection_membership(
        finance_track.Us,
        "XNAS",
        "listing:A",
        date_value(2020, 1, 1),
        fact.NotApplicable("membership remains open"),
        fact.Known(instant(1100)),
      ),
    ])
  let late_context =
    screen_decode.ContextInput(
      ..base.context,
      universe: screen_decode.ManifestInput(
        manifest.encode_universe(late),
        late |> manifest.universe_digest |> identity.sha256_value,
      ),
    )
  let assert Ok(unresolved) =
    screen.run(screen_decode.ScreenInput(..base, context: late_context))
  unresolved.details
  |> json.to_string
  |> string.contains("membership_known_after_source_cutoff")
  |> should.be_true
}

fn fixture() -> String {
  "[{\"id\":\"asset-aapl\",\"class\":\"us_equity\",\"exchange\":\"NASDAQ\",\"symbol\":\"AAPL\",\"name\":\"Apple Inc. Common Stock\",\"status\":\"inactive\",\"tradable\":false,\"marginable\":true,\"shortable\":false,\"easy_to_borrow\":false,\"fractionable\":true,\"attributes\":[\"has_options\"]}]"
}

fn screen_input(
  rows: List(screen_decode.RowInput),
  predicates: List(screen_decode.PredicateInput),
  partition: String,
  offset: Int,
  limit: Int,
) -> screen_decode.ScreenInput {
  let universe = universe_manifest()
  let dataset = dataset_manifest()
  screen_decode.ScreenInput(
    screen_decode.ContextInput(
      sha_text("instruction"),
      "us",
      "2026-02-01",
      "2026-02-28",
      1000,
      screen_decode.ManifestInput(
        manifest.encode_universe(universe),
        universe |> manifest.universe_digest |> identity.sha256_value,
      ),
      screen_decode.ManifestInput(
        manifest.encode_dataset(dataset),
        dataset |> manifest.dataset_digest |> identity.sha256_value,
      ),
      [sha_text("technical")],
    ),
    predicates,
    rows,
    screen_decode.RelationInput(
      "all_predicates_observed_true_v1",
      "preserve_unresolved_separately_v1",
    ),
    screen_decode.PageInput(partition, offset, limit),
  )
}

fn predicate(
  id: String,
  field: String,
  operator: String,
  threshold: String,
  unit: String,
) -> screen_decode.PredicateInput {
  screen_decode.PredicateInput(id, field, operator, threshold, unit)
}

fn row(
  listing_id: String,
  observation_id: String,
  value: screen_decode.ValueInput,
) -> screen_decode.RowInput {
  row_with_values(listing_id, observation_id, [value])
}

fn row_with_values(
  listing_id: String,
  observation_id: String,
  values: List(screen_decode.ValueInput),
) -> screen_decode.RowInput {
  screen_decode.RowInput(
    listing_id,
    "XNAS",
    "2026-02-24",
    observation_id,
    values,
  )
}

fn known_value(
  field: String,
  unit: String,
  raw: String,
  observation_id: String,
) -> screen_decode.ValueInput {
  screen_decode.ValueInput(
    field,
    unit,
    "dataset_observation",
    500,
    [sha_text(observation_id)],
    screen_decode.FactInput("known", Some(raw), None, []),
  )
}

fn unavailable_value(
  field: String,
  unit: String,
  reason: String,
  observation_id: String,
) -> screen_decode.ValueInput {
  screen_decode.ValueInput(
    field,
    unit,
    "dataset_observation",
    500,
    [sha_text(observation_id)],
    screen_decode.FactInput("unknown", None, Some(reason), []),
  )
}

fn universe_manifest() -> manifest.UniverseManifest {
  let assert Ok(coverage) =
    manifest.interval(date_value(2026, 2, 1), date_value(2026, 2, 28))
  let assert Ok(value) =
    manifest.universe(
      "universe-us",
      "1.0.0",
      finance_track.Us,
      manifest.ExactEnumerated,
      instant(900),
      coverage,
      sha("universe-source"),
      manifest.CallerDeclared,
      ["fixture point-in-time membership"],
      [
        membership("listing:A"),
        membership("listing:B"),
        membership("listing:C"),
      ],
    )
  value
}

fn membership(listing_id: String) -> manifest.Membership {
  let assert Ok(listing_interval) =
    manifest.open_interval(date_value(2020, 1, 1), None)
  manifest.Membership(
    listing_id,
    "XNAS",
    finance_track.Us,
    fact.Known(listing_id),
    fact.Known(listing_interval),
    listing_interval,
    fact.Known("common_stock"),
    fact.Known(listing_interval),
    date_value(2020, 1, 1),
    fact.NotApplicable("membership remains open in fixture"),
    fact.Known(instant(90)),
    fact.Known(instant(100)),
    instant(200),
    sha("membership-" <> listing_id),
    [],
    manifest.MembershipKnown,
  )
}

fn dataset_manifest() -> manifest.DatasetManifest {
  let assert Ok(coverage) =
    manifest.interval(date_value(2026, 2, 1), date_value(2026, 2, 28))
  let assert Ok(value) =
    manifest.dataset(
      "dataset-us",
      "1.0.0",
      "fixture-provider",
      "fixture://daily-bars",
      finance_track.Us,
      coverage,
      [
        observation("listing:A", "obs-a"),
        observation("listing:B", "obs-b"),
        observation("listing:C", "obs-c"),
      ],
      ["fixture observations"],
    )
  value
}

fn observation(
  listing_id: String,
  observation_id: String,
) -> manifest.ObservationHandle {
  manifest.ObservationHandle(
    observation_id,
    listing_id,
    "XNAS",
    finance_track.Us,
    date_value(2026, 2, 24),
    fact.Known(instant(300)),
    fact.Known(instant(310)),
    fact.Known(instant(320)),
    fact.Known(instant(330)),
    instant(400),
    fact.Known(instant(1000)),
    fact.Known("original"),
    [],
    fact.Known("regular_full"),
    fact.Known(sha("calendar")),
    fact.Known(sha("status")),
    fact.Known("price"),
    fact.Known("USD"),
    fact.Known(4),
    fact.Known("America/New_York"),
    fact.Known("raw"),
    fact.Known("shares"),
    fact.Known("fixture-access"),
    fact.Unknown("licence terms not supplied"),
    fact.Known("reported"),
    sha(observation_id),
    [],
    [],
  )
}

fn projection_manifest(
  track: finance_track.Track,
  mic: String,
  memberships: List(manifest.Membership),
) -> manifest.UniverseManifest {
  let assert Ok(coverage) =
    manifest.interval(date_value(2026, 2, 1), date_value(2026, 2, 28))
  let assert Ok(value) =
    manifest.universe(
      "universe-" <> finance_track.name(track) <> "-" <> mic,
      "1.0.0",
      track,
      manifest.ExactEnumerated,
      instant(900),
      coverage,
      sha("universe-source-" <> finance_track.name(track) <> "-" <> mic),
      manifest.CallerDeclared,
      ["caller-supplied point-in-time membership fixture"],
      memberships,
    )
  value
}

fn projection_membership(
  track: finance_track.Track,
  mic: String,
  listing_id: String,
  effective: time.Date,
  membership_end: fact.Fact(time.Date),
  knowledge_time: fact.Fact(time.Instant),
) -> manifest.Membership {
  let assert Ok(listing_interval) =
    manifest.open_interval(date_value(2010, 1, 1), None)
  manifest.Membership(
    listing_id,
    mic,
    track,
    fact.Known(listing_id),
    fact.Known(listing_interval),
    listing_interval,
    fact.Known("cash_equity"),
    fact.Known(listing_interval),
    effective,
    membership_end,
    fact.Known(instant(90)),
    knowledge_time,
    instant(500),
    sha(
      "membership-"
      <> finance_track.name(track)
      <> "-"
      <> mic
      <> "-"
      <> listing_id
      <> "-"
      <> date_identity(effective),
    ),
    [],
    manifest.MembershipKnown,
  )
}

fn projection_input(
  track: finance_track.Track,
  universe: manifest.UniverseManifest,
  partition: String,
  offset: Int,
  limit: Int,
) -> membership_decode.Input {
  membership_decode.Input(
    finance_track.name(track),
    "2026-02-24",
    1000,
    membership_decode.ManifestInput(
      manifest.encode_universe(universe),
      universe |> manifest.universe_digest |> identity.sha256_value,
    ),
    membership_decode.PageInput(partition, offset, limit),
  )
}

fn projection_handle(value: membership_projection.Response) -> String {
  let text = value.details |> json.to_string
  let assert [_, remainder] = string.split(text, "\"projectionHandle\":\"")
  let assert [value, ..] = string.split(remainder, "\"")
  value
}

fn date_identity(value: time.Date) -> String {
  let #(year, month, day) = time.date_parts(value)
  int.to_string(year)
  <> "-"
  <> int.to_string(month)
  <> "-"
  <> int.to_string(day)
}

fn result_handle(value: screen.Response, field: String) -> String {
  let text = value.details |> json.to_string
  let prefix = "\"" <> field <> "\":\""
  let assert [_, remainder] = string.split(text, prefix)
  let assert [value, ..] = string.split(remainder, "\"")
  value
}

fn sha_text(value: String) -> String {
  value |> sha |> identity.sha256_value
}

fn date_value(year: Int, month: Int, day: Int) -> time.Date {
  let assert Ok(value) = time.date(year, month, day)
  value
}

fn instant(value: Int) -> time.Instant {
  let assert Ok(value) = time.instant(value)
  value
}

fn sha(value: String) -> identity.Sha256 {
  let assert Ok(value) = provenance_hash.text(value)
  value
}
