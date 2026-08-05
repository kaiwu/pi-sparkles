import finance_track.{type Track}
import gleam/int
import gleam/list
import gleam/result
import gleam/string

/// Critical requirements do not participate in the allowed 15% gap.
///
/// A family policy decides which facts are critical. Typical examples are
/// instrument identity, track/venue, time, unit, adjustment, source, and
/// entitlement. Everything else may be Standard without becoming optional or
/// being silently filled.
pub type Importance {
  Critical
  Standard
}

pub opaque type Requirement {
  Requirement(id: String, importance: Importance)
}

/// One accepted channel's contribution to a declared family denominator.
///
/// `source_group` is the underlying origin, not the retrieval adapter. Direct
/// SSE and SSE-via-a-mirror therefore use the same group and cannot manufacture
/// two-source corroboration.
pub opaque type Contribution {
  Contribution(
    track: Track,
    channel_id: String,
    source_group: String,
    covered_requirements: List(String),
  )
}

/// Coverage policy for one data family in one track.
///
/// Coverage is assessed independently per family. Callers must not average a
/// strong family with a weak family to cross the threshold.
pub opaque type Policy {
  Policy(
    track: Track,
    family: String,
    minimum_basis_points: Int,
    minimum_source_groups: Int,
  )
}

pub type Readiness {
  OperationallyReady
  BelowThreshold
}

pub opaque type Assessment {
  Assessment(
    track: Track,
    family: String,
    readiness: Readiness,
    coverage_basis_points: Int,
    requirement_count: Int,
    covered_count: Int,
    covered_requirements: List(String),
    missing_requirements: List(String),
    missing_critical_requirements: List(String),
    source_groups: List(String),
    contributions: List(Contribution),
    minimum_basis_points: Int,
    minimum_source_groups: Int,
  )
}

pub type PictureReadiness {
  OperationalPicture
  IncompletePicture
}

/// A picture is ready only when every applicable family independently passes.
/// There is deliberately no blended average.
pub opaque type Picture {
  Picture(
    track: Track,
    readiness: PictureReadiness,
    assessments: List(Assessment),
  )
}

pub type CoverageError {
  InvalidRequirementId
  InvalidFamily
  InvalidThreshold
  InvalidMinimumSourceGroups
  InvalidChannelId
  WrongTrackChannelId(expected_prefix: String)
  InvalidSourceGroup
  EmptyContribution(channel_id: String)
  DuplicateCoveredRequirement(channel_id: String, requirement_id: String)
  EmptyRequirements
  DuplicateRequirement(requirement_id: String)
  DuplicateChannel(channel_id: String)
  ContributionTrackMismatch(channel_id: String)
  UnknownRequirement(channel_id: String, requirement_id: String)
  EmptyAssessments
  AssessmentTrackMismatch(family: String)
  DuplicateFamily(family: String)
}

pub fn requirement(
  id id_value: String,
  importance importance_value: Importance,
) -> Result(Requirement, CoverageError) {
  case valid_id(id_value) {
    True -> Ok(Requirement(id_value, importance_value))
    False -> Error(InvalidRequirementId)
  }
}

/// Construct the agreed operational policy: 85% union coverage for one family.
pub fn operational_policy(
  track track_value: Track,
  family family_value: String,
  minimum_source_groups minimum_groups: Int,
) -> Result(Policy, CoverageError) {
  policy(track_value, family_value, 8500, minimum_groups)
}

pub fn policy(
  track track_value: Track,
  family family_value: String,
  minimum_basis_points minimum_coverage: Int,
  minimum_source_groups minimum_groups: Int,
) -> Result(Policy, CoverageError) {
  case
    valid_id(family_value),
    minimum_coverage > 0 && minimum_coverage <= 10_000,
    minimum_groups > 0 && minimum_groups <= 100
  {
    False, _, _ -> Error(InvalidFamily)
    _, False, _ -> Error(InvalidThreshold)
    _, _, False -> Error(InvalidMinimumSourceGroups)
    True, True, True ->
      Ok(Policy(track_value, family_value, minimum_coverage, minimum_groups))
  }
}

