import gleam/list

/// A fact slot always survives even when its value is unavailable.
///
/// These states describe evidence availability. They are not correctness,
/// readiness, or trading verdicts.
pub type Fact(value) {
  Known(value)
  Unknown(reason: String)
  NotObtained(reason: String)
  Conflicting(alternatives: List(value))
  DecodeFailure(raw: String, reason: String)
}

pub fn map(
  value: Fact(value),
  with transform: fn(value) -> mapped,
) -> Fact(mapped) {
  case value {
    Known(value) -> Known(transform(value))
    Unknown(reason) -> Unknown(reason)
    NotObtained(reason) -> NotObtained(reason)
    Conflicting(values) -> Conflicting(list.map(values, transform))
    DecodeFailure(raw, reason) -> DecodeFailure(raw, reason)
  }
}

pub fn values(value: Fact(value)) -> List(value) {
  case value {
    Known(value) -> [value]
    Conflicting(values) -> values
    Unknown(_) | NotObtained(_) | DecodeFailure(_, _) -> []
  }
}

pub fn is_known(value: Fact(value)) -> Bool {
  case value {
    Known(_) -> True
    Unknown(_) | NotObtained(_) | Conflicting(_) | DecodeFailure(_, _) -> False
  }
}
