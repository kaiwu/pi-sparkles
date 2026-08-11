import gleam/dynamic/decode as decoder
import gleam/option.{type Option, None}

pub type ListingInput {
  ListingInput(
    listing_id: String,
    mic: String,
    symbol: String,
    currency: String,
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
    source_id: String,
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

pub type ExchangeTimeInput {
  ExchangeTimeInput(
    state: String,
    unix_milliseconds: Option(Int),
    source_lexeme: Option(String),
    reason: Option(String),
  )
}

pub type SequenceInput {
  SequenceInput(
    state: String,
    value: Option(Int),
    scope: String,
    reason: Option(String),
  )
}

pub type GapInput {
  GapInput(
    state: String,
    from_sequence: Option(Int),
    to_sequence: Option(Int),
    reason: Option(String),
  )
}

pub type VenueInput {
  VenueInput(kind: String, code: String)
}

pub type AggregationInput {
  AggregationInput(
    kind: String,
    venues: List(VenueInput),
    coverage: String,
    method_label: Option(String),
    reason: Option(String),
  )
}

pub type SizeUnitInput {
  SizeUnitInput(kind: String, label: Option(String), reason: Option(String))
}

pub type CandidateInput {
  CandidateInput(raw_price: String, raw_size: String, venue: VenueInput)
}

pub type AlternativeInput {
  AlternativeInput(
    raw_price: String,
    raw_size: String,
    venue: VenueInput,
    evidence_id: String,
  )
}

pub type SideInput {
  SideInput(
    state: String,
    candidate: Option(CandidateInput),
    reason: Option(String),
    alternatives: List(AlternativeInput),
  )
}

pub type ReportInput {
  ReportInput(
    report_id: String,
    source_id: String,
    currency: String,
    provider_timestamp: String,
    provider_time_unix_ms: Int,
    received_at_unix_ms: Int,
    exchange_time: ExchangeTimeInput,
    sequence: SequenceInput,
    gap: GapInput,
    aggregation: AggregationInput,
    size_unit: SizeUnitInput,
    condition_codes: List(String),
    bid: SideInput,
    ask: SideInput,
  )
}

pub type PageInput {
  PageInput(offset: Int, limit: Int)
}

pub type Input {
  Input(
    track: String,
    listing: ListingInput,
    sources: List(SourceInput),
    reports: List(ReportInput),
    page: PageInput,
  )
}

pub fn input() -> decoder.Decoder(Input) {
  use track <- decoder.field("track", decoder.string)
  use listing <- decoder.field("listing", listing_decoder())
  use sources <- decoder.field("sources", decoder.list(of: source_decoder()))
  use reports <- decoder.field("reports", decoder.list(of: report_decoder()))
  use page <- decoder.field("page", page_decoder())
  decoder.success(Input(track, listing, sources, reports, page))
}

fn listing_decoder() -> decoder.Decoder(ListingInput) {
  use listing_id <- decoder.field("listingId", decoder.string)
  use mic <- decoder.field("mic", decoder.string)
  use symbol <- decoder.field("symbol", decoder.string)
  use currency <- decoder.field("currency", decoder.string)
  decoder.success(ListingInput(listing_id, mic, symbol, currency))
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
  use source_id <- decoder.field("sourceId", decoder.string)
  use provider <- decoder.field("provider", decoder.string)
  use reference <- decoder.field("reference", decoder.string)
  use kind <- decoder.field("kind", decoder.string)
  use other_kind <- optional_string("otherKind")
  use feed <- decoder.field("feed", decoder.string)
  use entitlement <- decoder.field("entitlement", entitlement_decoder())
  use licence <- decoder.field("licence", licence_decoder())
  use receipt_hash <- decoder.field("receiptHash", decoder.string)
  decoder.success(SourceInput(
    source_id,
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

fn exchange_time_decoder() -> decoder.Decoder(ExchangeTimeInput) {
  use state <- decoder.field("state", decoder.string)
  use unix_milliseconds <- optional_int("unixMilliseconds")
  use source_lexeme <- optional_string("sourceLexeme")
  use reason <- optional_string("reason")
  decoder.success(ExchangeTimeInput(
    state,
    unix_milliseconds,
    source_lexeme,
    reason,
  ))
}

fn sequence_decoder() -> decoder.Decoder(SequenceInput) {
  use state <- decoder.field("state", decoder.string)
  use value <- optional_int("value")
  use scope <- decoder.field("scope", decoder.string)
  use reason <- optional_string("reason")
  decoder.success(SequenceInput(state, value, scope, reason))
}

fn gap_decoder() -> decoder.Decoder(GapInput) {
  use state <- decoder.field("state", decoder.string)
  use from_sequence <- optional_int("fromSequence")
  use to_sequence <- optional_int("toSequence")
  use reason <- optional_string("reason")
  decoder.success(GapInput(state, from_sequence, to_sequence, reason))
}

fn venue_decoder() -> decoder.Decoder(VenueInput) {
  use kind <- decoder.field("kind", decoder.string)
  use code <- decoder.field("code", decoder.string)
  decoder.success(VenueInput(kind, code))
}

fn aggregation_decoder() -> decoder.Decoder(AggregationInput) {
  use kind <- decoder.field("kind", decoder.string)
  use venues <- decoder.field("venues", decoder.list(of: venue_decoder()))
  use coverage <- decoder.field("coverage", decoder.string)
  use method_label <- optional_string("methodLabel")
  use reason <- optional_string("reason")
  decoder.success(AggregationInput(kind, venues, coverage, method_label, reason))
}

fn size_unit_decoder() -> decoder.Decoder(SizeUnitInput) {
  use kind <- decoder.field("kind", decoder.string)
  use label <- optional_string("label")
  use reason <- optional_string("reason")
  decoder.success(SizeUnitInput(kind, label, reason))
}

fn candidate_decoder() -> decoder.Decoder(CandidateInput) {
  use raw_price <- decoder.field("rawPrice", decoder.string)
  use raw_size <- decoder.field("rawSize", decoder.string)
  use venue <- decoder.field("venue", venue_decoder())
  decoder.success(CandidateInput(raw_price, raw_size, venue))
}

fn alternative_decoder() -> decoder.Decoder(AlternativeInput) {
  use raw_price <- decoder.field("rawPrice", decoder.string)
  use raw_size <- decoder.field("rawSize", decoder.string)
  use venue <- decoder.field("venue", venue_decoder())
  use evidence_id <- decoder.field("evidenceId", decoder.string)
  decoder.success(AlternativeInput(raw_price, raw_size, venue, evidence_id))
}

fn side_decoder() -> decoder.Decoder(SideInput) {
  use state <- decoder.field("state", decoder.string)
  use candidate <- optional_candidate("candidate")
  use reason <- optional_string("reason")
  use alternatives <- decoder.field(
    "alternatives",
    decoder.list(of: alternative_decoder()),
  )
  decoder.success(SideInput(state, candidate, reason, alternatives))
}

fn report_decoder() -> decoder.Decoder(ReportInput) {
  use report_id <- decoder.field("reportId", decoder.string)
  use source_id <- decoder.field("sourceId", decoder.string)
  use currency <- decoder.field("currency", decoder.string)
  use provider_timestamp <- decoder.field("providerTimestamp", decoder.string)
  use provider_time <- decoder.field(
    "providerTimeUnixMilliseconds",
    decoder.int,
  )
  use received_at <- decoder.field("receivedAtUnixMilliseconds", decoder.int)
  use exchange_time <- decoder.field("exchangeTime", exchange_time_decoder())
  use sequence <- decoder.field("sequence", sequence_decoder())
  use gap <- decoder.field("gap", gap_decoder())
  use aggregation <- decoder.field("aggregation", aggregation_decoder())
  use size_unit <- decoder.field("sizeUnit", size_unit_decoder())
  use conditions <- decoder.field(
    "conditionCodes",
    decoder.list(of: decoder.string),
  )
  use bid <- decoder.field("bid", side_decoder())
  use ask <- decoder.field("ask", side_decoder())
  decoder.success(ReportInput(
    report_id,
    source_id,
    currency,
    provider_timestamp,
    provider_time,
    received_at,
    exchange_time,
    sequence,
    gap,
    aggregation,
    size_unit,
    conditions,
    bid,
    ask,
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

fn optional_candidate(
  field: String,
  next: fn(Option(CandidateInput)) -> decoder.Decoder(value),
) -> decoder.Decoder(value) {
  decoder.optional_field(
    field,
    None,
    decoder.optional(candidate_decoder()),
    next,
  )
}
