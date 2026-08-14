import finance_broker_review/field
import finance_provenance/identity.{type Sha256}
import finance_track.{type Track}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub type FactState {
  Known(value: Bool)
  Unknown(reason: String)
  Unavailable(reason: String)
  Conflicting(values: List(Bool))
  NotApplicable(reason: String)
}

pub opaque type Fact {
  Fact(name: String, state: FactState, source_reference: Sha256)
}

/// Typed boolean expression. `All` and `Any` are non-empty by construction.
pub type Expression {
  Predicate(fact_name: String, expected: Bool)
  All(first: Expression, rest: List(Expression))
  Any(first: Expression, rest: List(Expression))
  Negated(expression: Expression)
}

pub opaque type Correction {
  Correction(from_version: String, authority_reference: Sha256, reason: String)
}

pub opaque type Rule {
  Rule(
    rule_id: String,
    version: String,
    track: Track,
    jurisdiction: String,
    account_scope: Sha256,
    effective_from_unix_milliseconds: Int,
    effective_until_unix_milliseconds: Option(Int),
    expression: Expression,
    severity: String,
    authority_reference: Sha256,
    corrections: List(Correction),
  )
}

pub type Completeness {
  UnprovedCompleteness(reason: String)
  CallerDeclaredComplete(reason: String)
}

pub opaque type RuleSet {
  RuleSet(content_hash: Sha256, completeness: Completeness, rules: List(Rule))
}

pub type EvaluationState {
  TrueState
  FalseState
  UnknownState
  NotApplicableState
  ConflictState
}

pub type Explanation {
  PredicateExplanation(
    fact_name: String,
    expected: Bool,
    state: EvaluationState,
    reason: String,
    matched_facts: List(Fact),
    exact_duplicate_count: Int,
  )
  AllExplanation(state: EvaluationState, children: List(Explanation))
  AnyExplanation(state: EvaluationState, children: List(Explanation))
  NegatedExplanation(state: EvaluationState, child: Explanation)
}

pub type RuleOutcome {
  RuleOutcome(
    rule_id: String,
    version: String,
    state: EvaluationState,
    reason: String,
    explanation: Option(Explanation),
  )
}

pub opaque type Evaluation {
  Evaluation(
    track: Track,
    account_reference: Sha256,
    as_of_unix_milliseconds: Int,
    rule_set_content_hash: Sha256,
    rule_set_completeness: Completeness,
    outcomes: List(RuleOutcome),
  )
}

pub type VersionChange {
  VersionChanged(before: String, after: String)
  TrackChanged(before: Track, after: Track)
  JurisdictionChanged(before: String, after: String)
  AccountScopeChanged(before: Sha256, after: Sha256)
  EffectiveFromChanged(before: Int, after: Int)
  EffectiveUntilChanged(before: Option(Int), after: Option(Int))
  ExpressionChanged(before: Expression, after: Expression)
  SeverityChanged(before: String, after: String)
  AuthorityChanged(before: Sha256, after: Sha256)
  CorrectionLinkAdded(from_version: String)
  CorrectionLinkRemoved(from_version: String)
  CorrectionLinkChanged(from_version: String)
}

pub opaque type VersionComparison {
  VersionComparison(
    rule_id: String,
    before_version: String,
    after_version: String,
    changes: List(VersionChange),
    correction_from_before_declared: Bool,
  )
}

pub type EngineError {
  InvalidField(field: String, reason: String)
  BudgetExceeded(field: String, maximum: Int)
  DuplicateRule(rule_id: String, version: String)
  MissingCorrectionSource(
    rule_id: String,
    version: String,
    from_version: String,
  )
  InvalidCorrectionOrder(rule_id: String, version: String, from_version: String)
  DifferentRuleIds(before: String, after: String)
  SameVersion(version: String)
}

const maximum_rules = 200

const maximum_facts = 200

const maximum_corrections_per_rule = 50

const maximum_expression_nodes = 500

const maximum_expression_depth = 20

const maximum_safe_unix_milliseconds = 9_007_199_254_740_991

