import finance_core/time
import finance_provenance/hash as provenance_hash
import finance_provenance/identity
import finance_quant/cn
import finance_quant/common
import finance_quant/event_study
import finance_quant/factor
import finance_replay/fact
import finance_replay/manifest
import finance_track
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None}
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn cn_snapshot_retains_unresolved_duplicates_and_exact_turnover_test() {
  let packet =
    json.object([
      #("schemaVersion", json.int(1)),
      #("contractId", json.string("cn_market_snapshot_v1")),
      #("operation", json.string("calculate_snapshot")),
      #("snapshotId", json.string("cn-2026-08-12-close")),
      #("asOfUnixMilliseconds", json.int(1000)),
      #("retrievedAtUnixMilliseconds", json.int(1100)),
      #("coverageState", json.string("partial")),
      #("expectedMembers", json.int(4)),
      #(
        "coverageReason",
        json.string("one member absent from supplied source packet"),
      ),
      #("entitlement", json.string("fixture-local-analysis")),
      #("licence", json.string("rights-safe deterministic fixture")),
      #("sourceReceipt", json.string(sha_text("snapshot-source"))),
      #(
        "members",
        json.array(
          [
            snapshot_member(
              "600000",
              "XSHG",
              "bank",
              "10",
              "9",
              "1000",
              "row-a",
            ),
            snapshot_member("000001", "XSHE", "bank", "8", "9", "2000", "row-b"),
            snapshot_unresolved("600000", "XSHG", "bank", "suspended", "row-c"),
          ],
          fn(value) { value },
        ),
      ),
    ])
    |> json.to_string
  let assert Ok(response) = cn.market_snapshot(packet, sha_text(packet))
  let text = response |> common.details |> json.to_string
  text |> string.contains("\"advanced\":1") |> should.be_true
  text |> string.contains("\"declined\":1") |> should.be_true
  text |> string.contains("\"unresolved\":1") |> should.be_true
  text |> string.contains("\"raw\":\"3000\"") |> should.be_true
  text |> string.contains("600000:XSHG") |> should.be_true
  text |> string.contains("market completion") |> should.be_true
}

pub fn cn_screen_keeps_late_and_missing_facts_unresolved_test() {
  let #(universe, dataset) =
    manifests(finance_track.Cn, "XSHG", ["listing:A", "listing:B"])
  let packet =
    json.object([
      #("schemaVersion", json.int(1)),
      #("contractId", json.string("cn_stock_screener_v1")),
      #("operation", json.string("screen")),
      #("binding", binding_json("cn", universe, dataset, 1000)),
      #(
        "predicates",
        json.array(
          [
            json.object([
              #("id", json.string("market-cap")),
              #("field", json.string("market_cap")),
              #("operator", json.string("greater_than")),
              #("threshold", json.string("100")),
              #("unit", json.string("CNY")),
            ]),
          ],
          fn(value) { value },
        ),
      ),
      #(
        "rows",
        json.array(
          [
            screen_row(
              "listing:A",
              "XSHG",
              "obs-listing:A",
              "known",
              "120",
              None,
              900,
            ),
            screen_row(
              "listing:B",
              "XSHG",
              "obs-listing:B",
              "known",
              "150",
              None,
              1200,
            ),
          ],
          fn(value) { value },
        ),
      ),
    ])
    |> json.to_string
  let assert Ok(response) = cn.stock_screen(packet, sha_text(packet))
  let text = response |> common.details |> json.to_string
  text |> string.contains("\"matched\":1") |> should.be_true
  text |> string.contains("\"unresolved\":1") |> should.be_true
  text |> string.contains("known_after_cutoff") |> should.be_true
  text |> string.contains("\"listingId\":\"listing:B\"") |> should.be_true
}

