import finance_provenance/hash
import finance_provenance/identity
import finance_track
import gleam/json.{type Json}
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import pi_sparkles_trade_compliance/advanced_decode as decode
import pi_sparkles_trade_compliance/rule_engine

pub opaque type Response {
  Response(summary: String, details: Json)
}

pub type DomainError {
  InvalidField(field: String, reason: String)
  EngineError(error: rule_engine.EngineError)
}

const maximum_operation_id_bytes = 500

pub fn evaluate(
  input: decode.EvaluationInput,
) -> Result(Response, DomainError) {
  use _ <- result.try(valid_operation(input.operation_id))
  use track <- result.try(parse_track(input.track))
  use account <- result.try(parse_hash(
    "accountReference",
    input.account_reference,
  ))
  use content_hash <- result.try(parse_hash(
    "ruleSetContentHash",
    input.rule_set_content_hash,
  ))
  use completeness <- result.try(parse_completeness(
    input.completeness,
    input.completeness_reason,
  ))
  use facts <- result.try(input.facts |> list.try_map(parse_fact))
  use rules <- result.try(input.rules |> list.try_map(parse_rule))
  use rule_set <- result.try(
    rule_engine.rule_set(content_hash, completeness, rules)
    |> result.map_error(EngineError),
  )
  use evaluation <- result.try(
    rule_engine.evaluate(
      rule_set,
      track,
      account,
      input.as_of_unix_milliseconds,
      facts,
    )
    |> result.map_error(EngineError),
  )
  let projection =
    json.object([
      #("contractVersion", json.string("supplied_rule_evaluation_v2")),
      #("operationId", json.string(input.operation_id)),
      #("track", json.string(finance_track.name(track))),
      #("accountReference", json.string(identity.sha256_value(account))),
      #("asOfUnixMilliseconds", json.int(input.as_of_unix_milliseconds)),
      #("ruleSetContentHash", json.string(identity.sha256_value(content_hash))),
      #("completeness", completeness_json(completeness)),
      #(
        "outcomes",
        json.array(rule_engine.evaluation_outcomes(evaluation), outcome_json),
      ),
    ])
  use receipt <- result.try(receipt(projection))
  Ok(Response(
    "Evaluated supplied typed compliance expressions independently; no aggregate legal or execution verdict was produced",
    common_details(projection, receipt),
  ))
}

pub fn explain(
  input: decode.ExplanationInput,
) -> Result(Response, DomainError) {
  use _ <- result.try(valid_operation(input.operation_id))
  use expression <- result.try(parse_expression(input.expression_nodes))
  use facts <- result.try(input.facts |> list.try_map(parse_fact))
  use explanation <- result.try(
    rule_engine.explain_expression(expression, facts)
    |> result.map_error(EngineError),
  )
  let projection =
    json.object([
      #("contractVersion", json.string("predicate_explanation_v1")),
      #("operationId", json.string(input.operation_id)),
      #("expression", expression_json(expression)),
      #("explanation", explanation_json(explanation)),
    ])
  use receipt <- result.try(receipt(projection))
  Ok(Response(
    "Explained one supplied typed compliance expression without producing an aggregate legal verdict",
    common_details(projection, receipt),
  ))
}

pub fn compare(input: decode.ComparisonInput) -> Result(Response, DomainError) {
  use _ <- result.try(valid_operation(input.operation_id))
  use before <- result.try(parse_rule(input.before))
  use after <- result.try(parse_rule(input.after))
  use content_hash <- result.try(
    json.object([
      #("before", rule_input_json(input.before)),
      #("after", rule_input_json(input.after)),
    ])
    |> receipt,
  )
  use comparison_hash <- result.try(parse_hash(
    "comparisonContentHash",
    content_hash,
  ))
  use _ <- result.try(
    rule_engine.rule_set(
      comparison_hash,
      rule_engine.UnprovedCompleteness(
        "comparison contains exactly two supplied versions",
      ),
      [before, after],
    )
    |> result.map_error(EngineError),
  )
  use comparison <- result.try(
    rule_engine.compare_versions(before, after)
    |> result.map_error(EngineError),
  )
  let projection =
    json.object([
      #("contractVersion", json.string("rule_version_comparison_v1")),
      #("operationId", json.string(input.operation_id)),
      #("ruleId", json.string(rule_engine.comparison_rule_id(comparison))),
      #(
        "beforeVersion",
        json.string(rule_engine.comparison_before_version(comparison)),
      ),
      #(
        "afterVersion",
        json.string(rule_engine.comparison_after_version(comparison)),
      ),
      #(
        "declaresCorrectionFromBefore",
        json.bool(rule_engine.comparison_declares_correction_from_before(
          comparison,
        )),
      ),
      #(
        "changes",
        json.array(rule_engine.comparison_changes(comparison), change_json),
      ),
    ])
  use output_receipt <- result.try(receipt(projection))
  Ok(Response(
    "Compared two supplied versions and retained their declared correction lineage",
    common_details(projection, output_receipt),
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
      "Invalid supplied compliance field " <> field <> ": " <> reason
    EngineError(error) -> rule_engine.error_message(error)
  }
}

