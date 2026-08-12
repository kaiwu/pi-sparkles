import finance_core/time.{type Instant}
import finance_journal/event.{type Event}
import finance_provenance/hash
import finance_provenance/identity.{type Sha256}
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub const maximum_revision = 100_000

pub opaque type State {
  State(
    revision: Int,
    events_reversed: List(Event),
    events_by_id: Dict(String, Event),
    events_by_idempotency: Dict(String, Event),
    journal: Option(String),
  )
}

pub type AppendOutcome {
  Stored(event: Event)
  AlreadyStored(event: Event)
}

pub type StateError {
  RevisionExhausted
  JournalMismatch(expected: String, received: String)
  DuplicateEventId(event_id: String)
  IdempotencyConflict(
    idempotency_key: String,
    original_event_id: String,
    original_semantic_hash: String,
    received_semantic_hash: String,
  )
  MissingSupersededEvent(event_id: String)
}

pub type ReplayError {
  EmptyLine(line: Int)
  DecodeFailure(line: Int, error: event.EventError)
  InvalidTransition(line: Int, error: StateError)
  DuplicatePersistedEvent(line: Int, event_id: String)
  TooManyEvents(received: Int, maximum: Int)
  TooManyCharacters(received: Int, maximum: Int)
}

pub type Query {
  Query(
    workflow_id: Option(String),
    kinds: List(event.EventKind),
    attribution_names: List(String),
    privacy_states: List(event.Privacy),
    include_superseded: Bool,
    maximum: Int,
  )
}

pub type QueryResult {
  QueryResult(events: List(Event), matched_count: Int, omitted_count: Int)
}

pub type ExportPolicy {
  ExportPolicy(
    include_private: Bool,
    include_review_visible: Bool,
    include_exportable: Bool,
    include_superseded: Bool,
  )
}

pub type ExportResult {
  ExportResult(
    jsonl: String,
    event_count: Int,
    omitted_count: Int,
    content_hash: Sha256,
  )
}

pub fn empty() -> State {
  State(0, [], dict.new(), dict.new(), None)
}

