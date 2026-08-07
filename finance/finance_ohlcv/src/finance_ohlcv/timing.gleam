import finance_core/time.{type Instant, type Timezone}
import finance_ohlcv.{type TimeBasis}
import finance_ohlcv/fact.{type Fact}

pub opaque type TimingFacts {
  TimingFacts(
    source_timestamp: Fact(String),
    provider_publication_time: Fact(Instant),
    retrieved_at: Instant,
    timezone: Fact(Timezone),
    session_close: Fact(Instant),
    next_session_open: Fact(Instant),
    time_basis: Fact(TimeBasis),
    calendar_version: Fact(String),
  )
}

/// A caller-requested mechanical comparison with all inputs retained.
pub opaque type ComparisonReceipt {
  ComparisonReceipt(
    name: String,
    instruction_reference: String,
    left_label: String,
    left: Instant,
    right_label: String,
    right: Instant,
    result: Bool,
  )
}

pub fn new(
  source_timestamp source_timestamp_value: Fact(String),
  provider_publication_time publication_value: Fact(Instant),
  retrieved_at retrieved_value: Instant,
  timezone timezone_value: Fact(Timezone),
  session_close close_value: Fact(Instant),
  next_session_open next_open_value: Fact(Instant),
  time_basis time_basis_value: Fact(TimeBasis),
  calendar_version calendar_version_value: Fact(String),
) -> TimingFacts {
  TimingFacts(
    source_timestamp_value,
    publication_value,
    retrieved_value,
    timezone_value,
    close_value,
    next_open_value,
    time_basis_value,
    calendar_version_value,
  )
}

pub fn retrieval_before_next_open(
  value: TimingFacts,
  instruction_reference instruction: String,
) -> Fact(ComparisonReceipt) {
  case value.next_session_open {
    fact.Known(next_open) ->
      fact.Known(ComparisonReceipt(
        "retrieval_before_next_open",
        instruction,
        "retrieved_at",
        value.retrieved_at,
        "next_session_open",
        next_open,
        time.unix_milliseconds(value.retrieved_at)
          < time.unix_milliseconds(next_open),
      ))
    fact.Unknown(reason) ->
      fact.NotObtained("next_session_open_unknown:" <> reason)
    fact.NotObtained(reason) ->
      fact.NotObtained("next_session_open_not_obtained:" <> reason)
    fact.Conflicting(_) -> fact.NotObtained("next_session_open_conflicting")
    fact.DecodeFailure(_, reason) ->
      fact.NotObtained("next_session_open_decode_failure:" <> reason)
  }
}

pub fn source_timestamp(value: TimingFacts) -> Fact(String) {
  value.source_timestamp
}

pub fn provider_publication_time(value: TimingFacts) -> Fact(Instant) {
  value.provider_publication_time
}

pub fn retrieved_at(value: TimingFacts) -> Instant {
  value.retrieved_at
}

pub fn timezone(value: TimingFacts) -> Fact(Timezone) {
  value.timezone
}

pub fn session_close(value: TimingFacts) -> Fact(Instant) {
  value.session_close
}

pub fn next_session_open(value: TimingFacts) -> Fact(Instant) {
  value.next_session_open
}

pub fn time_basis(value: TimingFacts) -> Fact(TimeBasis) {
  value.time_basis
}

pub fn calendar_version(value: TimingFacts) -> Fact(String) {
  value.calendar_version
}

pub fn comparison_name(value: ComparisonReceipt) -> String {
  value.name
}

pub fn comparison_instruction_reference(value: ComparisonReceipt) -> String {
  value.instruction_reference
}

pub fn comparison_left(value: ComparisonReceipt) -> #(String, Instant) {
  #(value.left_label, value.left)
}

pub fn comparison_right(value: ComparisonReceipt) -> #(String, Instant) {
  #(value.right_label, value.right)
}

pub fn comparison_result(value: ComparisonReceipt) -> Bool {
  value.result
}
