import finance_core/identifier
import finance_core/time
import finance_journal/event as journal_event
import finance_journal/information as journal_information
import finance_journal/state as journal_state
import finance_listing/listing
import finance_provenance/hash as provenance_hash
import finance_provenance/identity.{type Sha256}
import finance_replay/event as replay_event
import finance_replay/fact as replay_fact
import finance_replay/fold as replay_fold
import finance_strategy/definition
import finance_strategy/evidence
import finance_strategy/receipt
import finance_strategy/rsi_reversal
import finance_track.{type Track}
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import pi_sparkles_swing_workbench/domain
import pi_sparkles_swing_workbench/render
import pi_sparkles_swing_workbench/state

type Journey {
  Journey(
    track: Track,
    workflow_state: state.State,
    workflow_events: List(String),
    journal: journal_state.State,
    replay: replay_fold.State,
    checkpoint: replay_fold.Checkpoint,
    after_close: domain.CandidateSnapshot,
    preflight: domain.CandidateSnapshot,
    monitoring: domain.CandidateSnapshot,
    plan: domain.PlanRecord,
    review: domain.ReviewRecord,
  )
}

pub fn seeded_cn_hk_us_journeys_preserve_exact_tracks_and_declared_loop_test() {
  let journeys = [
    journey(finance_track.Cn, "600000", "XSHG"),
    journey(finance_track.Hk, "00700", "XHKG"),
    journey(finance_track.Us, "AAPL", "XNAS"),
  ]
  journeys
  |> list.map(fn(value) { value.track })
  |> should.equal([finance_track.Cn, finance_track.Hk, finance_track.Us])
  journeys
  |> list.each(fn(value) {
    state.revision(value.workflow_state) |> should.equal(5)
    value.workflow_state
    |> state.workflows
    |> first_workflow
    |> state.latest_snapshot
    |> domain.track
    |> should.equal(value.track)
    journal_state.event_count(value.journal) |> should.equal(3)
    replay_fold.status(value.replay) |> should.equal(replay_fold.Completed)
  })
}

pub fn every_journey_replays_after_interruption_without_receipt_drift_test() {
  [
    journey(finance_track.Cn, "600000", "XSHG"),
    journey(finance_track.Hk, "00700", "XHKG"),
    journey(finance_track.Us, "AAPL", "XNAS"),
  ]
  |> list.each(fn(value) {
    state.replay(value.workflow_events)
    |> should.equal(Ok(value.workflow_state))
    replay_fold.resume(value.checkpoint, checkpoint_state(value))
    |> should.equal(Ok(checkpoint_state(value)))
    let jsonl =
      value.journal |> journal_state.events |> journal_state.encode_jsonl
    journal_state.decode_jsonl(jsonl, 20, 500_000)
    |> should.equal(Ok(value.journal))
  })
}

pub fn exception_triage_preserves_changed_unknown_conflicting_and_unsupported_facts_test() {
  let cn = journey(finance_track.Cn, "600000", "XSHG")
  let hk = journey(finance_track.Hk, "00700", "XHKG")
  let us = journey(finance_track.Us, "AAPL", "XNAS")
  domain.changes(Some(cn.preflight), cn.monitoring)
  |> list.map(domain.change_kind)
  |> should.equal([
    domain.ChangedFact,
    domain.ChangedFact,
    domain.UnchangedFact,
    domain.AddedFact,
  ])
  cn.monitoring
  |> domain.facts
  |> states
  |> should.equal([
    domain.Known,
    domain.Conflicting,
    domain.Unknown,
    domain.NotObtained,
  ])
  hk.monitoring
  |> domain.facts
  |> states
  |> should.equal([
    domain.Known,
    domain.Conflicting,
    domain.Unsupported,
    domain.NotObtained,
  ])
  us.monitoring
  |> domain.facts
  |> states
  |> should.equal([
    domain.Known,
    domain.Conflicting,
    domain.NotObtained,
    domain.NotObtained,
  ])
}

pub fn task_times_are_exact_mechanical_facts_without_an_sla_judgment_test() {
  let value = journey(finance_track.Cn, "600000", "XSHG")
  let times = [
    value.after_close |> domain.attached_at |> time.unix_milliseconds,
    value.plan |> domain.plan_created_at |> time.unix_milliseconds,
    value.preflight |> domain.attached_at |> time.unix_milliseconds,
    value.monitoring |> domain.attached_at |> time.unix_milliseconds,
    value.review |> domain.observed_at |> time.unix_milliseconds,
  ]
  times |> should.equal([1000, 1100, 1200, 1400, 1600])
  adjacent_durations(times) |> should.equal([100, 100, 200, 200])
}

