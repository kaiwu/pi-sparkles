import finance_core/decimal
import finance_core/identifier
import finance_core/time
import finance_execution/instruction
import finance_execution/tape_simulation
import finance_provenance/identity
import finance_tape
import finance_track
import gleam/list
import gleam/option.{type Option, None, Some}
import gleeunit
import gleeunit/should

const hash_a = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

const hash_b = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

pub fn main() {
  gleeunit.main()
}

pub fn eligible_prints_create_non_fill_and_bounded_possible_fill_branches_test() {
  let simulation =
    simulate(
      desired(instruction.Buy, "100", instruction.Shares),
      packet([
        trade("e1", "t1", "10.00", "60", "1", "XHKG", ["regular"]),
        trade("e2", "t2", "10.25", "90", "2", "XHKG", ["regular"]),
      ]),
      policy(),
    )

  tape_simulation.model(simulation)
  |> should.equal(tape_simulation.transaction_tape_possible_fill_v1)
  simulation
  |> tape_simulation.observed_candidate_quantity
  |> decimal.to_string
  |> should.equal("150")
  simulation
  |> tape_simulation.compatible_fill_quantity
  |> decimal.to_string
  |> should.equal("100")
  let assert [
    tape_simulation.CompatibleNonFill(_),
    tape_simulation.CompatibleFillUpTo(quantity, _),
  ] = tape_simulation.branches(simulation)
  decimal.to_string(quantity) |> should.equal("100")
}

pub fn venue_condition_and_limit_policy_exclusions_are_explicit_test() {
  let simulation =
    simulate(
      desired(instruction.Buy, "100", instruction.Shares),
      packet([
        trade("venue", "t1", "10.00", "10", "1", "OTHER", ["regular"]),
        trade("condition", "t2", "10.00", "10", "2", "XHKG", ["odd"]),
        trade("limit", "t3", "11.00", "10", "3", "XHKG", ["regular"]),
      ]),
      policy(),
    )

  tape_simulation.candidates(simulation) |> should.equal([])
  tape_simulation.excluded(simulation)
  |> should.equal([
    tape_simulation.ExcludedTrade("venue", "venue_not_eligible"),
    tape_simulation.ExcludedTrade("condition", "condition_not_eligible"),
    tape_simulation.ExcludedTrade("limit", "outside_limit"),
  ])
  tape_simulation.branches(simulation)
  |> list.length
  |> should.equal(1)
}

pub fn sell_limit_uses_only_prints_at_or_above_limit_test() {
  let simulation =
    simulate(
      desired(instruction.Sell, "100", instruction.Shares),
      packet([
        trade("below", "t1", "10.49", "50", "1", "XHKG", ["regular"]),
        trade("equal", "t2", "10.50", "30", "2", "XHKG", ["regular"]),
        trade("above", "t3", "10.60", "40", "3", "XHKG", ["regular"]),
      ]),
      policy(),
    )

  simulation
  |> tape_simulation.observed_candidate_quantity
  |> decimal.to_string
  |> should.equal("70")
}

pub fn sequence_gaps_are_retained_without_becoming_fill_proof_test() {
  let simulation =
    simulate(
      desired(instruction.Buy, "100", instruction.Shares),
      packet([
        trade("e1", "t1", "10.00", "50", "1", "XHKG", ["regular"]),
        trade("e2", "t2", "10.00", "50", "3", "XHKG", ["regular"]),
      ]),
      policy(),
    )

  tape_simulation.sequence_issue_count(simulation) |> should.equal(1)
  let assert [tape_simulation.CompatibleNonFill(_), _] =
    tape_simulation.branches(simulation)
}

