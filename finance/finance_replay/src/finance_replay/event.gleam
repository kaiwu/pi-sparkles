import finance_core/time.{type Date, type Instant}
import finance_provenance/hash
import finance_provenance/identity.{type Sha256}
import finance_replay/fact.{type Fact}
import finance_replay/wire
import finance_track.{type Track}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import gleam/string

pub const maximum_payload_characters = 65_536

pub const maximum_references = 256

pub type Kind {
  UniverseMembershipAvailable
  MarketObservationAvailable
  MarketObservationCorrected
  FeatureResultProduced
  FeatureResultOmitted
  StrategyPredicateFact
  DesiredInstructionDeclared
  ExecutionBranchEmitted
  PositionLedgerChanged
  BenchmarkObservationAvailable
  RunCompleted
  RunTruncated
  RunCancelled
  RunResumed
}

pub type Reference {
  Reference(kind: String, hash: Sha256)
}

/// A replay event is information supplied to a deterministic fold. Its kind or
/// payload never implies that the research result is correct or sufficient.
pub opaque type Event {
  Event(
    run_id: String,
    event_id: String,
    kind: Kind,
    event_time: Fact(Instant),
    availability_time: Fact(Instant),
    replay_clock: Int,
    track: Fact(Track),
    session_date: Fact(Date),
    payload: String,
    references: List(Reference),
    recording_time: Instant,
    idempotency_key: String,
    semantic_content_hash: Sha256,
    canonical_content_hash: Sha256,
  )
}

pub type EventError {
  InvalidText(field: String)
  InvalidReplayClock
  PayloadTooLarge(received: Int, maximum: Int)
  TooManyReferences(received: Int, maximum: Int)
  DuplicateReference(kind: String, hash: String)
  HashMismatch
  InvalidJson
}

pub fn new(
  run_id run_id_value: String,
  event_id event_id_value: String,
  kind kind_value: Kind,
  event_time event_time_value: Fact(Instant),
  availability_time availability_time_value: Fact(Instant),
  replay_clock replay_clock_value: Int,
  track track_value: Fact(Track),
  session_date session_date_value: Fact(Date),
  payload payload_value: String,
  references reference_values: List(Reference),
  recording_time recording_time_value: Instant,
  idempotency_key idempotency_value: String,
) -> Result(Event, EventError) {
  use _ <- result.try(validate_text(run_id_value, "run_id"))
  use _ <- result.try(validate_text(event_id_value, "event_id"))
  use _ <- result.try(validate_text(idempotency_value, "idempotency_key"))
  use _ <- result.try(validate_replay_clock(replay_clock_value))
  use _ <- result.try(validate_payload(payload_value))
  use _ <- result.try(validate_references(reference_values, []))
  let semantic_payload =
    semantic_json(
      run_id_value,
      kind_value,
      event_time_value,
      availability_time_value,
      replay_clock_value,
      track_value,
      session_date_value,
      payload_value,
      reference_values,
    )
  let assert Ok(semantic_hash) = semantic_payload |> json.to_string |> hash.text
  let canonical_payload =
    canonical_json(
      run_id_value,
      event_id_value,
      kind_value,
      event_time_value,
      availability_time_value,
      replay_clock_value,
      track_value,
      session_date_value,
      payload_value,
      reference_values,
      recording_time_value,
      idempotency_value,
      semantic_hash,
    )
  let assert Ok(canonical_hash) =
    canonical_payload |> json.to_string |> hash.text
  Ok(Event(
    run_id_value,
    event_id_value,
    kind_value,
    event_time_value,
    availability_time_value,
    replay_clock_value,
    track_value,
    session_date_value,
    payload_value,
    reference_values,
    recording_time_value,
    idempotency_value,
    semantic_hash,
    canonical_hash,
  ))
}

pub fn encode(value: Event) -> String {
  value |> as_json |> json.to_string
}

pub fn as_json(value: Event) -> json.Json {
  json.object([
    #("payload", event_json(value)),
    #("canonical_content_hash", wire.sha_json(value.canonical_content_hash)),
  ])
}

