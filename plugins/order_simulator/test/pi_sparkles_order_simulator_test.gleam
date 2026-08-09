import gleam/dynamic/decode as dynamic_decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit
import gleeunit/should
import pi_sparkles_order_simulator/decode
import pi_sparkles_order_simulator/domain

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn touched_buy_limit_returns_every_compatible_branch_test() {
  let assert Ok(response) = domain.run(simulation_input("compact"))
  let text = result_text(response)
  text |> string.contains("\"state\":\"performed\"") |> should.be_true
  text |> string.contains("\"resultKind\":\"hypothetical\"") |> should.be_true
  text |> string.contains("\"branchId\":\"compatible_fill\"") |> should.be_true
  text
  |> string.contains("\"branchId\":\"compatible_non_fill\"")
  |> should.be_true
  text
  |> string.contains("\"minimum\":\"11.15\",\"maximum\":\"11.2\"")
  |> should.be_true
  text |> string.contains("\"branches\":2") |> should.be_true
  text |> string.contains("\"decisionOwner\":\"llm\"") |> should.be_true
  text |> string.contains("\"pluginDecisionFields\":[]") |> should.be_true
}

pub fn untouched_sell_limit_returns_only_compatible_non_fill_test() {
  let base = simulation_input("compact")
  let input =
    decode.SimulationInput(
      ..base,
      instruction: instruction_input("us", "USD", "sell", "11.70"),
    )
  let assert Ok(response) = domain.run(input)
  let text = result_text(response)
  text |> string.contains("\"branches\":1") |> should.be_true
  text
  |> string.contains("the supplied bar did not reach the limit price")
  |> should.be_true
  text |> string.contains("\"branchId\":\"compatible_fill\"") |> should.be_false
}

pub fn unavailable_and_conflicting_bars_remain_unperformed_test() {
  let base = simulation_input("compact")
  let unknown =
    decode.BarFactInput(
      "unknown",
      None,
      Some(source("bar unavailable", "USD", "ohlc", "b")),
      Some("completed bar not supplied"),
      None,
      [],
    )
  let assert Ok(unknown_response) =
    domain.run(decode.SimulationInput(..base, bar: unknown))
  let unknown_text = result_text(unknown_response)
  unknown_text
  |> string.contains(
    "completed_daily_bar_unavailable:unknown:completed bar not supplied",
  )
  |> should.be_true
  unknown_text |> string.contains("\"unknownInputs\":1") |> should.be_true
  unknown_text |> string.contains("\"branches\":[]") |> should.be_true

  let conflicting =
    decode.BarFactInput("conflicting", None, None, None, None, [
      decode.BarSourcedInput(
        decode.BarValueInput("11.20", "11.60", "11.15", "11.40"),
        source("bar-a", "USD", "ohlc", "b"),
      ),
      decode.BarSourcedInput(
        decode.BarValueInput("11.21", "11.61", "11.14", "11.41"),
        source("bar-c", "USD", "ohlc", "c"),
      ),
    ])
  let assert Ok(conflict_response) =
    domain.run(decode.SimulationInput(..base, bar: conflicting))
  let conflict_text = result_text(conflict_response)
  conflict_text
  |> string.contains("conflicting_alternatives:2")
  |> should.be_true
  conflict_text |> string.contains("\"conflictingInputs\":1") |> should.be_true
  conflict_text |> string.contains(hash("b")) |> should.be_true
  conflict_text |> string.contains(hash("c")) |> should.be_true
}

pub fn caller_selected_capability_policy_controls_only_performance_test() {
  let base = simulation_input("compact")
  let unsupported = known_bool(False, "capability says no", "c")
  let assert Ok(recorded) =
    domain.run(
      decode.SimulationInput(..base, desired_order_supported: unsupported),
    )
  result_text(recorded)
  |> string.contains("\"state\":\"performed\"")
  |> should.be_true

  let strict_policy =
    decode.PolicyInput(
      ..base.policy,
      capability_policy: "require_known_true_v1",
    )
  let assert Ok(strict) =
    domain.run(
      decode.SimulationInput(
        ..base,
        desired_order_supported: unsupported,
        policy: strict_policy,
      ),
    )
  let strict_text = result_text(strict)
  strict_text
  |> string.contains(
    "desired_order_supported=false_under_require_known_true_v1",
  )
  |> should.be_true
  strict_text |> string.contains("\"branches\":0") |> should.be_true

  let unavailable =
    decode.BoolFactInput(
      "not_obtained",
      None,
      Some(source("not obtained", "N/A", "boolean", "c")),
      Some("broker capability receipt absent"),
      None,
      [],
    )
  let assert Ok(missing) =
    domain.run(
      decode.SimulationInput(
        ..base,
        desired_order_supported: unavailable,
        policy: strict_policy,
      ),
    )
  result_text(missing)
  |> string.contains("desired_order_support_unavailable:not_obtained")
  |> should.be_true
}

pub fn valid_but_unsupported_desired_behavior_is_explicitly_unperformed_test() {
  let base = simulation_input("compact")
  let market_instruction =
    decode.InstructionInput(
      ..base.instruction,
      order_behavior: decode.OrderBehaviorInput(
        "market",
        None,
        None,
        None,
        None,
        None,
        None,
        None,
      ),
    )
  let assert Ok(response) =
    domain.run(decode.SimulationInput(..base, instruction: market_instruction))
  let text = result_text(response)
  text
  |> string.contains("unsupported_desired_behavior_for_limit_touch_v1")
  |> should.be_true
  text |> string.contains("\"desiredBehavior\":\"market\"") |> should.be_true
  text |> string.contains("\"state\":\"performed\"") |> should.be_false
}

