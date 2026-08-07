import finance_core/decimal
import finance_core/time
import finance_execution
import finance_execution/calculation
import finance_execution/capability
import finance_execution/fact
import finance_execution/fill
import finance_execution/instruction
import finance_execution/lifecycle
import finance_execution/receipt
import finance_execution/request
import finance_execution/session
import finance_execution/simulation
import finance_provenance/hash as provenance_hash
import finance_provenance/identity
import finance_track
import gleam/list
import gleam/option.{None}
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn package_is_experimental_test() {
  finance_execution.status() |> should.equal(finance_execution.Experimental)
}

pub fn execution_fact_states_retain_sources_and_not_applicable_test() {
  let source_value = source("", "N/A", "capability", "a")
  fact.NotApplicable(source_value, "field does not apply")
  |> fact.state_name
  |> should.equal("not_applicable")
  fact.conflicting([]) |> should.equal(Error(fact.EmptyConflict))
}

pub fn desired_instruction_requires_mechanical_identity_and_quantity_test() {
  instruction.desired(
    "I1",
    hash("a"),
    finance_track.Cn,
    "CNE000000001",
    "XSHG",
    "account:A",
    "CNY",
    instruction.Buy,
    None,
    decimal_value("0"),
    instruction.Shares,
    instruction.Limit(decimal_value("10.91")),
    instruction.Day,
    None,
    None,
    None,
    "Asia/Shanghai",
    [],
    [],
    [hash("b")],
    instruction.KnownAlternatives([]),
  )
  |> should.equal(Error(instruction.NonPositiveQuantity))

  instruction.desired(
    "I1",
    hash("a"),
    finance_track.Cn,
    "CNE000000001",
    "XSHG",
    "account:A",
    "CNY",
    instruction.Buy,
    None,
    decimal_value("1000"),
    instruction.Shares,
    instruction.Limit(decimal_value("10.91")),
    instruction.Day,
    None,
    None,
    None,
    "Asia/Shanghai",
    [],
    [],
    [],
    instruction.KnownAlternatives([]),
  )
  |> should.equal(Error(instruction.MissingAccountReference))
}

pub fn desired_behavior_is_preserved_without_broker_encoding_test() {
  let value = desired_instruction()
  instruction.order_behavior(value)
  |> should.equal(instruction.Limit(decimal_value("10.91")))
  instruction.track(value) |> should.equal(finance_track.Cn)
  instruction.capability_references(value) |> should.equal([hash("c")])
}

pub fn conflicting_capabilities_remain_branches_test() {
  let first =
    fact.Sourced(
      capability_value([instruction.Day, instruction.Gtc]),
      source("A", "N/A", "capability", "a"),
    )
  let second =
    fact.Sourced(
      capability_value([instruction.Day]),
      source("B", "N/A", "capability", "b"),
    )
  let assert Ok(value) = fact.conflicting([first, second])
  fact.state_name(value) |> should.equal("conflicting")
  value |> fact.fact_sources |> list.length |> should.equal(2)
}

pub fn visible_depth_buy_sweep_matches_session_fixture_test() {
  let result = marketable_buy_sweep()
  result
  |> simulation.filled_quantity
  |> decimal.to_string
  |> should.equal("700")
  result
  |> simulation.remaining_quantity
  |> decimal.to_string
  |> should.equal("300")
  simulation.fill_notional_lexeme(result) |> should.equal("7633.0000")
  simulation.weighted_fill_price(result)
  |> should.equal(simulation.WeightedPriceCalculated(
    decimal_value("10.9043"),
    "10.9043",
  ))
  simulation.depth_exhausted(result) |> should.be_false
  simulation.stopped_by_limit(result) |> should.be_true
  simulation.result_kind(result) |> should.equal(simulation.Hypothetical)
}

