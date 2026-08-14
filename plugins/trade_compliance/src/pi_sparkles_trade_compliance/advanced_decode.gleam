import gleam/dynamic/decode as decoder
import gleam/option.{type Option, None}

pub type FactInput {
  FactInput(
    name: String,
    state: String,
    value: Option(Bool),
    values: List(Bool),
    reason: Option(String),
    source_reference: String,
  )
}

/// Prefix-ordered expression node. `child_count` is zero for predicates, one
/// for negation, and positive for all/any. This representation keeps recursive
/// expressions bounded and unambiguous at the Pi decode boundary.
pub type ExpressionNodeInput {
  ExpressionNodeInput(
    kind: String,
    child_count: Int,
    fact_name: Option(String),
    expected: Option(Bool),
  )
}

pub type CorrectionInput {
  CorrectionInput(
    from_version: String,
    authority_reference: String,
    reason: String,
  )
}

pub type RuleInput {
  RuleInput(
    rule_id: String,
    version: String,
    track: String,
    jurisdiction: String,
    account_scope: String,
    effective_from_unix_milliseconds: Int,
    effective_until_unix_milliseconds: Option(Int),
    expression_nodes: List(ExpressionNodeInput),
    severity: String,
    authority_reference: String,
    corrections: List(CorrectionInput),
  )
}

pub type EvaluationInput {
  EvaluationInput(
    operation_id: String,
    track: String,
    account_reference: String,
    as_of_unix_milliseconds: Int,
    rule_set_content_hash: String,
    completeness: String,
    completeness_reason: String,
    facts: List(FactInput),
    rules: List(RuleInput),
  )
}

pub type ExplanationInput {
  ExplanationInput(
    operation_id: String,
    expression_nodes: List(ExpressionNodeInput),
    facts: List(FactInput),
  )
}

pub type ComparisonInput {
  ComparisonInput(operation_id: String, before: RuleInput, after: RuleInput)
}

pub fn evaluation_input() -> decoder.Decoder(EvaluationInput) {
  use operation_id <- decoder.field("operationId", decoder.string)
  use track <- decoder.field("track", decoder.string)
  use account_reference <- decoder.field("accountReference", decoder.string)
  use as_of <- decoder.field("asOfUnixMilliseconds", decoder.int)
  use content_hash <- decoder.field("ruleSetContentHash", decoder.string)
  use completeness <- decoder.field("completeness", decoder.string)
  use completeness_reason <- decoder.field("completenessReason", decoder.string)
  use facts <- decoder.field("facts", decoder.list(of: fact_input()))
  use rules <- decoder.field("rules", decoder.list(of: rule_input()))
  decoder.success(EvaluationInput(
    operation_id,
    track,
    account_reference,
    as_of,
    content_hash,
    completeness,
    completeness_reason,
    facts,
    rules,
  ))
}

pub fn explanation_input() -> decoder.Decoder(ExplanationInput) {
  use operation_id <- decoder.field("operationId", decoder.string)
  use nodes <- decoder.field(
    "expressionNodes",
    decoder.list(of: expression_node_input()),
  )
  use facts <- decoder.field("facts", decoder.list(of: fact_input()))
  decoder.success(ExplanationInput(operation_id, nodes, facts))
}

pub fn comparison_input() -> decoder.Decoder(ComparisonInput) {
  use operation_id <- decoder.field("operationId", decoder.string)
  use before <- decoder.field("before", rule_input())
  use after <- decoder.field("after", rule_input())
  decoder.success(ComparisonInput(operation_id, before, after))
}

fn fact_input() -> decoder.Decoder(FactInput) {
  use name <- decoder.field("name", decoder.string)
  use state <- decoder.field("state", decoder.string)
  use value <- optional_bool("value")
  use values <- decoder.field("values", decoder.list(of: decoder.bool))
  use reason <- optional_string("reason")
  use source_reference <- decoder.field("sourceReference", decoder.string)
  decoder.success(FactInput(
    name,
    state,
    value,
    values,
    reason,
    source_reference,
  ))
}

fn expression_node_input() -> decoder.Decoder(ExpressionNodeInput) {
  use kind <- decoder.field("kind", decoder.string)
  use child_count <- decoder.field("childCount", decoder.int)
  use fact_name <- optional_string("factName")
  use expected <- optional_bool("expected")
  decoder.success(ExpressionNodeInput(kind, child_count, fact_name, expected))
}

fn correction_input() -> decoder.Decoder(CorrectionInput) {
  use from_version <- decoder.field("fromVersion", decoder.string)
  use authority_reference <- decoder.field("authorityReference", decoder.string)
  use reason <- decoder.field("reason", decoder.string)
  decoder.success(CorrectionInput(from_version, authority_reference, reason))
}

fn rule_input() -> decoder.Decoder(RuleInput) {
  use rule_id <- decoder.field("ruleId", decoder.string)
  use version <- decoder.field("version", decoder.string)
  use track <- decoder.field("track", decoder.string)
  use jurisdiction <- decoder.field("jurisdiction", decoder.string)
  use account_scope <- decoder.field("accountScope", decoder.string)
  use effective_from <- decoder.field(
    "effectiveFromUnixMilliseconds",
    decoder.int,
  )
  use effective_until <- optional_int("effectiveUntilUnixMilliseconds")
  use expression_nodes <- decoder.field(
    "expressionNodes",
    decoder.list(of: expression_node_input()),
  )
  use severity <- decoder.field("severity", decoder.string)
  use authority_reference <- decoder.field("authorityReference", decoder.string)
  use corrections <- decoder.field(
    "corrections",
    decoder.list(of: correction_input()),
  )
  decoder.success(RuleInput(
    rule_id,
    version,
    track,
    jurisdiction,
    account_scope,
    effective_from,
    effective_until,
    expression_nodes,
    severity,
    authority_reference,
    corrections,
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

fn optional_string(
  name: String,
  next: fn(Option(String)) -> decoder.Decoder(value),
) -> decoder.Decoder(value) {
  decoder.optional_field(name, None, decoder.optional(decoder.string), next)
}
