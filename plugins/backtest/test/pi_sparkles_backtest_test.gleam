import finance_core/time
import finance_provenance/hash
import finance_provenance/identity
import finance_replay/definition
import finance_replay/event
import finance_replay/fact
import finance_track
import gleam/dynamic/decode as dynamic_decode
import gleam/json
import gleam/list
import gleam/option.{None}
import gleam/string
import gleeunit
import gleeunit/should
import pi_sparkles_backtest/decode
import pi_sparkles_backtest/domain

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn submit_run_executes_exact_script_and_retains_completed_state_test() {
  let input = completed_run()
  let assert Ok(response) = domain.submit_run(input)
  let text = json.to_string(response.details)
  text |> string.contains("\"operation\":\"submit_run\"") |> should.be_true
  text |> string.contains("\"status\":\"completed\"") |> should.be_true
  text |> string.contains("\"consumedEventCount\":3") |> should.be_true
  text |> string.contains("\"retainedEventCount\":3") |> should.be_true
  text |> string.contains("\"idempotentRetryCount\":0") |> should.be_true
  text |> string.contains("\"kind\":\"input_exhausted\"") |> should.be_true
  text
  |> string.contains("input_exhausted_does_not_imply_a_run_completed_event")
  |> should.be_true
}

pub fn exhausted_nonterminal_script_stays_open_test() {
  let value = completed_run()
  let input =
    decode.RunInput(..value, events: [
      replay_input("one", event.MarketObservationAvailable, 1, 0),
    ])
  let assert Ok(response) = domain.submit_run(input)
  let text = json.to_string(response.details)
  text |> string.contains("\"status\":\"open\"") |> should.be_true
  text |> string.contains("\"kind\":\"input_exhausted\"") |> should.be_true
}

pub fn exact_retry_is_counted_without_duplicating_fold_state_test() {
  let first =
    replay_event("one", event.MarketObservationAvailable, 1, "key-one")
  let events = [event_input(first, 1, 0), event_input(first, 1, 0)]
  let input = decode.RunInput(..completed_run(), events: events)
  let assert Ok(response) = domain.submit_run(input)
  let text = json.to_string(response.details)
  text |> string.contains("\"consumedEventCount\":2") |> should.be_true
  text |> string.contains("\"retainedEventCount\":1") |> should.be_true
  text |> string.contains("\"idempotentRetryCount\":1") |> should.be_true
}

pub fn every_budget_and_cancellation_retains_the_exact_prefix_test() {
  let base = completed_run()
  let decode.RunInput(_, _, events, _, _) = base
  let assert [first, second, ..] = events
  let first_bytes = string.byte_size(first.canonical_json)
  let second_bytes = string.byte_size(second.canonical_json)
  let cases = [
    #(
      decode.RunInput(
        ..base,
        budget: decode.BudgetInput(1, 1_000_000, 100, 100),
      ),
      "max_events",
    ),
    #(
      decode.RunInput(
        ..base,
        budget: decode.BudgetInput(
          100,
          first_bytes + second_bytes - 1,
          100,
          100,
        ),
      ),
      "max_bytes",
    ),
    #(
      decode.RunInput(
        ..base,
        budget: decode.BudgetInput(100, 1_000_000, 1, 100),
      ),
      "max_wall_time",
    ),
    #(
      decode.RunInput(
        ..base,
        events: [
          decode.EventInput(..first, session_increment: 1),
          decode.EventInput(..second, session_increment: 1),
        ],
        budget: decode.BudgetInput(100, 1_000_000, 100, 1),
      ),
      "max_sessions",
    ),
  ]
  cases
  |> list.each(fn(pair) {
    let assert Ok(response) = domain.submit_run(pair.0)
    let text = json.to_string(response.details)
    text |> string.contains("\"kind\":\"budget_truncated\"") |> should.be_true
    text |> string.contains("\"reason\":\"" <> pair.1 <> "\"") |> should.be_true
    text |> string.contains("\"consumedEventCount\":1") |> should.be_true
  })

  let cancelled =
    decode.RunInput(
      ..base,
      cancellation: decode.CancelBefore(2, 25, "user-fixture"),
    )
  let assert Ok(cancelled_response) = domain.submit_run(cancelled)
  let cancelled_text = json.to_string(cancelled_response.details)
  cancelled_text |> string.contains("\"kind\":\"cancelled\"") |> should.be_true
  cancelled_text
  |> string.contains("\"cancelledBy\":\"user-fixture\"")
  |> should.be_true
  cancelled_text
  |> string.contains("\"continuationReplayClock\":2")
  |> should.be_true
}

