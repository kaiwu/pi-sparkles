import finance_core/time.{type Instant}
import finance_journal/event
import finance_journal/information
import finance_provenance/identity.{type Sha256}
import finance_track.{type Track}
import gleam/option.{type Option, None, Some}
import gleam/result

pub type IdentityInput {
  IdentityInput(
    kind: String,
    track: Option(Track),
    listing_id: Option(String),
    mic: Option(String),
    symbol: Option(String),
  )
}

pub type AttributionInput {
  AttributionInput(
    kind: String,
    author_or_source_id: Option(String),
    receipt: Option(Sha256),
    result_receipt: Option(Sha256),
    context_receipt: Option(Sha256),
  )
}

pub type EntryData {
  EntryData(
    journal_id: String,
    event_id: String,
    kind: String,
    identity: IdentityInput,
    workflow_id: Option(String),
    position_id: Option(String),
    review_id: Option(String),
    attribution: AttributionInput,
    stage: Option(String),
    payload: String,
    occurrence_time: Option(Instant),
    recording_time: Instant,
    timezone: Option(String),
    privacy: event.Privacy,
    references: List(event.Reference),
    supersedes: Option(String),
    import_provenance: Option(String),
    idempotency_key: String,
  )
}

pub type DomainError {
  UnknownEventKind(String)
  InvalidIdentityShape(String)
  InvalidAttributionShape(String)
  InvalidEvent(event.EventError)
}

pub fn build_event(value: EntryData) -> Result(event.Event, DomainError) {
  let EntryData(
    journal_id,
    event_id,
    kind_name,
    identity_input,
    workflow_id,
    position_id,
    review_id,
    attribution_input,
    stage,
    payload,
    occurrence_time,
    recording_time,
    timezone,
    privacy,
    references,
    supersedes,
    import_provenance,
    idempotency_key,
  ) = value
  use kind <- result.try(
    event.kind_from_name(kind_name)
    |> result.map_error(fn(_) { UnknownEventKind(kind_name) }),
  )
  use identity <- result.try(identity_scope(identity_input))
  use attribution <- result.try(attribution(attribution_input))
  event.new(
    journal_id,
    event_id,
    kind,
    event.Scope(identity, workflow_id, position_id, review_id),
    attribution,
    known_or_not_asked(stage),
    payload,
    known_or_not_asked(occurrence_time),
    recording_time,
    known_or_not_asked(timezone),
    privacy,
    references,
    supersedes,
    case import_provenance {
      Some(value) -> information.Known(value)
      None -> information.NotApplicable("not_supplied")
    },
    idempotency_key,
  )
  |> result.map_error(InvalidEvent)
}

fn identity_scope(
  value: IdentityInput,
) -> Result(event.IdentityScope, DomainError) {
  let IdentityInput(kind, track, listing_id, mic, symbol) = value
  case kind, track, listing_id, mic, symbol {
    "journal_wide", None, None, None, None -> Ok(event.JournalWide)
    "track_wide", Some(track), None, None, None -> Ok(event.TrackWide(track))
    "exact_listing", Some(track), Some(listing_id), Some(mic), symbol ->
      Ok(event.ExactListing(track, listing_id, mic, known_or_not_asked(symbol)))
    "unresolved_listing", track, listing_id, mic, symbol ->
      Ok(event.UnresolvedListing(
        known_or_unknown(track, "track_not_supplied"),
        known_or_unknown(listing_id, "listing_id_not_supplied"),
        known_or_unknown(mic, "mic_not_supplied"),
        known_or_unknown(symbol, "symbol_not_supplied"),
      ))
    _, _, _, _, _ -> Error(InvalidIdentityShape(kind))
  }
}

fn attribution(
  value: AttributionInput,
) -> Result(event.Attribution, DomainError) {
  let AttributionInput(kind, author, receipt, result_receipt, context) = value
  case kind, author, receipt, result_receipt, context {
    "user_declared", Some(id), None, None, None -> Ok(event.UserDeclared(id))
    "llm_declared", Some(id), None, None, context ->
      Ok(event.LlmDeclared(id, context))
    "imported_declaration", Some(source), None, None, None ->
      Ok(event.ImportedDeclaration(source))
    "provider_observed", None, Some(receipt), None, None ->
      Ok(event.ProviderObserved(receipt))
    "broker_reported", None, Some(receipt), None, None ->
      Ok(event.BrokerReported(receipt))
    "system_observed", None, Some(receipt), None, None ->
      Ok(event.SystemObserved(receipt))
    "calculated", None, Some(request), Some(result), None ->
      Ok(event.Calculated(request, result))
    _, _, _, _, _ -> Error(InvalidAttributionShape(kind))
  }
}

fn known_or_not_asked(value: Option(a)) -> information.Information(a) {
  case value {
    Some(value) -> information.Known(value)
    None -> information.NotAsked
  }
}

fn known_or_unknown(
  value: Option(a),
  reason: String,
) -> information.Information(a) {
  case value {
    Some(value) -> information.Known(value)
    None -> information.Unknown(reason)
  }
}
