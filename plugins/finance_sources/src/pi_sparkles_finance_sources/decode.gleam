import gleam/dynamic/decode as decoder
import gleam/option.{type Option, None}

pub type AssumptionValueInput {
  AssumptionValueInput(
    kind: String,
    text: Option(String),
    decimal: Option(String),
    amount: Option(String),
    currency: Option(String),
    boolean: Option(Bool),
  )
}

pub type AssumptionInput {
  AssumptionInput(
    id: String,
    name: String,
    origin: String,
    explanation: String,
    value: AssumptionValueInput,
  )
}

pub type SourceInput {
  SourceInput(
    provider: String,
    reference: String,
    kind: String,
    other_kind: Option(String),
  )
}

pub type LicenceInput {
  LicenceInput(label: String, redistribution: String, notes: Option(String))
}

pub type AvailabilityInput {
  AvailabilityInput(
    state: String,
    reason: Option(String),
    superseded_by: Option(String),
  )
}

pub type EvidenceInput {
  EvidenceInput(
    receipt_hash: String,
    source_fingerprint: String,
    source: SourceInput,
    licence: LicenceInput,
    as_of_unix_ms: Int,
    retrieved_at_unix_ms: Int,
    media_type: String,
    byte_length: Int,
    content_hash: String,
    parents: List(String),
    assumptions: List(String),
    availability: AvailabilityInput,
  )
}

pub type CatalogueInput {
  CatalogueInput(
    instruction_ref: String,
    additional_sensitive_query_keys: List(String),
    assumptions: List(AssumptionInput),
    evidence: List(EvidenceInput),
    roots: List(String),
  )
}

pub type ListInput {
  ListInput(catalogue: CatalogueInput, offset: Int, limit: Int)
}

pub type InspectInput {
  InspectInput(catalogue: CatalogueInput, receipt_hash: String)
}

pub type ExportInput {
  ExportInput(catalogue: CatalogueInput, maximum_manifest_bytes: Int)
}

pub fn list_sources() -> decoder.Decoder(ListInput) {
  use catalogue <- decoder.field("catalogue", catalogue_decoder())
  use offset <- decoder.field("offset", decoder.int)
  use limit <- decoder.field("limit", decoder.int)
  decoder.success(ListInput(catalogue, offset, limit))
}

pub fn inspect_source() -> decoder.Decoder(InspectInput) {
  use catalogue <- decoder.field("catalogue", catalogue_decoder())
  use receipt_hash <- decoder.field("receiptHash", decoder.string)
  decoder.success(InspectInput(catalogue, receipt_hash))
}

pub fn export_manifest() -> decoder.Decoder(ExportInput) {
  use catalogue <- decoder.field("catalogue", catalogue_decoder())
  use maximum <- decoder.field("maximumManifestBytes", decoder.int)
  decoder.success(ExportInput(catalogue, maximum))
}

fn catalogue_decoder() -> decoder.Decoder(CatalogueInput) {
  use instruction_ref <- decoder.field("instructionRef", decoder.string)
  use sensitive_keys <- decoder.field(
    "additionalSensitiveQueryKeys",
    decoder.list(of: decoder.string),
  )
  use assumptions <- decoder.field(
    "assumptions",
    decoder.list(of: assumption_decoder()),
  )
  use evidence <- decoder.field(
    "evidence",
    decoder.list(of: evidence_decoder()),
  )
  use roots <- decoder.field("roots", decoder.list(of: decoder.string))
  decoder.success(CatalogueInput(
    instruction_ref,
    sensitive_keys,
    assumptions,
    evidence,
    roots,
  ))
}

fn assumption_decoder() -> decoder.Decoder(AssumptionInput) {
  use id <- decoder.field("id", decoder.string)
  use name <- decoder.field("name", decoder.string)
  use origin <- decoder.field("origin", decoder.string)
  use explanation <- decoder.field("explanation", decoder.string)
  use value <- decoder.field("value", assumption_value_decoder())
  decoder.success(AssumptionInput(id, name, origin, explanation, value))
}

fn assumption_value_decoder() -> decoder.Decoder(AssumptionValueInput) {
  use kind <- decoder.field("kind", decoder.string)
  use text <- optional_string("text")
  use decimal <- optional_string("decimal")
  use amount <- optional_string("amount")
  use currency <- optional_string("currency")
  use boolean <- decoder.optional_field(
    "boolean",
    None,
    decoder.optional(decoder.bool),
  )
  decoder.success(AssumptionValueInput(
    kind,
    text,
    decimal,
    amount,
    currency,
    boolean,
  ))
}

fn evidence_decoder() -> decoder.Decoder(EvidenceInput) {
  use receipt_hash <- decoder.field("receiptHash", decoder.string)
  use source_fingerprint <- decoder.field("sourceFingerprint", decoder.string)
  use source <- decoder.field("source", source_decoder())
  use licence <- decoder.field("licence", licence_decoder())
  use as_of <- decoder.field("asOfUnixMilliseconds", decoder.int)
  use retrieved_at <- decoder.field("retrievedAtUnixMilliseconds", decoder.int)
  use media_type <- decoder.field("mediaType", decoder.string)
  use byte_length <- decoder.field("byteLength", decoder.int)
  use content_hash <- decoder.field("contentHash", decoder.string)
  use parents <- decoder.field("parents", decoder.list(of: decoder.string))
  use assumptions <- decoder.field(
    "assumptions",
    decoder.list(of: decoder.string),
  )
  use availability <- decoder.field("availability", availability_decoder())
  decoder.success(EvidenceInput(
    receipt_hash,
    source_fingerprint,
    source,
    licence,
    as_of,
    retrieved_at,
    media_type,
    byte_length,
    content_hash,
    parents,
    assumptions,
    availability,
  ))
}

fn source_decoder() -> decoder.Decoder(SourceInput) {
  use provider <- decoder.field("provider", decoder.string)
  use reference <- decoder.field("reference", decoder.string)
  use kind <- decoder.field("kind", decoder.string)
  use other_kind <- optional_string("otherKind")
  decoder.success(SourceInput(provider, reference, kind, other_kind))
}

fn licence_decoder() -> decoder.Decoder(LicenceInput) {
  use label <- decoder.field("label", decoder.string)
  use redistribution <- decoder.field("redistribution", decoder.string)
  use notes <- optional_string("notes")
  decoder.success(LicenceInput(label, redistribution, notes))
}

fn availability_decoder() -> decoder.Decoder(AvailabilityInput) {
  use state <- decoder.field("state", decoder.string)
  use reason <- optional_string("reason")
  use superseded_by <- optional_string("supersededBy")
  decoder.success(AvailabilityInput(state, reason, superseded_by))
}

fn optional_string(
  name: String,
  next: fn(Option(String)) -> decoder.Decoder(value),
) -> decoder.Decoder(value) {
  decoder.optional_field(name, None, decoder.optional(decoder.string), next)
}
