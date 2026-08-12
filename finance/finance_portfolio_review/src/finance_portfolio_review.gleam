import finance_calendar/date as calendar_date
import finance_core/decimal.{type Decimal}
import finance_core/time
import finance_math/exact
import finance_provenance/hash
import finance_provenance/identity
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{Gt, Lt}
import gleam/result
import gleam/string

pub type Descriptor {
  Descriptor(contract_id: String, operations: List(String))
}

pub type Response {
  Response(summary: String, details: json.Json)
}

pub type CalculationError {
  InvalidJson
  ContentHashMismatch
  WrongSchema
  WrongContract
  WrongOperation
  InvalidIdentity
  InvalidTrack
  InvalidReceipt
  InvalidDecimal(field: String)
  InvalidDate(field: String)
  DuplicateIdentity(field: String)
  MissingShock(listing_id: String)
  MissingSelectedLot(lot_id: String)
  DivisionByZero(field: String)
  Unsupported(String)
}

type Metadata {
  Metadata(schema_version: Int, contract_id: String, operation: String)
}

type Common {
  Common(
    request_id: String,
    snapshot_id: String,
    base_currency: String,
    scale: Int,
    rounding: String,
    track_legs: List(String),
    source_receipts: List(String),
    assumptions: List(String),
  )
}

type ScenarioPosition {
  ScenarioPosition(
    position_id: String,
    listing_id: String,
    track: String,
    currency: String,
    quantity: String,
    current_price: String,
    fx_to_base: Option(String),
  )
}

type Shock {
  Shock(shock_id: String, kind: String, listing_id: String, value: String)
}

type ScenarioRequest {
  ScenarioRequest(
    common: Common,
    scenario_id: String,
    scenario_label: String,
    result_label: String,
    nlv: String,
    positions: List(ScenarioPosition),
    shocks: List(Shock),
  )
}

type GroupInput {
  GroupInput(
    group_id: String,
    portfolio_weight: String,
    portfolio_return: String,
    benchmark_weight: String,
    benchmark_return: String,
  )
}

type AttributionRequest {
  AttributionRequest(
    common: Common,
    benchmark_id: String,
    groups: List(GroupInput),
  )
}

type RebalancePosition {
  RebalancePosition(
    position_id: String,
    track: String,
    currency: String,
    current_value: String,
    current_price: String,
    fx_to_base: Option(String),
    target_weight: String,
    lot_size: String,
    minimum_trade_quantity: String,
  )
}

type RebalanceRequest {
  RebalanceRequest(
    common: Common,
    proposal_id: String,
    nlv: String,
    cash: String,
    target_source_receipt: String,
    positions: List(RebalancePosition),
  )
}

type LotInput {
  LotInput(
    lot_id: String,
    position_id: String,
    track: String,
    currency: String,
    acquisition_date: String,
    as_of_date: String,
    quantity: String,
    acquisition_cost: String,
    current_mark: String,
  )
}

type SaleInput {
  SaleInput(quantity: String, price: String, selected_lot_ids: List(String))
}

type TaxRequest {
  TaxRequest(
    common: Common,
    jurisdiction: String,
    jurisdiction_rule_receipt: String,
    holding_period_threshold_days: Int,
    disposal_method: String,
    lots: List(LotInput),
    sale: Option(SaleInput),
  )
}

type LotResult {
  LotResult(
    lot: LotInput,
    quantity: Decimal,
    cost_per_share: Decimal,
    unrealized_gain: Decimal,
    holding_days: Int,
    holding_classification: String,
  )
}

pub fn calculate(
  descriptor: Descriptor,
  required_operation: String,
  bytes: String,
  expected_sha256: String,
) -> Result(Response, CalculationError) {
  use _ <- result.try(verify_hash(bytes, expected_sha256))
  use metadata <- result.try(parse(bytes, metadata_decoder()))
  use _ <- result.try(validate_metadata(
    descriptor,
    required_operation,
    metadata,
  ))
  case descriptor.contract_id {
    "portfolio_scenarios_v1" -> scenario(bytes, expected_sha256)
    "portfolio_attribution_v1" -> attribution(bytes, expected_sha256)
    "portfolio_rebalance_v1" -> rebalance(bytes, expected_sha256)
    "tax_lots_v1" -> tax_lots(bytes, expected_sha256)
    other -> Error(Unsupported(other))
  }
}

pub fn summary(value: Response) -> String {
  value.summary
}

pub fn details(value: Response) -> json.Json {
  value.details
}

