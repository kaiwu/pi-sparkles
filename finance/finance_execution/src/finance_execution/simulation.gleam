import finance_core/decimal.{type Decimal, type RoundingMode}
import finance_execution/instruction.{type Side}
import finance_execution/numeric
import finance_math/exact
import finance_provenance/identity.{type Sha256}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{Eq, Gt, Lt}

pub const visible_depth_sweep_v1 = "visible_depth_sweep_v1"

pub const bar_possible_paths_v1 = "bar_possible_paths_v1"

pub type ResultKind {
  Hypothetical
  HistoricalReplay
  ObservedBrokerReceipt
  LlmDeclaredScenario
}

pub opaque type DepthLevel {
  DepthLevel(
    price: Decimal,
    price_lexeme: String,
    visible_quantity: Decimal,
    quantity_lexeme: String,
  )
}

pub opaque type DepthSnapshot {
  DepthSnapshot(
    snapshot_receipt: Sha256,
    bids: List(DepthLevel),
    asks: List(DepthLevel),
  )
}

pub type SweepStop {
  QuantitySatisfied
  LimitConstraint
  PriceBudgetConstraint
  DepthBudgetExhausted
  VisibleSnapshotExhausted
}

pub type StepAction {
  Consumed
  Stopped(stop: SweepStop)
}

pub type DepthStep {
  DepthStep(
    level_number: Int,
    price: Decimal,
    price_lexeme: String,
    displayed_quantity: Decimal,
    displayed_quantity_lexeme: String,
    filled_quantity: Decimal,
    remaining_quantity: Decimal,
    action: StepAction,
  )
}

pub type WeightedPrice {
  WeightedPriceCalculated(value: Decimal, output_lexeme: String)
  WeightedPriceUnperformed(reason: String)
}

pub opaque type SweepResult {
  SweepResult(
    model: String,
    result_kind: ResultKind,
    snapshot_receipt: Sha256,
    side: Side,
    limit_price: Decimal,
    price_budget: Decimal,
    requested_quantity: Decimal,
    maximum_depth_levels: Int,
    steps: List(DepthStep),
    filled_quantity: Decimal,
    remaining_quantity: Decimal,
    fill_notional: Decimal,
    fill_notional_lexeme: String,
    weighted_fill_price: WeightedPrice,
    depth_exhausted: Bool,
    stopped_by_limit: Bool,
    stop: SweepStop,
  )
}

pub type SimulationError {
  NonPositivePrice
  NonPositiveQuantity
  InvalidDepthBudget
  InvalidScale
  InvalidDepthLevel
  InvalidBarGeometry
}

pub fn depth_level(
  price price_value: Decimal,
  price_lexeme price_lexeme_value: String,
  visible_quantity quantity_value: Decimal,
  quantity_lexeme quantity_lexeme_value: String,
) -> Result(DepthLevel, SimulationError) {
  case numeric.positive(price_value), numeric.positive(quantity_value) {
    False, _ -> Error(InvalidDepthLevel)
    _, False -> Error(InvalidDepthLevel)
    True, True ->
      Ok(DepthLevel(
        price_value,
        price_lexeme_value,
        quantity_value,
        quantity_lexeme_value,
      ))
  }
}

pub fn depth_snapshot(
  snapshot_receipt receipt: Sha256,
  bids bid_values: List(DepthLevel),
  asks ask_values: List(DepthLevel),
) -> DepthSnapshot {
  DepthSnapshot(receipt, bid_values, ask_values)
}

