import finance_core/identifier
import finance_core/time
import finance_listing/listing
import finance_provenance/hash as provenance_hash
import finance_provenance/identity
import finance_strategy/definition
import finance_strategy/evidence
import finance_strategy/receipt
import finance_strategy/rsi_reversal
import finance_track
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleeunit
import gleeunit/should
import pi_sparkles_swing_workbench/domain
import pi_sparkles_swing_workbench/portable
import pi_sparkles_swing_workbench/render
import pi_sparkles_swing_workbench/state

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn fixture_strategy_payload() -> String {
  strategy_packet(finance_track.Us, "AAPL", "XNAS") |> receipt.encode
}

pub fn candidate_binds_exact_strategy_receipt_and_identity_test() {
  let packet = strategy_packet(finance_track.Us, "AAPL", "XNAS")
  let payload = receipt.encode(packet)
  let value =
    candidate("wf-aapl", payload, [
      fact_input("risk", domain.Required, domain.Unknown, "not supplied", []),
    ])
  domain.listing_key(value)
  |> should.equal("us|XNAS|AAPL|fixture:us:AAPL")
  domain.definition_id(value) |> should.equal(rsi_reversal.strategy_id)
  domain.strategy_receipt_payload(value) |> should.equal(payload)
  domain.information_state(value |> domain.facts |> first_fact)
  |> should.equal(domain.Unknown)
}

pub fn candidate_rejects_wrong_hash_and_invalid_strategy_json_test() {
  let payload =
    receipt.encode(strategy_packet(finance_track.Us, "AAPL", "XNAS"))
  domain.candidate_snapshot("wf-aapl", hash("wrong"), payload, [], instant(300))
  |> should.equal(Error(domain.StrategyReceiptHashMismatch))
  domain.candidate_snapshot("wf-aapl", hash("{}"), "{}", [], instant(300))
  |> should.equal(Error(domain.InvalidStrategyReceipt))
}

pub fn candidate_fact_states_are_not_collapsed_or_selected_test() {
  let payload =
    receipt.encode(strategy_packet(finance_track.Us, "AAPL", "XNAS"))
  let value =
    candidate("wf-aapl", payload, [
      fact_input(
        "predicate.false",
        domain.Required,
        domain.Known,
        "observed_false",
        [hash("p")],
      ),
      fact_input(
        "execution",
        domain.Required,
        domain.Unsupported,
        "desired stop mapping absent",
        [hash("e")],
      ),
      fact_input(
        "adjustment",
        domain.Required,
        domain.Conflicting,
        "two source branches",
        [hash("a"), hash("b")],
      ),
    ])
  value
  |> domain.facts
  |> list.map(domain.information_state)
  |> should.equal([domain.Known, domain.Unsupported, domain.Conflicting])

  domain.candidate_snapshot(
    "wf-aapl",
    hash(payload),
    payload,
    [
      fact_input("same", domain.Required, domain.Known, "one", []),
      fact_input("same", domain.Optional, domain.Unknown, "two", []),
    ],
    instant(300),
  )
  |> should.equal(Error(domain.DuplicateFactId("same")))
}

pub fn candidate_changes_report_added_changed_unchanged_and_removed_test() {
  let payload =
    receipt.encode(strategy_packet(finance_track.Us, "AAPL", "XNAS"))
  let first =
    candidate("wf-aapl", payload, [
      fact_input("same", domain.Required, domain.Known, "same", [hash("a")]),
      fact_input("changed", domain.Required, domain.Unknown, "old", []),
      fact_input("removed", domain.Optional, domain.Known, "old", [hash("r")]),
    ])
  let second =
    candidate("wf-aapl", payload, [
      fact_input("same", domain.Required, domain.Known, "same", [hash("a")]),
      fact_input("changed", domain.Required, domain.Known, "new", [hash("c")]),
      fact_input("added", domain.Context, domain.Declared, "caller label", []),
    ])
  domain.changes(Some(first), second)
  |> list.map(domain.change_kind)
  |> should.equal([
    domain.UnchangedFact,
    domain.ChangedFact,
    domain.AddedFact,
    domain.RemovedFact,
  ])
}

