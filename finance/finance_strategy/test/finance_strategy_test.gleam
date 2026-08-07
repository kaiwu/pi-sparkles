import finance_core/identifier
import finance_core/source
import finance_core/time
import finance_listing/listing
import finance_provenance/identity
import finance_strategy
import finance_strategy/context_receipt
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

pub fn sector_and_regime_receipt_preserves_source_labels_without_a_verdict_test() {
  let assert Ok(sector) =
    context_receipt.classification(
      "GICS-2023",
      "Technology Hardware, Storage & Peripherals",
      instant(100),
      instant(110),
      timezone(),
      fixture_source("sector-source"),
      root_hash("a"),
    )
  let assert Ok(regime) =
    context_receipt.classification(
      "fixture-provider-v1",
      "source-declared-range-bound",
      instant(100),
      instant(111),
      timezone(),
      fixture_source("regime-source"),
      root_hash("b"),
    )
  let assert Ok(value) =
    context_receipt.sector_regime_receipt(
      listing(),
      context_receipt.Known(sector),
      context_receipt.Known(regime),
      instant(120),
      [root("a"), root("b")],
      ["labels are copied from synthetic acceptance sources"],
    )
  context_receipt.family(value)
  |> should.equal(context_receipt.SectorRegime)
  context_receipt.verify(value) |> should.be_true
  let encoded = context_receipt.encode(value)
  encoded
  |> string.contains("source-declared-range-bound")
  |> should.be_true
  encoded |> string.contains("\"decision\"") |> should.be_false
  encoded |> string.contains("\"score\"") |> should.be_false
  encoded |> string.contains("\"recommendation\"") |> should.be_false
}

pub fn context_information_keeps_unknown_and_conflicting_states_exact_test() {
  let assert Ok(first) =
    context_receipt.classification(
      "provider-a",
      "label-a",
      instant(100),
      instant(110),
      timezone(),
      fixture_source("provider-a"),
      root_hash("a"),
    )
  let assert Ok(second) =
    context_receipt.classification(
      "provider-b",
      "label-b",
      instant(100),
      instant(110),
      timezone(),
      fixture_source("provider-b"),
      root_hash("b"),
    )
  let assert Ok(value) =
    context_receipt.sector_regime_receipt(
      listing(),
      context_receipt.Unknown("sector source was not supplied"),
      context_receipt.Conflicting(
        [first, second],
        "sources retain different labels",
      ),
      instant(120),
      [],
      [],
    )
  let encoded = context_receipt.encode(value)
  encoded |> string.contains("\"state\":\"unknown\"") |> should.be_true
  encoded
  |> string.contains("\"state\":\"conflicting\"")
  |> should.be_true

  context_receipt.sector_regime_receipt(
    listing(),
    context_receipt.Unknown("not supplied"),
    context_receipt.Conflicting([], "no alternatives"),
    instant(120),
    [],
    [],
  )
  |> should.equal(Error(context_receipt.InvalidInformation("regime")))
}

pub fn catalyst_receipt_preserves_query_event_time_and_lineage_test() {
  let assert Ok(event) =
    context_receipt.catalyst_event(
      "fixture-event-1",
      "earnings_calendar",
      "Synthetic scheduled earnings event",
      "source_declared_scheduled",
      context_receipt.Known(instant(200)),
      context_receipt.Unknown("publication time absent from source row"),
      timezone(),
      fixture_source("catalyst-source"),
      root_hash("c"),
      [root_hash("d")],
    )
  let assert Ok(snapshot) =
    context_receipt.catalyst_snapshot(
      "fixture calendar query from 2026-08-07 through 2026-08-31",
      [event],
    )
  let assert Ok(value) =
    context_receipt.catalyst_receipt(
      listing(),
      context_receipt.Known(snapshot),
      instant(210),
      [root("c")],
      ["synthetic source row only"],
    )
  context_receipt.schema(value)
  |> should.equal("finance_strategy/catalyst_observation_receipt")
  let encoded = context_receipt.encode(value)
  encoded |> string.contains("earnings_calendar") |> should.be_true
  encoded |> string.contains("source_declared_scheduled") |> should.be_true
  encoded |> string.contains("publication time absent") |> should.be_true
  encoded |> string.contains("\"impact\"") |> should.be_false
  encoded |> string.contains("\"sentiment\"") |> should.be_false
  context_receipt.verify(value) |> should.be_true
}

pub fn task_time_receipt_reports_exact_clocks_without_timing_labels_test() {
  let assert Ok(after_close) =
    context_receipt.task_time_observation(
      "fixture-after-close",
      "after_close",
      instant(300),
      context_receipt.Known(instant(280)),
      context_receipt.Known(instant(290)),
      instant(301),
      timezone(),
      [root("1")],
    )
  let assert Ok(monitor) =
    context_receipt.task_time_observation(
      "fixture-monitor",
      "monitor",
      instant(500),
      context_receipt.NotObtained("newer observation not supplied"),
      context_receipt.Known(instant(490)),
      instant(501),
      timezone(),
      [root("2")],
    )
  let assert Ok(value) =
    context_receipt.task_time_receipt(listing(), [after_close, monitor], [
      "timestamps are facts for LLM interpretation",
    ])
  let encoded = context_receipt.encode(value)
  encoded |> string.contains("\"requested_at_unix_ms\":300") |> should.be_true
  encoded |> string.contains("newer observation not supplied") |> should.be_true
  encoded |> string.contains("\"fresh\"") |> should.be_false
  encoded |> string.contains("\"stale\"") |> should.be_false
  encoded |> string.contains("\"late\"") |> should.be_false
  context_receipt.verify(value) |> should.be_true

  context_receipt.task_time_receipt(listing(), [], [])
  |> should.equal(Error(context_receipt.EmptyTaskTimes))
}

