import finance_core/identifier
import finance_core/time
import finance_listing/listing
import finance_provenance/identity
import finance_strategy
import finance_strategy/definition
import finance_strategy/evidence
import finance_strategy/plan
import finance_strategy/receipt
import finance_strategy/rsi_reversal
import finance_strategy/transition
import finance_track
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn package_is_experimental_test() {
  finance_strategy.status() |> should.equal(finance_strategy.Experimental)
}

pub fn rsi_definition_is_versioned_data_not_a_decision_test() {
  let definition = strategy_definition()
  definition.id(definition) |> should.equal(rsi_reversal.strategy_id)
  definition.version(definition) |> should.equal("1.0.0")
  definition.predicates(definition) |> list.length |> should.equal(7)
  definition.setup_requirements(definition)
  |> should.equal([
    definition.ExactIdentity,
    definition.CompletedSession,
    definition.CompletedDailyData,
    definition.AdjustmentProvenance,
    definition.SourceRights,
    definition.Freshness,
  ])
  definition.acceptance_requirements(definition)
  |> should.equal([
    definition.MarketRules,
    definition.RiskPolicy,
    definition.ExecutionCapability,
  ])
  definition.canonical_text(definition)
  |> string.contains("No positive-expectancy claim.")
  |> should.be_true
}

pub fn compact_receipt_exposes_facts_without_trade_decision_test() {
  let packet = packet(required_features(evidence.ObservedTrue))
  receipt.scope_issues(packet) |> should.equal([])
  let facts = receipt.predicate_facts(packet)
  facts |> list.length |> should.equal(7)
  let assert [first, ..] = facts
  first.compatibility |> should.equal(receipt.Compatible)
  let assert [first_receipt] = first.receipts
  evidence.observation(first_receipt)
  |> should.equal(evidence.ObservedTrue)

  let encoded = receipt.encode(packet)
  encoded |> string.contains("\"decision\"") |> should.be_false
  encoded |> string.contains("qualified") |> should.be_false
  encoded |> string.contains("accepted") |> should.be_false
  encoded |> string.contains("rejected") |> should.be_false
}

pub fn false_predicate_remains_a_source_fact_test() {
  let features = required_features(evidence.ObservedTrue)
  let assert [first, ..rest] = features
  let changed =
    make_feature(
      evidence.predicate_id(first),
      evidence.feature_id(first),
      False,
      evidence.ObservedFalse,
      evidence.WarmupComplete(250, 200),
      180,
      190,
      "9",
    )
  let packet = packet([changed, ..rest])
  let assert [fact, ..] = receipt.predicate_facts(packet)
  fact.compatibility |> should.equal(receipt.Compatible)
  let assert [source] = fact.receipts
  evidence.observation(source) |> should.equal(evidence.ObservedFalse)
  receipt.encode(packet) |> string.contains("\"decision\"") |> should.be_false
}

pub fn readiness_timing_warmup_and_optional_absence_stay_distinct_test() {
  let features = required_features(evidence.ObservedTrue)
  let assert [first, second, ..rest] = features
  let incomplete =
    make_feature(
      evidence.predicate_id(first),
      evidence.feature_id(first),
      False,
      evidence.Unknown("warmup_not_complete"),
      evidence.WarmupIncomplete(40, 200),
      180,
      190,
      "8",
    )
  let stale =
    make_feature_with_readiness(
      evidence.predicate_id(second),
      evidence.feature_id(second),
      True,
      evidence.ObservedTrue,
      evidence.WarmupComplete(250, 200),
      180,
      190,
      evidence.Stale("outside_daily_freshness_policy"),
      "7",
    )
  let packet = packet([incomplete, stale, ..rest])
  let assert [first_fact, second_fact, _, _, _, optional, ranking] =
    receipt.predicate_facts(packet)
  first_fact.compatibility
  |> should.equal(receipt.WarmupUnavailable(40, 200))
  second_fact.compatibility
  |> should.equal(
    receipt.UpstreamReadiness(evidence.Stale("outside_daily_freshness_policy")),
  )
  optional.compatibility |> should.equal(receipt.MissingReceipt)
  ranking.compatibility |> should.equal(receipt.MissingReceipt)
}