pub fn error_message(error: CalculationError) -> String {
  case error {
    InvalidJson -> "Portfolio review packet is not valid versioned JSON"
    ContentHashMismatch ->
      "Portfolio review packet does not match expectedSha256"
    WrongSchema -> "Portfolio review packet schemaVersion must be 1"
    WrongContract -> "Portfolio review packet contractId is wrong for this tool"
    WrongOperation -> "Portfolio review packet operation is wrong for this tool"
    InvalidIdentity -> "Portfolio review identity, bounds, or policy is invalid"
    InvalidTrack ->
      "Portfolio review contains an invalid or undeclared track leg"
    InvalidReceipt -> "Portfolio review source receipt is not an exact SHA-256"
    InvalidDecimal(field) -> "Portfolio review decimal is invalid: " <> field
    InvalidDate(field) -> "Portfolio review date is invalid: " <> field
    DuplicateIdentity(field) ->
      "Portfolio review identity is duplicated: " <> field
    MissingShock(listing_id) ->
      "Scenario shock has no exact position listing: " <> listing_id
    MissingSelectedLot(lot_id) -> "Tax-lot selection is unavailable: " <> lot_id
    DivisionByZero(field) ->
      "Portfolio review calculation is unperformed because zero divides: "
      <> field
    Unsupported(reason) ->
      "Portfolio review operation is unsupported: " <> reason
  }
}

fn scenario(
  bytes: String,
  source_hash: String,
) -> Result(Response, CalculationError) {
  use request <- result.try(parse(bytes, scenario_decoder()))
  let ScenarioRequest(
    common,
    scenario_id,
    label,
    result_label,
    nlv_text,
    positions,
    shocks,
  ) = request
  use _ <- result.try(validate_common(common))
  use _ <- result.try(validate_texts([scenario_id, label]))
  use _ <- result.try(
    case list.contains(["hypothetical", "historical_replay"], result_label) {
      True -> Ok(Nil)
      False -> Error(InvalidIdentity)
    },
  )
  use _ <- result.try(unique_strings(
    list.map(positions, fn(value) { value.position_id }),
    "position_id",
  ))
  use _ <- result.try(unique_strings(
    list.map(shocks, fn(value) { value.shock_id }),
    "shock_id",
  ))
  use nlv <- result.try(parse_decimal(nlv_text, "nlv"))
  use impacts <- result.try(
    list.try_map(positions, fn(position) {
      scenario_position(position, shocks, common, result_label)
    }),
  )
  use _ <- result.try(
    list.try_each(shocks, fn(shock) {
      case
        list.any(positions, fn(position) {
          position.listing_id == shock.listing_id
        })
      {
        True -> Ok(Nil)
        False -> Error(MissingShock(shock.listing_id))
      }
    }),
  )
  let aggregate = impacts |> list.map(fn(value) { value.1 }) |> exact.sum
  use impact_ratio <- result.try(divide(
    aggregate,
    nlv,
    common.scale,
    common.rounding,
    "nlv",
  ))
  let payload =
    common_json(common, [
      #("scenarioId", json.string(scenario_id)),
      #("scenarioLabel", json.string(label)),
      #("resultLabel", json.string(result_label)),
      #("aggregateImpact", decimal_json(aggregate)),
      #("impactFractionNlv", decimal_json(impact_ratio)),
      #("perPositionImpact", json.array(impacts, fn(value) { value.0 })),
      #(
        "unaffectedPositions",
        json.array(
          impacts
            |> list.filter_map(fn(value) {
              case value.2 {
                Some(value) -> Ok(value)
                None -> Error(Nil)
              }
            }),
          json.string,
        ),
      ),
      #("sourcePacketSha256", json.string(source_hash)),
      #(
        "formula",
        json.string("quantity * current_price * fx_to_base * shock_pct"),
      ),
      #("interpretation", json.string("not_performed")),
      #(
        "availableOperations",
        json.array(["drill_positions", "compare_scenarios"], json.string),
      ),
    ])
  response(
    "Scenario "
      <> scenario_id
      <> " "
      <> result_label
      <> " impact="
      <> decimal.to_string(aggregate)
      <> " "
      <> common.base_currency
      <> "; no probability, forecast, or pass/fail judgment",
    payload,
  )
}

fn scenario_position(
  position: ScenarioPosition,
  shocks: List(Shock),
  common: Common,
  result_label: String,
) -> Result(#(json.Json, Decimal, Option(String)), CalculationError) {
  use _ <- result.try(
    validate_texts([
      position.position_id,
      position.listing_id,
      position.currency,
    ]),
  )
  use _ <- result.try(validate_track(position.track, common.track_legs))
  use quantity <- result.try(parse_decimal(
    position.quantity,
    position.position_id <> ".quantity",
  ))
  use price <- result.try(parse_decimal(
    position.current_price,
    position.position_id <> ".current_price",
  ))
  use fx <- result.try(case position.fx_to_base {
    Some(value) -> parse_decimal(value, position.position_id <> ".fx_to_base")
    None if position.currency == common.base_currency -> Ok(decimal_one())
    None -> Error(Unsupported(position.position_id <> ":missing_explicit_fx"))
  })
  let current_value = decimal.multiply(decimal.multiply(quantity, price), fx)
  let matching =
    list.filter(shocks, fn(shock) { shock.listing_id == position.listing_id })
  use _ <- result.try(
    list.try_each(matching, fn(shock) {
      case shock.kind == "price_shock" {
        True -> Ok(Nil)
        False -> Error(Unsupported("scenario_shock_kind:" <> shock.kind))
      }
    }),
  )
  use shock_values <- result.try(
    list.try_map(matching, fn(shock) {
      parse_decimal(shock.value, shock.shock_id <> ".value")
    }),
  )
  let combined_shock = exact.sum(shock_values)
  let impact = decimal.multiply(current_value, combined_shock)
  let unaffected = case matching {
    [] -> Some(position.position_id)
    _ -> None
  }
  Ok(#(
    json.object([
      #("positionId", json.string(position.position_id)),
      #("listingId", json.string(position.listing_id)),
      #("track", json.string(position.track)),
      #("nativeCurrency", json.string(position.currency)),
      #("currentBaseValue", decimal_json(current_value)),
      #("combinedShock", decimal_json(combined_shock)),
      #("impact", decimal_json(impact)),
      #("resultLabel", json.string(result_label)),
    ]),
    impact,
    unaffected,
  ))
}

