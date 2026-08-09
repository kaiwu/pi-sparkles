import finance_core/currency
import finance_core/decimal.{type Decimal, type RoundingMode}
import finance_core/time
import finance_math/exact
import finance_provenance/hash
import finance_provenance/identity
import finance_risk/calculation
import finance_risk/fact
import finance_track
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{Eq, Gt, Lt}
import gleam/result
import gleam/string
import pi_sparkles_portfolio_risk/decode

pub type Output {
  Output(summary: String, details: Json)
}

pub type DomainError {
  InvalidField(field: String, reason: String)
  ReceiptFailure
}

type InformationPolicy {
  PartialTotals
  AllOrNothing
}

type HeatVariant {
  MarkBasis
  EntryBasis
}

type WeightFormat {
  Fraction
  Percentage
}

type Projection {
  Compact
  Receipt
}

type Denominator {
  NlvDenominator
  GrossDenominator
  CallerDenominator(capital: fact.Fact(Decimal))
}

type PreparedPolicy {
  PreparedPolicy(
    information: InformationPolicy,
    cutoff_seconds: Option(Int),
    heat_variant: HeatVariant,
    denominator: Option(Denominator),
    weight_format: WeightFormat,
    currency_rounding: calculation.RoundingSpec,
    weight_rounding: calculation.RoundingSpec,
    percentage_rounding: calculation.RoundingSpec,
    projection: Projection,
  )
}

type PreparedAccount {
  PreparedAccount(
    input: decode.AccountInput,
    nlv: fact.Fact(Decimal),
    cash: Option(fact.Fact(Decimal)),
    liabilities: Option(fact.Fact(Decimal)),
    stale: Bool,
  )
}

type Computation {
  Computation(expression: calculation.Expression, raw: Result(Decimal, String))
}

type PositionResult {
  ComputedPosition(
    input: decode.PositionInput,
    duplicate_count: Int,
    exposure: Computation,
    weight: Computation,
    heat: Computation,
    mechanical_facts: List(String),
    cutoff_facts: List(String),
  )
  ConflictingPosition(
    position_id: String,
    alternatives: List(decode.PositionInput),
  )
}

type UnavailableContribution {
  UnavailableContribution(position_id: String, reasons: List(String))
}

type Aggregate {
  Aggregate(
    expression: calculation.Expression,
    known_raw: Decimal,
    unavailable: List(UnavailableContribution),
  )
}

type TemporalCoherence {
  TemporalCoherence(earliest: Int, latest: Int, maximum_staleness_ms: Int)
}

type Results {
  Results(
    positions: List(PositionResult),
    gross: Aggregate,
    net: Aggregate,
    heat: Aggregate,
    heat_percentage: Computation,
    largest_weight: Computation,
    temporal: TemporalCoherence,
    account_stale: Bool,
    unknown_count: Int,
    conflict_count: Int,
    information_policy: InformationPolicy,
    heat_variant: HeatVariant,
    denominator_name: Option(String),
    weight_format: WeightFormat,
    currency_rounding: calculation.RoundingSpec,
    weight_rounding: calculation.RoundingSpec,
  )
}

pub fn error_message(value: DomainError) -> String {
  case value {
    InvalidField(field, reason) ->
      "Invalid explicit portfolio-risk field " <> field <> ": " <> reason
    ReceiptFailure ->
      "The canonical portfolio-risk semantic receipt could not be content-bound"
  }
}

pub fn run(value: decode.Input) -> Result(Output, DomainError) {
  use _ <- result.try(trimmed("portfolioId", value.portfolio_id))
  use instruction_ref <- result.try(sha("instructionRef", value.instruction_ref))
  use _ <- result.try(unique_strings(
    "requestedSummaryFields",
    value.requested_summary_fields,
  ))
  use policy <- result.try(prepare_policy(
    value.calculation,
    value.requested_summary_fields,
    value.account.account_currency,
    value.projection,
  ))
  use _ <- result.try(validate_account_header(value.account))
  use _ <- result.try(
    list.try_map(value.positions, validate_position_header)
    |> result.map(fn(_) { Nil }),
  )
  let temporal = temporal_coherence(value.account, value.positions)
  use account <- result.try(prepare_account(value.account, policy, temporal))
  use positions <- result.try(prepare_position_groups(
    value.positions,
    account,
    policy,
    temporal,
  ))
  let gross = gross_aggregate(positions, policy, value.account.account_currency)
  let net =
    net_aggregate(positions, gross, policy, value.account.account_currency)
  let heat = heat_aggregate(positions, policy, value.account.account_currency)
  let heat_percentage = heat_percentage(heat, gross, account, policy)
  let largest_weight = largest_weight(positions, policy)
  let unknown_count = count_unknown_positions(positions)
  let conflict_count =
    account_conflicts(account) + position_conflicts(positions)
  let results =
    Results(
      positions,
      gross,
      net,
      heat,
      heat_percentage,
      largest_weight,
      temporal,
      account.stale,
      unknown_count,
      conflict_count,
      policy.information,
      policy.heat_variant,
      denominator_name(policy.denominator),
      policy.weight_format,
      policy.currency_rounding,
      policy.weight_rounding,
    )
  let semantic_result =
    requested_result(
      value.requested_summary_fields,
      value.positions,
      results,
      None,
    )
  let payload =
    json.object([
      #("schema", json.string("pi-sparkles/portfolio-risk-semantic-result")),
      #("schemaVersion", json.int(1)),
      #("implementationVersion", json.string("portfolio_risk/0.1.0")),
      #("portfolioId", json.string(value.portfolio_id)),
      #(
        "instructionRef",
        instruction_ref |> identity.sha256_value |> json.string,
      ),
      #("accountInput", account_input_json(value.account)),
      #("positionInputs", json.array(value.positions, position_input_json)),
      #("calculation", calculation_input_json(value.calculation)),
      #(
        "requestedSummaryFields",
        json.array(value.requested_summary_fields, json.string),
      ),
      #("result", semantic_result),
      #("selfHashFieldExcluded", json.bool(True)),
      #("limitations", json.array(limitations(), json.string)),
    ])
  use receipt_hash <- result.try(
    payload
    |> json.to_string
    |> hash.text
    |> result.map_error(fn(_) { ReceiptFailure }),
  )
  let receipt_text = identity.sha256_value(receipt_hash)
  let output_result =
    requested_result(
      value.requested_summary_fields,
      value.positions,
      results,
      Some(receipt_text),
    )
  let receipt_fields = case policy.projection {
    Compact -> []
    Receipt -> [
      #(
        "semanticReceiptEnvelope",
        json.object([
          #("payload", payload),
          #("canonicalContentHash", json.string(receipt_text)),
        ]),
      ),
    ]
  }
  Ok(Output(
    "Calculated the explicitly requested portfolio facts for "
      <> int.to_string(list.length(value.positions))
      <> " supplied position row(s): "
      <> int.to_string(unknown_count)
      <> " unresolved position(s), "
      <> int.to_string(conflict_count)
      <> " conflict(s). No threshold, verdict, response, rebalance, or next action was selected.",
    json.object(list.append(
      [
        #("schema", json.string("pi-sparkles/portfolio-risk-result")),
        #("schemaVersion", json.int(1)),
        #("portfolioId", json.string(value.portfolio_id)),
        #("accountCurrency", json.string(value.account.account_currency)),
        #("result", output_result),
        #("semanticReceiptHandle", json.string(receipt_text)),
        #("decisionOwner", json.string("llm")),
        #("pluginDecisionFields", json.array([], json.string)),
        #("availableOperations", json.array(["portfolio_risk"], json.string)),
        #("limitations", json.array(limitations(), json.string)),
      ],
      receipt_fields,
    )),
  ))
}

