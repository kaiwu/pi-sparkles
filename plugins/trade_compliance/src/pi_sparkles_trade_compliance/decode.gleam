import gleam/dynamic/decode as decoder
import gleam/option.{type Option, None}

pub type FactInput {
  FactInput(
    name: String,
    state: String,
    value: Option(Bool),
    source_reference: String,
  )
}

pub type RuleInput {
  RuleInput(
    rule_id: String,
    version: String,
    effective_from_unix_milliseconds: Int,
    effective_until_unix_milliseconds: Option(Int),
    fact_name: String,
    expected: Bool,
    severity: String,
    authority_reference: String,
  )
}

pub type EvaluationInput {
  EvaluationInput(
    operation_id: String,
    track: String,
    account_reference: String,
    as_of_unix_milliseconds: Int,
    rule_set_content_hash: String,
    facts: List(FactInput),
    rules: List(RuleInput),
    missing_capabilities: List(String),
  )
}

pub fn evaluation_input() -> decoder.Decoder(EvaluationInput) {
  use operation_id <- decoder.field("operationId", decoder.string)
  use track <- decoder.field("track", decoder.string)
  use account_reference <- decoder.field("accountReference", decoder.string)
  use as_of <- decoder.field("asOfUnixMilliseconds", decoder.int)
  use rule_set_content_hash <- decoder.field(
    "ruleSetContentHash",
    decoder.string,
  )
  use facts <- decoder.field("facts", decoder.list(of: fact_input()))
  use rules <- decoder.field("rules", decoder.list(of: rule_input()))
  use missing <- decoder.field(
    "missingCapabilities",
    decoder.list(of: decoder.string),
  )
  decoder.success(EvaluationInput(
    operation_id,
    track,
    account_reference,
    as_of,
    rule_set_content_hash,
    facts,
    rules,
    missing,
  ))
}

fn fact_input() -> decoder.Decoder(FactInput) {
  use name <- decoder.field("name", decoder.string)
  use state <- decoder.field("state", decoder.string)
  use value <- optional_bool("value")
  use source_reference <- decoder.field("sourceReference", decoder.string)
  decoder.success(FactInput(name, state, value, source_reference))
}

fn rule_input() -> decoder.Decoder(RuleInput) {
  use rule_id <- decoder.field("ruleId", decoder.string)
  use version <- decoder.field("version", decoder.string)
  use effective_from <- decoder.field(
    "effectiveFromUnixMilliseconds",
    decoder.int,
  )
  use effective_until <- optional_int("effectiveUntilUnixMilliseconds")
  use fact_name <- decoder.field("factName", decoder.string)
  use expected <- decoder.field("expected", decoder.bool)
  use severity <- decoder.field("severity", decoder.string)
  use authority_reference <- decoder.field("authorityReference", decoder.string)
  decoder.success(RuleInput(
    rule_id,
    version,
    effective_from,
    effective_until,
    fact_name,
    expected,
    severity,
    authority_reference,
  ))
}

fn optional_bool(
  name: String,
  next: fn(Option(Bool)) -> decoder.Decoder(value),
) -> decoder.Decoder(value) {
  decoder.optional_field(name, None, decoder.optional(decoder.bool), next)
}

fn optional_int(
  name: String,
  next: fn(Option(Int)) -> decoder.Decoder(value),
) -> decoder.Decoder(value) {
  decoder.optional_field(name, None, decoder.optional(decoder.int), next)
}
