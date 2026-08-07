import finance_core/decimal
import finance_core/time
import finance_journal
import finance_journal/checklist
import finance_journal/comparison
import finance_journal/context
import finance_journal/event
import finance_journal/information
import finance_journal/metric
import finance_journal/receipt
import finance_journal/state
import finance_provenance/hash as provenance_hash
import finance_provenance/identity
import finance_track
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn package_is_experimental_test() {
  finance_journal.status() |> should.equal(finance_journal.Experimental)
}

pub fn event_round_trips_exact_attribution_and_payload_test() {
  let value = declaration("event-1", "{\"labels\":[\"anxious\"]}", "key-1", 10)
  let encoded = event.encode(value)
  event.decode(encoded) |> should.equal(Ok(value))
  encoded |> string.contains("user_declared") |> should.be_true
  event.payload(value) |> should.equal("{\"labels\":[\"anxious\"]}")
}

pub fn event_retains_unresolved_identity_without_relabelling_test() {
  let value = unresolved_event("event-1", "000001")
  case value |> event.scope |> event.identity_scope {
    event.UnresolvedListing(
      information.Known(finance_track.Cn),
      information.Unknown("stable identity not supplied"),
      information.Unknown("venue not supplied"),
      information.Known("000001"),
    ) -> Nil
    _ -> should.fail()
  }
}

pub fn correction_and_redaction_require_an_explicit_predecessor_test() {
  event.new(
    "journal-main",
    "correction-1",
    event.Correction,
    journal_scope(),
    event.UserDeclared("user-local"),
    information.Known("post_exit"),
    "corrected",
    information.Known(instant(10)),
    instant(20),
    information.Known("Asia/Shanghai"),
    event.Private,
    [],
    None,
    information.NotApplicable("not imported"),
    "key-correction",
  )
  |> should.equal(Error(event.SupersedesRequired))
}

