import finance_core/decimal
import finance_core/time.{type Date, type Instant}
import finance_listing/listing.{type Key}
import finance_provenance/identity.{type EvidenceId, type Sha256}
import finance_strategy/evidence
import finance_strategy/plan.{
  type DeclarationOrigin, type ExactPrice, type PlanDeclaration,
}
import finance_strategy/receipt.{type StrategyEvidenceReceipt}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{Eq, Gt, Lt}
import gleam/result
import gleam/string

pub type ExitCategory {
  DesiredStop
  Target
  HoldingWindow
  Invalidation
  GapThroughDesiredStop
  Manual
}

pub type ObservationSource {
  ProviderReported
  UserReported
  ImportedRecord
}

/// Facts and declarations that may be appended to workflow history.
///
/// Variant names describe what was recorded; they do not assert that an order
/// was authorized, executable, or filled by this package.
pub type WorkflowEventKind {
  PlanAttached(plan: PlanDeclaration)
  EntryWindowExpired(session: Date)
  EntryPriceObserved(
    session: Date,
    price: ExactPrice,
    source: ObservationSource,
  )
  MonitorPriceObserved(
    session: Date,
    price: ExactPrice,
    source: ObservationSource,
  )
  ExitPriceObserved(
    session: Date,
    price: ExactPrice,
    category: ExitCategory,
    source: ObservationSource,
  )
  DailyExitOrderingUnknown(session: Date, low: ExactPrice, high: ExactPrice)
  ReviewAttached(origin: DeclarationOrigin, note: String)
}

pub opaque type WorkflowEvent {
  WorkflowEvent(
    listing: Key,
    definition_hash: Sha256,
    observed_at: Instant,
    kind: WorkflowEventKind,
    evidence_roots: List(EvidenceId),
  )
}

pub type Phase {
  EvidencePrepared
  EntryWindowOpen
  EntryWindowExpiredPhase
  PositionObserved
  ExitObserved
  Reviewed
}

pub opaque type WorkflowHistory {
  WorkflowHistory(
    strategy_evidence: StrategyEvidenceReceipt,
    phase: Phase,
    plan: Option(PlanDeclaration),
    events: List(WorkflowEvent),
    last_observed_at: Instant,
  )
}

pub type EventError {
  InvalidReview
  EvidenceRequired
  DuplicateEvidenceRoot
}

pub type TransitionError {
  ListingMismatch
  DefinitionMismatch
  BackwardTimestamp
  IllegalEvent(phase: Phase)
  PlanCreatedAfterAttachment
  PlanListingMismatch
  PlanDefinitionMismatch
  EntryOutsideDeclaredWindow
  ExpiryBeforeWindowEnd
  InvalidUnknownOrdering
}

pub fn event(
  listing listing_value: Key,
  definition_hash definition_hash_value: Sha256,
  observed_at observed_at_value: Instant,
  kind kind_value: WorkflowEventKind,
  evidence_roots evidence_root_values: List(EvidenceId),
) -> Result(WorkflowEvent, EventError) {
  use _ <- result.try(validate_kind(kind_value, evidence_root_values))
  use _ <- result.try(validate_roots(evidence_root_values, []))
  Ok(WorkflowEvent(
    listing_value,
    definition_hash_value,
    observed_at_value,
    kind_value,
    evidence_root_values,
  ))
}

pub fn start(value: StrategyEvidenceReceipt) -> WorkflowHistory {
  WorkflowHistory(
    value,
    EvidencePrepared,
    None,
    [],
    value
      |> receipt.context
      |> evidence.evaluated_at,
  )
}

pub fn apply(
  history: WorkflowHistory,
  event: WorkflowEvent,
) -> Result(WorkflowHistory, TransitionError) {
  use _ <- result.try(validate_envelope(history, event))
  case history.phase, event.kind {
    EvidencePrepared, PlanAttached(plan) -> attach_plan(history, event, plan)
    EntryWindowOpen, EntryWindowExpired(session) ->
      expire_entry(history, event, session)
    EntryWindowOpen, EntryPriceObserved(session, _, _) ->
      observe_entry(history, event, session)
    PositionObserved, MonitorPriceObserved(_, _, _)
    | PositionObserved, DailyExitOrderingUnknown(_, _, _)
    -> observe_position_fact(history, event)
    PositionObserved, ExitPriceObserved(_, _, _, _) ->
      append_event(history, event, ExitObserved)
    EntryWindowExpiredPhase, ReviewAttached(_, _)
    | ExitObserved, ReviewAttached(_, _)
    -> append_event(history, event, Reviewed)
    phase, _ -> Error(IllegalEvent(phase))
  }
}

pub fn fold(
  history: WorkflowHistory,
  events: List(WorkflowEvent),
) -> Result(WorkflowHistory, TransitionError) {
  list.fold(events, Ok(history), fn(accumulator, event) {
    use history <- result.try(accumulator)
    apply(history, event)
  })
}

pub fn phase(value: WorkflowHistory) -> Phase {
  value.phase
}

pub fn strategy_evidence(value: WorkflowHistory) -> StrategyEvidenceReceipt {
  value.strategy_evidence
}

pub fn plan(value: WorkflowHistory) -> Option(PlanDeclaration) {
  value.plan
}

pub fn events(value: WorkflowHistory) -> List(WorkflowEvent) {
  value.events
}

pub fn last_observed_at(value: WorkflowHistory) -> Instant {
  value.last_observed_at
}