pub fn fact(
  name name: String,
  state state: FactState,
  source_reference source_reference: Sha256,
) -> Result(Fact, EngineError) {
  use _ <- result.try(valid_fact_name("fact.name", name))
  use _ <- result.try(valid_fact_state(state))
  Ok(Fact(name, state, source_reference))
}

pub fn correction(
  from_version from_version: String,
  authority_reference authority_reference: Sha256,
  reason reason: String,
) -> Result(Correction, EngineError) {
  use _ <- result.try(valid_text("correction.fromVersion", from_version, 1, 100))
  use _ <- result.try(valid_text("correction.reason", reason, 1, 500))
  Ok(Correction(from_version, authority_reference, reason))
}

pub fn rule(
  rule_id rule_id: String,
  version version: String,
  track track: Track,
  jurisdiction jurisdiction: String,
  account_scope account_scope: Sha256,
  effective_from_unix_milliseconds effective_from: Int,
  effective_until_unix_milliseconds effective_until: Option(Int),
  expression expression: Expression,
  severity severity: String,
  authority_reference authority_reference: Sha256,
  corrections corrections: List(Correction),
) -> Result(Rule, EngineError) {
  use _ <- result.try(valid_text("rule.ruleId", rule_id, 1, 200))
  use _ <- result.try(valid_text("rule.version", version, 1, 100))
  use _ <- result.try(valid_text("rule.jurisdiction", jurisdiction, 1, 200))
  use _ <- result.try(valid_instant("rule.effectiveFrom", effective_from))
  use _ <- result.try(case effective_until {
    Some(value) if value < effective_from ->
      Error(InvalidField("rule.effectiveUntil", "precedes effective start"))
    Some(value) -> valid_instant("rule.effectiveUntil", value)
    None -> Ok(Nil)
  })
  use _ <- result.try(valid_text("rule.severity", severity, 1, 100))
  use _ <- result.try(within_budget(
    "rule.corrections",
    corrections,
    maximum_corrections_per_rule,
  ))
  use _ <- result.try(unique_correction_sources(corrections))
  use _ <- result.try(valid_expression(expression))
  Ok(Rule(
    rule_id,
    version,
    track,
    jurisdiction,
    account_scope,
    effective_from,
    effective_until,
    expression,
    severity,
    authority_reference,
    corrections,
  ))
}

pub fn rule_set(
  content_hash content_hash: Sha256,
  completeness completeness: Completeness,
  rules rules: List(Rule),
) -> Result(RuleSet, EngineError) {
  use _ <- result.try(valid_completeness(completeness))
  use _ <- result.try(case rules {
    [] -> Error(InvalidField("rules", "at least one rule is required"))
    _ -> within_budget("rules", rules, maximum_rules)
  })
  use _ <- result.try(unique_rules(rules))
  use _ <- result.try(
    list.try_each(rules, fn(rule) { validate_correction_sources(rule, rules) }),
  )
  Ok(RuleSet(content_hash, completeness, rules))
}

pub fn evaluate(
  rule_set: RuleSet,
  track: Track,
  account_reference: Sha256,
  as_of_unix_milliseconds as_of: Int,
  facts facts: List(Fact),
) -> Result(Evaluation, EngineError) {
  use _ <- result.try(valid_instant("asOfUnixMilliseconds", as_of))
  use _ <- result.try(within_budget("facts", facts, maximum_facts))
  let outcomes =
    list.map(rule_set.rules, fn(rule) {
      evaluate_rule(
        rule,
        rule_set.rules,
        track,
        account_reference,
        as_of,
        facts,
      )
    })
  Ok(Evaluation(
    track,
    account_reference,
    as_of,
    rule_set.content_hash,
    rule_set.completeness,
    outcomes,
  ))
}

pub fn explain_expression(
  expression: Expression,
  facts: List(Fact),
) -> Result(Explanation, EngineError) {
  use _ <- result.try(within_budget("facts", facts, maximum_facts))
  use _ <- result.try(valid_expression(expression))
  Ok(evaluate_expression(expression, facts))
}