pub fn event_study_calculates_market_adjusted_car_and_retains_failure_test() {
  let #(universe, dataset) =
    manifests(finance_track.Us, "XNAS", ["listing:A", "listing:B"])
  let performed =
    json.object([
      #("eventId", json.string("event-a")),
      #("listingId", json.string("listing:A")),
      #("mic", json.string("XNAS")),
      #("eventDate", json.string("2026-02-24")),
      #("clusterId", json.string("cluster-a")),
      #("duplicateOf", json.null()),
      #("delistedDuringWindow", json.bool(False)),
      #("unperformedReason", json.null()),
      #(
        "securityPrices",
        price_points(
          [#(-3, "100"), #(-2, "110"), #(-1, "121"), #(0, "121"), #(1, "133.1")],
          "security",
        ),
      ),
      #(
        "benchmarkPrices",
        price_points(
          [
            #(-3, "100"),
            #(-2, "105"),
            #(-1, "110.25"),
            #(0, "110.25"),
            #(1, "115.7625"),
          ],
          "benchmark",
        ),
      ),
      #("eventReceipt", json.string(sha_text("event-a"))),
    ])
  let failed =
    json.object([
      #("eventId", json.string("event-b")),
      #("listingId", json.string("listing:B")),
      #("mic", json.string("XNAS")),
      #("eventDate", json.string("2026-02-25")),
      #("clusterId", json.string("cluster-b")),
      #("duplicateOf", json.null()),
      #("delistedDuringWindow", json.bool(True)),
      #("unperformedReason", json.string("delisted_during_event_window")),
      #("securityPrices", json.array([], fn(value) { value })),
      #("benchmarkPrices", json.array([], fn(value) { value })),
      #("eventReceipt", json.string(sha_text("event-b"))),
    ])
  let packet =
    json.object([
      #("schemaVersion", json.int(1)),
      #("contractId", json.string("stock_event_study_v1")),
      #("operation", json.string("calculate")),
      #("binding", binding_json("us", universe, dataset, 1000)),
      #(
        "definition",
        json.object([
          #("studyId", json.string("study-market-adjusted")),
          #("eventType", json.string("earnings_release")),
          #("model", json.string("market_adjusted_v1")),
          #("returnKind", json.string("simple_return_v1")),
          #(
            "estimationWindow",
            json.object([
              #("startOffset", json.int(-2)),
              #("endOffset", json.int(-1)),
            ]),
          ),
          #(
            "eventWindow",
            json.object([
              #("startOffset", json.int(0)),
              #("endOffset", json.int(1)),
            ]),
          ),
          #("clusterPolicy", json.string("include_all")),
          #("missingPolicy", json.string("retain_partial_unperformed")),
          #("scale", json.int(6)),
          #("rounding", json.string("half_even")),
          #("requestedStatistics", json.array(["car_mean"], json.string)),
        ]),
      ),
      #("events", json.array([performed, failed], fn(value) { value })),
    ])
    |> json.to_string
  let assert Ok(response) = event_study.calculate(packet, sha_text(packet))
  let text = response |> common.details |> json.to_string
  text |> string.contains("\"performedCount\":1") |> should.be_true
  text |> string.contains("\"unperformedCount\":1") |> should.be_true
  text |> string.contains("\"car\":\"0.05\"") |> should.be_true
  text |> string.contains("delisted_during_event_window") |> should.be_true
  text |> string.contains("causal") |> should.be_true
}

