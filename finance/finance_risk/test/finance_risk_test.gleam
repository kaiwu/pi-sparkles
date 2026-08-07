import finance_core/decimal
import finance_core/time
import finance_provenance/identity
import finance_risk
import finance_risk/bound
import finance_risk/calculation
import finance_risk/cost
import finance_risk/fact
import finance_risk/heat
import finance_risk/receipt
import finance_risk/request
import finance_track
import gleam/int as gleam_int
import gleam/list
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn package_is_experimental_test() {
  finance_risk.status() |> should.equal(finance_risk.Experimental)
}

pub fn source_and_conflict_boundaries_are_validated_test() {
  fact.source(
    fact.CallerDeclared,
    hash("a"),
    instant(1),
    instant(2),
    " CNY",
    "currency",
    "100.00",
    "account:A",
    [],
  )
  |> should.equal(Error(fact.InvalidText("currency")))
  fact.conflicting([]) |> should.equal(Error(fact.EmptyConflict))
}

pub fn rounding_requires_nonnegative_ordered_scales_test() {
  calculation.rounding(4, 2, decimal.HalfUp)
  |> should.equal(Error(calculation.InvalidScale))
}

pub fn planned_loss_returns_exact_positive_negative_and_zero_values_test() {
  let positive =
    calculation.planned_loss_per_unit(
      "planned_loss",
      decimal_fact("10.91", "CNY", "currency_per_share", "a"),
      decimal_fact("10.55", "CNY", "currency_per_share", "b"),
      rounding2(),
    )
  expression_lexeme(positive) |> should.equal("0.36")

  let negative =
    calculation.planned_loss_per_unit(
      "planned_loss",
      decimal_fact("10.00", "CNY", "currency_per_share", "a"),
      decimal_fact("10.50", "CNY", "currency_per_share", "b"),
      rounding2(),
    )
  expression_lexeme(negative) |> should.equal("-0.50")

  let zero =
    calculation.planned_loss_per_unit(
      "planned_loss",
      decimal_fact("10.00", "CNY", "currency_per_share", "a"),
      decimal_fact("10.00", "CNY", "currency_per_share", "b"),
      rounding2(),
    )
  expression_lexeme(zero) |> should.equal("0.00")
}

pub fn llm_selected_fraction_budget_is_calculated_without_a_default_test() {
  let amount =
    calculation.fraction_amount(
      "risk_budget",
      "net_liquidation_value",
      decimal_fact("100000.00", "CNY", "currency", "a"),
      decimal_fact("0.02", "N/A", "dimensionless", "b"),
      rounding2(),
    )
  expression_lexeme(amount) |> should.equal("2000.00")
}

pub fn stop_budget_bound_projects_onto_supplied_cn_grid_test() {
  let loss = planned_loss()
  let value =
    quantity_bound(
      "stop_bound",
      "stop_budget_bound_v1",
      decimal_fact("2000.00", "CNY", "currency", "c"),
      loss,
      known_grid(100, 100, "d"),
    )
  expression_lexeme(bound.raw(value)) |> should.equal("5555.555556")
  bound.whole_share_projection(value)
  |> should.equal(bound.Projected(5555, 1, 1, bound.FloorToIncrement))
  bound.grid_projection(value)
  |> should.equal(bound.Projected(5500, 100, 100, bound.FloorToIncrement))
}

pub fn different_declared_fraction_changes_the_bound_test() {
  let budget =
    calculation.fraction_amount(
      "risk_budget",
      "net_liquidation_value",
      decimal_fact("100000.00", "CNY", "currency", "a"),
      decimal_fact("0.015", "N/A", "dimensionless", "b"),
      rounding2(),
    )
  let assert calculation.Calculated(_, _, amount, _, _, _, _, _) = budget
  let value =
    quantity_bound(
      "stop_bound",
      "stop_budget_bound_v1",
      decimal_fact_from_value("1500.00", amount, "CNY", "currency", "e"),
      planned_loss(),
      known_grid(100, 100, "d"),
    )
  bound.grid_projection(value)
  |> should.equal(bound.Projected(4100, 100, 100, bound.FloorToIncrement))
}