pub fn acceptance_packets_expose_operations_and_never_a_plugin_verdict_test() {
  let value = journey(finance_track.Hk, "00700", "XHKG")
  let rendered =
    render.snapshot_json(
      value.workflow_state,
      state.workflows(value.workflow_state),
    )
    |> json.to_string
  rendered
  |> string.contains("\"decisionOwner\":\"llm\"")
  |> should.be_true
  [
    "\"accepted\"",
    "\"qualified\"",
    "\"correctness\"",
    "\"sufficiency\"",
    "\"nextAction\"",
    "\"edge\"",
    "\"robust\"",
  ]
  |> list.each(fn(value) {
    rendered |> string.contains(value) |> should.be_false
  })
}

fn journey(track: Track, symbol: String, mic: String) -> Journey {
  let prefix = finance_track.name(track) <> "-" <> symbol
  let workflow_id = "workflow-" <> prefix
  let packet = strategy_packet(track, symbol, mic)
  let strategy_payload = receipt.encode(packet)
  let strategy_hash = sha(strategy_payload)
  let after_close =
    candidate(workflow_id, strategy_hash, strategy_payload, 1000, [
      fact_input(
        "market.completed_daily",
        domain.Required,
        domain.Known,
        "caller-supplied completed daily observation",
        [sha(prefix <> ":market:1")],
      ),
      fact_input(
        "calculation.requested_feature",
        domain.Required,
        domain.Known,
        "caller-requested RSI calculation receipt",
        [sha(prefix <> ":feature:1")],
      ),
      fact_input(
        "risk.requested_projection",
        domain.Required,
        domain.NotObtained,
        "risk calculation not obtained at after-close inspection",
        [],
      ),
    ])
  let assert Ok(#(one, _)) = state.attach_candidate(state.empty(), after_close)
  let event_one =
    state.event_for_candidate(one, after_close) |> state.encode_event

  let plan_payload =
    "llm-declared next-session plan for " <> finance_track.name(track)
  let assert Ok(plan) =
    domain.plan_record(
      workflow_id,
      strategy_hash,
      sha(plan_payload),
      plan_payload,
      domain.LlmAuthored,
      [sha(prefix <> ":risk:1")],
      [sha(prefix <> ":rule:1")],
      [sha(prefix <> ":execution:1")],
      instant(1100),
    )
  let assert Ok(#(two, _)) = state.attach_plan(one, plan)
  let event_two = state.event_for_plan(two, plan) |> state.encode_event

  let preflight =
    candidate(workflow_id, strategy_hash, strategy_payload, 1200, [
      fact_input(
        "market.completed_daily",
        domain.Required,
        domain.Known,
        "same source observation at preflight",
        [sha(prefix <> ":market:1")],
      ),
      fact_input(
        "execution.branch_population",
        domain.Required,
        domain.Unknown,
        "daily bar ordering branches not yet observed",
        [sha(prefix <> ":execution:1")],
      ),
      track_exception(track, prefix),
    ])
  let assert Ok(#(three, _)) = state.attach_candidate(two, preflight)
  let event_three =
    state.event_for_candidate(three, preflight) |> state.encode_event

  let monitoring =
    candidate(workflow_id, strategy_hash, strategy_payload, 1400, [
      fact_input(
        "market.completed_daily",
        domain.Required,
        domain.Known,
        "same source observation during monitoring",
        [sha(prefix <> ":market:1")],
      ),
      fact_input(
        "execution.branch_population",
        domain.Required,
        domain.Conflicting,
        "stop-first and target-first alternatives retained",
        [sha(prefix <> ":branch:stop"), sha(prefix <> ":branch:target")],
      ),
      track_exception(track, prefix),
      fact_input(
        "journal.prior_review",
        domain.Context,
        domain.NotObtained,
        "no prior review supplied for this fixture",
        [],
      ),
    ])
  let assert Ok(#(four, _)) = state.attach_candidate(three, monitoring)
  let event_four =
    state.event_for_candidate(four, monitoring) |> state.encode_event

  let replay_events = replay_events(prefix, plan)
  let replay_definition = sha(prefix <> ":run-definition")
  let replay_initial = replay_fold.empty(prefix <> ":run", replay_definition)
  let assert Ok(#(replay_prefix, _, _)) =
    replay_fold.append_many(replay_initial, list.take(replay_events, 4))
  let assert Ok(checkpoint) =
    replay_fold.checkpoint(
      prefix <> ":checkpoint",
      replay_prefix,
      replay_fact.Known(sha(prefix <> ":position-ledger")),
      replay_fact.Known("seed:fixture/stream:0"),
      instant(1350),
    )
  let assert Ok(resumed) = replay_fold.resume(checkpoint, replay_prefix)
  let assert Ok(#(replay_final, _, _)) =
    replay_fold.append_many(resumed, list.drop(replay_events, 4))
  let assert Ok(#(replay_batch, _, _)) =
    replay_fold.append_many(replay_initial, replay_events)
  replay_fold.semantic_hash(replay_final)
  |> should.equal(replay_fold.semantic_hash(replay_batch))

  let review_payload =
    "llm review retains both execution branches and track-specific exception"
  let assert Ok(review) =
    domain.review_record(
      workflow_id,
      "review-" <> prefix,
      "planned_vs_observed_information",
      sha(review_payload),
      review_payload,
      Some(domain.plan_receipt_hash(plan)),
      [
        replay_fold.semantic_hash(replay_final),
        sha(prefix <> ":journal-plan-event"),
      ],
      instant(1600),
    )
  let assert Ok(#(five, _)) = state.attach_review(four, review)
  let event_five = state.event_for_review(five, review) |> state.encode_event
  let workflow_events = [
    event_one,
    event_two,
    event_three,
    event_four,
    event_five,
  ]

  let journal =
    journal(prefix, workflow_id, symbol, mic, track, plan, review, replay_final)
  Journey(
    track,
    five,
    workflow_events,
    journal,
    replay_final,
    checkpoint,
    after_close,
    preflight,
    monitoring,
    plan,
    review,
  )
}

fn checkpoint_state(value: Journey) -> replay_fold.State {
  let replay_events = value.replay |> replay_fold.events |> list.take(4)
  let initial =
    replay_fold.empty(
      value.replay |> replay_fold.run_id,
      value.replay |> replay_fold.run_definition_hash,
    )
  let assert Ok(#(state, _, _)) =
    replay_fold.append_many(initial, replay_events)
  state
}

fn journal(
  prefix: String,
  workflow_id: String,
  symbol: String,
  mic: String,
  track: Track,
  plan: domain.PlanRecord,
  review: domain.ReviewRecord,
  replay: replay_fold.State,
) -> journal_state.State {
  let identity =
    journal_event.ExactListing(
      track,
      "fixture:" <> prefix,
      mic,
      journal_information.Known(symbol),
    )
  let scope = journal_event.Scope(identity, Some(workflow_id), None, None)
  let after_close =
    journal_entry(
      prefix,
      "after-close",
      scope,
      journal_event.UserDeclared("fixture-user"),
      "after_close",
      "after-close observations inspected",
      1000,
      [
        journal_event.Reference(
          "strategy",
          domain.source_strategy_receipt_hash(plan),
        ),
      ],
    )
  let plan_event =
    journal_entry(
      prefix,
      "plan",
      scope,
      journal_event.LlmDeclared("fixture-llm", None),
      "plan",
      domain.plan_payload(plan),
      1100,
      [journal_event.Reference("plan", domain.plan_receipt_hash(plan))],
    )
  let review_event =
    journal_entry(
      prefix,
      "review",
      scope,
      journal_event.LlmDeclared("fixture-llm", None),
      "review",
      domain.review_payload(review),
      1600,
      [
        journal_event.Reference("plan", domain.plan_receipt_hash(plan)),
        journal_event.Reference(
          "replay_state",
          replay_fold.semantic_hash(replay),
        ),
      ],
    )
  let assert Ok(#(value, _)) =
    journal_state.append_many(journal_state.empty(), [
      after_close,
      plan_event,
      review_event,
    ])
  value
}

fn journal_entry(
  prefix: String,
  suffix: String,
  scope: journal_event.Scope,
  attribution: journal_event.Attribution,
  stage: String,
  payload: String,
  occurred: Int,
  references: List(journal_event.Reference),
) -> journal_event.Event {
  let assert Ok(value) =
    journal_event.new(
      "journal-" <> prefix,
      "journal-event-" <> prefix <> "-" <> suffix,
      journal_event.Declaration,
      scope,
      attribution,
      journal_information.Known(stage),
      payload,
      journal_information.Known(instant(occurred)),
      instant(occurred + 1),
      journal_information.Known("fixture-timezone"),
      journal_event.Private,
      references,
      None,
      journal_information.NotApplicable("not imported"),
      "journal-key-" <> prefix <> "-" <> suffix,
    )
  value
}

fn replay_events(
  prefix: String,
  plan: domain.PlanRecord,
) -> List(replay_event.Event) {
  [
    replay_entry(
      prefix,
      "membership",
      replay_event.UniverseMembershipAvailable,
      1,
      1000,
      [],
    ),
    replay_entry(
      prefix,
      "observation",
      replay_event.MarketObservationAvailable,
      2,
      1010,
      [],
    ),
    replay_entry(
      prefix,
      "feature",
      replay_event.FeatureResultProduced,
      3,
      1020,
      [],
    ),
    replay_entry(
      prefix,
      "instruction",
      replay_event.DesiredInstructionDeclared,
      4,
      1100,
      [replay_event.Reference("plan", domain.plan_receipt_hash(plan))],
    ),
    replay_entry(
      prefix,
      "branch-stop",
      replay_event.ExecutionBranchEmitted,
      5,
      1400,
      [],
    ),
    replay_entry(
      prefix,
      "branch-target",
      replay_event.ExecutionBranchEmitted,
      6,
      1400,
      [],
    ),
    replay_entry(
      prefix,
      "position",
      replay_event.PositionLedgerChanged,
      7,
      1500,
      [],
    ),
    replay_entry(prefix, "complete", replay_event.RunCompleted, 8, 1600, []),
  ]
}

fn replay_entry(
  prefix: String,
  suffix: String,
  kind: replay_event.Kind,
  clock: Int,
  occurred: Int,
  references: List(replay_event.Reference),
) -> replay_event.Event {
  let assert Ok(value) =
    replay_event.new(
      prefix <> ":run",
      prefix <> ":replay:" <> suffix,
      kind,
      replay_fact.Known(instant(occurred)),
      replay_fact.Known(instant(occurred)),
      clock,
      replay_fact.Known(track_from_prefix(prefix)),
      replay_fact.Known(date(2026, 8, 7)),
      "caller-supplied fixture payload:" <> suffix,
      references,
      instant(occurred + 1),
      prefix <> ":replay-key:" <> suffix,
    )
  value
}

fn track_exception(track: Track, prefix: String) -> domain.FactInput {
  case track {
    finance_track.Cn ->
      fact_input(
        "track.exception",
        domain.Required,
        domain.Unknown,
        "reported quantity semantics unavailable",
        [sha(prefix <> ":quantity")],
      )
    finance_track.Hk ->
      fact_input(
        "track.exception",
        domain.Required,
        domain.Unsupported,
        "daily row does not establish half-day intraday completeness",
        [sha(prefix <> ":half-day")],
      )
    finance_track.Us ->
      fact_input(
        "track.exception",
        domain.Required,
        domain.NotObtained,
        "realtime entitlement not obtained",
        [sha(prefix <> ":entitlement")],
      )
  }
}

fn candidate(
  workflow_id: String,
  strategy_hash: Sha256,
  strategy_payload: String,
  attached_at: Int,
  facts: List(domain.FactInput),
) -> domain.CandidateSnapshot {
  let assert Ok(value) =
    domain.candidate_snapshot(
      workflow_id,
      strategy_hash,
      strategy_payload,
      facts,
      instant(attached_at),
    )
  value
}

fn fact_input(
  id: String,
  role: domain.FactRole,
  state: domain.InformationState,
  detail: String,
  references: List(Sha256),
) -> domain.FactInput {
  domain.FactInput(id, role, state, detail, references)
}

fn states(values: List(domain.EvidenceFact)) -> List(domain.InformationState) {
  values |> list.map(domain.information_state)
}

fn strategy_packet(
  track: Track,
  symbol: String,
  mic: String,
) -> receipt.StrategyEvidenceReceipt {
  let assert Ok(definition_value) = rsi_reversal.v1(date(2026, 1, 1), None)
  let requirements =
    list.append(
      definition.setup_requirements(definition_value),
      definition.acceptance_requirements(definition_value),
    )
  let dependencies =
    requirements
    |> list.map(fn(requirement) {
      let assert Ok(value) =
        evidence.dependency_receipt(
          requirement,
          evidence.Declared("fixture declaration; LLM decides"),
          None,
          [],
        )
      value
    })
  let assert Ok(context) =
    evidence.evaluation_context(
      listing(track, symbol, mic),
      date(2026, 8, 7),
      instant(1000),
      instant(900),
      dependencies,
      [],
    )
  receipt.build(definition_value, context, [])
}

fn listing(track: Track, symbol: String, mic: String) -> listing.Key {
  let assert Ok(instrument_id) =
    identifier.instrument_id(
      "fixture:" <> finance_track.name(track) <> ":" <> symbol,
    )
  let assert Ok(symbol_value) = identifier.symbol(symbol)
  let assert Ok(mic_value) = identifier.mic(mic)
  listing.new(track, instrument_id, symbol_value, mic_value)
}

fn first_workflow(values: List(state.Workflow)) -> state.Workflow {
  let assert [value] = values
  value
}

fn adjacent_durations(values: List(Int)) -> List(Int) {
  case values {
    [] | [_] -> []
    [first, second, ..rest] -> [
      second - first,
      ..adjacent_durations([second, ..rest])
    ]
  }
}

fn track_from_prefix(value: String) -> Track {
  case string.starts_with(value, "cn-") {
    True -> finance_track.Cn
    False ->
      case string.starts_with(value, "hk-") {
        True -> finance_track.Hk
        False -> finance_track.Us
      }
  }
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
