import finance_core/time
import finance_provenance/hash
import finance_provenance/identity
import finance_replay/definition
import finance_replay/fact
import gleam/dynamic/decode as dynamic_decode
import gleam/json
import gleam/option.{None, Some}
import gleam/string
import gleeunit
import gleeunit/should
import pi_sparkles_quant_research/decode
import pi_sparkles_quant_research/domain

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn ledger_retains_all_seven_states_and_pages_stably_test() {
  let events = [
    ledger_event("completed", completed()),
    ledger_event("failed", failed("division by zero")),
    ledger_event("cancelled", cancelled(35, "user")),
    ledger_event("truncated", truncated("event budget")),
    ledger_event("duplicate", duplicate_of("trial-completed")),
    ledger_event("unperformed", unperformed("missing source receipt")),
    ledger_event("completed-2", completed()),
  ]
  let counts = decode.ExpectedCounts(7, 2, 1, 1, 1, 1, 1)
  let first = inspect_input(events, counts, 0, 2)
  let second = decode.InspectInput(..first, offset: 2)
  let assert Ok(first_response) = domain.inspect_trial_ledger(first)
  let assert Ok(second_response) = domain.inspect_trial_ledger(second)
  let first_text = json.to_string(first_response.details)
  let second_text = json.to_string(second_response.details)

  first_text
  |> string.contains(
    "\"counts\":{\"total\":7,\"completed\":2,\"failed\":1,\"cancelled\":1,\"truncated\":1,\"duplicate\":1,\"unperformed\":1}",
  )
  |> should.be_true
  first_text |> string.contains("\"returnedCount\":2") |> should.be_true
  first_text |> string.contains("\"nextOffset\":2") |> should.be_true
  first_text
  |> string.contains("\"trialId\":\"trial-completed\"")
  |> should.be_true
  first_text
  |> string.contains("\"trialId\":\"trial-failed\"")
  |> should.be_true
  first_text |> string.contains("trial-cancelled") |> should.be_false
  first_text |> string.contains("\"text\":null") |> should.be_true
  first_text |> string.contains("\"textOmitted\":true") |> should.be_true
  first_text |> string.contains("\"eventEnvelope\":null") |> should.be_true
  first_text
  |> string.contains(
    "caller_declaration_cannot_prove_external_events_were_not_omitted",
  )
  |> should.be_true

  let assert Ok(first_cursor) =
    json.parse(first_text, {
      use value <- dynamic_decode.field("ledgerCursor", dynamic_decode.string)
      dynamic_decode.success(value)
    })
  let assert Ok(second_cursor) =
    json.parse(second_text, {
      use value <- dynamic_decode.field("ledgerCursor", dynamic_decode.string)
      dynamic_decode.success(value)
    })
  first_cursor |> should.equal(second_cursor)
}

pub fn explicit_payload_flags_reveal_exact_hypothesis_and_trial_envelopes_test() {
  let value =
    inspect_input(
      [ledger_event("completed", completed())],
      decode.ExpectedCounts(1, 1, 0, 0, 0, 0, 0),
      0,
      10,
    )
  let input =
    decode.InspectInput(
      ..value,
      include_hypothesis_text: True,
      include_trial_payloads: True,
    )
  let assert Ok(response) = domain.inspect_trial_ledger(input)
  let text = json.to_string(response.details)
  text
  |> string.contains("\"text\":\"Exact fixture hypothesis\"")
  |> should.be_true
  text |> string.contains("\"textOmitted\":false") |> should.be_true
  text
  |> string.contains("\"schema\":\"finance_replay_trial_ledger_event\"")
  |> should.be_true
  text
  |> string.contains("\"trial_event\":{\"trial_definition_hash\":")
  |> should.be_true
}

