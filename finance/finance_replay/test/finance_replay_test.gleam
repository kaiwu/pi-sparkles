import finance_core/decimal
import finance_core/time
import finance_provenance/hash as provenance_hash
import finance_provenance/identity.{type Sha256}
import finance_replay
import finance_replay/comparison
import finance_replay/context
import finance_replay/definition
import finance_replay/event
import finance_replay/fact
import finance_replay/fold
import finance_replay/manifest
import finance_replay/metric
import finance_replay/partition
import finance_replay/reproduction
import finance_replay/scripted
import finance_replay/trial
import finance_track
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn package_is_experimental_test() {
  finance_replay.status() |> should.equal(finance_replay.Experimental)
}

pub fn universe_and_dataset_manifests_round_trip_without_track_substitution_test() {
  let universe = universe_manifest()
  let dataset = dataset_manifest()
  manifest.decode_universe(manifest.encode_universe(universe))
  |> should.equal(Ok(universe))
  manifest.decode_dataset(manifest.encode_dataset(dataset))
  |> should.equal(Ok(dataset))
  manifest.universe_track(universe) |> should.equal(finance_track.Cn)
  manifest.dataset_track(dataset) |> should.equal(finance_track.Cn)
  manifest.dataset_manifest_id(dataset) |> should.equal("dataset-cn")
  manifest.dataset_version(dataset) |> should.equal("1")
  manifest.dataset_provider(dataset) |> should.equal("scripted")
  manifest.dataset_source(dataset) |> should.equal("fixture")
  manifest.dataset_coverage(dataset)
  |> should.equal(manifest.Interval(date(2026, 1, 1), date(2026, 6, 30)))
  manifest.dataset_limitations(dataset)
  |> should.equal(["completed daily observations"])
}

pub fn partition_round_trip_and_reports_gap_mechanically_test() {
  let first = window("train", date(2026, 1, 1), date(2026, 1, 10))
  let second = window("test", date(2026, 1, 13), date(2026, 1, 20))
  let assert Ok(value) =
    partition.new("partition-1", "1", partition.Fixed, partition.Calendar, [
      first,
      second,
    ])
  partition.decode(partition.encode(value)) |> should.equal(Ok(value))
  partition.relations(value)
  |> should.equal([
    partition.OrderedBefore("train", "test"),
    partition.Gap("train", "test", date(2026, 1, 11), date(2026, 1, 12), 2),
  ])
}

pub fn run_definition_round_trip_binds_all_shared_receipt_families_test() {
  let value = run_definition("definition-1", "all_branches")
  definition.decode(definition.encode(value)) |> should.equal(Ok(value))
  definition.feature_receipts(value) |> should.equal([sha("feature")])
  definition.risk_receipts(value) |> should.equal([sha("risk")])
  definition.execution_branch_policy(value) |> should.equal("all_branches")
  definition.encode(value)
  |> string.contains("\"plugin_decision_fields\":[]")
  |> should.be_true
}

pub fn replay_event_round_trips_exact_payload_and_ordering_facts_test() {
  let value = replay_event("event-1", event.MarketObservationAvailable, 1, 10)
  event.decode(event.encode(value)) |> should.equal(Ok(value))
  event.encode(value) |> string.contains("source-row-1") |> should.be_true
}

