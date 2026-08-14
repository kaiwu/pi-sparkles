import finance_core/identifier.{type Mic}
import finance_provenance/identity.{type Sha256}
import finance_track.{type Track}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

/// An exact provider field. No decimal conversion or alternative selection is
/// performed by this package.
pub type Lexeme {
  KnownLexeme(value: String)
  UnavailableLexeme(reason: String)
  ConflictingLexemes(values: List(String))
}

pub type EventKind {
  OriginalTrade
  Correction(reference_event_id: String, reference_trade_id: Option(String))
  Cancel(reference_event_id: String, reference_trade_id: Option(String))
}

/// The provider's sequence observation for one event.
///
/// Sequence values are canonical unsigned-decimal strings so identifiers above
/// JavaScript's safe-integer limit remain exact and comparable.
pub type SequenceMarker {
  Sequenced(scope: String, value: String)
  SequenceReset(scope: String, value: String, declared_previous: Option(String))
  SequenceUnavailable(reason: String)
  SequenceConflicting(scope: String, values: List(String))
}

pub opaque type Clocks {
  Clocks(
    exchange_unix_milliseconds: Option(Int),
    provider_unix_milliseconds: Option(Int),
    retrieved_unix_milliseconds: Int,
  )
}

pub opaque type Event {
  Event(
    event_id: String,
    trade_id: String,
    kind: EventKind,
    price: Lexeme,
    size: Lexeme,
    condition_codes: List(String),
    venue_lexeme: String,
    clocks: Clocks,
    sequence: SequenceMarker,
    raw_receipt_hash: Sha256,
  )
}

/// Coverage is always a supplied/provider declaration. This core does not turn
/// it into an exchange attestation or authenticate its origin.
pub type Coverage {
  ProviderDeclaredComplete(reference: Sha256)
  BoundedPartial(reason: String)
  UnknownCoverage(reason: String)
}

pub type ConditionCoverage {
  DocumentedConditions(codes: List(String), reference: Sha256)
  PartiallyDocumentedConditions(
    codes: List(String),
    reference: Sha256,
    reason: String,
  )
  UndocumentedConditions(reason: String)
}

pub opaque type Packet {
  Packet(
    track: Track,
    listing_id: String,
    mic: Mic,
    session_id: String,
    provider: String,
    feed: String,
    entitlement: String,
    licence: String,
    coverage: Coverage,
    condition_coverage: ConditionCoverage,
    maximum_events: Int,
    events: List(Event),
  )
}

pub type OrderingBasis {
  ExchangeClock
  ProviderClock
  RetrievalClock
}

pub type EventTimeOrder {
  Nondecreasing(basis: OrderingBasis)
  Nonmonotonic(basis: OrderingBasis, event_ids: List(String))
}

pub type SequenceIssue {
  SequenceGap(
    scope: String,
    previous: String,
    expected: String,
    received: String,
    event_id: String,
  )
  DuplicateSequence(scope: String, value: String, event_id: String)
  OutOfOrderSequence(
    scope: String,
    previous: String,
    received: String,
    event_id: String,
  )
  SequenceScopeChanged(
    previous_scope: String,
    received_scope: String,
    event_id: String,
  )
  ResetBoundary(
    scope: String,
    value: String,
    declared_previous: Option(String),
    event_id: String,
  )
  ResetPreviousMismatch(
    scope: String,
    observed_previous: String,
    declared_previous: String,
    event_id: String,
  )
  UnavailableSequence(reason: String, event_id: String)
  ConflictingSequence(scope: String, values: List(String), event_id: String)
}

pub type LineageIssue {
  MissingReference(event_id: String, reference_event_id: String)
  AmbiguousReference(event_id: String, reference_event_id: String)
  SelfReference(event_id: String)
  TradeReferenceMismatch(
    event_id: String,
    expected_trade_id: String,
    received_trade_id: String,
  )
  CancelReference(event_id: String, reference_event_id: String)
  ReferenceOccursLater(event_id: String, reference_event_id: String)
}

pub type ClockDelta {
  ClockDelta(
    event_id: String,
    exchange_to_provider_milliseconds: Option(Int),
    provider_to_retrieval_milliseconds: Option(Int),
    exchange_to_retrieval_milliseconds: Option(Int),
  )
}

pub type ConditionCount {
  ConditionCount(code: String, occurrences: Int)
}