pub fn universe_candidate_receipt_preserves_point_in_time_source_row_test() {
  let assert Ok(observation) =
    universe_observation(
      "fixture-row-600000",
      "source_declared_included",
      ["source reports all requested fields present"],
      "c",
    )
  let assert Ok(value) =
    context_receipt.universe_candidate_receipt(
      listing(),
      context_receipt.Known(observation),
      instant(230),
      ["one copied source row; not a complete population proof"],
    )
  context_receipt.family(value)
  |> should.equal(context_receipt.UniverseCandidate)
  context_receipt.schema(value)
  |> should.equal("finance_strategy/universe_candidate_observation_receipt")
  let encoded = context_receipt.encode(value)
  encoded |> string.contains("fixture-universe-cn-liquid-v1") |> should.be_true
  encoded |> string.contains("source_declared_included") |> should.be_true
  encoded |> string.contains("\"source_cutoff_unix_ms\":205") |> should.be_true
  encoded |> string.contains("\"rank\"") |> should.be_false
  encoded |> string.contains("\"qualified\"") |> should.be_false
  encoded |> string.contains("\"selected\"") |> should.be_false
  encoded |> string.contains("\"recommendation\"") |> should.be_false
  context_receipt.verify(value) |> should.be_true
}

pub fn universe_candidate_receipt_keeps_exclusion_and_conflict_as_source_data_test() {
  let assert Ok(included) =
    universe_observation(
      "fixture-row-a",
      "source_declared_included",
      ["source label A"],
      "a",
    )
  let assert Ok(excluded) =
    universe_observation(
      "fixture-row-b",
      "source_declared_excluded",
      ["source reports insufficient warmup rows"],
      "b",
    )
  let assert Ok(value) =
    context_receipt.universe_candidate_receipt(
      listing(),
      context_receipt.Conflicting(
        [included, excluded],
        "two supplied source snapshots retain different membership labels",
      ),
      instant(230),
      [],
    )
  let encoded = context_receipt.encode(value)
  encoded |> string.contains("\"state\":\"conflicting\"") |> should.be_true
  encoded |> string.contains("source_declared_excluded") |> should.be_true
  encoded |> string.contains("insufficient warmup rows") |> should.be_true
  encoded |> string.contains("\"decision\"") |> should.be_false
  context_receipt.verify(value) |> should.be_true

  let assert Ok(unknown) =
    context_receipt.universe_candidate_receipt(
      listing(),
      context_receipt.NotObtained(
        "point-in-time universe source was not supplied",
      ),
      instant(230),
      [],
    )
  context_receipt.encode(unknown)
  |> string.contains("point-in-time universe source was not supplied")
  |> should.be_true
}

pub fn universe_candidate_receipt_validates_source_text_without_interpreting_it_test() {
  context_receipt.universe_candidate_observation(
    "fixture-universe-cn-liquid-v1",
    "2026-08-07.1",
    "track=cn; as_of=2026-08-07; source predicate copied exactly",
    "fixture-row-invalid",
    "source_declared_included",
    [" leading whitespace is not canonical"],
    [],
    instant(200),
    instant(205),
    instant(210),
    timezone(),
    fixture_source("universe-source"),
    root_hash("c"),
    root_hash("d"),
    [],
  )
  |> should.equal(
    Error(context_receipt.InvalidText("universe.source_declared_reasons")),
  )

  context_receipt.universe_candidate_receipt(
    listing(),
    context_receipt.Conflicting([], "no source rows"),
    instant(230),
    [],
  )
  |> should.equal(
    Error(context_receipt.InvalidInformation("universe.observation")),
  )
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

fn universe_observation(
  row_id: String,
  membership: String,
  reasons: List(String),
  hash_digit: String,
) -> Result(
  context_receipt.UniverseCandidateObservation,
  context_receipt.ContextError,
) {
  let assert Ok(status) =
    context_receipt.source_field("provider_status", membership)
  context_receipt.universe_candidate_observation(
    "fixture-universe-cn-liquid-v1",
    "2026-08-07.1",
    "track=cn; as_of=2026-08-07; source predicate copied exactly",
    row_id,
    membership,
    reasons,
    [status],
    instant(200),
    instant(205),
    instant(210),
    timezone(),
    fixture_source("universe-source"),
    root_hash(hash_digit),
    root_hash("d"),
    [root(hash_digit)],
  )
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

fn timezone() -> time.Timezone {
  let assert Ok(value) = time.timezone("America/New_York")
  value
}

fn fixture_source(reference: String) -> source.SourceRef {
  let assert Ok(value) =
    source.new("acceptance_fixture", reference, source.Synthetic)
  value
}