pub fn decode(input: String) -> Result(Event, EventError) {
  case json.parse(input, envelope_decoder()) {
    Error(_) -> Error(InvalidJson)
    Ok(#(value, expected)) ->
      case value.canonical_content_hash == expected {
        True -> Ok(value)
        False -> Error(HashMismatch)
      }
  }
}

fn event_json(value: Event) -> json.Json {
  canonical_json(
    value.run_id,
    value.event_id,
    value.kind,
    value.event_time,
    value.availability_time,
    value.replay_clock,
    value.track,
    value.session_date,
    value.payload,
    value.references,
    value.recording_time,
    value.idempotency_key,
    value.semantic_content_hash,
  )
}

fn canonical_json(
  run_id: String,
  event_id: String,
  kind: Kind,
  event_time: Fact(Instant),
  availability_time: Fact(Instant),
  replay_clock: Int,
  track: Fact(Track),
  session_date: Fact(Date),
  payload: String,
  references: List(Reference),
  recording_time: Instant,
  idempotency_key: String,
  semantic_content_hash: Sha256,
) -> json.Json {
  json.object([
    #("schema", json.string("finance_replay_event")),
    #("schema_version", json.int(1)),
    #("decision_owner", json.string("llm")),
    #("run_id", json.string(run_id)),
    #("event_id", json.string(event_id)),
    #("kind", kind |> kind_name |> json.string),
    #("event_time", fact.to_json(event_time, wire.instant_json)),
    #("availability_time", fact.to_json(availability_time, wire.instant_json)),
    #("replay_clock", json.int(replay_clock)),
    #("track", fact.to_json(track, wire.track_json)),
    #("session_date", fact.to_json(session_date, wire.date_json)),
    #("payload", json.string(payload)),
    #("references", json.array(references, reference_json)),
    #("recording_time", wire.instant_json(recording_time)),
    #("idempotency_key", json.string(idempotency_key)),
    #("semantic_content_hash", wire.sha_json(semantic_content_hash)),
    #(
      "plugin_decision_fields",
      json.array([], fn(value) { json.string(value) }),
    ),
  ])
}

fn semantic_json(
  run_id: String,
  kind: Kind,
  event_time: Fact(Instant),
  availability_time: Fact(Instant),
  replay_clock: Int,
  track: Fact(Track),
  session_date: Fact(Date),
  payload: String,
  references: List(Reference),
) -> json.Json {
  json.object([
    #("run_id", json.string(run_id)),
    #("kind", kind |> kind_name |> json.string),
    #("event_time", fact.to_json(event_time, wire.instant_json)),
    #("availability_time", fact.to_json(availability_time, wire.instant_json)),
    #("replay_clock", json.int(replay_clock)),
    #("track", fact.to_json(track, wire.track_json)),
    #("session_date", fact.to_json(session_date, wire.date_json)),
    #("payload", json.string(payload)),
    #("references", json.array(references, reference_json)),
  ])
}

fn reference_json(value: Reference) -> json.Json {
  let Reference(kind, hash) = value
  json.object([
    #("kind", json.string(kind)),
    #("hash", wire.sha_json(hash)),
  ])
}