pub fn visible_depth_remainder_is_unknown_beyond_exhausted_snapshot_test() {
  let snapshot =
    simulation.depth_snapshot(hash("s"), [], [level("10.90", "100")])
  let assert Ok(result) =
    simulation.visible_depth_sweep(
      snapshot,
      instruction.Buy,
      decimal_value("10.91"),
      decimal_value("1000"),
      1,
      decimal_value("10.91"),
      4,
      decimal.HalfUp,
    )
  simulation.depth_exhausted(result) |> should.be_true
  simulation.sweep_stop(result) |> should.equal(simulation.DepthBudgetExhausted)
  result
  |> simulation.remaining_quantity
  |> decimal.to_string
  |> should.equal("900")
}

pub fn zero_visible_fill_leaves_weighted_price_unperformed_test() {
  let snapshot =
    simulation.depth_snapshot(hash("s"), [], [level("10.92", "100")])
  let assert Ok(result) =
    simulation.visible_depth_sweep(
      snapshot,
      instruction.Buy,
      decimal_value("10.91"),
      decimal_value("100"),
      1,
      decimal_value("10.91"),
      4,
      decimal.HalfUp,
    )
  simulation.weighted_fill_price(result)
  |> should.equal(simulation.WeightedPriceUnperformed("zero_filled_quantity"))
}

pub fn sell_sweep_consumes_only_bids_at_or_above_limit_test() {
  let snapshot =
    simulation.depth_snapshot(
      hash("s"),
      [level("11.51", "40"), level("11.50", "30"), level("11.49", "50")],
      [],
    )
  let assert Ok(result) =
    simulation.visible_depth_sweep(
      snapshot,
      instruction.Sell,
      decimal_value("11.50"),
      decimal_value("100"),
      3,
      decimal_value("11.50"),
      4,
      decimal.HalfUp,
    )
  result
  |> simulation.filled_quantity
  |> decimal.to_string
  |> should.equal("70")
  simulation.stopped_by_limit(result) |> should.be_true
}

pub fn daily_bar_limit_touch_returns_fill_and_non_fill_branches_test() {
  let bar = daily_bar("11.20", "11.60", "11.15", "11.40")
  let result =
    simulation.limit_possible_paths(
      bar,
      instruction.Sell,
      decimal_value("11.50"),
    )
  result
  |> simulation.branches
  |> list.map(fn(value) {
    let simulation.SimulationBranch(_, outcome, _, _) = value
    outcome
  })
  |> should.equal([simulation.CompatibleFill, simulation.CompatibleNonFill])
}

pub fn daily_bar_stop_and_target_retains_all_ordering_branches_test() {
  let bar = daily_bar("10.80", "12.30", "9.80", "11.00")
  let result =
    simulation.stop_target_possible_paths(
      bar,
      decimal_value("10.00"),
      decimal_value("12.00"),
    )
  result
  |> simulation.branches
  |> list.map(fn(value) {
    let simulation.SimulationBranch(_, outcome, _, _) = value
    outcome
  })
  |> should.equal([
    simulation.StopTriggeredFirst,
    simulation.TargetReachedFirst,
    simulation.UnknownOrdering,
  ])
}

pub fn fill_rejects_a_source_lexeme_mismatch_test() {
  fill.fill(
    "F1",
    None,
    None,
    "I1",
    "CNE000000001",
    "XSHG",
    "account:A",
    instruction.Buy,
    decimal_value("300"),
    "301",
    "shares",
    decimal_value("10.90"),
    "10.90",
    "CNY",
    instant(1),
    fill.ObservedBrokerReceipt,
    hash("a"),
    hash("b"),
    "account",
    "private-use",
    [identity.evidence_id(hash("e"))],
    [],
    [],
  )
  |> should.equal(Error(fill.QuantityLexemeMismatch))
}

