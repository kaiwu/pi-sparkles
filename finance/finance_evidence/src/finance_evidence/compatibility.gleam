import finance_core/market.{type Unit}
import finance_core/observation.{
  type MissingReason, type Observation, type Quality,
}
import finance_core/time
import finance_provenance/evidence.{
  type Availability, type Evidence, type Redistribution,
}
import finance_provenance/identity
import finance_track.{type Track}
import finance_track/context.{type Leg}
import gleam/list
import gleam/option.{type Option, None, Some}

/// Whether a calculation is confined to one market track or deliberately
/// composes independently labelled legs.
pub type TrackPolicy {
  SameTrackOnly
  ExplicitCrossTrack
}

/// The temporal coherence required between observations.
pub type AsOfPolicy {
  IndependentAsOf
  ExactSameAsOf
}

/// The source quality states accepted by a calculation.
pub type QualityPolicy {
  ReportedOnly
  ReportedOrRestated
  AnyKnownQuality
}

/// The intended handling of provider material.
///
/// `InternalAnalysis` makes no redistribution claim. `RedistributableOutput`
/// fails closed unless every evidence licence explicitly permits it.
pub type IntendedUse {
  InternalAnalysis
  RedistributableOutput
}

pub type Policy {
  Policy(
    track: TrackPolicy,
    as_of: AsOfPolicy,
    quality: QualityPolicy,
    intended_use: IntendedUse,
    require_known_unit: Bool,
  )
}

/// One canonical observation, its market-track leg, and the evidence record
/// whose source and optional evidence identity must agree with the observation.
pub type Input(value) {
  Input(leg: Leg(Observation(value)), evidence: Evidence)
}

/// Evidence inputs that passed the declared compatibility policy.
///
/// The complete inputs remain available, including every track context and
/// evidence licence. Validation never flattens a cross-track composition.
pub opaque type Validated(value) {
  Validated(policy: Policy, inputs: List(Input(value)))
}

pub type CompatibilityError {
  EmptyInputs
  ObservationRetrievedBeforeAsOf(index: Int)
  EvidenceRetrievedBeforeAsOf(index: Int)
  SourceMismatch(index: Int)
  EvidenceIdMismatch(index: Int, expected: String, received: String)
  EvidenceUnavailable(index: Int, availability: Availability)
  MissingUnit(index: Int)
  UnitMismatch(index: Int, expected: Unit, received: Unit)
  MissingQuality(index: Int, reason: MissingReason)
  QualityRejected(index: Int, quality: Quality)
  AsOfMismatch(index: Int, expected_unix_ms: Int, received_unix_ms: Int)
  TrackMismatch(index: Int, expected: Track, received: Track)
  CrossTrackRequiresMultipleTracks
  RedistributionRejected(index: Int, redistribution: Redistribution)
}

pub fn validate(
  inputs: List(Input(value)),
  under policy: Policy,
) -> Result(Validated(value), List(CompatibilityError)) {
  case inputs {
    [] -> Error([EmptyInputs])
    [first, ..] -> {
      let errors =
        inputs
        |> validate_inputs(policy, first, 0, [])
        |> append_cross_track_error(policy.track, inputs)
      case errors {
        [] -> Ok(Validated(policy, inputs))
        errors -> Error(errors)
      }
    }
  }
}

pub fn policy(value: Validated(a)) -> Policy {
  value.policy
}

pub fn inputs(value: Validated(a)) -> List(Input(a)) {
  value.inputs
}

fn validate_inputs(
  inputs: List(Input(value)),
  policy: Policy,
  first: Input(value),
  index: Int,
  errors: List(CompatibilityError),
) -> List(CompatibilityError) {
  case inputs {
    [] -> errors
    [input, ..rest] ->
      validate_inputs(
        rest,
        policy,
        first,
        index + 1,
        list.append(errors, input_errors(input, first, policy, index)),
      )
  }
}

