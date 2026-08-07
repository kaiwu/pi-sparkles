import finance_core/time.{type Date, type Instant}
import finance_ohlcv/acquisition_receipt.{type Receipt}
import finance_ohlcv/fact.{type Fact}
import gleam/int
import gleam/json

pub type EffectiveBudget {
  PageBudget(maximum_pages: Int)
  BarBudget(maximum_bars: Int)
  ByteBudget(maximum_bytes: Int)
  TimeoutBudget(maximum_milliseconds: Int)
}

pub type Outcome {
  TransportComplete
  CancelledByCaller(at: Instant)
  TimedOut(at: Instant, budget_ms: Int)
  ProviderError(at: Instant, reason: String)
}

/// One bounded retrieval attempt, including partial evidence.
pub opaque type Attempt {
  Attempt(
    receipt: Fact(Receipt),
    outcome: Outcome,
    budgets: List(EffectiveBudget),
    partial_bar_dates: List(Date),
  )
}

pub fn new(
  receipt receipt_value: Fact(Receipt),
  outcome outcome_value: Outcome,
  budgets budget_values: List(EffectiveBudget),
  partial_bar_dates dates: List(Date),
) -> Attempt {
  Attempt(receipt_value, outcome_value, budget_values, dates)
}

pub fn receipt(value: Attempt) -> Fact(Receipt) {
  value.receipt
}

pub fn outcome(value: Attempt) -> Outcome {
  value.outcome
}

pub fn budgets(value: Attempt) -> List(EffectiveBudget) {
  value.budgets
}

pub fn partial_bar_dates(value: Attempt) -> List(Date) {
  value.partial_bar_dates
}

/// Canonical attempt text binds effective budgets and interrupted partial data
/// in addition to the underlying acquisition receipt.
pub fn canonical_text(value: Attempt) -> String {
  json.object([
    #("receipt", receipt_fact_json(value.receipt)),
    #("outcome", outcome_json(value.outcome)),
    #("budgets", json.array(value.budgets, budget_json)),
    #("partial_bar_dates", json.array(value.partial_bar_dates, date_json)),
  ])
  |> json.to_string
}

fn receipt_fact_json(value: Fact(Receipt)) -> json.Json {
  case value {
    fact.Known(value) ->
      json.object([
        #("state", json.string("known")),
        #(
          "canonical_receipt",
          json.string(acquisition_receipt.canonical_text(value)),
        ),
      ])
    fact.Unknown(reason) -> state_reason("unknown", reason)
    fact.NotObtained(reason) -> state_reason("not_obtained", reason)
    fact.Conflicting(values) ->
      json.object([
        #("state", json.string("conflicting")),
        #(
          "canonical_receipts",
          json.array(values, fn(value) {
            value |> acquisition_receipt.canonical_text |> json.string
          }),
        ),
      ])
    fact.DecodeFailure(raw, reason) ->
      json.object([
        #("state", json.string("decode_failure")),
        #("raw", json.string(raw)),
        #("reason", json.string(reason)),
      ])
  }
}

fn outcome_json(value: Outcome) -> json.Json {
  case value {
    TransportComplete ->
      json.object([#("state", json.string("transport_complete"))])
    CancelledByCaller(at) -> timed_outcome("cancelled_by_caller", at, [])
    TimedOut(at, budget_ms) ->
      timed_outcome("timed_out", at, [#("budget_ms", json.int(budget_ms))])
    ProviderError(at, reason) ->
      timed_outcome("provider_error", at, [#("reason", json.string(reason))])
  }
}

fn timed_outcome(
  state: String,
  at: Instant,
  extra: List(#(String, json.Json)),
) -> json.Json {
  json.object([
    #("state", json.string(state)),
    #("at_unix_ms", json.int(time.unix_milliseconds(at))),
    ..extra
  ])
}

fn budget_json(value: EffectiveBudget) -> json.Json {
  case value {
    PageBudget(value) -> named_budget("page", value)
    BarBudget(value) -> named_budget("bar", value)
    ByteBudget(value) -> named_budget("byte", value)
    TimeoutBudget(value) -> named_budget("timeout_ms", value)
  }
}

fn named_budget(name: String, maximum: Int) -> json.Json {
  json.object([
    #("name", json.string(name)),
    #("maximum", json.int(maximum)),
  ])
}

fn state_reason(state: String, reason: String) -> json.Json {
  json.object([
    #("state", json.string(state)),
    #("reason", json.string(reason)),
  ])
}

fn date_json(value: Date) -> json.Json {
  let #(year, month, day) = time.date_parts(value)
  json.string(
    int.to_string(year) <> "-" <> two_digits(month) <> "-" <> two_digits(day),
  )
}

fn two_digits(value: Int) -> String {
  case value < 10 {
    True -> "0" <> int.to_string(value)
    False -> int.to_string(value)
  }
}