pub fn observed_partial_fill_aggregate_matches_session_fixture_test() {
  let assert Ok(value) =
    fill.aggregate(
      [
        observed_fill("F1", "300", "10.90", 1, "a"),
        observed_fill("F2", "400", "10.91", 2, "b"),
        observed_fill("F3", "300", "10.89", 3, "c"),
      ],
      4,
      decimal.HalfUp,
    )
  fill.cumulative_quantity(value)
  |> should.equal(fill.AggregateCalculated(decimal_value("1000"), "1000.0000"))
  fill.total_notional(value)
  |> should.equal(fill.AggregateCalculated(decimal_value("10901"), "10901.0000"))
  fill.weighted_fill_price(value)
  |> should.equal(fill.AggregateCalculated(decimal_value("10.901"), "10.9010"))
  fill.aggregate_result_kind(value) |> should.equal(fill.ObservedBrokerReceipt)
}

pub fn fills_in_different_currencies_are_not_aggregated_test() {
  let first = observed_fill("F1", "300", "10.90", 1, "a")
  let second = fill_with_currency("F2", "300", "10.90", "HKD", 2, "b")
  fill.aggregate([first, second], 4, decimal.HalfUp)
  |> should.equal(Error("incompatible_fill_identity_currency_unit_side_or_kind"))
}

pub fn cancel_fill_race_preserves_all_events_and_external_state_test() {
  let events = [
    lifecycle_event("E1", 1, lifecycle.CancelRequested, "a"),
    lifecycle_event(
      "E2",
      2,
      lifecycle.PartiallyFilled(observed_fill("F1", "500", "10.91", 2, "b")),
      "b",
    ),
    lifecycle_event("E3", 3, lifecycle.CancelAcknowledged, "c"),
  ]
  let assert Ok(value) =
    lifecycle.fold("I1", decimal_value("1000"), events, 4, decimal.HalfUp)
  value |> lifecycle.ordered_events |> list.length |> should.equal(3)
  lifecycle.state(value) |> should.equal(lifecycle.CancelledState)
  value
  |> lifecycle.cumulative_filled
  |> decimal.to_string
  |> should.equal("500")
  value
  |> lifecycle.remaining_quantity
  |> decimal.to_string
  |> should.equal("500")
  lifecycle.fill_after_cancel_request(value) |> should.be_true
}

pub fn broker_rejection_is_preserved_as_exact_external_fact_test() {
  let event =
    lifecycle_event(
      "E1",
      1,
      lifecycle.BrokerRejected("INSUFFICIENT_FUNDS", "Buying power exceeded"),
      "r",
    )
  let assert Ok(value) =
    lifecycle.fold("I1", decimal_value("1000"), [event], 2, decimal.HalfUp)
  lifecycle.state(value)
  |> should.equal(lifecycle.BrokerRejectedState(
    "INSUFFICIENT_FUNDS",
    "Buying power exceeded",
  ))
}

pub fn lifecycle_batch_and_incremental_folds_are_equal_test() {
  let events = [
    lifecycle_event("E1", 1, lifecycle.Working, "a"),
    lifecycle_event(
      "E2",
      2,
      lifecycle.PartiallyFilled(observed_fill("F1", "300", "10.90", 2, "b")),
      "b",
    ),
    lifecycle_event(
      "E3",
      3,
      lifecycle.PartiallyFilled(observed_fill("F2", "400", "10.91", 3, "c")),
      "c",
    ),
    lifecycle_event("E4", 4, lifecycle.FullyFilled([]), "d"),
  ]
  let assert Ok(batch) =
    lifecycle.fold("I1", decimal_value("700"), events, 4, decimal.HalfUp)
  let incremental =
    list.fold(
      events,
      lifecycle.initial("I1", decimal_value("700")),
      fn(state, event) { lifecycle.apply(state, event, 4, decimal.HalfUp) },
    )
  lifecycle.state(batch) |> should.equal(lifecycle.state(incremental))
  lifecycle.cumulative_filled(batch)
  |> should.equal(lifecycle.cumulative_filled(incremental))
  lifecycle.ordered_events(batch)
  |> should.equal(lifecycle.ordered_events(incremental))
}