fn prepare_policy(
  value: decode.CalculationInput,
  requested_fields: List(String),
  account_currency: String,
  projection: String,
) -> Result(PreparedPolicy, DomainError) {
  use information <- result.try(case value.information_policy {
    "partial_totals_v1" -> Ok(PartialTotals)
    "all_or_nothing_v1" -> Ok(AllOrNothing)
    _ ->
      Error(InvalidField(
        "calculation.informationPolicy",
        "expected partial_totals_v1 or all_or_nothing_v1",
      ))
  })
  use cutoff <- result.try(case value.max_staleness_seconds {
    None -> Ok(None)
    Some(seconds) if seconds >= 0 -> Ok(Some(seconds))
    Some(_) ->
      Error(InvalidField(
        "calculation.maxStalenessSeconds",
        "must be non-negative when supplied",
      ))
  })
  use heat_variant <- result.try(case value.heat_variant {
    "heat_mark_basis_v1" -> Ok(MarkBasis)
    "heat_entry_basis_v1" -> Ok(EntryBasis)
    _ ->
      Error(InvalidField(
        "calculation.heatVariant",
        "expected an exact supported heat basis",
      ))
  })
  use weight_format <- result.try(case value.position_weight_format {
    "fraction_v1" -> Ok(Fraction)
    "percentage_v1" -> Ok(Percentage)
    _ ->
      Error(InvalidField(
        "calculation.positionWeightFormat",
        "expected fraction_v1 or percentage_v1",
      ))
  })
  use mode <- result.try(rounding_mode(value.rounding_mode))
  use currency_rounding <- result.try(
    calculation.rounding(value.currency_scale, value.intermediate_scale, mode)
    |> result.map_error(fn(_) {
      InvalidField(
        "calculation",
        "intermediateScale must be at least currencyScale and both must be non-negative",
      )
    }),
  )
  use weight_rounding <- result.try(
    calculation.rounding(value.weight_scale, value.intermediate_scale, mode)
    |> result.map_error(fn(_) {
      InvalidField(
        "calculation",
        "intermediateScale must be at least weightScale and both must be non-negative",
      )
    }),
  )
  use percentage_rounding <- result.try(
    calculation.rounding(value.percentage_scale, value.intermediate_scale, mode)
    |> result.map_error(fn(_) {
      InvalidField(
        "calculation",
        "intermediateScale must be at least percentageScale and both must be non-negative",
      )
    }),
  )
  use projection_value <- result.try(case projection {
    "compact" -> Ok(Compact)
    "receipt" -> Ok(Receipt)
    _ -> Error(InvalidField("projection", "expected compact or receipt"))
  })
  let wants_heat_percentage = list.contains(requested_fields, "heat_pct")
  use denominator <- result.try(
    case wants_heat_percentage, value.heat_denominator {
      False, None -> Ok(None)
      False, Some(_) ->
        Error(InvalidField(
          "calculation.heatDenominator",
          "is only accepted when heat_pct is explicitly requested",
        ))
      True, None ->
        Error(InvalidField(
          "calculation.heatDenominator",
          "is required when heat_pct is explicitly requested",
        ))
      True, Some(input) -> prepare_denominator(input, account_currency)
    },
  )
  Ok(PreparedPolicy(
    information,
    cutoff,
    heat_variant,
    denominator,
    weight_format,
    currency_rounding,
    weight_rounding,
    percentage_rounding,
    projection_value,
  ))
}

fn prepare_denominator(
  value: decode.HeatDenominatorInput,
  account_currency: String,
) -> Result(Option(Denominator), DomainError) {
  case value.kind, value.caller_capital {
    "denom_nlv_v1", None -> Ok(Some(NlvDenominator))
    "denom_gross_v1", None -> Ok(Some(GrossDenominator))
    "denom_caller_v1", Some(input) -> {
      use capital <- result.try(decimal_fact(
        "calculation.heatDenominator.callerCapital",
        input,
        account_currency,
        "currency",
      ))
      Ok(Some(CallerDenominator(capital)))
    }
    "denom_caller_v1", None ->
      Error(InvalidField(
        "calculation.heatDenominator.callerCapital",
        "is required for denom_caller_v1",
      ))
    "denom_nlv_v1", Some(_) | "denom_gross_v1", Some(_) ->
      Error(InvalidField(
        "calculation.heatDenominator.callerCapital",
        "is forbidden unless denom_caller_v1 is selected",
      ))
    _, _ ->
      Error(InvalidField(
        "calculation.heatDenominator.kind",
        "expected denom_nlv_v1, denom_gross_v1, or denom_caller_v1",
      ))
  }
}

fn validate_account_header(
  value: decode.AccountInput,
) -> Result(Nil, DomainError) {
  use _ <- result.try(trimmed("account.accountId", value.account_id))
  use _ <- result.try(exact_currency(
    "account.accountCurrency",
    value.account_currency,
  ))
  use _ <- result.try(instant(
    "account.asOfUnixMilliseconds",
    value.as_of_unix_ms,
  ))
  use _ <- result.try(sha("account.sourceReceipt", value.source_receipt))
  case value.source_kind {
    "custodian_observation" | "caller_declared" -> Ok(Nil)
    _ ->
      Error(InvalidField(
        "account.sourceKind",
        "expected custodian_observation or caller_declared",
      ))
  }
}

fn validate_position_header(
  value: decode.PositionInput,
) -> Result(Nil, DomainError) {
  use _ <- result.try(trimmed("positions[].positionId", value.position_id))
  use _ <- result.try(trimmed("positions[].listingId", value.listing_id))
  use _ <- result.try(
    case
      string.length(value.mic) == 4 && string.uppercase(value.mic) == value.mic
    {
      True -> Ok(Nil)
      False ->
        Error(InvalidField(
          "positions[].mic",
          "expected an exact four-character uppercase MIC",
        ))
    },
  )
  use _ <- result.try(
    finance_track.from_name(value.track)
    |> result.map_error(fn(_) {
      InvalidField("positions[].track", "expected cn, hk, or us exactly")
    }),
  )
  use _ <- result.try(case value.direction {
    "long" | "short" -> Ok(Nil)
    _ -> Error(InvalidField("positions[].direction", "expected long or short"))
  })
  use _ <- result.try(case value.quantity_unit {
    "shares" | "lots" -> Ok(Nil)
    _ ->
      Error(InvalidField("positions[].quantityUnit", "expected shares or lots"))
  })
  use _ <- result.try(exact_currency(
    "positions[].positionCurrency",
    value.position_currency,
  ))
  use _ <- result.try(instant(
    "positions[].asOfUnixMilliseconds",
    value.as_of_unix_ms,
  ))
  use _ <- result.try(validate_optional_instant(
    "positions[].markTimeUnixMilliseconds",
    value.mark_time_unix_ms,
  ))
  validate_optional_instant(
    "positions[].stopTimeUnixMilliseconds",
    value.stop_time_unix_ms,
  )
}

fn prepare_account(
  value: decode.AccountInput,
  policy: PreparedPolicy,
  temporal: TemporalCoherence,
) -> Result(PreparedAccount, DomainError) {
  use nlv <- result.try(decimal_fact(
    "account.netLiquidationValue",
    value.net_liquidation_value,
    value.account_currency,
    "currency",
  ))
  use cash <- result.try(optional_decimal_fact(
    "account.cashBalance",
    value.cash_balance,
    value.account_currency,
    "currency",
  ))
  use liabilities <- result.try(optional_decimal_fact(
    "account.liabilities",
    value.liabilities,
    value.account_currency,
    "currency",
  ))
  use _ <- result.try(
    case value.net_liquidation_value.state, value.net_liquidation_value.source {
      "known", Some(source)
        if source.reference == value.source_receipt
        && source.kind == value.source_kind
      -> Ok(Nil)
      "known", _ ->
        Error(InvalidField(
          "account.netLiquidationValue.source",
          "known NLV source kind and reference must match the account receipt",
        ))
      _, _ -> Ok(Nil)
    },
  )
  let stale =
    exceeds_cutoff(temporal.latest - value.as_of_unix_ms, policy.cutoff_seconds)
  Ok(PreparedAccount(value, nlv, cash, liabilities, stale))
}

fn prepare_position_groups(
  values: List(decode.PositionInput),
  account: PreparedAccount,
  policy: PreparedPolicy,
  temporal: TemporalCoherence,
) -> Result(List(PositionResult), DomainError) {
  case values {
    [] -> Ok([])
    [first, ..rest] -> {
      let #(same_id, others) =
        list.partition(rest, fn(value) {
          value.position_id == first.position_id
        })
      let alternatives = [first, ..same_id]
      use current <- result.try(
        case list.all(same_id, fn(value) { value == first }) {
          True ->
            prepare_position(
              first,
              list.length(alternatives),
              account,
              policy,
              temporal,
            )
          False -> Ok(ConflictingPosition(first.position_id, alternatives))
        },
      )
      use remaining <- result.try(prepare_position_groups(
        others,
        account,
        policy,
        temporal,
      ))
      Ok([current, ..remaining])
    }
  }
}