pub opaque type Review {
  Review(
    event_time_order: EventTimeOrder,
    duplicate_exact_event_count: Int,
    duplicate_event_ids: List(String),
    conflicting_event_ids: List(String),
    duplicate_original_trade_ids: List(String),
    sequence_issues: List(SequenceIssue),
    lineage_issues: List(LineageIssue),
    clock_deltas: List(ClockDelta),
    condition_counts: List(ConditionCount),
    undocumented_condition_codes: List(String),
    condition_documentation_complete: Bool,
    provider_declared_complete: Bool,
  )
}

pub type TapeError {
  InvalidField(field: String, reason: String)
  WrongTrackMic(track: String, mic: String)
  BudgetExceeded(field: String, maximum: Int)
}

const maximum_packet_events = 10_000

const maximum_payload_bytes = 2_000_000

const maximum_safe_unix_milliseconds = 8_640_000_000_000_000

pub fn clocks(
  exchange_unix_milliseconds exchange: Option(Int),
  provider_unix_milliseconds provider: Option(Int),
  retrieved_unix_milliseconds retrieved: Int,
) -> Result(Clocks, TapeError) {
  use _ <- result.try(valid_optional_instant(
    "exchangeUnixMilliseconds",
    exchange,
  ))
  use _ <- result.try(valid_optional_instant(
    "providerUnixMilliseconds",
    provider,
  ))
  use _ <- result.try(valid_instant("retrievedUnixMilliseconds", retrieved))
  Ok(Clocks(exchange, provider, retrieved))
}

pub fn event(
  event_id event_id: String,
  trade_id trade_id: String,
  kind kind: EventKind,
  price price: Lexeme,
  size size: Lexeme,
  condition_codes condition_codes: List(String),
  venue_lexeme venue_lexeme: String,
  clocks clocks: Clocks,
  sequence sequence: SequenceMarker,
  raw_receipt_hash raw_receipt_hash: Sha256,
) -> Result(Event, TapeError) {
  use _ <- result.try(valid_text("eventId", event_id, 1, 500))
  use _ <- result.try(valid_text("tradeId", trade_id, 1, 500))
  use _ <- result.try(valid_event_kind(kind))
  use _ <- result.try(valid_lexeme("price", price))
  use _ <- result.try(valid_lexeme("size", size))
  use _ <- result.try(within_budget("conditionCodes", condition_codes, 100))
  use _ <- result.try(
    list.try_each(condition_codes, fn(value) {
      valid_text("conditionCodes[]", value, 1, 200)
    }),
  )
  use _ <- result.try(valid_text("venueLexeme", venue_lexeme, 1, 200))
  use _ <- result.try(valid_sequence(sequence))
  Ok(Event(
    event_id,
    trade_id,
    kind,
    price,
    size,
    condition_codes,
    venue_lexeme,
    clocks,
    sequence,
    raw_receipt_hash,
  ))
}

pub fn packet(
  track track: Track,
  listing_id listing_id: String,
  mic mic: Mic,
  session_id session_id: String,
  provider provider: String,
  feed feed: String,
  entitlement entitlement: String,
  licence licence: String,
  coverage coverage: Coverage,
  condition_coverage condition_coverage: ConditionCoverage,
  maximum_events maximum_events: Int,
  events events: List(Event),
) -> Result(Packet, TapeError) {
  use _ <- result.try(valid_text("listingId", listing_id, 1, 500))
  use _ <- result.try(valid_track_mic(track, mic))
  use _ <- result.try(valid_text("sessionId", session_id, 1, 500))
  use _ <- result.try(valid_text("provider", provider, 1, 200))
  use _ <- result.try(valid_text("feed", feed, 1, 200))
  use _ <- result.try(valid_text("entitlement", entitlement, 1, 500))
  use _ <- result.try(valid_text("licence", licence, 1, 1000))
  use _ <- result.try(valid_coverage(coverage))
  use _ <- result.try(valid_condition_coverage(condition_coverage))
  use _ <- result.try(case maximum_events {
    value if value < 1 ->
      Error(InvalidField("maximumEvents", "must be positive"))
    value if value > maximum_packet_events ->
      Error(BudgetExceeded("maximumEvents", maximum_packet_events))
    _ -> Ok(Nil)
  })
  use _ <- result.try(case events {
    [] -> Error(InvalidField("events", "at least one event is required"))
    _ -> within_budget("events", events, maximum_events)
  })
  use _ <- result.try(case payload_size(events) {
    size if size <= maximum_payload_bytes -> Ok(Nil)
    _ -> Error(BudgetExceeded("payloadBytes", maximum_payload_bytes))
  })
  Ok(Packet(
    track,
    listing_id,
    mic,
    session_id,
    provider,
    feed,
    entitlement,
    licence,
    coverage,
    condition_coverage,
    maximum_events,
    events,
  ))
}