pub fn compare_versions(
  before: Rule,
  after: Rule,
) -> Result(VersionComparison, EngineError) {
  use _ <- result.try(case before.rule_id == after.rule_id {
    True -> Ok(Nil)
    False -> Error(DifferentRuleIds(before.rule_id, after.rule_id))
  })
  use _ <- result.try(case before.version == after.version {
    True -> Error(SameVersion(before.version))
    False -> Ok(Nil)
  })
  let changes =
    list.flatten([
      changed(before.version, after.version, VersionChanged),
      changed(before.track, after.track, TrackChanged),
      changed(before.jurisdiction, after.jurisdiction, JurisdictionChanged),
      changed(before.account_scope, after.account_scope, AccountScopeChanged),
      changed(
        before.effective_from_unix_milliseconds,
        after.effective_from_unix_milliseconds,
        EffectiveFromChanged,
      ),
      changed(
        before.effective_until_unix_milliseconds,
        after.effective_until_unix_milliseconds,
        EffectiveUntilChanged,
      ),
      changed(before.expression, after.expression, ExpressionChanged),
      changed(before.severity, after.severity, SeverityChanged),
      changed(
        before.authority_reference,
        after.authority_reference,
        AuthorityChanged,
      ),
      correction_changes(before.corrections, after.corrections),
    ])
  Ok(VersionComparison(
    before.rule_id,
    before.version,
    after.version,
    changes,
    list.any(after.corrections, fn(value) {
      value.from_version == before.version
    }),
  ))
}

pub fn evaluation_track(value: Evaluation) -> Track {
  value.track
}

pub fn evaluation_account_reference(value: Evaluation) -> Sha256 {
  value.account_reference
}

pub fn evaluation_as_of_unix_milliseconds(value: Evaluation) -> Int {
  value.as_of_unix_milliseconds
}

pub fn evaluation_rule_set_content_hash(value: Evaluation) -> Sha256 {
  value.rule_set_content_hash
}

pub fn evaluation_completeness(value: Evaluation) -> Completeness {
  value.rule_set_completeness
}

pub fn evaluation_outcomes(value: Evaluation) -> List(RuleOutcome) {
  value.outcomes
}

pub fn explanation_state(value: Explanation) -> EvaluationState {
  case value {
    PredicateExplanation(_, _, state, _, _, _) -> state
    AllExplanation(state, _) -> state
    AnyExplanation(state, _) -> state
    NegatedExplanation(state, _) -> state
  }
}

pub fn comparison_rule_id(value: VersionComparison) -> String {
  value.rule_id
}

pub fn comparison_before_version(value: VersionComparison) -> String {
  value.before_version
}

pub fn comparison_after_version(value: VersionComparison) -> String {
  value.after_version
}

pub fn comparison_changes(value: VersionComparison) -> List(VersionChange) {
  value.changes
}

pub fn comparison_declares_correction_from_before(
  value: VersionComparison,
) -> Bool {
  value.correction_from_before_declared
}

pub fn fact_name(value: Fact) -> String {
  value.name
}

pub fn fact_state(value: Fact) -> FactState {
  value.state
}

pub fn fact_source_reference(value: Fact) -> Sha256 {
  value.source_reference
}

pub fn rule_track(value: Rule) -> Track {
  value.track
}

pub fn error_message(value: EngineError) -> String {
  case value {
    InvalidField(field, reason) ->
      "Invalid private compliance-engine field " <> field <> ": " <> reason
    BudgetExceeded(field, maximum) ->
      "Private compliance-engine "
      <> field
      <> " exceeds maximum "
      <> int.to_string(maximum)
    DuplicateRule(rule_id, version) ->
      "Duplicate compliance rule " <> rule_id <> " version " <> version
    MissingCorrectionSource(rule_id, version, from_version) ->
      "Compliance rule "
      <> rule_id
      <> " version "
      <> version
      <> " references missing correction source "
      <> from_version
    InvalidCorrectionOrder(rule_id, version, from_version) ->
      "Compliance rule "
      <> rule_id
      <> " version "
      <> version
      <> " does not follow correction source "
      <> from_version
    DifferentRuleIds(before, after) ->
      "Cannot compare different compliance rules " <> before <> " and " <> after
    SameVersion(version) ->
      "Cannot compare compliance version " <> version <> " with itself"
  }
}

