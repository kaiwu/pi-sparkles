import finance_track.{type Track}
import gleam/int
import gleam/list
import gleam/result
import gleam/string

/// Evidence maturity for one declared credibility criterion.
///
/// This is deliberately discrete. Callers cannot invent a persuasive-looking
/// 73% for an individual criterion.
pub type Level {
  Verified
  Partial
  Missing
}

pub type Importance {
  Critical
  Standard
}

pub opaque type Criterion {
  Criterion(id: String, importance: Importance, level: Level, evidence: String)
}

pub type Readiness {
  OperationallyCredible
  LimitedCredibility
}

/// An equal-weight evidence-maturity receipt for one track source set.
///
/// The percentage is not a probability that a claim is true. It reports how
/// many declared source controls are verified, partial, or missing.
pub opaque type Assessment {
  Assessment(
    track: Track,
    source_set: String,
    readiness: Readiness,
    score_basis_points: Int,
    minimum_basis_points: Int,
    criteria: List(Criterion),
    critical_gaps: List(String),
  )
}

pub type CredibilityError {
  InvalidCriterionId
  InvalidEvidence
  InvalidSourceSet
  InvalidThreshold
  EmptyCriteria
  DuplicateCriterion(id: String)
}

pub fn criterion(
  id id_value: String,
  importance importance_value: Importance,
  level level_value: Level,
  evidence evidence_value: String,
) -> Result(Criterion, CredibilityError) {
  case valid_id(id_value), valid_text(evidence_value, 500) {
    False, _ -> Error(InvalidCriterionId)
    _, False -> Error(InvalidEvidence)
    True, True ->
      Ok(Criterion(id_value, importance_value, level_value, evidence_value))
  }
}

/// Construct the agreed operational credibility gate at 85%.
pub fn operational_assessment(
  track track_value: Track,
  source_set source_set_value: String,
  criteria criterion_values: List(Criterion),
) -> Result(Assessment, CredibilityError) {
  assess(track_value, source_set_value, 8500, criterion_values)
}

pub fn assess(
  track track_value: Track,
  source_set source_set_value: String,
  minimum_basis_points minimum: Int,
  criteria criterion_values: List(Criterion),
) -> Result(Assessment, CredibilityError) {
  case
    valid_id(source_set_value),
    minimum > 0 && minimum <= 10_000,
    criterion_values
  {
    False, _, _ -> Error(InvalidSourceSet)
    _, False, _ -> Error(InvalidThreshold)
    True, True, [] -> Error(EmptyCriteria)
    True, True, [_, ..] -> {
      use _ <- result.try(validate_criteria(criterion_values, []))
      let score = calculate_score_basis_points(criterion_values)
      let critical_gaps =
        criterion_values
        |> list.filter(fn(value) {
          value.importance == Critical && value.level != Verified
        })
        |> list.map(fn(value) { value.id })
      let readiness = case score >= minimum, critical_gaps {
        True, [] -> OperationallyCredible
        _, _ -> LimitedCredibility
      }
      Ok(Assessment(
        track: track_value,
        source_set: source_set_value,
        readiness: readiness,
        score_basis_points: score,
        minimum_basis_points: minimum,
        criteria: criterion_values,
        critical_gaps: critical_gaps,
      ))
    }
  }
}

pub fn track(value: Assessment) -> Track {
  value.track
}

pub fn source_set(value: Assessment) -> String {
  value.source_set
}

pub fn readiness(value: Assessment) -> Readiness {
  value.readiness
}

pub fn score_basis_points(value: Assessment) -> Int {
  value.score_basis_points
}

pub fn score_percentage(value: Assessment) -> Int {
  let assert Ok(percentage) = int.divide(value.score_basis_points, by: 100)
  percentage
}

pub fn minimum_basis_points(value: Assessment) -> Int {
  value.minimum_basis_points
}

pub fn criteria(value: Assessment) -> List(Criterion) {
  value.criteria
}

pub fn critical_gaps(value: Assessment) -> List(String) {
  value.critical_gaps
}

pub fn criterion_id(value: Criterion) -> String {
  value.id
}

pub fn criterion_importance(value: Criterion) -> Importance {
  value.importance
}

pub fn criterion_level(value: Criterion) -> Level {
  value.level
}

pub fn criterion_evidence(value: Criterion) -> String {
  value.evidence
}

fn calculate_score_basis_points(values: List(Criterion)) -> Int {
  let achieved =
    values
    |> list.fold(0, fn(total, value) { total + level_points(value.level) })
  let assert Ok(score) = int.divide(achieved, by: list.length(values))
  score
}

fn level_points(value: Level) -> Int {
  case value {
    Verified -> 10_000
    Partial -> 5000
    Missing -> 0
  }
}

fn validate_criteria(
  values: List(Criterion),
  seen: List(String),
) -> Result(Nil, CredibilityError) {
  case values {
    [] -> Ok(Nil)
    [first, ..rest] ->
      case list.contains(seen, first.id) {
        True -> Error(DuplicateCriterion(first.id))
        False -> validate_criteria(rest, [first.id, ..seen])
      }
  }
}

fn valid_id(value: String) -> Bool {
  value != ""
  && string.trim(value) == value
  && string.length(value) <= 100
  && value
  |> string.to_graphemes
  |> list.all(fn(character) {
    string.contains("abcdefghijklmnopqrstuvwxyz0123456789_", character)
  })
}

fn valid_text(value: String, maximum_length: Int) -> Bool {
  value != ""
  && string.trim(value) == value
  && string.length(value) <= maximum_length
  && !string.contains(value, "\r")
  && !string.contains(value, "\n")
}