fn prepare_position(
  value: decode.PositionInput,
  duplicate_count: Int,
  account: PreparedAccount,
  policy: PreparedPolicy,
  temporal: TemporalCoherence,
) -> Result(PositionResult, DomainError) {
  use _ <- result.try(case value.direction {
    "long" -> Ok(Nil)
    "short" ->
      Error(InvalidField(
        "positions[].direction",
        "short positions are typed but deferred by the first-slice long-only contract",
      ))
    _ -> Error(InvalidField("positions[].direction", "unsupported direction"))
  })
  use _ <- result.try(
    case value.position_currency == account.input.account_currency {
      True -> Ok(Nil)
      False ->
        Error(InvalidField(
          "positions[].positionCurrency",
          "first slice requires the exact account currency; FX fallback is forbidden",
        ))
    },
  )
  use quantity <- result.try(decimal_fact(
    "positions[].quantity",
    value.quantity,
    "N/A",
    value.quantity_unit,
  ))
  use lot_size <- result.try(optional_decimal_fact(
    "positions[].lotSize",
    value.lot_size,
    "N/A",
    "shares_per_lot",
  ))
  use mark <- result.try(decimal_fact(
    "positions[].currentMark",
    value.current_mark,
    value.position_currency,
    "currency_per_share",
  ))
  use _ <- result.try(optional_decimal_fact(
    "positions[].costBasis",
    value.cost_basis,
    value.position_currency,
    "currency_per_share",
  ))
  use stop <- result.try(decimal_fact(
    "positions[].desiredStop",
    value.desired_stop,
    value.position_currency,
    "currency_per_share",
  ))
  use entry <- result.try(optional_decimal_fact(
    "positions[].entryPrice",
    value.entry_price,
    value.position_currency,
    "currency_per_share",
  ))
  use _ <- result.try(validate_lot_size(value.quantity_unit, lot_size))
  use _ <- result.try(validate_observation_time(
    "positions[].currentMark",
    value.current_mark,
    value.mark_time_unix_ms,
  ))
  use _ <- result.try(validate_observation_time(
    "positions[].desiredStop",
    value.desired_stop,
    value.stop_time_unix_ms,
  ))
  let snapshot_stale =
    exceeds_cutoff(temporal.latest - value.as_of_unix_ms, policy.cutoff_seconds)
  let mark_stale = case value.mark_time_unix_ms {
    Some(mark_time) ->
      snapshot_stale
      || exceeds_cutoff(temporal.latest - mark_time, policy.cutoff_seconds)
    None -> snapshot_stale
  }
  let stop_stale = case value.stop_time_unix_ms {
    Some(stop_time) ->
      snapshot_stale
      || exceeds_cutoff(temporal.latest - stop_time, policy.cutoff_seconds)
    None -> snapshot_stale
  }
  let cutoff_facts =
    [
      #(snapshot_stale, "position_snapshot"),
      #(mark_stale, "current_mark"),
      #(stop_stale, "desired_stop"),
    ]
    |> list.filter_map(fn(item) {
      case item {
        #(True, name) -> Ok(name)
        #(False, _) -> Error(Nil)
      }
    })
  let share_quantity =
    share_quantity(quantity, value.quantity_unit, lot_size, snapshot_stale)
  let exposure =
    exposure(
      value,
      quantity,
      lot_size,
      mark,
      share_quantity,
      mark_stale,
      policy,
    )
  let weight = position_weight(value, exposure, account, policy)
  let heat =
    position_heat(
      value,
      quantity,
      lot_size,
      mark,
      stop,
      entry,
      share_quantity,
      mark_stale,
      stop_stale,
      policy,
    )
  let mechanical_facts =
    mechanical_facts(
      value,
      quantity,
      mark,
      stop,
      entry,
      cutoff_facts != [],
      policy.heat_variant,
    )
  Ok(ComputedPosition(
    value,
    duplicate_count,
    exposure,
    weight,
    heat,
    mechanical_facts,
    cutoff_facts,
  ))
}

fn share_quantity(
  quantity: fact.Fact(Decimal),
  quantity_unit: String,
  lot_size: Option(fact.Fact(Decimal)),
  stale: Bool,
) -> Result(Decimal, String) {
  case stale {
    True -> Error("exceeds_staleness_cutoff")
    False ->
      case fact.known_value(quantity), quantity_unit, lot_size {
        Error(_), _, _ -> Error(fact_reason("quantity", quantity))
        Ok(sourced), "shares", None -> Ok(absolute(fact.sourced_value(sourced)))
        Ok(sourced), "lots", Some(size) ->
          case fact.known_value(size) {
            Error(_) -> Error(fact_reason("lot_size", size))
            Ok(sourced_size) ->
              Ok(decimal.multiply(
                absolute(fact.sourced_value(sourced)),
                fact.sourced_value(sourced_size),
              ))
          }
        _, _, _ -> Error("invalid_quantity_unit_contract")
      }
  }
}

fn exposure(
  position: decode.PositionInput,
  quantity: fact.Fact(Decimal),
  lot_size: Option(fact.Fact(Decimal)),
  mark: fact.Fact(Decimal),
  shares: Result(Decimal, String),
  mark_stale: Bool,
  policy: PreparedPolicy,
) -> Computation {
  let operands = quantity_operands(quantity, lot_size, mark, "current_mark")
  case shares, mark_stale, fact.known_value(mark) {
    _, True, _ ->
      unperformed(
        "exposure:" <> position.position_id,
        "gross_market_exposure_long_abs_quantity_v1",
        "mark_exceeds_staleness_cutoff",
        operands,
      )
    Ok(quantity_value), False, Ok(mark_value) -> {
      let raw = decimal.multiply(quantity_value, fact.sourced_value(mark_value))
      Computation(
        calculation.make_calculated(
          "exposure:" <> position.position_id,
          "gross_market_exposure_long_abs_quantity_v1",
          raw,
          position.position_currency,
          "currency",
          operands,
          [
            calculation.Intermediate(
              "unrounded_product",
              decimal.to_string(raw),
            ),
          ],
          policy.currency_rounding,
        ),
        Ok(raw),
      )
    }
    Error(reason), _, _ ->
      unperformed(
        "exposure:" <> position.position_id,
        "gross_market_exposure_long_abs_quantity_v1",
        reason,
        operands,
      )
    _, _, Error(_) ->
      unperformed(
        "exposure:" <> position.position_id,
        "gross_market_exposure_long_abs_quantity_v1",
        fact_reason("mark", mark),
        operands,
      )
  }
}

fn position_weight(
  position: decode.PositionInput,
  exposure: Computation,
  account: PreparedAccount,
  policy: PreparedPolicy,
) -> Computation {
  let formula = case policy.weight_format {
    Fraction -> "position_weight_nlv_fraction_v1"
    Percentage -> "position_weight_nlv_percentage_v1"
  }
  let operands = [calculation.operand("net_liquidation_value", account.nlv)]
  case exposure.raw, account.stale, fact.known_value(account.nlv) {
    Error(reason), _, _ ->
      unperformed(
        "weight:" <> position.position_id,
        formula,
        "dependency_unperformed:" <> reason,
        operands,
      )
    _, True, _ ->
      unperformed(
        "weight:" <> position.position_id,
        formula,
        "net_liquidation_value_exceeds_staleness_cutoff",
        operands,
      )
    Ok(numerator), False, Ok(sourced) -> {
      let denominator = fact.sourced_value(sourced)
      case decimal.compare(denominator, decimal.zero()) {
        Lt | Eq ->
          unperformed(
            "weight:" <> position.position_id,
            formula,
            "non_positive_denominator",
            operands,
          )
        Gt ->
          ratio_computation(
            "weight:" <> position.position_id,
            formula,
            numerator,
            denominator,
            position.position_currency,
            policy.weight_format == Percentage,
            operands,
            policy.weight_rounding,
          )
      }
    }
    _, _, Error(_) ->
      unperformed(
        "weight:" <> position.position_id,
        formula,
        fact_reason("net_liquidation_value", account.nlv),
        operands,
      )
  }
}

fn position_heat(
  position: decode.PositionInput,
  quantity: fact.Fact(Decimal),
  lot_size: Option(fact.Fact(Decimal)),
  mark: fact.Fact(Decimal),
  stop: fact.Fact(Decimal),
  entry: Option(fact.Fact(Decimal)),
  shares: Result(Decimal, String),
  mark_stale: Bool,
  stop_stale: Bool,
  policy: PreparedPolicy,
) -> Computation {
  let #(formula, basis_name, basis) = case policy.heat_variant, entry {
    MarkBasis, _ -> #("heat_mark_basis_v1", "current_mark", Some(mark))
    EntryBasis, value -> #("heat_entry_basis_v1", "entry_price", value)
  }
  let operands = case basis {
    None -> [
      calculation.operand("quantity", quantity),
      calculation.Operand(basis_name, "not_obtained", [], [], [], [], []),
      calculation.operand("desired_stop", stop),
    ]
    Some(basis) ->
      quantity_operands(quantity, lot_size, basis, basis_name)
      |> list.append([calculation.operand("desired_stop", stop)])
  }
  let basis_stale = case policy.heat_variant {
    MarkBasis -> mark_stale
    EntryBasis -> False
  }
  case shares, basis_stale, stop_stale, basis, fact.known_value(stop) {
    Error(reason), _, _, _, _ ->
      unperformed("heat:" <> position.position_id, formula, reason, operands)
    _, True, _, _, _ ->
      unperformed(
        "heat:" <> position.position_id,
        formula,
        "heat_basis_exceeds_staleness_cutoff",
        operands,
      )
    _, _, True, _, _ ->
      unperformed(
        "heat:" <> position.position_id,
        formula,
        "stop_exceeds_staleness_cutoff",
        operands,
      )
    _, _, _, None, _ ->
      unperformed(
        "heat:" <> position.position_id,
        formula,
        "missing_entry_price",
        operands,
      )
    Ok(quantity_value), False, False, Some(basis_fact), Ok(stop_value) ->
      case fact.known_value(basis_fact) {
        Error(_) ->
          unperformed(
            "heat:" <> position.position_id,
            formula,
            fact_reason(basis_name, basis_fact),
            operands,
          )
        Ok(basis_value) -> {
          let distance =
            decimal.subtract(
              fact.sourced_value(basis_value),
              fact.sourced_value(stop_value),
            )
          let raw = decimal.multiply(quantity_value, distance)
          Computation(
            calculation.make_calculated(
              "heat:" <> position.position_id,
              formula,
              raw,
              position.position_currency,
              "currency",
              operands,
              [
                calculation.Intermediate(
                  "signed_basis_minus_stop",
                  decimal.to_string(distance),
                ),
                calculation.Intermediate(
                  "unrounded_product",
                  decimal.to_string(raw),
                ),
              ],
              policy.currency_rounding,
            ),
            Ok(raw),
          )
        }
      }
    _, _, _, _, Error(_) ->
      unperformed(
        "heat:" <> position.position_id,
        formula,
        fact_reason("stop", stop),
        operands,
      )
  }
}

