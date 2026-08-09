import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleeunit
import gleeunit/should
import pi_sparkles_portfolio_risk/decode
import pi_sparkles_portfolio_risk/domain

const as_of = 1_770_000_000_000

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn session_18_example_reconciles_exact_exposure_heat_and_weights_test() {
  let positions = [
    position(
      "pos_001",
      "listing_001",
      "XSHG",
      "cn",
      "2000",
      "10.50",
      "10.20",
      "b",
    ),
    position(
      "pos_002",
      "listing_002",
      "XSHG",
      "cn",
      "100",
      "1850.00",
      "1800.00",
      "c",
    ),
    position(
      "pos_003",
      "listing_003",
      "XSHE",
      "cn",
      "5400",
      "6.25",
      "5.88",
      "d",
    ),
  ]
  let assert Ok(output) =
    domain.run(input(positions, "partial_totals_v1", None, "compact"))
  let text = json.to_string(output.details)
  text |> string.contains("\"grossMarketExposure\"") |> should.be_true
  text |> string.contains("\"value\":\"239750.00\"") |> should.be_true
  text |> string.contains("\"portfolioHeat\"") |> should.be_true
  text |> string.contains("\"value\":\"7598.00\"") |> should.be_true
  text |> string.contains("\"value\":\"7.60\"") |> should.be_true
  text |> string.contains("\"value\":\"1.8500\"") |> should.be_true
  text |> string.contains("\"reconciled\":true") |> should.be_true
  text |> string.contains("\"decisionOwner\":\"llm\"") |> should.be_true
  text |> string.contains("\"pluginDecisionFields\":[]") |> should.be_true
}

pub fn partial_totals_keep_unknown_mark_and_stop_visible_test() {
  let p1 =
    position(
      "pos_001",
      "listing_001",
      "XSHG",
      "cn",
      "2000",
      "10.50",
      "10.20",
      "b",
    )
  let p2 =
    position(
      "pos_002",
      "listing_002",
      "XSHG",
      "cn",
      "100",
      "1850.00",
      "1800.00",
      "c",
    )
  let p3 =
    position(
      "pos_003",
      "listing_003",
      "XSHE",
      "cn",
      "5400",
      "6.25",
      "5.88",
      "d",
    )
  let p2 =
    decode.PositionInput(
      ..p2,
      current_mark: unknown_decimal(
        "provider omission",
        "CNY",
        "currency_per_share",
        "c",
      ),
      mark_time_unix_ms: None,
    )
  let p3 =
    decode.PositionInput(
      ..p3,
      desired_stop: unknown_decimal(
        "not yet set",
        "CNY",
        "currency_per_share",
        "d",
      ),
      stop_time_unix_ms: None,
    )
  let assert Ok(output) =
    domain.run(input([p1, p2, p3], "partial_totals_v1", None, "compact"))
  let text = json.to_string(output.details)
  text |> string.contains("\"value\":\"54750.00\"") |> should.be_true
  text |> string.contains("\"value\":\"600.00\"") |> should.be_true
  text |> string.contains("\"value\":\"0.60\"") |> should.be_true
  text |> string.contains("\"partial\":true") |> should.be_true
  text |> string.contains("\"unknownCount\":2") |> should.be_true
  text |> string.contains("missing_mark") |> should.be_true
  text |> string.contains("missing_stop") |> should.be_true
}

pub fn all_or_nothing_unperforms_totals_but_keeps_known_contributions_test() {
  let known_position =
    position(
      "known",
      "listing_001",
      "XSHG",
      "cn",
      "2000",
      "10.50",
      "10.20",
      "b",
    )
  let missing =
    position(
      "missing",
      "listing_002",
      "XSHG",
      "cn",
      "100",
      "20.00",
      "19.00",
      "c",
    )
  let missing =
    decode.PositionInput(
      ..missing,
      current_mark: unknown_decimal(
        "mark not supplied",
        "CNY",
        "currency_per_share",
        "c",
      ),
      mark_time_unix_ms: None,
    )
  let assert Ok(output) =
    domain.run(input(
      [known_position, missing],
      "all_or_nothing_v1",
      None,
      "compact",
    ))
  let text = json.to_string(output.details)
  text
  |> string.contains("unknown_contributions_exist_under_all_or_nothing_v1")
  |> should.be_true
  text |> string.contains("\"positionId\":\"known\"") |> should.be_true
  text |> string.contains("\"value\":\"21000.00\"") |> should.be_true
}