pub fn event_inspection_pages_stably_and_requires_payload_opt_in_test() {
  let run = completed_run()
  let assert Ok(first) =
    domain.inspect_events(decode.InspectInput(run, 0, 1, False))
  let assert Ok(second) =
    domain.inspect_events(decode.InspectInput(run, 1, 1, True))
  let first_text = json.to_string(first.details)
  let second_text = json.to_string(second.details)
  first_text |> string.contains("\"returnedCount\":1") |> should.be_true
  first_text |> string.contains("\"nextOffset\":1") |> should.be_true
  first_text |> string.contains("\"eventEnvelope\":null") |> should.be_true
  second_text
  |> string.contains("\"schema\":\"finance_replay_event\"")
  |> should.be_true
  let assert Ok(first_handle) =
    json.parse(first_text, {
      use value <- dynamic_decode.field("runStateHandle", dynamic_decode.string)
      dynamic_decode.success(value)
    })
  let assert Ok(second_handle) =
    json.parse(second_text, {
      use value <- dynamic_decode.field("runStateHandle", dynamic_decode.string)
      dynamic_decode.success(value)
    })
  first_handle |> should.equal(second_handle)
}

pub fn canonical_hash_identity_and_fold_conflicts_fail_closed_test() {
  let base = completed_run()
  let wrong_definition =
    decode.DefinitionInput(
      base.definition.canonical_json,
      sha_text("wrong-definition"),
    )
  case
    domain.submit_run(decode.RunInput(..base, definition: wrong_definition))
  {
    Error(domain.DefinitionHashMismatch(_, _)) -> Nil
    _ -> should.fail()
  }

  let assert [first, ..] = base.events
  let wrong_event =
    decode.EventInput(..first, content_hash: sha_text("wrong-event"))
  case domain.submit_run(decode.RunInput(..base, events: [wrong_event])) {
    Error(domain.EventHashMismatch(0, _, _)) -> Nil
    _ -> should.fail()
  }

  let other_run =
    replay_event_for_run(
      "other-run",
      "other",
      event.MarketObservationAvailable,
      1,
      "other-key",
    )
  domain.submit_run(
    decode.RunInput(..base, events: [event_input(other_run, 1, 0)]),
  )
  |> should.equal(Error(domain.EventRunMismatch(0, "run-1", "other-run")))

  let first_value =
    replay_event("same", event.MarketObservationAvailable, 1, "key-a")
  let duplicate_id =
    replay_event("same", event.FeatureResultProduced, 2, "key-b")
  case
    domain.submit_run(
      decode.RunInput(..base, events: [
        event_input(first_value, 1, 0),
        event_input(duplicate_id, 1, 0),
      ]),
    )
  {
    Error(domain.ReplayFailure(reason)) ->
      reason |> string.contains("DuplicateEventId") |> should.be_true
    _ -> should.fail()
  }
}

pub fn export_binds_definition_receipts_and_returns_canonical_bundle_test() {
  let run = completed_run()
  let input = decode.ExportInput(run, manifest_input(), 0, 200, 1_000_000)
  let assert Ok(response) = domain.export_manifest(input)
  let text = json.to_string(response.details)
  text |> string.contains("\"bundleComplete\":true") |> should.be_true
  text |> string.contains("\"returnedCount\":3") |> should.be_true
  text |> string.contains(sha_text("partition")) |> should.be_true
  text |> string.contains(sha_text("universe")) |> should.be_true
  text |> string.contains(sha_text("dataset")) |> should.be_true
  text |> string.contains(sha_text("execution")) |> should.be_true
  text
  |> string.contains("finance_replay_reproduction_manifest")
  |> should.be_true
  text |> string.contains("finance_replay_event") |> should.be_true
  text
  |> string.contains(
    "content_coherence_only_not_origin_licence_correctness_or_research_quality",
  )
  |> should.be_true
}

pub fn bounded_export_reports_partial_and_rejects_zero_progress_test() {
  let run = completed_run()
  let assert Ok(partial) =
    domain.export_manifest(decode.ExportInput(
      run,
      manifest_input(),
      0,
      1,
      1_000_000,
    ))
  let text = json.to_string(partial.details)
  text |> string.contains("\"returnedCount\":1") |> should.be_true
  text |> string.contains("\"nextOffset\":1") |> should.be_true
  text |> string.contains("\"bundleComplete\":false") |> should.be_true

  case
    domain.export_manifest(decode.ExportInput(run, manifest_input(), 0, 10, 1))
  {
    Error(domain.ExportEventTooLarge(0, required, 1)) ->
      should.be_true(required > 1)
    _ -> should.fail()
  }
}

