import gleam/dynamic/decode as decoder
import gleam/option.{type Option, None}

pub type ManifestInput {
  ManifestInput(manifest_json: String, manifest_hash: String)
}

pub type ContextInput {
  ContextInput(
    instruction_ref: String,
    track: String,
    date_start: String,
    date_end: String,
    source_cutoff_unix_ms: Int,
    universe: ManifestInput,
    dataset: ManifestInput,
    technical_receipt_roots: List(String),
  )
}

pub type PredicateInput {
  PredicateInput(
    id: String,
    field: String,
    operator: String,
    threshold_raw: String,
    unit: String,
  )
}

pub type FactInput {
  FactInput(
    state: String,
    raw: Option(String),
    reason: Option(String),
    alternatives: List(String),
  )
}

pub type ValueInput {
  ValueInput(
    field: String,
    unit: String,
    source_kind: String,
    known_at_unix_ms: Int,
    evidence_roots: List(String),
    fact: FactInput,
  )
}

pub type RowInput {
  RowInput(
    listing_id: String,
    mic: String,
    observation_date: String,
    observation_id: String,
    values: List(ValueInput),
  )
}

pub type RelationInput {
  RelationInput(match_policy: String, unresolved_policy: String)
}

pub type PageInput {
  PageInput(partition: String, offset: Int, limit: Int)
}

pub type ScreenInput {
  ScreenInput(
    context: ContextInput,
    predicates: List(PredicateInput),
    rows: List(RowInput),
    relation: RelationInput,
    page: PageInput,
  )
}

pub fn screen() -> decoder.Decoder(ScreenInput) {
  use context <- decoder.field("context", context_decoder())
  use predicates <- decoder.field(
    "predicates",
    decoder.list(of: predicate_decoder()),
  )
  use rows <- decoder.field("rows", decoder.list(of: row_decoder()))
  use relation <- decoder.field("relation", relation_decoder())
  use page <- decoder.field("page", page_decoder())
  decoder.success(ScreenInput(context, predicates, rows, relation, page))
}

fn context_decoder() -> decoder.Decoder(ContextInput) {
  use instruction_ref <- decoder.field("instructionRef", decoder.string)
  use track <- decoder.field("track", decoder.string)
  use date_start <- decoder.field("dateStart", decoder.string)
  use date_end <- decoder.field("dateEnd", decoder.string)
  use source_cutoff <- decoder.field(
    "sourceCutoffUnixMilliseconds",
    decoder.int,
  )
  use universe <- decoder.field("universe", manifest_decoder())
  use dataset <- decoder.field("dataset", manifest_decoder())
  use technical_receipt_roots <- decoder.field(
    "technicalReceiptRoots",
    decoder.list(of: decoder.string),
  )
  decoder.success(ContextInput(
    instruction_ref,
    track,
    date_start,
    date_end,
    source_cutoff,
    universe,
    dataset,
    technical_receipt_roots,
  ))
}

fn manifest_decoder() -> decoder.Decoder(ManifestInput) {
  use manifest_json <- decoder.field("manifestJson", decoder.string)
  use manifest_hash <- decoder.field("manifestHash", decoder.string)
  decoder.success(ManifestInput(manifest_json, manifest_hash))
}

fn predicate_decoder() -> decoder.Decoder(PredicateInput) {
  use id <- decoder.field("id", decoder.string)
  use left <- decoder.field("leftOperand", field_operand_decoder())
  use operator <- decoder.field("operator", decoder.string)
  use right <- decoder.field("rightOperand", constant_operand_decoder())
  let #(field, left_unit) = left
  let #(threshold_raw, right_unit) = right
  case left_unit == right_unit {
    True ->
      decoder.success(PredicateInput(
        id,
        field,
        operator,
        threshold_raw,
        left_unit,
      ))
    False ->
      decoder.failure(
        PredicateInput(id, field, operator, threshold_raw, left_unit),
        "predicate operand units must be exactly equal",
      )
  }
}

fn field_operand_decoder() -> decoder.Decoder(#(String, String)) {
  use kind <- decoder.field("kind", decoder.string)
  use field <- decoder.field("field", decoder.string)
  use unit <- decoder.field("unit", decoder.string)
  case kind {
    "field" -> decoder.success(#(field, unit))
    _ -> decoder.failure(#(field, unit), "field operand kind")
  }
}

fn constant_operand_decoder() -> decoder.Decoder(#(String, String)) {
  use kind <- decoder.field("kind", decoder.string)
  use raw <- decoder.field("raw", decoder.string)
  use unit <- decoder.field("unit", decoder.string)
  case kind {
    "constant" -> decoder.success(#(raw, unit))
    _ -> decoder.failure(#(raw, unit), "constant operand kind")
  }
}

fn row_decoder() -> decoder.Decoder(RowInput) {
  use listing_id <- decoder.field("listingId", decoder.string)
  use mic <- decoder.field("mic", decoder.string)
  use observation_date <- decoder.field("observationDate", decoder.string)
  use observation_id <- decoder.field("observationId", decoder.string)
  use values <- decoder.field("values", decoder.list(of: value_decoder()))
  decoder.success(RowInput(
    listing_id,
    mic,
    observation_date,
    observation_id,
    values,
  ))
}

fn value_decoder() -> decoder.Decoder(ValueInput) {
  use field <- decoder.field("field", decoder.string)
  use unit <- decoder.field("unit", decoder.string)
  use source_kind <- decoder.field("sourceKind", decoder.string)
  use known_at <- decoder.field("knownAtUnixMilliseconds", decoder.int)
  use evidence_roots <- decoder.field(
    "evidenceRoots",
    decoder.list(of: decoder.string),
  )
  use fact <- decoder.field("fact", fact_decoder())
  decoder.success(ValueInput(
    field,
    unit,
    source_kind,
    known_at,
    evidence_roots,
    fact,
  ))
}

fn fact_decoder() -> decoder.Decoder(FactInput) {
  use state <- decoder.field("state", decoder.string)
  use raw <- optional_string("raw")
  use reason <- optional_string("reason")
  use alternatives <- decoder.field(
    "alternatives",
    decoder.list(of: decoder.string),
  )
  decoder.success(FactInput(state, raw, reason, alternatives))
}

fn relation_decoder() -> decoder.Decoder(RelationInput) {
  use match_policy <- decoder.field("matchPolicy", decoder.string)
  use unresolved_policy <- decoder.field("unresolvedPolicy", decoder.string)
  decoder.success(RelationInput(match_policy, unresolved_policy))
}

fn page_decoder() -> decoder.Decoder(PageInput) {
  use partition <- decoder.field("partition", decoder.string)
  use offset <- decoder.field("offset", decoder.int)
  use limit <- decoder.field("limit", decoder.int)
  decoder.success(PageInput(partition, offset, limit))
}

fn optional_string(
  name: String,
  next: fn(Option(String)) -> decoder.Decoder(value),
) -> decoder.Decoder(value) {
  decoder.optional_field(name, None, decoder.optional(decoder.string), next)
}