pub fn caller_declarations_never_become_verified_dependencies_test() {
  evidence.dependency_receipt(
    definition.RiskPolicy,
    evidence.Declared("llm_has_not_requested_account_context"),
    None,
    [],
  )
  |> should.be_ok

  let assert Error(error) =
    evidence.dependency_receipt(definition.RiskPolicy, evidence.Ready, None, [])
  error |> should.equal(evidence.ReadyRequiresKnownAt)

  evidence.dependency_receipt(
    definition.RiskPolicy,
    evidence.Declared("caller_statement"),
    None,
    [root("9")],
  )
  |> should.equal(Error(evidence.ReadyCannotBeDeclaration))

  let packet = packet(required_features(evidence.ObservedTrue))
  let assert [rules, risk, execution] = receipt.acceptance_dependencies(packet)
  rules.compatibility
  |> should.equal(
    receipt.UpstreamReadiness(evidence.Declared(
      "market_rule_contract_not_supplied",
    )),
  )
  risk.compatibility
  |> should.equal(
    receipt.UpstreamReadiness(evidence.Declared("risk_contract_not_supplied")),
  )
  execution.compatibility
  |> should.equal(
    receipt.UpstreamReadiness(evidence.Declared(
      "execution_contract_not_supplied",
    )),
  )
}

pub fn late_dependency_is_visible_without_becoming_a_decision_test() {
  let dependencies = setup_dependencies()
  let late = ready_dependency(definition.Freshness, "f", 220)
  let replaced = [
    late,
    ..list.filter(dependencies, fn(value) {
      evidence.dependency_requirement(value) != definition.Freshness
    })
  ]
  let packet =
    packet_with_context(
      context(replaced, 200, 300),
      required_features(evidence.ObservedTrue),
    )
  let freshness =
    packet
    |> receipt.setup_dependencies
    |> list.find(fn(value) { value.requirement == definition.Freshness })
  freshness
  |> should.equal(
    Ok(receipt.DependencyFact(
      definition.Freshness,
      receipt.KnownAfterCutoff(220, 200),
      Some(late),
    )),
  )
}

pub fn evidence_receipt_round_trips_exact_context_and_roots_test() {
  let original = packet(required_features(evidence.ObservedTrue))
  let encoded = receipt.encode(original)
  let assert Ok(decoded) = receipt.decode(encoded)
  decoded |> should.equal(original)
  receipt.encode(decoded) |> should.equal(encoded)

  let tampered_hash =
    encoded
    |> string.replace(
      identity.sha256_value(receipt.input_hash(original)),
      string.repeat("9", 64),
    )
  receipt.decode(tampered_hash) |> should.be_error

  let tampered_compatibility =
    encoded
    |> string.replace(
      "\"state\":\"compatible\"",
      "\"state\":\"missing_receipt\"",
    )
  receipt.decode(tampered_compatibility) |> should.be_error

  receipt.evidence_roots(decoded)
  |> list.map(identity.evidence_id_value)
  |> should.equal([
    string.repeat("0", 64),
    string.repeat("a", 64),
    string.repeat("b", 64),
    string.repeat("c", 64),
    string.repeat("d", 64),
    string.repeat("e", 64),
    string.repeat("f", 64),
    string.repeat("1", 64),
    string.repeat("2", 64),
    string.repeat("3", 64),
    string.repeat("4", 64),
    string.repeat("5", 64),
  ])
}

