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

pub type FreshnessPolicyInput {
  FreshnessPolicyInput(
    state: String,
    evaluated_at_unix_ms: Option(Int),
    maximum_age_milliseconds: Option(Int),
    reason: Option(String),
  )
}

pub type CoordinateInput {
  CoordinateInput(observation_key: String, metric: String)
}

pub type UnitInput {
  UnitInput(
    kind: String,
    currency_code: Option(String),
    other_label: Option(String),
  )
}

pub type AdjustmentInput {
  AdjustmentInput(kind: String, provider: Option(String), basis: Option(String))
}

pub type AlternativeInput {
  AlternativeInput(raw_value: String, evidence_id: String)
}

pub type ValueInput {
  ValueInput(
    state: String,
    raw_value: Option(String),
    reason: Option(String),
    alternatives: List(AlternativeInput),
  )
}

pub type FactInput {
  FactInput(
    fact_id: String,
    observation_key: String,
    metric: String,
    source_id: String,
    as_of_unix_ms: Int,
    retrieved_at_unix_ms: Int,
    unit: UnitInput,
    adjustment: AdjustmentInput,
    value: ValueInput,
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

pub type PageInput {
  PageInput(offset: Int, limit: Int)
}

pub type Input {
  Input(
    track: String,
    scope: ScopeInput,
    freshness_policy: FreshnessPolicyInput,
    expected_coordinates: List(CoordinateInput),
    sources: List(SourceInput),
    facts: List(FactInput),
    page: PageInput,
  )
}

pub fn input() -> decoder.Decoder(Input) {
  use track <- decoder.field("track", decoder.string)
  use scope <- decoder.field("scope", scope_decoder())
  use freshness <- decoder.field("freshnessPolicy", freshness_policy_decoder())
  use expected <- decoder.field(
    "expectedCoordinates",
    decoder.list(of: coordinate_decoder()),
  )
  use sources <- decoder.field("sources", decoder.list(of: source_decoder()))
  use facts <- decoder.field("facts", decoder.list(of: fact_decoder()))
  use page <- decoder.field("page", page_decoder())
  decoder.success(Input(track, scope, freshness, expected, sources, facts, page))
}

fn scope_decoder() -> decoder.Decoder(ScopeInput) {
  use kind <- decoder.field("kind", decoder.string)
  use scope_id <- decoder.field("scopeId", decoder.string)
  use mic <- decoder.field("mic", decoder.string)
  use symbol <- optional_string("symbol")
  decoder.success(ScopeInput(kind, scope_id, mic, symbol))
}

fn freshness_policy_decoder() -> decoder.Decoder(FreshnessPolicyInput) {
  use state <- decoder.field("state", decoder.string)
  use evaluated <- optional_int("evaluatedAtUnixMilliseconds")
  use maximum_age <- optional_int("maximumAgeMilliseconds")
  use reason <- optional_string("reason")
  decoder.success(FreshnessPolicyInput(state, evaluated, maximum_age, reason))
}

fn coordinate_decoder() -> decoder.Decoder(CoordinateInput) {
  use key <- decoder.field("observationKey", decoder.string)
  use metric <- decoder.field("metric", decoder.string)
  decoder.success(CoordinateInput(key, metric))
}

fn unit_decoder() -> decoder.Decoder(UnitInput) {
  use kind <- decoder.field("kind", decoder.string)
  use currency_code <- optional_string("currencyCode")
  use other_label <- optional_string("otherLabel")
  decoder.success(UnitInput(kind, currency_code, other_label))
}

fn adjustment_decoder() -> decoder.Decoder(AdjustmentInput) {
  use kind <- decoder.field("kind", decoder.string)
  use provider <- optional_string("provider")
  use basis <- optional_string("basis")
  decoder.success(AdjustmentInput(kind, provider, basis))
}

fn alternative_decoder() -> decoder.Decoder(AlternativeInput) {
  use raw_value <- decoder.field("rawValue", decoder.string)
  use evidence_id <- decoder.field("evidenceId", decoder.string)
  decoder.success(AlternativeInput(raw_value, evidence_id))
}

fn value_decoder() -> decoder.Decoder(ValueInput) {
  use state <- decoder.field("state", decoder.string)
  use raw_value <- optional_string("rawValue")
  use reason <- optional_string("reason")
  use alternatives <- decoder.field(
    "alternatives",
    decoder.list(of: alternative_decoder()),
  )
  decoder.success(ValueInput(state, raw_value, reason, alternatives))
}

fn fact_decoder() -> decoder.Decoder(FactInput) {
  use fact_id <- decoder.field("factId", decoder.string)
  use key <- decoder.field("observationKey", decoder.string)
  use metric <- decoder.field("metric", decoder.string)
  use source_id <- decoder.field("sourceId", decoder.string)
  use as_of <- decoder.field("asOfUnixMilliseconds", decoder.int)
  use retrieved <- decoder.field("retrievedAtUnixMilliseconds", decoder.int)
  use unit <- decoder.field("unit", unit_decoder())
  use adjustment <- decoder.field("adjustment", adjustment_decoder())
  use value <- decoder.field("value", value_decoder())
  decoder.success(FactInput(
    fact_id,
    key,
    metric,
    source_id,
    as_of,
    retrieved,
    unit,
    adjustment,
    value,
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
