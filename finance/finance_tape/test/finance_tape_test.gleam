import finance_core/identifier
import finance_provenance/identity
import finance_tape.{
  BoundedPartial, Cancel, ConflictingSequence, DocumentedConditions,
  DuplicateSequence, ExchangeClock, KnownLexeme, MissingReference, Nondecreasing,
  Nonmonotonic, OriginalTrade, OutOfOrderSequence, ProviderDeclaredComplete,
  ReferenceOccursLater, ResetBoundary, ResetPreviousMismatch, SelfReference,
  SequenceConflicting, SequenceGap, SequenceReset, SequenceScopeChanged,
  SequenceUnavailable, Sequenced, TradeReferenceMismatch, UnavailableSequence,
  UndocumentedConditions,
}
import finance_track
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleeunit
import gleeunit/should

const hash_a = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

const hash_b = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

pub fn main() {
  gleeunit.main()
}

pub fn clean_packet_retains_scope_and_has_no_integrity_issues_test() {
  let events = [trade("e1", "t1", 10, "9007199254740992", ["regular"])]
  let packet = complete_packet(events)
  let review = finance_tape.review(packet)

  finance_tape.packet_track(packet) |> should.equal(finance_track.Hk)
  finance_tape.packet_listing_id(packet) |> should.equal("HK.00700")
  finance_tape.packet_feed(packet) |> should.equal("futu_ticker")
  finance_tape.review_provider_declared_complete(review) |> should.be_true
  finance_tape.review_condition_documentation_complete(review)
  |> should.be_true
  finance_tape.duplicate_exact_event_count(review) |> should.equal(0)
  finance_tape.review_sequence_issues(review) |> should.equal([])
  finance_tape.review_lineage_issues(review) |> should.equal([])
  finance_tape.event_time_order(review)
  |> should.equal(Nondecreasing(ExchangeClock))
}

pub fn arbitrary_length_sequence_gap_is_exact_test() {
  let review =
    complete_packet([
      trade("e1", "t1", 10, "999999999999999999999999", []),
      trade("e2", "t2", 11, "1000000000000000000000001", []),
    ])
    |> finance_tape.review

  finance_tape.review_sequence_issues(review)
  |> should.equal([
    SequenceGap(
      "ticker",
      "999999999999999999999999",
      "1000000000000000000000000",
      "1000000000000000000000001",
      "e2",
    ),
  ])
}

pub fn duplicate_out_of_order_and_reset_boundaries_are_distinct_test() {
  let events = [
    trade("e1", "t1", 10, "8", []),
    trade("e2", "t2", 11, "8", []),
    trade("e3", "t3", 12, "7", []),
    event_with_sequence("e4", "t4", 13, SequenceReset("ticker", "1", Some("7"))),
    trade("e5", "t5", 14, "2", []),
  ]
  let issues =
    complete_packet(events)
    |> finance_tape.review
    |> finance_tape.review_sequence_issues

  issues
  |> should.equal([
    DuplicateSequence("ticker", "8", "e2"),
    OutOfOrderSequence("ticker", "8", "7", "e3"),
    ResetBoundary("ticker", "1", Some("7"), "e4"),
  ])
}

pub fn reset_predecessor_and_scope_mismatches_are_reported_test() {
  let events = [
    trade("e1", "t1", 10, "10", []),
    event_with_sequence("e2", "t2", 11, SequenceReset("ticker", "1", Some("9"))),
    event_with_sequence("e3", "t3", 12, Sequenced("other", "2")),
  ]
  let issues =
    complete_packet(events)
    |> finance_tape.review
    |> finance_tape.review_sequence_issues

  issues
  |> should.equal([
    ResetPreviousMismatch("ticker", "10", "9", "e2"),
    ResetBoundary("ticker", "1", Some("9"), "e2"),
    SequenceScopeChanged("ticker", "other", "e3"),
  ])
}

pub fn unavailable_and_conflicting_sequences_remain_explicit_test() {
  let issues =
    complete_packet([
      event_with_sequence("e1", "t1", 10, SequenceUnavailable("not reported")),
      event_with_sequence(
        "e2",
        "t2",
        11,
        SequenceConflicting("ticker", ["1", "2"]),
      ),
    ])
    |> finance_tape.review
    |> finance_tape.review_sequence_issues

  issues
  |> should.equal([
    UnavailableSequence("not reported", "e1"),
    ConflictingSequence("ticker", ["1", "2"], "e2"),
  ])
}

pub fn exact_duplicates_and_conflicting_event_ids_are_separate_test() {
  let first = trade("same", "trade", 10, "1", [])
  let changed = trade("same", "trade", 11, "2", [])
  let review =
    partial_packet([first, first, changed])
    |> finance_tape.review

  finance_tape.duplicate_exact_event_count(review) |> should.equal(1)
  finance_tape.duplicate_event_id_values(review) |> should.equal(["same"])
  finance_tape.conflicting_event_id_values(review) |> should.equal(["same"])
  finance_tape.duplicate_original_trade_id_values(review)
  |> should.equal(["trade"])
}