pub fn definition_and_input_hashes_are_deterministic_and_sensitive_test() {
  let first_definition = strategy_definition()
  let second_definition = strategy_definition()
  definition.digest(first_definition)
  |> should.equal(definition.digest(second_definition))

  let first = packet(required_features(evidence.ObservedTrue))
  let second = packet(required_features(evidence.ObservedTrue))
  receipt.input_hash(first) |> should.equal(receipt.input_hash(second))

  let assert [first_feature, ..rest] = required_features(evidence.ObservedTrue)
  let changed =
    make_feature(
      evidence.predicate_id(first_feature),
      evidence.feature_id(first_feature),
      False,
      evidence.ObservedFalse,
      evidence.WarmupComplete(250, 200),
      180,
      190,
      "9",
    )
  receipt.input_hash(packet([changed, ..rest]))
  |> should.not_equal(receipt.input_hash(first))
}

pub fn plan_is_an_llm_declaration_not_an_execution_acceptance_test() {
  let declaration = desired_plan()
  plan.origin(declaration) |> should.equal(plan.LlmProposed)
  plan.price_raw(plan.entry_ceiling(declaration)) |> should.equal("101.25")
  plan.price_raw(plan.desired_stop(declaration)) |> should.equal("95.00")
  plan.price_raw(plan.target(declaration)) |> should.equal("113.75")
  plan.exact_price("0") |> should.equal(Error(plan.NonPositivePrice))
  let assert Ok(too_high_stop) = plan.exact_price("102")
  plan.declare(
    plan.LlmProposed,
    listing(),
    receipt.definition_hash(packet(required_features(evidence.ObservedTrue))),
    instant(310),
    civil(2026, 8, 7),
    civil(2026, 8, 10),
    price("101.25"),
    too_high_stop,
    price("113.75"),
    "tighter_of_volatility_and_structure",
    "completed_daily_close",
    [],
  )
  |> should.equal(Error(plan.InvalidLongPriceShape))
}

pub fn transition_fold_rejects_fill_before_plan_and_preserves_history_test() {
  let packet = packet(required_features(evidence.ObservedTrue))
  let history = transition.start(packet)
  let observed_entry =
    workflow_event(
      320,
      transition.EntryPriceObserved(
        civil(2026, 8, 7),
        price("100.50"),
        transition.ImportedRecord,
      ),
      "6",
    )
  transition.apply(history, observed_entry)
  |> should.equal(Error(transition.IllegalEvent(transition.EvidencePrepared)))

  let attached =
    workflow_event(315, transition.PlanAttached(desired_plan()), "")
  let assert Ok(planned) = transition.apply(history, attached)
  transition.phase(planned) |> should.equal(transition.EntryWindowOpen)
  let assert Ok(entered) = transition.apply(planned, observed_entry)
  transition.phase(entered) |> should.equal(transition.PositionObserved)

  let ambiguity =
    workflow_event(
      330,
      transition.DailyExitOrderingUnknown(
        civil(2026, 8, 8),
        price("94.50"),
        price("114.00"),
      ),
      "7",
    )
  let assert Ok(ambiguous) = transition.apply(entered, ambiguity)
  transition.phase(ambiguous) |> should.equal(transition.PositionObserved)

  let exit =
    workflow_event(
      340,
      transition.ExitPriceObserved(
        civil(2026, 8, 9),
        price("93.80"),
        transition.GapThroughDesiredStop,
        transition.ProviderReported,
      ),
      "8",
    )
  let assert Ok(closed) = transition.apply(ambiguous, exit)
  transition.phase(closed) |> should.equal(transition.ExitObserved)
  transition.events(closed) |> list.length |> should.equal(4)
  transition.strategy_evidence(closed) |> should.equal(packet)
}

pub fn expiry_and_review_are_history_facts_not_strategy_decisions_test() {
  let history =
    transition.start(packet(required_features(evidence.ObservedTrue)))
  let assert Ok(planned) =
    transition.apply(
      history,
      workflow_event(315, transition.PlanAttached(desired_plan()), ""),
    )
  let assert Ok(expired) =
    transition.apply(
      planned,
      workflow_event(
        350,
        transition.EntryWindowExpired(civil(2026, 8, 10)),
        "6",
      ),
    )
  transition.phase(expired)
  |> should.equal(transition.EntryWindowExpiredPhase)
  let assert Ok(reviewed) =
    transition.apply(
      expired,
      workflow_event(
        360,
        transition.ReviewAttached(
          plan.LlmProposed,
          "No entry price was observed inside the declared window.",
        ),
        "",
      ),
    )
  transition.phase(reviewed) |> should.equal(transition.Reviewed)
}