pub fn every_result_keeps_the_llm_decision_boundary_test() {
  let assert Ok(response) = domain.submit_run(completed_run())
  let text = json.to_string(response.details)
  text |> string.contains("\"decisionOwner\":\"llm\"") |> should.be_true
  text |> string.contains("\"pluginDecisionFields\":[]") |> should.be_true
  text |> string.contains("\"preferredRun\"") |> should.be_false
  text |> string.contains("\"verdict\"") |> should.be_false
  text |> string.contains("\"significant\"") |> should.be_false
  text |> string.contains("\"deployable\"") |> should.be_false
  text |> string.contains("\"nextAction\"") |> should.be_false
}

fn completed_run() -> decode.RunInput {
  decode.RunInput(
    "caller_declared_completed_daily_cash_equity_v1",
    definition_input(),
    [
      replay_input("one", event.MarketObservationAvailable, 1, 1),
      replay_input("two", event.FeatureResultProduced, 2, 0),
      replay_input("three", event.RunCompleted, 3, 0),
    ],
    decode.BudgetInput(100, 1_000_000, 100, 100),
    decode.Continue,
  )
}

fn definition_input() -> decode.DefinitionInput {
  let assert Ok(value) =
    definition.new(
      "run-1",
      "1.0.0",
      [sha("feature")],
      sha("strategy"),
      [sha("risk")],
      sha("execution"),
      sha("universe"),
      sha("dataset"),
      sha("partition"),
      fact.Known(instant(5)),
      [definition.DeclaredPolicy("missing_data", "preserve_unknown", None)],
      "all_branches",
      fact.Known("seed:42/stream:main"),
      ["completed daily caller fixture"],
    )
  decode.DefinitionInput(
    definition.encode(value),
    value |> definition.digest |> identity.sha256_value,
  )
}

fn replay_input(
  suffix: String,
  kind: event.Kind,
  clock: Int,
  session_increment: Int,
) -> decode.EventInput {
  replay_event(suffix, kind, clock, "key-" <> suffix)
  |> event_input(1, session_increment)
}

fn replay_event(
  suffix: String,
  kind: event.Kind,
  clock: Int,
  key: String,
) -> event.Event {
  replay_event_for_run("run-1", suffix, kind, clock, key)
}

fn replay_event_for_run(
  run_id: String,
  suffix: String,
  kind: event.Kind,
  clock: Int,
  key: String,
) -> event.Event {
  let assert Ok(value) =
    event.new(
      run_id,
      "event-" <> suffix,
      kind,
      fact.Known(instant(clock * 10)),
      fact.Known(instant(clock * 10)),
      clock,
      fact.Known(finance_track.Us),
      fact.Known(date(2026, 1, clock)),
      "{\"fixture\":\"" <> suffix <> "\"}",
      [event.Reference("source", sha("source-" <> suffix))],
      instant(100 + clock),
      key,
    )
  value
}

fn event_input(
  value: event.Event,
  elapsed: Int,
  session_increment: Int,
) -> decode.EventInput {
  decode.EventInput(
    event.encode(value),
    value |> event.canonical_content_hash |> identity.sha256_value,
    elapsed,
    session_increment,
  )
}

fn manifest_input() -> decode.ManifestInput {
  decode.ManifestInput(
    "manifest-fixture",
    [decode.EnvironmentInput("finance_replay", "0.1.0", True)],
    ["trial-1"],
    [sha_text("source")],
    [sha_text("transform")],
    [sha_text("calendar")],
    [sha_text("rule")],
    [sha_text("action")],
    [sha_text("cost")],
    ["seed:42/stream:main"],
    ["caller effect fact"],
    [sha_text("output")],
    [sha_text("checkpoint")],
    ["fixture is not redistributable"],
    [
      decode.DependencyInput(
        fact.Known(sha_text("omitted")),
        "proprietary source omitted",
      ),
    ],
    [decode.DependencyInput(fact.Unknown("not obtained"), "not obtained")],
    [],
    "local scripted export",
    "exclude private notes",
  )
}

fn sha_text(value: String) -> String {
  value |> sha |> identity.sha256_value
}

fn sha(value: String) -> identity.Sha256 {
  let assert Ok(value) = hash.text(value)
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
