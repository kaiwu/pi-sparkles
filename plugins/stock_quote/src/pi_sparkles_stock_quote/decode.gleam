import gleam/dynamic/decode as decoder
import gleam/option.{type Option, None}

pub type ListingInput {
  ListingInput(listing_id: String, mic: String, symbol: String)
}

pub type SideInput {
  SideInput(exchange: String, raw_price: String, raw_size: String)
}

pub type QuoteInput {
  QuoteInput(
    provider_timestamp: String,
    as_of_unix_ms: Int,
    retrieved_at_unix_ms: Int,
    currency: String,
    bid: SideInput,
    ask: SideInput,
    condition_codes: List(String),
    tape: String,
    size_unit: String,
  )
}

pub type EntitlementInput {
  EntitlementInput(state: String, delay_milliseconds: Option(Int))
}

pub type LicenceInput {
  LicenceInput(label: String, redistribution: String, notes: Option(String))
}

pub type SourceInput {
  SourceInput(
    provider: String,
    reference: String,
    kind: String,
    other_kind: Option(String),
    feed: String,
    entitlement: EntitlementInput,
    licence: LicenceInput,
    receipt_hash: String,
  )
}

pub type Input {
  Input(
    track: String,
    listing: ListingInput,
    quote: QuoteInput,
    source: SourceInput,
  )
}

pub fn input() -> decoder.Decoder(Input) {
  use track <- decoder.field("track", decoder.string)
  use listing <- decoder.field("listing", listing_decoder())
  use quote <- decoder.field("quote", quote_decoder())
  use source <- decoder.field("source", source_decoder())
  decoder.success(Input(track, listing, quote, source))
}

fn listing_decoder() -> decoder.Decoder(ListingInput) {
  use listing_id <- decoder.field("listingId", decoder.string)
  use mic <- decoder.field("mic", decoder.string)
  use symbol <- decoder.field("symbol", decoder.string)
  decoder.success(ListingInput(listing_id, mic, symbol))
}

fn side_decoder() -> decoder.Decoder(SideInput) {
  use exchange <- decoder.field("exchange", decoder.string)
  use raw_price <- decoder.field("rawPrice", decoder.string)
  use raw_size <- decoder.field("rawSize", decoder.string)
  decoder.success(SideInput(exchange, raw_price, raw_size))
}

fn quote_decoder() -> decoder.Decoder(QuoteInput) {
  use provider_timestamp <- decoder.field("providerTimestamp", decoder.string)
  use as_of <- decoder.field("asOfUnixMilliseconds", decoder.int)
  use retrieved_at <- decoder.field("retrievedAtUnixMilliseconds", decoder.int)
  use currency <- decoder.field("currency", decoder.string)
  use bid <- decoder.field("bid", side_decoder())
  use ask <- decoder.field("ask", side_decoder())
  use conditions <- decoder.field(
    "conditionCodes",
    decoder.list(of: decoder.string),
  )
  use tape <- decoder.field("tape", decoder.string)
  use size_unit <- decoder.field("sizeUnit", decoder.string)
  decoder.success(QuoteInput(
    provider_timestamp,
    as_of,
    retrieved_at,
    currency,
    bid,
    ask,
    conditions,
    tape,
    size_unit,
  ))
}

fn entitlement_decoder() -> decoder.Decoder(EntitlementInput) {
  use state <- decoder.field("state", decoder.string)
  use delay <- optional_int("delayMilliseconds")
  decoder.success(EntitlementInput(state, delay))
}

fn licence_decoder() -> decoder.Decoder(LicenceInput) {
  use label <- decoder.field("label", decoder.string)
  use redistribution <- decoder.field("redistribution", decoder.string)
  use notes <- optional_string("notes")
  decoder.success(LicenceInput(label, redistribution, notes))
}

fn source_decoder() -> decoder.Decoder(SourceInput) {
  use provider <- decoder.field("provider", decoder.string)
  use reference <- decoder.field("reference", decoder.string)
  use kind <- decoder.field("kind", decoder.string)
  use other_kind <- optional_string("otherKind")
  use feed <- decoder.field("feed", decoder.string)
  use entitlement <- decoder.field("entitlement", entitlement_decoder())
  use licence <- decoder.field("licence", licence_decoder())
  use receipt_hash <- decoder.field("receiptHash", decoder.string)
  decoder.success(SourceInput(
    provider,
    reference,
    kind,
    other_kind,
    feed,
    entitlement,
    licence,
    receipt_hash,
  ))
}

fn optional_string(
  name: String,
  next: fn(Option(String)) -> decoder.Decoder(value),
) -> decoder.Decoder(value) {
  decoder.optional_field(name, None, decoder.optional(decoder.string), next)
}

fn optional_int(
  name: String,
  next: fn(Option(Int)) -> decoder.Decoder(value),
) -> decoder.Decoder(value) {
  decoder.optional_field(name, None, decoder.optional(decoder.int), next)
}