fn input_errors(
  input: Input(value),
  first: Input(value),
  policy: Policy,
  index: Int,
) -> List(CompatibilityError) {
  let Input(leg, evidence) = input
  let Input(first_leg, _) = first
  let observed = leg.value
  let first_observed = first_leg.value
  []
  |> append_if(
    time.unix_milliseconds(observed.retrieved_at)
      < time.unix_milliseconds(observed.as_of),
    ObservationRetrievedBeforeAsOf(index),
  )
  |> append_if(
    time.unix_milliseconds(evidence.retrieved_at)
      < time.unix_milliseconds(evidence.as_of),
    EvidenceRetrievedBeforeAsOf(index),
  )
  |> append_if(observed.source != evidence.source, SourceMismatch(index))
  |> list.append(evidence_id_errors(observed, evidence, index))
  |> append_if(
    evidence.availability != evidence.Available,
    EvidenceUnavailable(index, evidence.availability),
  )
  |> list.append(unit_errors(
    observed.unit,
    first_observed.unit,
    policy.require_known_unit,
    index,
  ))
  |> list.append(quality_errors(observed.quality, policy.quality, index))
  |> list.append(as_of_errors(observed, first_observed, policy.as_of, index))
  |> list.append(track_errors(leg, first_leg, policy.track, index))
  |> list.append(redistribution_errors(
    evidence.licence.redistribution,
    policy.intended_use,
    index,
  ))
}

fn evidence_id_errors(
  observed: Observation(value),
  evidence: Evidence,
  index: Int,
) -> List(CompatibilityError) {
  case observed.evidence_id {
    None -> []
    Some(received) -> {
      let expected = identity.evidence_id_value(evidence.id)
      case received == expected {
        True -> []
        False -> [EvidenceIdMismatch(index, expected, received)]
      }
    }
  }
}

fn unit_errors(
  received: Option(Unit),
  expected: Option(Unit),
  require_known: Bool,
  index: Int,
) -> List(CompatibilityError) {
  case received, expected, require_known {
    None, _, True -> [MissingUnit(index)]
    Some(received), Some(expected), _ if received != expected -> [
      UnitMismatch(index, expected, received),
    ]
    _, _, _ -> []
  }
}

fn quality_errors(
  received: Quality,
  policy: QualityPolicy,
  index: Int,
) -> List(CompatibilityError) {
  case received, policy {
    observation.Missing(reason), _ -> [MissingQuality(index, reason)]
    observation.Reported, _ -> []
    observation.Restated, ReportedOrRestated -> []
    observation.Restated, AnyKnownQuality -> []
    observation.Estimated, AnyKnownQuality -> []
    observation.Revised, AnyKnownQuality -> []
    quality, _ -> [QualityRejected(index, quality)]
  }
}

fn as_of_errors(
  observed: Observation(value),
  first: Observation(value),
  policy: AsOfPolicy,
  index: Int,
) -> List(CompatibilityError) {
  let expected = time.unix_milliseconds(first.as_of)
  let received = time.unix_milliseconds(observed.as_of)
  case policy == ExactSameAsOf && received != expected {
    True -> [AsOfMismatch(index, expected, received)]
    False -> []
  }
}

fn track_errors(
  leg: Leg(a),
  first: Leg(a),
  policy: TrackPolicy,
  index: Int,
) -> List(CompatibilityError) {
  let expected = context.track(first.context)
  let received = context.track(leg.context)
  case policy == SameTrackOnly && received != expected {
    True -> [TrackMismatch(index, expected, received)]
    False -> []
  }
}

fn redistribution_errors(
  redistribution: Redistribution,
  intended_use: IntendedUse,
  index: Int,
) -> List(CompatibilityError) {
  case intended_use, redistribution {
    InternalAnalysis, _ -> []
    RedistributableOutput, evidence.PublicDomain
    | RedistributableOutput, evidence.AttributionRequired
    -> []
    RedistributableOutput, value -> [RedistributionRejected(index, value)]
  }
}

fn append_cross_track_error(
  errors: List(CompatibilityError),
  policy: TrackPolicy,
  inputs: List(Input(value)),
) -> List(CompatibilityError) {
  case policy {
    SameTrackOnly -> errors
    ExplicitCrossTrack -> {
      let tracks = distinct_tracks(inputs, [])
      case list.length(tracks) >= 2 {
        True -> errors
        False -> list.append(errors, [CrossTrackRequiresMultipleTracks])
      }
    }
  }
}

fn distinct_tracks(
  inputs: List(Input(value)),
  found: List(Track),
) -> List(Track) {
  case inputs {
    [] -> found
    [Input(leg, _), ..rest] -> {
      let track = context.track(leg.context)
      case list.contains(found, track) {
        True -> distinct_tracks(rest, found)
        False -> distinct_tracks(rest, list.append(found, [track]))
      }
    }
  }
}

fn append_if(
  errors: List(CompatibilityError),
  condition: Bool,
  error: CompatibilityError,
) -> List(CompatibilityError) {
  case condition {
    True -> list.append(errors, [error])
    False -> errors
  }
}