pub fn transition_rejects_context_and_time_rewrites_test() {
  let history =
    transition.start(packet(required_features(evidence.ObservedTrue)))
  let wrong_hash_event =
    event_for(
      listing(),
      root_hash("9"),
      315,
      transition.PlanAttached(desired_plan()),
      [],
    )
  transition.apply(history, wrong_hash_event)
  |> should.equal(Error(transition.DefinitionMismatch))

  let backward =
    workflow_event(299, transition.PlanAttached(desired_plan()), "")
  transition.apply(history, backward)
  |> should.equal(Error(transition.BackwardTimestamp))
}

fn packet(
  features: List(evidence.FeatureReceipt),
) -> receipt.StrategyEvidenceReceipt {
  packet_with_context(context(all_dependencies(), 200, 300), features)
}

fn packet_with_context(
  context: evidence.EvaluationContext,
  features: List(evidence.FeatureReceipt),
) -> receipt.StrategyEvidenceReceipt {
  receipt.build(strategy_definition(), context, features)
}

fn strategy_definition() -> definition.Definition {
  let assert Ok(value) = rsi_reversal.v1(civil(2026, 1, 1), None)
  value
}

fn context(
  dependencies: List(evidence.DependencyReceipt),
  cutoff: Int,
  evaluated: Int,
) -> evidence.EvaluationContext {
  let assert Ok(value) =
    evidence.evaluation_context(
      listing(),
      civil(2026, 8, 6),
      instant(evaluated),
      instant(cutoff),
      dependencies,
      [root("0")],
    )
  value
}

fn all_dependencies() -> List(evidence.DependencyReceipt) {
  list.append(setup_dependencies(), [
    declared_dependency(
      definition.MarketRules,
      "market_rule_contract_not_supplied",
    ),
    declared_dependency(definition.RiskPolicy, "risk_contract_not_supplied"),
    declared_dependency(
      definition.ExecutionCapability,
      "execution_contract_not_supplied",
    ),
  ])
}

fn setup_dependencies() -> List(evidence.DependencyReceipt) {
  [
    ready_dependency(definition.ExactIdentity, "a", 150),
    ready_dependency(definition.CompletedSession, "b", 151),
    ready_dependency(definition.CompletedDailyData, "c", 152),
    ready_dependency(definition.AdjustmentProvenance, "d", 153),
    ready_dependency(definition.SourceRights, "e", 154),
    ready_dependency(definition.Freshness, "f", 155),
  ]
}

fn ready_dependency(
  requirement: definition.Requirement,
  digit: String,
  known_at: Int,
) -> evidence.DependencyReceipt {
  let assert Ok(value) =
    evidence.dependency_receipt(
      requirement,
      evidence.Ready,
      Some(instant(known_at)),
      [root(digit)],
    )
  value
}

fn declared_dependency(
  requirement: definition.Requirement,
  declaration: String,
) -> evidence.DependencyReceipt {
  let assert Ok(value) =
    evidence.dependency_receipt(
      requirement,
      evidence.Declared(declaration),
      None,
      [],
    )
  value
}

fn required_features(
  observation: evidence.PredicateObservation,
) -> List(evidence.FeatureReceipt) {
  [
    make_feature(
      "eligible_liquid_universe",
      "universe_eligibility_v1",
      False,
      observation,
      evidence.WarmupComplete(1, 1),
      180,
      190,
      "1",
    ),
    make_feature(
      "close_above_long_ma",
      "sma_200_v1",
      True,
      observation,
      evidence.WarmupComplete(250, 200),
      180,
      190,
      "2",
    ),
    make_feature(
      "rsi_at_or_below_threshold",
      "rsi_14_v1",
      True,
      observation,
      evidence.WarmupComplete(250, 15),
      180,
      190,
      "3",
    ),
    make_feature(
      "rsi_strictly_rising",
      "rsi_14_prior_comparison_v1",
      True,
      observation,
      evidence.WarmupComplete(250, 16),
      180,
      190,
      "4",
    ),
    make_feature(
      "close_near_medium_ma",
      "sma_50_distance_v1",
      True,
      observation,
      evidence.WarmupComplete(250, 50),
      180,
      190,
      "5",
    ),
  ]
}