pub fn factor_study_binds_vintages_and_calculates_buckets_ic_and_turnover_test() {
  let ids = ["listing:A", "listing:B", "listing:C", "listing:D"]
  let #(universe, dataset) = manifests(finance_track.Us, "XNAS", ids)
  let first =
    factor_period("p1", 100, [
      #("listing:A", "1", "0.01"),
      #("listing:B", "2", "0.02"),
      #("listing:C", "3", "0.03"),
      #("listing:D", "4", "0.04"),
    ])
  let second =
    factor_period("p2", 200, [
      #("listing:A", "4", "0.04"),
      #("listing:B", "3", "0.03"),
      #("listing:C", "2", "0.02"),
      #("listing:D", "1", "0.01"),
    ])
  let packet =
    json.object([
      #("schemaVersion", json.int(1)),
      #("contractId", json.string("stock_factor_lab_v1")),
      #("operation", json.string("calculate")),
      #("binding", binding_json("us", universe, dataset, 1000)),
      #(
        "definition",
        json.object([
          #("factorId", json.string("size-v1")),
          #("sourceField", json.string("market_cap")),
          #("sourceUnit", json.string("USD")),
          #("calculation", json.string("identity(market_cap)")),
          #("transformation", json.string("rank_v1")),
          #("availabilityRule", json.string("known_at_or_before_period_cutoff")),
          #("rebalanceSchedule", json.string("caller_supplied_month_end")),
          #("weighting", json.string("equal_weight")),
          #("bucketCount", json.int(2)),
          #("direction", json.string("high_minus_low")),
          #("returnHorizon", json.string("next_month")),
          #("currency", json.string("USD")),
          #("missingPolicy", json.string("retain_unperformed")),
          #(
            "survivorshipPolicy",
            json.string("include_delisted_with_unknown_return"),
          ),
          #("icMethod", json.string("pearson_v1")),
          #("scale", json.int(6)),
          #("rounding", json.string("half_even")),
        ]),
      ),
      #("periods", json.array([first, second], fn(value) { value })),
    ])
    |> json.to_string
  let assert Ok(response) = factor.calculate(packet, sha_text(packet))
  let text = response |> common.details |> json.to_string
  text |> string.contains("\"periodCount\":2") |> should.be_true
  text |> string.contains("\"factorReturn\":\"0.02\"") |> should.be_true
  text |> string.contains("\"turnover\":\"1\"") |> should.be_true
  text |> string.contains("\"bucket\":2") |> should.be_true
  text |> string.contains("factor discovery") |> should.be_true
}

pub fn factor_study_rejects_late_factor_as_insufficient_bucket_population_test() {
  let #(universe, dataset) =
    manifests(finance_track.Us, "XNAS", ["listing:A", "listing:B"])
  let late_member = factor_member("listing:A", "1", "0.01", 1200)
  let on_time = factor_member("listing:B", "2", "0.02", 900)
  let period =
    json.object([
      #("periodId", json.string("p1")),
      #("atUnixMilliseconds", json.int(100)),
      #("knowledgeCutoffUnixMilliseconds", json.int(1000)),
      #("rebalanceReceipt", json.string(sha_text("rebalance-p1"))),
      #("members", json.array([late_member, on_time], fn(value) { value })),
    ])
  let packet =
    json.object([
      #("schemaVersion", json.int(1)),
      #("contractId", json.string("stock_factor_lab_v1")),
      #("operation", json.string("calculate")),
      #("binding", binding_json("us", universe, dataset, 1000)),
      #(
        "definition",
        json.object([
          #("factorId", json.string("late-test")),
          #("sourceField", json.string("market_cap")),
          #("sourceUnit", json.string("USD")),
          #("calculation", json.string("identity")),
          #("transformation", json.string("raw_v1")),
          #("availabilityRule", json.string("known_by_cutoff")),
          #("rebalanceSchedule", json.string("caller")),
          #("weighting", json.string("equal_weight")),
          #("bucketCount", json.int(2)),
          #("direction", json.string("high_minus_low")),
          #("returnHorizon", json.string("next_month")),
          #("currency", json.string("USD")),
          #("missingPolicy", json.string("retain_unperformed")),
          #(
            "survivorshipPolicy",
            json.string("include_delisted_with_unknown_return"),
          ),
          #("icMethod", json.string("pearson_v1")),
          #("scale", json.int(6)),
          #("rounding", json.string("half_even")),
        ]),
      ),
      #("periods", json.array([period], fn(value) { value })),
    ])
    |> json.to_string
  case factor.calculate(packet, sha_text(packet)) {
    Error(common.CalculationFailure(reason)) ->
      reason |> string.contains("fewer eligible listings") |> should.be_true
    _ -> should.fail()
  }
}

fn snapshot_member(
  listing_id: String,
  mic: String,
  group_id: String,
  current: String,
  previous: String,
  turnover: String,
  receipt: String,
) -> json.Json {
  json.object([
    #("listingId", json.string(listing_id)),
    #("mic", json.string(mic)),
    #("board", json.string("main")),
    #("shareClass", json.string("A")),
    #("status", json.string("listed")),
    #("groupId", json.string(group_id)),
    #(
      "price",
      json.object([
        #("state", json.string("observed")),
        #("current", json.string(current)),
        #("previousClose", json.string(previous)),
        #("reason", json.null()),
      ]),
    ),
    #(
      "turnover",
      json.object([
        #("state", json.string("known")),
        #("raw", json.string(turnover)),
        #("unit", json.string("CNY")),
        #("reason", json.null()),
      ]),
    ),
    #("sourceReceipt", json.string(sha_text(receipt))),
  ])
}

