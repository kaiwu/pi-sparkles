import gleam/dynamic/decode
import gleam/option.{type Option, None}

pub type InspectInput {
  InspectInput(
    packet_payload: String,
    packet_hash: String,
    maximum_events: Int,
    as_of_unix_ms: Int,
    freshness_cutoff_unix_ms: Int,
    include_events: Bool,
    include_source_lexemes: Bool,
    offset: Int,
    limit: Int,
  )
}

pub type EventFilter {
  EventFilter(
    include_odd_lots: Bool,
    include_off_exchange: Bool,
    included_condition_codes: List(String),
  )
}

pub type CalculationInput {
  CalculationInput(
    packet_payload: String,
    packet_hash: String,
    maximum_events: Int,
    calculation: String,
    window_start_unix_ms: Int,
    window_end_unix_ms: Int,
    scale: Int,
    rounding: String,
    event_filter: EventFilter,
  )
}

pub type TransitionInput {
  TransitionInput(
    current_state_payload: Option(String),
    current_state_hash: Option(String),
    workflow_id: String,
    branch_id: String,
    transition_id: String,
    idempotency_key: String,
    event_kind: String,
    origin: String,
    occurred_at_unix_ms: Int,
    payload: String,
    payload_hash: String,
    evidence_references: List(String),
    execution_receipt_references: List(String),
  )
}

pub fn inspect() -> decode.Decoder(InspectInput) {
  use payload <- decode.field("packetPayload", decode.string)
  use hash <- decode.field("packetHash", decode.string)
  use maximum_events <- decode.field("maximumEvents", decode.int)
  use as_of <- decode.field("asOfUnixMilliseconds", decode.int)
  use cutoff <- decode.field("freshnessCutoffUnixMilliseconds", decode.int)
  use include_events <- decode.field("includeEvents", decode.bool)
  use include_lexemes <- decode.field("includeSourceLexemes", decode.bool)
  use offset <- decode.field("offset", decode.int)
  use limit <- decode.field("limit", decode.int)
  decode.success(InspectInput(
    payload,
    hash,
    maximum_events,
    as_of,
    cutoff,
    include_events,
    include_lexemes,
    offset,
    limit,
  ))
}

pub fn calculation() -> decode.Decoder(CalculationInput) {
  use payload <- decode.field("packetPayload", decode.string)
  use hash <- decode.field("packetHash", decode.string)
  use maximum_events <- decode.field("maximumEvents", decode.int)
  use calculation <- decode.field("calculation", decode.string)
  use start <- decode.field("windowStartUnixMilliseconds", decode.int)
  use end <- decode.field("windowEndUnixMilliseconds", decode.int)
  use scale <- decode.field("scale", decode.int)
  use rounding <- decode.field("rounding", decode.string)
  use event_filter <- decode.field("eventFilter", event_filter_decoder())
  decode.success(CalculationInput(
    payload,
    hash,
    maximum_events,
    calculation,
    start,
    end,
    scale,
    rounding,
    event_filter,
  ))
}

pub fn transition() -> decode.Decoder(TransitionInput) {
  use state_payload <- optional_string("currentStatePayload")
  use state_hash <- optional_string("currentStateHash")
  use workflow_id <- decode.field("workflowId", decode.string)
  use branch_id <- decode.field("branchId", decode.string)
  use transition_id <- decode.field("transitionId", decode.string)
  use idempotency_key <- decode.field("idempotencyKey", decode.string)
  use event_kind <- decode.field("eventKind", decode.string)
  use origin <- decode.field("origin", decode.string)
  use occurred_at <- decode.field("occurredAtUnixMilliseconds", decode.int)
  use payload <- decode.field("payload", decode.string)
  use payload_hash <- decode.field("payloadHash", decode.string)
  use evidence <- decode.field(
    "evidenceReferences",
    decode.list(of: decode.string),
  )
  use execution <- decode.field(
    "executionReceiptReferences",
    decode.list(of: decode.string),
  )
  decode.success(TransitionInput(
    state_payload,
    state_hash,
    workflow_id,
    branch_id,
    transition_id,
    idempotency_key,
    event_kind,
    origin,
    occurred_at,
    payload,
    payload_hash,
    evidence,
    execution,
  ))
}

fn event_filter_decoder() -> decode.Decoder(EventFilter) {
  use include_odd_lots <- decode.field("includeOddLots", decode.bool)
  use include_off_exchange <- decode.field("includeOffExchange", decode.bool)
  use conditions <- decode.field(
    "includedConditionCodes",
    decode.list(of: decode.string),
  )
  decode.success(EventFilter(include_odd_lots, include_off_exchange, conditions))
}

fn optional_string(
  name: String,
  next: fn(Option(String)) -> decode.Decoder(value),
) -> decode.Decoder(value) {
  decode.optional_field(name, None, decode.optional(decode.string), next)
}
