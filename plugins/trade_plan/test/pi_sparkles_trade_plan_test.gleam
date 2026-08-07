import gleam/dynamic/decode as dynamic_decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit
import gleeunit/should
import pi_sparkles_trade_plan/decode
import pi_sparkles_trade_plan/domain

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn planned_loss_returns_positive_zero_and_negative_facts_test() {
  let assert Ok(positive) =
    domain.run_loss(loss_input("10.91", "10.55", "compact"))
  result_text(positive)
  |> string.contains("\"value\":\"0.36\"")
  |> should.be_true

  let assert Ok(zero) = domain.run_loss(loss_input("10.00", "10.00", "compact"))
  result_text(zero)
  |> string.contains("\"value\":\"0.00\"")
  |> should.be_true

  let assert Ok(negative) =
    domain.run_loss(loss_input("10.00", "10.50", "compact"))
  result_text(negative)
  |> string.contains("\"value\":\"-0.50\"")
  |> should.be_true
  let text = result_text(negative)
  text |> string.contains("\"decisionOwner\":\"llm\"") |> should.be_true
  text |> string.contains("\"pluginDecisionFields\":[]") |> should.be_true
}

pub fn unavailable_and_conflicting_operands_remain_unperformed_test() {
  let unknown =
    decode.DecimalFactInput(
      "unknown",
      None,
      Some(source("unknown", "CNY", "currency_per_share", "a")),
      Some("quote not supplied"),
      None,
      [],
    )
  let first =
    decode.DecimalSourcedInput(
      "10.55",
      source("10.55", "CNY", "currency_per_share", "b"),
    )
  let second =
    decode.DecimalSourcedInput(
      "10.56",
      source("10.56", "CNY", "currency_per_share", "c"),
    )
  let conflicting =
    decode.DecimalFactInput("conflicting", None, None, None, None, [
      first,
      second,
    ])
  let assert Ok(response) =
    domain.run_loss(decode.LossInput(
      common("compact", "cn", "CNY"),
      "planned_loss",
      unknown,
      conflicting,
    ))
  let text = result_text(response)
  text |> string.contains("\"state\":\"unperformed\"") |> should.be_true
  text |> string.contains("entry_price=unknown") |> should.be_true
  text |> string.contains("stop_price=conflicting") |> should.be_true
  text |> string.contains("\"unknownInputs\":1") |> should.be_true
  text |> string.contains("\"conflictingInputs\":1") |> should.be_true
  text |> string.contains(hash("b")) |> should.be_true
  text |> string.contains(hash("c")) |> should.be_true
}

pub fn not_obtained_and_decode_failure_lexemes_remain_visible_test() {
  let not_obtained =
    decode.DecimalFactInput(
      "not_obtained",
      None,
      Some(source("not-returned", "CNY", "currency_per_share", "a")),
      Some("custodian omitted field"),
      None,
      [],
    )
  let decode_failure =
    decode.DecimalFactInput(
      "decode_failure",
      None,
      Some(source("bad-price", "CNY", "currency_per_share", "b")),
      Some("invalid decimal token"),
      Some("bad-price"),
      [],
    )
  let assert Ok(response) =
    domain.run_loss(decode.LossInput(
      common("receipt", "cn", "CNY"),
      "planned_loss",
      not_obtained,
      decode_failure,
    ))
  let text = result_text(response)
  text |> string.contains("entry_price=not_obtained") |> should.be_true
  text |> string.contains("stop_price=decode_failure") |> should.be_true
  text |> string.contains("\"notObtainedInputs\":1") |> should.be_true
  text |> string.contains("\"decodeFailureInputs\":1") |> should.be_true
  text |> string.contains("bad-price") |> should.be_true
  text |> string.contains("custodian omitted field") |> should.be_true
}

pub fn independent_bounds_and_requested_intersection_are_visible_test() {
  let request =
    decode.BoundsInput(
      common("compact", "cn", "CNY"),
      [stop_bound("2000.00"), cash_bound("30000.00")],
      known_grid(100, 100, "d"),
      decode.IntersectionInput("requested", Some("requested_intersection"), [
        "stop_bound",
        "cash_bound",
      ]),
    )
  let assert Ok(response) = domain.run_bounds(request)
  let text = result_text(response)
  text |> string.contains("\"boundId\":\"stop_bound\"") |> should.be_true
  text |> string.contains("\"quantity\":5500") |> should.be_true
  text |> string.contains("\"boundId\":\"cash_bound\"") |> should.be_true
  text |> string.contains("\"quantity\":2700") |> should.be_true
  text
  |> string.contains("\"tightestBoundIds\":[\"cash_bound\"]")
  |> should.be_true
  text
  |> string.contains("\"selectedBoundIds\":[\"stop_bound\",\"cash_bound\"]")
  |> should.be_true
}

