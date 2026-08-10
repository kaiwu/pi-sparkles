import gleam/dynamic/decode as decoder
import gleam/option.{type Option, None}

pub type MarketInput {
  MarketInput(mic: String, scope_kind: String, scope_id: String, label: String)
}

pub type SessionInput {
  SessionInput(state: String, other_label: Option(String))
}

pub type CoverageInput {
  CoverageInput(
    state: String,
    expected_members: Option(Int),
    reason: Option(String),
  )
}

pub type SnapshotInput {
  SnapshotInput(
    provider_timestamp: String,
    as_of_unix_ms: Int,
    retrieved_at_unix_ms: Int,
    currency: String,
    session: SessionInput,
    coverage: CoverageInput,
  )
}

pub type GroupInput {
  GroupInput(kind: String, id: String, label: String)
}

pub type PriceAlternativeInput {
  PriceAlternativeInput(
    raw_current: String,
    raw_previous_close: String,
    evidence_id: String,
  )
}

pub type PriceInput {
  PriceInput(
    state: String,
    raw_current: Option(String),
    raw_previous_close: Option(String),
    reason: Option(String),
    alternatives: List(PriceAlternativeInput),
  )
}

pub type MeasurementInput {
  MeasurementInput(
    state: String,
    raw_value: Option(String),
    unit: Option(String),
    method: Option(String),
    reason: Option(String),
  )
}

pub type MemberInput {
  MemberInput(
    listing_id: String,
    mic: String,
    symbol: String,
    label: Option(String),
    groups: List(GroupInput),
    price: PriceInput,
    volume: MeasurementInput,
    volatility: MeasurementInput,
  )
}

pub type CalculationInput {
  CalculationInput(
    change_fraction_scale: Int,
    rounding: String,
    extrema_limit: Int,
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
    market: MarketInput,
    snapshot: SnapshotInput,
    members: List(MemberInput),
    calculation: CalculationInput,
    source: SourceInput,
    page: PageInput,
  )
}

pub fn input() -> decoder.Decoder(Input) {
  use track <- decoder.field("track", decoder.string)
  use market <- decoder.field("market", market_decoder())
  use snapshot <- decoder.field("snapshot", snapshot_decoder())
  use members <- decoder.field("members", decoder.list(of: member_decoder()))
  use calculation <- decoder.field("calculation", calculation_decoder())
  use source <- decoder.field("source", source_decoder())
  use page <- decoder.field("page", page_decoder())
  decoder.success(Input(
    track,
    market,
    snapshot,
    members,
    calculation,
    source,
    page,
  ))
}

fn market_decoder() -> decoder.Decoder(MarketInput) {
  use mic <- decoder.field("mic", decoder.string)
  use scope_kind <- decoder.field("scopeKind", decoder.string)
  use scope_id <- decoder.field("scopeId", decoder.string)
  use label <- decoder.field("label", decoder.string)
  decoder.success(MarketInput(mic, scope_kind, scope_id, label))
}

fn session_decoder() -> decoder.Decoder(SessionInput) {
  use state <- decoder.field("state", decoder.string)
  use other_label <- optional_string("otherLabel")
  decoder.success(SessionInput(state, other_label))
}

fn coverage_decoder() -> decoder.Decoder(CoverageInput) {
  use state <- decoder.field("state", decoder.string)
  use expected_members <- optional_int("expectedMembers")
  use reason <- optional_string("reason")
  decoder.success(CoverageInput(state, expected_members, reason))
}

fn snapshot_decoder() -> decoder.Decoder(SnapshotInput) {
  use timestamp <- decoder.field("providerTimestamp", decoder.string)
  use as_of <- decoder.field("asOfUnixMilliseconds", decoder.int)
  use retrieved <- decoder.field("retrievedAtUnixMilliseconds", decoder.int)
  use currency <- decoder.field("currency", decoder.string)
  use session <- decoder.field("session", session_decoder())
  use coverage <- decoder.field("coverage", coverage_decoder())
  decoder.success(SnapshotInput(
    timestamp,
    as_of,
    retrieved,
    currency,
    session,
    coverage,
  ))
}

fn group_decoder() -> decoder.Decoder(GroupInput) {
  use kind <- decoder.field("kind", decoder.string)
  use id <- decoder.field("id", decoder.string)
  use label <- decoder.field("label", decoder.string)
  decoder.success(GroupInput(kind, id, label))
}

fn price_alternative_decoder() -> decoder.Decoder(PriceAlternativeInput) {
  use current <- decoder.field("rawCurrent", decoder.string)
  use previous <- decoder.field("rawPreviousClose", decoder.string)
  use evidence_id <- decoder.field("evidenceId", decoder.string)
  decoder.success(PriceAlternativeInput(current, previous, evidence_id))
}

fn price_decoder() -> decoder.Decoder(PriceInput) {
  use state <- decoder.field("state", decoder.string)
  use current <- optional_string("rawCurrent")
  use previous <- optional_string("rawPreviousClose")
  use reason <- optional_string("reason")
  use alternatives <- decoder.field(
    "alternatives",
    decoder.list(of: price_alternative_decoder()),
  )
  decoder.success(PriceInput(state, current, previous, reason, alternatives))
}

fn measurement_decoder() -> decoder.Decoder(MeasurementInput) {
  use state <- decoder.field("state", decoder.string)
  use raw_value <- optional_string("rawValue")
  use unit <- optional_string("unit")
  use method <- optional_string("method")
  use reason <- optional_string("reason")
  decoder.success(MeasurementInput(state, raw_value, unit, method, reason))
}

fn member_decoder() -> decoder.Decoder(MemberInput) {
  use listing_id <- decoder.field("listingId", decoder.string)
  use mic <- decoder.field("mic", decoder.string)
  use symbol <- decoder.field("symbol", decoder.string)
  use label <- optional_string("label")
  use groups <- decoder.field("groups", decoder.list(of: group_decoder()))
  use price <- decoder.field("price", price_decoder())
  use volume <- decoder.field("volume", measurement_decoder())
  use volatility <- decoder.field("volatility", measurement_decoder())
  decoder.success(MemberInput(
    listing_id,
    mic,
    symbol,
    label,
    groups,
    price,
    volume,
    volatility,
  ))
}

fn calculation_decoder() -> decoder.Decoder(CalculationInput) {
  use scale <- decoder.field("changeFractionScale", decoder.int)
  use rounding <- decoder.field("rounding", decoder.string)
  use extrema_limit <- decoder.field("extremaLimit", decoder.int)
  decoder.success(CalculationInput(scale, rounding, extrema_limit))
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