pub fn contribution(
  track track_value: Track,
  channel_id channel_id_value: String,
  source_group source_group_value: String,
  covered_requirements covered: List(String),
) -> Result(Contribution, CoverageError) {
  let prefix = finance_track.name(track_value) <> "_"
  case
    valid_id(channel_id_value),
    string.starts_with(channel_id_value, prefix),
    valid_term(source_group_value, 100),
    covered
  {
    False, _, _, _ -> Error(InvalidChannelId)
    _, False, _, _ -> Error(WrongTrackChannelId(prefix))
    _, _, False, _ -> Error(InvalidSourceGroup)
    True, True, True, [] -> Error(EmptyContribution(channel_id_value))
    True, True, True, [_, ..] ->
      case validate_covered(covered, channel_id_value, []) {
        Error(error) -> Error(error)
        Ok(Nil) ->
          Ok(Contribution(
            track_value,
            channel_id_value,
            source_group_value,
            covered,
          ))
      }
  }
}

pub fn assess(
  policy policy_value: Policy,
  requirements requirements_value: List(Requirement),
  contributions contribution_values: List(Contribution),
) -> Result(Assessment, CoverageError) {
  case requirements_value {
    [] -> Error(EmptyRequirements)
    [_, ..] -> {
      use _ <- result.try(validate_requirements(requirements_value, []))
      let requirement_ids =
        requirements_value |> list.map(fn(value) { value.id })
      use _ <- result.try(
        validate_contributions(
          contribution_values,
          policy_value.track,
          requirement_ids,
          [],
        ),
      )

      let covered_requirements =
        requirement_ids
        |> list.filter(fn(id) { contribution_covers(contribution_values, id) })
      let missing_requirements =
        requirement_ids
        |> list.filter(fn(id) { !list.contains(covered_requirements, id) })
      let missing_critical_requirements =
        requirements_value
        |> list.filter(fn(value) {
          value.importance == Critical
          && !list.contains(covered_requirements, value.id)
        })
        |> list.map(fn(value) { value.id })
      let source_groups = distinct_source_groups(contribution_values, [])
      let requirement_count = list.length(requirement_ids)
      let covered_count = list.length(covered_requirements)
      let coverage_basis_points = basis_points(covered_count, requirement_count)
      let readiness = case
        coverage_basis_points >= policy_value.minimum_basis_points,
        missing_critical_requirements,
        list.length(source_groups) >= policy_value.minimum_source_groups
      {
        True, [], True -> OperationallyReady
        _, _, _ -> BelowThreshold
      }

      Ok(Assessment(
        track: policy_value.track,
        family: policy_value.family,
        readiness: readiness,
        coverage_basis_points: coverage_basis_points,
        requirement_count: requirement_count,
        covered_count: covered_count,
        covered_requirements: covered_requirements,
        missing_requirements: missing_requirements,
        missing_critical_requirements: missing_critical_requirements,
        source_groups: source_groups,
        contributions: contribution_values,
        minimum_basis_points: policy_value.minimum_basis_points,
        minimum_source_groups: policy_value.minimum_source_groups,
      ))
    }
  }
}

pub fn picture(
  track track_value: Track,
  assessments assessment_values: List(Assessment),
) -> Result(Picture, CoverageError) {
  case assessment_values {
    [] -> Error(EmptyAssessments)
    [_, ..] -> {
      use _ <- result.try(
        validate_assessments(assessment_values, track_value, []),
      )
      let readiness = case
        assessment_values
        |> list.all(fn(value) { value.readiness == OperationallyReady })
      {
        True -> OperationalPicture
        False -> IncompletePicture
      }
      Ok(Picture(track_value, readiness, assessment_values))
    }
  }
}

pub fn requirement_id(value: Requirement) -> String {
  value.id
}

pub fn requirement_importance(value: Requirement) -> Importance {
  value.importance
}

pub fn policy_track(value: Policy) -> Track {
  value.track
}

pub fn policy_family(value: Policy) -> String {
  value.family
}

pub fn minimum_basis_points(value: Policy) -> Int {
  value.minimum_basis_points
}

pub fn minimum_source_groups(value: Policy) -> Int {
  value.minimum_source_groups
}

pub fn assessment_track(value: Assessment) -> Track {
  value.track
}

pub fn assessment_family(value: Assessment) -> String {
  value.family
}

pub fn assessment_readiness(value: Assessment) -> Readiness {
  value.readiness
}

pub fn coverage_basis_points(value: Assessment) -> Int {
  value.coverage_basis_points
}

pub fn requirement_count(value: Assessment) -> Int {
  value.requirement_count
}

pub fn covered_count(value: Assessment) -> Int {
  value.covered_count
}

pub fn covered_requirements(value: Assessment) -> List(String) {
  value.covered_requirements
}

pub fn missing_requirements(value: Assessment) -> List(String) {
  value.missing_requirements
}

pub fn missing_critical_requirements(value: Assessment) -> List(String) {
  value.missing_critical_requirements
}