fn gross_aggregate(
  positions: List(PositionResult),
  policy: PreparedPolicy,
  account_currency: String,
) -> Aggregate {
  let known =
    positions
    |> list.filter_map(fn(value) {
      case value {
        ComputedPosition(exposure: Computation(_, Ok(raw)), ..) -> Ok(raw)
        _ -> Error(Nil)
      }
    })
  let unavailable =
    positions
    |> list.filter_map(fn(value) {
      case value {
        ComputedPosition(
          input: input,
          exposure: Computation(_, Error(reason)),
          ..,
        ) -> Ok(UnavailableContribution(input.position_id, [reason]))
        ConflictingPosition(id, _) ->
          Ok(UnavailableContribution(id, ["conflicting_position_id"]))
        _ -> Error(Nil)
      }
    })
  let total = exact.sum(known)
  let expression = case policy.information, unavailable {
    AllOrNothing, [_, ..] ->
      calculation.make_unperformed(
        "gross_market_exposure",
        "gross_market_exposure_long_abs_quantity_v1",
        "unknown_contributions_exist_under_all_or_nothing_v1",
        [],
      )
    _, _ ->
      calculation.make_calculated(
        "gross_market_exposure",
        "gross_market_exposure_long_abs_quantity_v1",
        total,
        account_currency,
        "currency",
        [],
        known_intermediates(positions, True),
        policy.currency_rounding,
      )
  }
  Aggregate(expression, total, unavailable)
}

fn net_aggregate(
  positions: List(PositionResult),
  gross: Aggregate,
  policy: PreparedPolicy,
  account_currency: String,
) -> Aggregate {
  let expression = case gross.expression {
    calculation.Calculated(_, _, _, _, _, _, _, _) ->
      calculation.make_calculated(
        "net_market_exposure",
        "net_market_exposure_long_only_v1",
        gross.known_raw,
        account_currency,
        "currency",
        [],
        known_intermediates(positions, True),
        policy.currency_rounding,
      )
    calculation.Unperformed(_, _, reason, _) ->
      calculation.make_unperformed(
        "net_market_exposure",
        "net_market_exposure_long_only_v1",
        reason,
        [],
      )
  }
  Aggregate(expression, gross.known_raw, gross.unavailable)
}

fn heat_aggregate(
  positions: List(PositionResult),
  policy: PreparedPolicy,
  account_currency: String,
) -> Aggregate {
  let known =
    positions
    |> list.filter_map(fn(value) {
      case value {
        ComputedPosition(heat: Computation(_, Ok(raw)), ..) -> Ok(raw)
        _ -> Error(Nil)
      }
    })
  let unavailable =
    positions
    |> list.filter_map(fn(value) {
      case value {
        ComputedPosition(input: input, heat: Computation(_, Error(reason)), ..) ->
          Ok(UnavailableContribution(input.position_id, [reason]))
        ConflictingPosition(id, _) ->
          Ok(UnavailableContribution(id, ["conflicting_position_id"]))
        _ -> Error(Nil)
      }
    })
  let total = exact.sum(known)
  let formula = heat_variant_name(policy.heat_variant)
  let expression = case policy.information, unavailable {
    AllOrNothing, [_, ..] ->
      calculation.make_unperformed(
        "portfolio_heat",
        formula,
        "unknown_contributions_exist_under_all_or_nothing_v1",
        [],
      )
    _, _ ->
      calculation.make_calculated(
        "portfolio_heat",
        formula,
        total,
        account_currency,
        "currency",
        [],
        known_intermediates(positions, False),
        policy.currency_rounding,
      )
  }
  Aggregate(expression, total, unavailable)
}

fn heat_percentage(
  heat: Aggregate,
  gross: Aggregate,
  account: PreparedAccount,
  policy: PreparedPolicy,
) -> Computation {
  case policy.denominator {
    None ->
      unperformed(
        "heat_pct",
        "not_requested",
        "heat_percentage_not_requested",
        [],
      )
    Some(denominator) -> {
      let name = case denominator {
        NlvDenominator -> "denom_nlv_v1"
        GrossDenominator -> "denom_gross_v1"
        CallerDenominator(_) -> "denom_caller_v1"
      }
      case heat.expression {
        calculation.Unperformed(_, _, reason, _) ->
          unperformed(
            "heat_pct",
            "portfolio_heat_percentage_" <> name,
            "dependency_unperformed:" <> reason,
            [],
          )
        calculation.Calculated(_, _, _, _, currency, _, _, _) -> {
          let denominator_value = case denominator {
            NlvDenominator ->
              case account.stale, fact.known_value(account.nlv) {
                True, _ ->
                  Error("net_liquidation_value_exceeds_staleness_cutoff")
                False, Error(_) ->
                  Error(fact_reason("net_liquidation_value", account.nlv))
                False, Ok(sourced) -> Ok(fact.sourced_value(sourced))
              }
            GrossDenominator ->
              case gross.expression {
                calculation.Calculated(_, _, _, _, _, _, _, _) ->
                  Ok(gross.known_raw)
                calculation.Unperformed(_, _, reason, _) ->
                  Error("gross_exposure_unperformed:" <> reason)
              }
            CallerDenominator(capital) ->
              case fact.known_value(capital) {
                Ok(sourced) -> Ok(fact.sourced_value(sourced))
                Error(_) -> Error(fact_reason("caller_capital", capital))
              }
          }
          case denominator_value {
            Error(reason) ->
              unperformed(
                "heat_pct",
                "portfolio_heat_percentage_" <> name,
                reason,
                [],
              )
            Ok(value) ->
              case decimal.compare(value, decimal.zero()) {
                Lt | Eq ->
                  unperformed(
                    "heat_pct",
                    "portfolio_heat_percentage_" <> name,
                    "non_positive_denominator",
                    [],
                  )
                Gt ->
                  ratio_computation(
                    "heat_pct",
                    "portfolio_heat_percentage_" <> name,
                    heat.known_raw,
                    value,
                    currency,
                    True,
                    [],
                    policy.percentage_rounding,
                  )
              }
          }
        }
      }
    }
  }
}

fn largest_weight(
  positions: List(PositionResult),
  policy: PreparedPolicy,
) -> Computation {
  let known =
    positions
    |> list.filter_map(fn(value) {
      case value {
        ComputedPosition(weight: Computation(_, Ok(raw)), ..) -> Ok(raw)
        _ -> Error(Nil)
      }
    })
  let unavailable_count = list.length(positions) - list.length(known)
  let formula = case policy.weight_format {
    Fraction -> "largest_position_weight_nlv_fraction_v1"
    Percentage -> "largest_position_weight_nlv_percentage_v1"
  }
  case known, policy.information, unavailable_count > 0 {
    [], _, _ ->
      unperformed(
        "largest_position_weight",
        formula,
        case positions {
          [] -> "empty_portfolio"
          _ -> "no_calculable_position_weights"
        },
        [],
      )
    _, AllOrNothing, True ->
      unperformed(
        "largest_position_weight",
        formula,
        "unknown_contributions_exist_under_all_or_nothing_v1",
        [],
      )
    [first, ..rest], _, _ -> {
      let maximum =
        list.fold(rest, first, fn(candidate, current) {
          case decimal.compare(candidate, current) {
            Gt -> candidate
            Eq | Lt -> current
          }
        })
      Computation(
        calculation.make_calculated(
          "largest_position_weight",
          formula,
          maximum,
          "N/A",
          weight_unit(policy.weight_format),
          [],
          [],
          policy.weight_rounding,
        ),
        Ok(maximum),
      )
    }
  }
}