pub fn unknown_grid_preserves_raw_and_whole_share_bound_test() {
  let unknown_grid =
    decode.TradeUnitFactInput(
      "unknown",
      None,
      Some(source("not supplied", "N/A", "shares", "d")),
      Some("HK board lot not available"),
      None,
      [],
    )
  let request =
    decode.GridInput(
      common("compact", "hk", "HKD"),
      stop_bound_with_currency("2000.00", "HKD"),
      unknown_grid,
    )
  let assert Ok(response) = domain.run_grid(request)
  let text = result_text(response)
  text |> string.contains("\"value\":\"5555.555556\"") |> should.be_true
  text
  |> string.contains(
    "\"wholeShare\":{\"state\":\"projected\",\"quantity\":5555",
  )
  |> should.be_true
  text |> string.contains("missing_trade_unit_fact:unknown") |> should.be_true
}

pub fn focused_grid_projection_uses_exact_cn_hk_us_units_test() {
  let cases = [
    #("cn", "CNY", 100, 100, 5500),
    #("hk", "HKD", 500, 500, 5500),
    #("us", "USD", 1, 1, 5555),
  ]
  cases
  |> list.each(fn(value) {
    let #(track, currency, minimum, increment, expected) = value
    let assert Ok(response) =
      domain.run_grid(decode.GridInput(
        common("compact", track, currency),
        stop_bound_with_currency("2000.00", currency),
        known_grid(minimum, increment, "d"),
      ))
    result_text(response)
    |> string.contains(
      "\"gridProjected\":{\"state\":\"projected\",\"quantity\":"
      <> int.to_string(expected),
    )
    |> should.be_true
  })
}

pub fn compact_and_receipt_projections_share_semantic_identity_test() {
  let assert Ok(compact) =
    domain.run_loss(loss_input("10.91", "10.55", "compact"))
  let assert Ok(full) = domain.run_loss(loss_input("10.91", "10.55", "receipt"))
  semantic_handle(compact) |> should.equal(semantic_handle(full))
  result_text(compact)
  |> string.contains("semanticReceiptEnvelope")
  |> should.be_false
  let full_text = result_text(full)
  full_text |> string.contains("semanticReceiptEnvelope") |> should.be_true
  full_text
  |> string.contains("pi-sparkles/risk-calculation-receipt")
  |> should.be_true

  let assert Ok(changed) =
    domain.run_bounds(decode.BoundsInput(
      common("compact", "cn", "CNY"),
      [stop_bound("1500.00")],
      known_grid(100, 100, "d"),
      no_intersection(),
    ))
  semantic_handle(changed) |> should.not_equal(semantic_handle(compact))
}

pub fn intersection_rejects_unknown_and_duplicate_ids_test() {
  let base =
    decode.BoundsInput(
      common("compact", "cn", "CNY"),
      [stop_bound("2000.00")],
      known_grid(100, 100, "d"),
      decode.IntersectionInput("requested", Some("intersection"), ["missing"]),
    )
  case domain.run_bounds(base) {
    Error(domain.InvalidField("intersection.selectedBoundIds", _)) ->
      should.be_true(True)
    _ -> should.fail()
  }

  let duplicate =
    decode.BoundsInput(
      ..base,
      intersection: decode.IntersectionInput("requested", Some("intersection"), [
        "stop_bound",
        "stop_bound",
      ]),
    )
  case domain.run_bounds(duplicate) {
    Error(domain.InvalidField("intersection.selectedBoundIds", _)) ->
      should.be_true(True)
    _ -> should.fail()
  }
}