pub fn gap_scenario_is_an_independent_requested_branch_test() {
  let loss =
    calculation.gap_loss_per_unit(
      "gap_loss",
      decimal_fact("10.91", "CNY", "currency_per_share", "a"),
      decimal_fact("9.819", "CNY", "currency_per_share", "b"),
      rounding3(),
    )
  expression_lexeme(loss) |> should.equal("1.091")
  let value =
    bound.quantity_bound(
      "gap_bound",
      "gap_budget_bound_v1",
      "declared_gap_budget",
      decimal_fact("2000.00", "CNY", "currency", "c"),
      loss,
      known_grid(100, 100, "d"),
      rounding3(),
    )
  bound.grid_projection(value)
  |> should.equal(bound.Projected(1800, 100, 100, bound.FloorToIncrement))
}

pub fn unknown_gap_leaves_stop_bound_available_test() {
  let gap_loss =
    calculation.gap_loss_per_unit(
      "gap_loss",
      decimal_fact("10.91", "CNY", "currency_per_share", "a"),
      fact.Unknown(
        source("", "CNY", "currency_per_share", "b"),
        "open_ended_gap_loss",
      ),
      rounding2(),
    )
  let assert calculation.Unperformed(_, _, reason, _) = gap_loss
  reason |> string.contains("gap_open_price=unknown") |> should.be_true
  bound.grid_projection(quantity_bound(
    "stop_bound",
    "stop_budget_bound_v1",
    decimal_fact("2000.00", "CNY", "currency", "c"),
    planned_loss(),
    known_grid(100, 100, "d"),
  ))
  |> should.equal(bound.Projected(5500, 100, 100, bound.FloorToIncrement))
}

pub fn notional_and_cash_bounds_are_returned_independently_test() {
  let entry =
    calculation.fact_value(
      "entry",
      "desired_entry_value_v1",
      "desired_entry",
      decimal_fact("10.91", "CNY", "currency_per_share", "a"),
      "currency_per_share",
      rounding2(),
    )
  let notional =
    quantity_bound(
      "notional_bound",
      "notional_ceiling_bound_v1",
      decimal_fact("50000.00", "CNY", "currency", "b"),
      entry,
      known_grid(100, 100, "d"),
    )
  let cash =
    quantity_bound(
      "cash_bound",
      "cash_ceiling_bound_v1",
      decimal_fact("30000.00", "CNY", "currency", "c"),
      entry,
      known_grid(100, 100, "d"),
    )
  bound.grid_projection(notional)
  |> should.equal(bound.Projected(4500, 100, 100, bound.FloorToIncrement))
  bound.grid_projection(cash)
  |> should.equal(bound.Projected(2700, 100, 100, bound.FloorToIncrement))
}

pub fn unknown_grid_retains_raw_and_whole_share_bounds_test() {
  let value =
    quantity_bound(
      "stop_bound",
      "stop_budget_bound_v1",
      decimal_fact("2000.00", "CNY", "currency", "c"),
      planned_loss(),
      fact.Unknown(
        source("", "N/A", "shares", "d"),
        "HK board lot not obtained",
      ),
    )
  expression_lexeme(bound.raw(value)) |> should.equal("5555.555556")
  bound.whole_share_projection(value)
  |> should.equal(bound.Projected(5555, 1, 1, bound.FloorToIncrement))
  let assert bound.ProjectionUnperformed(reason) = bound.grid_projection(value)
  reason |> string.contains("missing_trade_unit_fact") |> should.be_true
}

pub fn requested_intersection_reports_the_tightest_projected_bounds_test() {
  let stop =
    quantity_bound(
      "stop_bound",
      "stop_budget_bound_v1",
      decimal_fact("2000.00", "CNY", "currency", "a"),
      planned_loss(),
      known_grid(100, 100, "b"),
    )
  let entry =
    calculation.fact_value(
      "entry",
      "desired_entry_value_v1",
      "desired_entry",
      decimal_fact("10.91", "CNY", "currency_per_share", "c"),
      "currency_per_share",
      rounding2(),
    )
  let cash =
    quantity_bound(
      "cash_bound",
      "cash_ceiling_bound_v1",
      decimal_fact("30000.00", "CNY", "currency", "d"),
      entry,
      known_grid(100, 100, "b"),
    )
  let intersection = bound.requested_intersection("intersection", [stop, cash])
  bound.intersection_value(intersection)
  |> should.equal(bound.IntersectionCalculated(2700, ["cash_bound"]))
}