fn attribution(
  bytes: String,
  source_hash: String,
) -> Result(Response, CalculationError) {
  use request <- result.try(parse(bytes, attribution_decoder()))
  let AttributionRequest(common, benchmark_id, groups) = request
  use _ <- result.try(validate_common(common))
  use _ <- result.try(validate_texts([benchmark_id]))
  use _ <- result.try(unique_strings(
    list.map(groups, fn(value) { value.group_id }),
    "group_id",
  ))
  use rows <- result.try(
    list.try_map(groups, fn(group) { attribution_group(group) }),
  )
  let portfolio_return = rows |> list.map(fn(value) { value.1 }) |> exact.sum
  let benchmark_return = rows |> list.map(fn(value) { value.2 }) |> exact.sum
  let allocation = rows |> list.map(fn(value) { value.3 }) |> exact.sum
  let selection = rows |> list.map(fn(value) { value.4 }) |> exact.sum
  let interaction = rows |> list.map(fn(value) { value.5 }) |> exact.sum
  let excess = decimal.subtract(portfolio_return, benchmark_return)
  let explained = exact.sum([allocation, selection, interaction])
  let reconciliation = decimal.subtract(excess, explained)
  let payload =
    common_json(common, [
      #("benchmarkId", json.string(benchmark_id)),
      #("method", json.string("brinson_fachler_v1")),
      #("portfolioReturn", decimal_json(portfolio_return)),
      #("benchmarkReturn", decimal_json(benchmark_return)),
      #("excessReturn", decimal_json(excess)),
      #("allocationEffect", decimal_json(allocation)),
      #("selectionEffect", decimal_json(selection)),
      #("interactionEffect", decimal_json(interaction)),
      #("reconciliationDelta", decimal_json(reconciliation)),
      #("groups", json.array(rows, fn(value) { value.0 })),
      #("sourcePacketSha256", json.string(source_hash)),
      #("interpretation", json.string("not_performed")),
      #(
        "availableOperations",
        json.array(["drill_groups", "inspect_reconciliation"], json.string),
      ),
    ])
  response(
    "Brinson attribution excess="
      <> decimal.to_string(excess)
      <> " reconciliation="
      <> decimal.to_string(reconciliation)
      <> "; values only, no performance judgment",
    payload,
  )
}

fn attribution_group(
  group: GroupInput,
) -> Result(
  #(json.Json, Decimal, Decimal, Decimal, Decimal, Decimal),
  CalculationError,
) {
  use _ <- result.try(validate_texts([group.group_id]))
  use pw <- result.try(parse_decimal(
    group.portfolio_weight,
    group.group_id <> ".portfolio_weight",
  ))
  use pr <- result.try(parse_decimal(
    group.portfolio_return,
    group.group_id <> ".portfolio_return",
  ))
  use bw <- result.try(parse_decimal(
    group.benchmark_weight,
    group.group_id <> ".benchmark_weight",
  ))
  use br <- result.try(parse_decimal(
    group.benchmark_return,
    group.group_id <> ".benchmark_return",
  ))
  let portfolio_contribution = decimal.multiply(pw, pr)
  let benchmark_contribution = decimal.multiply(bw, br)
  let allocation = decimal.multiply(decimal.subtract(pw, bw), br)
  let selection = decimal.multiply(bw, decimal.subtract(pr, br))
  let interaction =
    decimal.multiply(decimal.subtract(pw, bw), decimal.subtract(pr, br))
  Ok(#(
    json.object([
      #("groupId", json.string(group.group_id)),
      #("portfolioContribution", decimal_json(portfolio_contribution)),
      #("benchmarkContribution", decimal_json(benchmark_contribution)),
      #("allocation", decimal_json(allocation)),
      #("selection", decimal_json(selection)),
      #("interaction", decimal_json(interaction)),
    ]),
    portfolio_contribution,
    benchmark_contribution,
    allocation,
    selection,
    interaction,
  ))
}