fn parse_rule(
  value: decode.RuleInput,
) -> Result(rule_engine.Rule, DomainError) {
  use track <- result.try(parse_track(value.track))
  use account <- result.try(parse_hash(
    "rules[].accountScope",
    value.account_scope,
  ))
  use authority <- result.try(parse_hash(
    "rules[].authorityReference",
    value.authority_reference,
  ))
  use expression <- result.try(parse_expression(value.expression_nodes))
  use corrections <- result.try(
    value.corrections
    |> list.try_map(fn(value) {
      use authority <- result.try(parse_hash(
        "rules[].corrections[].authorityReference",
        value.authority_reference,
      ))
      rule_engine.correction(value.from_version, authority, value.reason)
      |> result.map_error(EngineError)
    }),
  )
  rule_engine.rule(
    value.rule_id,
    value.version,
    track,
    value.jurisdiction,
    account,
    value.effective_from_unix_milliseconds,
    value.effective_until_unix_milliseconds,
    expression,
    value.severity,
    authority,
    corrections,
  )
  |> result.map_error(EngineError)
}

fn parse_fact(
  value: decode.FactInput,
) -> Result(rule_engine.Fact, DomainError) {
  use source <- result.try(parse_hash(
    "facts[].sourceReference",
    value.source_reference,
  ))
  use state <- result.try(
    case value.state, value.value, value.values, value.reason {
      "known", Some(known), [], None -> Ok(rule_engine.Known(known))
      "unknown", None, [], Some(reason) -> Ok(rule_engine.Unknown(reason))
      "unavailable", None, [], Some(reason) ->
        Ok(rule_engine.Unavailable(reason))
      "not_applicable", None, [], Some(reason) ->
        Ok(rule_engine.NotApplicable(reason))
      "conflicting", None, values, None -> Ok(rule_engine.Conflicting(values))
      _, _, _, _ ->
        Error(InvalidField(
          "facts[]",
          "state requires exactly its matching value, values, and reason fields",
        ))
    },
  )
  rule_engine.fact(value.name, state, source) |> result.map_error(EngineError)
}

fn parse_expression(
  nodes: List(decode.ExpressionNodeInput),
) -> Result(rule_engine.Expression, DomainError) {
  use parsed <- result.try(parse_one(nodes))
  case parsed.1 {
    [] -> Ok(parsed.0)
    _ -> Error(InvalidField("expressionNodes", "contains unconsumed nodes"))
  }
}