pub fn candidate_snapshots_are_branch_revisioned_and_track_isolated_test() {
  let us =
    candidate(
      "wf-aapl",
      receipt.encode(strategy_packet(finance_track.Us, "AAPL", "XNAS")),
      [],
    )
  let hk =
    candidate(
      "wf-0700",
      receipt.encode(strategy_packet(finance_track.Hk, "00700", "XHKG")),
      [],
    )
  let assert Ok(#(one, state.CandidateStored(_, _))) =
    state.attach_candidate(state.empty(), us)
  let assert Ok(#(two, state.CandidateStored(_, _))) =
    state.attach_candidate(one, hk)
  state.revision(two) |> should.equal(2)
  state.workflows(two) |> list.length |> should.equal(2)
  two
  |> state.workflows
  |> list.map(fn(workflow) { workflow |> state.latest_snapshot |> domain.track })
  |> should.equal([finance_track.Us, finance_track.Hk])
}

pub fn workflow_id_cannot_be_relabelled_to_another_listing_test() {
  let first =
    candidate(
      "wf-one",
      receipt.encode(strategy_packet(finance_track.Us, "AAPL", "XNAS")),
      [],
    )
  let relabelled =
    candidate(
      "wf-one",
      receipt.encode(strategy_packet(finance_track.Us, "MSFT", "XNAS")),
      [],
    )
  let assert Ok(#(one, _)) = state.attach_candidate(state.empty(), first)
  state.attach_candidate(one, relabelled)
  |> should.equal(Error(state.WorkflowIdentityMismatch("wf-one")))
}

pub fn plan_is_immutable_content_bound_data_not_an_order_test() {
  let snapshot =
    candidate(
      "wf-aapl",
      receipt.encode(strategy_packet(finance_track.Us, "AAPL", "XNAS")),
      [],
    )
  let assert Ok(#(one, _)) = state.attach_candidate(state.empty(), snapshot)
  let plan =
    plan_record("wf-aapl", domain.strategy_receipt_hash(snapshot), "plan-one")
  let assert Ok(#(two, state.PlanStored(_))) = state.attach_plan(one, plan)
  let assert Ok(#(same, state.PlanUnchanged(_))) = state.attach_plan(two, plan)
  state.revision(same) |> should.equal(2)

  let replacement =
    plan_record("wf-aapl", domain.strategy_receipt_hash(snapshot), "plan-two")
  state.attach_plan(two, replacement)
  |> should.equal(Error(state.PlanAlreadyAttached))

  domain.plan_record(
    "wf-aapl",
    domain.strategy_receipt_hash(snapshot),
    hash("wrong"),
    "plan-one",
    domain.LlmAuthored,
    [],
    [],
    [],
    instant(310),
  )
  |> should.equal(Error(domain.PayloadHashMismatch))
}

pub fn review_records_preserve_caller_vocabulary_and_exact_plan_reference_test() {
  let snapshot =
    candidate(
      "wf-aapl",
      receipt.encode(strategy_packet(finance_track.Us, "AAPL", "XNAS")),
      [],
    )
  let assert Ok(#(one, _)) = state.attach_candidate(state.empty(), snapshot)
  let plan =
    plan_record("wf-aapl", domain.strategy_receipt_hash(snapshot), "plan")
  let assert Ok(#(two, _)) = state.attach_plan(one, plan)
  let review =
    review_record(
      "wf-aapl",
      "R1",
      "daily_stop_target_ordering_unknown",
      "both levels touched",
      Some(domain.plan_receipt_hash(plan)),
    )
  let assert Ok(#(three, state.ReviewStored(stored))) =
    state.attach_review(two, review)
  domain.record_kind(stored)
  |> should.equal("daily_stop_target_ordering_unknown")
  state.revision(three) |> should.equal(3)

  let wrong =
    review_record(
      "wf-aapl",
      "R2",
      "observed_exit",
      "external fact",
      Some(hash("other-plan")),
    )
  state.attach_review(three, wrong)
  |> should.equal(Error(state.PlanReferenceMismatch))
}

pub fn durable_journal_references_are_exact_idempotent_and_replayable_test() {
  let snapshot =
    candidate(
      "wf-aapl",
      receipt.encode(strategy_packet(finance_track.Us, "AAPL", "XNAS")),
      [],
    )
  let assert Ok(#(one, _)) = state.attach_candidate(state.empty(), snapshot)
  let reference = journal_reference("journal-aapl", "event-review", "review")
  let assert Ok(#(two, state.JournalReferenceStored(stored))) =
    state.attach_journal_reference(one, reference)
  domain.journal_event_id(stored) |> should.equal("event-review")
  domain.journal_event_content_hash(stored)
  |> should.equal(hash("journal-event"))
  let assert Ok(#(same, state.JournalReferenceUnchanged(_))) =
    state.attach_journal_reference(two, reference)
  state.revision(same) |> should.equal(2)

  let conflict =
    domain.journal_event_reference(
      "wf-aapl",
      "journal-aapl",
      "event-review",
      hash("changed-event"),
      "review",
      instant(330),
    )
  let assert Ok(conflict) = conflict
  state.attach_journal_reference(two, conflict)
  |> should.equal(
    Error(state.JournalReferenceConflict(
      "journal-aapl",
      "event-review",
      "review",
    )),
  )

  let candidate_event =
    state.event_for_candidate(one, snapshot) |> state.encode_event
  let reference_event =
    state.event_for_journal_reference(two, reference) |> state.encode_event
  state.replay([candidate_event, reference_event]) |> should.equal(Ok(two))
  let assert [workflow] = state.workflows(two)
  render.workflow_json(workflow)
  |> json.to_string
  |> string.contains("\"journalEventReferences\"")
  |> should.be_true
}

pub fn event_log_replays_exactly_and_rejects_revision_gaps_test() {
  let snapshot =
    candidate(
      "wf-aapl",
      receipt.encode(strategy_packet(finance_track.Us, "AAPL", "XNAS")),
      [fact_input("risk", domain.Required, domain.Unknown, "absent", [])],
    )
  let assert Ok(#(one, _)) = state.attach_candidate(state.empty(), snapshot)
  let first = state.event_for_candidate(one, snapshot) |> state.encode_event
  let plan =
    plan_record("wf-aapl", domain.strategy_receipt_hash(snapshot), "plan")
  let assert Ok(#(two, _)) = state.attach_plan(one, plan)
  let second = state.event_for_plan(two, plan) |> state.encode_event
  state.replay([first, second]) |> should.equal(Ok(two))
  state.replay(["not-json"]) |> should.equal(Error(state.InvalidEventJson))

  let skipped = state.PlanEvent(3, plan) |> state.encode_event
  state.replay([first, skipped])
  |> should.equal(Error(state.NonContiguousRevision(2, 3)))
}

pub fn snapshot_is_deterministic_and_contains_no_plugin_decision_fields_test() {
  let snapshot =
    candidate(
      "wf-aapl",
      receipt.encode(strategy_packet(finance_track.Us, "AAPL", "XNAS")),
      [
        fact_input(
          "predicate.false",
          domain.Required,
          domain.Known,
          "observed_false",
          [hash("f")],
        ),
        fact_input(
          "execution",
          domain.Required,
          domain.Unsupported,
          "mapping absent",
          [],
        ),
      ],
    )
  let assert Ok(#(value, _)) = state.attach_candidate(state.empty(), snapshot)
  let encoded =
    render.snapshot_json(value, state.workflows(value)) |> json.to_string
  encoded |> string.contains("\"decisionOwner\":\"llm\"") |> should.be_true
  encoded |> string.contains("observed_false") |> should.be_true
  encoded |> string.contains("unsupported") |> should.be_true
  [
    "\"verdict\"",
    "\"qualified\"",
    "\"accepted\"",
    "\"recommended\"",
    "\"selectedNextOperation\"",
    "\"correctness\"",
  ]
  |> list.each(fn(forbidden) {
    encoded |> string.contains(forbidden) |> should.be_false
  })
}

pub fn malformed_or_duplicate_review_events_fail_closed_test() {
  let snapshot =
    candidate(
      "wf-aapl",
      receipt.encode(strategy_packet(finance_track.Us, "AAPL", "XNAS")),
      [],
    )
  let assert Ok(#(one, _)) = state.attach_candidate(state.empty(), snapshot)
  let review = review_record("wf-aapl", "R1", "note", "payload", None)
  let assert Ok(#(two, _)) = state.attach_review(one, review)
  state.attach_review(two, review)
  |> should.equal(Error(state.DuplicateReviewId("R1")))
}

pub fn portable_bundle_round_trips_exact_information_state_test() {
  let snapshot =
    candidate(
      "wf-aapl",
      receipt.encode(strategy_packet(finance_track.Us, "AAPL", "XNAS")),
      [fact_input("risk", domain.Required, domain.Unknown, "absent", [])],
    )
  let assert Ok(#(one, _)) = state.attach_candidate(state.empty(), snapshot)
  let plan =
    plan_record("wf-aapl", domain.strategy_receipt_hash(snapshot), "plan")
  let assert Ok(#(two, _)) = state.attach_plan(one, plan)
  let review =
    review_record(
      "wf-aapl",
      "R1",
      "observed",
      "payload",
      Some(domain.plan_receipt_hash(plan)),
    )
  let assert Ok(#(three, _)) = state.attach_review(two, review)
  let reference = journal_reference("journal-aapl", "event-review", "review")
  let assert Ok(#(four, _)) = state.attach_journal_reference(three, reference)
  let assert Ok(bundle) =
    portable.build(four, state.workflows(four), portable.AllWorkflows)
  portable.source_revision(bundle) |> should.equal(4)
  portable.portable_revision(bundle) |> should.equal(4)
  let encoded = portable.encode(bundle)
  let assert Ok(decoded) =
    portable.decode_bundle(encoded, portable.content_hash(bundle))
  let assert Ok(restored) = state.replay(portable.events(decoded))
  restored |> should.equal(four)
}

pub fn exact_workflow_portability_reindexes_without_moving_tracks_test() {
  let us =
    candidate(
      "wf-aapl",
      receipt.encode(strategy_packet(finance_track.Us, "AAPL", "XNAS")),
      [],
    )
  let hk =
    candidate(
      "wf-0700",
      receipt.encode(strategy_packet(finance_track.Hk, "00700", "XHKG")),
      [],
    )
  let assert Ok(#(one, _)) = state.attach_candidate(state.empty(), us)
  let assert Ok(#(two, _)) = state.attach_candidate(one, hk)
  let review = review_record("wf-aapl", "R1", "observation", "payload", None)
  let assert Ok(#(three, _)) = state.attach_review(two, review)
  let assert Ok([selected]) = state.selected_workflows(three, Some("wf-aapl"))
  let assert Ok(bundle) =
    portable.build(three, [selected], portable.ExactWorkflow("wf-aapl"))
  portable.source_revision(bundle) |> should.equal(3)
  portable.portable_revision(bundle) |> should.equal(2)
  portable.workflow_ids(bundle) |> should.equal(["wf-aapl"])
  let assert Ok(restored) = state.replay(portable.events(bundle))
  let assert [workflow] = state.workflows(restored)
  workflow
  |> state.latest_snapshot
  |> domain.track
  |> should.equal(finance_track.Us)
}

pub fn portable_bundle_rejects_wrong_hash_tampering_and_noncanonical_text_test() {
  let snapshot =
    candidate(
      "wf-aapl",
      receipt.encode(strategy_packet(finance_track.Us, "AAPL", "XNAS")),
      [],
    )
  let assert Ok(#(one, _)) = state.attach_candidate(state.empty(), snapshot)
  let assert Ok(bundle) =
    portable.build(one, state.workflows(one), portable.AllWorkflows)
  let encoded = portable.encode(bundle)
  portable.decode_bundle(encoded, hash("wrong"))
  |> should.equal(Error(portable.ExpectedContentHashMismatch))
  encoded
  |> string.replace("\"source_revision\":1", "\"source_revision\":2")
  |> portable.decode_bundle(portable.content_hash(bundle))
  |> should.equal(Error(portable.ContentHashMismatch))
  portable.decode_bundle(" " <> encoded, portable.content_hash(bundle))
  |> should.equal(Error(portable.NonCanonicalEncoding))
}

fn candidate(
  workflow_id: String,
  payload: String,
  facts: List(domain.FactInput),
) -> domain.CandidateSnapshot {
  let assert Ok(value) =
    domain.candidate_snapshot(
      workflow_id,
      hash(payload),
      payload,
      facts,
      instant(300),
    )
  value
}

fn fact_input(
  id: String,
  role: domain.FactRole,
  state: domain.InformationState,
  detail: String,
  references: List(identity.Sha256),
) -> domain.FactInput {
  domain.FactInput(id, role, state, detail, references)
}

fn plan_record(
  workflow_id: String,
  strategy_hash: identity.Sha256,
  payload: String,
) -> domain.PlanRecord {
  let assert Ok(value) =
    domain.plan_record(
      workflow_id,
      strategy_hash,
      hash(payload),
      payload,
      domain.LlmAuthored,
      [hash("risk")],
      [hash("rule")],
      [hash("execution")],
      instant(310),
    )
  value
}

fn journal_reference(
  journal_id: String,
  event_id: String,
  relation: String,
) -> domain.JournalEventReference {
  let assert Ok(value) =
    domain.journal_event_reference(
      "wf-aapl",
      journal_id,
      event_id,
      hash("journal-event"),
      relation,
      instant(330),
    )
  value
}

fn review_record(
  workflow_id: String,
  id: String,
  kind: String,
  payload: String,
  plan_reference: Option(identity.Sha256),
) -> domain.ReviewRecord {
  let assert Ok(value) =
    domain.review_record(
      workflow_id,
      id,
      kind,
      hash(payload),
      payload,
      plan_reference,
      [hash("evidence")],
      instant(320),
    )
  value
}

fn strategy_packet(
  track: finance_track.Track,
  symbol: String,
  mic: String,
) -> receipt.StrategyEvidenceReceipt {
  let assert Ok(definition_value) = rsi_reversal.v1(civil(2026, 1, 1), None)
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
          evidence.Declared("not supplied in fixture"),
          None,
          [],
        )
      value
    })
  let assert Ok(context) =
    evidence.evaluation_context(
      listing(track, symbol, mic),
      civil(2026, 8, 6),
      instant(300),
      instant(200),
      dependencies,
      [],
    )
  receipt.build(definition_value, context, [])
}

fn listing(
  track: finance_track.Track,
  symbol: String,
  mic: String,
) -> listing.Key {
  let assert Ok(instrument_id) =
    identifier.instrument_id(
      "fixture:" <> finance_track.name(track) <> ":" <> symbol,
    )
  let assert Ok(symbol_value) = identifier.symbol(symbol)
  let assert Ok(mic_value) = identifier.mic(mic)
  listing.new(track, instrument_id, symbol_value, mic_value)
}

fn first_fact(values: List(domain.EvidenceFact)) -> domain.EvidenceFact {
  let assert [value, ..] = values
  value
}

fn hash(value: String) -> identity.Sha256 {
  let assert Ok(value) = provenance_hash.text(value)
  value
}

fn civil(year: Int, month: Int, day: Int) -> time.Date {
  let assert Ok(value) = time.date(year, month, day)
  value
}

fn instant(value: Int) -> time.Instant {
  let assert Ok(value) = time.instant(value)
  value
}