pub fn results_contain_no_plugin_verdict_or_quantity_choice_test() {
  let assert Ok(response) =
    domain.run_bounds(decode.BoundsInput(
      common("compact", "cn", "CNY"),
      [stop_bound("10.00")],
      known_grid(100, 100, "d"),
      decode.IntersectionInput("requested", Some("intersection"), ["stop_bound"]),
    ))
  let text = result_text(response)
  text |> string.contains("\"quantity\":0") |> should.be_true
  [
    "\"safe\"",
    "\"ready\"",
    "\"accepted\"",
    "\"rejected\"",
    "\"recommendedSize\"",
    "\"selectedQuantity\"",
    "\"nextAction\"",
    "\"verdict\"",
    "do_not_trade",
  ]
  |> list.each(fn(forbidden) {
    text |> string.contains(forbidden) |> should.be_false
  })
}

fn loss_input(
  entry: String,
  stop: String,
  projection: String,
) -> decode.LossInput {
  decode.LossInput(
    common(projection, "cn", "CNY"),
    "planned_loss",
    known_decimal(entry, "CNY", "currency_per_share", "a"),
    known_decimal(stop, "CNY", "currency_per_share", "b"),
  )
}

fn common(
  projection: String,
  track: String,
  currency: String,
) -> decode.CommonInput {
  decode.CommonInput(
    decode.ContextInput(
      hash("f"),
      "account:A",
      "portfolio:A",
      track,
      "listing:A",
      1_770_000_000_000,
      currency,
      [hash("e")],
    ),
    decode.RoundingInput("half_up", "final_only", 2, 6),
    decode.BranchPolicyInput("all_branches", None, None),
    10,
    10,
    projection,
  )
}

fn stop_bound(amount: String) -> decode.BoundInput {
  stop_bound_with_currency(amount, "CNY")
}

fn stop_bound_with_currency(
  amount: String,
  currency: String,
) -> decode.BoundInput {
  decode.BoundInput(
    "stop_bound",
    "stop_budget_bound_v1",
    "declared_stop_budget",
    known_decimal(amount, currency, "currency", "c"),
    decode.DenominatorInput(
      "long_planned_loss_per_unit_v1",
      None,
      None,
      None,
      None,
      Some(known_decimal("10.91", currency, "currency_per_share", "a")),
      Some(known_decimal("10.55", currency, "currency_per_share", "b")),
    ),
  )
}

fn cash_bound(amount: String) -> decode.BoundInput {
  decode.BoundInput(
    "cash_bound",
    "cash_ceiling_bound_v1",
    "available_cash",
    known_decimal(amount, "CNY", "currency", "9"),
    decode.DenominatorInput(
      "supplied_denominator_v1",
      Some("desired_entry"),
      Some("desired_entry_value_v1"),
      Some("currency_per_share"),
      Some(known_decimal("10.91", "CNY", "currency_per_share", "a")),
      None,
      None,
    ),
  )
}

fn known_decimal(
  value: String,
  currency: String,
  unit: String,
  marker: String,
) -> decode.DecimalFactInput {
  decode.DecimalFactInput(
    "known",
    Some(value),
    Some(source(value, currency, unit, marker)),
    None,
    None,
    [],
  )
}

fn known_grid(
  minimum: Int,
  increment: Int,
  marker: String,
) -> decode.TradeUnitFactInput {
  let lexeme = int.to_string(minimum) <> "x" <> int.to_string(increment)
  decode.TradeUnitFactInput(
    "known",
    Some(decode.TradeUnitValueInput(minimum, increment)),
    Some(source(lexeme, "N/A", "shares", marker)),
    None,
    None,
    [],
  )
}

fn source(
  lexeme: String,
  currency: String,
  unit: String,
  marker: String,
) -> decode.SourceInput {
  decode.SourceInput(
    "caller_declared",
    hash(marker),
    1_770_000_000_000,
    1_770_000_000_100,
    currency,
    unit,
    lexeme,
    "fixture",
    [],
  )
}

fn no_intersection() -> decode.IntersectionInput {
  decode.IntersectionInput("not_requested", None, [])
}

fn result_text(value: domain.Response) -> String {
  value |> domain.details |> json.to_string
}

fn semantic_handle(value: domain.Response) -> String {
  let value_decoder = {
    use value <- dynamic_decode.field(
      "semanticReceiptHandle",
      dynamic_decode.string,
    )
    dynamic_decode.success(value)
  }
  let assert Ok(value) = value |> result_text |> json.parse(value_decoder)
  value
}

fn hash(digit: String) -> String {
  string.repeat(digit, 64)
}
