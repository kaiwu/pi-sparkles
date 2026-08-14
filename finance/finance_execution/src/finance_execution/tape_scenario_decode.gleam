import gleam/dynamic/decode as decoder
import gleam/option.{type Option, None}

pub type EventInput {
  EventInput(
    event_id: String,
    trade_id: String,
    price_lexeme: String,
    size_lexeme: String,
    venue_lexeme: String,
    condition_codes: List(String),
    exchange_unix_milliseconds: Option(Int),
    provider_unix_milliseconds: Option(Int),
    retrieved_unix_milliseconds: Int,
    sequence_scope: String,
    sequence_lexeme: String,
    raw_receipt_hash: String,
  )
}

pub type Input {
  Input(
    operation_id: String,
    provider: String,
    track: String,
    listing_id: String,
    mic: String,
    session_id: String,
    currency: String,
    timezone: String,
    entitlement: String,
    licence: String,
    provider_receipt_hash: String,
    coverage: String,
    coverage_reason: Option(String),
    condition_codes: List(String),
    condition_reference_hash: String,
    instruction_id: String,
    instruction_receipt_hash: String,
    account_reference: String,
    side: String,
    quantity_lexeme: String,
    limit_price_lexeme: String,
    activation_unix_milliseconds: Option(Int),
    expiry_unix_milliseconds: Option(Int),
    rule_references: List(String),
    capability_references: List(String),
    eligible_venue_lexemes: List(String),
    eligible_condition_codes: List(String),
    allow_unconditioned_events: Bool,
    maximum_events: Int,
    events: List(EventInput),
  )
}

pub fn input() -> decoder.Decoder(Input) {
  use operation_id <- decoder.field("operationId", decoder.string)
  use provider <- decoder.field("provider", decoder.string)
  use track <- decoder.field("track", decoder.string)
  use listing_id <- decoder.field("listingId", decoder.string)
  use mic <- decoder.field("mic", decoder.string)
  use session_id <- decoder.field("sessionId", decoder.string)
  use currency <- decoder.field("currency", decoder.string)
  use timezone <- decoder.field("timezone", decoder.string)
  use entitlement <- decoder.field("entitlement", decoder.string)
  use licence <- decoder.field("licence", decoder.string)
  use provider_receipt_hash <- decoder.field(
    "providerReceiptHash",
    decoder.string,
  )
  use coverage <- decoder.field("coverage", decoder.string)
  use coverage_reason <- optional_string("coverageReason")
  use condition_codes <- decoder.field(
    "documentedConditionCodes",
    decoder.list(of: decoder.string),
  )
  use condition_reference_hash <- decoder.field(
    "conditionReferenceHash",
    decoder.string,
  )
  use instruction_id <- decoder.field("instructionId", decoder.string)
  use instruction_receipt_hash <- decoder.field(
    "instructionReceiptHash",
    decoder.string,
  )
  use account_reference <- decoder.field("accountReference", decoder.string)
  use side <- decoder.field("side", decoder.string)
  use quantity_lexeme <- decoder.field("quantity", decoder.string)
  use limit_price_lexeme <- decoder.field("limitPrice", decoder.string)
  use activation <- optional_int("activationUnixMilliseconds")
  use expiry <- optional_int("expiryUnixMilliseconds")
  use rule_references <- decoder.field(
    "ruleReferences",
    decoder.list(of: decoder.string),
  )
  use capability_references <- decoder.field(
    "capabilityReferences",
    decoder.list(of: decoder.string),
  )
  use eligible_venues <- decoder.field(
    "eligibleVenueLexemes",
    decoder.list(of: decoder.string),
  )
  use eligible_conditions <- decoder.field(
    "eligibleConditionCodes",
    decoder.list(of: decoder.string),
  )
  use allow_unconditioned <- decoder.field(
    "allowUnconditionedEvents",
    decoder.bool,
  )
  use maximum_events <- decoder.field("maximumEvents", decoder.int)
  use events <- decoder.field("events", decoder.list(of: event_input()))
  decoder.success(Input(
    operation_id,
    provider,
    track,
    listing_id,
    mic,
    session_id,
    currency,
    timezone,
    entitlement,
    licence,
    provider_receipt_hash,
    coverage,
    coverage_reason,
    condition_codes,
    condition_reference_hash,
    instruction_id,
    instruction_receipt_hash,
    account_reference,
    side,
    quantity_lexeme,
    limit_price_lexeme,
    activation,
    expiry,
    rule_references,
    capability_references,
    eligible_venues,
    eligible_conditions,
    allow_unconditioned,
    maximum_events,
    events,
  ))
}

fn event_input() -> decoder.Decoder(EventInput) {
  use event_id <- decoder.field("eventId", decoder.string)
  use trade_id <- decoder.field("tradeId", decoder.string)
  use price <- decoder.field("price", decoder.string)
  use size <- decoder.field("size", decoder.string)
  use venue <- decoder.field("venueLexeme", decoder.string)
  use conditions <- decoder.field(
    "conditionCodes",
    decoder.list(of: decoder.string),
  )
  use exchange <- optional_int("exchangeUnixMilliseconds")
  use provider <- optional_int("providerUnixMilliseconds")
  use retrieved <- decoder.field("retrievedUnixMilliseconds", decoder.int)
  use sequence_scope <- decoder.field("sequenceScope", decoder.string)
  use sequence <- decoder.field("sequence", decoder.string)
  use receipt <- decoder.field("rawReceiptHash", decoder.string)
  decoder.success(EventInput(
    event_id,
    trade_id,
    price,
    size,
    venue,
    conditions,
    exchange,
    provider,
    retrieved,
    sequence_scope,
    sequence,
    receipt,
  ))
}

fn optional_int(
  name: String,
  next: fn(Option(Int)) -> decoder.Decoder(value),
) -> decoder.Decoder(value) {
  decoder.optional_field(name, None, decoder.optional(decoder.int), next)
}

fn optional_string(
  name: String,
  next: fn(Option(String)) -> decoder.Decoder(value),
) -> decoder.Decoder(value) {
  decoder.optional_field(name, None, decoder.optional(decoder.string), next)
}
