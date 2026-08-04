import finance_core/source.{type SourceRef}
import finance_core/time.{type Duration, type Instant}
import gleam/option.{type Option}

pub type Freshness {
  Fresh(maximum_age: Duration)
  Stale(age: Duration, maximum_age: Duration)
  UnknownFreshness
}

pub type Entitlement {
  RealTime
  Delayed(delay: Duration)
  EndOfDay
  UnknownEntitlement
}

pub type MissingReason {
  NotReported
  NotApplicable
  Unavailable
  Suppressed
  ParseFailure
}

pub type Quality {
  Reported
  Estimated
  Restated
  Revised
  Missing(reason: MissingReason)
}

pub type Observation(value) {
  Observation(
    value: value,
    as_of: Instant,
    retrieved_at: Instant,
    source: SourceRef,
    evidence_id: Option(String),
    freshness: Freshness,
    entitlement: Entitlement,
    quality: Quality,
    unit: Option(Unit),
    adjustment: Option(Adjustment),
    session: Option(Session),
  )
}

pub fn map(
  observation: Observation(value),
  with transform: fn(value) -> mapped,
) -> Observation(mapped) {
  Observation(
    value: transform(observation.value),
    as_of: observation.as_of,
    retrieved_at: observation.retrieved_at,
    source: observation.source,
    evidence_id: observation.evidence_id,
    freshness: observation.freshness,
    entitlement: observation.entitlement,
    quality: observation.quality,
    unit: observation.unit,
    adjustment: observation.adjustment,
    session: observation.session,
  )
}

import finance_core/adjustment.{type Adjustment}
import finance_core/market.{type Session, type Unit}