pub fn visible_depth_sweep(
  snapshot snapshot_value: DepthSnapshot,
  side side_value: Side,
  limit_price limit_value: Decimal,
  requested_quantity quantity_value: Decimal,
  maximum_depth_levels depth_budget: Int,
  price_budget price_budget_value: Decimal,
  output_scale output_scale_value: Int,
  rounding_mode rounding_value: RoundingMode,
) -> Result(SweepResult, SimulationError) {
  case
    numeric.positive(limit_value),
    numeric.positive(quantity_value),
    numeric.positive(price_budget_value),
    depth_budget > 0,
    output_scale_value >= 0
  {
    False, _, _, _, _ -> Error(NonPositivePrice)
    _, False, _, _, _ -> Error(NonPositiveQuantity)
    _, _, False, _, _ -> Error(NonPositivePrice)
    _, _, _, False, _ -> Error(InvalidDepthBudget)
    _, _, _, _, False -> Error(InvalidScale)
    True, True, True, True, True -> {
      let levels = case side_value {
        instruction.Buy -> snapshot_value.asks
        instruction.Sell -> snapshot_value.bids
      }
      let #(steps, remaining, notional, stop) =
        sweep_levels(
          levels,
          side_value,
          limit_value,
          price_budget_value,
          quantity_value,
          decimal.zero(),
          1,
          depth_budget,
          [],
        )
      let filled = decimal.subtract(quantity_value, remaining)
      let weighted = case numeric.positive(filled) {
        False -> WeightedPriceUnperformed("zero_filled_quantity")
        True -> {
          let assert Ok(value) =
            exact.ratio(notional, filled, output_scale_value, rounding_value)
          WeightedPriceCalculated(
            value,
            numeric.fixed(value, output_scale_value),
          )
        }
      }
      let depth_exhausted = case stop {
        DepthBudgetExhausted | VisibleSnapshotExhausted ->
          numeric.positive(remaining)
        QuantitySatisfied | LimitConstraint | PriceBudgetConstraint -> False
      }
      Ok(SweepResult(
        visible_depth_sweep_v1,
        Hypothetical,
        snapshot_value.snapshot_receipt,
        side_value,
        limit_value,
        price_budget_value,
        quantity_value,
        depth_budget,
        steps,
        filled,
        remaining,
        notional,
        numeric.fixed(notional, output_scale_value),
        weighted,
        depth_exhausted,
        stop == LimitConstraint,
        stop,
      ))
    }
  }
}

fn sweep_levels(
  levels: List(DepthLevel),
  side: Side,
  limit: Decimal,
  price_budget: Decimal,
  remaining: Decimal,
  notional: Decimal,
  level_number: Int,
  maximum_levels: Int,
  reversed_steps: List(DepthStep),
) -> #(List(DepthStep), Decimal, Decimal, SweepStop) {
  case numeric.positive(remaining), level_number > maximum_levels, levels {
    False, _, _ -> #(
      list.reverse(reversed_steps),
      remaining,
      notional,
      QuantitySatisfied,
    )
    _, True, _ -> #(
      list.reverse(reversed_steps),
      remaining,
      notional,
      DepthBudgetExhausted,
    )
    _, _, [] -> #(
      list.reverse(reversed_steps),
      remaining,
      notional,
      VisibleSnapshotExhausted,
    )
    True, False, [level, ..rest] -> {
      let limit_allowed = price_allowed(side, level.price, limit)
      let budget_allowed = price_allowed(side, level.price, price_budget)
      case limit_allowed, budget_allowed {
        False, _ -> {
          let step =
            step(
              level_number,
              level,
              decimal.zero(),
              remaining,
              LimitConstraint,
            )
          #(
            list.reverse([step, ..reversed_steps]),
            remaining,
            notional,
            LimitConstraint,
          )
        }
        _, False -> {
          let step =
            step(
              level_number,
              level,
              decimal.zero(),
              remaining,
              PriceBudgetConstraint,
            )
          #(
            list.reverse([step, ..reversed_steps]),
            remaining,
            notional,
            PriceBudgetConstraint,
          )
        }
        True, True -> {
          let consumed = numeric.minimum(remaining, level.visible_quantity)
          let next_remaining = decimal.subtract(remaining, consumed)
          let next_notional =
            decimal.add(notional, decimal.multiply(consumed, level.price))
          let step =
            DepthStep(
              level_number,
              level.price,
              level.price_lexeme,
              level.visible_quantity,
              level.quantity_lexeme,
              consumed,
              next_remaining,
              Consumed,
            )
          sweep_levels(
            rest,
            side,
            limit,
            price_budget,
            next_remaining,
            next_notional,
            level_number + 1,
            maximum_levels,
            [step, ..reversed_steps],
          )
        }
      }
    }
  }
}

