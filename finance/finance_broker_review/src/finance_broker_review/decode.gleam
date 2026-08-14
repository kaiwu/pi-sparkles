import gleam/dynamic/decode as decoder
import gleam/option.{type Option, None}

pub type FactInput {
  FactInput(
    name: String,
    state: String,
    value: Option(String),
    unit: Option(String),
    source_reference: String,
  )
}

pub type EventInput {
  EventInput(
    event_reference: String,
    status_lexeme: String,
    occurred_at_unix_milliseconds: Int,
    source_reference: String,
  )
}

pub type ReviewInput {
  ReviewInput(
    operation_id: String,
    mode: String,
    environment: String,
    account_reference: String,
    track: String,
    listing_id: String,
    mic: String,
    source_content_hash: String,
    facts: List(FactInput),
    events: List(EventInput),
    missing_capabilities: List(String),
  )
}

pub type BoundReviewInput {
  BoundReviewInput(
    contract_version: String,
    provider: String,
    review: ReviewInput,
  )
}

/// A normalized evidence packet paired with the exact external provider
/// capability selected by the caller. Provider credentials and SDK handles are
/// intentionally outside this serializable boundary.
pub type ExplicitCapabilityInput {
  ExplicitCapabilityInput(provider: String, review: ReviewInput)
}

pub fn explicit_capability_input() -> decoder.Decoder(ExplicitCapabilityInput) {
  use provider <- decoder.field("provider", decoder.string)
  use operation_id <- decoder.field("operationId", decoder.string)
  use mode <- decoder.field("mode", decoder.string)
  use environment <- decoder.field("environment", decoder.string)
  use account_reference <- decoder.field("accountReference", decoder.string)
  use track <- decoder.field("track", decoder.string)
  use listing_id <- decoder.field("listingId", decoder.string)
  use mic <- decoder.field("mic", decoder.string)
  use source_content_hash <- decoder.field("sourceContentHash", decoder.string)
  use facts <- decoder.field("facts", decoder.list(of: fact_input()))
  use events <- decoder.field("events", decoder.list(of: event_input()))
  use missing_capabilities <- decoder.field(
    "missingCapabilities",
    decoder.list(of: decoder.string),
  )
  decoder.success(ExplicitCapabilityInput(
    provider,
    ReviewInput(
      operation_id,
      mode,
      environment,
      account_reference,
      track,
      listing_id,
      mic,
      source_content_hash,
      facts,
      events,
      missing_capabilities,
    ),
  ))
}

pub fn review_input() -> decoder.Decoder(ReviewInput) {
  use operation_id <- decoder.field("operationId", decoder.string)
  use mode <- decoder.field("mode", decoder.string)
  use environment <- decoder.field("environment", decoder.string)
  use account_reference <- decoder.field("accountReference", decoder.string)
  use track <- decoder.field("track", decoder.string)
  use listing_id <- decoder.field("listingId", decoder.string)
  use mic <- decoder.field("mic", decoder.string)
  use source_content_hash <- decoder.field("sourceContentHash", decoder.string)
  use facts <- decoder.field("facts", decoder.list(of: fact_input()))
  use events <- decoder.field("events", decoder.list(of: event_input()))
  use missing_capabilities <- decoder.field(
    "missingCapabilities",
    decoder.list(of: decoder.string),
  )
  decoder.success(ReviewInput(
    operation_id,
    mode,
    environment,
    account_reference,
    track,
    listing_id,
    mic,
    source_content_hash,
    facts,
    events,
    missing_capabilities,
  ))
}

/// Decode a local-import envelope whose source hash was supplied and verified
/// out of band. Omitting the hash from the JSON avoids an impossible self-hash.
pub fn bound_review_input(
  source_content_hash: String,
) -> decoder.Decoder(BoundReviewInput) {
  use contract_version <- decoder.field("contractVersion", decoder.string)
  use provider <- decoder.field("provider", decoder.string)
  use operation_id <- decoder.field("operationId", decoder.string)
  use mode <- decoder.field("mode", decoder.string)
  use environment <- decoder.field("environment", decoder.string)
  use account_reference <- decoder.field("accountReference", decoder.string)
  use track <- decoder.field("track", decoder.string)
  use listing_id <- decoder.field("listingId", decoder.string)
  use mic <- decoder.field("mic", decoder.string)
  use facts <- decoder.field("facts", decoder.list(of: fact_input()))
  use events <- decoder.field("events", decoder.list(of: event_input()))
  use missing_capabilities <- decoder.field(
    "missingCapabilities",
    decoder.list(of: decoder.string),
  )
  decoder.success(BoundReviewInput(
    contract_version,
    provider,
    ReviewInput(
      operation_id,
      mode,
      environment,
      account_reference,
      track,
      listing_id,
      mic,
      source_content_hash,
      facts,
      events,
      missing_capabilities,
    ),
  ))
}

fn fact_input() -> decoder.Decoder(FactInput) {
  use name <- decoder.field("name", decoder.string)
  use state <- decoder.field("state", decoder.string)
  use value <- optional_string("value")
  use unit <- optional_string("unit")
  use source_reference <- decoder.field("sourceReference", decoder.string)
  decoder.success(FactInput(name, state, value, unit, source_reference))
}

fn event_input() -> decoder.Decoder(EventInput) {
  use event_reference <- decoder.field("eventReference", decoder.string)
  use status_lexeme <- decoder.field("statusLexeme", decoder.string)
  use occurred_at <- decoder.field("occurredAtUnixMilliseconds", decoder.int)
  use source_reference <- decoder.field("sourceReference", decoder.string)
  decoder.success(EventInput(
    event_reference,
    status_lexeme,
    occurred_at,
    source_reference,
  ))
}

fn optional_string(
  name: String,
  next: fn(Option(String)) -> decoder.Decoder(value),
) -> decoder.Decoder(value) {
  decoder.optional_field(name, None, decoder.optional(decoder.string), next)
}