pub fn session_comparison_returns_boolean_or_unperformed_fact_test() {
  let intervals =
    fact.known(
      [session.PhaseInterval("regular", instant(100), instant(200), hash("a"))],
      source("regular", "N/A", "phase_intervals", "b"),
    )
  session.timestamp_in_phase(instant(150), "regular", intervals)
  |> should.equal(session.Compared(
    instant(150),
    "regular",
    [session.PhaseInterval("regular", instant(100), instant(200), hash("a"))],
    True,
  ))
  session.timestamp_in_phase(
    instant(150),
    "regular",
    fact.Unknown(source("", "N/A", "phase_intervals", "c"), "calendar absent"),
  )
  |> should.equal(session.ComparisonUnperformed(
    instant(150),
    "regular",
    "unknown:calendar absent",
  ))
}

pub fn unknown_cost_retains_known_subtotal_and_unperformed_total_test() {
  let result =
    calculation.fill_cost_total(
      "costs",
      "CNY",
      decimal_fact("1000", "N/A", "shares", "q"),
      [
        calculation.CostComponent(
          "commission",
          decimal_fact("2.73", "CNY", "currency", "a"),
        ),
        calculation.CostComponent(
          "stamp",
          decimal_fact("5.46", "CNY", "currency", "b"),
        ),
        calculation.CostComponent(
          "slippage",
          fact.Unknown(source("", "CNY", "currency", "c"), "not supplied"),
        ),
      ],
      rounding5(),
    )
  calculation.known_subtotal(result)
  |> expression_lexeme
  |> should.equal("8.19000")
  calculation.known_cost_per_quantity(result)
  |> expression_lexeme
  |> should.equal("0.00819")
  let assert calculation.Unperformed(_, _, reason, _) =
    calculation.total_cost(result)
  reason |> string.contains("slippage") |> should.be_true
}

pub fn negative_slippage_is_returned_without_an_interpretive_label_test() {
  calculation.slippage_vs_limit(
    "slippage",
    instruction.Buy,
    decimal_fact("10.89", "CNY", "currency_per_share", "a"),
    decimal_fact("10.91", "CNY", "currency_per_share", "b"),
    calculation.FillMinusReference,
    rounding2(),
  )
  |> expression_lexeme
  |> should.equal("-0.02")
}

pub fn latency_requires_an_explicit_clock_relation_test() {
  let start = instant_fact(100, "a")
  let end = instant_fact(175, "b")
  calculation.latency(
    "ack_latency",
    "acknowledgement_latency_v1",
    start,
    end,
    calculation.SameClock,
  )
  |> expression_lexeme
  |> should.equal("75")
  let unknown =
    calculation.latency(
      "ack_latency",
      "acknowledgement_latency_v1",
      start,
      end,
      calculation.OffsetUnknown("not synchronized"),
    )
  let assert calculation.Unperformed(_, _, reason, _) = unknown
  reason |> string.contains("clock_offset_unknown") |> should.be_true
}

pub fn request_receipt_is_content_bound_and_non_self_referential_test() {
  let first = execution_request("10.91")
  let second = execution_request("10.90")
  let assert Ok(first_receipt) = receipt.request_receipt(first)
  let assert Ok(second_receipt) = receipt.request_receipt(second)
  receipt.verify(first_receipt) |> should.be_true
  receipt.canonical_content_hash(first_receipt)
  |> should.not_equal(receipt.canonical_content_hash(second_receipt))
  receipt.payload_text(first_receipt)
  |> string.contains("canonical_content_hash")
  |> should.be_false
}