pub fn review(packet: Packet) -> Review {
  let event_ids = duplicate_event_ids(packet.events)
  let conditions = all_condition_codes(packet.events)
  let undocumented =
    undocumented_conditions(conditions, packet.condition_coverage)
  Review(
    time_order(packet.events),
    duplicate_exact_count(packet.events),
    event_ids,
    conflicting_event_ids(packet.events, event_ids),
    duplicate_original_trade_ids(packet.events),
    sequence_issues(packet.events),
    lineage_issues(packet.events),
    list.map(packet.events, clock_delta),
    condition_counts(conditions),
    undocumented,
    condition_documentation_declared_complete(packet.condition_coverage)
      && list.is_empty(undocumented),
    case packet.coverage {
      ProviderDeclaredComplete(_) -> True
      _ -> False
    },
  )
}

pub fn packet_track(value: Packet) -> Track {
  value.track
}

pub fn packet_listing_id(value: Packet) -> String {
  value.listing_id
}

pub fn packet_mic(value: Packet) -> Mic {
  value.mic
}

pub fn packet_session_id(value: Packet) -> String {
  value.session_id
}

pub fn packet_provider(value: Packet) -> String {
  value.provider
}

pub fn packet_feed(value: Packet) -> String {
  value.feed
}

pub fn packet_entitlement(value: Packet) -> String {
  value.entitlement
}

pub fn packet_licence(value: Packet) -> String {
  value.licence
}

pub fn packet_coverage(value: Packet) -> Coverage {
  value.coverage
}

pub fn packet_maximum_events(value: Packet) -> Int {
  value.maximum_events
}

pub fn packet_events(value: Packet) -> List(Event) {
  value.events
}

pub fn event_id(value: Event) -> String {
  value.event_id
}

pub fn trade_id(value: Event) -> String {
  value.trade_id
}

pub fn event_kind(value: Event) -> EventKind {
  value.kind
}

pub fn event_price(value: Event) -> Lexeme {
  value.price
}

pub fn event_size(value: Event) -> Lexeme {
  value.size
}

pub fn event_condition_codes(value: Event) -> List(String) {
  value.condition_codes
}

pub fn event_venue_lexeme(value: Event) -> String {
  value.venue_lexeme
}

pub fn event_clocks(value: Event) -> Clocks {
  value.clocks
}

pub fn event_sequence(value: Event) -> SequenceMarker {
  value.sequence
}

pub fn event_raw_receipt_hash(value: Event) -> Sha256 {
  value.raw_receipt_hash
}

pub fn exchange_unix_milliseconds(value: Clocks) -> Option(Int) {
  value.exchange_unix_milliseconds
}

pub fn provider_unix_milliseconds(value: Clocks) -> Option(Int) {
  value.provider_unix_milliseconds
}

pub fn retrieved_unix_milliseconds(value: Clocks) -> Int {
  value.retrieved_unix_milliseconds
}

pub fn event_time_order(value: Review) -> EventTimeOrder {
  value.event_time_order
}

pub fn duplicate_exact_event_count(value: Review) -> Int {
  value.duplicate_exact_event_count
}

pub fn duplicate_event_id_values(value: Review) -> List(String) {
  value.duplicate_event_ids
}

pub fn conflicting_event_id_values(value: Review) -> List(String) {
  value.conflicting_event_ids
}

pub fn duplicate_original_trade_id_values(value: Review) -> List(String) {
  value.duplicate_original_trade_ids
}

pub fn review_sequence_issues(value: Review) -> List(SequenceIssue) {
  value.sequence_issues
}

pub fn review_lineage_issues(value: Review) -> List(LineageIssue) {
  value.lineage_issues
}

pub fn review_clock_deltas(value: Review) -> List(ClockDelta) {
  value.clock_deltas
}

