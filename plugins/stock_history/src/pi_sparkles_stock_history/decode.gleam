import gleam/dynamic/decode as decoder
import gleam/option.{type Option, None}

pub type ListingInput {
  ListingInput(listing_id: String, mic: String, symbol: String)
}

pub type RangeInput {
  RangeInput(start_date: String, end_date: String)
}

pub type AdjustmentInput {
  AdjustmentInput(kind: String, provider: Option(String), basis: Option(String))
}

pub type SessionInput {
  SessionInput(state: String, other_label: Option(String))
}

pub type PaginationInput {
  PaginationInput(state: String, maximum: Option(Int))
}

pub type GapInput {
  GapInput(
    session_date: String,
    state: String,
    evidence_reference: Option(String),
  )
}

pub type CalendarInput {
  CalendarInput(state: String, reason: Option(String), gaps: List(GapInput))
}

pub type BatchInput {
  BatchInput(
    retrieved_at_unix_ms: Int,
    currency: String,
    volume_unit: String,
    adjustment: AdjustmentInput,
    session: SessionInput,
    pagination: PaginationInput,
    calendar: CalendarInput,
  )
}

pub type BarInput {
  BarInput(
    session_date: String,
    source_timestamp: String,
    time_basis: String,
    at_unix_ms: Option(Int),
    raw_open: String,
    raw_high: String,
    raw_low: String,
    raw_close: String,
    raw_volume: String,
    raw_trade_count: Option(String),
    raw_vwap: Option(String),
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

pub type PageInput {
  PageInput(offset: Int, limit: Int)
}

pub type Input {
  Input(
    track: String,
    listing: ListingInput,
    range: RangeInput,
    batch: BatchInput,
    bars: List(BarInput),
    source: SourceInput,
    page: PageInput,
  )
}

pub fn input() -> decoder.Decoder(Input) {
  use track <- decoder.field("track", decoder.string)
  use listing <- decoder.field("listing", listing_decoder())
  use range <- decoder.field("range", range_decoder())
  use batch <- decoder.field("batch", batch_decoder())
  use bars <- decoder.field("bars", decoder.list(of: bar_decoder()))
  use source <- decoder.field("source", source_decoder())
  use page <- decoder.field("page", page_decoder())
  decoder.success(Input(track, listing, range, batch, bars, source, page))
}

fn listing_decoder() -> decoder.Decoder(ListingInput) {
  use listing_id <- decoder.field("listingId", decoder.string)
  use mic <- decoder.field("mic", decoder.string)
  use symbol <- decoder.field("symbol", decoder.string)
  decoder.success(ListingInput(listing_id, mic, symbol))
}

fn range_decoder() -> decoder.Decoder(RangeInput) {
  use start <- decoder.field("startDate", decoder.string)
  use end <- decoder.field("endDate", decoder.string)
  decoder.success(RangeInput(start, end))
}

fn adjustment_decoder() -> decoder.Decoder(AdjustmentInput) {
  use kind <- decoder.field("kind", decoder.string)
  use provider <- optional_string("provider")
  use basis <- optional_string("basis")
  decoder.success(AdjustmentInput(kind, provider, basis))
}

fn session_decoder() -> decoder.Decoder(SessionInput) {
  use state <- decoder.field("state", decoder.string)
  use other_label <- optional_string("otherLabel")
  decoder.success(SessionInput(state, other_label))
}

fn pagination_decoder() -> decoder.Decoder(PaginationInput) {
  use state <- decoder.field("state", decoder.string)
  use maximum <- optional_int("maximum")
  decoder.success(PaginationInput(state, maximum))
}

fn gap_decoder() -> decoder.Decoder(GapInput) {
  use session_date <- decoder.field("sessionDate", decoder.string)
  use state <- decoder.field("state", decoder.string)
  use reference <- optional_string("evidenceReference")
  decoder.success(GapInput(session_date, state, reference))
}

fn calendar_decoder() -> decoder.Decoder(CalendarInput) {
  use state <- decoder.field("state", decoder.string)
  use reason <- optional_string("reason")
  use gaps <- decoder.field("gaps", decoder.list(of: gap_decoder()))
  decoder.success(CalendarInput(state, reason, gaps))
}

fn batch_decoder() -> decoder.Decoder(BatchInput) {
  use retrieved <- decoder.field("retrievedAtUnixMilliseconds", decoder.int)
  use currency <- decoder.field("currency", decoder.string)
  use volume_unit <- decoder.field("volumeUnit", decoder.string)
  use adjustment <- decoder.field("adjustment", adjustment_decoder())
  use session <- decoder.field("session", session_decoder())
  use pagination <- decoder.field("pagination", pagination_decoder())
  use calendar <- decoder.field("calendar", calendar_decoder())
  decoder.success(BatchInput(
    retrieved,
    currency,
    volume_unit,
    adjustment,
    session,
    pagination,
    calendar,
  ))
}

fn bar_decoder() -> decoder.Decoder(BarInput) {
  use session_date <- decoder.field("sessionDate", decoder.string)
  use source_timestamp <- decoder.field("sourceTimestamp", decoder.string)
  use time_basis <- decoder.field("timeBasis", decoder.string)
  use at <- optional_int("atUnixMilliseconds")
  use open <- decoder.field("rawOpen", decoder.string)
  use high <- decoder.field("rawHigh", decoder.string)
  use low <- decoder.field("rawLow", decoder.string)
  use close <- decoder.field("rawClose", decoder.string)
  use volume <- decoder.field("rawVolume", decoder.string)
  use trade_count <- optional_string("rawTradeCount")
  use vwap <- optional_string("rawVwap")
  decoder.success(BarInput(
    session_date,
    source_timestamp,
    time_basis,
    at,
    open,
    high,
    low,
    close,
    volume,
    trade_count,
    vwap,
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

fn page_decoder() -> decoder.Decoder(PageInput) {
  use offset <- decoder.field("offset", decoder.int)
  use limit <- decoder.field("limit", decoder.int)
  decoder.success(PageInput(offset, limit))
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