pub fn event_listing(value: WorkflowEvent) -> Key {
  value.listing
}

pub fn event_definition_hash(value: WorkflowEvent) -> Sha256 {
  value.definition_hash
}

pub fn event_observed_at(value: WorkflowEvent) -> Instant {
  value.observed_at
}

pub fn event_kind(value: WorkflowEvent) -> WorkflowEventKind {
  value.kind
}

pub fn event_evidence_roots(value: WorkflowEvent) -> List(EvidenceId) {
  value.evidence_roots
}

fn validate_kind(
  kind: WorkflowEventKind,
  roots: List(EvidenceId),
) -> Result(Nil, EventError) {
  case kind, roots {
    ReviewAttached(_, note), _ ->
      case valid_text(note) {
        True -> Ok(Nil)
        False -> Error(InvalidReview)
      }
    PlanAttached(_), _ -> Ok(Nil)
    _, [] -> Error(EvidenceRequired)
    _, _ -> Ok(Nil)
  }
}

fn validate_envelope(
  history: WorkflowHistory,
  event: WorkflowEvent,
) -> Result(Nil, TransitionError) {
  let expected_listing =
    history.strategy_evidence
    |> receipt.context
    |> evidence.context_listing
  case
    event.listing == expected_listing,
    event.definition_hash == receipt.definition_hash(history.strategy_evidence),
    time.unix_milliseconds(event.observed_at)
    >= time.unix_milliseconds(history.last_observed_at)
  {
    False, _, _ -> Error(ListingMismatch)
    _, False, _ -> Error(DefinitionMismatch)
    _, _, False -> Error(BackwardTimestamp)
    True, True, True -> Ok(Nil)
  }
}

fn attach_plan(
  history: WorkflowHistory,
  event: WorkflowEvent,
  plan: PlanDeclaration,
) -> Result(WorkflowHistory, TransitionError) {
  case
    plan.listing(plan)
    == {
      history.strategy_evidence
      |> receipt.context
      |> evidence.context_listing
    },
    plan.definition_hash(plan)
    == receipt.definition_hash(history.strategy_evidence),
    time.unix_milliseconds(plan.created_at(plan))
    <= time.unix_milliseconds(event.observed_at)
  {
    False, _, _ -> Error(PlanListingMismatch)
    _, False, _ -> Error(PlanDefinitionMismatch)
    _, _, False -> Error(PlanCreatedAfterAttachment)
    True, True, True ->
      Ok(
        WorkflowHistory(
          ..history,
          phase: EntryWindowOpen,
          plan: Some(plan),
          events: list.append(history.events, [event]),
          last_observed_at: event.observed_at,
        ),
      )
  }
}

fn expire_entry(
  history: WorkflowHistory,
  event: WorkflowEvent,
  session: Date,
) -> Result(WorkflowHistory, TransitionError) {
  let assert Some(plan) = history.plan
  case date_number(session) >= date_number(plan.final_entry_session(plan)) {
    True -> append_event(history, event, EntryWindowExpiredPhase)
    False -> Error(ExpiryBeforeWindowEnd)
  }
}

fn observe_entry(
  history: WorkflowHistory,
  event: WorkflowEvent,
  session: Date,
) -> Result(WorkflowHistory, TransitionError) {
  let assert Some(plan) = history.plan
  let session_number = date_number(session)
  case
    session_number >= date_number(plan.entry_session(plan))
    && session_number <= date_number(plan.final_entry_session(plan))
  {
    True -> append_event(history, event, PositionObserved)
    False -> Error(EntryOutsideDeclaredWindow)
  }
}

fn observe_position_fact(
  history: WorkflowHistory,
  event: WorkflowEvent,
) -> Result(WorkflowHistory, TransitionError) {
  case event.kind {
    DailyExitOrderingUnknown(_, low, high) -> {
      let assert Some(plan) = history.plan
      let stop = plan.desired_stop(plan) |> plan.price_value
      let target = plan.target(plan) |> plan.price_value
      case
        decimal.compare(plan.price_value(low), stop),
        decimal.compare(plan.price_value(high), target)
      {
        Lt, Gt | Lt, Eq | Eq, Gt | Eq, Eq ->
          append_event(history, event, PositionObserved)
        _, _ -> Error(InvalidUnknownOrdering)
      }
    }
    _ -> append_event(history, event, PositionObserved)
  }
}

fn append_event(
  history: WorkflowHistory,
  event: WorkflowEvent,
  phase: Phase,
) -> Result(WorkflowHistory, TransitionError) {
  Ok(
    WorkflowHistory(
      ..history,
      phase: phase,
      events: list.append(history.events, [event]),
      last_observed_at: event.observed_at,
    ),
  )
}

fn validate_roots(
  roots: List(EvidenceId),
  seen: List(EvidenceId),
) -> Result(Nil, EventError) {
  case roots {
    [] -> Ok(Nil)
    [root, ..rest] ->
      case list.contains(seen, root) {
        True -> Error(DuplicateEvidenceRoot)
        False -> validate_roots(rest, [root, ..seen])
      }
  }
}

fn valid_text(value: String) -> Bool {
  value != ""
  && string.length(value) <= 1000
  && string.trim(value) == value
  && !string.contains(value, "\r")
}

fn date_number(value: Date) -> Int {
  let #(year, month, day) = time.date_parts(value)
  year * 10_000 + month * 100 + day
}
