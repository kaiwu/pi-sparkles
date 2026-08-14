import finance_provenance/identity
import finance_track
import gleam/list
import gleam/option.{type Option, None, Some}
import gleeunit
import gleeunit/should
import pi_sparkles_trade_compliance/rule_engine

const hash_a = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

const hash_b = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

const hash_c = "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

pub fn main() {
  gleeunit.main()
}

pub fn compound_all_any_and_negation_return_explanation_trees_test() {
  let expression =
    rule_engine.All(rule_engine.Predicate("account_enabled", True), [
      rule_engine.Any(rule_engine.Predicate("session_open", True), [
        rule_engine.Predicate("manual_override", True),
      ]),
      rule_engine.Negated(rule_engine.Predicate("restricted", True)),
    ])
  let facts = [
    known_fact("account_enabled", True, hash_a),
    known_fact("session_open", True, hash_a),
    known_fact("restricted", False, hash_b),
  ]
  let assert Ok(explanation) = rule_engine.explain_expression(expression, facts)

  rule_engine.explanation_state(explanation)
  |> should.equal(rule_engine.TrueState)
  let assert rule_engine.AllExplanation(rule_engine.TrueState, [_, _, _]) =
    explanation
}

pub fn decisive_false_and_true_do_not_hide_child_explanations_test() {
  let all_expression =
    rule_engine.All(rule_engine.Predicate("disabled", True), [
      rule_engine.Predicate("missing", True),
    ])
  let any_expression =
    rule_engine.Any(rule_engine.Predicate("enabled", True), [
      rule_engine.Predicate("conflicting", True),
    ])
  let facts = [
    known_fact("disabled", False, hash_a),
    known_fact("enabled", True, hash_a),
    conflicting_fact("conflicting"),
  ]
  let assert Ok(all_explanation) =
    rule_engine.explain_expression(all_expression, facts)
  let assert Ok(any_explanation) =
    rule_engine.explain_expression(any_expression, facts)

  rule_engine.explanation_state(all_explanation)
  |> should.equal(rule_engine.FalseState)
  rule_engine.explanation_state(any_explanation)
  |> should.equal(rule_engine.TrueState)
  let assert rule_engine.AllExplanation(_, [_, _]) = all_explanation
  let assert rule_engine.AnyExplanation(_, [_, _]) = any_explanation
}

pub fn missing_and_conflicting_facts_remain_distinct_test() {
  let assert Ok(missing) =
    rule_engine.explain_expression(rule_engine.Predicate("absent", True), [])
  let assert Ok(conflict) =
    rule_engine.explain_expression(rule_engine.Predicate("flag", True), [
      known_fact("flag", True, hash_a),
      known_fact("flag", False, hash_b),
    ])

  rule_engine.explanation_state(missing)
  |> should.equal(rule_engine.UnknownState)
  rule_engine.explanation_state(conflict)
  |> should.equal(rule_engine.ConflictState)
}

pub fn exact_duplicate_facts_are_counted_without_inventing_conflict_test() {
  let fact = known_fact("flag", True, hash_a)
  let assert Ok(explanation) =
    rule_engine.explain_expression(rule_engine.Predicate("flag", True), [
      fact,
      fact,
    ])
  let assert rule_engine.PredicateExplanation(
    _,
    _,
    rule_engine.TrueState,
    _,
    [_, _],
    1,
  ) = explanation
}

pub fn evaluation_retains_track_account_and_unproved_completeness_test() {
  let account = sha(hash_a)
  let rule =
    base_rule_for_track(
      "rule",
      "v1",
      finance_track.Cn,
      account,
      10,
      None,
      [],
      True,
    )
  let set = rule_set([rule])
  let assert Ok(value) =
    rule_engine.evaluate(
      set,
      finance_track.Cn,
      account,
      as_of_unix_milliseconds: 20,
      facts: [known_fact("flag", True, hash_b)],
    )

  rule_engine.evaluation_track(value) |> should.equal(finance_track.Cn)
  rule_engine.evaluation_account_reference(value) |> should.equal(account)
  let assert rule_engine.UnprovedCompleteness(_) =
    rule_engine.evaluation_completeness(value)
  let assert [
    rule_engine.RuleOutcome("rule", "v1", rule_engine.TrueState, _, Some(_)),
  ] = rule_engine.evaluation_outcomes(value)
}

pub fn account_scope_effective_interval_and_overlapping_versions_fail_closed_test() {
  let account = sha(hash_a)
  let other_account = sha(hash_b)
  let scoped = base_rule("scoped", "v1", other_account, 10, None, [], True)
  let expired = base_rule("expired", "v1", account, 1, Some(5), [], True)
  let first = base_rule("overlap", "v1", account, 10, None, [], True)
  let second = base_rule("overlap", "v2", account, 11, None, [], True)
  let set = rule_set([scoped, expired, first, second])
  let assert Ok(value) =
    rule_engine.evaluate(
      set,
      finance_track.Hk,
      account,
      as_of_unix_milliseconds: 20,
      facts: [known_fact("flag", True, hash_c)],
    )
  let outcomes = rule_engine.evaluation_outcomes(value)

  let assert [
    rule_engine.RuleOutcome(
      "scoped",
      _,
      rule_engine.NotApplicableState,
      _,
      None,
    ),
    rule_engine.RuleOutcome(
      "expired",
      _,
      rule_engine.NotApplicableState,
      _,
      None,
    ),
    rule_engine.RuleOutcome("overlap", "v1", rule_engine.ConflictState, _, None),
    rule_engine.RuleOutcome("overlap", "v2", rule_engine.ConflictState, _, None),
  ] = outcomes
}

