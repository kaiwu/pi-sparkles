import finance_broker_review/field
import finance_provenance/hash
import finance_provenance/identity
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import pi_sparkles_trade_compliance/decode.{
  type EvaluationInput, type FactInput, type RuleInput,
}

pub opaque type Response {
  Response(summary: String, details: Json)
}

pub type DomainError {
  InvalidField(field: String, reason: String)
  BudgetExceeded(field: String, maximum: Int)
}

type Outcome {
  Outcome(
    rule: RuleInput,
    state: String,
    reason: String,
    matched_facts: List(FactInput),
    duplicate_fact_count: Int,
  )
}

const maximum_payload_bytes = 150_000

const maximum_safe_unix_milliseconds = 9_007_199_254_740_991

pub fn evaluate(input: EvaluationInput) -> Result(Response, DomainError) {
  use _ <- result.try(valid_text("operationId", input.operation_id, 1, 500))
  use _ <- result.try(valid_track(input.track))
  use _ <- result.try(valid_hash("accountReference", input.account_reference))
  use _ <- result.try(
    case
      input.as_of_unix_milliseconds >= 0
      && input.as_of_unix_milliseconds <= maximum_safe_unix_milliseconds
    {
      True -> Ok(Nil)
      False ->
        Error(InvalidField(
          "asOfUnixMilliseconds",
          "must be a non-negative JavaScript-safe integer",
        ))
    },
  )
  use _ <- result.try(valid_hash(
    "ruleSetContentHash",
    input.rule_set_content_hash,
  ))
  use _ <- result.try(within_budget("facts", input.facts, 200))
  use _ <- result.try(within_budget("rules", input.rules, 200))
  use _ <- result.try(within_budget(
    "missingCapabilities",
    input.missing_capabilities,
    100,
  ))
  use _ <- result.try(case input.rules {
    [] -> Error(InvalidField("rules", "at least one supplied rule is required"))
    _ -> Ok(Nil)
  })
  use _ <- result.try(list.try_each(input.facts, validate_fact))
  use _ <- result.try(list.try_each(input.rules, validate_rule))
  use _ <- result.try(unique_rules(input.rules))
  let missing =
    list.append(
      [
        "authoritative_rule_acquisition",
        "rule_set_completeness_proof",
        "version_comparison_predicate_explanation_and_correction_lineage",
      ],
      input.missing_capabilities,
    )
    |> list.unique
  use _ <- result.try(
    list.try_each(missing, fn(value) {
      valid_text("missingCapabilities[]", value, 1, 200)
    }),
  )
  let semantic = semantic_json(input, missing)
  let semantic_text = json.to_string(semantic)
  use _ <- result.try(
    case
      string.byte_size(input.operation_id) + string.byte_size(semantic_text)
    {
      total if total <= maximum_payload_bytes -> Ok(Nil)
      _ -> Error(BudgetExceeded("payloadBytes", maximum_payload_bytes))
    },
  )
  let outcomes =
    list.map(input.rules, fn(rule) {
      evaluate_rule(
        rule,
        input.rules,
        input.facts,
        input.as_of_unix_milliseconds,
      )
    })
  use receipt <- result.try(case hash.text(semantic_text) {
    Ok(value) -> Ok(identity.sha256_value(value))
    Error(_) ->
      Error(InvalidField("semanticReceipt", "could not hash evaluation"))
  })
  Ok(Response(
    "Evaluated supplied rules independently; no aggregate legal or execution verdict was produced",
    json.object([
      #("maturity", json.string("track_partial")),
      #("contractVersion", json.string("supplied_rule_evaluation_v1")),
      #("operationId", json.string(input.operation_id)),
      #("track", json.string(input.track)),
      #("accountReference", json.string(input.account_reference)),
      #("asOfUnixMilliseconds", json.int(input.as_of_unix_milliseconds)),
      #("ruleSetContentHash", json.string(input.rule_set_content_hash)),
      #("inputFacts", json.array(input.facts, fact_json)),
      #("suppliedRules", json.array(input.rules, rule_json)),
      #("outcomes", json.array(outcomes, outcome_json)),
      #("semanticReceipt", json.string(receipt)),
      #("missingCapabilities", json.array(missing, json.string)),
      #("aggregateVerdict", json.null()),
      #("legalAuthorityAuthenticated", json.bool(False)),
      #("networkPerformed", json.bool(False)),
      #("executable", json.bool(False)),
    ]),
  ))
}

pub fn summary(value: Response) -> String {
  value.summary
}

pub fn details(value: Response) -> Json {
  value.details
}