fn envelope_decoder() -> decode.Decoder(#(Event, Sha256)) {
  use value <- decode.field("payload", event_decoder())
  use expected <- decode.field("canonical_content_hash", wire.sha_decoder())
  decode.success(#(value, expected))
}

fn event_decoder() -> decode.Decoder(Event) {
  use run_id <- decode.field("run_id", decode.string)
  use event_id <- decode.field("event_id", decode.string)
  use kind <- decode.field("kind", kind_decoder())
  use event_time <- decode.field(
    "event_time",
    fact.decoder(wire.instant_decoder()),
  )
  use availability_time <- decode.field(
    "availability_time",
    fact.decoder(wire.instant_decoder()),
  )
  use replay_clock <- decode.field("replay_clock", decode.int)
  use track <- decode.field("track", fact.decoder(wire.track_decoder()))
  use session_date <- decode.field(
    "session_date",
    fact.decoder(wire.date_decoder()),
  )
  use payload <- decode.field("payload", decode.string)
  use references <- decode.field(
    "references",
    decode.list(of: reference_decoder()),
  )
  use recording_time <- decode.field("recording_time", wire.instant_decoder())
  use idempotency_key <- decode.field("idempotency_key", decode.string)
  use supplied_semantic <- decode.field(
    "semantic_content_hash",
    wire.sha_decoder(),
  )
  case
    new(
      run_id,
      event_id,
      kind,
      event_time,
      availability_time,
      replay_clock,
      track,
      session_date,
      payload,
      references,
      recording_time,
      idempotency_key,
    )
  {
    Ok(value) if value.semantic_content_hash == supplied_semantic ->
      decode.success(value)
    _ -> decode.failure(placeholder(), "valid replay event")
  }
}

fn reference_decoder() -> decode.Decoder(Reference) {
  use kind <- decode.field("kind", decode.string)
  use hash <- decode.field("hash", wire.sha_decoder())
  decode.success(Reference(kind, hash))
}

fn kind_decoder() -> decode.Decoder(Kind) {
  decode.string
  |> decode.then(fn(value) {
    case kind_from_name(value) {
      Ok(value) -> decode.success(value)
      Error(_) ->
        decode.failure(UniverseMembershipAvailable, "replay event kind")
    }
  })
}

pub fn kind_name(value: Kind) -> String {
  case value {
    UniverseMembershipAvailable -> "universe_membership_available"
    MarketObservationAvailable -> "market_observation_available"
    MarketObservationCorrected -> "market_observation_corrected"
    FeatureResultProduced -> "feature_result_produced"
    FeatureResultOmitted -> "feature_result_omitted"
    StrategyPredicateFact -> "strategy_predicate_fact"
    DesiredInstructionDeclared -> "desired_instruction_declared"
    ExecutionBranchEmitted -> "execution_branch_emitted"
    PositionLedgerChanged -> "position_ledger_changed"
    BenchmarkObservationAvailable -> "benchmark_observation_available"
    RunCompleted -> "run_completed"
    RunTruncated -> "run_truncated"
    RunCancelled -> "run_cancelled"
    RunResumed -> "run_resumed"
  }
}

fn kind_from_name(value: String) -> Result(Kind, Nil) {
  case value {
    "universe_membership_available" -> Ok(UniverseMembershipAvailable)
    "market_observation_available" -> Ok(MarketObservationAvailable)
    "market_observation_corrected" -> Ok(MarketObservationCorrected)
    "feature_result_produced" -> Ok(FeatureResultProduced)
    "feature_result_omitted" -> Ok(FeatureResultOmitted)
    "strategy_predicate_fact" -> Ok(StrategyPredicateFact)
    "desired_instruction_declared" -> Ok(DesiredInstructionDeclared)
    "execution_branch_emitted" -> Ok(ExecutionBranchEmitted)
    "position_ledger_changed" -> Ok(PositionLedgerChanged)
    "benchmark_observation_available" -> Ok(BenchmarkObservationAvailable)
    "run_completed" -> Ok(RunCompleted)
    "run_truncated" -> Ok(RunTruncated)
    "run_cancelled" -> Ok(RunCancelled)
    "run_resumed" -> Ok(RunResumed)
    _ -> Error(Nil)
  }
}

fn validate_text(value: String, field: String) -> Result(Nil, EventError) {
  case wire.valid_text(value, 512) {
    True -> Ok(Nil)
    False -> Error(InvalidText(field))
  }
}

fn validate_replay_clock(value: Int) -> Result(Nil, EventError) {
  case value < 0 {
    True -> Error(InvalidReplayClock)
    False -> Ok(Nil)
  }
}

fn validate_payload(value: String) -> Result(Nil, EventError) {
  let size = string.length(value)
  case size > maximum_payload_characters {
    True -> Error(PayloadTooLarge(size, maximum_payload_characters))
    False -> Ok(Nil)
  }
}

fn validate_references(
  values: List(Reference),
  seen: List(String),
) -> Result(Nil, EventError) {
  let count = list.length(values)
  case count > maximum_references {
    True -> Error(TooManyReferences(count, maximum_references))
    False -> validate_reference_values(values, seen)
  }
}

fn validate_reference_values(
  values: List(Reference),
  seen: List(String),
) -> Result(Nil, EventError) {
  case values {
    [] -> Ok(Nil)
    [Reference(kind, value_hash), ..rest] -> {
      use _ <- result.try(validate_text(kind, "reference_kind"))
      let key = kind <> ":" <> identity.sha256_value(value_hash)
      case list.contains(seen, key) {
        True ->
          Error(DuplicateReference(kind, identity.sha256_value(value_hash)))
        False -> validate_reference_values(rest, [key, ..seen])
      }
    }
  }
}

fn placeholder() -> Event {
  let assert Ok(value) =
    new(
      "placeholder-run",
      "placeholder-event",
      UniverseMembershipAvailable,
      fact.Unknown("placeholder"),
      fact.Unknown("placeholder"),
      0,
      fact.Unknown("placeholder"),
      fact.Unknown("placeholder"),
      "",
      [],
      wire.placeholder_instant(),
      "placeholder-key",
    )
  value
}

pub fn run_id(value: Event) -> String {
  value.run_id
}

pub fn event_id(value: Event) -> String {
  value.event_id
}

pub fn kind(value: Event) -> Kind {
  value.kind
}

pub fn event_time(value: Event) -> Fact(Instant) {
  value.event_time
}

pub fn availability_time(value: Event) -> Fact(Instant) {
  value.availability_time
}

pub fn replay_clock(value: Event) -> Int {
  value.replay_clock
}

pub fn idempotency_key(value: Event) -> String {
  value.idempotency_key
}

pub fn semantic_content_hash(value: Event) -> Sha256 {
  value.semantic_content_hash
}

pub fn canonical_content_hash(value: Event) -> Sha256 {
  value.canonical_content_hash
}