pub fn rule_track_scope_is_not_relabelled_by_evaluation_test() {
  let account = sha(hash_a)
  let cn_rule =
    base_rule_for_track(
      "cn-only",
      "v1",
      finance_track.Cn,
      account,
      1,
      None,
      [],
      True,
    )
  let assert Ok(value) =
    rule_engine.evaluate(
      rule_set([cn_rule]),
      finance_track.Us,
      account,
      as_of_unix_milliseconds: 20,
      facts: [known_fact("flag", True, hash_b)],
    )
  let assert [
    rule_engine.RuleOutcome(
      "cn-only",
      "v1",
      rule_engine.NotApplicableState,
      "track scope differs",
      None,
    ),
  ] = rule_engine.evaluation_outcomes(value)
}

pub fn version_comparison_retains_changes_and_declared_correction_test() {
  let account = sha(hash_a)
  let before = base_rule("rule", "v1", account, 10, Some(19), [], True)
  let correction = correction("v1")
  let after = base_rule("rule", "v2", account, 20, None, [correction], False)
  let assert Ok(comparison) = rule_engine.compare_versions(before, after)
  let changes = rule_engine.comparison_changes(comparison)

  rule_engine.comparison_rule_id(comparison) |> should.equal("rule")
  rule_engine.comparison_declares_correction_from_before(comparison)
  |> should.be_true
  list.contains(changes, rule_engine.VersionChanged("v1", "v2"))
  |> should.be_true
  list.contains(changes, rule_engine.EffectiveFromChanged(10, 20))
  |> should.be_true
  list.contains(changes, rule_engine.CorrectionLinkAdded("v1"))
  |> should.be_true
  list.any(changes, fn(change) {
    case change {
      rule_engine.ExpressionChanged(_, _) -> True
      _ -> False
    }
  })
  |> should.be_true
}

pub fn correction_lineage_requires_existing_earlier_same_rule_version_test() {
  let account = sha(hash_a)
  let missing =
    base_rule("rule", "v2", account, 20, None, [correction("v1")], True)
  rule_engine.rule_set(
    content_hash: sha(hash_b),
    completeness: rule_engine.UnprovedCompleteness("fixture only"),
    rules: [missing],
  )
  |> should.be_error

  let later = base_rule("rule", "v1", account, 30, None, [], True)
  rule_engine.rule_set(
    content_hash: sha(hash_b),
    completeness: rule_engine.UnprovedCompleteness("fixture only"),
    rules: [later, missing],
  )
  |> should.be_error
}

pub fn depth_market_data_and_credential_shaped_predicates_fail_closed_test() {
  let deeply_nested = nested_negation(21, rule_engine.Predicate("flag", True))
  rule_engine.explain_expression(deeply_nested, []) |> should.be_error
  rule_engine.explain_expression(
    rule_engine.Predicate("best_offer_price", True),
    [],
  )
  |> should.be_error
  rule_engine.explain_expression(
    rule_engine.Predicate("access_token", True),
    [],
  )
  |> should.be_error
}

fn known_fact(name: String, value: Bool, hash: String) -> rule_engine.Fact {
  let assert Ok(fact) =
    rule_engine.fact(
      name: name,
      state: rule_engine.Known(value),
      source_reference: sha(hash),
    )
  fact
}

fn conflicting_fact(name: String) -> rule_engine.Fact {
  let assert Ok(fact) =
    rule_engine.fact(
      name: name,
      state: rule_engine.Conflicting([True, False]),
      source_reference: sha(hash_c),
    )
  fact
}

fn correction(from_version: String) -> rule_engine.Correction {
  let assert Ok(value) =
    rule_engine.correction(
      from_version: from_version,
      authority_reference: sha(hash_c),
      reason: "caller supplied correction lineage",
    )
  value
}

fn base_rule(
  rule_id: String,
  version: String,
  account: identity.Sha256,
  effective_from: Int,
  effective_until: Option(Int),
  corrections: List(rule_engine.Correction),
  expected: Bool,
) -> rule_engine.Rule {
  base_rule_for_track(
    rule_id,
    version,
    finance_track.Hk,
    account,
    effective_from,
    effective_until,
    corrections,
    expected,
  )
}

fn base_rule_for_track(
  rule_id: String,
  version: String,
  track: finance_track.Track,
  account: identity.Sha256,
  effective_from: Int,
  effective_until: Option(Int),
  corrections: List(rule_engine.Correction),
  expected: Bool,
) -> rule_engine.Rule {
  let assert Ok(value) =
    rule_engine.rule(
      rule_id: rule_id,
      version: version,
      track: track,
      jurisdiction: "caller_declared",
      account_scope: account,
      effective_from_unix_milliseconds: effective_from,
      effective_until_unix_milliseconds: effective_until,
      expression: rule_engine.Predicate("flag", expected),
      severity: "caller_high",
      authority_reference: sha(hash_b),
      corrections: corrections,
    )
  value
}

fn rule_set(rules: List(rule_engine.Rule)) -> rule_engine.RuleSet {
  let assert Ok(value) =
    rule_engine.rule_set(
      content_hash: sha(hash_c),
      completeness: rule_engine.UnprovedCompleteness("fixture only"),
      rules: rules,
    )
  value
}

fn nested_negation(
  depth: Int,
  value: rule_engine.Expression,
) -> rule_engine.Expression {
  case depth <= 0 {
    True -> value
    False -> nested_negation(depth - 1, rule_engine.Negated(value))
  }
}

fn sha(value: String) -> identity.Sha256 {
  let assert Ok(value) = identity.sha256(value)
  value
}