fn rebalance(
  bytes: String,
  source_hash: String,
) -> Result(Response, CalculationError) {
  use request <- result.try(parse(bytes, rebalance_decoder()))
  let RebalanceRequest(
    common,
    proposal_id,
    nlv_text,
    cash_text,
    target_receipt,
    positions,
  ) = request
  use _ <- result.try(validate_common(common))
  use _ <- result.try(validate_texts([proposal_id]))
  use _ <- result.try(validate_receipt(target_receipt))
  use _ <- result.try(unique_strings(
    list.map(positions, fn(value) { value.position_id }),
    "position_id",
  ))
  use nlv <- result.try(parse_decimal(nlv_text, "nlv"))
  use cash <- result.try(parse_decimal(cash_text, "cash"))
  use rows <- result.try(
    list.try_map(positions, fn(position) {
      rebalance_position(position, nlv, common)
    }),
  )
  let grid_value_delta = rows |> list.map(fn(value) { value.1 }) |> exact.sum
  let turnover =
    rows |> list.map(fn(value) { decimal_abs(value.1) }) |> exact.sum
  use turnover_fraction <- result.try(divide(
    turnover,
    nlv,
    common.scale,
    common.rounding,
    "nlv",
  ))
  let projected_cash = decimal.subtract(cash, grid_value_delta)
  let violations =
    rows
    |> list.filter_map(fn(value) {
      case value.2 {
        Some(value) -> Ok(value)
        None -> Error(Nil)
      }
    })
  let all_violations = case decimal.compare(projected_cash, decimal.zero()) {
    Lt -> ["cash_constraint_violated", ..violations]
    _ -> violations
  }
  let payload =
    common_json(common, [
      #("proposalId", json.string(proposal_id)),
      #("targetSourceReceipt", json.string(target_receipt)),
      #(
        "proposalMeaning",
        json.string("mechanical_deltas_not_orders_or_recommendations"),
      ),
      #("trades", json.array(rows, fn(value) { value.0 })),
      #("projectedCash", decimal_json(projected_cash)),
      #("turnoverFraction", decimal_json(turnover_fraction)),
      #("violations", json.array(all_violations, json.string)),
      #("sourcePacketSha256", json.string(source_hash)),
      #(
        "availableOperations",
        json.array(
          ["drill_trades", "project_weights", "inspect_violations"],
          json.string,
        ),
      ),
    ])
  response(
    "Rebalance "
      <> proposal_id
      <> " produced "
      <> int.to_string(list.length(rows))
      <> " mechanical deltas and "
      <> int.to_string(list.length(all_violations))
      <> " constraint facts; no order or recommendation",
    payload,
  )
}

fn rebalance_position(
  position: RebalancePosition,
  nlv: Decimal,
  common: Common,
) -> Result(#(json.Json, Decimal, Option(String)), CalculationError) {
  use _ <- result.try(validate_texts([position.position_id, position.currency]))
  use _ <- result.try(validate_track(position.track, common.track_legs))
  use current <- result.try(parse_decimal(
    position.current_value,
    position.position_id <> ".current_value",
  ))
  use price <- result.try(parse_decimal(
    position.current_price,
    position.position_id <> ".current_price",
  ))
  use fx <- result.try(case position.fx_to_base {
    Some(value) -> parse_decimal(value, position.position_id <> ".fx_to_base")
    None if position.currency == common.base_currency -> Ok(decimal_one())
    None -> Error(Unsupported(position.position_id <> ":missing_explicit_fx"))
  })
  use target_weight <- result.try(parse_decimal(
    position.target_weight,
    position.position_id <> ".target_weight",
  ))
  use lot_size <- result.try(parse_decimal(
    position.lot_size,
    position.position_id <> ".lot_size",
  ))
  use minimum <- result.try(parse_decimal(
    position.minimum_trade_quantity,
    position.position_id <> ".minimum_trade_quantity",
  ))
  let current_base_value = decimal.multiply(current, fx)
  let base_price = decimal.multiply(price, fx)
  let target_value = decimal.multiply(target_weight, nlv)
  let continuous_value_delta =
    decimal.subtract(target_value, current_base_value)
  use continuous_quantity <- result.try(divide(
    continuous_value_delta,
    base_price,
    common.scale,
    common.rounding,
    position.position_id <> ".price",
  ))
  use lot_count <- result.try(divide(
    continuous_quantity,
    lot_size,
    0,
    "toward_zero",
    position.position_id <> ".lot_size",
  ))
  let grid_quantity = decimal.multiply(lot_count, lot_size)
  let grid_value_delta = decimal.multiply(grid_quantity, base_price)
  let violation = case
    decimal.compare(decimal_abs(grid_quantity), minimum),
    decimal.compare(decimal_abs(continuous_quantity), decimal.zero())
  {
    Lt, Gt -> Some(position.position_id <> ":below_min_trade")
    _, _ -> None
  }
  Ok(#(
    json.object([
      #("positionId", json.string(position.position_id)),
      #("track", json.string(position.track)),
      #("nativeCurrency", json.string(position.currency)),
      #("fxToBase", decimal_json(fx)),
      #("currentBaseValue", decimal_json(current_base_value)),
      #("basePrice", decimal_json(base_price)),
      #(
        "action",
        json.string(case decimal.compare(grid_quantity, decimal.zero()) {
          Lt -> "sell"
          _ -> "buy_or_none"
        }),
      ),
      #("continuousValueDelta", decimal_json(continuous_value_delta)),
      #("continuousQuantityDelta", decimal_json(continuous_quantity)),
      #("gridQuantityDelta", decimal_json(grid_quantity)),
      #("gridValueDelta", decimal_json(grid_value_delta)),
      #("targetWeight", decimal_json(target_weight)),
      #("constraintFact", json.nullable(violation, json.string)),
    ]),
    grid_value_delta,
    violation,
  ))
}