pub fn semantic_receipt_is_deterministic_and_has_no_plugin_decision_test() {
  let request_value = execution_request("10.91")
  let items = [receipt.SweepResult("sweep", marketable_buy_sweep())]
  let assert Ok(first) = receipt.semantic_result_receipt(request_value, items)
  let assert Ok(second) = receipt.semantic_result_receipt(request_value, items)
  receipt.canonical_content_hash(first)
  |> should.equal(receipt.canonical_content_hash(second))
  receipt.verify(first) |> should.be_true
  let encoded = receipt.encode(first)
  [
    "\"verdict\"",
    "\"recommendation\"",
    "\"recommended_quantity\"",
    "\"should_submit\"",
    "\"next_action\"",
    "\"correctness\"",
    "consider raising limit",
  ]
  |> list.each(fn(forbidden) {
    encoded |> string.contains(forbidden) |> should.be_false
  })
}

pub fn semantic_receipt_rejects_unrequested_and_over_budget_results_test() {
  let request_value = execution_request("10.91")
  receipt.semantic_result_receipt(request_value, [
    receipt.SweepResult("other", marketable_buy_sweep()),
  ])
  |> should.equal(Error(receipt.ResultNotRequested("other")))
}

fn marketable_buy_sweep() -> simulation.SweepResult {
  let snapshot =
    simulation.depth_snapshot(hash("s"), [], [
      level("10.90", "400"),
      level("10.91", "300"),
      level("10.92", "500"),
    ])
  let assert Ok(result) =
    simulation.visible_depth_sweep(
      snapshot,
      instruction.Buy,
      decimal_value("10.91"),
      decimal_value("1000"),
      3,
      decimal_value("10.91"),
      4,
      decimal.HalfUp,
    )
  result
}

fn level(price: String, quantity: String) -> simulation.DepthLevel {
  let assert Ok(value) =
    simulation.depth_level(
      decimal_value(price),
      price,
      decimal_value(quantity),
      quantity,
    )
  value
}

fn daily_bar(
  open: String,
  high: String,
  low: String,
  close: String,
) -> simulation.DailyBar {
  let assert Ok(value) =
    simulation.daily_bar(
      decimal_value(open),
      decimal_value(high),
      decimal_value(low),
      decimal_value(close),
    )
  value
}

fn desired_instruction() -> instruction.DesiredInstruction {
  desired_instruction_at("10.91")
}

fn desired_instruction_at(limit: String) -> instruction.DesiredInstruction {
  let assert Ok(value) =
    instruction.desired(
      "I1",
      hash("i"),
      finance_track.Cn,
      "CNE000000001",
      "XSHG",
      "account:A",
      "CNY",
      instruction.Buy,
      None,
      decimal_value("1000"),
      instruction.Shares,
      instruction.Limit(decimal_value(limit)),
      instruction.Day,
      None,
      None,
      None,
      "Asia/Shanghai",
      [hash("r")],
      [hash("c")],
      [hash("a")],
      instruction.KnownAlternatives([]),
    )
  value
}

fn capability_value(
  values: List(instruction.TimeInForce),
) -> capability.Capability {
  let assert Ok(value) =
    capability.capability(
      "broker:A",
      "account:A",
      finance_track.Cn,
      ["cash_equity"],
      ["XSHG"],
      ["regular"],
      [capability.NativeOrderType("LIMIT", ["price", "quantity"], [])],
      [instruction.Buy, instruction.Sell],
      values,
      [instruction.LastSale],
      bool_fact(True, "a"),
      bool_fact(True, "b"),
      fact.Unknown(source("", "N/A", "tick_handling", "c"), "not obtained"),
      fact.Unknown(source("", "N/A", "lot_handling", "d"), "not obtained"),
      "fixture-v1",
    )
  value
}

fn observed_fill(
  id: String,
  quantity: String,
  price: String,
  timestamp: Int,
  marker: String,
) -> fill.Fill {
  fill_with_currency(id, quantity, price, "CNY", timestamp, marker)
}