fn step(
  level_number: Int,
  level: DepthLevel,
  filled: Decimal,
  remaining: Decimal,
  stop: SweepStop,
) -> DepthStep {
  DepthStep(
    level_number,
    level.price,
    level.price_lexeme,
    level.visible_quantity,
    level.quantity_lexeme,
    filled,
    remaining,
    Stopped(stop),
  )
}

fn price_allowed(side: Side, price: Decimal, boundary: Decimal) -> Bool {
  case side, decimal.compare(price, boundary) {
    instruction.Buy, Lt | instruction.Buy, Eq -> True
    instruction.Sell, Gt | instruction.Sell, Eq -> True
    _, _ -> False
  }
}

pub type DailyBar {
  DailyBar(open: Decimal, high: Decimal, low: Decimal, close: Decimal)
}

pub type BranchOutcome {
  CompatibleFill
  CompatibleNonFill
  StopTriggeredFirst
  TargetReachedFirst
  UnknownOrdering
  StopReached
  TargetReached
}

pub type SimulationBranch {
  SimulationBranch(
    branch_id: String,
    outcome: BranchOutcome,
    compatible_price_range: Option(#(Decimal, Decimal)),
    note: String,
  )
}

pub opaque type BranchResult {
  BranchResult(
    model: String,
    result_kind: ResultKind,
    branches: List(SimulationBranch),
  )
}

pub fn daily_bar(
  open open_value: Decimal,
  high high_value: Decimal,
  low low_value: Decimal,
  close close_value: Decimal,
) -> Result(DailyBar, SimulationError) {
  case
    decimal.compare(high_value, low_value),
    decimal.compare(open_value, high_value),
    decimal.compare(open_value, low_value),
    decimal.compare(close_value, high_value),
    decimal.compare(close_value, low_value)
  {
    Lt, _, _, _, _ -> Error(InvalidBarGeometry)
    _, Gt, _, _, _ -> Error(InvalidBarGeometry)
    _, _, Lt, _, _ -> Error(InvalidBarGeometry)
    _, _, _, Gt, _ -> Error(InvalidBarGeometry)
    _, _, _, _, Lt -> Error(InvalidBarGeometry)
    _, _, _, _, _ ->
      Ok(DailyBar(open_value, high_value, low_value, close_value))
  }
}

pub fn limit_possible_paths(
  bar bar_value: DailyBar,
  side side_value: Side,
  limit_price limit_value: Decimal,
) -> BranchResult {
  let touched = case side_value {
    instruction.Buy -> decimal.compare(bar_value.low, limit_value) != Gt
    instruction.Sell -> decimal.compare(bar_value.high, limit_value) != Lt
  }
  let range = case side_value {
    instruction.Buy -> #(bar_value.low, limit_value)
    instruction.Sell -> #(limit_value, bar_value.high)
  }
  let branches = case touched {
    True -> [
      SimulationBranch(
        "compatible_fill",
        CompatibleFill,
        Some(range),
        "a fill at or better than the limit is compatible with the bar",
      ),
      SimulationBranch(
        "compatible_non_fill",
        CompatibleNonFill,
        None,
        "bar touch does not prove the specific order filled",
      ),
    ]
    False -> [
      SimulationBranch(
        "compatible_non_fill",
        CompatibleNonFill,
        None,
        "the supplied bar did not reach the limit price",
      ),
    ]
  }
  BranchResult(bar_possible_paths_v1, Hypothetical, branches)
}

pub fn stop_target_possible_paths(
  bar bar_value: DailyBar,
  stop_price stop_value: Decimal,
  target_price target_value: Decimal,
) -> BranchResult {
  let stop_touched = decimal.compare(bar_value.low, stop_value) != Gt
  let target_touched = decimal.compare(bar_value.high, target_value) != Lt
  let branches = case stop_touched, target_touched {
    True, True -> [
      SimulationBranch(
        "stop_triggered_first",
        StopTriggeredFirst,
        None,
        "a path reaching the low before the high is compatible with the bar",
      ),
      SimulationBranch(
        "target_reached_first",
        TargetReachedFirst,
        None,
        "a path reaching the high before the low is compatible with the bar",
      ),
      SimulationBranch(
        "unknown_ordering",
        UnknownOrdering,
        None,
        "the daily bar does not prove intraday sequence",
      ),
    ]
    True, False -> [
      SimulationBranch(
        "stop_reached",
        StopReached,
        None,
        "the bar range includes the stop and excludes the target",
      ),
    ]
    False, True -> [
      SimulationBranch(
        "target_reached",
        TargetReached,
        None,
        "the bar range includes the target and excludes the stop",
      ),
    ]
    False, False -> []
  }
  BranchResult(bar_possible_paths_v1, Hypothetical, branches)
}

pub fn result_model(value: SweepResult) -> String {
  value.model
}

pub fn result_kind(value: SweepResult) -> ResultKind {
  value.result_kind
}

pub fn snapshot_receipt(value: SweepResult) -> Sha256 {
  value.snapshot_receipt
}

pub fn steps(value: SweepResult) -> List(DepthStep) {
  value.steps
}

pub fn sweep_side(value: SweepResult) -> Side {
  value.side
}

pub fn limit_price(value: SweepResult) -> Decimal {
  value.limit_price
}

pub fn price_budget(value: SweepResult) -> Decimal {
  value.price_budget
}

pub fn requested_quantity(value: SweepResult) -> Decimal {
  value.requested_quantity
}

pub fn maximum_depth_levels(value: SweepResult) -> Int {
  value.maximum_depth_levels
}

pub fn filled_quantity(value: SweepResult) -> Decimal {
  value.filled_quantity
}

pub fn remaining_quantity(value: SweepResult) -> Decimal {
  value.remaining_quantity
}

pub fn fill_notional(value: SweepResult) -> Decimal {
  value.fill_notional
}

pub fn fill_notional_lexeme(value: SweepResult) -> String {
  value.fill_notional_lexeme
}

pub fn weighted_fill_price(value: SweepResult) -> WeightedPrice {
  value.weighted_fill_price
}

pub fn depth_exhausted(value: SweepResult) -> Bool {
  value.depth_exhausted
}

pub fn stopped_by_limit(value: SweepResult) -> Bool {
  value.stopped_by_limit
}

pub fn sweep_stop(value: SweepResult) -> SweepStop {
  value.stop
}

pub fn branch_model(value: BranchResult) -> String {
  value.model
}

pub fn branch_result_kind(value: BranchResult) -> ResultKind {
  value.result_kind
}

pub fn branches(value: BranchResult) -> List(SimulationBranch) {
  value.branches
}

pub fn depth_level_price(value: DepthLevel) -> Decimal {
  value.price
}

pub fn depth_level_visible_quantity(value: DepthLevel) -> Decimal {
  value.visible_quantity
}

pub fn result_kind_name(value: ResultKind) -> String {
  case value {
    Hypothetical -> "hypothetical"
    HistoricalReplay -> "historical_replay"
    ObservedBrokerReceipt -> "observed_broker_receipt"
    LlmDeclaredScenario -> "llm_declared_scenario"
  }
}

pub fn branch_outcome_name(value: BranchOutcome) -> String {
  case value {
    CompatibleFill -> "compatible_fill"
    CompatibleNonFill -> "compatible_non_fill"
    StopTriggeredFirst -> "stop_triggered_first"
    TargetReachedFirst -> "target_reached_first"
    UnknownOrdering -> "unknown_ordering"
    StopReached -> "stop_reached"
    TargetReached -> "target_reached"
  }
}