pub fn no_positive_grid_point_is_a_mechanical_zero_test() {
  let loss =
    calculation.fact_value(
      "loss",
      "supplied_loss_per_unit_v1",
      "loss_per_unit",
      decimal_fact("1.00", "CNY", "currency_per_share", "a"),
      "currency_per_share",
      rounding2(),
    )
  let small =
    quantity_bound(
      "small_bound",
      "declared_budget_bound_v1",
      decimal_fact("43.00", "CNY", "currency", "b"),
      loss,
      known_grid(100, 100, "c"),
    )
  bound.grid_projection(small)
  |> should.equal(bound.Projected(0, 100, 100, bound.FloorToIncrement))
  let intersection = bound.requested_intersection("intersection", [small])
  bound.intersection_value(intersection)
  |> should.equal(bound.IntersectionCalculated(0, ["small_bound"]))
}

pub fn portfolio_heat_preserves_ordered_position_contributions_test() {
  let current =
    heat.planned_stop_v1(
      "current_heat",
      "CNY",
      [
        position("P1", 2000, "10.50", "10.20", "a"),
        position("P2", 100, "1850.00", "1800.00", "b"),
      ],
      rounding2(),
    )
  expression_lexeme(heat.total(current)) |> should.equal("5600.00")
  current
  |> heat.contributions
  |> list.map(fn(value) {
    value |> heat.contribution_expression |> expression_lexeme
  })
  |> should.equal(["600.00", "5000.00"])
}

pub fn remaining_heat_can_be_negative_without_a_verdict_test() {
  let current =
    heat.planned_stop_v1(
      "current_heat",
      "CNY",
      [
        position("P1", 2000, "10.50", "10.20", "a"),
        position("P2", 100, "1850.00", "1800.00", "b"),
      ],
      rounding2(),
    )
  let proposed =
    heat.planned_stop_v1(
      "proposed_heat",
      "CNY",
      [position("proposed", 5500, "10.91", "10.55", "c")],
      rounding2(),
    )
  heat.remaining(
    "remaining_heat",
    decimal_fact("6000.00", "CNY", "currency", "d"),
    current,
    proposed,
    rounding2(),
  )
  |> expression_lexeme
  |> should.equal("-1580.00")
}

pub fn unknown_cost_component_retains_the_known_subtotal_test() {
  let quantity = int_fact(5500, "shares", "a")
  let price = decimal_fact("10.91", "CNY", "currency_per_share", "b")
  let estimate =
    cost.one_way(
      "buy_cost",
      cost.Buy,
      "CNY",
      quantity,
      price,
      [
        cost.rate(
          "commission",
          cost.Buy,
          decimal_fact("0.00025", "N/A", "dimensionless", "c"),
        ),
        cost.rate(
          "slippage",
          cost.Buy,
          fact.Unknown(source("", "N/A", "dimensionless", "d"), "not supplied"),
        ),
      ],
      rounding2(),
    )
  estimate |> cost.known_subtotal |> expression_lexeme |> should.equal("15.00")
  let assert calculation.Unperformed(_, _, reason, _) = cost.total(estimate)
  reason |> string.contains("slippage") |> should.be_true
}

pub fn conflicting_equity_is_unperformed_and_alternatives_are_retained_test() {
  let first =
    fact.Sourced(
      decimal_value("100000.00"),
      source("100000.00", "CNY", "currency", "a"),
    )
  let second =
    fact.Sourced(
      decimal_value("100500.00"),
      source("100500.00", "CNY", "currency", "b"),
    )
  let assert Ok(conflict) = fact.conflicting([first, second])
  let amount =
    calculation.fraction_amount(
      "risk_budget",
      "net_liquidation_value",
      conflict,
      decimal_fact("0.02", "N/A", "dimensionless", "c"),
      rounding2(),
    )
  let assert calculation.Unperformed(_, _, reason, operands) = amount
  reason
  |> string.contains("net_liquidation_value=conflicting")
  |> should.be_true
  let assert [calculation.Operand(_, "conflicting", references, _, _, _, _), _] =
    operands
  list.length(references) |> should.equal(2)
}