fn evaluate_rule(
  rule: Rule,
  rules: List(Rule),
  track: Track,
  account_reference: Sha256,
  as_of: Int,
  facts: List(Fact),
) -> RuleOutcome {
  case
    rule.track == track,
    rule.account_scope == account_reference,
    active(rule, as_of)
  {
    False, _, _ ->
      RuleOutcome(
        rule.rule_id,
        rule.version,
        NotApplicableState,
        "track scope differs",
        None,
      )
    True, False, _ ->
      RuleOutcome(
        rule.rule_id,
        rule.version,
        NotApplicableState,
        "account scope differs",
        None,
      )
    True, True, False ->
      RuleOutcome(
        rule.rule_id,
        rule.version,
        NotApplicableState,
        "outside effective interval",
        None,
      )
    True, True, True -> {
      let overlapping =
        list.filter(rules, fn(other) {
          other.rule_id == rule.rule_id
          && other.version != rule.version
          && other.track == track
          && other.account_scope == account_reference
          && active(other, as_of)
        })
      case overlapping {
        [_first, ..] ->
          RuleOutcome(
            rule.rule_id,
            rule.version,
            ConflictState,
            "multiple supplied versions of this rule are active",
            None,
          )
        [] -> {
          let explanation = evaluate_expression(rule.expression, facts)
          RuleOutcome(
            rule.rule_id,
            rule.version,
            explanation_state(explanation),
            "typed expression evaluated; inspect explanation tree",
            Some(explanation),
          )
        }
      }
    }
  }
}

fn evaluate_expression(
  expression: Expression,
  facts: List(Fact),
) -> Explanation {
  case expression {
    Predicate(name, expected) -> evaluate_predicate(name, expected, facts)
    All(first, rest) -> {
      let children =
        [first, ..rest]
        |> list.map(fn(value) { evaluate_expression(value, facts) })
      AllExplanation(all_state(list.map(children, explanation_state)), children)
    }
    Any(first, rest) -> {
      let children =
        [first, ..rest]
        |> list.map(fn(value) { evaluate_expression(value, facts) })
      AnyExplanation(any_state(list.map(children, explanation_state)), children)
    }
    Negated(value) -> {
      let child = evaluate_expression(value, facts)
      NegatedExplanation(negated_state(explanation_state(child)), child)
    }
  }
}

fn evaluate_predicate(
  name: String,
  expected: Bool,
  facts: List(Fact),
) -> Explanation {
  let matching = list.filter(facts, fn(fact) { fact.name == name })
  let unique = list.unique(matching)
  let duplicates = list.length(matching) - list.length(unique)
  let #(state, reason) = case unique {
    [] -> #(UnknownState, "required fact is missing")
    [fact] -> predicate_fact_state(fact.state, expected)
    _ -> #(ConflictState, "different supplied facts share this name")
  }
  PredicateExplanation(name, expected, state, reason, matching, duplicates)
}

fn predicate_fact_state(
  state: FactState,
  expected: Bool,
) -> #(EvaluationState, String) {
  case state {
    Known(value) if value == expected -> #(
      TrueState,
      "known fact matches expected boolean",
    )
    Known(_) -> #(FalseState, "known fact differs from expected boolean")
    Unknown(reason) -> #(UnknownState, "fact is unknown: " <> reason)
    Unavailable(reason) -> #(UnknownState, "fact is unavailable: " <> reason)
    Conflicting(_) -> #(ConflictState, "fact has conflicting values")
    NotApplicable(reason) -> #(
      NotApplicableState,
      "fact is not applicable: " <> reason,
    )
  }
}