fn fill_with_currency(
  id: String,
  quantity: String,
  price: String,
  currency: String,
  timestamp: Int,
  marker: String,
) -> fill.Fill {
  let assert Ok(value) =
    fill.fill(
      id,
      None,
      None,
      "I1",
      "CNE000000001",
      "XSHG",
      "account:A",
      instruction.Buy,
      decimal_value(quantity),
      quantity,
      "shares",
      decimal_value(price),
      price,
      currency,
      instant(timestamp),
      fill.ObservedBrokerReceipt,
      hash(marker),
      hash(marker),
      "account",
      "private-use",
      [identity.evidence_id(hash("e"))],
      [],
      [],
    )
  value
}

fn lifecycle_event(
  id: String,
  timestamp: Int,
  kind: lifecycle.EventKind,
  marker: String,
) -> lifecycle.Event {
  let assert Ok(value) =
    lifecycle.event(id, "I1", instant(timestamp), hash(marker), kind)
  value
}

fn execution_request(limit: String) -> request.Request {
  let operation = operation("sweep", simulation.visible_depth_sweep_v1)
  let input = decimal_fact(limit, "CNY", "currency_per_share", "l")
  let assert Ok(value) =
    request.request(
      desired_instruction_at(limit),
      [operation],
      [request.input_reference("limit_price", input)],
      request.ReferenceSet(
        [hash("c")],
        [hash("r")],
        [hash("k")],
        [hash("m")],
        [],
        [],
        [],
        [],
        [],
      ),
      "regular",
      "2026-08-07T09:30:00+08:00",
      [#("model", simulation.visible_depth_sweep_v1)],
      [],
      [],
      [],
      [],
      rounding4(),
      "native",
      request.AllBranches,
      ["filled_quantity", "remaining_quantity", "weighted_fill_price"],
      request.Budgets(64, 8, 16, 32, 16, 100_000, 8),
      [
        "drill_desired_instruction",
        "drill_market_events",
        "drill_simulation_branch",
        "calculate_all_branches",
        "select_branch",
        "simulate",
        "supply_fact",
      ],
    )
  value
}

fn operation(id: String, variant: String) -> request.OperationSpec {
  let assert Ok(value) = request.operation(id, variant, [], hash("i"), [])
  value
}

fn decimal_fact(
  lexeme: String,
  currency: String,
  unit: String,
  marker: String,
) -> fact.Fact(decimal.Decimal) {
  fact.known(decimal_value(lexeme), source(lexeme, currency, unit, marker))
}

fn bool_fact(value: Bool, marker: String) -> fact.Fact(Bool) {
  fact.known(value, source("bool", "N/A", "boolean", marker))
}

fn instant_fact(value: Int, marker: String) -> fact.Fact(time.Instant) {
  fact.known(
    instant(value),
    source(string.inspect(value), "N/A", "unix_ms", marker),
  )
}

fn source(
  lexeme: String,
  currency: String,
  unit: String,
  marker: String,
) -> fact.Source {
  let assert Ok(value) =
    fact.source(
      fact.CallerDeclared,
      hash(marker),
      instant(1),
      instant(2),
      currency,
      unit,
      lexeme,
      "fixture",
      [],
    )
  value
}

fn rounding2() -> calculation.RoundingSpec {
  let assert Ok(value) = calculation.rounding(2, decimal.HalfUp)
  value
}

fn rounding4() -> calculation.RoundingSpec {
  let assert Ok(value) = calculation.rounding(4, decimal.HalfUp)
  value
}

fn rounding5() -> calculation.RoundingSpec {
  let assert Ok(value) = calculation.rounding(5, decimal.HalfUp)
  value
}

fn expression_lexeme(value: calculation.Expression) -> String {
  let assert calculation.Calculated(_, _, _, lexeme, _, _, _) = value
  lexeme
}

fn decimal_value(value: String) -> decimal.Decimal {
  let assert Ok(result) = decimal.parse(value)
  result
}

fn hash(marker: String) -> identity.Sha256 {
  let assert Ok(value) = provenance_hash.text(marker)
  value
}

fn instant(value: Int) -> time.Instant {
  let assert Ok(result) = time.instant(value)
  result
}