pub fn request_receipts_are_content_bound_and_non_self_referential_test() {
  let first =
    risk_request([operation("stop_bound", "stop_budget_bound_v1")], [
      request.input_reference(
        "entry",
        decimal_fact("10.91", "CNY", "currency_per_share", "a"),
      ),
      request.input_reference(
        "fraction",
        decimal_fact("0.02", "N/A", "dimensionless", "b"),
      ),
    ])
  let second =
    risk_request([operation("stop_bound", "stop_budget_bound_v1")], [
      request.input_reference(
        "entry",
        decimal_fact("10.91", "CNY", "currency_per_share", "a"),
      ),
      request.input_reference(
        "fraction",
        decimal_fact("0.015", "N/A", "dimensionless", "b"),
      ),
    ])
  let assert Ok(first_receipt) = receipt.request_receipt(first)
  let assert Ok(second_receipt) = receipt.request_receipt(second)
  receipt.verify(first_receipt) |> should.be_true
  receipt.canonical_content_hash(first_receipt)
  |> should.not_equal(receipt.canonical_content_hash(second_receipt))
  receipt.payload_text(first_receipt)
  |> string.contains("canonical_content_hash")
  |> should.be_false
}

pub fn semantic_receipt_is_deterministic_and_contains_no_plugin_verdict_test() {
  let request_value =
    risk_request([operation("stop_bound", "stop_budget_bound_v1")], [
      request.input_reference(
        "entry",
        decimal_fact("10.91", "CNY", "currency_per_share", "a"),
      ),
      request.input_reference(
        "stop",
        decimal_fact("10.55", "CNY", "currency_per_share", "b"),
      ),
      request.input_reference(
        "budget",
        decimal_fact("2000.00", "CNY", "currency", "c"),
      ),
      request.input_reference("grid", known_grid(100, 100, "d")),
    ])
  let result =
    quantity_bound(
      "stop_bound",
      "stop_budget_bound_v1",
      decimal_fact("2000.00", "CNY", "currency", "c"),
      planned_loss(),
      known_grid(100, 100, "d"),
    )
  let items = [receipt.BoundResult(result)]
  let assert Ok(first) = receipt.semantic_result_receipt(request_value, items)
  let assert Ok(second) = receipt.semantic_result_receipt(request_value, items)
  receipt.canonical_content_hash(first)
  |> should.equal(receipt.canonical_content_hash(second))
  receipt.verify(first) |> should.be_true
  let encoded = receipt.encode(first)
  [
    "\"verdict\"",
    "\"recommended_size\"",
    "\"safe\"",
    "\"accepted\"",
    "\"rejected\"",
    "\"next_action\"",
    "\"do_not_trade\"",
  ]
  |> list.each(fn(forbidden) {
    encoded |> string.contains(forbidden) |> should.be_false
  })
}

pub fn semantic_receipt_rejects_an_unrequested_result_mechanically_test() {
  let request_value =
    risk_request(
      [operation("planned_loss", "long_planned_loss_per_unit_v1")],
      [],
    )
  receipt.semantic_result_receipt(request_value, [
    receipt.ExpressionResult(calculation.planned_loss_per_unit(
      "other",
      decimal_fact("10.91", "CNY", "currency_per_share", "a"),
      decimal_fact("10.55", "CNY", "currency_per_share", "b"),
      rounding2(),
    )),
  ])
  |> should.equal(Error(receipt.ResultNotRequested("other")))
}

fn planned_loss() -> calculation.Expression {
  calculation.planned_loss_per_unit(
    "planned_loss",
    decimal_fact("10.91", "CNY", "currency_per_share", "a"),
    decimal_fact("10.55", "CNY", "currency_per_share", "b"),
    rounding2(),
  )
}