fn requested_result(
  fields: List(String),
  supplied_positions: List(decode.PositionInput),
  values: Results,
  receipt_handle: Option(String),
) -> Json {
  fields
  |> list.map(fn(field) {
    case field {
      "position_count" -> #(
        "positionCount",
        json.int(list.length(supplied_positions)),
      )
      "gross_market_exposure" -> #(
        "grossMarketExposure",
        aggregate_json(values.gross, values.information_policy),
      )
      "net_market_exposure" -> #(
        "netMarketExposure",
        aggregate_json(values.net, values.information_policy),
      )
      "portfolio_heat" -> #(
        "portfolioHeat",
        aggregate_json(values.heat, values.information_policy),
      )
      "heat_pct" -> #(
        "heatPct",
        json.object([
          #("denominator", option_string_json(values.denominator_name)),
          #("value", expression_json(values.heat_percentage.expression)),
          #("partial", json.bool(values.heat.unavailable != [])),
          #(
            "unknownHeatContributions",
            unavailable_json(values.heat.unavailable),
          ),
        ]),
      )
      "largest_position_weight" -> #(
        "largestPositionWeight",
        json.object([
          #("format", json.string(weight_format_name(values.weight_format))),
          #("value", expression_json(values.largest_weight.expression)),
          #(
            "partial",
            json.bool(
              list.length(values.positions)
              > calculable_weights(values.positions),
            ),
          ),
        ]),
      )
      "position_contributions" -> #(
        "positionContributions",
        json.array(values.positions, fn(value) {
          position_result_json(value, values)
        }),
      )
      "reconciliation" -> #(
        "reconciliation",
        json.object([
          #(
            "exposure",
            reconciliation_json(
              values.gross,
              values.positions,
              True,
              values.currency_rounding,
            ),
          ),
          #(
            "heat",
            reconciliation_json(
              values.heat,
              values.positions,
              False,
              values.currency_rounding,
            ),
          ),
        ]),
      )
      "temporal_coherence" -> #(
        "temporalCoherence",
        temporal_json(values.temporal, values.account_stale, values.positions),
      )
      "unknown_count" -> #("unknownCount", json.int(values.unknown_count))
      "conflict_count" -> #("conflictCount", json.int(values.conflict_count))
      "receipt_handle" -> #("receiptHandle", option_string_json(receipt_handle))
      _ -> #("unsupportedField", json.string(field))
    }
  })
  |> json.object
}

fn position_result_json(value: PositionResult, results: Results) -> Json {
  case value {
    ConflictingPosition(position_id, alternatives) ->
      json.object([
        #("positionId", json.string(position_id)),
        #("state", json.string("conflicting")),
        #("reason", json.string("conflicting_position_id")),
        #("alternatives", json.array(alternatives, position_input_json)),
        #(
          "exposure",
          expression_json(
            calculation.make_unperformed(
              "exposure:" <> position_id,
              "gross_market_exposure_long_abs_quantity_v1",
              "conflicting_position_id",
              [],
            ),
          ),
        ),
        #(
          "weight",
          expression_json(
            calculation.make_unperformed(
              "weight:" <> position_id,
              "position_weight_nlv_"
                <> weight_format_name(results.weight_format),
              "conflicting_position_id",
              [],
            ),
          ),
        ),
        #(
          "heat",
          expression_json(
            calculation.make_unperformed(
              "heat:" <> position_id,
              heat_variant_name(results.heat_variant),
              "conflicting_position_id",
              [],
            ),
          ),
        ),
        #(
          "heatContributionPct",
          expression_json(
            calculation.make_unperformed(
              "heat_contribution_pct:" <> position_id,
              "heat_contribution_fraction_v1",
              "conflicting_position_id",
              [],
            ),
          ),
        ),
      ])
    ComputedPosition(
      input,
      duplicate_count,
      exposure,
      weight,
      heat,
      mechanical_facts,
      cutoff_facts,
    ) ->
      json.object([
        #("positionId", json.string(input.position_id)),
        #("listingId", json.string(input.listing_id)),
        #("mic", json.string(input.mic)),
        #("track", json.string(input.track)),
        #("direction", json.string(input.direction)),
        #("duplicateCount", json.int(duplicate_count)),
        #("exposure", expression_json(exposure.expression)),
        #("weight", expression_json(weight.expression)),
        #("heat", expression_json(heat.expression)),
        #(
          "heatContributionPct",
          expression_json(
            heat_contribution_percentage(
              input,
              heat,
              results.heat,
              results.weight_rounding,
            ).expression,
          ),
        ),
        #(
          "unknownContributionsExist",
          json.bool(results.heat.unavailable != []),
        ),
        #("mechanicalFacts", json.array(mechanical_facts, json.string)),
        #("cutoffProjection", case cutoff_facts {
          [] -> json.object([#("state", json.string("not_applied"))])
          _ ->
            json.object([
              #("state", json.string("not_obtained")),
              #("reason", json.string("exceeds_staleness_cutoff")),
              #("affectedFacts", json.array(cutoff_facts, json.string)),
            ])
        }),
        #("temporalFacts", position_temporal_json(input)),
        #(
          "inputStates",
          json.object([
            #("quantity", fact_input_json(input.quantity)),
            #("lotSize", option_fact_json(input.lot_size)),
            #("currentMark", fact_input_json(input.current_mark)),
            #("desiredStop", fact_input_json(input.desired_stop)),
            #("entryPrice", option_fact_json(input.entry_price)),
          ]),
        ),
      ])
  }
}

fn heat_contribution_percentage(
  position: decode.PositionInput,
  heat: Computation,
  aggregate: Aggregate,
  rounding: calculation.RoundingSpec,
) -> Computation {
  case heat.raw, aggregate.expression {
    Error(reason), _ ->
      unperformed(
        "heat_contribution_pct:" <> position.position_id,
        "heat_contribution_fraction_v1",
        "dependency_unperformed:" <> reason,
        [],
      )
    _, calculation.Unperformed(_, _, reason, _) ->
      unperformed(
        "heat_contribution_pct:" <> position.position_id,
        "heat_contribution_fraction_v1",
        "portfolio_heat_unperformed:" <> reason,
        [],
      )
    Ok(numerator), calculation.Calculated(_, _, _, _, currency, _, _, _) ->
      case decimal.compare(aggregate.known_raw, decimal.zero()) {
        Eq ->
          unperformed(
            "heat_contribution_pct:" <> position.position_id,
            "heat_contribution_fraction_v1",
            "zero_total_heat",
            [],
          )
        Lt | Gt ->
          case
            exact.ratio(
              numerator,
              aggregate.known_raw,
              calculation.intermediate_scale(rounding),
              calculation.rounding_mode(rounding),
            )
          {
            Error(_) ->
              unperformed(
                "heat_contribution_pct:" <> position.position_id,
                "heat_contribution_fraction_v1",
                "division_by_zero",
                [],
              )
            Ok(raw) ->
              Computation(
                calculation.make_calculated(
                  "heat_contribution_pct:" <> position.position_id,
                  "heat_contribution_fraction_v1",
                  raw,
                  currency,
                  "dimensionless_fraction",
                  [],
                  [],
                  rounding,
                ),
                Ok(raw),
              )
          }
      }
  }
}

fn aggregate_json(value: Aggregate, policy: InformationPolicy) -> Json {
  json.object([
    #("informationPolicy", json.string(information_policy_name(policy))),
    #("knownTotal", expression_json(value.expression)),
    #("unknownContributions", unavailable_json(value.unavailable)),
    #("partial", json.bool(value.unavailable != [])),
  ])
}

fn unavailable_json(values: List(UnavailableContribution)) -> Json {
  json.array(values, fn(value) {
    json.object([
      #("positionId", json.string(value.position_id)),
      #("reasons", json.array(value.reasons, json.string)),
    ])
  })
}

fn reconciliation_json(
  aggregate: Aggregate,
  positions: List(PositionResult),
  exposure: Bool,
  rounding: calculation.RoundingSpec,
) -> Json {
  case aggregate.expression {
    calculation.Unperformed(_, _, reason, _) ->
      json.object([
        #("state", json.string("unperformed")),
        #("reason", json.string("aggregate_unperformed:" <> reason)),
      ])
    calculation.Calculated(_, _, total, total_lexeme, currency, _, _, _) -> {
      let contributions =
        positions
        |> list.filter_map(fn(value) {
          case value, exposure {
            ComputedPosition(
              exposure: Computation(
                calculation.Calculated(_, _, number, _, _, _, _, _),
                _,
              ),
              ..,
            ),
              True
            -> Ok(number)
            ComputedPosition(
              heat: Computation(
                calculation.Calculated(_, _, number, _, _, _, _, _),
                _,
              ),
              ..,
            ),
              False
            -> Ok(number)
            _, _ -> Error(Nil)
          }
        })
      let contribution_sum = exact.sum(contributions)
      let delta = decimal.subtract(total, contribution_sum)
      let sum_expression =
        calculation.make_calculated(
          "reconciliation_sum",
          "sum_of_rounded_position_contributions_v1",
          contribution_sum,
          currency,
          "currency",
          [],
          [],
          rounding,
        )
      let delta_expression =
        calculation.make_calculated(
          "reconciliation_delta",
          "reported_total_minus_sum_of_reported_contributions_v1",
          delta,
          currency,
          "currency",
          [],
          [],
          rounding,
        )
      json.object([
        #("state", json.string("calculated")),
        #("total", json.string(total_lexeme)),
        #("sumOfContributions", expression_json(sum_expression)),
        #("delta", expression_json(delta_expression)),
        #("reconciled", json.bool(decimal.compare(delta, decimal.zero()) == Eq)),
      ])
    }
  }
}