pub fn duplicate_events_and_unreconciled_corrections_fail_closed_test() {
  let event = trade("e1", "t1", "10.00", "50", "1", "XHKG", ["regular"])
  tape_simulation.simulate(
    instruction: desired(instruction.Buy, "100", instruction.Shares),
    packet: packet([event, event]),
    policy: policy(),
  )
  |> should.be_error

  let correction = correction("e2", "t1", "e1")
  tape_simulation.simulate(
    instruction: desired(instruction.Buy, "100", instruction.Shares),
    packet: packet([event, correction]),
    policy: policy(),
  )
  |> should.be_error
}

pub fn identity_behavior_quantity_and_unknown_trade_fields_fail_closed_test() {
  let base =
    packet([trade("e1", "t1", "10.00", "50", "1", "XHKG", ["regular"])])
  tape_simulation.simulate(
    instruction: desired_for_listing(
      instruction.Buy,
      "100",
      instruction.Shares,
      "HK.00005",
      instruction.Limit(decimal_value("10.50")),
      None,
      None,
    ),
    packet: base,
    policy: policy(),
  )
  |> should.be_error
  tape_simulation.simulate(
    instruction: desired_for_listing(
      instruction.Buy,
      "100",
      instruction.Shares,
      "HK.00700",
      instruction.Market,
      None,
      None,
    ),
    packet: base,
    policy: policy(),
  )
  |> should.be_error
  tape_simulation.simulate(
    instruction: desired(instruction.Buy, "10", instruction.Lots),
    packet: base,
    policy: policy(),
  )
  |> should.be_error

  let unknown =
    event_with_price(
      "unknown",
      "t2",
      finance_tape.UnavailableLexeme("not reported"),
    )
  tape_simulation.simulate(
    instruction: desired(instruction.Buy, "100", instruction.Shares),
    packet: packet([unknown]),
    policy: policy(),
  )
  |> should.be_error
}

pub fn events_outside_instruction_time_window_are_excluded_test() {
  let instruction =
    desired_for_listing(
      instruction.Buy,
      "100",
      instruction.Shares,
      "HK.00700",
      instruction.Limit(decimal_value("10.50")),
      Some(instant(2)),
      Some(instant(5)),
    )
  let simulation =
    simulate(
      instruction,
      packet([trade("early", "t1", "10.00", "50", "1", "XHKG", ["regular"])]),
      policy(),
    )
  tape_simulation.excluded(simulation)
  |> should.equal([
    tape_simulation.ExcludedTrade("early", "outside_instruction_time_window"),
  ])
}

pub fn policy_rejects_empty_venues_and_duplicate_codes_test() {
  tape_simulation.eligibility_policy(
    eligible_venue_lexemes: [],
    eligible_condition_codes: [],
    allow_unconditioned_events: True,
  )
  |> should.be_error
  tape_simulation.eligibility_policy(
    eligible_venue_lexemes: ["XHKG"],
    eligible_condition_codes: ["regular", "regular"],
    allow_unconditioned_events: True,
  )
  |> should.be_error
}

fn simulate(
  instruction: instruction.DesiredInstruction,
  packet: finance_tape.Packet,
  policy: tape_simulation.EligibilityPolicy,
) -> tape_simulation.TapeSimulation {
  let assert Ok(value) =
    tape_simulation.simulate(
      instruction: instruction,
      packet: packet,
      policy: policy,
    )
  value
}

fn policy() -> tape_simulation.EligibilityPolicy {
  let assert Ok(value) =
    tape_simulation.eligibility_policy(
      eligible_venue_lexemes: ["XHKG"],
      eligible_condition_codes: ["regular"],
      allow_unconditioned_events: False,
    )
  value
}

fn desired(
  side: instruction.Side,
  quantity: String,
  unit: instruction.QuantityUnit,
) -> instruction.DesiredInstruction {
  desired_for_listing(
    side,
    quantity,
    unit,
    "HK.00700",
    instruction.Limit(decimal_value("10.50")),
    None,
    None,
  )
}