pub fn review_condition_counts(value: Review) -> List(ConditionCount) {
  value.condition_counts
}

pub fn review_undocumented_condition_codes(value: Review) -> List(String) {
  value.undocumented_condition_codes
}

pub fn review_condition_documentation_complete(value: Review) -> Bool {
  value.condition_documentation_complete
}

pub fn review_provider_declared_complete(value: Review) -> Bool {
  value.provider_declared_complete
}

pub fn error_message(value: TapeError) -> String {
  case value {
    InvalidField(field, reason) ->
      "Invalid transaction-tape field " <> field <> ": " <> reason
    WrongTrackMic(track, mic) ->
      "Transaction-tape MIC " <> mic <> " is outside track " <> track
    BudgetExceeded(field, maximum) ->
      "Transaction-tape "
      <> field
      <> " exceeds maximum "
      <> int.to_string(maximum)
  }
}

fn valid_event_kind(value: EventKind) -> Result(Nil, TapeError) {
  case value {
    OriginalTrade -> Ok(Nil)
    Correction(reference_event_id, reference_trade_id)
    | Cancel(reference_event_id, reference_trade_id) -> {
      use _ <- result.try(valid_text(
        "kind.referenceEventId",
        reference_event_id,
        1,
        500,
      ))
      case reference_trade_id {
        None -> Ok(Nil)
        Some(value) -> valid_text("kind.referenceTradeId", value, 1, 500)
      }
    }
  }
}

fn valid_lexeme(field: String, value: Lexeme) -> Result(Nil, TapeError) {
  case value {
    KnownLexeme(value) -> valid_decimal_lexeme(field, value)
    UnavailableLexeme(reason) ->
      valid_text(field <> ".unavailableReason", reason, 1, 500)
    ConflictingLexemes(values) -> {
      use _ <- result.try(case list.unique(values) {
        [_, _, ..] -> Ok(Nil)
        _ ->
          Error(InvalidField(
            field,
            "conflicting lexemes require at least two distinct values",
          ))
      })
      list.try_each(values, fn(value) { valid_decimal_lexeme(field, value) })
    }
  }
}

fn valid_decimal_lexeme(
  field: String,
  value: String,
) -> Result(Nil, TapeError) {
  let graphemes = string.to_graphemes(value)
  let #(digits, points) =
    list.fold(graphemes, #(0, 0), fn(counts, character) {
      let #(digits, points) = counts
      case character {
        "." -> #(digits, points + 1)
        value ->
          case string.contains("0123456789", value) {
            True -> #(digits + 1, points)
            False -> #(digits, points + 2)
          }
      }
    })
  case
    value != ""
    && string.trim(value) == value
    && digits > 0
    && points <= 1
    && !string.starts_with(value, ".")
    && !string.ends_with(value, ".")
  {
    True -> Ok(Nil)
    False -> Error(InvalidField(field, "must be an exact unsigned decimal"))
  }
}

fn valid_sequence(value: SequenceMarker) -> Result(Nil, TapeError) {
  case value {
    Sequenced(scope, sequence) -> {
      use _ <- result.try(valid_text("sequence.scope", scope, 1, 200))
      valid_unsigned_integer("sequence.value", sequence)
    }
    SequenceReset(scope, sequence, previous) -> {
      use _ <- result.try(valid_text("sequence.scope", scope, 1, 200))
      use _ <- result.try(valid_unsigned_integer("sequence.value", sequence))
      case previous {
        None -> Ok(Nil)
        Some(value) ->
          valid_unsigned_integer("sequence.declaredPrevious", value)
      }
    }
    SequenceUnavailable(reason) ->
      valid_text("sequence.unavailableReason", reason, 1, 500)
    SequenceConflicting(scope, values) -> {
      use _ <- result.try(valid_text("sequence.scope", scope, 1, 200))
      use _ <- result.try(case list.unique(values) {
        [_, _, ..] -> Ok(Nil)
        _ ->
          Error(InvalidField(
            "sequence.values",
            "requires at least two distinct values",
          ))
      })
      list.try_each(values, fn(value) {
        valid_unsigned_integer("sequence.values[]", value)
      })
    }
  }
}