fn expression_json(value: calculation.Expression) -> Json {
  case value {
    calculation.Calculated(
      operation_id,
      formula_variant,
      _,
      output_lexeme,
      currency,
      unit,
      operands,
      intermediates,
    ) ->
      json.object([
        #("operationId", json.string(operation_id)),
        #("formulaVariant", json.string(formula_variant)),
        #("state", json.string("calculated")),
        #("value", json.string(output_lexeme)),
        #("currency", json.string(currency)),
        #("unit", json.string(unit)),
        #("orderedOperands", json.array(operands, operand_json)),
        #("intermediateValues", json.array(intermediates, intermediate_json)),
      ])
    calculation.Unperformed(operation_id, formula_variant, reason, operands) ->
      json.object([
        #("operationId", json.string(operation_id)),
        #("formulaVariant", json.string(formula_variant)),
        #("state", json.string("unperformed")),
        #("reason", json.string(reason)),
        #("orderedOperands", json.array(operands, operand_json)),
      ])
  }
}

fn operand_json(value: calculation.Operand) -> Json {
  json.object([
    #("name", json.string(value.name)),
    #("state", json.string(value.state)),
    #("sourceReferences", json.array(value.source_references, json.string)),
    #("sourceLexemes", json.array(value.source_lexemes, json.string)),
    #("currencies", json.array(value.currencies, json.string)),
    #("units", json.array(value.units, json.string)),
    #(
      "retainedAlternatives",
      json.array(value.retained_alternatives, json.string),
    ),
  ])
}

fn intermediate_json(value: calculation.Intermediate) -> Json {
  json.object([
    #("name", json.string(value.name)),
    #("value", json.string(value.value)),
  ])
}

fn temporal_coherence(
  account: decode.AccountInput,
  positions: List(decode.PositionInput),
) -> TemporalCoherence {
  let times = [
    account.as_of_unix_ms,
    ..list.map(positions, fn(value) { value.as_of_unix_ms })
  ]
  let earliest = list.fold(times, account.as_of_unix_ms, int.min)
  let latest = list.fold(times, account.as_of_unix_ms, int.max)
  TemporalCoherence(earliest, latest, latest - earliest)
}

fn temporal_json(
  value: TemporalCoherence,
  account_stale: Bool,
  positions: List(PositionResult),
) -> Json {
  json.object([
    #("earliestAsOfUnixMilliseconds", json.int(value.earliest)),
    #("latestAsOfUnixMilliseconds", json.int(value.latest)),
    #("maxStalenessMilliseconds", json.int(value.maximum_staleness_ms)),
    #("maxStalenessSeconds", json.int(value.maximum_staleness_ms / 1000)),
    #("accountNlvExcludedByCutoff", json.bool(account_stale)),
    #(
      "positionsWithCutoffFacts",
      positions
        |> list.filter_map(fn(position) {
          case position {
            ComputedPosition(input: input, cutoff_facts: [_, ..], ..) ->
              Ok(input.position_id)
            _ -> Error(Nil)
          }
        })
        |> json.array(json.string),
    ),
  ])
}

fn position_temporal_json(value: decode.PositionInput) -> Json {
  json.object([
    #("positionAsOfUnixMilliseconds", json.int(value.as_of_unix_ms)),
    #("markTimeUnixMilliseconds", option_int_json(value.mark_time_unix_ms)),
    #("stopTimeUnixMilliseconds", option_int_json(value.stop_time_unix_ms)),
    #("markAgeMilliseconds", case value.mark_time_unix_ms {
      None -> json.null()
      Some(mark_time) -> json.int(value.as_of_unix_ms - mark_time)
    }),
    #(
      "stopAgeAtMarkMilliseconds",
      case value.mark_time_unix_ms, value.stop_time_unix_ms {
        Some(mark_time), Some(stop_time) -> json.int(mark_time - stop_time)
        _, _ -> json.null()
      },
    ),
  ])
}

fn mechanical_facts(
  position: decode.PositionInput,
  quantity: fact.Fact(Decimal),
  mark: fact.Fact(Decimal),
  stop: fact.Fact(Decimal),
  entry: Option(fact.Fact(Decimal)),
  snapshot_stale: Bool,
  variant: HeatVariant,
) -> List(String) {
  let facts = case fact.known_value(quantity) {
    Ok(sourced) ->
      case decimal.compare(fact.sourced_value(sourced), decimal.zero()) {
        Lt -> ["direction_quantity_mismatch", "quantity_sign_mismatch"]
        Eq | Gt -> []
      }
    Error(_) -> []
  }
  let facts = case variant, fact.known_value(mark), fact.known_value(stop) {
    MarkBasis, Ok(mark_value), Ok(stop_value) ->
      case
        decimal.compare(
          fact.sourced_value(mark_value),
          fact.sourced_value(stop_value),
        )
      {
        Gt -> facts
        Eq | Lt -> ["stop_at_or_above_mark", ..facts]
      }
    EntryBasis, _, Ok(stop_value) ->
      case entry {
        Some(entry_fact) ->
          case fact.known_value(entry_fact) {
            Ok(entry_value) ->
              case
                decimal.compare(
                  fact.sourced_value(entry_value),
                  fact.sourced_value(stop_value),
                )
              {
                Gt -> facts
                Eq | Lt -> ["stop_at_or_above_entry", ..facts]
              }
            Error(_) -> facts
          }
        None -> facts
      }
    _, _, _ -> facts
  }
  let facts = case position.mark_time_unix_ms {
    Some(mark_time) if mark_time < position.as_of_unix_ms -> [
      "mark_staleness_reported",
      ..facts
    ]
    Some(mark_time) if mark_time > position.as_of_unix_ms -> [
      "mark_time_after_position_as_of",
      ..facts
    ]
    _ -> facts
  }
  let facts = case position.mark_time_unix_ms, position.stop_time_unix_ms {
    Some(mark_time), Some(stop_time) if stop_time < mark_time -> [
      "stop_staleness_reported",
      ..facts
    ]
    Some(mark_time), Some(stop_time) if stop_time > mark_time -> [
      "stop_time_after_mark_time",
      ..facts
    ]
    _, _ -> facts
  }
  case snapshot_stale {
    True -> ["exceeds_staleness_cutoff", ..facts]
    False -> facts
  }
}

fn validate_lot_size(
  quantity_unit: String,
  lot_size: Option(fact.Fact(Decimal)),
) -> Result(Nil, DomainError) {
  case quantity_unit, lot_size {
    "shares", None -> Ok(Nil)
    "shares", Some(_) ->
      Error(InvalidField(
        "positions[].lotSize",
        "must be absent when quantityUnit is shares",
      ))
    "lots", None ->
      Error(InvalidField(
        "positions[].lotSize",
        "must be supplied as an information-state fact when quantityUnit is lots",
      ))
    "lots", Some(value) ->
      case fact.known_value(value) {
        Ok(sourced) ->
          case decimal.compare(fact.sourced_value(sourced), decimal.zero()) {
            Gt -> Ok(Nil)
            Eq | Lt ->
              Error(InvalidField(
                "positions[].lotSize",
                "known lot size must be positive",
              ))
          }
        Error(_) -> Ok(Nil)
      }
    _, _ ->
      Error(InvalidField(
        "positions[].quantityUnit",
        "unsupported quantity unit",
      ))
  }
}

fn validate_observation_time(
  field_name: String,
  value: decode.DecimalFactInput,
  observed_at: Option(Int),
) -> Result(Nil, DomainError) {
  case value.state, value.source, observed_at {
    "known", Some(source), Some(at) if source.effective_at_unix_ms == at ->
      Ok(Nil)
    "known", _, _ ->
      Error(InvalidField(
        field_name,
        "known value requires a matching explicit observation time",
      ))
    _, _, _ -> Ok(Nil)
  }
}

fn decimal_fact(
  field_name: String,
  value: decode.DecimalFactInput,
  expected_currency: String,
  expected_unit: String,
) -> Result(fact.Fact(Decimal), DomainError) {
  case
    value.state,
    value.value,
    value.source,
    value.reason,
    value.raw,
    value.alternatives
  {
    "known", Some(raw), Some(source_input), None, None, [] -> {
      use parsed <- result.try(parse_decimal(field_name <> ".value", raw))
      use source <- result.try(source(
        field_name <> ".source",
        source_input,
        expected_currency,
        expected_unit,
      ))
      use _ <- result.try(case source_input.source_lexeme == raw {
        True -> Ok(Nil)
        False ->
          Error(InvalidField(
            field_name <> ".source.sourceLexeme",
            "must equal the exact known decimal lexeme",
          ))
      })
      Ok(fact.known(parsed, source))
    }
    "unknown", None, Some(source_input), Some(reason), None, [] -> {
      use source <- result.try(source(
        field_name <> ".source",
        source_input,
        expected_currency,
        expected_unit,
      ))
      use _ <- result.try(trimmed(field_name <> ".reason", reason))
      Ok(fact.Unknown(source, reason))
    }
    "not_obtained", None, Some(source_input), Some(reason), None, [] -> {
      use source <- result.try(source(
        field_name <> ".source",
        source_input,
        expected_currency,
        expected_unit,
      ))
      use _ <- result.try(trimmed(field_name <> ".reason", reason))
      Ok(fact.NotObtained(source, reason))
    }
    "conflicting", None, None, None, None, alternatives -> {
      use _ <- result.try(
        case list.length(alternatives) >= 2 && list.length(alternatives) <= 20 {
          True -> Ok(Nil)
          False ->
            Error(InvalidField(
              field_name <> ".alternatives",
              "conflicting requires 2-20 alternatives",
            ))
        },
      )
      use parsed <- result.try(
        list.try_map(alternatives, fn(alternative) {
          use number <- result.try(parse_decimal(
            field_name <> ".alternatives[].value",
            alternative.value,
          ))
          use source <- result.try(source(
            field_name <> ".alternatives[].source",
            alternative.source,
            expected_currency,
            expected_unit,
          ))
          use _ <- result.try(
            case alternative.source.source_lexeme == alternative.value {
              True -> Ok(Nil)
              False ->
                Error(InvalidField(
                  field_name <> ".alternatives[].source.sourceLexeme",
                  "must equal the exact alternative decimal lexeme",
                ))
            },
          )
          Ok(fact.Sourced(number, source))
        }),
      )
      fact.conflicting(parsed)
      |> result.map_error(fn(error) {
        InvalidField(field_name, string.inspect(error))
      })
    }
    "decode_failure", None, Some(source_input), Some(reason), Some(raw), [] -> {
      use source <- result.try(source(
        field_name <> ".source",
        source_input,
        expected_currency,
        expected_unit,
      ))
      use _ <- result.try(trimmed(field_name <> ".reason", reason))
      Ok(fact.DecodeFailure(source, raw, reason))
    }
    _, _, _, _, _, _ ->
      Error(InvalidField(
        field_name,
        "fact state must supply exactly its required value/source/reason/raw/alternatives fields",
      ))
  }
}