fn desired_for_listing(
  side: instruction.Side,
  quantity: String,
  unit: instruction.QuantityUnit,
  listing_id: String,
  behavior: instruction.OrderBehavior,
  activation_time: Option(time.Instant),
  expiry_time: Option(time.Instant),
) -> instruction.DesiredInstruction {
  let assert Ok(value) =
    instruction.desired(
      instruction_id: "instruction-1",
      instruction_receipt: sha(hash_a),
      track: finance_track.Hk,
      listing_id: listing_id,
      mic: "XHKG",
      account_scope: "caller-account-scope",
      currency: "HKD",
      side: side,
      intent: None,
      quantity: decimal_value(quantity),
      quantity_unit: unit,
      order_behavior: behavior,
      time_in_force: instruction.Day,
      requested_session: Some(instruction.Regular),
      activation_time: activation_time,
      expiry_time: expiry_time,
      timezone: "Asia/Hong_Kong",
      rule_references: [sha(hash_b)],
      capability_references: [sha(hash_b)],
      account_references: [sha(hash_a)],
      retained_alternatives: instruction.AlternativesNotApplicable("fixture"),
    )
  value
}

fn packet(events: List(finance_tape.Event)) -> finance_tape.Packet {
  let assert Ok(mic) = identifier.mic("XHKG")
  let assert Ok(value) =
    finance_tape.packet(
      track: finance_track.Hk,
      listing_id: "HK.00700",
      mic: mic,
      session_id: "2026-08-14-regular",
      provider: "fixture",
      feed: "transaction_ticker",
      entitlement: "fixture_only",
      licence: "rights-safe fixture",
      coverage: finance_tape.ProviderDeclaredComplete(sha(hash_b)),
      condition_coverage: finance_tape.DocumentedConditions(
        ["regular"],
        sha(hash_b),
      ),
      maximum_events: 100,
      events: events,
    )
  value
}

fn trade(
  event_id: String,
  trade_id: String,
  price: String,
  size: String,
  sequence: String,
  venue: String,
  conditions: List(String),
) -> finance_tape.Event {
  event(
    event_id,
    trade_id,
    finance_tape.OriginalTrade,
    finance_tape.KnownLexeme(price),
    finance_tape.KnownLexeme(size),
    sequence,
    venue,
    conditions,
  )
}

fn correction(
  event_id: String,
  trade_id: String,
  reference_event_id: String,
) -> finance_tape.Event {
  event(
    event_id,
    trade_id,
    finance_tape.Correction(reference_event_id, Some(trade_id)),
    finance_tape.KnownLexeme("10.00"),
    finance_tape.KnownLexeme("40"),
    "2",
    "XHKG",
    ["regular"],
  )
}

fn event_with_price(
  event_id: String,
  trade_id: String,
  price: finance_tape.Lexeme,
) -> finance_tape.Event {
  event(
    event_id,
    trade_id,
    finance_tape.OriginalTrade,
    price,
    finance_tape.KnownLexeme("10"),
    "1",
    "XHKG",
    ["regular"],
  )
}

fn event(
  event_id: String,
  trade_id: String,
  kind: finance_tape.EventKind,
  price: finance_tape.Lexeme,
  size: finance_tape.Lexeme,
  sequence: String,
  venue: String,
  conditions: List(String),
) -> finance_tape.Event {
  let assert Ok(clocks) = finance_tape.clocks(Some(1), Some(2), 3)
  let assert Ok(value) =
    finance_tape.event(
      event_id: event_id,
      trade_id: trade_id,
      kind: kind,
      price: price,
      size: size,
      condition_codes: conditions,
      venue_lexeme: venue,
      clocks: clocks,
      sequence: finance_tape.Sequenced("ticker", sequence),
      raw_receipt_hash: sha(hash_a),
    )
  value
}

fn decimal_value(value: String) -> decimal.Decimal {
  let assert Ok(value) = decimal.parse(value)
  value
}

fn instant(value: Int) -> time.Instant {
  let assert Ok(value) = time.instant(value)
  value
}

fn sha(value: String) -> identity.Sha256 {
  let assert Ok(value) = identity.sha256(value)
  value
}