fn valid_unsigned_integer(
  field: String,
  value: String,
) -> Result(Nil, TapeError) {
  case
    value != ""
    && string.length(value) <= 500
    && { value == "0" || !string.starts_with(value, "0") }
    && {
      value
      |> string.to_graphemes
      |> list.all(fn(character) { string.contains("0123456789", character) })
    }
  {
    True -> Ok(Nil)
    False ->
      Error(InvalidField(field, "must be a canonical unsigned integer lexeme"))
  }
}

fn valid_coverage(value: Coverage) -> Result(Nil, TapeError) {
  case value {
    ProviderDeclaredComplete(_) -> Ok(Nil)
    BoundedPartial(reason) -> valid_text("coverage.reason", reason, 1, 500)
    UnknownCoverage(reason) -> valid_text("coverage.reason", reason, 1, 500)
  }
}

fn valid_condition_coverage(
  value: ConditionCoverage,
) -> Result(Nil, TapeError) {
  case value {
    DocumentedConditions(codes, _) -> valid_documented_codes(codes)
    PartiallyDocumentedConditions(codes, _, reason) -> {
      use _ <- result.try(valid_documented_codes(codes))
      valid_text("conditionCoverage.reason", reason, 1, 500)
    }
    UndocumentedConditions(reason) ->
      valid_text("conditionCoverage.reason", reason, 1, 500)
  }
}

fn valid_documented_codes(codes: List(String)) -> Result(Nil, TapeError) {
  use _ <- result.try(
    case list.length(codes) == list.length(list.unique(codes)) {
      True -> Ok(Nil)
      False ->
        Error(InvalidField(
          "conditionCoverage.codes",
          "documented codes must be unique",
        ))
    },
  )
  list.try_each(codes, fn(value) {
    valid_text("conditionCoverage.codes[]", value, 1, 200)
  })
}

fn valid_track_mic(track: Track, mic: Mic) -> Result(Nil, TapeError) {
  let name = finance_track.name(track)
  let value = identifier.mic_value(mic)
  let cn = ["XSHG", "XSHE", "XBSE"]
  case name {
    "cn" ->
      case list.contains(cn, value) {
        True -> Ok(Nil)
        False -> Error(WrongTrackMic(name, value))
      }
    "hk" if value == "XHKG" -> Ok(Nil)
    "hk" -> Error(WrongTrackMic(name, value))
    "us" ->
      case list.contains(["XSHG", "XSHE", "XBSE", "XHKG"], value) {
        True -> Error(WrongTrackMic(name, value))
        False -> Ok(Nil)
      }
    _ -> Error(WrongTrackMic(name, value))
  }
}

fn valid_optional_instant(
  field: String,
  value: Option(Int),
) -> Result(Nil, TapeError) {
  case value {
    None -> Ok(Nil)
    Some(value) -> valid_instant(field, value)
  }
}

fn valid_instant(field: String, value: Int) -> Result(Nil, TapeError) {
  case
    value >= 0 - maximum_safe_unix_milliseconds
    && value <= maximum_safe_unix_milliseconds
  {
    True -> Ok(Nil)
    False -> Error(InvalidField(field, "must be within the exact clock range"))
  }
}

fn valid_text(
  field: String,
  value: String,
  minimum: Int,
  maximum: Int,
) -> Result(Nil, TapeError) {
  case
    string.length(value) >= minimum
    && string.length(value) <= maximum
    && string.trim(value) == value
    && !string.contains(value, "\n")
    && !string.contains(value, "\r")
    && !string.contains(value, "\t")
  {
    True -> Ok(Nil)
    False -> Error(InvalidField(field, "outside bounded plain-text policy"))
  }
}

fn within_budget(
  field: String,
  values: List(value),
  maximum: Int,
) -> Result(Nil, TapeError) {
  case list.length(values) <= maximum {
    True -> Ok(Nil)
    False -> Error(BudgetExceeded(field, maximum))
  }
}

fn payload_size(events: List(Event)) -> Int {
  list.fold(events, 0, fn(total, event) {
    total
    + string.byte_size(event.event_id)
    + string.byte_size(event.trade_id)
    + lexeme_size(event.price)
    + lexeme_size(event.size)
    + string.byte_size(event.venue_lexeme)
    + event_kind_size(event.kind)
    + sequence_size(event.sequence)
    + list.fold(event.condition_codes, 0, fn(value, code) {
      value + string.byte_size(code)
    })
  })
}