fn snapshot_unresolved(
  listing_id: String,
  mic: String,
  group_id: String,
  reason: String,
  receipt: String,
) -> json.Json {
  json.object([
    #("listingId", json.string(listing_id)),
    #("mic", json.string(mic)),
    #("board", json.string("main")),
    #("shareClass", json.string("A")),
    #("status", json.string("suspended")),
    #("groupId", json.string(group_id)),
    #(
      "price",
      json.object([
        #("state", json.string("unavailable")),
        #("current", json.null()),
        #("previousClose", json.null()),
        #("reason", json.string(reason)),
      ]),
    ),
    #(
      "turnover",
      json.object([
        #("state", json.string("not_obtained")),
        #("raw", json.null()),
        #("unit", json.null()),
        #("reason", json.string(reason)),
      ]),
    ),
    #("sourceReceipt", json.string(sha_text(receipt))),
  ])
}

fn screen_row(
  listing_id: String,
  mic: String,
  observation_id: String,
  state: String,
  raw: String,
  reason: Option(String),
  known_at: Int,
) -> json.Json {
  json.object([
    #("listingId", json.string(listing_id)),
    #("mic", json.string(mic)),
    #("board", json.string("main")),
    #("shareClass", json.string("A")),
    #("status", json.string("listed")),
    #("membershipState", json.string("member")),
    #("membershipReason", json.null()),
    #(
      "membershipReceipt",
      json.string(sha_text("membership-projection-" <> listing_id)),
    ),
    #("observationId", json.string(observation_id)),
    #(
      "values",
      json.array(
        [
          json.object([
            #("field", json.string("market_cap")),
            #("unit", json.string("CNY")),
            #("state", json.string(state)),
            #("raw", json.string(raw)),
            #("reason", json.nullable(reason, json.string)),
            #("alternatives", json.array([], json.string)),
            #("knownAtUnixMilliseconds", json.int(known_at)),
            #(
              "receipts",
              json.array([sha_text("fact-" <> listing_id)], json.string),
            ),
          ]),
        ],
        fn(value) { value },
      ),
    ),
  ])
}

fn price_points(values: List(#(Int, String)), prefix: String) -> json.Json {
  values
  |> list.index_map(fn(value, index) {
    json.object([
      #("offset", json.int(value.0)),
      #("raw", json.string(value.1)),
      #(
        "sourceReceipt",
        json.string(sha_text(prefix <> "-" <> int.to_string(index))),
      ),
    ])
  })
  |> fn(values) { json.array(values, fn(value) { value }) }
}

fn factor_period(
  period_id: String,
  at: Int,
  values: List(#(String, String, String)),
) -> json.Json {
  json.object([
    #("periodId", json.string(period_id)),
    #("atUnixMilliseconds", json.int(at)),
    #("knowledgeCutoffUnixMilliseconds", json.int(1000)),
    #("rebalanceReceipt", json.string(sha_text("rebalance-" <> period_id))),
    #(
      "members",
      json.array(
        list.map(values, fn(value) {
          factor_member(value.0, value.1, value.2, 900)
        }),
        fn(value) { value },
      ),
    ),
  ])
}

fn factor_member(
  listing_id: String,
  factor_raw: String,
  return_raw: String,
  known_at: Int,
) -> json.Json {
  json.object([
    #("listingId", json.string(listing_id)),
    #("mic", json.string("XNAS")),
    #("observationId", json.string("obs-" <> listing_id)),
    #("membershipState", json.string("member")),
    #(
      "membershipReceipt",
      json.string(sha_text("membership-projection-" <> listing_id)),
    ),
    #("factor", known_fact(factor_raw, known_at, "factor-" <> listing_id)),
    #("forwardReturn", known_fact(return_raw, 900, "return-" <> listing_id)),
    #("weight", json.null()),
    #("delisted", json.bool(False)),
    #("suspended", json.bool(False)),
  ])
}