pub fn error_message(value: DomainError) -> String {
  case value {
    InvalidField(field, reason) ->
      "Invalid supplied-rule field " <> field <> ": " <> reason
    BudgetExceeded(field, maximum) ->
      "Supplied-rule " <> field <> " exceeds maximum " <> int.to_string(maximum)
  }
}

fn evaluate_rule(
  rule: RuleInput,
  rules: List(RuleInput),
  facts: List(FactInput),
  as_of: Int,
) -> Outcome {
  let matches = list.filter(facts, fn(fact) { fact.name == rule.fact_name })
  let unique_matches = list.unique(matches)
  let duplicate_count = list.length(matches) - list.length(unique_matches)
  let overlapping_versions =
    list.filter(rules, fn(other) {
      other.rule_id == rule.rule_id
      && other.version != rule.version
      && active(other, as_of)
    })
  case active(rule, as_of), overlapping_versions, unique_matches {
    False, _, _ ->
      Outcome(
        rule,
        "NotApplicable",
        "outside supplied effective interval",
        matches,
        duplicate_count,
      )
    True, [_first, ..], _ ->
      Outcome(
        rule,
        "Conflict",
        "multiple supplied versions of this rule are active",
        matches,
        duplicate_count,
      )
    True, [], [] ->
      Outcome(rule, "Unknown", "required fact is missing", [], duplicate_count)
    True, [], [fact] ->
      case fact.state, fact.value {
        "known", Some(value) if value == rule.expected ->
          Outcome(
            rule,
            "True",
            "known fact matches expected boolean",
            matches,
            duplicate_count,
          )
        "known", Some(_) ->
          Outcome(
            rule,
            "False",
            "known fact differs from expected boolean",
            matches,
            duplicate_count,
          )
        "unknown", _ ->
          Outcome(
            rule,
            "Unknown",
            "supplied fact is unknown",
            matches,
            duplicate_count,
          )
        "conflicting", _ ->
          Outcome(
            rule,
            "Conflict",
            "supplied fact is conflicting",
            matches,
            duplicate_count,
          )
        "not_applicable", _ ->
          Outcome(
            rule,
            "NotApplicable",
            "supplied fact is not applicable",
            matches,
            duplicate_count,
          )
        _, _ ->
          Outcome(
            rule,
            "Unknown",
            "supplied fact is unavailable",
            matches,
            duplicate_count,
          )
      }
    True, [], _values ->
      Outcome(
        rule,
        "Conflict",
        "different facts share the required name",
        matches,
        duplicate_count,
      )
  }
}

fn active(rule: RuleInput, as_of: Int) -> Bool {
  let after_start = as_of >= rule.effective_from_unix_milliseconds
  case rule.effective_until_unix_milliseconds {
    None -> after_start
    Some(value) -> after_start && as_of <= value
  }
}

fn validate_fact(value: FactInput) -> Result(Nil, DomainError) {
  use _ <- result.try(valid_text("facts[].name", value.name, 1, 200))
  use _ <- result.try(non_depth_name("facts[].name", value.name))
  use _ <- result.try(non_sensitive_name("facts[].name", value.name))
  use _ <- result.try(valid_hash(
    "facts[].sourceReference",
    value.source_reference,
  ))
  case value.state, value.value {
    "known", Some(_) -> Ok(Nil)
    "known", None ->
      Error(InvalidField("facts[]", "known fact requires boolean value"))
    state, None
      if state == "unknown"
      || state == "unavailable"
      || state == "conflicting"
      || state == "not_applicable"
    -> Ok(Nil)
    _, _ ->
      Error(InvalidField("facts[]", "fact state/value combination is invalid"))
  }
}

fn validate_rule(value: RuleInput) -> Result(Nil, DomainError) {
  use _ <- result.try(valid_text("rules[].ruleId", value.rule_id, 1, 200))
  use _ <- result.try(valid_text("rules[].version", value.version, 1, 100))
  use _ <- result.try(valid_text("rules[].factName", value.fact_name, 1, 200))
  use _ <- result.try(non_depth_name("rules[].factName", value.fact_name))
  use _ <- result.try(non_sensitive_name("rules[].factName", value.fact_name))
  use _ <- result.try(valid_text("rules[].severity", value.severity, 1, 100))
  use _ <- result.try(valid_hash(
    "rules[].authorityReference",
    value.authority_reference,
  ))
  case
    value.effective_from_unix_milliseconds >= 0
    && value.effective_from_unix_milliseconds <= maximum_safe_unix_milliseconds,
    value.effective_until_unix_milliseconds
  {
    False, _ ->
      Error(InvalidField(
        "rules[].effectiveFromUnixMilliseconds",
        "must be non-negative",
      ))
    True, Some(until) if until < value.effective_from_unix_milliseconds ->
      Error(InvalidField(
        "rules[].effectiveUntilUnixMilliseconds",
        "precedes effective start",
      ))
    True, Some(until) if until > maximum_safe_unix_milliseconds ->
      Error(InvalidField(
        "rules[].effectiveUntilUnixMilliseconds",
        "must be a JavaScript-safe integer",
      ))
    True, _ -> Ok(Nil)
  }
}