pub fn negative_long_quantity_and_stop_above_mark_are_mechanical_facts_test() {
  let position =
    position(
      "negative",
      "listing_001",
      "XSHG",
      "cn",
      "-500",
      "10.00",
      "10.50",
      "b",
    )
  let assert Ok(output) =
    domain.run(input([position], "partial_totals_v1", None, "compact"))
  let text = json.to_string(output.details)
  text |> string.contains("\"value\":\"5000.00\"") |> should.be_true
  text |> string.contains("\"value\":\"-250.00\"") |> should.be_true
  text |> string.contains("direction_quantity_mismatch") |> should.be_true
  text |> string.contains("quantity_sign_mismatch") |> should.be_true
  text |> string.contains("stop_at_or_above_mark") |> should.be_true
}

pub fn exact_duplicates_collapse_once_and_conflicting_duplicates_preserve_alternatives_test() {
  let first =
    position("same", "listing_001", "XSHG", "cn", "2000", "10.50", "10.20", "b")
  let assert Ok(collapsed) =
    domain.run(input([first, first], "partial_totals_v1", None, "compact"))
  let collapsed_text = json.to_string(collapsed.details)
  collapsed_text |> string.contains("\"positionCount\":2") |> should.be_true
  collapsed_text |> string.contains("\"duplicateCount\":2") |> should.be_true
  collapsed_text |> string.contains("\"value\":\"21000.00\"") |> should.be_true

  let changed =
    decode.PositionInput(
      ..first,
      current_mark: known_decimal(
        "10.60",
        "CNY",
        "currency_per_share",
        "e",
        as_of,
        "provider_observation",
      ),
    )
  let assert Ok(conflicting) =
    domain.run(input([first, changed], "partial_totals_v1", None, "compact"))
  let conflict_text = json.to_string(conflicting.details)
  conflict_text |> string.contains("conflicting_position_id") |> should.be_true
  conflict_text |> string.contains("\"conflictCount\":1") |> should.be_true
  conflict_text |> string.contains("\"alternatives\":[{") |> should.be_true
}

pub fn staleness_cutoff_projects_affected_facts_to_not_obtained_test() {
  let old =
    position("old", "listing_001", "XSHG", "cn", "2000", "10.50", "10.20", "b")
  let value = input([old], "partial_totals_v1", Some(10), "compact")
  let value =
    decode.Input(
      ..value,
      account: decode.AccountInput(
        ..value.account,
        as_of_unix_ms: as_of + 100_000,
        net_liquidation_value: known_decimal(
          "100000.00",
          "CNY",
          "currency",
          "a",
          as_of + 100_000,
          "caller_declared",
        ),
      ),
    )
  let assert Ok(output) = domain.run(value)
  let text = json.to_string(output.details)
  text |> string.contains("\"state\":\"not_obtained\"") |> should.be_true
  text |> string.contains("exceeds_staleness_cutoff") |> should.be_true
  text
  |> string.contains("\"maxStalenessMilliseconds\":100000")
  |> should.be_true
  text |> string.contains("mark_exceeds_staleness_cutoff") |> should.be_true
}

pub fn zero_nlv_unperforms_weights_but_empty_totals_remain_currency_values_test() {
  let value = input([], "partial_totals_v1", None, "compact")
  let value =
    decode.Input(
      ..value,
      account: decode.AccountInput(
        ..value.account,
        net_liquidation_value: known_decimal(
          "0.00",
          "CNY",
          "currency",
          "a",
          as_of,
          "caller_declared",
        ),
      ),
    )
  let assert Ok(empty) = domain.run(value)
  let empty_text = json.to_string(empty.details)
  empty_text |> string.contains("\"positionCount\":0") |> should.be_true
  empty_text |> string.contains("\"value\":\"0.00\"") |> should.be_true
  empty_text |> string.contains("\"currency\":\"CNY\"") |> should.be_true

  let with_position =
    decode.Input(..value, positions: [
      position("zero", "listing_001", "XSHG", "cn", "10", "10.00", "9.00", "b"),
    ])
  let assert Ok(output) = domain.run(with_position)
  json.to_string(output.details)
  |> string.contains("non_positive_denominator")
  |> should.be_true
}

