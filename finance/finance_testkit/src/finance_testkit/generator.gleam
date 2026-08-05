import finance_core/adjustment
import finance_core/currency.{type Currency}
import finance_core/decimal.{type Decimal}
import finance_core/market
import finance_core/money.{type Money}
import finance_core/observation
import finance_core/source
import finance_core/time.{type Instant}
import finance_testkit/seed.{type Seed}
import gleam/int
import gleam/option.{None, Some}

pub const algorithm_version = 1

pub const provider = "SYNTHETIC_TEST_DATA"

pub type Quote {
  Quote(price: observation.Observation(Decimal), size: Decimal)
}

pub type Bar {
  Bar(
    open: Decimal,
    high: Decimal,
    low: Decimal,
    close: Decimal,
    volume: Decimal,
    as_of: Instant,
    adjustment: adjustment.Adjustment,
  )
}

pub type CorporateAction {
  Split(ratio: Decimal)
  CashDividend(amount: Money)
}

pub type GeneratorError {
  SeedFailure
  DecimalFailure
  SourceFailure
}

pub fn quote(
  seed initial: Seed,
  as_of as_of: Instant,
  currency currency_value: Currency,
) -> Result(#(Seed, Quote), GeneratorError) {
  use #(after_price, cents) <- result_try(
    seed.between(initial, 100, 1_000_000) |> map_seed_error,
  )
  use #(after_size, size) <- result_try(
    seed.between(after_price, 1, 100_000) |> map_seed_error,
  )
  use price <- result_try(decimal_from_cents(cents))
  use size <- result_try(decimal_from_integer(size))
  use source_ref <- result_try(synthetic_source("quote"))
  let value =
    observation.Observation(
      value: price,
      as_of: as_of,
      retrieved_at: as_of,
      timezone: None,
      source: source_ref,
      evidence_id: None,
      freshness: observation.UnknownFreshness,
      entitlement: observation.UnknownEntitlement,
      quality: observation.Estimated,
      unit: Some(market.CurrencyPerShare(currency_value)),
      adjustment: Some(adjustment.Raw),
      session: Some(market.Regular),
    )
  Ok(#(after_size, Quote(value, size)))
}

pub fn bar(
  seed initial: Seed,
  as_of as_of: Instant,
) -> Result(#(Seed, Bar), GeneratorError) {
  use #(after_base, base) <- result_try(
    seed.between(initial, 10_000, 1_000_000) |> map_seed_error,
  )
  use #(after_up, up) <- result_try(
    seed.between(after_base, 0, 1000) |> map_seed_error,
  )
  use #(after_down, down) <- result_try(
    seed.between(after_up, 0, 1000) |> map_seed_error,
  )
  use #(after_close, close_delta) <- result_try(
    seed.between(after_down, 0 - down, up) |> map_seed_error,
  )
  use #(after_volume, volume) <- result_try(
    seed.between(after_close, 0, 10_000_000) |> map_seed_error,
  )
  use open <- result_try(decimal_from_cents(base))
  use high <- result_try(decimal_from_cents(base + up))
  use low <- result_try(decimal_from_cents(base - down))
  use close <- result_try(decimal_from_cents(base + close_delta))
  use volume <- result_try(decimal_from_integer(volume))
  Ok(#(after_volume, Bar(open, high, low, close, volume, as_of, adjustment.Raw)))
}

pub fn split(
  ratio_numerator: Int,
  ratio_denominator: Int,
) -> Result(CorporateAction, GeneratorError) {
  use numerator <- result_try(decimal_from_integer(ratio_numerator))
  use denominator <- result_try(decimal_from_integer(ratio_denominator))
  case
    decimal.divide(
      numerator,
      by: denominator,
      scale: 8,
      rounding: decimal.HalfEven,
    )
  {
    Ok(value) -> Ok(Split(value))
    Error(_) -> Error(DecimalFailure)
  }
}

fn decimal_from_integer(value: Int) -> Result(Decimal, GeneratorError) {
  case value |> int.to_string |> decimal.parse {
    Ok(value) -> Ok(value)
    Error(_) -> Error(DecimalFailure)
  }
}

fn decimal_from_cents(value: Int) -> Result(Decimal, GeneratorError) {
  let whole = value / 100
  let fraction = value % 100
  let encoded =
    int.to_string(whole)
    <> "."
    <> case fraction < 10 {
      True -> "0" <> int.to_string(fraction)
      False -> int.to_string(fraction)
    }
  case decimal.parse(encoded) {
    Ok(value) -> Ok(value)
    Error(_) -> Error(DecimalFailure)
  }
}

fn synthetic_source(
  reference: String,
) -> Result(source.SourceRef, GeneratorError) {
  case
    source.new(provider: provider, reference: reference, kind: source.Synthetic)
  {
    Ok(value) -> Ok(value)
    Error(_) -> Error(SourceFailure)
  }
}

fn map_seed_error(
  result: Result(value, seed.SeedError),
) -> Result(value, GeneratorError) {
  case result {
    Ok(value) -> Ok(value)
    Error(_) -> Error(SeedFailure)
  }
}

fn result_try(
  result: Result(value, error),
  next: fn(value) -> Result(next, error),
) -> Result(next, error) {
  case result {
    Ok(value) -> next(value)
    Error(error) -> Error(error)
  }
}
