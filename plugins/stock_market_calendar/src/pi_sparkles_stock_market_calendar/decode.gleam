import gleam/dynamic/decode as decoder
import gleam/option.{type Option, None}

pub type ScopeInput {
  ScopeInput(
    kind: String,
    scope_id: String,
    mic: String,
    symbol: Option(String),
  )
}

pub type QueryInput {
  QueryInput(
    date: String,
    local_time: String,
    timezone: String,
    at_unix_ms: Int,
  )
}

pub type CoverageInput {
  CoverageInput(
    state: String,
    start_unix_ms: Option(Int),
    end_unix_ms: Option(Int),
    reason: Option(String),
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
    coverage: CoverageInput,
    entitlement: EntitlementInput,
    licence: LicenceInput,
    receipt_hash: String,
  )
}

pub type AlternativeInput {
  AlternativeInput(
    category: String,
    other_label: Option(String),
    starts_at_local: Option(String),
    ends_at_local: Option(String),
    evidence_id: String,
  )
}

pub type ValueInput {
  ValueInput(
    state: String,
    category: Option(String),
    other_label: Option(String),
    starts_at_local: Option(String),
    ends_at_local: Option(String),
    reason: Option(String),
    alternatives: List(AlternativeInput),
  )
}

pub type FactInput {
  FactInput(
    fact_id: String,
    kind: String,
    source_id: String,
    date: Option(String),
    as_of_unix_ms: Int,
    retrieved_at_unix_ms: Int,
    value: ValueInput,
  )
}

pub type PageInput {
  PageInput(offset: Int, limit: Int)
}

pub type Input {
  Input(
    track: String,
    scope: ScopeInput,
    query: QueryInput,
    sources: List(SourceInput),
    facts: List(FactInput),
    page: PageInput,
  )
}

pub fn input() -> decoder.Decoder(Input) {
  use track <- decoder.field("track", decoder.string)
  use scope <- decoder.field("scope", scope_decoder())
  use query <- decoder.field("query", query_decoder())
  use sources <- decoder.field("sources", decoder.list(of: source_decoder()))
  use facts <- decoder.field("facts", decoder.list(of: fact_decoder()))
  use page <- decoder.field("page", page_decoder())
  decoder.success(Input(track, scope, query, sources, facts, page))
}

fn scope_decoder() -> decoder.Decoder(ScopeInput) {
  use kind <- decoder.field("kind", decoder.string)
  use scope_id <- decoder.field("scopeId", decoder.string)
  use mic <- decoder.field("mic", decoder.string)
  use symbol <- optional_string("symbol")
  decoder.success(ScopeInput(kind, scope_id, mic, symbol))
}

fn query_decoder() -> decoder.Decoder(QueryInput) {
  use date <- decoder.field("date", decoder.string)
  use local_time <- decoder.field("localTime", decoder.string)
  use timezone <- decoder.field("timezone", decoder.string)
  use at <- decoder.field("atUnixMilliseconds", decoder.int)
  decoder.success(QueryInput(date, local_time, timezone, at))
}

fn coverage_decoder() -> decoder.Decoder(CoverageInput) {
  use state <- decoder.field("state", decoder.string)
  use start <- optional_int("startUnixMilliseconds")
  use end <- optional_int("endUnixMilliseconds")
  use reason <- optional_string("reason")
  decoder.success(CoverageInput(state, start, end, reason))
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
  use coverage <- decoder.field("coverage", coverage_decoder())
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
    coverage,
    entitlement,
    licence,
    receipt_hash,
  ))
}

fn alternative_decoder() -> decoder.Decoder(AlternativeInput) {
  use category <- decoder.field("category", decoder.string)
  use other_label <- optional_string("otherLabel")
  use starts <- optional_string("startsAtLocal")
  use ends <- optional_string("endsAtLocal")
  use evidence_id <- decoder.field("evidenceId", decoder.string)
  decoder.success(AlternativeInput(
    category,
    other_label,
    starts,
    ends,
    evidence_id,
  ))
}

fn value_decoder() -> decoder.Decoder(ValueInput) {
  use state <- decoder.field("state", decoder.string)
  use category <- optional_string("category")
  use other_label <- optional_string("otherLabel")
  use starts <- optional_string("startsAtLocal")
  use ends <- optional_string("endsAtLocal")
  use reason <- optional_string("reason")
  use alternatives <- decoder.field(
    "alternatives",
    decoder.list(of: alternative_decoder()),
  )
  decoder.success(ValueInput(
    state,
    category,
    other_label,
    starts,
    ends,
    reason,
    alternatives,
  ))
}

fn fact_decoder() -> decoder.Decoder(FactInput) {
  use fact_id <- decoder.field("factId", decoder.string)
  use kind <- decoder.field("kind", decoder.string)
  use source_id <- decoder.field("sourceId", decoder.string)
  use date <- optional_string("date")
  use as_of <- decoder.field("asOfUnixMilliseconds", decoder.int)
  use retrieved <- decoder.field("retrievedAtUnixMilliseconds", decoder.int)
  use value <- decoder.field("value", value_decoder())
  decoder.success(FactInput(
    fact_id,
    kind,
    source_id,
    date,
    as_of,
    retrieved,
    value,
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