fn optional_decimal_fact(
  field_name: String,
  value: Option(decode.DecimalFactInput),
  expected_currency: String,
  expected_unit: String,
) -> Result(Option(fact.Fact(Decimal)), DomainError) {
  case value {
    None -> Ok(None)
    Some(input) ->
      decimal_fact(field_name, input, expected_currency, expected_unit)
      |> result.map(Some)
  }
}

fn source(
  field_name: String,
  value: decode.SourceInput,
  expected_currency: String,
  expected_unit: String,
) -> Result(fact.Source, DomainError) {
  use kind <- result.try(source_kind(field_name <> ".kind", value.kind))
  use reference <- result.try(sha(field_name <> ".reference", value.reference))
  use effective_at <- result.try(instant(
    field_name <> ".effectiveAtUnixMilliseconds",
    value.effective_at_unix_ms,
  ))
  use retrieved_at <- result.try(instant(
    field_name <> ".retrievedAtUnixMilliseconds",
    value.retrieved_at_unix_ms,
  ))
  use _ <- result.try(case value.currency == expected_currency {
    True -> Ok(Nil)
    False ->
      Error(InvalidField(
        field_name <> ".currency",
        "expected exact " <> expected_currency,
      ))
  })
  use _ <- result.try(case value.unit == expected_unit {
    True -> Ok(Nil)
    False ->
      Error(InvalidField(
        field_name <> ".unit",
        "expected exact " <> expected_unit,
      ))
  })
  use _ <- result.try(trimmed(
    field_name <> ".sourceLexeme",
    value.source_lexeme,
  ))
  use _ <- result.try(trimmed(field_name <> ".scope", value.scope))
  use _ <- result.try(
    list.try_map(value.retained_alternatives, fn(text) {
      trimmed(field_name <> ".retainedAlternatives[]", text)
    })
    |> result.map(fn(_) { Nil }),
  )
  fact.source(
    kind,
    reference,
    effective_at,
    retrieved_at,
    value.currency,
    value.unit,
    value.source_lexeme,
    value.scope,
    value.retained_alternatives,
  )
  |> result.map_error(fn(error) {
    InvalidField(field_name, string.inspect(error))
  })
}

fn source_kind(
  field_name: String,
  value: String,
) -> Result(fact.SourceKind, DomainError) {
  case value {
    "provider_observation" -> Ok(fact.ProviderObservation)
    "market_rule" -> Ok(fact.MarketRule)
    "custodian_observation" -> Ok(fact.CustodianObservation)
    "caller_declared" -> Ok(fact.CallerDeclared)
    "llm_instruction" -> Ok(fact.LlmInstruction)
    _ -> Error(InvalidField(field_name, "unsupported explicit source kind"))
  }
}

fn ratio_computation(
  operation_id: String,
  formula: String,
  numerator: Decimal,
  denominator: Decimal,
  currency: String,
  percentage: Bool,
  operands: List(calculation.Operand),
  rounding: calculation.RoundingSpec,
) -> Computation {
  let divided = case percentage {
    True ->
      exact.percentage(
        numerator,
        denominator,
        calculation.intermediate_scale(rounding),
        calculation.rounding_mode(rounding),
      )
    False ->
      exact.ratio(
        numerator,
        denominator,
        calculation.intermediate_scale(rounding),
        calculation.rounding_mode(rounding),
      )
  }
  case divided {
    Error(_) -> unperformed(operation_id, formula, "division_by_zero", operands)
    Ok(raw) ->
      Computation(
        calculation.make_calculated(
          operation_id,
          formula,
          raw,
          currency,
          case percentage {
            True -> "percentage_points"
            False -> "dimensionless_fraction"
          },
          operands,
          [
            calculation.Intermediate("numerator", decimal.to_string(numerator)),
            calculation.Intermediate(
              "denominator",
              decimal.to_string(denominator),
            ),
          ],
          rounding,
        ),
        Ok(raw),
      )
  }
}

fn unperformed(
  operation_id: String,
  formula: String,
  reason: String,
  operands: List(calculation.Operand),
) -> Computation {
  Computation(
    calculation.make_unperformed(operation_id, formula, reason, operands),
    Error(reason),
  )
}

fn quantity_operands(
  quantity: fact.Fact(Decimal),
  lot_size: Option(fact.Fact(Decimal)),
  price: fact.Fact(Decimal),
  price_name: String,
) -> List(calculation.Operand) {
  let operands = [calculation.operand("quantity", quantity)]
  let operands = case lot_size {
    None -> operands
    Some(value) ->
      list.append(operands, [calculation.operand("lot_size", value)])
  }
  list.append(operands, [calculation.operand(price_name, price)])
}

fn fact_reason(name: String, value: fact.Fact(value)) -> String {
  case value {
    fact.Known(_) -> name <> "_known"
    fact.Unknown(_, _) -> "missing_" <> name
    fact.NotObtained(_, reason) -> "not_obtained_" <> name <> ":" <> reason
    fact.Conflicting(_) -> "conflicting_" <> name
    fact.DecodeFailure(_, _, reason) ->
      "decode_failure_" <> name <> ":" <> reason
  }
}

fn absolute(value: Decimal) -> Decimal {
  case decimal.compare(value, decimal.zero()) {
    Lt -> decimal.negate(value)
    Eq | Gt -> value
  }
}

fn known_intermediates(
  positions: List(PositionResult),
  exposure: Bool,
) -> List(calculation.Intermediate) {
  positions
  |> list.filter_map(fn(value) {
    case value, exposure {
      ComputedPosition(input: input, exposure: Computation(_, Ok(raw)), ..),
        True
      -> Ok(calculation.Intermediate(input.position_id, decimal.to_string(raw)))
      ComputedPosition(input: input, heat: Computation(_, Ok(raw)), ..), False
      -> Ok(calculation.Intermediate(input.position_id, decimal.to_string(raw)))
      _, _ -> Error(Nil)
    }
  })
}

fn count_unknown_positions(values: List(PositionResult)) -> Int {
  values
  |> list.filter(fn(value) {
    case value {
      ComputedPosition(
        exposure: Computation(_, exposure),
        heat: Computation(_, heat),
        ..,
      ) -> result.is_error(exposure) || result.is_error(heat)
      ConflictingPosition(_, _) -> False
    }
  })
  |> list.length
}

fn account_conflicts(value: PreparedAccount) -> Int {
  let nlv = case value.nlv {
    fact.Conflicting(_) -> 1
    _ -> 0
  }
  let cash = case value.cash {
    Some(fact.Conflicting(_)) -> 1
    _ -> 0
  }
  let liabilities = case value.liabilities {
    Some(fact.Conflicting(_)) -> 1
    _ -> 0
  }
  nlv + cash + liabilities
}

fn position_conflicts(values: List(PositionResult)) -> Int {
  values
  |> list.fold(0, fn(total, value) {
    case value {
      ConflictingPosition(_, alternatives) ->
        total
        + 1
        + list.fold(alternatives, 0, fn(count, input) {
          count + input_fact_conflicts(input)
        })
      ComputedPosition(input: input, ..) -> total + input_fact_conflicts(input)
    }
  })
}

fn input_fact_conflicts(value: decode.PositionInput) -> Int {
  let facts = [value.quantity, value.current_mark, value.desired_stop]
  let facts = case value.lot_size {
    Some(fact) -> [fact, ..facts]
    None -> facts
  }
  let facts = case value.cost_basis {
    Some(fact) -> [fact, ..facts]
    None -> facts
  }
  let facts = case value.entry_price {
    Some(fact) -> [fact, ..facts]
    None -> facts
  }
  facts
  |> list.filter(fn(value) { value.state == "conflicting" })
  |> list.length
}