pub fn correction_and_cancel_lineage_failures_are_retained_test() {
  let original = trade("original", "trade-1", 20, "1", [])
  let later_reference =
    correction("early-correction", "trade-1", 10, "original", Some("trade-1"))
  let missing = correction("missing", "trade-2", 21, "absent", Some("trade-2"))
  let mismatch =
    correction("mismatch", "trade-1", 22, "original", Some("wrong-trade"))
  let self = correction("self", "trade-3", 23, "self", None)
  let cancelled = cancel("cancel", "trade-1", 24, "original")
  let after_cancel =
    correction("after-cancel", "trade-1", 25, "cancel", Some("trade-1"))
  let issues =
    partial_packet([
      original,
      later_reference,
      missing,
      mismatch,
      self,
      cancelled,
      after_cancel,
    ])
    |> finance_tape.review
    |> finance_tape.review_lineage_issues

  list.contains(issues, ReferenceOccursLater("early-correction", "original"))
  |> should.be_true
  list.contains(issues, MissingReference("missing", "absent"))
  |> should.be_true
  list.contains(
    issues,
    TradeReferenceMismatch("mismatch", "trade-1", "wrong-trade"),
  )
  |> should.be_true
  list.contains(issues, SelfReference("self")) |> should.be_true
  list.contains(issues, finance_tape.CancelReference("after-cancel", "cancel"))
  |> should.be_true
}

pub fn time_order_uses_one_honest_clock_basis_test() {
  let first =
    event_with_clocks(
      "e1",
      "t1",
      finance_tape.clocks(Some(20), Some(30), 40),
      "1",
    )
  let second =
    event_with_clocks(
      "e2",
      "t2",
      finance_tape.clocks(Some(10), Some(31), 41),
      "2",
    )
  let review = complete_packet([first, second]) |> finance_tape.review

  finance_tape.event_time_order(review)
  |> should.equal(Nonmonotonic(ExchangeClock, ["e2"]))
  let assert [finance_tape.ClockDelta(_, Some(10), Some(10), Some(20)), ..] =
    finance_tape.review_clock_deltas(review)
}

pub fn exact_condition_counts_do_not_infer_meaning_test() {
  let packet =
    packet_with_conditions([
      trade("e1", "t1", 10, "1", ["regular", "odd_lot"]),
      trade("e2", "t2", 11, "2", ["regular", "unknown_code"]),
    ])
  let review = finance_tape.review(packet)

  finance_tape.review_condition_counts(review)
  |> should.equal([
    finance_tape.ConditionCount("regular", 2),
    finance_tape.ConditionCount("odd_lot", 1),
    finance_tape.ConditionCount("unknown_code", 1),
  ])
  finance_tape.review_undocumented_condition_codes(review)
  |> should.equal(["unknown_code"])
  finance_tape.review_condition_documentation_complete(review)
  |> should.be_false
}

pub fn track_mic_budget_decimal_and_sequence_inputs_fail_closed_test() {
  let assert Ok(c) = finance_tape.clocks(Some(1), Some(2), 3)
  let assert Ok(receipt) = identity.sha256(hash_a)
  let assert Ok(cn_mic) = identifier.mic("XSHG")
  let assert Ok(hk_mic) = identifier.mic("XHKG")

  finance_tape.event(
    event_id: "e",
    trade_id: "t",
    kind: OriginalTrade,
    price: KnownLexeme("10x"),
    size: KnownLexeme("1"),
    condition_codes: [],
    venue_lexeme: "XHKG",
    clocks: c,
    sequence: Sequenced("ticker", "1"),
    raw_receipt_hash: receipt,
  )
  |> should.be_error

  finance_tape.event(
    event_id: "e",
    trade_id: "t",
    kind: OriginalTrade,
    price: KnownLexeme("10"),
    size: KnownLexeme("1"),
    condition_codes: [],
    venue_lexeme: "XHKG",
    clocks: c,
    sequence: Sequenced("ticker", "01"),
    raw_receipt_hash: receipt,
  )
  |> should.be_error

  finance_tape.packet(
    track: finance_track.Hk,
    listing_id: "HK.00700",
    mic: cn_mic,
    session_id: "2026-08-14",
    provider: "fixture",
    feed: "ticker",
    entitlement: "fixture",
    licence: "test-only",
    coverage: BoundedPartial("fixture"),
    condition_coverage: UndocumentedConditions("fixture"),
    maximum_events: 1,
    events: [trade("e1", "t1", 1, "1", [])],
  )
  |> should.be_error

  finance_tape.packet(
    track: finance_track.Hk,
    listing_id: "HK.00700",
    mic: hk_mic,
    session_id: "2026-08-14",
    provider: "fixture",
    feed: "ticker",
    entitlement: "fixture",
    licence: "test-only",
    coverage: BoundedPartial("fixture"),
    condition_coverage: UndocumentedConditions("fixture"),
    maximum_events: 1,
    events: [
      trade("e1", "t1", 1, "1", []),
      trade("e2", "t2", 2, "2", []),
    ],
  )
  |> should.be_error
}