pub fn ledger_counts_hashes_and_idempotency_conflicts_fail_exactly_test() {
  let one = ledger_event("completed", completed())
  let mismatched =
    inspect_input([one], decode.ExpectedCounts(1, 0, 1, 0, 0, 0, 0), 0, 10)
  domain.inspect_trial_ledger(mismatched)
  |> should.equal(Error(domain.LedgerCountsMismatch))

  let base_hypothesis = hypothesis()
  let wrong_hypothesis =
    decode.HypothesisInput(
      ..base_hypothesis,
      content_hash: sha_text("wrong-hypothesis"),
    )
  let bad_hash_input =
    decode.InspectInput(..mismatched, hypothesis: wrong_hypothesis)
  case domain.inspect_trial_ledger(bad_hash_input) {
    Error(domain.HypothesisHashMismatch(_, _)) -> Nil
    _ -> should.fail()
  }

  let retry = decode.LedgerEventInput(..one, ledger_event_id: "event-retry")
  let retry_input =
    inspect_input(
      [one, retry],
      decode.ExpectedCounts(1, 1, 0, 0, 0, 0, 0),
      0,
      10,
    )
  let assert Ok(retry_response) = domain.inspect_trial_ledger(retry_input)
  json.to_string(retry_response.details)
  |> string.contains("\"idempotentRetryCount\":1")
  |> should.be_true

  let conflict =
    decode.LedgerEventInput(
      ..one,
      ledger_event_id: "event-conflict",
      status: failed("changed outcome"),
    )
  case
    domain.inspect_trial_ledger(
      decode.InspectInput(..retry_input, events: [one, conflict]),
    )
  {
    Error(domain.LedgerFailure(_)) -> Nil
    _ -> should.fail()
  }
}

pub fn net_return_calculates_exactly_and_preserves_unperformed_unknown_test() {
  let metadata = metric_metadata("metric-net", "(ending-start)/start", 4)
  let denominator =
    decode.DecimalInput("starting_equity", "100.00", sha_text("starting"))
  let ending =
    decode.DecimalInput("ending_equity", "120.00", sha_text("ending"))
  let assert Ok(calculated) =
    domain.request_metric(decode.MetricInput(
      metadata,
      decode.NetReturn(fact.Known(denominator), fact.Known(ending)),
    ))
  let calculated_text = json.to_string(calculated.details)
  calculated_text
  |> string.contains("\"metricKind\":\"net_return\"")
  |> should.be_true
  calculated_text
  |> string.contains("\"exact_decimal\":\"0.2\"")
  |> should.be_true
  calculated_text
  |> string.contains("\"ordered_inputs\":[{\"name\":\"starting_equity\"")
  |> should.be_true

  let assert Ok(unperformed_response) =
    domain.request_metric(decode.MetricInput(
      metadata,
      decode.NetReturn(
        fact.Unknown("starting equity unavailable"),
        fact.Known(ending),
      ),
    ))
  let unperformed_text = json.to_string(unperformed_response.details)
  unperformed_text
  |> string.contains("\"state\":\"unperformed\"")
  |> should.be_true
  unperformed_text
  |> string.contains("one or more requested net-return operands are not known")
  |> should.be_true
}