fn calculable_weights(values: List(PositionResult)) -> Int {
  values
  |> list.filter(fn(value) {
    case value {
      ComputedPosition(weight: Computation(_, Ok(_)), ..) -> True
      _ -> False
    }
  })
  |> list.length
}

fn exceeds_cutoff(age_ms: Int, cutoff_seconds: Option(Int)) -> Bool {
  case cutoff_seconds {
    None -> False
    Some(seconds) -> age_ms > seconds * 1000
  }
}

fn information_policy_name(value: InformationPolicy) -> String {
  case value {
    PartialTotals -> "partial_totals_v1"
    AllOrNothing -> "all_or_nothing_v1"
  }
}

fn heat_variant_name(value: HeatVariant) -> String {
  case value {
    MarkBasis -> "heat_mark_basis_v1"
    EntryBasis -> "heat_entry_basis_v1"
  }
}

fn weight_format_name(value: WeightFormat) -> String {
  case value {
    Fraction -> "fraction_v1"
    Percentage -> "percentage_v1"
  }
}

fn weight_unit(value: WeightFormat) -> String {
  case value {
    Fraction -> "dimensionless_fraction"
    Percentage -> "percentage_points"
  }
}

fn denominator_name(value: Option(Denominator)) -> Option(String) {
  case value {
    None -> None
    Some(NlvDenominator) -> Some("denom_nlv_v1")
    Some(GrossDenominator) -> Some("denom_gross_v1")
    Some(CallerDenominator(_)) -> Some("denom_caller_v1")
  }
}

fn rounding_mode(value: String) -> Result(RoundingMode, DomainError) {
  case value {
    "toward_zero" -> Ok(decimal.TowardZero)
    "away_from_zero" -> Ok(decimal.AwayFromZero)
    "half_up" -> Ok(decimal.HalfUp)
    "half_even" -> Ok(decimal.HalfEven)
    _ ->
      Error(InvalidField(
        "calculation.roundingMode",
        "unsupported explicit rounding mode",
      ))
  }
}

fn limitations() -> List(String) {
  [
    "Long-only, single-currency cash-equity calculations over caller-supplied facts; no provider/account import, identity authentication, FX conversion, persistence, or order effect.",
    "Signed heat is abs(quantity in shares) multiplied by basis minus desired stop; a stop at or above the basis is returned as zero or negative with a mechanical fact.",
    "Known partial totals never imply completeness; unknown and conflicting contributions remain explicit.",
    "No threshold, concentration concern, risk adequacy, response, rebalance, recommendation, authorization, or next operation is selected by the plugin.",
    "Correlation, covariance, factor, liquidity, margin, leverage, stress, VaR/CVaR, shorts, multi-currency, optimization, and rebalancing are outside this slice.",
  ]
}

fn account_input_json(value: decode.AccountInput) -> Json {
  json.object([
    #("accountId", json.string(value.account_id)),
    #("netLiquidationValue", fact_input_json(value.net_liquidation_value)),
    #("cashBalance", option_fact_json(value.cash_balance)),
    #("liabilities", option_fact_json(value.liabilities)),
    #("accountCurrency", json.string(value.account_currency)),
    #("asOfUnixMilliseconds", json.int(value.as_of_unix_ms)),
    #("sourceKind", json.string(value.source_kind)),
    #("sourceReceipt", json.string(value.source_receipt)),
  ])
}

fn position_input_json(value: decode.PositionInput) -> Json {
  json.object([
    #("positionId", json.string(value.position_id)),
    #("listingId", json.string(value.listing_id)),
    #("mic", json.string(value.mic)),
    #("track", json.string(value.track)),
    #("direction", json.string(value.direction)),
    #("quantity", fact_input_json(value.quantity)),
    #("quantityUnit", json.string(value.quantity_unit)),
    #("lotSize", option_fact_json(value.lot_size)),
    #("currentMark", fact_input_json(value.current_mark)),
    #("markTimeUnixMilliseconds", option_int_json(value.mark_time_unix_ms)),
    #("costBasis", option_fact_json(value.cost_basis)),
    #("desiredStop", fact_input_json(value.desired_stop)),
    #("stopTimeUnixMilliseconds", option_int_json(value.stop_time_unix_ms)),
    #("entryPrice", option_fact_json(value.entry_price)),
    #("positionCurrency", json.string(value.position_currency)),
    #("asOfUnixMilliseconds", json.int(value.as_of_unix_ms)),
  ])
}

fn calculation_input_json(value: decode.CalculationInput) -> Json {
  json.object([
    #("informationPolicy", json.string(value.information_policy)),
    #("maxStalenessSeconds", option_int_json(value.max_staleness_seconds)),
    #("heatVariant", json.string(value.heat_variant)),
    #("heatDenominator", case value.heat_denominator {
      None -> json.null()
      Some(denominator) ->
        json.object([
          #("kind", json.string(denominator.kind)),
          #("callerCapital", option_fact_json(denominator.caller_capital)),
        ])
    }),
    #("positionWeightFormat", json.string(value.position_weight_format)),
    #("roundingMode", json.string(value.rounding_mode)),
    #("currencyScale", json.int(value.currency_scale)),
    #("weightScale", json.int(value.weight_scale)),
    #("percentageScale", json.int(value.percentage_scale)),
    #("intermediateScale", json.int(value.intermediate_scale)),
  ])
}

fn fact_input_json(value: decode.DecimalFactInput) -> Json {
  json.object([
    #("state", json.string(value.state)),
    #("value", option_string_json(value.value)),
    #("source", case value.source {
      None -> json.null()
      Some(source) -> source_input_json(source)
    }),
    #("reason", option_string_json(value.reason)),
    #("raw", option_string_json(value.raw)),
    #(
      "alternatives",
      json.array(value.alternatives, fn(alternative) {
        json.object([
          #("value", json.string(alternative.value)),
          #("source", source_input_json(alternative.source)),
        ])
      }),
    ),
  ])
}

fn source_input_json(value: decode.SourceInput) -> Json {
  json.object([
    #("kind", json.string(value.kind)),
    #("reference", json.string(value.reference)),
    #("effectiveAtUnixMilliseconds", json.int(value.effective_at_unix_ms)),
    #("retrievedAtUnixMilliseconds", json.int(value.retrieved_at_unix_ms)),
    #("currency", json.string(value.currency)),
    #("unit", json.string(value.unit)),
    #("sourceLexeme", json.string(value.source_lexeme)),
    #("scope", json.string(value.scope)),
    #(
      "retainedAlternatives",
      json.array(value.retained_alternatives, json.string),
    ),
  ])
}

fn option_fact_json(value: Option(decode.DecimalFactInput)) -> Json {
  case value {
    None -> json.null()
    Some(fact) -> fact_input_json(fact)
  }
}

fn option_string_json(value: Option(String)) -> Json {
  case value {
    None -> json.null()
    Some(text) -> json.string(text)
  }
}

fn option_int_json(value: Option(Int)) -> Json {
  case value {
    None -> json.null()
    Some(number) -> json.int(number)
  }
}

fn exact_currency(
  field_name: String,
  value: String,
) -> Result(Nil, DomainError) {
  use parsed <- result.try(
    currency.from_code(value)
    |> result.map_error(fn(_) {
      InvalidField(field_name, "expected an exact three-letter currency code")
    }),
  )
  case currency.code(parsed) == value {
    True -> Ok(Nil)
    False -> Error(InvalidField(field_name, "currency code must be uppercase"))
  }
}

fn sha(
  field_name: String,
  value: String,
) -> Result(identity.Sha256, DomainError) {
  identity.sha256(value)
  |> result.map_error(fn(_) {
    InvalidField(field_name, "expected an exact SHA-256 hexadecimal string")
  })
}

fn instant(
  field_name: String,
  value: Int,
) -> Result(time.Instant, DomainError) {
  time.instant(value)
  |> result.map_error(fn(_) {
    InvalidField(field_name, "instant is outside the supported range")
  })
}

fn validate_optional_instant(
  field_name: String,
  value: Option(Int),
) -> Result(Nil, DomainError) {
  case value {
    None -> Ok(Nil)
    Some(value) -> instant(field_name, value) |> result.map(fn(_) { Nil })
  }
}

fn parse_decimal(
  field_name: String,
  value: String,
) -> Result(Decimal, DomainError) {
  decimal.parse(value)
  |> result.map_error(fn(_) {
    InvalidField(field_name, "expected an exact decimal string")
  })
}

fn trimmed(field_name: String, value: String) -> Result(Nil, DomainError) {
  case value != "" && string.trim(value) == value {
    True -> Ok(Nil)
    False -> Error(InvalidField(field_name, "must be non-empty and trimmed"))
  }
}

fn unique_strings(
  field_name: String,
  values: List(String),
) -> Result(Nil, DomainError) {
  case values {
    [] -> Ok(Nil)
    [first, ..rest] ->
      case list.contains(rest, first) {
        True ->
          Error(InvalidField(field_name, "duplicate values are not allowed"))
        False -> unique_strings(field_name, rest)
      }
  }
}