pub fn event_retry_is_idempotent_by_semantic_payload_test() {
  let first = replay_event_with_key("event-1", "same-key", 1, 10, "same")
  let retry = replay_event_with_key("event-retry", "same-key", 1, 10, "same")
  let assert Ok(#(one, fold.Stored(_), _)) =
    fold.append(fold.empty("run-1", sha("definition")), first)
  let assert Ok(#(same, fold.AlreadyStored(stored), effects)) =
    fold.append(one, retry)
  fold.revision(same) |> should.equal(1)
  event.event_id(stored) |> should.equal("event-1")
  effects |> should.equal([])
}

pub fn event_retry_conflict_preserves_both_hashes_test() {
  let first = replay_event_with_key("event-1", "same-key", 1, 10, "first")
  let conflict = replay_event_with_key("event-2", "same-key", 1, 10, "second")
  let assert Ok(#(one, _, _)) =
    fold.append(fold.empty("run-1", sha("definition")), first)
  case fold.append(one, conflict) {
    Error(fold.IdempotencyConflict("same-key", "event-1", left, right)) ->
      left |> should.not_equal(right)
    _ -> should.fail()
  }
}

pub fn batch_and_incremental_fold_have_identical_semantic_hashes_test() {
  let events = [
    replay_event("event-1", event.MarketObservationAvailable, 1, 10),
    replay_event("event-2", event.FeatureResultProduced, 2, 20),
    replay_event("event-3", event.RunCompleted, 3, 30),
  ]
  let assert [first, second, third] = events
  let initial = fold.empty("run-1", sha("definition"))
  let assert Ok(#(batch, _, _)) = fold.append_many(initial, events)
  let assert Ok(#(one, _, _)) = fold.append(initial, first)
  let assert Ok(#(two, _, _)) = fold.append(one, second)
  let assert Ok(#(incremental, _, _)) = fold.append(two, third)
  fold.semantic_hash(batch) |> should.equal(fold.semantic_hash(incremental))
  fold.status(batch) |> should.equal(fold.Completed)
}

pub fn unknown_required_times_are_reported_as_ambiguous_without_reordering_test() {
  let first = replay_event_unknown_time("event-1", 1)
  let second = replay_event_unknown_time("event-2", 2)
  let assert Ok(#(state, _, _)) =
    fold.append_many(fold.empty("run-1", sha("definition")), [first, second])
  case fold.ordering_facts(state) {
    [fold.AmbiguousOrdering("event-1", "event-2", _, alternatives)] ->
      list.length(alternatives) |> should.equal(2)
    _ -> should.fail()
  }
  fold.events(state) |> should.equal([first, second])
}

pub fn known_time_moving_backward_is_a_structural_fold_error_test() {
  let first = replay_event("event-1", event.MarketObservationAvailable, 1, 20)
  let second = replay_event("event-2", event.FeatureResultProduced, 2, 10)
  let assert Ok(#(one, _, _)) =
    fold.append(fold.empty("run-1", sha("definition")), first)
  fold.append(one, second)
  |> should.equal(Error(fold.KnownTimeMovedBackward("event-1", "event-2")))
}

pub fn checkpoint_resume_requires_exact_definition_and_state_test() {
  let definition_hash = sha("definition")
  let value = replay_event("event-1", event.MarketObservationAvailable, 1, 10)
  let assert Ok(#(state, _, _)) =
    fold.append(fold.empty("run-1", definition_hash), value)
  let assert Ok(checkpoint) =
    fold.checkpoint(
      "checkpoint-1",
      state,
      fact.Known(sha("ledger")),
      fact.Known("seed:42/stream:10"),
      instant(20),
    )
  fold.resume(checkpoint, state) |> should.equal(Ok(state))
  case fold.resume(checkpoint, fold.empty("run-1", sha("other-definition"))) {
    Error(fold.CheckpointDefinitionMismatch(_, _)) -> Nil
    _ -> should.fail()
  }
}

pub fn trial_ledger_retains_every_status_and_counts_them_test() {
  let statuses = [
    trial.Completed,
    trial.Failed("division by zero"),
    trial.Cancelled(instant(30), "user"),
    trial.Truncated("max_events"),
    trial.DuplicateOf("trial-0"),
    trial.Unperformed("operand unknown"),
  ]
  let events =
    statuses
    |> list.index_map(fn(status, index) {
      trial_event(
        "ledger-" <> int_text(index),
        "key-" <> int_text(index),
        status,
      )
    })
  let assert Ok(#(ledger, _)) = trial.append_many(trial.empty(), events)
  trial.counts(ledger) |> should.equal(trial.Counts(6, 1, 1, 1, 1, 1, 1))
  trial.events(ledger) |> list.length |> should.equal(6)
}

pub fn trial_ledger_retry_returns_original_and_conflict_is_visible_test() {
  let first = trial_event("ledger-1", "same-key", trial.Completed)
  let retry = trial_event("ledger-retry", "same-key", trial.Completed)
  let conflict = trial_event("ledger-conflict", "same-key", trial.Failed("x"))
  let assert Ok(#(one, trial.Stored(_))) = trial.append(trial.empty(), first)
  let assert Ok(#(same, trial.AlreadyStored(stored))) = trial.append(one, retry)
  trial.event_id(stored) |> should.equal("ledger-1")
  trial.revision(same) |> should.equal(1)
  case trial.append(same, conflict) {
    Error(trial.IdempotencyConflict("same-key", "ledger-1", left, right)) ->
      left |> should.not_equal(right)
    _ -> should.fail()
  }
}

pub fn net_return_uses_only_caller_supplied_formula_metadata_and_operands_test() {
  let assert Ok(value) =
    metric.net_return(
      metric_metadata("net-return", "(ending-denominator)/denominator", 4),
      fact.Known(metric.DecimalInput("denominator", "100.00", sha("start"))),
      fact.Known(metric.DecimalInput("ending", "110.00", sha("end"))),
    )
  metric.value(value) |> should.equal(metric.ExactDecimal("0.1"))
  metric.as_json(value)
  |> json.to_string
  |> string.contains("\"decision_owner\":\"llm\"")
  |> should.be_true
}

pub fn net_return_unknown_operand_is_unperformed_not_a_run_verdict_test() {
  let assert Ok(value) =
    metric.net_return(
      metric_metadata("net-return", "(ending-denominator)/denominator", 4),
      fact.Known(metric.DecimalInput("denominator", "100", sha("start"))),
      fact.Unknown("ending value unavailable"),
    )
  case metric.value(value) {
    metric.Unperformed(_, ["denominator", "ending_value"]) -> Nil
    _ -> should.fail()
  }
}

pub fn win_loss_tie_counts_preserve_zero_as_caller_named_policy_test() {
  let assert Ok(value) =
    metric.win_loss_counts(
      metric_metadata("counts", "sign(net_pnl)", 2),
      [
        metric.TradePnl("a", "1.00", sha("a")),
        metric.TradePnl("b", "-0.10", sha("b")),
        metric.TradePnl("c", "0", sha("c")),
      ],
      "zero_is_tie",
    )
  metric.value(value) |> should.equal(metric.Counts(1, 1, 1))
}

pub fn drawdown_series_retains_equity_peak_and_source_receipts_test() {
  let assert Ok(value) =
    metric.drawdown_series(
      metric_metadata("drawdown", "(running_peak-equity)/running_peak", 4),
      [
        #("d1", metric.DecimalInput("d1", "100", sha("d1"))),
        #("d2", metric.DecimalInput("d2", "80", sha("d2"))),
        #("d3", metric.DecimalInput("d3", "120", sha("d3"))),
      ],
      "inclusive_running_peak",
    )
  case metric.value(value) {
    metric.DrawdownSeries([
      metric.DrawdownPoint(_, _, _, "0", _),
      metric.DrawdownPoint(_, _, "100", "0.2", _),
      metric.DrawdownPoint(_, _, "120", "0", _),
    ]) -> Nil
    _ -> should.fail()
  }
}

pub fn run_comparison_exposes_definition_and_output_differences_only_test() {
  let left = run_definition("left", "all_branches")
  let right = run_definition("right", "first_branch_declared_by_llm")
  let value =
    comparison.runs(
      left,
      right,
      [comparison.OutputField("net_return", "0.10", sha("left-output"))],
      [comparison.OutputField("net_return", "0.08", sha("right-output"))],
    )
  comparison.input_differences(value)
  |> list.length
  |> fn(value) { value > 0 }
  |> should.be_true
  comparison.output_differences(value)
  |> should.equal([comparison.Difference("net_return", "0.10", "0.08")])
  comparison.as_json(value)
  |> json.to_string
  |> string.contains("llm_owned")
  |> should.be_true
}

pub fn reproduction_manifest_and_event_jsonl_round_trip_exactly_test() {
  let manifest = reproduction_manifest("manifest-1")
  reproduction.decode(reproduction.encode(manifest))
  |> should.equal(Ok(manifest))
  let events = [
    replay_event("event-1", event.MarketObservationAvailable, 1, 10),
    replay_event("event-2", event.RunCompleted, 2, 20),
  ]
  let jsonl = reproduction.encode_events_jsonl(events)
  reproduction.decode_events_jsonl(jsonl, 10, 100_000)
  |> should.equal(Ok(events))
}

pub fn reproduction_comparison_reports_exact_and_different_without_quality_label_test() {
  let first = reproduction_manifest("manifest-1")
  let same = reproduction_manifest("manifest-1")
  let different = reproduction_manifest("manifest-2")
  reproduction.compare(first, same) |> should.equal(reproduction.ExactMatch)
  case reproduction.compare(first, different) {
    reproduction.Different(receipts) -> {
      let nonempty = receipts != []
      nonempty |> should.be_true
    }
    _ -> should.fail()
  }
}

pub fn scripted_replay_stops_before_crossing_explicit_event_budget_test() {
  let script = [
    scripted.ScriptItem(
      replay_event("event-1", event.MarketObservationAvailable, 1, 10),
      100,
      1,
      1,
    ),
    scripted.ScriptItem(
      replay_event("event-2", event.FeatureResultProduced, 2, 20),
      100,
      1,
      0,
    ),
  ]
  let assert Ok(value) =
    scripted.run(
      "run-1",
      sha("definition"),
      script,
      scripted.Budget(1, 1000, 1000, 10),
      scripted.Continue,
    )
  scripted.processed_events(value) |> should.equal(1)
  scripted.omitted_events(value) |> should.equal(1)
  scripted.stop(value)
  |> should.equal(scripted.BudgetTruncated("max_events", 2))
}

pub fn scripted_replay_respects_caller_cancellation_point_test() {
  let script = [
    scripted.ScriptItem(
      replay_event("event-1", event.MarketObservationAvailable, 1, 10),
      100,
      1,
      1,
    ),
    scripted.ScriptItem(
      replay_event("event-2", event.FeatureResultProduced, 2, 20),
      100,
      1,
      0,
    ),
  ]
  let assert Ok(value) =
    scripted.run(
      "run-1",
      sha("definition"),
      script,
      scripted.Budget(10, 1000, 1000, 10),
      scripted.CancelBefore(2, instant(15), "user"),
    )
  scripted.processed_events(value) |> should.equal(1)
  scripted.stop(value)
  |> should.equal(scripted.Cancelled(instant(15), "user", 2))
}

pub fn compact_context_has_drill_operations_and_no_decision_fields_test() {
  let value =
    context.Context(
      sha("hypothesis"),
      sha("definition"),
      finance_track.Cn,
      sha("universe"),
      sha("dataset"),
      sha("partition"),
      sha("state"),
      context.EventCounts(10, 4, 1, 2, 1, 1, 1, 0),
      trial.Counts(2, 1, 1, 0, 0, 0, 0),
      [#("availability_time", 2)],
      [],
      [#("event_order", 1)],
      sha("trial-cursor"),
      sha("manifest"),
      context.OmittedCounts(10, 2, 1),
    )
  let encoded = value |> context.as_json |> json.to_string
  encoded |> string.contains("inspect_replay_events") |> should.be_true
  encoded |> string.contains("\"plugin_decision_fields\":[]") |> should.be_true
  encoded |> string.contains("private_payloads\":1") |> should.be_true
}

fn universe_manifest() -> manifest.UniverseManifest {
  let assert Ok(coverage) =
    manifest.interval(date(2026, 1, 1), date(2026, 6, 30))
  let assert Ok(value) =
    manifest.universe(
      "universe-cn",
      "1",
      finance_track.Cn,
      manifest.ExactEnumerated,
      instant(100),
      coverage,
      sha("universe-source"),
      manifest.CallerDeclared,
      ["ten explicitly selected listings in the production fixture"],
      [known_membership()],
    )
  value
}

fn known_membership() -> manifest.Membership {
  let assert Ok(interval) = manifest.open_interval(date(2020, 1, 1), None)
  manifest.Membership(
    "listing-cn-1",
    "XSHG",
    finance_track.Cn,
    fact.Known("600000"),
    fact.Known(interval),
    interval,
    fact.Known("common_stock"),
    fact.Known(interval),
    date(2020, 1, 1),
    fact.NotApplicable("open membership"),
    fact.Known(instant(80)),
    fact.Known(instant(90)),
    instant(100),
    sha("membership-source"),
    [],
    manifest.MembershipKnown,
  )
}

fn dataset_manifest() -> manifest.DatasetManifest {
  let assert Ok(coverage) =
    manifest.interval(date(2026, 1, 1), date(2026, 6, 30))
  let assert Ok(value) =
    manifest.dataset(
      "dataset-cn",
      "1",
      "scripted",
      "fixture",
      finance_track.Cn,
      coverage,
      [],
      ["completed daily observations"],
    )
  value
}

fn window(label: String, start: time.Date, end: time.Date) -> partition.Window {
  partition.Window(
    label,
    "caller_declared",
    start,
    end,
    instant(100),
    None,
    fact.Known("0 calendar days"),
    manifest.universe_digest(universe_manifest()),
    manifest.dataset_digest(dataset_manifest()),
    [],
    [],
    fact.Known("after close"),
  )
}

fn run_definition(
  id: String,
  branch_policy: String,
) -> definition.RunDefinition {
  let assert Ok(value) =
    definition.new(
      id,
      "1.0.0",
      [sha("feature")],
      sha("strategy"),
      [sha("risk")],
      sha("execution"),
      manifest.universe_digest(universe_manifest()),
      manifest.dataset_digest(dataset_manifest()),
      partition.digest(partition_value()),
      fact.Known(instant(100)),
      [definition.DeclaredPolicy("missing_data", "preserve_unknown", None)],
      branch_policy,
      fact.Known("seed:42/stream:main"),
      ["completed daily long-only cash equities"],
    )
  value
}

fn partition_value() -> partition.Partition {
  let assert Ok(value) =
    partition.new("partition-1", "1", partition.Fixed, partition.Calendar, [
      window("test", date(2026, 1, 1), date(2026, 6, 30)),
    ])
  value
}

fn replay_event(
  id: String,
  kind: event.Kind,
  clock: Int,
  milliseconds: Int,
) -> event.Event {
  replay_event_with_key(id, "key-" <> id, clock, milliseconds, "source-row-1")
  |> event_with_kind(kind)
}

fn event_with_kind(value: event.Event, kind: event.Kind) -> event.Event {
  let assert Ok(rebuilt) =
    event.new(
      event.run_id(value),
      event.event_id(value),
      kind,
      event.event_time(value),
      event.availability_time(value),
      event.replay_clock(value),
      fact.Known(finance_track.Cn),
      fact.Known(date(2026, 1, 2)),
      "source-row-1",
      [event.Reference("source", sha("source-row-1"))],
      instant(100),
      event.idempotency_key(value),
    )
  rebuilt
}

fn replay_event_with_key(
  id: String,
  key: String,
  clock: Int,
  milliseconds: Int,
  payload: String,
) -> event.Event {
  let assert Ok(value) =
    event.new(
      "run-1",
      id,
      event.MarketObservationAvailable,
      fact.Known(instant(milliseconds)),
      fact.Known(instant(milliseconds)),
      clock,
      fact.Known(finance_track.Cn),
      fact.Known(date(2026, 1, 2)),
      payload,
      [event.Reference("source", sha("source-row-1"))],
      instant(100),
      key,
    )
  value
}

fn replay_event_unknown_time(id: String, clock: Int) -> event.Event {
  let assert Ok(value) =
    event.new(
      "run-1",
      id,
      event.MarketObservationAvailable,
      fact.Unknown("event time unavailable"),
      fact.Unknown("availability time unavailable"),
      clock,
      fact.Known(finance_track.Cn),
      fact.Known(date(2026, 1, 2)),
      "source-row-1",
      [],
      instant(100),
      "key-" <> id,
    )
  value
}

fn trial_definition() -> trial.Definition {
  let assert Ok(value) =
    trial.definition(
      "trial-1",
      None,
      Some("batch-1"),
      sha("definition"),
      [
        trial.ParameterValue(
          "period",
          "14",
          trial.Llm,
          fact.Known(sha("parameter")),
        ),
      ],
      fact.Known("caller-requested parameter point"),
      sha("partition"),
      [],
      fact.Known("42"),
      [sha("metric")],
      [sha("budget")],
      trial.Llm,
      instant(10),
      trial.ResearchContext,
    )
  value
}

fn trial_event(
  id: String,
  key: String,
  status: trial.Status,
) -> trial.LedgerEvent {
  let assert Ok(value) =
    trial.ledger_event(
      id,
      trial_definition(),
      status,
      instant(20),
      fact.Known(instant(30)),
      [sha("output")],
      [],
      sha("effect"),
      key,
    )
  value
}

fn metric_metadata(id: String, formula: String, scale: Int) -> metric.Metadata {
  metric.Metadata(
    id,
    formula,
    "1",
    "dimensionless",
    scale,
    decimal.HalfEven,
    "preserve_unknown",
    "caller-selected events",
    "replay event order",
    fact.NotApplicable("no benchmark requested"),
    [sha("source")],
  )
}

fn reproduction_manifest(id: String) -> reproduction.Manifest {
  let assert Ok(value) =
    reproduction.new(
      id,
      [
        reproduction.EnvironmentVersion("finance_replay", "0.1.0", True),
        reproduction.EnvironmentVersion("machine", "fixture-a", False),
      ],
      sha("definition"),
      ["trial-1"],
      sha("partition"),
      sha("universe"),
      sha("dataset"),
      [sha("source")],
      [sha("transformation")],
      [sha("calendar")],
      [sha("rule")],
      [sha("corporate-action")],
      sha("execution"),
      [sha("cost")],
      ["seed:42/stream:main"],
      ["no cancellation"],
      [sha("output")],
      [sha("checkpoint")],
      ["fixture is not redistributable"],
      [
        reproduction.Dependency(
          fact.Known(sha("proprietary")),
          "proprietary — not redistributable",
        ),
      ],
      [reproduction.Dependency(fact.Unknown("not obtained"), "not obtained")],
      [],
      "local scripted export",
      "exclude private notes",
    )
  value
}

fn sha(value: String) -> Sha256 {
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

fn int_text(value: Int) -> String {
  case value {
    0 -> "0"
    1 -> "1"
    2 -> "2"
    3 -> "3"
    4 -> "4"
    5 -> "5"
    _ -> "n"
  }
}