fn make_feature(
  predicate_id: String,
  feature_id: String,
  price_dependent: Bool,
  observation: evidence.PredicateObservation,
  warmup: evidence.Warmup,
  known_at: Int,
  source_cutoff: Int,
  digit: String,
) -> evidence.FeatureReceipt {
  make_feature_with_readiness(
    predicate_id,
    feature_id,
    price_dependent,
    observation,
    warmup,
    known_at,
    source_cutoff,
    evidence.Ready,
    digit,
  )
}

fn make_feature_with_readiness(
  predicate_id: String,
  feature_id: String,
  price_dependent: Bool,
  observation: evidence.PredicateObservation,
  warmup: evidence.Warmup,
  known_at: Int,
  source_cutoff: Int,
  readiness: evidence.Readiness,
  digit: String,
) -> evidence.FeatureReceipt {
  let price_dependency = case price_dependent {
    True -> evidence.PriceDependent("split_adjusted:authority_factors_v1")
    False -> evidence.NotPriceDependent
  }
  let assert Ok(value) =
    evidence.feature_receipt(
      predicate_id,
      feature_id,
      "1.0.0",
      [],
      warmup,
      root_hash(digit),
      listing(),
      civil(2026, 8, 6),
      price_dependency,
      "scalar",
      instant(known_at),
      instant(source_cutoff),
      readiness,
      observation,
      [root(digit)],
    )
  value
}

fn desired_plan() -> plan.PlanDeclaration {
  let assert Ok(value) =
    plan.declare(
      plan.LlmProposed,
      listing(),
      receipt.definition_hash(packet(required_features(evidence.ObservedTrue))),
      instant(310),
      civil(2026, 8, 7),
      civil(2026, 8, 10),
      price("101.25"),
      price("95.00"),
      price("113.75"),
      "tighter_of_volatility_and_structure",
      "completed_daily_close",
      [],
    )
  value
}

fn workflow_event(
  at: Int,
  kind: transition.WorkflowEventKind,
  root_digit: String,
) -> transition.WorkflowEvent {
  let roots = case root_digit {
    "" -> []
    value -> [root(value)]
  }
  event_for(
    listing(),
    receipt.definition_hash(packet(required_features(evidence.ObservedTrue))),
    at,
    kind,
    roots,
  )
}

fn event_for(
  listing: listing.Key,
  definition_hash: identity.Sha256,
  at: Int,
  kind: transition.WorkflowEventKind,
  roots: List(identity.EvidenceId),
) -> transition.WorkflowEvent {
  let assert Ok(value) =
    transition.event(listing, definition_hash, instant(at), kind, roots)
  value
}

fn listing() -> listing.Key {
  let assert Ok(instrument_id) = identifier.instrument_id("fixture:us:aapl")
  let assert Ok(symbol) = identifier.symbol("AAPL")
  let assert Ok(mic) = identifier.mic("XNAS")
  listing.new(finance_track.Us, instrument_id, symbol, mic)
}

fn price(value: String) -> plan.ExactPrice {
  let assert Ok(value) = plan.exact_price(value)
  value
}

fn root(digit: String) -> identity.EvidenceId {
  digit |> root_hash |> identity.evidence_id
}

fn root_hash(digit: String) -> identity.Sha256 {
  let assert Ok(value) = identity.sha256(string.repeat(digit, 64))
  value
}

fn civil(year: Int, month: Int, day: Int) -> time.Date {
  let assert Ok(value) = time.date(year, month, day)
  value
}

fn instant(milliseconds: Int) -> time.Instant {
  let assert Ok(value) = time.instant(milliseconds)
  value
}
