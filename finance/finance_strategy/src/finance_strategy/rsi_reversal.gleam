import finance_core/time.{type Date}
import finance_strategy/definition.{type Definition, type DefinitionError}
import finance_track
import gleam/option.{type Option}
import gleam/result

pub const strategy_id = "rsi_reversal_daily_long"

pub const strategy_version = "1.0.0"

/// Construct the reviewed RSI-reversal hypothesis as executable data.
///
/// The values here are declaration parameters only. This package does not
/// calculate an SMA, RSI, distance, eligibility, or liquidity measure.
pub fn v1(
  valid_from valid_from_value: Date,
  valid_through valid_through_value: Option(Date),
) -> Result(Definition, DefinitionError) {
  use parameters <- result.try(parameters())
  use predicates <- result.try(predicates())
  use lifecycle <- result.try(definition.lifecycle_policy(
    entry_valid_sessions: 2,
    maximum_holding_sessions: 10,
    monitoring: "completed_daily_close",
    trailing_stop_intent: "versioned_daily_close_trail",
  ))
  definition.new(
    id: strategy_id,
    version: strategy_version,
    hypothesis: "A long-only daily RSI reversal above a long trend may identify a bounded next-session swing setup.",
    negative_claims: [
      "No positive-expectancy claim.",
      "No intraday, short-selling, position-sizing, fill, or provider-coverage claim.",
      "Optional confirmations and ranking are not required predicates.",
    ],
    tracks: [finance_track.Cn, finance_track.Hk, finance_track.Us],
    valid_from: valid_from_value,
    valid_through: valid_through_value,
    parameters: parameters,
    predicates: predicates,
    setup_requirements: [
      definition.ExactIdentity,
      definition.CompletedSession,
      definition.CompletedDailyData,
      definition.AdjustmentProvenance,
      definition.SourceRights,
      definition.Freshness,
    ],
    acceptance_requirements: [
      definition.MarketRules,
      definition.RiskPolicy,
      definition.ExecutionCapability,
    ],
    lifecycle: lifecycle,
  )
}

fn parameters() -> Result(List(definition.Parameter), DefinitionError) {
  use long_ma <- result.try(definition.parameter(
    "long_ma_sessions",
    "200",
    "trading_sessions",
  ))
  use medium_ma <- result.try(definition.parameter(
    "medium_ma_sessions",
    "50",
    "trading_sessions",
  ))
  use rsi_period <- result.try(definition.parameter(
    "rsi_sessions",
    "14",
    "trading_sessions",
  ))
  use rsi_threshold <- result.try(definition.parameter(
    "rsi_oversold_threshold",
    "30",
    "index_points",
  ))
  use distance <- result.try(definition.parameter(
    "maximum_medium_ma_distance",
    "0.03",
    "fraction_of_price",
  ))
  Ok([long_ma, medium_ma, rsi_period, rsi_threshold, distance])
}

fn predicates() -> Result(List(definition.Predicate), DefinitionError) {
  use eligible <- result.try(definition.predicate(
    "eligible_liquid_universe",
    definition.Required,
    "universe_eligibility_v1",
    "The exact listing is point-in-time eligible, tradeable, and liquid under the selected universe policy.",
  ))
  use trend <- result.try(definition.predicate(
    "close_above_long_ma",
    definition.Required,
    "sma_200_v1",
    "The completed-session close is above the versioned long moving average.",
  ))
  use oversold <- result.try(definition.predicate(
    "rsi_at_or_below_threshold",
    definition.Required,
    "rsi_14_v1",
    "RSI is at or below the declared oversold threshold.",
  ))
  use rising <- result.try(definition.predicate(
    "rsi_strictly_rising",
    definition.Required,
    "rsi_14_prior_comparison_v1",
    "RSI is strictly higher than its prior trading-session value.",
  ))
  use proximity <- result.try(definition.predicate(
    "close_near_medium_ma",
    definition.Required,
    "sma_50_distance_v1",
    "The completed-session close is within the declared distance of the medium moving average.",
  ))
  use volume <- result.try(definition.predicate(
    "volume_confirmation",
    definition.Confirmation,
    "volume_confirmation_v1",
    "Optional volume evidence confirms the reversal under explicit units and semantics.",
  ))
  use sector <- result.try(definition.predicate(
    "sector_regime_confirmation",
    definition.Ranking,
    "sector_regime_v1",
    "Optional point-in-time sector and regime context contributes only to ranking.",
  ))
  Ok([eligible, trend, oversold, rising, proximity, volume, sector])
}