fn event_kind_size(value: EventKind) -> Int {
  case value {
    OriginalTrade -> 0
    Correction(event_id, trade_id) | Cancel(event_id, trade_id) ->
      string.byte_size(event_id)
      + case trade_id {
        None -> 0
        Some(value) -> string.byte_size(value)
      }
  }
}

fn sequence_size(value: SequenceMarker) -> Int {
  case value {
    Sequenced(scope, sequence) ->
      string.byte_size(scope) + string.byte_size(sequence)
    SequenceReset(scope, sequence, previous) ->
      string.byte_size(scope)
      + string.byte_size(sequence)
      + case previous {
        None -> 0
        Some(value) -> string.byte_size(value)
      }
    SequenceUnavailable(reason) -> string.byte_size(reason)
    SequenceConflicting(scope, values) ->
      string.byte_size(scope)
      + list.fold(values, 0, fn(total, value) {
        total + string.byte_size(value)
      })
  }
}

fn lexeme_size(value: Lexeme) -> Int {
  case value {
    KnownLexeme(value) | UnavailableLexeme(value) -> string.byte_size(value)
    ConflictingLexemes(values) ->
      list.fold(values, 0, fn(total, value) { total + string.byte_size(value) })
  }
}

fn time_order(events: List(Event)) -> EventTimeOrder {
  let basis = ordering_basis(events)
  case events {
    [] -> Nondecreasing(basis)
    [first, ..rest] -> {
      let regressions =
        time_regressions(event_time(first, basis), rest, basis, [])
      case regressions {
        [] -> Nondecreasing(basis)
        values -> Nonmonotonic(basis, list.reverse(values))
      }
    }
  }
}

fn ordering_basis(events: List(Event)) -> OrderingBasis {
  case
    list.all(events, fn(event) {
      event.clocks.exchange_unix_milliseconds != None
    })
  {
    True -> ExchangeClock
    False ->
      case
        list.all(events, fn(event) {
          event.clocks.provider_unix_milliseconds != None
        })
      {
        True -> ProviderClock
        False -> RetrievalClock
      }
  }
}

fn event_time(event: Event, basis: OrderingBasis) -> Int {
  case basis {
    ExchangeClock -> {
      let assert Some(value) = event.clocks.exchange_unix_milliseconds
      value
    }
    ProviderClock -> {
      let assert Some(value) = event.clocks.provider_unix_milliseconds
      value
    }
    RetrievalClock -> event.clocks.retrieved_unix_milliseconds
  }
}

fn time_regressions(
  previous: Int,
  events: List(Event),
  basis: OrderingBasis,
  found: List(String),
) -> List(String) {
  case events {
    [] -> found
    [event, ..rest] -> {
      let current = event_time(event, basis)
      let next_found = case current < previous {
        True -> [event.event_id, ..found]
        False -> found
      }
      time_regressions(current, rest, basis, next_found)
    }
  }
}

fn duplicate_exact_count(events: List(Event)) -> Int {
  list.index_fold(events, 0, fn(total, event, index) {
    case list.contains(list.take(events, index), event) {
      True -> total + 1
      False -> total
    }
  })
}

fn duplicate_event_ids(events: List(Event)) -> List(String) {
  events
  |> list.filter_map(fn(event) {
    case count_event_id(events, event.event_id) > 1 {
      True -> Ok(event.event_id)
      False -> Error(Nil)
    }
  })
  |> list.unique
}

fn count_event_id(events: List(Event), id: String) -> Int {
  events
  |> list.filter(fn(event) { event.event_id == id })
  |> list.length
}

fn conflicting_event_ids(
  events: List(Event),
  duplicates: List(String),
) -> List(String) {
  list.filter(duplicates, fn(id) {
    let matching = list.filter(events, fn(event) { event.event_id == id })
    list.length(list.unique(matching)) > 1
  })
}

fn duplicate_original_trade_ids(events: List(Event)) -> List(String) {
  let originals =
    list.filter(events, fn(event) {
      case event.kind {
        OriginalTrade -> True
        _ -> False
      }
    })
  originals
  |> list.filter_map(fn(event) {
    let count =
      originals
      |> list.filter(fn(other) { other.trade_id == event.trade_id })
      |> list.length
    case count > 1 {
      True -> Ok(event.trade_id)
      False -> Error(Nil)
    }
  })
  |> list.unique
}