fn complete_packet(events: List(finance_tape.Event)) -> finance_tape.Packet {
  let assert Ok(receipt) = identity.sha256(hash_a)
  let assert Ok(mic) = identifier.mic("XHKG")
  let assert Ok(value) =
    finance_tape.packet(
      track: finance_track.Hk,
      listing_id: "HK.00700",
      mic: mic,
      session_id: "2026-08-14-continuous",
      provider: "futu",
      feed: "futu_ticker",
      entitlement: "caller_declared_hk_lv2",
      licence: "caller-owned development observation",
      coverage: ProviderDeclaredComplete(receipt),
      condition_coverage: DocumentedConditions(["regular"], receipt),
      maximum_events: 100,
      events: events,
    )
  value
}

fn partial_packet(events: List(finance_tape.Event)) -> finance_tape.Packet {
  let assert Ok(mic) = identifier.mic("XHKG")
  let assert Ok(value) =
    finance_tape.packet(
      track: finance_track.Hk,
      listing_id: "HK.00700",
      mic: mic,
      session_id: "2026-08-14-continuous",
      provider: "fixture",
      feed: "scripted_ticker",
      entitlement: "fixture_only",
      licence: "rights-safe fixture",
      coverage: BoundedPartial("bounded scripted packet"),
      condition_coverage: UndocumentedConditions("not supplied"),
      maximum_events: 100,
      events: events,
    )
  value
}

fn packet_with_conditions(
  events: List(finance_tape.Event),
) -> finance_tape.Packet {
  let assert Ok(receipt) = identity.sha256(hash_b)
  let assert Ok(mic) = identifier.mic("XHKG")
  let assert Ok(value) =
    finance_tape.packet(
      track: finance_track.Hk,
      listing_id: "HK.00700",
      mic: mic,
      session_id: "2026-08-14-continuous",
      provider: "fixture",
      feed: "scripted_ticker",
      entitlement: "fixture_only",
      licence: "rights-safe fixture",
      coverage: BoundedPartial("bounded scripted packet"),
      condition_coverage: DocumentedConditions(["regular", "odd_lot"], receipt),
      maximum_events: 100,
      events: events,
    )
  value
}

fn trade(
  event_id: String,
  trade_id: String,
  time: Int,
  sequence: String,
  conditions: List(String),
) -> finance_tape.Event {
  base_event(
    event_id,
    trade_id,
    OriginalTrade,
    time,
    Sequenced("ticker", sequence),
    conditions,
  )
}

fn correction(
  event_id: String,
  trade_id: String,
  time: Int,
  reference_event_id: String,
  reference_trade_id: Option(String),
) -> finance_tape.Event {
  base_event(
    event_id,
    trade_id,
    finance_tape.Correction(reference_event_id, reference_trade_id),
    time,
    Sequenced("ticker", int.to_string(time)),
    [],
  )
}

fn cancel(
  event_id: String,
  trade_id: String,
  time: Int,
  reference_event_id: String,
) -> finance_tape.Event {
  base_event(
    event_id,
    trade_id,
    Cancel(reference_event_id, Some(trade_id)),
    time,
    Sequenced("ticker", int.to_string(time)),
    [],
  )
}

fn event_with_sequence(
  event_id: String,
  trade_id: String,
  time: Int,
  sequence: finance_tape.SequenceMarker,
) -> finance_tape.Event {
  base_event(event_id, trade_id, OriginalTrade, time, sequence, [])
}

fn event_with_clocks(
  event_id: String,
  trade_id: String,
  clocks_result: Result(finance_tape.Clocks, finance_tape.TapeError),
  sequence: String,
) -> finance_tape.Event {
  let assert Ok(clocks) = clocks_result
  let assert Ok(receipt) = identity.sha256(hash_a)
  let assert Ok(value) =
    finance_tape.event(
      event_id: event_id,
      trade_id: trade_id,
      kind: OriginalTrade,
      price: KnownLexeme("10.00"),
      size: KnownLexeme("100"),
      condition_codes: [],
      venue_lexeme: "XHKG",
      clocks: clocks,
      sequence: Sequenced("ticker", sequence),
      raw_receipt_hash: receipt,
    )
  value
}

fn base_event(
  event_id: String,
  trade_id: String,
  kind: finance_tape.EventKind,
  time: Int,
  sequence: finance_tape.SequenceMarker,
  conditions: List(String),
) -> finance_tape.Event {
  let assert Ok(clocks) =
    finance_tape.clocks(Some(time), Some(time + 1), time + 2)
  let assert Ok(receipt) = identity.sha256(hash_a)
  let assert Ok(value) =
    finance_tape.event(
      event_id: event_id,
      trade_id: trade_id,
      kind: kind,
      price: KnownLexeme("10.00"),
      size: KnownLexeme("100"),
      condition_codes: conditions,
      venue_lexeme: "XHKG",
      clocks: clocks,
      sequence: sequence,
      raw_receipt_hash: receipt,
    )
  value
}
