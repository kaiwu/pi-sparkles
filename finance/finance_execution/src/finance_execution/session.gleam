import finance_core/time
import finance_execution/fact.{type Fact}
import finance_provenance/identity.{type Sha256}
import gleam/list

pub type PhaseInterval {
  PhaseInterval(
    phase: String,
    starts_at: time.Instant,
    ends_at: time.Instant,
    source_reference: Sha256,
  )
}

pub type Comparison {
  Compared(
    timestamp: time.Instant,
    requested_phase: String,
    matching_intervals: List(PhaseInterval),
    in_window: Bool,
  )
  ComparisonUnperformed(
    timestamp: time.Instant,
    requested_phase: String,
    reason: String,
  )
}

pub fn timestamp_in_phase(
  timestamp timestamp_value: time.Instant,
  requested_phase phase_value: String,
  phase_intervals intervals_value: Fact(List(PhaseInterval)),
) -> Comparison {
  case fact.known_value(intervals_value) {
    Error(reason) -> ComparisonUnperformed(timestamp_value, phase_value, reason)
    Ok(sourced) -> {
      let matching =
        fact.sourced_value(sourced)
        |> list.filter(fn(interval) {
          interval.phase == phase_value
          && time.unix_milliseconds(timestamp_value)
          >= time.unix_milliseconds(interval.starts_at)
          && time.unix_milliseconds(timestamp_value)
          <= time.unix_milliseconds(interval.ends_at)
        })
      Compared(timestamp_value, phase_value, matching, !list.is_empty(matching))
    }
  }
}
