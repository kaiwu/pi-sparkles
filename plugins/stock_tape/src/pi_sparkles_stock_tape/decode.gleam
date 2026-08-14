import gleam/dynamic/decode as decoder
import gleam/option.{type Option, None}

pub type CoverageInput {
  CoverageInput(
    state: String,
    reference_hash: Option(String),
    reason: Option(String),
  )
}

pub type ConditionCoverageInput {
  ConditionCoverageInput(
    state: String,
    codes: List(String),
    reference_hash: Option(String),
    reason: Option(String),
  )
}

pub type EventKindInput {
  EventKindInput(
    state: String,
    reference_event_id: Option(String),
    reference_trade_id: Option(String),
  )
}

pub type LexemeInput {
  LexemeInput(
    state: String,
    value: Option(String),
    values: List(String),
    reason: Option(String),
  )
}

pub type ClocksInput {
  ClocksInput(
    exchange_unix_milliseconds: Option(Int),
    provider_unix_milliseconds: Option(Int),
    retrieved_unix_milliseconds: Int,
  )
}

pub type SequenceInput {
  SequenceInput(
    state: String,
    scope: Option(String),
    value: Option(String),
    values: List(String),
    declared_previous: Option(String),
    reason: Option(String),
  )
}

pub type EventInput {
  EventInput(
    event_id: String,
    trade_id: String,
    kind: EventKindInput,
    price: LexemeInput,
    size: LexemeInput,
    condition_codes: List(String),
    venue_lexeme: String,
    clocks: ClocksInput,
    sequence: SequenceInput,
    raw_receipt_hash: String,
  )
}

pub type PageInput {
  PageInput(offset: Int, limit: Int)
}

pub type Input {
  Input(
    track: String,
    listing_id: String,
    mic: String,
    session_id: String,
    provider: String,
    feed: String,
    entitlement: String,
    licence: String,
    provider_receipt_hash: String,
    coverage: CoverageInput,
    condition_coverage: ConditionCoverageInput,
    maximum_events: Int,
    events: List(EventInput),
    page: PageInput,
  )
}

pub fn input() -> decoder.Decoder(Input) {
  use track <- decoder.field("track", decoder.string)
  use listing_id <- decoder.field("listingId", decoder.string)
  use mic <- decoder.field("mic", decoder.string)
  use session_id <- decoder.field("sessionId", decoder.string)
  use provider <- decoder.field("provider", decoder.string)
  use feed <- decoder.field("feed", decoder.string)
  use entitlement <- decoder.field("entitlement", decoder.string)
  use licence <- decoder.field("licence", decoder.string)
  use provider_receipt_hash <- decoder.field(
    "providerReceiptHash",
    decoder.string,
  )
  use coverage <- decoder.field("coverage", coverage_decoder())
  use condition_coverage <- decoder.field(
    "conditionCoverage",
    condition_coverage_decoder(),
  )
  use maximum_events <- decoder.field("maximumEvents", decoder.int)
  use events <- decoder.field("events", decoder.list(of: event_decoder()))
  use page <- decoder.field("page", page_decoder())
  decoder.success(Input(
    track,
    listing_id,
    mic,
    session_id,
    provider,
    feed,
    entitlement,
    licence,
    provider_receipt_hash,
    coverage,
    condition_coverage,
    maximum_events,
    events,
    page,
  ))
}

fn coverage_decoder() -> decoder.Decoder(CoverageInput) {
  use state <- decoder.field("state", decoder.string)
  use reference_hash <- optional_string("referenceHash")
  use reason <- optional_string("reason")
  decoder.success(CoverageInput(state, reference_hash, reason))
}

fn condition_coverage_decoder() -> decoder.Decoder(ConditionCoverageInput) {
  use state <- decoder.field("state", decoder.string)
  use codes <- decoder.field("codes", decoder.list(of: decoder.string))
  use reference_hash <- optional_string("referenceHash")
  use reason <- optional_string("reason")
  decoder.success(ConditionCoverageInput(state, codes, reference_hash, reason))
}

fn event_kind_decoder() -> decoder.Decoder(EventKindInput) {
  use state <- decoder.field("state", decoder.string)
  use reference_event_id <- optional_string("referenceEventId")
  use reference_trade_id <- optional_string("referenceTradeId")
  decoder.success(EventKindInput(state, reference_event_id, reference_trade_id))
}

fn lexeme_decoder() -> decoder.Decoder(LexemeInput) {
  use state <- decoder.field("state", decoder.string)
  use value <- optional_string("value")
  use values <- decoder.field("values", decoder.list(of: decoder.string))
  use reason <- optional_string("reason")
  decoder.success(LexemeInput(state, value, values, reason))
}

fn clocks_decoder() -> decoder.Decoder(ClocksInput) {
  use exchange <- optional_int("exchangeUnixMilliseconds")
  use provider <- optional_int("providerUnixMilliseconds")
  use retrieved <- decoder.field("retrievedUnixMilliseconds", decoder.int)
  decoder.success(ClocksInput(exchange, provider, retrieved))
}

fn sequence_decoder() -> decoder.Decoder(SequenceInput) {
  use state <- decoder.field("state", decoder.string)
  use scope <- optional_string("scope")
  use value <- optional_string("value")
  use values <- decoder.field("values", decoder.list(of: decoder.string))
  use declared_previous <- optional_string("declaredPrevious")
  use reason <- optional_string("reason")
  decoder.success(SequenceInput(
    state,
    scope,
    value,
    values,
    declared_previous,
    reason,
  ))
}

fn event_decoder() -> decoder.Decoder(EventInput) {
  use event_id <- decoder.field("eventId", decoder.string)
  use trade_id <- decoder.field("tradeId", decoder.string)
  use kind <- decoder.field("kind", event_kind_decoder())
  use price <- decoder.field("price", lexeme_decoder())
  use size <- decoder.field("size", lexeme_decoder())
  use condition_codes <- decoder.field(
    "conditionCodes",
    decoder.list(of: decoder.string),
  )
  use venue_lexeme <- decoder.field("venueLexeme", decoder.string)
  use clocks <- decoder.field("clocks", clocks_decoder())
  use sequence <- decoder.field("sequence", sequence_decoder())
  use receipt <- decoder.field("rawReceiptHash", decoder.string)
  decoder.success(EventInput(
    event_id,
    trade_id,
    kind,
    price,
    size,
    condition_codes,
    venue_lexeme,
    clocks,
    sequence,
    receipt,
  ))
}

fn page_decoder() -> decoder.Decoder(PageInput) {
  use offset <- decoder.field("offset", decoder.int)
  use limit <- decoder.field("limit", decoder.int)
  decoder.success(PageInput(offset, limit))
}

fn optional_string(
  field: String,
  next: fn(Option(String)) -> decoder.Decoder(value),
) -> decoder.Decoder(value) {
  decoder.optional_field(field, None, decoder.optional(decoder.string), next)
}

fn optional_int(
  field: String,
  next: fn(Option(Int)) -> decoder.Decoder(value),
) -> decoder.Decoder(value) {
  decoder.optional_field(field, None, decoder.optional(decoder.int), next)
}