pub fn lot_quantity_uses_only_the_supplied_evidenced_lot_size_test() {
  let shares =
    position("lots", "listing_001", "XHKG", "hk", "2", "10.00", "9.50", "b")
  let lots =
    decode.PositionInput(
      ..shares,
      quantity_unit: "lots",
      quantity: known_decimal(
        "2",
        "N/A",
        "lots",
        "b",
        as_of,
        "custodian_observation",
      ),
      lot_size: Some(known_decimal(
        "100",
        "N/A",
        "shares_per_lot",
        "e",
        as_of,
        "market_rule",
      )),
      position_currency: "HKD",
      current_mark: known_decimal(
        "10.00",
        "HKD",
        "currency_per_share",
        "b",
        as_of,
        "provider_observation",
      ),
      desired_stop: known_decimal(
        "9.50",
        "HKD",
        "currency_per_share",
        "b",
        as_of,
        "llm_instruction",
      ),
    )
  let value = input([lots], "partial_totals_v1", None, "compact")
  let value = decode.Input(..value, account: account("HKD"))
  let assert Ok(output) = domain.run(value)
  let text = json.to_string(output.details)
  text |> string.contains("\"value\":\"2000.00\"") |> should.be_true
  text |> string.contains("\"value\":\"100.00\"") |> should.be_true
  text |> string.contains("shares_per_lot") |> should.be_true
}

pub fn compact_and_receipt_outputs_share_semantics_and_contain_no_verdicts_test() {
  let positions = [
    position("one", "listing_001", "XNAS", "us", "10", "50.00", "45.00", "b"),
  ]
  let assert Ok(compact) =
    domain.run(input(positions, "partial_totals_v1", None, "compact"))
  let assert Ok(receipt) =
    domain.run(input(positions, "partial_totals_v1", None, "receipt"))
  let compact_text = json.to_string(compact.details)
  let receipt_text = json.to_string(receipt.details)
  compact_text |> string.contains("semanticReceiptEnvelope") |> should.be_false
  receipt_text |> string.contains("semanticReceiptEnvelope") |> should.be_true
  [
    "\"verdict\"",
    "\"recommendation\"",
    "\"nextAction\"",
    "\"concentrated\"",
    "\"excessive\"",
    "\"rebalance\"",
    "\"reducePosition\"",
  ]
  |> list.each(fn(forbidden) {
    compact_text |> string.contains(forbidden) |> should.be_false
  })
}

pub fn entry_basis_heat_is_separate_and_requires_an_entry_fact_test() {
  let base =
    position("entry", "listing_001", "XNAS", "us", "10", "10.00", "9.00", "b")
  let with_entry =
    decode.PositionInput(
      ..base,
      entry_price: Some(known_decimal(
        "12.00",
        "CNY",
        "currency_per_share",
        "e",
        as_of,
        "custodian_observation",
      )),
    )
  let value = input([with_entry], "partial_totals_v1", None, "compact")
  let value =
    decode.Input(
      ..value,
      calculation: decode.CalculationInput(
        ..value.calculation,
        heat_variant: "heat_entry_basis_v1",
      ),
    )
  let assert Ok(output) = domain.run(value)
  let text = json.to_string(output.details)
  text
  |> string.contains("\"formulaVariant\":\"heat_entry_basis_v1\"")
  |> should.be_true
  text |> string.contains("\"value\":\"30.00\"") |> should.be_true

  let missing = decode.Input(..value, positions: [base])
  let assert Ok(missing_output) = domain.run(missing)
  json.to_string(missing_output.details)
  |> string.contains("missing_entry_price")
  |> should.be_true
}

pub fn gross_and_caller_heat_denominators_are_explicit_and_non_positive_fails_test() {
  let position =
    position(
      "denominator",
      "listing_001",
      "XNAS",
      "us",
      "10",
      "50.00",
      "45.00",
      "b",
    )
  let gross = input([position], "partial_totals_v1", None, "compact")
  let gross =
    decode.Input(
      ..gross,
      calculation: decode.CalculationInput(
        ..gross.calculation,
        heat_denominator: Some(decode.HeatDenominatorInput(
          "denom_gross_v1",
          None,
        )),
      ),
    )
  let assert Ok(gross_output) = domain.run(gross)
  json.to_string(gross_output.details)
  |> string.contains("\"value\":\"10.00\"")
  |> should.be_true

  let caller =
    decode.Input(
      ..gross,
      calculation: decode.CalculationInput(
        ..gross.calculation,
        heat_denominator: Some(decode.HeatDenominatorInput(
          "denom_caller_v1",
          Some(known_decimal(
            "1000.00",
            "CNY",
            "currency",
            "e",
            as_of,
            "llm_instruction",
          )),
        )),
      ),
    )
  let assert Ok(caller_output) = domain.run(caller)
  json.to_string(caller_output.details)
  |> string.contains("\"value\":\"5.00\"")
  |> should.be_true

  let zero =
    decode.Input(
      ..caller,
      calculation: decode.CalculationInput(
        ..caller.calculation,
        heat_denominator: Some(decode.HeatDenominatorInput(
          "denom_caller_v1",
          Some(known_decimal(
            "0.00",
            "CNY",
            "currency",
            "e",
            as_of,
            "llm_instruction",
          )),
        )),
      ),
    )
  let assert Ok(zero_output) = domain.run(zero)
  json.to_string(zero_output.details)
  |> string.contains("non_positive_denominator")
  |> should.be_true
}