fn known_fact(raw: String, known_at: Int, receipt: String) -> json.Json {
  json.object([
    #("state", json.string("known")),
    #("raw", json.string(raw)),
    #("knownAtUnixMilliseconds", json.int(known_at)),
    #("reason", json.null()),
    #("alternatives", json.array([], json.string)),
    #("receipts", json.array([sha_text(receipt)], json.string)),
  ])
}

fn binding_json(
  track: String,
  universe: manifest.UniverseManifest,
  dataset: manifest.DatasetManifest,
  cutoff: Int,
) -> json.Json {
  json.object([
    #("track", json.string(track)),
    #(
      "universe",
      json.object([
        #("manifestJson", json.string(manifest.encode_universe(universe))),
        #(
          "manifestHash",
          json.string(
            universe |> manifest.universe_digest |> identity.sha256_value,
          ),
        ),
      ]),
    ),
    #(
      "dataset",
      json.object([
        #("manifestJson", json.string(manifest.encode_dataset(dataset))),
        #(
          "manifestHash",
          json.string(
            dataset |> manifest.dataset_digest |> identity.sha256_value,
          ),
        ),
      ]),
    ),
    #("knowledgeCutoffUnixMilliseconds", json.int(cutoff)),
    #("calendarReceipt", json.string(sha_text("calendar"))),
    #("trialId", json.string("trial-001")),
  ])
}

fn manifests(
  track: finance_track.Track,
  mic: String,
  listing_ids: List(String),
) -> #(manifest.UniverseManifest, manifest.DatasetManifest) {
  let assert Ok(coverage) =
    manifest.interval(date(2026, 2, 1), date(2026, 2, 28))
  let assert Ok(universe) =
    manifest.universe(
      "universe-" <> finance_track.name(track),
      "1.0.0",
      track,
      manifest.ExactEnumerated,
      instant(900),
      coverage,
      sha("universe-source"),
      manifest.CallerDeclared,
      ["point-in-time fixture"],
      list.map(listing_ids, fn(id) { membership(track, mic, id) }),
    )
  let assert Ok(dataset) =
    manifest.dataset(
      "dataset-" <> finance_track.name(track),
      "1.0.0",
      "fixture-provider",
      "fixture://daily",
      track,
      coverage,
      list.map(listing_ids, fn(id) { observation(track, mic, id) }),
      ["fixture observations"],
    )
  #(universe, dataset)
}

fn membership(
  track: finance_track.Track,
  mic: String,
  listing_id: String,
) -> manifest.Membership {
  let assert Ok(interval) = manifest.open_interval(date(2020, 1, 1), None)
  manifest.Membership(
    listing_id,
    mic,
    track,
    fact.Known(listing_id),
    fact.Known(interval),
    interval,
    fact.Known("cash_equity"),
    fact.Known(interval),
    date(2020, 1, 1),
    fact.NotApplicable("open"),
    fact.Known(instant(90)),
    fact.Known(instant(100)),
    instant(200),
    sha("membership-" <> listing_id),
    [],
    manifest.MembershipKnown,
  )
}

fn observation(
  track: finance_track.Track,
  mic: String,
  listing_id: String,
) -> manifest.ObservationHandle {
  manifest.ObservationHandle(
    "obs-" <> listing_id,
    listing_id,
    mic,
    track,
    date(2026, 2, 24),
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
    fact.Known(case track {
      finance_track.Cn -> "CNY"
      finance_track.Hk -> "HKD"
      finance_track.Us -> "USD"
    }),
    fact.Known(6),
    fact.Known("venue_local"),
    fact.Known("raw"),
    fact.Known("shares"),
    fact.Known("fixture"),
    fact.Known("rights-safe"),
    fact.Known("reported"),
    sha("obs-" <> listing_id),
    [],
    [],
  )
}

fn sha_text(value: String) -> String {
  value |> sha |> identity.sha256_value
}

fn sha(value: String) -> identity.Sha256 {
  let assert Ok(value) = provenance_hash.text(value)
  value
}

fn instant(value: Int) -> time.Instant {
  let assert Ok(value) = time.instant(value)
  value
}

fn date(year: Int, month: Int, day: Int) -> time.Date {
  let assert Ok(value) = time.date(year, month, day)
  value
}