pub fn requested_counts_drawdown_and_trade_list_use_exact_core_variants_test() {
  let receipts = [sha_text("trade-1"), sha_text("trade-2"), sha_text("trade-3")]
  let assert [one, two, three] = receipts
  let assert Ok(counts_response) =
    domain.request_metric(decode.MetricInput(
      metric_metadata("metric-counts", "count(sign(net_pnl))", 4),
      decode.WinLossCounts(
        [
          decode.TradePnlInput("trade-1", "2.5", one),
          decode.TradePnlInput("trade-2", "-1.0", two),
          decode.TradePnlInput("trade-3", "0", three),
        ],
        "zero_is_tie_v1",
      ),
    ))
  json.to_string(counts_response.details)
  |> string.contains("\"win\":1,\"loss\":1,\"tie\":1")
  |> should.be_true

  let assert Ok(drawdown_response) =
    domain.request_metric(decode.MetricInput(
      metric_metadata("metric-dd", "(peak-equity)/peak", 4),
      decode.DrawdownSeries(
        [
          decode.EquityPointInput(
            "day-1",
            decode.DecimalInput("equity-1", "100", one),
          ),
          decode.EquityPointInput(
            "day-2",
            decode.DecimalInput("equity-2", "80", two),
          ),
          decode.EquityPointInput(
            "day-3",
            decode.DecimalInput("equity-3", "120", three),
          ),
        ],
        "running_peak_inclusive_v1",
      ),
    ))
  let drawdown_text = json.to_string(drawdown_response.details)
  drawdown_text |> string.contains("\"label\":\"day-2\"") |> should.be_true
  drawdown_text |> string.contains("\"drawdown\":\"0.2\"") |> should.be_true

  let assert Ok(trades_response) =
    domain.request_metric(decode.MetricInput(
      metric_metadata("metric-trades", "identity(trades)", 0),
      decode.TradeList([
        decode.TradeInput(
          "trade-1",
          sha_text("instruction"),
          [sha_text("fill"), sha_text("exit")],
          "{\"side\":\"long\",\"netPnl\":\"2.5\"}",
        ),
      ]),
    ))
  let trades_text = json.to_string(trades_response.details)
  trades_text
  |> string.contains("\"metricKind\":\"trade_list\"")
  |> should.be_true
  trades_text |> string.contains("\"trade_id\":\"trade-1\"") |> should.be_true
  trades_text
  |> string.contains(
    "\"exact_payload\":\"{\\\"side\\\":\\\"long\\\",\\\"netPnl\\\":\\\"2.5\\\"}\"",
  )
  |> should.be_true
}

pub fn malformed_metric_inputs_fail_without_discarding_other_tool_contracts_test() {
  let malformed =
    decode.DecimalInput("starting_equity", "not-a-decimal", sha_text("source"))
  case
    domain.request_metric(decode.MetricInput(
      metric_metadata("bad-metric", "(ending-start)/start", 4),
      decode.NetReturn(fact.Known(malformed), fact.Known(malformed)),
    ))
  {
    Error(domain.MetricFailure(_)) -> Nil
    _ -> should.fail()
  }
  let bad_rounding =
    decode.MetricMetadataInput(
      ..metric_metadata("bad-rounding", "identity", 4),
      rounding: "nearest_magic",
    )
  domain.request_metric(decode.MetricInput(bad_rounding, decode.TradeList([])))
  |> should.equal(
    Error(domain.InvalidField("metadata.rounding", "unknown rounding mode")),
  )
}

pub fn compare_runs_reports_only_exact_input_and_output_differences_test() {
  let left = run_definition("run-left", "1.0.0", "all_branches")
  let right = run_definition("run-right", "1.1.0", "stop_first")
  let input =
    decode.CompareInput(
      "caller_selected_exact_runs_and_outputs_v1",
      definition_input(left),
      definition_input(right),
      [
        decode.OutputInput("net_return", "0.10", sha_text("left-return")),
        decode.OutputInput("trade_count", "3", sha_text("left-count")),
      ],
      [
        decode.OutputInput("net_return", "0.12", sha_text("right-return")),
        decode.OutputInput("drawdown", "0.08", sha_text("right-dd")),
      ],
    )
  let assert Ok(response) = domain.compare_runs(input)
  let text = json.to_string(response.details)
  text |> string.contains("\"operation\":\"compare_runs\"") |> should.be_true
  text |> string.contains("\"field\":\"version\"") |> should.be_true
  text
  |> string.contains("\"field\":\"execution_branch_policy\"")
  |> should.be_true
  text
  |> string.contains(
    "\"field\":\"net_return\",\"left\":\"0.10\",\"right\":\"0.12\"",
  )
  |> should.be_true
  text
  |> string.contains(
    "\"field\":\"trade_count\",\"left\":\"3\",\"right\":\"not_supplied\"",
  )
  |> should.be_true
  text |> string.contains("\"interpretation\":\"llm_owned\"") |> should.be_true
  text |> string.contains("\"preferredRun\"") |> should.be_false
  text |> string.contains("\"significant\"") |> should.be_false
  text |> string.contains("\"robust\"") |> should.be_false
}

