import finance_core/observation.{type MissingReason}

/// Shared, data-only failures for exact formulas and approximate analytics.
pub type MetricError {
  EmptyInput
  InsufficientData(required: Int, actual: Int)
  LengthMismatch(left: Int, right: Int)
  DivisionByZero
  InvalidScale
  InvalidPeriod
  InvalidConfidence
  InvalidTolerance
  InvalidIterationLimit
  InvalidBounds
  InvalidWeight
  ZeroWeight
  InvalidModel
  SingularSystem
  InvalidCompounding
  DomainError
  NonFiniteInput
  NonFiniteOutput
  ZeroVariance
  NoSignChange
  RootNotBracketed
  DidNotConverge(iterations: Int)
  InvalidInputName
  DuplicateInput(name: String)
  UnknownInput(name: String)
  MissingInput(name: String, reason: MissingReason)
}