pub fn append_is_idempotent_for_same_key_and_semantic_payload_test() {
  let first = declaration("event-1", "same", "same-key", 10)
  let retry = declaration("event-retry", "same", "same-key", 10)
  let assert Ok(#(one, state.Stored(_))) = state.append(state.empty(), first)
  let assert Ok(#(same, state.AlreadyStored(stored))) = state.append(one, retry)
  state.revision(same) |> should.equal(1)
  event.event_id(stored) |> should.equal("event-1")
}

pub fn idempotency_conflict_retains_both_hashes_without_overwrite_test() {
  let first = declaration("event-1", "first", "same-key", 10)
  let conflict = declaration("event-2", "second", "same-key", 10)
  let assert Ok(#(one, _)) = state.append(state.empty(), first)
  case state.append(one, conflict) {
    Error(state.IdempotencyConflict(
      "same-key",
      "event-1",
      first_hash,
      second_hash,
    )) -> first_hash |> should.not_equal(second_hash)
    _ -> should.fail()
  }
  state.event_count(one) |> should.equal(1)
}

pub fn correction_lineage_has_current_and_point_in_time_views_test() {
  let original = declaration("event-1", "calm", "key-1", 10)
  let correction = correction("event-2", "anxious", "key-2", "event-1", 20)
  let assert Ok(#(one, _)) = state.append(state.empty(), original)
  let assert Ok(#(two, _)) = state.append(one, correction)
  two
  |> state.current_events
  |> list.map(event.event_id)
  |> should.equal(["event-2"])
  two
  |> state.events_as_of(instant(15))
  |> list.map(event.event_id)
  |> should.equal(["event-1"])
  state.events(two) |> list.length |> should.equal(2)
}

pub fn correction_cannot_reference_an_unknown_event_test() {
  state.append(
    state.empty(),
    correction("event-2", "new", "key-2", "missing", 20),
  )
  |> should.equal(Error(state.MissingSupersededEvent("missing")))
}

pub fn batch_append_is_purely_atomic_before_storage_test() {
  let first = declaration("event-1", "one", "key-1", 10)
  let invalid = correction("event-2", "two", "key-2", "missing", 20)
  state.append_many(state.empty(), [first, invalid])
  |> should.equal(Error(state.MissingSupersededEvent("missing")))
}

pub fn jsonl_replay_is_exact_and_blank_middle_line_fails_test() {
  let first = declaration("event-1", "one", "key-1", 10)
  let second = declaration("event-2", "two", "key-2", 20)
  let jsonl = state.encode_jsonl([first, second])
  let assert Ok(replayed) = state.decode_jsonl(jsonl, 10, 100_000)
  state.events(replayed) |> should.equal([first, second])
  state.decode_jsonl(
    event.encode(first) <> "\n\n" <> event.encode(second),
    10,
    100_000,
  )
  |> should.equal(Error(state.EmptyLine(2)))
}

pub fn caller_selected_export_privacy_and_bounds_are_explicit_test() {
  let private = declaration("event-1", "private", "key-1", 10)
  let visible =
    declaration_with_privacy(
      "event-2",
      "visible",
      "key-2",
      20,
      event.Exportable,
    )
  let assert Ok(#(one, _)) = state.append(state.empty(), private)
  let assert Ok(#(two, _)) = state.append(one, visible)
  let exported =
    state.export_jsonl(two, state.ExportPolicy(False, False, True, True), 1)
  state.exported_count(exported) |> should.equal(1)
  state.export_text(exported) |> string.contains("visible") |> should.be_true
  state.export_text(exported) |> string.contains("private") |> should.be_false
}

pub fn bounded_query_filters_exact_workflow_and_reports_omissions_test() {
  let first = workflow_event("event-1", "wf-a", "key-1", 10)
  let second = workflow_event("event-2", "wf-a", "key-2", 20)
  let third = workflow_event("event-3", "wf-b", "key-3", 30)
  let assert Ok(#(one, _)) = state.append(state.empty(), first)
  let assert Ok(#(two, _)) = state.append(one, second)
  let assert Ok(#(three, _)) = state.append(two, third)
  let result =
    state.query(three, state.Query(Some("wf-a"), [], [], [], True, 1))
  state.matched_count(result) |> should.equal(2)
  state.query_omitted_count(result) |> should.equal(1)
  result
  |> state.query_events
  |> list.map(event.event_id)
  |> should.equal(["event-1"])
}

pub fn checklist_receipts_report_answers_without_pass_fail_or_prompt_choice_test() {
  let definition = checklist_definition()
  let assert Ok(response) =
    checklist.response(
      definition,
      "workflow:wf-a",
      event.UserDeclared("user-local"),
      instant(10),
      instant(11),
      [
        checklist.Answer("thesis", checklist.Yes, None),
        checklist.Answer("emotion", checklist.Unknown("not supplied"), None),
      ],
      [],
    )
  let encoded = response |> checklist.response_receipt |> receipt.encode
  encoded |> string.contains("\"answered\":1") |> should.be_true
  encoded |> string.contains("\"unknown\":1") |> should.be_true
  encoded |> string.contains("\"plugin_decision_fields\":[]") |> should.be_true
  encoded |> string.contains("\"pass\"") |> should.be_false
  encoded |> string.contains("next_prompt") |> should.be_false
}

pub fn checklist_answer_schema_mismatch_is_structural_test() {
  let definition = checklist_definition()
  checklist.response(
    definition,
    "workflow:wf-a",
    event.UserDeclared("user-local"),
    instant(10),
    instant(11),
    [checklist.Answer("thesis", checklist.Text("yes"), None)],
    [],
  )
  |> should.equal(Error(checklist.AnswerDoesNotMatchSchema("thesis")))
}

pub fn comparison_returns_requested_decimal_delta_without_process_label_test() {
  let assert Ok(value) =
    comparison.compare(
      hash("instruction"),
      hash("plan"),
      [hash("observation")],
      "unknown",
      "preserve_all",
      [
        comparison.FieldRequest(
          "quantity",
          information.Known("5500"),
          information.Known("5400"),
          comparison.DecimalDelta(2, decimal.HalfUp),
          "shares",
        ),
      ],
    )
  comparison.results(value)
  |> should.equal([
    comparison.Compared(
      "quantity",
      "5500",
      "5400",
      False,
      information.Known("-100.00"),
      "shares",
    ),
  ])
  let encoded = value |> comparison.receipt |> receipt.encode
  encoded |> string.contains("violation") |> should.be_false
  encoded |> string.contains("\"decision_owner\":\"llm\"") |> should.be_true
}

pub fn comparison_retains_unknown_and_unperformed_inputs_test() {
  let assert Ok(value) =
    comparison.compare(
      hash("instruction"),
      hash("plan"),
      [],
      "unknown",
      "preserve_all",
      [
        comparison.FieldRequest(
          "price",
          information.Known("10.91"),
          information.Unknown("fill absent"),
          comparison.DecimalDelta(2, decimal.HalfUp),
          "CNY/share",
        ),
      ],
    )
  case comparison.results(value) {
    [
      comparison.Unperformed(
        "price",
        _,
        information.Unknown("fill absent"),
        _,
        _,
      ),
    ] -> Nil
    _ -> should.fail()
  }
}

pub fn requested_long_cash_net_pnl_preserves_components_and_scale_test() {
  let assert Ok(value) =
    metric.long_cash_realized_net_pnl(
      hash("instruction"),
      "CNY",
      2,
      decimal.HalfUp,
      [
        metric.FillInput("entry", metric.Entry, "100", "10.00", hash("entry")),
        metric.FillInput("exit", metric.Exit, "100", "11.00", hash("exit")),
      ],
      [metric.CostInput("commission", "2.00", hash("cost"))],
    )
  value |> metric.net_pnl |> decimal.to_string |> should.equal("98")
  let encoded = value |> metric.receipt |> receipt.encode
  encoded |> string.contains("\"net_pnl\":\"98.00\"") |> should.be_true
  encoded |> string.contains("recommend") |> should.be_false
}

pub fn metric_decode_failure_does_not_become_a_trade_decision_test() {
  metric.long_cash_realized_net_pnl(
    hash("instruction"),
    "CNY",
    2,
    decimal.HalfUp,
    [
      metric.FillInput("entry", metric.Entry, "bad", "10.00", hash("entry")),
      metric.FillInput("exit", metric.Exit, "100", "11.00", hash("exit")),
    ],
    [],
  )
  |> should.equal(Error(metric.InvalidDecimal("fill_quantity:entry", "bad")))
}

pub fn context_is_compact_private_and_has_no_decision_fields_test() {
  let first = declaration("event-1", "sensitive prose", "key-1", 10)
  let second = correction("event-2", "replacement", "key-2", "event-1", 20)
  let assert Ok(#(one, _)) = state.append(state.empty(), first)
  let assert Ok(#(two, _)) = state.append(one, second)
  let encoded = two |> context.receipt(False) |> receipt.encode
  encoded |> string.contains("sensitive prose") |> should.be_false
  encoded |> string.contains("\"decision_owner\":\"llm\"") |> should.be_true
  encoded |> string.contains("\"plugin_decision_fields\":[]") |> should.be_true
  encoded |> string.contains("selected_operation") |> should.be_false
}

pub fn same_symbol_on_two_tracks_remains_two_scopes_test() {
  let cn =
    listing_event(
      "event-cn",
      finance_track.Cn,
      "cn:000001",
      "XSHG",
      "000001",
      "key-cn",
    )
  let hk =
    listing_event(
      "event-hk",
      finance_track.Hk,
      "hk:000001",
      "XHKG",
      "000001",
      "key-hk",
    )
  let assert Ok(#(one, _)) = state.append(state.empty(), cn)
  let assert Ok(#(two, _)) = state.append(one, hk)
  state.event_count(two) |> should.equal(2)
  state.events(two)
  |> list.map(fn(value) { value |> event.scope |> event.identity_scope })
  |> should.equal([
    event.ExactListing(
      finance_track.Cn,
      "cn:000001",
      "XSHG",
      information.Known("000001"),
    ),
    event.ExactListing(
      finance_track.Hk,
      "hk:000001",
      "XHKG",
      information.Known("000001"),
    ),
  ])
}

fn declaration(
  id: String,
  payload: String,
  key: String,
  at: Int,
) -> event.Event {
  declaration_with_privacy(id, payload, key, at, event.Private)
}

fn declaration_with_privacy(
  id: String,
  payload: String,
  key: String,
  at: Int,
  privacy: event.Privacy,
) -> event.Event {
  let assert Ok(value) =
    event.new(
      "journal-main",
      id,
      event.Declaration,
      journal_scope(),
      event.UserDeclared("user-local"),
      information.Known("pre_order"),
      payload,
      information.Known(instant(at)),
      instant(at),
      information.Known("Asia/Shanghai"),
      privacy,
      [],
      None,
      information.NotApplicable("not imported"),
      key,
    )
  value
}

fn correction(
  id: String,
  payload: String,
  key: String,
  supersedes: String,
  at: Int,
) -> event.Event {
  let assert Ok(value) =
    event.new(
      "journal-main",
      id,
      event.Correction,
      journal_scope(),
      event.UserDeclared("user-local"),
      information.Known("post_exit"),
      payload,
      information.Known(instant(10)),
      instant(at),
      information.Known("Asia/Shanghai"),
      event.Private,
      [],
      Some(supersedes),
      information.NotApplicable("not imported"),
      key,
    )
  value
}

fn unresolved_event(id: String, symbol: String) -> event.Event {
  let assert Ok(value) =
    event.new(
      "journal-main",
      id,
      event.Declaration,
      event.Scope(
        event.UnresolvedListing(
          information.Known(finance_track.Cn),
          information.Unknown("stable identity not supplied"),
          information.Unknown("venue not supplied"),
          information.Known(symbol),
        ),
        Some("wf-a"),
        None,
        None,
      ),
      event.UserDeclared("user-local"),
      information.NotAsked,
      "identity unresolved",
      information.Unknown("time not supplied"),
      instant(10),
      information.Unknown("timezone not supplied"),
      event.ReviewVisible,
      [],
      None,
      information.NotApplicable("not imported"),
      "key-unresolved",
    )
  value
}

fn workflow_event(
  id: String,
  workflow: String,
  key: String,
  at: Int,
) -> event.Event {
  let assert Ok(value) =
    event.new(
      "journal-main",
      id,
      event.Declaration,
      event.Scope(event.JournalWide, Some(workflow), None, None),
      event.LlmDeclared("llm-session", Some(hash("context"))),
      information.Known("periodic_review"),
      "llm-authored conclusion",
      information.Known(instant(at)),
      instant(at),
      information.Known("UTC"),
      event.ReviewVisible,
      [],
      None,
      information.NotApplicable("not imported"),
      key,
    )
  value
}

fn listing_event(
  id: String,
  track: finance_track.Track,
  listing_id: String,
  mic: String,
  symbol: String,
  key: String,
) -> event.Event {
  let assert Ok(value) =
    event.new(
      "journal-main",
      id,
      event.Declaration,
      event.Scope(
        event.ExactListing(track, listing_id, mic, information.Known(symbol)),
        None,
        None,
        None,
      ),
      event.UserDeclared("user-local"),
      information.NotAsked,
      "same display symbol",
      information.Known(instant(10)),
      instant(10),
      information.Known("UTC"),
      event.Exportable,
      [],
      None,
      information.NotApplicable("not imported"),
      key,
    )
  value
}

fn journal_scope() -> event.Scope {
  event.Scope(event.JournalWide, None, None, None)
}

fn checklist_definition() -> checklist.Definition {
  let assert Ok(value) =
    checklist.definition(
      "swing_pre_trade",
      "1.0.0",
      "Swing pre-trade declarations",
      "swing_trader",
      "pre_trade",
      [finance_track.Cn, finance_track.Hk, finance_track.Us],
      [
        checklist.Item(
          "thesis",
          "Can you state the thesis?",
          checklist.YesNo,
          Some("context"),
          False,
        ),
        checklist.Item(
          "emotion",
          "What do you declare?",
          checklist.FreeText,
          Some("context"),
          False,
        ),
      ],
      event.UserDeclared("user-local"),
      instant(1),
    )
  value
}

fn hash(value: String) -> identity.Sha256 {
  let assert Ok(value) = provenance_hash.text(value)
  value
}

fn instant(value: Int) -> time.Instant {
  let assert Ok(value) = time.instant(value)
  value
}