fn sequence_issues(events: List(Event)) -> List(SequenceIssue) {
  sequence_issues_loop(events, None, []) |> list.reverse
}

fn sequence_issues_loop(
  events: List(Event),
  previous: Option(#(String, String)),
  found: List(SequenceIssue),
) -> List(SequenceIssue) {
  case events {
    [] -> found
    [event, ..rest] ->
      case event.sequence {
        SequenceUnavailable(reason) ->
          sequence_issues_loop(rest, previous, [
            UnavailableSequence(reason, event.event_id),
            ..found
          ])
        SequenceConflicting(scope, values) ->
          sequence_issues_loop(rest, previous, [
            ConflictingSequence(scope, values, event.event_id),
            ..found
          ])
        Sequenced(scope, value) -> {
          let issues = continuity_issues(previous, scope, value, event.event_id)
          sequence_issues_loop(
            rest,
            Some(#(scope, value)),
            list.append(list.reverse(issues), found),
          )
        }
        SequenceReset(scope, value, declared_previous) -> {
          let reset =
            ResetBoundary(scope, value, declared_previous, event.event_id)
          let issues =
            reset_issues(previous, scope, declared_previous, event.event_id)
          sequence_issues_loop(rest, Some(#(scope, value)), [
            reset,
            ..list.append(list.reverse(issues), found)
          ])
        }
      }
  }
}

fn continuity_issues(
  previous: Option(#(String, String)),
  scope: String,
  value: String,
  event_id: String,
) -> List(SequenceIssue) {
  case previous {
    None -> []
    Some(#(previous_scope, _previous_value)) if previous_scope != scope -> [
      SequenceScopeChanged(previous_scope, scope, event_id),
    ]
    Some(#(_, previous_value)) -> {
      let expected = increment_decimal(previous_value)
      case compare_decimal(value, previous_value), value == expected {
        Equal, _ -> [DuplicateSequence(scope, value, event_id)]
        Less, _ -> [OutOfOrderSequence(scope, previous_value, value, event_id)]
        Greater, True -> []
        Greater, False -> [
          SequenceGap(scope, previous_value, expected, value, event_id),
        ]
      }
    }
  }
}

fn reset_issues(
  previous: Option(#(String, String)),
  scope: String,
  declared_previous: Option(String),
  event_id: String,
) -> List(SequenceIssue) {
  case previous, declared_previous {
    Some(#(previous_scope, _)), _ if previous_scope != scope -> [
      SequenceScopeChanged(previous_scope, scope, event_id),
    ]
    Some(#(_, observed)), Some(declared) if observed != declared -> [
      ResetPreviousMismatch(scope, observed, declared, event_id),
    ]
    _, _ -> []
  }
}

type DecimalOrder {
  Less
  Equal
  Greater
}

fn compare_decimal(left: String, right: String) -> DecimalOrder {
  case string.length(left) < string.length(right) {
    True -> Less
    False ->
      case string.length(left) > string.length(right) {
        True -> Greater
        False ->
          compare_digits(string.to_graphemes(left), string.to_graphemes(right))
      }
  }
}

fn compare_digits(left: List(String), right: List(String)) -> DecimalOrder {
  case left, right {
    [], [] -> Equal
    [left, ..left_rest], [right, ..right_rest] ->
      case digit_value(left), digit_value(right) {
        left, right if left < right -> Less
        left, right if left > right -> Greater
        _, _ -> compare_digits(left_rest, right_rest)
      }
    [], [_first, ..] -> Less
    [_first, ..], [] -> Greater
  }
}

fn increment_decimal(value: String) -> String {
  value
  |> string.to_graphemes
  |> list.reverse
  |> increment_reversed(True, [])
  |> string.concat
}

fn increment_reversed(
  reversed: List(String),
  carry: Bool,
  built: List(String),
) -> List(String) {
  case reversed, carry {
    [], True -> ["1", ..built]
    [], False -> built
    [digit, ..rest], False -> increment_reversed(rest, False, [digit, ..built])
    ["9", ..rest], True -> increment_reversed(rest, True, ["0", ..built])
    [digit, ..rest], True ->
      increment_reversed(rest, False, [
        digit_from_value(digit_value(digit) + 1),
        ..built
      ])
  }
}

fn digit_value(value: String) -> Int {
  case value {
    "0" -> 0
    "1" -> 1
    "2" -> 2
    "3" -> 3
    "4" -> 4
    "5" -> 5
    "6" -> 6
    "7" -> 7
    "8" -> 8
    "9" -> 9
    _ -> 0
  }
}

fn digit_from_value(value: Int) -> String {
  case value {
    0 -> "0"
    1 -> "1"
    2 -> "2"
    3 -> "3"
    4 -> "4"
    5 -> "5"
    6 -> "6"
    7 -> "7"
    8 -> "8"
    9 -> "9"
    _ -> "0"
  }
}

fn lineage_issues(events: List(Event)) -> List(LineageIssue) {
  events
  |> list.flat_map(fn(event) { event_lineage_issues(event, events) })
}

fn event_lineage_issues(
  event: Event,
  events: List(Event),
) -> List(LineageIssue) {
  case event.kind {
    OriginalTrade -> []
    Correction(reference_event_id, reference_trade_id)
    | Cancel(reference_event_id, reference_trade_id) ->
      case reference_event_id == event.event_id {
        True -> [SelfReference(event.event_id)]
        False -> {
          let matches =
            list.filter(events, fn(other) {
              other.event_id == reference_event_id
            })
          case matches {
            [] -> [MissingReference(event.event_id, reference_event_id)]
            [target] -> target_lineage_issues(event, target, reference_trade_id)
            [_, _, ..] -> [
              AmbiguousReference(event.event_id, reference_event_id),
            ]
          }
        }
      }
  }
}

fn target_lineage_issues(
  event: Event,
  target: Event,
  reference_trade_id: Option(String),
) -> List(LineageIssue) {
  let trade_issues = case reference_trade_id {
    Some(value) if value != target.trade_id -> [
      TradeReferenceMismatch(event.event_id, target.trade_id, value),
    ]
    _ -> []
  }
  let cancel_issues = case target.kind {
    Cancel(_, _) -> [CancelReference(event.event_id, target.event_id)]
    _ -> []
  }
  let time_issues = case lineage_time(event) < lineage_time(target) {
    True -> [ReferenceOccursLater(event.event_id, target.event_id)]
    False -> []
  }
  list.flatten([trade_issues, cancel_issues, time_issues])
}

fn lineage_time(event: Event) -> Int {
  case
    event.clocks.exchange_unix_milliseconds,
    event.clocks.provider_unix_milliseconds
  {
    Some(value), _ -> value
    None, Some(value) -> value
    None, None -> event.clocks.retrieved_unix_milliseconds
  }
}

fn clock_delta(event: Event) -> ClockDelta {
  let clocks = event.clocks
  ClockDelta(
    event.event_id,
    subtract_options(
      clocks.provider_unix_milliseconds,
      clocks.exchange_unix_milliseconds,
    ),
    subtract_options(
      Some(clocks.retrieved_unix_milliseconds),
      clocks.provider_unix_milliseconds,
    ),
    subtract_options(
      Some(clocks.retrieved_unix_milliseconds),
      clocks.exchange_unix_milliseconds,
    ),
  )
}

fn subtract_options(left: Option(Int), right: Option(Int)) -> Option(Int) {
  case left, right {
    Some(left), Some(right) -> Some(left - right)
    _, _ -> None
  }
}

fn all_condition_codes(events: List(Event)) -> List(String) {
  list.flat_map(events, fn(event) { event.condition_codes })
}

fn condition_counts(codes: List(String)) -> List(ConditionCount) {
  codes
  |> list.unique
  |> list.map(fn(code) {
    ConditionCount(
      code,
      codes |> list.filter(fn(value) { value == code }) |> list.length,
    )
  })
}

fn undocumented_conditions(
  codes: List(String),
  coverage: ConditionCoverage,
) -> List(String) {
  let documented = case coverage {
    DocumentedConditions(values, _)
    | PartiallyDocumentedConditions(values, _, _) -> values
    UndocumentedConditions(_) -> []
  }
  codes
  |> list.filter(fn(code) { !list.contains(documented, code) })
  |> list.unique
}

fn condition_documentation_declared_complete(value: ConditionCoverage) -> Bool {
  case value {
    DocumentedConditions(_, _) -> True
    _ -> False
  }
}