fn tax_lots(
  bytes: String,
  source_hash: String,
) -> Result(Response, CalculationError) {
  use request <- result.try(parse(bytes, tax_decoder()))
  let TaxRequest(
    common,
    jurisdiction,
    rule_receipt,
    threshold,
    disposal,
    lots,
    sale,
  ) = request
  use _ <- result.try(validate_common(common))
  use _ <- result.try(validate_texts([jurisdiction, disposal]))
  use _ <- result.try(validate_receipt(rule_receipt))
  use _ <- result.try(case threshold >= 1 && threshold <= 10_000 {
    True -> Ok(Nil)
    False -> Error(InvalidIdentity)
  })
  use _ <- result.try(unique_strings(
    list.map(lots, fn(value) { value.lot_id }),
    "lot_id",
  ))
  use lot_results <- result.try(
    list.try_map(lots, fn(lot) { tax_lot(lot, threshold, common) }),
  )
  let unrealized =
    lot_results |> list.map(fn(value) { value.unrealized_gain }) |> exact.sum
  use realized <- result.try(realized_gain(lot_results, sale, common))
  let payload =
    common_json(common, [
      #("jurisdiction", json.string(jurisdiction)),
      #("jurisdictionRuleReceipt", json.string(rule_receipt)),
      #("holdingPeriodThresholdDays", json.int(threshold)),
      #("disposalMethod", json.string(disposal)),
      #("lots", json.array(lot_results, lot_json)),
      #("totalUnrealizedGain", decimal_json(unrealized)),
      #("realizedSale", realized.0),
      #("sourcePacketSha256", json.string(source_hash)),
      #("taxMeaning", json.string("caller_rule_mechanics_not_tax_advice")),
      #(
        "availableOperations",
        json.array(
          ["drill_lots", "inspect_selection", "inspect_rule_receipt"],
          json.string,
        ),
      ),
    ])
  response(
    "Tax-lot facts unrealized="
      <> decimal.to_string(unrealized)
      <> " realized="
      <> realized.1
      <> "; caller-supplied rules, no tax advice or lot recommendation",
    payload,
  )
}

fn tax_lot(
  lot: LotInput,
  threshold: Int,
  common: Common,
) -> Result(LotResult, CalculationError) {
  use _ <- result.try(
    validate_texts([lot.lot_id, lot.position_id, lot.currency]),
  )
  use _ <- result.try(validate_track(lot.track, common.track_legs))
  use _ <- result.try(case lot.currency == common.base_currency {
    True -> Ok(Nil)
    False -> Error(Unsupported(lot.lot_id <> ":missing_explicit_fx"))
  })
  use quantity <- result.try(parse_decimal(
    lot.quantity,
    lot.lot_id <> ".quantity",
  ))
  use cost <- result.try(parse_decimal(
    lot.acquisition_cost,
    lot.lot_id <> ".acquisition_cost",
  ))
  use mark <- result.try(parse_decimal(
    lot.current_mark,
    lot.lot_id <> ".current_mark",
  ))
  use cost_per_share <- result.try(divide(
    cost,
    quantity,
    common.scale,
    common.rounding,
    lot.lot_id <> ".quantity",
  ))
  let unrealized =
    decimal.multiply(quantity, decimal.subtract(mark, cost_per_share))
  use acquired <- result.try(parse_date(
    lot.acquisition_date,
    lot.lot_id <> ".acquisition_date",
  ))
  use as_of <- result.try(parse_date(
    lot.as_of_date,
    lot.lot_id <> ".as_of_date",
  ))
  let days = calendar_date.days_between(acquired, as_of)
  use _ <- result.try(case days >= 0 {
    True -> Ok(Nil)
    False -> Error(InvalidDate(lot.lot_id <> ".date_order"))
  })
  Ok(
    LotResult(
      lot,
      quantity,
      cost_per_share,
      unrealized,
      days,
      case days >= threshold {
        True -> "long_term"
        False -> "short_term"
      },
    ),
  )
}