fn all_state(states: List(EvaluationState)) -> EvaluationState {
  case list.contains(states, FalseState) {
    True -> FalseState
    False ->
      case list.contains(states, ConflictState) {
        True -> ConflictState
        False ->
          case list.contains(states, UnknownState) {
            True -> UnknownState
            False ->
              case list.contains(states, NotApplicableState) {
                True -> NotApplicableState
                False -> TrueState
              }
          }
      }
  }
}

fn any_state(states: List(EvaluationState)) -> EvaluationState {
  case list.contains(states, TrueState) {
    True -> TrueState
    False ->
      case list.contains(states, ConflictState) {
        True -> ConflictState
        False ->
          case list.contains(states, UnknownState) {
            True -> UnknownState
            False ->
              case list.contains(states, NotApplicableState) {
                True -> NotApplicableState
                False -> FalseState
              }
          }
      }
  }
}

fn negated_state(value: EvaluationState) -> EvaluationState {
  case value {
    TrueState -> FalseState
    FalseState -> TrueState
    UnknownState -> UnknownState
    NotApplicableState -> NotApplicableState
    ConflictState -> ConflictState
  }
}

fn active(rule: Rule, as_of: Int) -> Bool {
  let after_start = as_of >= rule.effective_from_unix_milliseconds
  case rule.effective_until_unix_milliseconds {
    None -> after_start
    Some(value) -> after_start && as_of <= value
  }
}

fn valid_fact_state(value: FactState) -> Result(Nil, EngineError) {
  case value {
    Known(_) -> Ok(Nil)
    Unknown(reason) -> valid_text("fact.state.reason", reason, 1, 500)
    Unavailable(reason) -> valid_text("fact.state.reason", reason, 1, 500)
    NotApplicable(reason) -> valid_text("fact.state.reason", reason, 1, 500)
    Conflicting(values) ->
      case list.unique(values) {
        [_, _] -> Ok(Nil)
        _ ->
          Error(InvalidField(
            "fact.state.conflicting",
            "requires both distinct boolean alternatives",
          ))
      }
  }
}

fn valid_expression(value: Expression) -> Result(Nil, EngineError) {
  use _ <- result.try(
    case expression_node_count(value) <= maximum_expression_nodes {
      True -> Ok(Nil)
      False ->
        BudgetExceeded("expressionNodes", maximum_expression_nodes) |> Error
    },
  )
  use _ <- result.try(case expression_depth(value) <= maximum_expression_depth {
    True -> Ok(Nil)
    False ->
      BudgetExceeded("expressionDepth", maximum_expression_depth) |> Error
  })
  validate_predicate_names(value)
}

fn validate_predicate_names(value: Expression) -> Result(Nil, EngineError) {
  case value {
    Predicate(name, _) -> valid_fact_name("expression.factName", name)
    All(first, rest) | Any(first, rest) ->
      list.try_each([first, ..rest], validate_predicate_names)
    Negated(value) -> validate_predicate_names(value)
  }
}

fn expression_node_count(value: Expression) -> Int {
  case value {
    Predicate(_, _) -> 1
    Negated(value) -> 1 + expression_node_count(value)
    All(first, rest) | Any(first, rest) ->
      1
      + list.fold([first, ..rest], 0, fn(total, value) {
        total + expression_node_count(value)
      })
  }
}

fn expression_depth(value: Expression) -> Int {
  case value {
    Predicate(_, _) -> 1
    Negated(value) -> 1 + expression_depth(value)
    All(first, rest) | Any(first, rest) ->
      1
      + list.fold([first, ..rest], 0, fn(maximum, value) {
        int.max(maximum, expression_depth(value))
      })
  }
}

fn valid_fact_name(
  field_name: String,
  value: String,
) -> Result(Nil, EngineError) {
  use _ <- result.try(valid_text(field_name, value, 1, 200))
  case field.is_market_depth_name(value), field.is_sensitive_name(value) {
    True, _ ->
      Error(InvalidField(field_name, "market-depth facts are outside scope"))
    _, True ->
      Error(InvalidField(field_name, "credential-shaped facts are forbidden"))
    False, False -> Ok(Nil)
  }
}