fn parse_one(
  nodes: List(decode.ExpressionNodeInput),
) -> Result(
  #(rule_engine.Expression, List(decode.ExpressionNodeInput)),
  DomainError,
) {
  case nodes {
    [] -> Error(InvalidField("expressionNodes", "ended before the expression"))
    [node, ..rest] ->
      case node.kind, node.child_count, node.fact_name, node.expected {
        "predicate", 0, Some(name), Some(expected) ->
          Ok(#(rule_engine.Predicate(name, expected), rest))
        "not", 1, None, None -> {
          use child <- result.try(parse_one(rest))
          Ok(#(rule_engine.Negated(child.0), child.1))
        }
        "all", count, None, None if count > 0 -> {
          use children <- result.try(parse_children(rest, count, []))
          let expressions = list.reverse(children.0)
          let assert [first, ..remaining] = expressions
          Ok(#(rule_engine.All(first, remaining), children.1))
        }
        "any", count, None, None if count > 0 -> {
          use children <- result.try(parse_children(rest, count, []))
          let expressions = list.reverse(children.0)
          let assert [first, ..remaining] = expressions
          Ok(#(rule_engine.Any(first, remaining), children.1))
        }
        _, _, _, _ ->
          Error(InvalidField(
            "expressionNodes",
            "predicate/all/any/not fields and childCount do not agree",
          ))
      }
  }
}

fn parse_children(
  nodes: List(decode.ExpressionNodeInput),
  remaining: Int,
  reversed: List(rule_engine.Expression),
) -> Result(
  #(List(rule_engine.Expression), List(decode.ExpressionNodeInput)),
  DomainError,
) {
  case remaining {
    0 -> Ok(#(reversed, nodes))
    _ -> {
      use parsed <- result.try(parse_one(nodes))
      parse_children(parsed.1, remaining - 1, [parsed.0, ..reversed])
    }
  }
}

fn parse_completeness(
  value: String,
  reason: String,
) -> Result(rule_engine.Completeness, DomainError) {
  case value {
    "unproved" -> Ok(rule_engine.UnprovedCompleteness(reason))
    "caller_declared_complete" -> Ok(rule_engine.CallerDeclaredComplete(reason))
    _ ->
      Error(InvalidField(
        "completeness",
        "must be unproved or caller_declared_complete",
      ))
  }
}

fn parse_track(value: String) -> Result(finance_track.Track, DomainError) {
  finance_track.from_name(value)
  |> result.map_error(fn(_) { InvalidField("track", "must be cn, hk, or us") })
}

fn parse_hash(
  field: String,
  value: String,
) -> Result(identity.Sha256, DomainError) {
  identity.sha256(value)
  |> result.map_error(fn(_) {
    InvalidField(field, "must be a SHA-256 hex digest")
  })
}

fn valid_operation(value: String) -> Result(Nil, DomainError) {
  case
    value != ""
    && string.trim(value) == value
    && string.byte_size(value) <= maximum_operation_id_bytes
  {
    True -> Ok(Nil)
    False ->
      Error(InvalidField("operationId", "must be trimmed and at most 500 bytes"))
  }
}

fn receipt(value: Json) -> Result(String, DomainError) {
  case value |> json.to_string |> hash.text {
    Ok(value) -> Ok(identity.sha256_value(value))
    Error(_) ->
      Error(InvalidField(
        "semanticReceipt",
        "could not hash canonical projection",
      ))
  }
}

fn common_details(projection: Json, receipt: String) -> Json {
  json.object([
    #("maturity", json.string("experimental")),
    #("result", projection),
    #("semanticReceipt", json.string(receipt)),
    #("aggregateVerdict", json.null()),
    #(
      "authorityDependency",
      json.object([
        #("mode", json.string("explicit_external_rule_capability")),
        #("requiredAtRuntime", json.bool(True)),
        #("providerBundled", json.bool(False)),
        #("credentialsAcceptedByPlugin", json.bool(False)),
      ]),
    ),
    #("legalAuthorityAuthenticated", json.bool(False)),
    #("networkPerformed", json.bool(False)),
    #("executable", json.bool(False)),
  ])
}

fn completeness_json(value: rule_engine.Completeness) -> Json {
  case value {
    rule_engine.UnprovedCompleteness(reason) ->
      json.object([
        #("state", json.string("unproved")),
        #("reason", json.string(reason)),
      ])
    rule_engine.CallerDeclaredComplete(reason) ->
      json.object([
        #("state", json.string("caller_declared_complete")),
        #("reason", json.string(reason)),
        #("authenticated", json.bool(False)),
      ])
  }
}

fn outcome_json(value: rule_engine.RuleOutcome) -> Json {
  let rule_engine.RuleOutcome(rule_id, version, state, reason, explanation) =
    value
  json.object([
    #("ruleId", json.string(rule_id)),
    #("version", json.string(version)),
    #("state", json.string(state_name(state))),
    #("reason", json.string(reason)),
    #("explanation", json.nullable(explanation, explanation_json)),
  ])
}

fn explanation_json(value: rule_engine.Explanation) -> Json {
  case value {
    rule_engine.PredicateExplanation(
      name,
      expected,
      state,
      reason,
      facts,
      duplicates,
    ) ->
      json.object([
        #("kind", json.string("predicate")),
        #("factName", json.string(name)),
        #("expected", json.bool(expected)),
        #("state", json.string(state_name(state))),
        #("reason", json.string(reason)),
        #("matchedFacts", json.array(facts, fact_json)),
        #("exactDuplicateCount", json.int(duplicates)),
      ])
    rule_engine.AllExplanation(state, children) ->
      compound_explanation("all", state, children)
    rule_engine.AnyExplanation(state, children) ->
      compound_explanation("any", state, children)
    rule_engine.NegatedExplanation(state, child) ->
      json.object([
        #("kind", json.string("not")),
        #("state", json.string(state_name(state))),
        #("child", explanation_json(child)),
      ])
  }
}

fn compound_explanation(
  kind: String,
  state: rule_engine.EvaluationState,
  children: List(rule_engine.Explanation),
) -> Json {
  json.object([
    #("kind", json.string(kind)),
    #("state", json.string(state_name(state))),
    #("children", json.array(children, explanation_json)),
  ])
}

fn fact_json(value: rule_engine.Fact) -> Json {
  json.object([
    #("name", json.string(rule_engine.fact_name(value))),
    #("state", fact_state_json(rule_engine.fact_state(value))),
    #(
      "sourceReference",
      json.string(
        identity.sha256_value(rule_engine.fact_source_reference(value)),
      ),
    ),
  ])
}

fn fact_state_json(value: rule_engine.FactState) -> Json {
  case value {
    rule_engine.Known(value) ->
      json.object([
        #("state", json.string("known")),
        #("value", json.bool(value)),
      ])
    rule_engine.Unknown(reason) -> reason_state("unknown", reason)
    rule_engine.Unavailable(reason) -> reason_state("unavailable", reason)
    rule_engine.NotApplicable(reason) -> reason_state("not_applicable", reason)
    rule_engine.Conflicting(values) ->
      json.object([
        #("state", json.string("conflicting")),
        #("values", json.array(values, json.bool)),
      ])
  }
}

fn reason_state(state: String, reason: String) -> Json {
  json.object([#("state", json.string(state)), #("reason", json.string(reason))])
}

fn state_name(value: rule_engine.EvaluationState) -> String {
  case value {
    rule_engine.TrueState -> "True"
    rule_engine.FalseState -> "False"
    rule_engine.UnknownState -> "Unknown"
    rule_engine.NotApplicableState -> "NotApplicable"
    rule_engine.ConflictState -> "Conflict"
  }
}

fn expression_json(value: rule_engine.Expression) -> Json {
  case value {
    rule_engine.Predicate(name, expected) ->
      json.object([
        #("kind", json.string("predicate")),
        #("factName", json.string(name)),
        #("expected", json.bool(expected)),
      ])
    rule_engine.All(first, rest) ->
      json.object([
        #("kind", json.string("all")),
        #("children", json.array([first, ..rest], expression_json)),
      ])
    rule_engine.Any(first, rest) ->
      json.object([
        #("kind", json.string("any")),
        #("children", json.array([first, ..rest], expression_json)),
      ])
    rule_engine.Negated(child) ->
      json.object([
        #("kind", json.string("not")),
        #("child", expression_json(child)),
      ])
  }
}

fn change_json(value: rule_engine.VersionChange) -> Json {
  case value {
    rule_engine.VersionChanged(before, after) ->
      text_change("version", before, after)
    rule_engine.TrackChanged(before, after) ->
      text_change(
        "track",
        finance_track.name(before),
        finance_track.name(after),
      )
    rule_engine.JurisdictionChanged(before, after) ->
      text_change("jurisdiction", before, after)
    rule_engine.AccountScopeChanged(before, after) ->
      text_change(
        "account_scope",
        identity.sha256_value(before),
        identity.sha256_value(after),
      )
    rule_engine.EffectiveFromChanged(before, after) ->
      int_change("effective_from", before, after)
    rule_engine.EffectiveUntilChanged(before, after) ->
      json.object([
        #("field", json.string("effective_until")),
        #("before", json.nullable(before, json.int)),
        #("after", json.nullable(after, json.int)),
      ])
    rule_engine.ExpressionChanged(before, after) ->
      json.object([
        #("field", json.string("expression")),
        #("before", expression_json(before)),
        #("after", expression_json(after)),
      ])
    rule_engine.SeverityChanged(before, after) ->
      text_change("severity", before, after)
    rule_engine.AuthorityChanged(before, after) ->
      text_change(
        "authority",
        identity.sha256_value(before),
        identity.sha256_value(after),
      )
    rule_engine.CorrectionLinkAdded(version) ->
      link_change("correction_added", version)
    rule_engine.CorrectionLinkRemoved(version) ->
      link_change("correction_removed", version)
    rule_engine.CorrectionLinkChanged(version) ->
      link_change("correction_changed", version)
  }
}

fn text_change(field: String, before: String, after: String) -> Json {
  json.object([
    #("field", json.string(field)),
    #("before", json.string(before)),
    #("after", json.string(after)),
  ])
}

fn int_change(field: String, before: Int, after: Int) -> Json {
  json.object([
    #("field", json.string(field)),
    #("before", json.int(before)),
    #("after", json.int(after)),
  ])
}

fn link_change(field: String, version: String) -> Json {
  json.object([
    #("field", json.string(field)),
    #("fromVersion", json.string(version)),
  ])
}

fn rule_input_json(value: decode.RuleInput) -> Json {
  json.object([
    #("ruleId", json.string(value.rule_id)),
    #("version", json.string(value.version)),
    #("track", json.string(value.track)),
    #("accountScope", json.string(value.account_scope)),
    #("effectiveFrom", json.int(value.effective_from_unix_milliseconds)),
    #("authorityReference", json.string(value.authority_reference)),
  ])
}