fn realized_gain(
  lots: List(LotResult),
  sale: Option(SaleInput),
  common: Common,
) -> Result(#(json.Json, String), CalculationError) {
  case sale {
    None ->
      Ok(#(
        json.object([
          #("state", json.string("unperformed")),
          #("reason", json.string("no_sale_requested")),
        ]),
        "unperformed",
      ))
    Some(sale) -> {
      use quantity <- result.try(parse_decimal(sale.quantity, "sale.quantity"))
      use price <- result.try(parse_decimal(sale.price, "sale.price"))
      use _ <- result.try(unique_strings(
        sale.selected_lot_ids,
        "selected_lot_id",
      ))
      use selected <- result.try(
        list.try_map(sale.selected_lot_ids, fn(id) {
          case list.find(lots, fn(value) { value.lot.lot_id == id }) {
            Ok(value) -> Ok(value)
            Error(_) -> Error(MissingSelectedLot(id))
          }
        }),
      )
      let available =
        selected |> list.map(fn(value) { value.quantity }) |> exact.sum
      use _ <- result.try(case decimal.compare(quantity, available) {
        Gt -> Error(Unsupported("sale_quantity_exceeds_selected_lots"))
        _ -> Ok(Nil)
      })
      use weighted_cost <- result.try(weighted_cost_per_share(selected, common))
      let gain =
        decimal.multiply(quantity, decimal.subtract(price, weighted_cost))
      Ok(#(
        json.object([
          #("state", json.string("calculated")),
          #("quantity", decimal_json(quantity)),
          #("salePrice", decimal_json(price)),
          #("selectedLotIds", json.array(sale.selected_lot_ids, json.string)),
          #("selectedWeightedCostPerShare", decimal_json(weighted_cost)),
          #("realizedGain", decimal_json(gain)),
        ]),
        decimal.to_string(gain),
      ))
    }
  }
}

fn weighted_cost_per_share(
  lots: List(LotResult),
  common: Common,
) -> Result(Decimal, CalculationError) {
  let total_quantity =
    lots |> list.map(fn(value) { value.quantity }) |> exact.sum
  let total_cost =
    lots
    |> list.map(fn(value) {
      decimal.multiply(value.quantity, value.cost_per_share)
    })
    |> exact.sum
  divide(
    total_cost,
    total_quantity,
    common.scale,
    common.rounding,
    "selected_lot_quantity",
  )
}

fn lot_json(value: LotResult) -> json.Json {
  json.object([
    #("lotId", json.string(value.lot.lot_id)),
    #("positionId", json.string(value.lot.position_id)),
    #("track", json.string(value.lot.track)),
    #("currency", json.string(value.lot.currency)),
    #("quantity", decimal_json(value.quantity)),
    #("costPerShare", decimal_json(value.cost_per_share)),
    #("unrealizedGain", decimal_json(value.unrealized_gain)),
    #("holdingPeriodDays", json.int(value.holding_days)),
    #("holdingClassification", json.string(value.holding_classification)),
  ])
}

fn response(
  summary: String,
  payload: json.Json,
) -> Result(Response, CalculationError) {
  let assert Ok(content_hash) = payload |> json.to_string |> hash.text
  Ok(Response(
    summary,
    json.object([
      #("canonicalReview", payload),
      #(
        "canonicalContentHash",
        content_hash |> identity.sha256_value |> json.string,
      ),
    ]),
  ))
}