pub fn comparison_rejects_noncanonical_hash_drift_and_duplicate_outputs_test() {
  let left = run_definition("run-left", "1.0.0", "all_branches")
  let right = run_definition("run-right", "1.0.0", "all_branches")
  let base =
    decode.CompareInput(
      "caller_selected_exact_runs_and_outputs_v1",
      definition_input(left),
      definition_input(right),
      [],
      [],
    )
  let left_input = definition_input(left)
  let noncanonical =
    decode.DefinitionInput(
      ..left_input,
      canonical_json: left_input.canonical_json <> " ",
    )
  domain.compare_runs(
    decode.CompareInput(..base, left_definition: noncanonical),
  )
  |> should.equal(Error(domain.DefinitionNotCanonical("left")))

  let wrong_hash =
    decode.DefinitionInput(
      ..left_input,
      content_hash: sha_text("wrong-definition"),
    )
  case
    domain.compare_runs(
      decode.CompareInput(..base, left_definition: wrong_hash),
    )
  {
    Error(domain.DefinitionHashMismatch("left", _, _)) -> Nil
    _ -> should.fail()
  }

  let duplicate = decode.OutputInput("net_return", "0.1", sha_text("output"))
  domain.compare_runs(
    decode.CompareInput(..base, left_outputs: [duplicate, duplicate]),
  )
  |> should.equal(Error(domain.DuplicateOutput("left", "net_return")))
}

pub fn every_result_keeps_the_llm_decision_boundary_test() {
  let assert Ok(response) =
    domain.request_metric(decode.MetricInput(
      metric_metadata("metric-boundary", "identity(trades)", 0),
      decode.TradeList([]),
    ))
  let text = json.to_string(response.details)
  text |> string.contains("\"decisionOwner\":\"llm\"") |> should.be_true
  text |> string.contains("\"pluginDecisionFields\":[]") |> should.be_true
  text |> string.contains("\"verdict\"") |> should.be_false
  text |> string.contains("\"recommended\"") |> should.be_false
  text |> string.contains("\"deployable\"") |> should.be_false
  text |> string.contains("\"edge\"") |> should.be_false
  text |> string.contains("\"nextAction\"") |> should.be_false
}

fn inspect_input(
  events: List(decode.LedgerEventInput),
  counts: decode.ExpectedCounts,
  offset: Int,
  limit: Int,
) -> decode.InspectInput {
  decode.InspectInput(
    hypothesis(),
    "population-fixture",
    "caller_declared_complete_population_v1",
    counts,
    events,
    False,
    False,
    offset,
    limit,
  )
}

fn hypothesis() -> decode.HypothesisInput {
  let placeholder =
    decode.HypothesisInput(
      "hypothesis-fixture",
      "1.0.0",
      sha_text("placeholder"),
      decode.AuthorInput("user", None),
      Some("user-fixture"),
      10,
      "Exact fixture hypothesis",
      Some("close_t > close_t_minus_1"),
      Some("net_return"),
      Some(sha_text("universe")),
      [sha_text("feature")],
      Some(sha_text("strategy")),
      Some(9),
      [sha_text("journal")],
      "research_context",
      "review_visible",
    )
  let content =
    json.object([
      #("schema", json.string("pi-sparkles/research-hypothesis")),
      #("schemaVersion", json.int(1)),
      #("hypothesisId", json.string(placeholder.hypothesis_id)),
      #("version", json.string(placeholder.version)),
      #(
        "author",
        json.object([
          #("kind", json.string("user")),
          #("importSource", json.null()),
        ]),
      ),
      #("authorId", json.string("user-fixture")),
      #("declaredTimeUnixMilliseconds", json.int(10)),
      #("text", json.string("Exact fixture hypothesis")),
      #("structuredExpression", json.string("close_t > close_t_minus_1")),
      #("targetValue", json.string("net_return")),
      #("populationRef", json.string(sha_text("universe"))),
      #("featureRefs", json.array([sha_text("feature")], json.string)),
      #("strategyRef", json.string(sha_text("strategy"))),
      #("sourceCutoffUnixMilliseconds", json.int(9)),
      #("supportingRefs", json.array([sha_text("journal")], json.string)),
      #("privacy", json.string("research_context")),
      #("exportClassification", json.string("review_visible")),
      #("decisionOwner", json.string("llm")),
      #("pluginDecisionFields", json.array([], json.string)),
    ])
  let assert Ok(digest) = content |> json.to_string |> hash.text
  decode.HypothesisInput(
    ..placeholder,
    content_hash: identity.sha256_value(digest),
  )
}