pub fn unrequested_derived_fields_are_absent_and_need_no_denominator_test() {
  let value =
    input(
      [
        position(
          "one",
          "listing_001",
          "XNAS",
          "us",
          "10",
          "50.00",
          "45.00",
          "b",
        ),
      ],
      "partial_totals_v1",
      None,
      "compact",
    )
  let value =
    decode.Input(
      ..value,
      calculation: decode.CalculationInput(
        ..value.calculation,
        heat_denominator: None,
      ),
      requested_summary_fields: ["position_count", "receipt_handle"],
    )
  let assert Ok(output) = domain.run(value)
  let text = json.to_string(output.details)
  text |> string.contains("\"positionCount\":1") |> should.be_true
  text |> string.contains("\"receiptHandle\":") |> should.be_true
  text |> string.contains("\"grossMarketExposure\":") |> should.be_false
  text |> string.contains("\"portfolioHeat\":") |> should.be_false
}

fn input(
  positions: List(decode.PositionInput),
  information_policy: String,
  cutoff: Option(Int),
  projection: String,
) -> decode.Input {
  decode.Input(
    "portfolio_001",
    hash("f"),
    account("CNY"),
    positions,
    decode.CalculationInput(
      information_policy,
      cutoff,
      "heat_mark_basis_v1",
      Some(decode.HeatDenominatorInput("denom_nlv_v1", None)),
      "fraction_v1",
      "half_up",
      2,
      4,
      2,
      8,
    ),
    [
      "position_count",
      "gross_market_exposure",
      "net_market_exposure",
      "portfolio_heat",
      "heat_pct",
      "largest_position_weight",
      "position_contributions",
      "reconciliation",
      "temporal_coherence",
      "unknown_count",
      "conflict_count",
      "receipt_handle",
    ],
    projection,
  )
}

fn account(currency: String) -> decode.AccountInput {
  decode.AccountInput(
    "account_001",
    known_decimal(
      "100000.00",
      currency,
      "currency",
      "a",
      as_of,
      "caller_declared",
    ),
    None,
    None,
    currency,
    as_of,
    "caller_declared",
    hash("a"),
  )
}

fn position(
  position_id: String,
  listing_id: String,
  mic: String,
  track: String,
  quantity: String,
  mark: String,
  stop: String,
  marker: String,
) -> decode.PositionInput {
  decode.PositionInput(
    position_id,
    listing_id,
    mic,
    track,
    "long",
    known_decimal(
      quantity,
      "N/A",
      "shares",
      marker,
      as_of,
      "custodian_observation",
    ),
    "shares",
    None,
    known_decimal(
      mark,
      "CNY",
      "currency_per_share",
      marker,
      as_of,
      "provider_observation",
    ),
    Some(as_of),
    None,
    known_decimal(
      stop,
      "CNY",
      "currency_per_share",
      marker,
      as_of,
      "llm_instruction",
    ),
    Some(as_of),
    None,
    "CNY",
    as_of,
  )
}

fn known_decimal(
  value: String,
  currency: String,
  unit: String,
  marker: String,
  effective_at: Int,
  kind: String,
) -> decode.DecimalFactInput {
  decode.DecimalFactInput(
    "known",
    Some(value),
    Some(
      decode.SourceInput(
        kind,
        hash(marker),
        effective_at,
        effective_at + 100,
        currency,
        unit,
        value,
        "fixture",
        [],
      ),
    ),
    None,
    None,
    [],
  )
}

fn unknown_decimal(
  reason: String,
  currency: String,
  unit: String,
  marker: String,
) -> decode.DecimalFactInput {
  decode.DecimalFactInput(
    "unknown",
    None,
    Some(
      decode.SourceInput(
        "caller_declared",
        hash(marker),
        as_of,
        as_of + 100,
        currency,
        unit,
        "not supplied",
        "fixture",
        [],
      ),
    ),
    Some(reason),
    None,
    [],
  )
}

fn hash(character: String) -> String {
  string.repeat(character, times: 64)
}