fn valid_completeness(value: Completeness) -> Result(Nil, EngineError) {
  case value {
    UnprovedCompleteness(reason) | CallerDeclaredComplete(reason) ->
      valid_text("completeness.reason", reason, 1, 500)
  }
}

fn unique_correction_sources(
  values: List(Correction),
) -> Result(Nil, EngineError) {
  let sources = list.map(values, fn(value) { value.from_version })
  case list.length(sources) == list.length(list.unique(sources)) {
    True -> Ok(Nil)
    False ->
      Error(InvalidField(
        "rule.corrections",
        "correction source versions must be unique",
      ))
  }
}

fn unique_rules(values: List(Rule)) -> Result(Nil, EngineError) {
  case values {
    [] -> Ok(Nil)
    [first, ..rest] ->
      case
        list.any(rest, fn(other) {
          other.rule_id == first.rule_id && other.version == first.version
        })
      {
        True -> Error(DuplicateRule(first.rule_id, first.version))
        False -> unique_rules(rest)
      }
  }
}

fn validate_correction_sources(
  rule: Rule,
  rules: List(Rule),
) -> Result(Nil, EngineError) {
  list.try_each(rule.corrections, fn(correction) {
    let matches =
      list.filter(rules, fn(candidate) {
        candidate.rule_id == rule.rule_id
        && candidate.version == correction.from_version
      })
    case matches {
      [] ->
        Error(MissingCorrectionSource(
          rule.rule_id,
          rule.version,
          correction.from_version,
        ))
      [source]
        if source.effective_from_unix_milliseconds
        < rule.effective_from_unix_milliseconds
      -> Ok(Nil)
      [_source] ->
        Error(InvalidCorrectionOrder(
          rule.rule_id,
          rule.version,
          correction.from_version,
        ))
      [_, _, ..] ->
        Error(InvalidField("rule.corrections", "correction source is ambiguous"))
    }
  })
}

fn correction_changes(
  before: List(Correction),
  after: List(Correction),
) -> List(VersionChange) {
  let before_versions = list.map(before, fn(value) { value.from_version })
  let after_versions = list.map(after, fn(value) { value.from_version })
  let removed =
    before_versions
    |> list.filter(fn(value) { !list.contains(after_versions, value) })
    |> list.map(CorrectionLinkRemoved)
  let added =
    after_versions
    |> list.filter(fn(value) { !list.contains(before_versions, value) })
    |> list.map(CorrectionLinkAdded)
  let changed =
    after
    |> list.filter_map(fn(after_value) {
      let before_match =
        list.filter(before, fn(before_value) {
          before_value.from_version == after_value.from_version
        })
      case before_match {
        [before_value] if before_value != after_value ->
          Ok(CorrectionLinkChanged(after_value.from_version))
        _ -> Error(Nil)
      }
    })
  list.flatten([removed, added, changed])
}

fn changed(
  before: value,
  after: value,
  constructor: fn(value, value) -> change,
) -> List(change) {
  case before == after {
    True -> []
    False -> [constructor(before, after)]
  }
}

fn valid_instant(field: String, value: Int) -> Result(Nil, EngineError) {
  case value >= 0 && value <= maximum_safe_unix_milliseconds {
    True -> Ok(Nil)
    False ->
      Error(InvalidField(
        field,
        "must be a non-negative JavaScript-safe integer",
      ))
  }
}

fn within_budget(
  field: String,
  values: List(value),
  maximum: Int,
) -> Result(Nil, EngineError) {
  case list.length(values) <= maximum {
    True -> Ok(Nil)
    False -> Error(BudgetExceeded(field, maximum))
  }
}

fn valid_text(
  field: String,
  value: String,
  minimum: Int,
  maximum: Int,
) -> Result(Nil, EngineError) {
  case
    string.length(value) >= minimum
    && string.length(value) <= maximum
    && string.trim(value) == value
    && !field.has_control_characters(value)
    && !field.contains_sensitive_lexeme(value)
  {
    True -> Ok(Nil)
    False -> Error(InvalidField(field, "outside bounded plain-text policy"))
  }
}