pub fn compact_and_receipt_projections_share_semantic_identity_test() {
  let compact_input = simulation_input("compact")
  let full_input =
    decode.SimulationInput(
      ..compact_input,
      policy: decode.PolicyInput(..compact_input.policy, projection: "receipt"),
    )
  let assert Ok(compact) = domain.run(compact_input)
  let assert Ok(full) = domain.run(full_input)
  semantic_handle(compact) |> should.equal(semantic_handle(full))
  result_text(compact)
  |> string.contains("semanticReceiptEnvelope")
  |> should.be_false
  let full_text = result_text(full)
  full_text |> string.contains("semanticReceiptEnvelope") |> should.be_true
  full_text
  |> string.contains("pi-sparkles/execution-information-receipt")
  |> should.be_true
  full_text
  |> string.contains("pi-sparkles/execution-information-request")
  |> should.be_true
}

pub fn invalid_geometry_and_core_budgets_fail_mechanically_test() {
  let base = simulation_input("compact")
  let invalid_bar = known_bar("11.20", "11.10", "11.15", "11.18", "b")
  case domain.run(decode.SimulationInput(..base, bar: invalid_bar)) {
    Error(domain.InvalidField("bar.value", _)) -> should.be_true(True)
    _ -> should.fail()
  }

  let one_branch_budget = decode.PolicyInput(..base.policy, maximum_branches: 1)
  case domain.run(decode.SimulationInput(..base, policy: one_branch_budget)) {
    Error(domain.CoreFailure("bar_paths", reason)) ->
      reason |> string.contains("TooManyBranches") |> should.be_true
    _ -> should.fail()
  }

  let tiny_byte_budget = decode.PolicyInput(..base.policy, maximum_bytes: 1)
  case domain.run(decode.SimulationInput(..base, policy: tiny_byte_budget)) {
    Error(domain.CoreFailure("bar_paths", reason)) ->
      reason |> string.contains("maximum_bytes exceeded") |> should.be_true
    _ -> should.fail()
  }
}

pub fn exact_cn_hk_us_tracks_remain_separate_and_no_plugin_verdict_appears_test() {
  [#("cn", "CNY"), #("hk", "HKD"), #("us", "USD")]
  |> list.each(fn(scope) {
    let #(track, currency) = scope
    let base = simulation_input("compact")
    let input =
      decode.SimulationInput(
        ..base,
        instruction: instruction_input(track, currency, "buy", "11.20"),
        bar: known_bar("11.20", "11.60", "11.15", "11.40", "b"),
      )
    let assert Ok(response) = domain.run(input)
    let text = result_text(response)
    text
    |> string.contains("\"track\":\"" <> track <> "\"")
    |> should.be_true
    [
      "\"verdict\"",
      "\"recommendation\"",
      "\"selectedBranch\"",
      "\"predictedFill\"",
      "\"nextAction\"",
      "\"authorization\"",
      "\"ready\"",
      "\"accepted\"",
    ]
    |> list.each(fn(forbidden) {
      text |> string.contains(forbidden) |> should.be_false
    })
  })
}

fn simulation_input(projection: String) -> decode.SimulationInput {
  decode.SimulationInput(
    "bar_paths",
    instruction_input("us", "USD", "buy", "11.20"),
    known_bar("11.20", "11.60", "11.15", "11.40", "b"),
    known_bool(True, "supported", "c"),
    policy(projection),
  )
}

fn instruction_input(
  track: String,
  currency: String,
  side: String,
  price: String,
) -> decode.InstructionInput {
  decode.InstructionInput(
    "instruction-1",
    hash("i"),
    track,
    "listing:A",
    case track {
      "cn" -> "XSHG"
      "hk" -> "XHKG"
      _ -> "XNAS"
    },
    "account:A",
    currency,
    side,
    Some(case side {
      "sell" -> "close"
      _ -> "open"
    }),
    "100",
    "shares",
    decode.OrderBehaviorInput(
      "limit",
      Some(price),
      None,
      None,
      None,
      None,
      None,
      None,
    ),
    decode.TimeInForceInput("day", None),
    Some("regular"),
    None,
    None,
    case track {
      "cn" -> "Asia/Shanghai"
      "hk" -> "Asia/Hong_Kong"
      _ -> "America/New_York"
    },
    [hash("r")],
    [hash("c")],
    [hash("a")],
    decode.RetainedAlternativesInput("known", [], None),
  )
}

fn policy(projection: String) -> decode.PolicyInput {
  decode.PolicyInput(
    "bar_possible_paths_v1",
    "limit_touch_v1",
    "record_only_v1",
    "all_branches",
    "regular",
    "2026-08-07",
    "native",
    decode.RoundingInput(4, "half_up"),
    decode.ReferenceSetInput(
      [hash("c")],
      [hash("r")],
      [hash("k")],
      [hash("b")],
      [],
      [],
      [],
      [],
      [],
    ),
    10,
    10,
    100_000,
    10,
    projection,
  )
}

fn known_bar(
  open: String,
  high: String,
  low: String,
  close: String,
  marker: String,
) -> decode.BarFactInput {
  decode.BarFactInput(
    "known",
    Some(decode.BarValueInput(open, high, low, close)),
    Some(source(
      open <> "|" <> high <> "|" <> low <> "|" <> close,
      "USD",
      "ohlc",
      marker,
    )),
    None,
    None,
    [],
  )
}

fn known_bool(
  value: Bool,
  lexeme: String,
  marker: String,
) -> decode.BoolFactInput {
  decode.BoolFactInput(
    "known",
    Some(value),
    Some(source(lexeme, "N/A", "boolean", marker)),
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

fn hash(marker: String) -> String {
  string.repeat(
    case marker {
      "i" -> "1"
      "r" -> "2"
      "k" -> "3"
      value -> value
    },
    times: 64,
  )
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