fn common_json(
  common: Common,
  fields: List(#(String, json.Json)),
) -> json.Json {
  json.object(list.append(
    [
      #("schemaVersion", json.int(1)),
      #("requestId", json.string(common.request_id)),
      #("snapshotId", json.string(common.snapshot_id)),
      #("baseCurrency", json.string(common.base_currency)),
      #("scale", json.int(common.scale)),
      #("rounding", json.string(common.rounding)),
      #("trackLegs", json.array(common.track_legs, json.string)),
      #("sourceReceipts", json.array(common.source_receipts, json.string)),
      #("assumptions", json.array(common.assumptions, json.string)),
      #("decisionOwner", json.string("llm_or_user")),
    ],
    fields,
  ))
}

fn validate_metadata(
  descriptor: Descriptor,
  required_operation: String,
  metadata: Metadata,
) -> Result(Nil, CalculationError) {
  case
    metadata.schema_version == 1,
    metadata.contract_id == descriptor.contract_id
  {
    False, _ -> Error(WrongSchema)
    _, False -> Error(WrongContract)
    True, True ->
      case
        metadata.operation == required_operation
        && list.contains(descriptor.operations, metadata.operation)
      {
        True -> Ok(Nil)
        False -> Error(WrongOperation)
      }
  }
}

fn validate_common(common: Common) -> Result(Nil, CalculationError) {
  use _ <- result.try(
    validate_texts([common.request_id, common.snapshot_id, common.base_currency]),
  )
  use _ <- result.try(
    case
      common.scale >= 0
      && common.scale <= 18
      && list.length(common.track_legs) >= 1
      && list.length(common.track_legs) <= 3
      && list.length(common.source_receipts) >= 1
      && list.length(common.source_receipts) <= 100
      && list.length(common.assumptions) <= 100
    {
      True -> Ok(Nil)
      False -> Error(InvalidIdentity)
    },
  )
  use _ <- result.try(unique_strings(common.track_legs, "track_leg"))
  use _ <- result.try(
    list.try_each(common.track_legs, fn(track) {
      validate_track(track, common.track_legs)
    }),
  )
  list.try_each(common.source_receipts, validate_receipt)
}

fn validate_track(
  track: String,
  declared: List(String),
) -> Result(Nil, CalculationError) {
  case
    list.contains(["cn", "hk", "us"], track) && list.contains(declared, track)
  {
    True -> Ok(Nil)
    False -> Error(InvalidTrack)
  }
}

fn validate_receipt(value: String) -> Result(Nil, CalculationError) {
  case
    string.length(value) == 64
    && list.all(string.to_graphemes(value), fn(character) {
      string.contains("0123456789abcdef", character)
    })
  {
    True -> Ok(Nil)
    False -> Error(InvalidReceipt)
  }
}

fn validate_texts(values: List(String)) -> Result(Nil, CalculationError) {
  case
    list.all(values, fn(value) {
      value != "" && string.trim(value) == value && string.length(value) <= 4096
    })
  {
    True -> Ok(Nil)
    False -> Error(InvalidIdentity)
  }
}

fn unique_strings(
  values: List(String),
  field: String,
) -> Result(Nil, CalculationError) {
  case list.length(values) == list.length(list.unique(values)) {
    True -> Ok(Nil)
    False -> Error(DuplicateIdentity(field))
  }
}

fn parse_decimal(
  value: String,
  field: String,
) -> Result(Decimal, CalculationError) {
  decimal.parse(value) |> result.map_error(fn(_) { InvalidDecimal(field) })
}

fn divide(
  numerator: Decimal,
  denominator: Decimal,
  scale: Int,
  rounding: String,
  field: String,
) -> Result(Decimal, CalculationError) {
  use mode <- result.try(rounding_mode(rounding))
  decimal.divide(numerator, denominator, scale, mode)
  |> result.map_error(fn(_) { DivisionByZero(field) })
}

fn rounding_mode(
  value: String,
) -> Result(decimal.RoundingMode, CalculationError) {
  case value {
    "toward_zero" -> Ok(decimal.TowardZero)
    "away_from_zero" -> Ok(decimal.AwayFromZero)
    "half_up" -> Ok(decimal.HalfUp)
    "half_even" -> Ok(decimal.HalfEven)
    _ -> Error(InvalidIdentity)
  }
}

fn decimal_abs(value: Decimal) -> Decimal {
  case decimal.compare(value, decimal.zero()) {
    Lt -> decimal.negate(value)
    _ -> value
  }
}

fn decimal_one() -> Decimal {
  let assert Ok(value) = decimal.parse("1")
  value
}

fn decimal_json(value: Decimal) -> json.Json {
  value |> decimal.to_string |> json.string
}

fn verify_hash(
  bytes: String,
  expected: String,
) -> Result(Nil, CalculationError) {
  case hash.text(bytes) {
    Ok(actual) ->
      case identity.sha256_value(actual) == expected {
        True -> Ok(Nil)
        False -> Error(ContentHashMismatch)
      }
    Error(_) -> Error(ContentHashMismatch)
  }
}

fn parse(
  bytes: String,
  decoder: decode.Decoder(value),
) -> Result(value, CalculationError) {
  json.parse(bytes, decoder) |> result.map_error(fn(_) { InvalidJson })
}

fn parse_date(
  value: String,
  field: String,
) -> Result(time.Date, CalculationError) {
  case string.split(value, on: "-") {
    [year, month, day] ->
      case int.parse(year), int.parse(month), int.parse(day) {
        Ok(year), Ok(month), Ok(day) ->
          time.date(year, month, day)
          |> result.map_error(fn(_) { InvalidDate(field) })
        _, _, _ -> Error(InvalidDate(field))
      }
    _ -> Error(InvalidDate(field))
  }
}

fn metadata_decoder() -> decode.Decoder(Metadata) {
  use schema_version <- decode.field("schemaVersion", decode.int)
  use contract_id <- decode.field("contractId", decode.string)
  use operation <- decode.field("operation", decode.string)
  decode.success(Metadata(schema_version, contract_id, operation))
}

fn with_common(
  next: fn(Common) -> decode.Decoder(value),
) -> decode.Decoder(value) {
  use request_id <- decode.field("requestId", decode.string)
  use snapshot_id <- decode.field("snapshotId", decode.string)
  use base_currency <- decode.field("baseCurrency", decode.string)
  use scale <- decode.field("scale", decode.int)
  use rounding <- decode.field("rounding", decode.string)
  use track_legs <- decode.field("trackLegs", decode.list(of: decode.string))
  use source_receipts <- decode.field(
    "sourceReceipts",
    decode.list(of: decode.string),
  )
  use assumptions <- decode.field("assumptions", decode.list(of: decode.string))
  next(Common(
    request_id,
    snapshot_id,
    base_currency,
    scale,
    rounding,
    track_legs,
    source_receipts,
    assumptions,
  ))
}

fn scenario_decoder() -> decode.Decoder(ScenarioRequest) {
  use common <- with_common
  use scenario_id <- decode.field("scenarioId", decode.string)
  use label <- decode.field("scenarioLabel", decode.string)
  use result_label <- decode.field("resultLabel", decode.string)
  use nlv <- decode.field("nlv", decode.string)
  use positions <- decode.field(
    "positions",
    decode.list(of: scenario_position_decoder()),
  )
  use shocks <- decode.field("shocks", decode.list(of: shock_decoder()))
  decode.success(ScenarioRequest(
    common,
    scenario_id,
    label,
    result_label,
    nlv,
    positions,
    shocks,
  ))
}

fn scenario_position_decoder() -> decode.Decoder(ScenarioPosition) {
  use position_id <- decode.field("positionId", decode.string)
  use listing_id <- decode.field("listingId", decode.string)
  use track <- decode.field("track", decode.string)
  use currency <- decode.field("currency", decode.string)
  use quantity <- decode.field("quantity", decode.string)
  use price <- decode.field("currentPrice", decode.string)
  use fx <- decode.optional_field(
    "fxToBase",
    None,
    decode.optional(decode.string),
  )
  decode.success(ScenarioPosition(
    position_id,
    listing_id,
    track,
    currency,
    quantity,
    price,
    fx,
  ))
}

fn shock_decoder() -> decode.Decoder(Shock) {
  use shock_id <- decode.field("shockId", decode.string)
  use kind <- decode.field("kind", decode.string)
  use listing_id <- decode.field("listingId", decode.string)
  use value <- decode.field("value", decode.string)
  decode.success(Shock(shock_id, kind, listing_id, value))
}

fn attribution_decoder() -> decode.Decoder(AttributionRequest) {
  use common <- with_common
  use benchmark_id <- decode.field("benchmarkId", decode.string)
  use groups <- decode.field("groups", decode.list(of: group_decoder()))
  decode.success(AttributionRequest(common, benchmark_id, groups))
}

fn group_decoder() -> decode.Decoder(GroupInput) {
  use group_id <- decode.field("groupId", decode.string)
  use portfolio_weight <- decode.field("portfolioWeight", decode.string)
  use portfolio_return <- decode.field("portfolioReturn", decode.string)
  use benchmark_weight <- decode.field("benchmarkWeight", decode.string)
  use benchmark_return <- decode.field("benchmarkReturn", decode.string)
  decode.success(GroupInput(
    group_id,
    portfolio_weight,
    portfolio_return,
    benchmark_weight,
    benchmark_return,
  ))
}

fn rebalance_decoder() -> decode.Decoder(RebalanceRequest) {
  use common <- with_common
  use proposal_id <- decode.field("proposalId", decode.string)
  use nlv <- decode.field("nlv", decode.string)
  use cash <- decode.field("cash", decode.string)
  use receipt <- decode.field("targetSourceReceipt", decode.string)
  use positions <- decode.field(
    "positions",
    decode.list(of: rebalance_position_decoder()),
  )
  decode.success(RebalanceRequest(
    common,
    proposal_id,
    nlv,
    cash,
    receipt,
    positions,
  ))
}

fn rebalance_position_decoder() -> decode.Decoder(RebalancePosition) {
  use position_id <- decode.field("positionId", decode.string)
  use track <- decode.field("track", decode.string)
  use currency <- decode.field("currency", decode.string)
  use current <- decode.field("currentValue", decode.string)
  use price <- decode.field("currentPrice", decode.string)
  use fx <- decode.optional_field(
    "fxToBase",
    None,
    decode.optional(decode.string),
  )
  use target <- decode.field("targetWeight", decode.string)
  use lot <- decode.field("lotSize", decode.string)
  use minimum <- decode.field("minimumTradeQuantity", decode.string)
  decode.success(RebalancePosition(
    position_id,
    track,
    currency,
    current,
    price,
    fx,
    target,
    lot,
    minimum,
  ))
}

fn tax_decoder() -> decode.Decoder(TaxRequest) {
  use common <- with_common
  use jurisdiction <- decode.field("jurisdiction", decode.string)
  use receipt <- decode.field("jurisdictionRuleReceipt", decode.string)
  use threshold <- decode.field("holdingPeriodThresholdDays", decode.int)
  use disposal <- decode.field("disposalMethod", decode.string)
  use lots <- decode.field("lots", decode.list(of: lot_decoder()))
  use sale <- decode.optional_field(
    "sale",
    None,
    decode.optional(sale_decoder()),
  )
  decode.success(TaxRequest(
    common,
    jurisdiction,
    receipt,
    threshold,
    disposal,
    lots,
    sale,
  ))
}

fn lot_decoder() -> decode.Decoder(LotInput) {
  use lot_id <- decode.field("lotId", decode.string)
  use position_id <- decode.field("positionId", decode.string)
  use track <- decode.field("track", decode.string)
  use currency <- decode.field("currency", decode.string)
  use acquired <- decode.field("acquisitionDate", decode.string)
  use as_of <- decode.field("asOfDate", decode.string)
  use quantity <- decode.field("quantity", decode.string)
  use cost <- decode.field("acquisitionCost", decode.string)
  use mark <- decode.field("currentMark", decode.string)
  decode.success(LotInput(
    lot_id,
    position_id,
    track,
    currency,
    acquired,
    as_of,
    quantity,
    cost,
    mark,
  ))
}

fn sale_decoder() -> decode.Decoder(SaleInput) {
  use quantity <- decode.field("quantity", decode.string)
  use price <- decode.field("price", decode.string)
  use selected <- decode.field("selectedLotIds", decode.list(of: decode.string))
  decode.success(SaleInput(quantity, price, selected))
}