fn ledger_event(
  suffix: String,
  status: decode.StatusInput,
) -> decode.LedgerEventInput {
  decode.LedgerEventInput(
    "event-" <> suffix,
    decode.TrialDefinitionInput(
      "trial-" <> suffix,
      None,
      Some("batch-fixture"),
      sha_text("run-" <> suffix),
      [
        decode.ParameterInput(
          "period",
          suffix,
          decode.AuthorInput("llm", None),
          fact.Known(sha_text("parameter-" <> suffix)),
        ),
      ],
      fact.Known("caller-authored rationale"),
      sha_text("partition"),
      [sha_text("model")],
      fact.Known("seed-" <> suffix),
      [sha_text("metric")],
      [sha_text("budget")],
      decode.AuthorInput("llm", None),
      10,
      "research_context",
    ),
    status,
    20,
    fact.Known(30),
    [sha_text("output-" <> suffix)],
    case status.state {
      "failed" -> ["fixture failure retained"]
      _ -> []
    },
    sha_text("effect-" <> suffix),
    "key-" <> suffix,
  )
}

fn completed() -> decode.StatusInput {
  decode.StatusInput("completed", None, None, None, None)
}

fn failed(reason: String) -> decode.StatusInput {
  decode.StatusInput("failed", Some(reason), None, None, None)
}

fn cancelled(at: Int, by: String) -> decode.StatusInput {
  decode.StatusInput("cancelled", None, Some(at), Some(by), None)
}

fn truncated(reason: String) -> decode.StatusInput {
  decode.StatusInput("truncated", Some(reason), None, None, None)
}

fn duplicate_of(existing: String) -> decode.StatusInput {
  decode.StatusInput("duplicate_of", None, None, None, Some(existing))
}

fn unperformed(reason: String) -> decode.StatusInput {
  decode.StatusInput("unperformed", Some(reason), None, None, None)
}

fn metric_metadata(
  id: String,
  formula: String,
  scale: Int,
) -> decode.MetricMetadataInput {
  decode.MetricMetadataInput(
    id,
    formula,
    "1.0.0",
    "dimensionless",
    scale,
    "half_even",
    "preserve_unknown_v1",
    "caller-selected fixture population",
    "caller-supplied order",
    fact.NotApplicable("no benchmark requested"),
    [sha_text("metric-source")],
  )
}

fn run_definition(
  id: String,
  version: String,
  branch_policy: String,
) -> definition.RunDefinition {
  let assert Ok(value) =
    definition.new(
      id,
      version,
      [sha("feature")],
      sha("strategy"),
      [sha("risk")],
      sha("execution"),
      sha("universe"),
      sha("dataset"),
      sha("partition"),
      fact.Known(instant(100)),
      [
        definition.DeclaredPolicy("missing_data", "preserve_unknown", None),
      ],
      branch_policy,
      fact.Known("seed:42/stream:main"),
      ["completed daily fixture"],
    )
  value
}

fn definition_input(value: definition.RunDefinition) -> decode.DefinitionInput {
  decode.DefinitionInput(
    definition.encode(value),
    value |> definition.digest |> identity.sha256_value,
  )
}

fn sha_text(value: String) -> String {
  value |> sha |> identity.sha256_value
}

fn sha(value: String) -> identity.Sha256 {
  let assert Ok(value) = hash.text(value)
  value
}

fn instant(value: Int) -> time.Instant {
  let assert Ok(value) = time.instant(value)
  value
}