fn quantity_bound(
  id: String,
  formula: String,
  numerator: fact.Fact(decimal.Decimal),
  denominator: calculation.Expression,
  grid: fact.Fact(bound.TradeUnit),
) -> bound.Bound {
  bound.quantity_bound(
    id,
    formula,
    "declared_ceiling",
    numerator,
    denominator,
    grid,
    rounding2(),
  )
}

fn known_grid(
  minimum: Int,
  increment: Int,
  marker: String,
) -> fact.Fact(bound.TradeUnit) {
  let assert Ok(value) = bound.trade_unit(minimum, increment)
  fact.known(
    value,
    source(
      int_text(minimum) <> "x" <> int_text(increment),
      "N/A",
      "shares",
      marker,
    ),
  )
}

fn position(
  id: String,
  quantity: Int,
  entry: String,
  stop: String,
  marker: String,
) -> heat.Position {
  let assert Ok(value) =
    heat.position(
      id,
      "account:A",
      finance_track.Cn,
      "CNE000000001",
      int_fact(quantity, "shares", marker),
      decimal_fact(entry, "CNY", "currency_per_share", marker),
      decimal_fact(stop, "CNY", "currency_per_share", marker),
      "CNY",
      hash(marker),
    )
  value
}

fn decimal_fact(
  lexeme: String,
  currency: String,
  unit: String,
  marker: String,
) -> fact.Fact(decimal.Decimal) {
  decimal_fact_from_value(lexeme, decimal_value(lexeme), currency, unit, marker)
}

fn decimal_fact_from_value(
  lexeme: String,
  value: decimal.Decimal,
  currency: String,
  unit: String,
  marker: String,
) -> fact.Fact(decimal.Decimal) {
  fact.known(value, source(lexeme, currency, unit, marker))
}

fn int_fact(value: Int, unit: String, marker: String) -> fact.Fact(Int) {
  fact.known(value, source(int_text(value), "N/A", unit, marker))
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

fn risk_request(
  operations: List(request.OperationSpec),
  inputs: List(request.InputReference),
) -> request.Request {
  let assert Ok(context) =
    request.context(
      "account:A",
      "portfolio:A",
      finance_track.Cn,
      "CNE000000001",
      instant(10),
      "CNY",
      [identity.evidence_id(hash("e"))],
    )
  let assert Ok(value) =
    request.request(
      hash("f"),
      context,
      operations,
      inputs,
      ["declared_risk_budget"],
      [],
      [],
      bound.FloorToIncrement,
      rounding2(),
      request.NativeCurrency,
      request.AllBranches,
      ["ordered_positions_as_supplied"],
      ["receipt_handle"],
      request.ExecutionBudgets(64, 32),
      [
        "drill_input_facts",
        "drill_formula",
        "project_bound_onto_grid",
        "request_intersection",
        "supply_fact",
      ],
    )
  value
}

fn operation(id: String, formula: String) -> request.OperationSpec {
  let assert Ok(value) = request.operation(id, formula, [], hash("f"), [])
  value
}

fn expression_lexeme(value: calculation.Expression) -> String {
  let assert calculation.Calculated(_, _, _, lexeme, _, _, _, _) = value
  lexeme
}

fn rounding2() -> calculation.RoundingSpec {
  let assert Ok(value) = calculation.rounding(2, 6, decimal.HalfUp)
  value
}

fn rounding3() -> calculation.RoundingSpec {
  let assert Ok(value) = calculation.rounding(3, 6, decimal.HalfUp)
  value
}

fn decimal_value(value: String) -> decimal.Decimal {
  let assert Ok(result) = decimal.parse(value)
  result
}

fn hash(marker: String) -> identity.Sha256 {
  let assert Ok(value) = marker |> string.repeat(times: 64) |> identity.sha256
  value
}

fn instant(value: Int) -> time.Instant {
  let assert Ok(result) = time.instant(value)
  result
}

fn int_text(value: Int) -> String {
  gleam_int.to_string(value)
}
