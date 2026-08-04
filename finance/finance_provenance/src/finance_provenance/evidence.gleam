import finance_core/source.{type SourceRef}
import finance_core/time.{type Instant}
import finance_provenance/identity.{
  type EvidenceId, type Sha256, type SourceFingerprint,
}
import gleam/option.{type Option}
import gleam/string

pub type Redistribution {
  PublicDomain
  AttributionRequired
  InternalUseOnly
  NoRedistribution
  UnknownRedistribution
}

pub type Licence {
  Licence(label: String, redistribution: Redistribution, notes: Option(String))
}

pub type Availability {
  Available
  Unavailable(reason: String)
  Expired
  Superseded(by: EvidenceId)
  VerificationFailed(reason: String)
}

pub type Evidence {
  Evidence(
    id: EvidenceId,
    source_fingerprint: SourceFingerprint,
    source: SourceRef,
    licence: Licence,
    as_of: Instant,
    retrieved_at: Instant,
    media_type: String,
    byte_length: Int,
    content_hash: Sha256,
    parents: List(EvidenceId),
    availability: Availability,
  )
}

pub type EvidenceError {
  InvalidMediaType
  NegativeByteLength
  RetrievedBeforeAsOf
}

pub fn new(
  id id: EvidenceId,
  source_fingerprint source_fingerprint: SourceFingerprint,
  source source: SourceRef,
  licence licence: Licence,
  as_of as_of: Instant,
  retrieved_at retrieved_at: Instant,
  media_type media_type: String,
  byte_length byte_length: Int,
  content_hash content_hash: Sha256,
  parents parents: List(EvidenceId),
) -> Result(Evidence, EvidenceError) {
  case string.trim(media_type) == media_type && media_type != "", byte_length {
    False, _ -> Error(InvalidMediaType)
    _, length if length < 0 -> Error(NegativeByteLength)
    True, _ ->
      case
        time.unix_milliseconds(retrieved_at) < time.unix_milliseconds(as_of)
      {
        True -> Error(RetrievedBeforeAsOf)
        False ->
          Ok(Evidence(
            id: id,
            source_fingerprint: source_fingerprint,
            source: source,
            licence: licence,
            as_of: as_of,
            retrieved_at: retrieved_at,
            media_type: media_type,
            byte_length: byte_length,
            content_hash: content_hash,
            parents: parents,
            availability: Available,
          ))
      }
  }
}

pub fn with_availability(
  evidence: Evidence,
  availability: Availability,
) -> Evidence {
  Evidence(..evidence, availability: availability)
}