pub fn source_groups(value: Assessment) -> List(String) {
  value.source_groups
}

pub fn assessment_contributions(value: Assessment) -> List(Contribution) {
  value.contributions
}

pub fn assessment_minimum_basis_points(value: Assessment) -> Int {
  value.minimum_basis_points
}

pub fn assessment_minimum_source_groups(value: Assessment) -> Int {
  value.minimum_source_groups
}

pub fn contribution_track(value: Contribution) -> Track {
  value.track
}

pub fn contribution_channel_id(value: Contribution) -> String {
  value.channel_id
}

pub fn contribution_source_group(value: Contribution) -> String {
  value.source_group
}

pub fn contribution_covered_requirements(value: Contribution) -> List(String) {
  value.covered_requirements
}

pub fn picture_track(value: Picture) -> Track {
  value.track
}

pub fn picture_readiness(value: Picture) -> PictureReadiness {
  value.readiness
}

pub fn picture_assessments(value: Picture) -> List(Assessment) {
  value.assessments
}

fn validate_covered(
  values: List(String),
  channel_id: String,
  seen: List(String),
) -> Result(Nil, CoverageError) {
  case values {
    [] -> Ok(Nil)
    [first, ..rest] ->
      case valid_id(first), list.contains(seen, first) {
        False, _ -> Error(InvalidRequirementId)
        _, True -> Error(DuplicateCoveredRequirement(channel_id, first))
        True, False -> validate_covered(rest, channel_id, [first, ..seen])
      }
  }
}

fn validate_requirements(
  values: List(Requirement),
  seen: List(String),
) -> Result(Nil, CoverageError) {
  case values {
    [] -> Ok(Nil)
    [first, ..rest] ->
      case list.contains(seen, first.id) {
        True -> Error(DuplicateRequirement(first.id))
        False -> validate_requirements(rest, [first.id, ..seen])
      }
  }
}

fn validate_contributions(
  values: List(Contribution),
  track: Track,
  requirements: List(String),
  seen_channels: List(String),
) -> Result(Nil, CoverageError) {
  case values {
    [] -> Ok(Nil)
    [first, ..rest] ->
      case
        first.track == track,
        list.contains(seen_channels, first.channel_id),
        first.covered_requirements
        |> list.find(fn(id) { !list.contains(requirements, id) })
      {
        False, _, _ -> Error(ContributionTrackMismatch(first.channel_id))
        _, True, _ -> Error(DuplicateChannel(first.channel_id))
        True, False, Ok(unknown) ->
          Error(UnknownRequirement(first.channel_id, unknown))
        True, False, Error(_) ->
          validate_contributions(rest, track, requirements, [
            first.channel_id,
            ..seen_channels
          ])
      }
  }
}

fn validate_assessments(
  values: List(Assessment),
  track: Track,
  seen_families: List(String),
) -> Result(Nil, CoverageError) {
  case values {
    [] -> Ok(Nil)
    [first, ..rest] ->
      case first.track == track, list.contains(seen_families, first.family) {
        False, _ -> Error(AssessmentTrackMismatch(first.family))
        _, True -> Error(DuplicateFamily(first.family))
        True, False ->
          validate_assessments(rest, track, [first.family, ..seen_families])
      }
  }
}

fn contribution_covers(
  values: List(Contribution),
  requirement_id: String,
) -> Bool {
  values
  |> list.any(fn(value) {
    list.contains(value.covered_requirements, requirement_id)
  })
}

fn distinct_source_groups(
  values: List(Contribution),
  reversed: List(String),
) -> List(String) {
  case values {
    [] -> list.reverse(reversed)
    [first, ..rest] ->
      case list.contains(reversed, first.source_group) {
        True -> distinct_source_groups(rest, reversed)
        False -> distinct_source_groups(rest, [first.source_group, ..reversed])
      }
  }
}

fn basis_points(covered: Int, total: Int) -> Int {
  let assert Ok(value) = int.divide(covered * 10_000, by: total)
  value
}

fn valid_id(value: String) -> Bool {
  valid_term(value, 100)
  && value
  |> string.to_graphemes
  |> list.all(fn(character) {
    string.contains("abcdefghijklmnopqrstuvwxyz0123456789_-", character)
  })
}

fn valid_term(value: String, maximum_length: Int) -> Bool {
  value != ""
  && string.trim(value) == value
  && string.length(value) <= maximum_length
  && !string.contains(value, "\r")
  && !string.contains(value, "\n")
}