pub fn append(
  state state_value: State,
  event new_event: Event,
) -> Result(#(State, AppendOutcome), StateError) {
  use _ <- result.try(validate_journal(state_value.journal, new_event))
  case
    dict.get(
      state_value.events_by_idempotency,
      event.idempotency_key(new_event),
    )
  {
    Ok(existing) ->
      case
        event.semantic_content_hash(existing)
        == event.semantic_content_hash(new_event)
      {
        True -> Ok(#(state_value, AlreadyStored(existing)))
        False ->
          Error(IdempotencyConflict(
            event.idempotency_key(new_event),
            event.event_id(existing),
            existing
              |> event.semantic_content_hash
              |> identity.sha256_value,
            new_event
              |> event.semantic_content_hash
              |> identity.sha256_value,
          ))
      }
    Error(_) ->
      case dict.has_key(state_value.events_by_id, event.event_id(new_event)) {
        True -> Error(DuplicateEventId(event.event_id(new_event)))
        False -> {
          use _ <- result.try(validate_supersedes(
            state_value.events_by_id,
            new_event,
          ))
          case state_value.revision >= maximum_revision {
            True -> Error(RevisionExhausted)
            False -> {
              let next =
                State(
                  state_value.revision + 1,
                  [new_event, ..state_value.events_reversed],
                  dict.insert(
                    state_value.events_by_id,
                    event.event_id(new_event),
                    new_event,
                  ),
                  dict.insert(
                    state_value.events_by_idempotency,
                    event.idempotency_key(new_event),
                    new_event,
                  ),
                  Some(event.journal_id(new_event)),
                )
              Ok(#(next, Stored(new_event)))
            }
          }
        }
      }
  }
}

/// Apply a batch entirely in immutable memory. Callers persist `next` only
/// when this function succeeds, so a structural error cannot produce a
/// partially written batch.
pub fn append_many(
  state state_value: State,
  events new_events: List(Event),
) -> Result(#(State, List(AppendOutcome)), StateError) {
  append_many_loop(new_events, state_value, [])
}

fn append_many_loop(
  remaining: List(Event),
  current: State,
  reversed: List(AppendOutcome),
) -> Result(#(State, List(AppendOutcome)), StateError) {
  case remaining {
    [] -> Ok(#(current, list.reverse(reversed)))
    [next, ..rest] -> {
      use #(next_state, outcome) <- result.try(append(current, next))
      append_many_loop(rest, next_state, [outcome, ..reversed])
    }
  }
}

pub fn replay(events: List(Event)) -> Result(State, ReplayError) {
  replay_loop(events, empty(), 1)
}

fn replay_loop(
  events: List(Event),
  state: State,
  line: Int,
) -> Result(State, ReplayError) {
  case events {
    [] -> Ok(state)
    [next, ..rest] ->
      case append(state, next) {
        Error(error) -> Error(InvalidTransition(line, error))
        Ok(#(_, AlreadyStored(existing))) ->
          Error(DuplicatePersistedEvent(line, event.event_id(existing)))
        Ok(#(next_state, Stored(_))) -> replay_loop(rest, next_state, line + 1)
      }
  }
}

pub fn decode_jsonl(
  input: String,
  maximum_events maximum_event_count: Int,
  maximum_characters maximum_character_count: Int,
) -> Result(State, ReplayError) {
  let received_characters = string.length(input)
  case received_characters > maximum_character_count {
    True ->
      Error(TooManyCharacters(received_characters, maximum_character_count))
    False -> {
      let lines = jsonl_lines(input)
      let received_events = list.length(lines)
      case received_events > maximum_event_count {
        True -> Error(TooManyEvents(received_events, maximum_event_count))
        False -> {
          use events <- result.try(decode_lines(lines, 1, []))
          replay(events)
        }
      }
    }
  }
}

fn jsonl_lines(input: String) -> List(String) {
  case input {
    "" -> []
    _ -> {
      let lines = string.split(input, on: "\n")
      case list.last(lines) {
        Ok("") -> list.take(lines, list.length(lines) - 1)
        _ -> lines
      }
    }
  }
}

fn decode_lines(
  lines: List(String),
  line: Int,
  reversed: List(Event),
) -> Result(List(Event), ReplayError) {
  case lines {
    [] -> Ok(list.reverse(reversed))
    ["", ..] -> Error(EmptyLine(line))
    [value, ..rest] ->
      case event.decode(value) {
        Error(error) -> Error(DecodeFailure(line, error))
        Ok(decoded) -> decode_lines(rest, line + 1, [decoded, ..reversed])
      }
  }
}

pub fn query(state_value: State, request: Query) -> QueryResult {
  let Query(
    workflow,
    kinds,
    attributions,
    privacy_states,
    include_superseded,
    maximum,
  ) = request
  let source_events = case include_superseded {
    True -> events(state_value)
    False -> current_events(state_value)
  }
  let matched =
    source_events
    |> list.filter(fn(value) {
      matches_workflow(value, workflow)
      && matches_kind(value, kinds)
      && matches_attribution(value, attributions)
      && matches_privacy(value, privacy_states)
    })
  let safe_maximum = case maximum < 0 {
    True -> 0
    False -> maximum
  }
  QueryResult(
    list.take(matched, safe_maximum),
    list.length(matched),
    int_max(list.length(matched) - safe_maximum, 0),
  )
}

pub fn export_jsonl(
  state_value: State,
  policy: ExportPolicy,
  maximum_events maximum: Int,
) -> ExportResult {
  let ExportPolicy(
    include_private,
    include_review_visible,
    include_exportable,
    include_superseded,
  ) = policy
  let source_events = case include_superseded {
    True -> events(state_value)
    False -> current_events(state_value)
  }
  let visible =
    source_events
    |> list.filter(fn(value) {
      case event.privacy(value) {
        event.Private -> include_private
        event.ReviewVisible -> include_review_visible
        event.Exportable -> include_exportable
      }
    })
  let safe_maximum = case maximum < 0 {
    True -> 0
    False -> maximum
  }
  let selected = list.take(visible, safe_maximum)
  let jsonl = encode_jsonl(selected)
  let assert Ok(content_hash) = hash.text(jsonl)
  ExportResult(
    jsonl,
    list.length(selected),
    int_max(list.length(visible) - list.length(selected), 0),
    content_hash,
  )
}

pub fn encode_jsonl(values: List(Event)) -> String {
  case values {
    [] -> ""
    _ ->
      values
      |> list.map(event.encode)
      |> string.join(with: "\n")
      |> fn(value) { value <> "\n" }
  }
}

pub fn current_events(value: State) -> List(Event) {
  let superseded =
    value.events_reversed
    |> list.fold(dict.new(), fn(ids, possible_correction) {
      case event.supersedes(possible_correction) {
        Some(id) -> dict.insert(ids, id, Nil)
        None -> ids
      }
    })
  value
  |> events
  |> list.filter(fn(candidate) {
    !dict.has_key(superseded, event.event_id(candidate))
  })
}

pub fn events_as_of(value: State, cutoff: Instant) -> List(Event) {
  let included =
    value
    |> events
    |> list.filter(fn(candidate) {
      candidate
      |> event.recording_time
      |> time.unix_milliseconds
      <= time.unix_milliseconds(cutoff)
    })
  let superseded =
    included
    |> list.fold(dict.new(), fn(ids, possible_correction) {
      case event.supersedes(possible_correction) {
        Some(id) -> dict.insert(ids, id, Nil)
        None -> ids
      }
    })
  included
  |> list.filter(fn(candidate) {
    !dict.has_key(superseded, event.event_id(candidate))
  })
}

fn validate_journal(
  current: Option(String),
  new_event: Event,
) -> Result(Nil, StateError) {
  case current {
    None -> Ok(Nil)
    Some(id) ->
      case id == event.journal_id(new_event) {
        True -> Ok(Nil)
        False -> Error(JournalMismatch(id, event.journal_id(new_event)))
      }
  }
}

fn validate_supersedes(
  events_by_id: Dict(String, Event),
  new_event: Event,
) -> Result(Nil, StateError) {
  case event.supersedes(new_event) {
    None -> Ok(Nil)
    Some(id) ->
      case dict.has_key(events_by_id, id) {
        False -> Error(MissingSupersededEvent(id))
        True -> Ok(Nil)
      }
  }
}

fn matches_workflow(value: Event, selected: Option(String)) -> Bool {
  case selected {
    None -> True
    Some(id) -> event.workflow_id(event.scope(value)) == Some(id)
  }
}

fn matches_kind(value: Event, selected: List(event.EventKind)) -> Bool {
  selected == [] || list.contains(selected, event.kind(value))
}

fn matches_attribution(value: Event, selected: List(String)) -> Bool {
  selected == []
  || list.contains(
    selected,
    value |> event.attribution |> event.attribution_name,
  )
}

fn matches_privacy(value: Event, selected: List(event.Privacy)) -> Bool {
  selected == [] || list.contains(selected, event.privacy(value))
}

fn int_max(left: Int, right: Int) -> Int {
  case left > right {
    True -> left
    False -> right
  }
}

pub fn revision(value: State) -> Int {
  value.revision
}

pub fn events(value: State) -> List(Event) {
  list.reverse(value.events_reversed)
}

pub fn event_count(value: State) -> Int {
  value.revision
}

pub fn journal_id(value: State) -> Option(String) {
  value.journal
}

pub fn query_events(value: QueryResult) -> List(Event) {
  let QueryResult(events, _, _) = value
  events
}

pub fn matched_count(value: QueryResult) -> Int {
  let QueryResult(_, count, _) = value
  count
}

pub fn query_omitted_count(value: QueryResult) -> Int {
  let QueryResult(_, _, count) = value
  count
}

pub fn export_text(value: ExportResult) -> String {
  let ExportResult(text, _, _, _) = value
  text
}

pub fn exported_count(value: ExportResult) -> Int {
  let ExportResult(_, count, _, _) = value
  count
}

pub fn export_omitted_count(value: ExportResult) -> Int {
  let ExportResult(_, _, count, _) = value
  count
}

pub fn export_content_hash(value: ExportResult) -> Sha256 {
  let ExportResult(_, _, _, hash) = value
  hash
}