fn unique_rules(values: List(RuleInput)) -> Result(Nil, DomainError) {
  let keys = list.map(values, fn(value) { #(value.rule_id, value.version) })
  case list.length(keys) == list.length(list.unique(keys)) {
    True -> Ok(Nil)
    False ->
      Error(InvalidField("rules", "rule id and version pairs must be unique"))
  }
}

fn valid_track(value: String) -> Result(Nil, DomainError) {
  case list.contains(["cn", "hk", "us"], value) {
    True -> Ok(Nil)
    False -> Error(InvalidField("track", "must be cn, hk, or us"))
  }
}

fn non_depth_name(
  field_name: String,
  value: String,
) -> Result(Nil, DomainError) {
  case field.is_market_depth_name(value) {
    True ->
      Error(InvalidField(
        field_name,
        "market-depth facts are outside the compliance plugin scope",
      ))
    False -> Ok(Nil)
  }
}

fn non_sensitive_name(
  field_name: String,
  value: String,
) -> Result(Nil, DomainError) {
  case field.is_sensitive_name(value) {
    True ->
      Error(InvalidField(
        field_name,
        "credential, secret, and direct-account identifiers are forbidden",
      ))
    False -> Ok(Nil)
  }
}

fn valid_hash(field: String, value: String) -> Result(Nil, DomainError) {
  case identity.sha256(value) {
    Ok(_) -> Ok(Nil)
    Error(_) -> Error(InvalidField(field, "must be a SHA-256 hex digest"))
  }
}

fn valid_text(
  field: String,
  value: String,
  minimum: Int,
  maximum: Int,
) -> Result(Nil, DomainError) {
  let normalized = string.trim(value)
  case
    string.length(normalized) >= minimum
    && string.length(normalized) <= maximum
    && !field.has_control_characters(value)
    && !field.contains_sensitive_lexeme(value)
  {
    True -> Ok(Nil)
    False ->
      Error(InvalidField(
        field,
        "outside bounded plain-text policy or contains credential-shaped data",
      ))
  }
}

fn semantic_json(input: EvaluationInput, missing: List(String)) -> Json {
  json.object([
    #("contractVersion", json.string("supplied_rule_evaluation_v1")),
    #("track", json.string(input.track)),
    #("accountReference", json.string(input.account_reference)),
    #("asOfUnixMilliseconds", json.int(input.as_of_unix_milliseconds)),
    #("ruleSetContentHash", json.string(input.rule_set_content_hash)),
    #("facts", json.array(input.facts, fact_json)),
    #("rules", json.array(input.rules, rule_json)),
    #("missingCapabilities", json.array(missing, json.string)),
  ])
}

fn within_budget(
  field: String,
  values: List(value),
  maximum: Int,
) -> Result(Nil, DomainError) {
  case list.length(values) <= maximum {
    True -> Ok(Nil)
    False -> Error(BudgetExceeded(field, maximum))
  }
}

fn fact_json(value: FactInput) -> Json {
  json.object([
    #("name", json.string(value.name)),
    #("state", json.string(value.state)),
    #("value", json.nullable(value.value, json.bool)),
    #("sourceReference", json.string(value.source_reference)),
  ])
}

fn rule_json(value: RuleInput) -> Json {
  json.object([
    #("ruleId", json.string(value.rule_id)),
    #("version", json.string(value.version)),
    #(
      "effectiveFromUnixMilliseconds",
      json.int(value.effective_from_unix_milliseconds),
    ),
    #(
      "effectiveUntilUnixMilliseconds",
      json.nullable(value.effective_until_unix_milliseconds, json.int),
    ),
    #("factName", json.string(value.fact_name)),
    #("expected", json.bool(value.expected)),
    #("severity", json.string(value.severity)),
    #("authorityReference", json.string(value.authority_reference)),
  ])
}

fn outcome_json(value: Outcome) -> Json {
  json.object([
    #("ruleId", json.string(value.rule.rule_id)),
    #("version", json.string(value.rule.version)),
    #("state", json.string(value.state)),
    #("reason", json.string(value.reason)),
    #("severity", json.string(value.rule.severity)),
    #("authorityReference", json.string(value.rule.authority_reference)),
    #("matchedFacts", json.array(value.matched_facts, fact_json)),
    #("duplicateFactCount", json.int(value.duplicate_fact_count)),
  ])
}
