import gleam/list

/// An attributed journal slot. These constructors retain information states;
/// none is a workflow, psychology, process, or trade decision.
pub type Information(value) {
  Known(value)
  Unknown(reason: String)
  NotAsked
  NotObtained(reason: String)
  Declined
  NotApplicable(reason: String)
  Conflicting(alternatives: List(value), reason: String)
  DecodeFailure(raw: String, reason: String)
  Redacted(metadata: String)
  Superseded(new_event_id: String)
}

pub fn state_name(value: Information(a)) -> String {
  case value {
    Known(_) -> "known"
    Unknown(_) -> "unknown"
    NotAsked -> "not_asked"
    NotObtained(_) -> "not_obtained"
    Declined -> "declined"
    NotApplicable(_) -> "not_applicable"
    Conflicting(_, _) -> "conflicting"
    DecodeFailure(_, _) -> "decode_failure"
    Redacted(_) -> "redacted"
    Superseded(_) -> "superseded"
  }
}

pub fn known_values(value: Information(a)) -> List(a) {
  case value {
    Known(value) -> [value]
    Conflicting(values, _) -> values
    _ -> []
  }
}

pub fn map(value: Information(a), transform: fn(a) -> b) -> Information(b) {
  case value {
    Known(value) -> Known(transform(value))
    Unknown(reason) -> Unknown(reason)
    NotAsked -> NotAsked
    NotObtained(reason) -> NotObtained(reason)
    Declined -> Declined
    NotApplicable(reason) -> NotApplicable(reason)
    Conflicting(values, reason) ->
      Conflicting(list.map(values, transform), reason)
    DecodeFailure(raw, reason) -> DecodeFailure(raw, reason)
    Redacted(metadata) -> Redacted(metadata)
    Superseded(id) -> Superseded(id)
  }
}
