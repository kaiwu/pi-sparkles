import finance_core/decimal
import finance_core/time
import finance_provenance/hash
import finance_provenance/identity.{type Sha256}
import finance_replay/comparison
import finance_replay/definition
import finance_replay/fact
import finance_replay/metric
import finance_replay/trial
import finance_replay/wire
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import pi_sparkles_quant_research/decode

const maximum_text = 65_536

const maximum_events = 1000

const maximum_page_size = 200

const maximum_definition_bytes = 2_000_000

pub type Response {
  Response(summary: String, details: Json)
}

pub type DomainError {
  InvalidField(field: String, reason: String)
  HypothesisHashMismatch(expected: String, actual: String)
  TrialDefinitionFailure(reason: String)
  TrialEventFailure(reason: String)
  LedgerFailure(reason: String)
  LedgerCountsMismatch
  MetricFailure(reason: String)
  DefinitionFailure(side: String, reason: String)
  DefinitionNotCanonical(side: String)
  DefinitionHashMismatch(side: String, expected: String, actual: String)
  DuplicateOutput(side: String, name: String)
}

type PreparedEvent {
  PreparedEvent(
    input: decode.LedgerEventInput,
    value: trial.LedgerEvent,
    definition_hash: Sha256,
    envelope_handle: Sha256,
  )
}

type PreparedLedger {
  PreparedLedger(
    value: trial.Ledger,
    events: List(PreparedEvent),
    idempotent_retries: Int,
  )
}

pub fn error_message(value: DomainError) -> String {
  case value {
    InvalidField(field, reason) ->
      "Invalid exact quant-research field " <> field <> ": " <> reason
    HypothesisHashMismatch(expected, actual) ->
      "Hypothesis contentHash "
      <> expected
      <> " does not match its canonical declaration "
      <> actual
    TrialDefinitionFailure(reason) ->
      "A supplied trial definition failed the finance_replay contract: "
      <> reason
    TrialEventFailure(reason) ->
      "A supplied trial event failed the finance_replay contract: " <> reason
    LedgerFailure(reason) ->
      "The supplied trial ledger failed append-only replay: " <> reason
    LedgerCountsMismatch ->
      "The reconstructed ledger status counts do not match expectedCounts; the declared complete population was not accepted"
    MetricFailure(reason) ->
      "The explicitly requested finance_replay metric failed: " <> reason
    DefinitionFailure(side, reason) ->
      "The " <> side <> " run definition failed to decode: " <> reason
    DefinitionNotCanonical(side) ->
      "The "
      <> side
      <> " canonicalJson is not the exact finance_replay encoding"
    DefinitionHashMismatch(side, expected, actual) ->
      "The "
      <> side
      <> " definition contentHash "
      <> expected
      <> " does not match "
      <> actual
    DuplicateOutput(side, name) ->
      "The " <> side <> " outputs repeat field " <> name
  }
}

pub fn inspect_trial_ledger(
  input: decode.InspectInput,
) -> Result(Response, DomainError) {
  use _ <- result.try(exact_text("populationId", input.population_id))
  use _ <- result.try(case input.completeness_policy {
    "caller_declared_complete_population_v1" -> Ok(Nil)
    _ ->
      Error(InvalidField(
        "completenessPolicy",
        "expected caller_declared_complete_population_v1",
      ))
  })
  use _ <- result.try(count_bound("events", input.events, maximum_events))
  use hypothesis_handle <- result.try(validate_hypothesis(input.hypothesis))
  use prepared <- result.try(prepare_ledger(input.events))
  use _ <- result.try(validate_counts(
    trial.counts(prepared.value),
    input.expected_counts,
  ))
  let total = list.length(prepared.events)
  use _ <- result.try(page(input.offset, input.limit, total))
  let page_values =
    prepared.events |> list.drop(input.offset) |> list.take(input.limit)
  let returned = list.length(page_values)
  let next_offset = case input.offset + returned < total {
    True -> Some(input.offset + returned)
    False -> None
  }
  let cursor = trial.cursor(prepared.value)
  let assert Ok(population_handle) =
    json.object([
      #("hypothesis", wire.sha_json(hypothesis_handle)),
      #("population_id", json.string(input.population_id)),
      #("ledger_cursor", wire.sha_json(cursor)),
    ])
    |> json.to_string
    |> hash.text
  Ok(Response(
    "Inspected "
      <> int.to_string(total)
      <> " retained trials in caller-declared population "
      <> input.population_id,
    json.object([
      #("operation", json.string("inspect_trial_ledger")),
      #(
        "hypothesis",
        hypothesis_json(
          input.hypothesis,
          hypothesis_handle,
          input.include_hypothesis_text,
        ),
      ),
      #("populationId", json.string(input.population_id)),
      #(
        "completenessPolicy",
        json.string("caller_declared_complete_population_v1"),
      ),
      #(
        "completenessLimitation",
        json.string(
          "caller_declaration_cannot_prove_external_events_were_not_omitted",
        ),
      ),
      #("populationHandle", wire.sha_json(population_handle)),
      #("ledgerCursor", wire.sha_json(cursor)),
      #("revision", json.int(trial.revision(prepared.value))),
      #("counts", counts_json(trial.counts(prepared.value))),
      #("idempotentRetryCount", json.int(prepared.idempotent_retries)),
      #("offset", json.int(input.offset)),
      #("limit", json.int(input.limit)),
      #("returnedCount", json.int(returned)),
      #("nextOffset", json.nullable(next_offset, json.int)),
      #(
        "payloadPolicy",
        json.object([
          #("hypothesisTextIncluded", json.bool(input.include_hypothesis_text)),
          #("trialPayloadsIncluded", json.bool(input.include_trial_payloads)),
          #(
            "omittedTrialPayloadCount",
            json.int(case input.include_trial_payloads {
              True -> 0
              False -> total
            }),
          ),
        ]),
      ),
      #(
        "events",
        json.array(page_values, fn(value) {
          prepared_event_json(value, input.include_trial_payloads)
        }),
      ),
      #("decisionOwner", json.string("llm")),
      #("pluginDecisionFields", json.array([], json.string)),
      #(
        "availableOperations",
        json.array(
          ["inspect_trial_ledger", "request_metric", "compare_runs"],
          json.string,
        ),
      ),
    ]),
  ))
}

pub fn request_metric(
  input: decode.MetricInput,
) -> Result(Response, DomainError) {
  use metadata <- result.try(metric_metadata(input.metadata))
  use calculation <- result.try(case input.request {
    decode.NetReturn(denominator, ending_value) -> {
      use denominator <- result.try(decimal_fact(denominator))
      use ending_value <- result.try(decimal_fact(ending_value))
      metric.net_return(metadata, denominator, ending_value)
      |> result.map_error(fn(error) { MetricFailure(string.inspect(error)) })
    }
    decode.WinLossCounts(trades, zero_policy) -> {
      use trades <- result.try(
        list.try_map(trades, fn(value) {
          use source <- result.try(sha(
            "request.trades[].sourceReceipt",
            value.source_receipt,
          ))
          Ok(metric.TradePnl(value.trade_id, value.net_pnl_lexeme, source))
        }),
      )
      metric.win_loss_counts(metadata, trades, zero_policy)
      |> result.map_error(fn(error) { MetricFailure(string.inspect(error)) })
    }
    decode.DrawdownSeries(points, peak_convention) -> {
      use points <- result.try(
        list.try_map(points, fn(value) {
          use input <- result.try(decimal_input(value.value))
          Ok(#(value.label, input))
        }),
      )
      metric.drawdown_series(metadata, points, peak_convention)
      |> result.map_error(fn(error) { MetricFailure(string.inspect(error)) })
    }
    decode.TradeList(trades) -> {
      use trades <- result.try(
        list.try_map(trades, fn(value) {
          use instruction <- result.try(sha(
            "request.trades[].instructionReceipt",
            value.instruction_receipt,
          ))
          use lifecycle <- result.try(shas(
            "request.trades[].lifecycleReceipts",
            value.lifecycle_receipts,
          ))
          Ok(metric.Trade(
            value.trade_id,
            instruction,
            lifecycle,
            value.exact_payload,
          ))
        }),
      )
      metric.trade_list(metadata, trades)
      |> result.map_error(fn(error) { MetricFailure(string.inspect(error)) })
    }
  })
  let calculation_handle = metric.content_hash(calculation)
  Ok(Response(
    metric_summary(input.request, metric.value(calculation)),
    json.object([
      #("operation", json.string("request_metric")),
      #("metricKind", json.string(metric_kind(input.request))),
      #("calculation", metric.as_json(calculation)),
      #("calculationHandle", wire.sha_json(calculation_handle)),
      #("interpretation", json.string("llm_owned")),
      #("decisionOwner", json.string("llm")),
      #("pluginDecisionFields", json.array([], json.string)),
    ]),
  ))
}

pub fn compare_runs(
  input: decode.CompareInput,
) -> Result(Response, DomainError) {
  use _ <- result.try(case input.comparison_policy {
    "caller_selected_exact_runs_and_outputs_v1" -> Ok(Nil)
    _ ->
      Error(InvalidField(
        "comparisonPolicy",
        "expected caller_selected_exact_runs_and_outputs_v1",
      ))
  })
  use left <- result.try(run_definition("left", input.left_definition))
  use right <- result.try(run_definition("right", input.right_definition))
  use left_outputs <- result.try(outputs("left", input.left_outputs))
  use right_outputs <- result.try(outputs("right", input.right_outputs))
  let value = comparison.runs(left, right, left_outputs, right_outputs)
  let input_difference_count = list.length(comparison.input_differences(value))
  let output_difference_count =
    list.length(comparison.output_differences(value))
  Ok(Response(
    "Compared exact runs "
      <> definition.id(left)
      <> " and "
      <> definition.id(right)
      <> ": "
      <> int.to_string(input_difference_count)
      <> " input differences and "
      <> int.to_string(output_difference_count)
      <> " output differences",
    json.object([
      #("operation", json.string("compare_runs")),
      #(
        "comparisonPolicy",
        json.string("caller_selected_exact_runs_and_outputs_v1"),
      ),
      #(
        "runs",
        json.object([
          #(
            "left",
            json.object([
              #("id", json.string(definition.id(left))),
              #("definitionHandle", wire.sha_json(definition.digest(left))),
            ]),
          ),
          #(
            "right",
            json.object([
              #("id", json.string(definition.id(right))),
              #("definitionHandle", wire.sha_json(definition.digest(right))),
            ]),
          ),
        ]),
      ),
      #("inputDifferenceCount", json.int(input_difference_count)),
      #("outputDifferenceCount", json.int(output_difference_count)),
      #("comparison", comparison.as_json(value)),
      #("comparisonHandle", wire.sha_json(comparison.content_hash(value))),
      #("interpretation", json.string("llm_owned")),
      #("decisionOwner", json.string("llm")),
      #("pluginDecisionFields", json.array([], json.string)),
    ]),
  ))
}

fn validate_hypothesis(
  input: decode.HypothesisInput,
) -> Result(Sha256, DomainError) {
  use _ <- result.try(exact_text("hypothesis.hypothesisId", input.hypothesis_id))
  use _ <- result.try(exact_text("hypothesis.version", input.version))
  use _ <- result.try(exact_text("hypothesis.text", input.text))
  use _ <- result.try(validate_author("hypothesis.author", input.author))
  use _ <- result.try(optional_text("hypothesis.authorId", input.author_id))
  use _ <- result.try(optional_text(
    "hypothesis.structuredExpression",
    input.structured_expression,
  ))
  use _ <- result.try(optional_text(
    "hypothesis.targetValue",
    input.target_value,
  ))
  use _ <- result.try(instant(
    "hypothesis.declaredTimeUnixMilliseconds",
    input.declared_time_unix_ms,
  ))
  use _ <- result.try(optional_instant(
    "hypothesis.sourceCutoffUnixMilliseconds",
    input.source_cutoff_unix_ms,
  ))
  use _ <- result.try(optional_sha(
    "hypothesis.populationRef",
    input.population_ref,
  ))
  use _ <- result.try(shas("hypothesis.featureRefs", input.feature_refs))
  use _ <- result.try(optional_sha("hypothesis.strategyRef", input.strategy_ref))
  use _ <- result.try(shas("hypothesis.supportingRefs", input.supporting_refs))
  use _ <- result.try(case input.privacy {
    "private" | "research_context" | "exportable" -> Ok(Nil)
    _ -> Error(InvalidField("hypothesis.privacy", "unknown privacy class"))
  })
  use _ <- result.try(case input.export_classification {
    "local_only" | "review_visible" | "exportable" -> Ok(Nil)
    _ ->
      Error(InvalidField(
        "hypothesis.exportClassification",
        "unknown export class",
      ))
  })
  use expected <- result.try(sha("hypothesis.contentHash", input.content_hash))
  let assert Ok(actual) =
    input |> hypothesis_content_json |> json.to_string |> hash.text
  case expected == actual {
    True -> Ok(actual)
    False ->
      Error(HypothesisHashMismatch(
        identity.sha256_value(expected),
        identity.sha256_value(actual),
      ))
  }
}

fn prepare_ledger(
  values: List(decode.LedgerEventInput),
) -> Result(PreparedLedger, DomainError) {
  prepare_ledger_loop(values, trial.empty(), [], 0)
}

fn prepare_ledger_loop(
  remaining: List(decode.LedgerEventInput),
  ledger: trial.Ledger,
  reversed: List(PreparedEvent),
  idempotent_retries: Int,
) -> Result(PreparedLedger, DomainError) {
  case remaining {
    [] -> Ok(PreparedLedger(ledger, list.reverse(reversed), idempotent_retries))
    [input, ..rest] -> {
      use #(definition, event) <- result.try(build_trial_event(input))
      use #(next_ledger, outcome) <- result.try(
        trial.append(ledger, event)
        |> result.map_error(fn(error) { LedgerFailure(string.inspect(error)) }),
      )
      case outcome {
        trial.Stored(stored) -> {
          let envelope = trial.ledger_event_json(stored)
          let assert Ok(envelope_handle) =
            envelope |> json.to_string |> hash.text
          prepare_ledger_loop(
            rest,
            next_ledger,
            [
              PreparedEvent(
                input,
                stored,
                trial.definition_hash(definition),
                envelope_handle,
              ),
              ..reversed
            ],
            idempotent_retries,
          )
        }
        trial.AlreadyStored(_) ->
          prepare_ledger_loop(
            rest,
            next_ledger,
            reversed,
            idempotent_retries + 1,
          )
      }
    }
  }
}

fn build_trial_event(
  input: decode.LedgerEventInput,
) -> Result(#(trial.Definition, trial.LedgerEvent), DomainError) {
  use definition <- result.try(build_trial_definition(input.trial))
  use status <- result.try(status(input.status))
  use start_time <- result.try(instant(
    "events[].startTimeUnixMilliseconds",
    input.start_time_unix_ms,
  ))
  use end_time <- result.try(instant_fact("events[].endTime", input.end_time))
  use outputs <- result.try(shas(
    "events[].outputReceiptHashes",
    input.output_receipt_hashes,
  ))
  use effect <- result.try(sha(
    "events[].effectReceiptHash",
    input.effect_receipt_hash,
  ))
  use value <- result.try(
    trial.ledger_event(
      input.ledger_event_id,
      definition,
      status,
      start_time,
      end_time,
      outputs,
      input.error_facts,
      effect,
      input.idempotency_key,
    )
    |> result.map_error(fn(error) { TrialEventFailure(string.inspect(error)) }),
  )
  Ok(#(definition, value))
}

fn build_trial_definition(
  input: decode.TrialDefinitionInput,
) -> Result(trial.Definition, DomainError) {
  use run_definition_hash <- result.try(sha(
    "events[].trial.runDefinitionHash",
    input.run_definition_hash,
  ))
  use parameters <- result.try(
    list.try_map(input.parameter_values, fn(value) {
      use author <- result.try(author(
        "events[].trial.parameterValues[].author",
        value.author,
      ))
      use source <- result.try(sha_fact(
        "events[].trial.parameterValues[].sourceReceipt",
        value.source_receipt,
      ))
      Ok(trial.ParameterValue(value.name, value.exact_value, author, source))
    }),
  )
  use partition <- result.try(sha(
    "events[].trial.partitionRef",
    input.partition_ref,
  ))
  use models <- result.try(shas("events[].trial.modelRefs", input.model_refs))
  use metrics <- result.try(shas("events[].trial.metricRefs", input.metric_refs))
  use budgets <- result.try(shas("events[].trial.budgetRefs", input.budget_refs))
  use author <- result.try(author("events[].trial.author", input.author))
  use declared_time <- result.try(instant(
    "events[].trial.declaredTimeUnixMilliseconds",
    input.declared_time_unix_ms,
  ))
  use privacy <- result.try(privacy(input.privacy))
  trial.definition(
    input.trial_id,
    input.parent_trial_id,
    input.batch_id,
    run_definition_hash,
    parameters,
    input.trial_rationale,
    partition,
    models,
    input.seed,
    metrics,
    budgets,
    author,
    declared_time,
    privacy,
  )
  |> result.map_error(fn(error) {
    TrialDefinitionFailure(string.inspect(error))
  })
}

fn validate_counts(
  actual: trial.Counts,
  expected: decode.ExpectedCounts,
) -> Result(Nil, DomainError) {
  let trial.Counts(
    total,
    completed,
    failed,
    cancelled,
    truncated,
    duplicate,
    unperformed,
  ) = actual
  let nonnegative =
    expected.total >= 0
    && expected.completed >= 0
    && expected.failed >= 0
    && expected.cancelled >= 0
    && expected.truncated >= 0
    && expected.duplicate >= 0
    && expected.unperformed >= 0
  case
    nonnegative,
    expected.total
    == expected.completed
    + expected.failed
    + expected.cancelled
    + expected.truncated
    + expected.duplicate
    + expected.unperformed,
    expected
    == decode.ExpectedCounts(
      total,
      completed,
      failed,
      cancelled,
      truncated,
      duplicate,
      unperformed,
    )
  {
    True, True, True -> Ok(Nil)
    _, _, _ -> Error(LedgerCountsMismatch)
  }
}

fn metric_metadata(
  input: decode.MetricMetadataInput,
) -> Result(metric.Metadata, DomainError) {
  use rounding <- result.try(rounding(input.rounding))
  use benchmark <- result.try(sha_fact("metadata.benchmark", input.benchmark))
  use sources <- result.try(shas(
    "metadata.sourceReceipts",
    input.source_receipts,
  ))
  Ok(metric.Metadata(
    input.request_id,
    input.formula,
    input.formula_version,
    input.unit,
    input.scale,
    rounding,
    input.missing_conflict_policy,
    input.sample_population,
    input.ordering,
    benchmark,
    sources,
  ))
}

fn run_definition(
  side: String,
  input: decode.DefinitionInput,
) -> Result(definition.RunDefinition, DomainError) {
  use _ <- result.try(case string.byte_size(input.canonical_json) {
    size if size >= 1 && size <= maximum_definition_bytes -> Ok(Nil)
    _ ->
      Error(InvalidField(
        side <> "Definition.canonicalJson",
        "byte length must be 1..2000000",
      ))
  })
  use expected <- result.try(sha(
    side <> "Definition.contentHash",
    input.content_hash,
  ))
  use value <- result.try(
    definition.decode(input.canonical_json)
    |> result.map_error(fn(error) {
      DefinitionFailure(side, string.inspect(error))
    }),
  )
  use _ <- result.try(case definition.encode(value) == input.canonical_json {
    True -> Ok(Nil)
    False -> Error(DefinitionNotCanonical(side))
  })
  let actual = definition.digest(value)
  case expected == actual {
    True -> Ok(value)
    False ->
      Error(DefinitionHashMismatch(
        side,
        identity.sha256_value(expected),
        identity.sha256_value(actual),
      ))
  }
}

fn outputs(
  side: String,
  values: List(decode.OutputInput),
) -> Result(List(comparison.OutputField), DomainError) {
  use _ <- result.try(count_bound(side <> "Outputs", values, 1000))
  outputs_loop(side, values, [], [])
}

fn outputs_loop(
  side: String,
  remaining: List(decode.OutputInput),
  seen: List(String),
  reversed: List(comparison.OutputField),
) -> Result(List(comparison.OutputField), DomainError) {
  case remaining {
    [] -> Ok(list.reverse(reversed))
    [value, ..rest] -> {
      use _ <- result.try(exact_text(side <> "Outputs[].name", value.name))
      use _ <- result.try(exact_text(
        side <> "Outputs[].exactValue",
        value.exact_value,
      ))
      use source <- result.try(sha(
        side <> "Outputs[].sourceReceipt",
        value.source_receipt,
      ))
      case list.contains(seen, value.name) {
        True -> Error(DuplicateOutput(side, value.name))
        False ->
          outputs_loop(side, rest, [value.name, ..seen], [
            comparison.OutputField(value.name, value.exact_value, source),
            ..reversed
          ])
      }
    }
  }
}

fn prepared_event_json(value: PreparedEvent, include_payload: Bool) -> Json {
  let base = [
    #("ledgerEventId", json.string(value.input.ledger_event_id)),
    #("trialId", json.string(value.input.trial.trial_id)),
    #("trialDefinitionHandle", wire.sha_json(value.definition_hash)),
    #("eventEnvelopeHandle", wire.sha_json(value.envelope_handle)),
    #("status", status_input_json(value.input.status)),
    #(
      "parameterValues",
      json.array(value.input.trial.parameter_values, parameter_input_json),
    ),
    #(
      "outputReceiptHashes",
      json.array(value.input.output_receipt_hashes, json.string),
    ),
    #("errorFacts", json.array(value.input.error_facts, json.string)),
  ]
  json.object(case include_payload {
    True ->
      list.append(base, [
        #("eventEnvelope", trial.ledger_event_json(value.value)),
      ])
    False -> list.append(base, [#("eventEnvelope", json.null())])
  })
}

fn hypothesis_content_json(input: decode.HypothesisInput) -> Json {
  json.object([
    #("schema", json.string("pi-sparkles/research-hypothesis")),
    #("schemaVersion", json.int(1)),
    #("hypothesisId", json.string(input.hypothesis_id)),
    #("version", json.string(input.version)),
    #("author", author_input_json(input.author)),
    #("authorId", json.nullable(input.author_id, json.string)),
    #("declaredTimeUnixMilliseconds", json.int(input.declared_time_unix_ms)),
    #("text", json.string(input.text)),
    #(
      "structuredExpression",
      json.nullable(input.structured_expression, json.string),
    ),
    #("targetValue", json.nullable(input.target_value, json.string)),
    #("populationRef", json.nullable(input.population_ref, json.string)),
    #("featureRefs", json.array(input.feature_refs, json.string)),
    #("strategyRef", json.nullable(input.strategy_ref, json.string)),
    #(
      "sourceCutoffUnixMilliseconds",
      json.nullable(input.source_cutoff_unix_ms, json.int),
    ),
    #("supportingRefs", json.array(input.supporting_refs, json.string)),
    #("privacy", json.string(input.privacy)),
    #("exportClassification", json.string(input.export_classification)),
    #("decisionOwner", json.string("llm")),
    #("pluginDecisionFields", json.array([], json.string)),
  ])
}

fn hypothesis_json(
  input: decode.HypothesisInput,
  handle: Sha256,
  include_text: Bool,
) -> Json {
  json.object([
    #("hypothesisId", json.string(input.hypothesis_id)),
    #("version", json.string(input.version)),
    #("contentHash", wire.sha_json(handle)),
    #("author", author_input_json(input.author)),
    #("authorId", json.nullable(input.author_id, json.string)),
    #("declaredTimeUnixMilliseconds", json.int(input.declared_time_unix_ms)),
    #("text", case include_text {
      True -> json.string(input.text)
      False -> json.null()
    }),
    #("textOmitted", json.bool(!include_text)),
    #(
      "structuredExpression",
      json.nullable(input.structured_expression, json.string),
    ),
    #("targetValue", json.nullable(input.target_value, json.string)),
    #("populationRef", json.nullable(input.population_ref, json.string)),
    #("featureRefs", json.array(input.feature_refs, json.string)),
    #("strategyRef", json.nullable(input.strategy_ref, json.string)),
    #(
      "sourceCutoffUnixMilliseconds",
      json.nullable(input.source_cutoff_unix_ms, json.int),
    ),
    #("supportingRefs", json.array(input.supporting_refs, json.string)),
    #("privacy", json.string(input.privacy)),
    #("exportClassification", json.string(input.export_classification)),
  ])
}

fn parameter_input_json(value: decode.ParameterInput) -> Json {
  json.object([
    #("name", json.string(value.name)),
    #("exactValue", json.string(value.exact_value)),
    #("author", author_input_json(value.author)),
    #("sourceReceipt", fact.to_json(value.source_receipt, json.string)),
  ])
}

fn author_input_json(value: decode.AuthorInput) -> Json {
  json.object([
    #("kind", json.string(value.kind)),
    #("importSource", json.nullable(value.import_source, json.string)),
  ])
}

fn status_input_json(value: decode.StatusInput) -> Json {
  json.object([
    #("state", json.string(value.state)),
    #("reason", json.nullable(value.reason, json.string)),
    #("atUnixMilliseconds", json.nullable(value.at_unix_ms, json.int)),
    #("by", json.nullable(value.by, json.string)),
    #("existingTrialId", json.nullable(value.existing_trial_id, json.string)),
  ])
}

fn counts_json(value: trial.Counts) -> Json {
  let trial.Counts(
    total,
    completed,
    failed,
    cancelled,
    truncated,
    duplicate,
    unperformed,
  ) = value
  json.object([
    #("total", json.int(total)),
    #("completed", json.int(completed)),
    #("failed", json.int(failed)),
    #("cancelled", json.int(cancelled)),
    #("truncated", json.int(truncated)),
    #("duplicate", json.int(duplicate)),
    #("unperformed", json.int(unperformed)),
  ])
}

fn metric_summary(
  request: decode.MetricRequestInput,
  value: metric.CalculationValue,
) -> String {
  let prefix = "Calculated requested " <> metric_kind(request) <> ": "
  case value {
    metric.ExactDecimal(value) -> prefix <> value
    metric.Counts(wins, losses, ties) ->
      prefix
      <> int.to_string(wins)
      <> " wins, "
      <> int.to_string(losses)
      <> " losses, "
      <> int.to_string(ties)
      <> " ties"
    metric.DrawdownSeries(points) ->
      prefix <> int.to_string(list.length(points)) <> " ordered points"
    metric.TradeList(trades) ->
      prefix <> int.to_string(list.length(trades)) <> " exact trades"
    metric.Unperformed(reason, _) -> prefix <> "unperformed (" <> reason <> ")"
  }
}

fn metric_kind(value: decode.MetricRequestInput) -> String {
  case value {
    decode.NetReturn(_, _) -> "net_return"
    decode.WinLossCounts(_, _) -> "win_loss_counts"
    decode.DrawdownSeries(_, _) -> "drawdown_series"
    decode.TradeList(_) -> "trade_list"
  }
}

fn decimal_fact(
  value: fact.Fact(decode.DecimalInput),
) -> Result(fact.Fact(metric.DecimalInput), DomainError) {
  case value {
    fact.Known(value) -> decimal_input(value) |> result.map(fact.Known)
    fact.Unknown(reason) -> Ok(fact.Unknown(reason))
    fact.NotObtained(reason) -> Ok(fact.NotObtained(reason))
    fact.NotApplicable(reason) -> Ok(fact.NotApplicable(reason))
    fact.DecodeFailure(raw, reason) -> Ok(fact.DecodeFailure(raw, reason))
    fact.Conflicting(values, reason) ->
      list.try_map(values, decimal_input)
      |> result.map(fn(values) { fact.Conflicting(values, reason) })
  }
}

fn decimal_input(
  value: decode.DecimalInput,
) -> Result(metric.DecimalInput, DomainError) {
  use source <- result.try(sha(
    "request.input.sourceReceipt",
    value.source_receipt,
  ))
  Ok(metric.DecimalInput(value.name, value.exact_lexeme, source))
}

fn sha_fact(
  field: String,
  value: fact.Fact(String),
) -> Result(fact.Fact(Sha256), DomainError) {
  case value {
    fact.Known(value) -> sha(field, value) |> result.map(fact.Known)
    fact.Unknown(reason) -> Ok(fact.Unknown(reason))
    fact.NotObtained(reason) -> Ok(fact.NotObtained(reason))
    fact.NotApplicable(reason) -> Ok(fact.NotApplicable(reason))
    fact.DecodeFailure(raw, reason) -> Ok(fact.DecodeFailure(raw, reason))
    fact.Conflicting(values, reason) ->
      list.try_map(values, fn(value) { sha(field, value) })
      |> result.map(fn(values) { fact.Conflicting(values, reason) })
  }
}

fn instant_fact(
  field: String,
  value: fact.Fact(Int),
) -> Result(fact.Fact(time.Instant), DomainError) {
  case value {
    fact.Known(value) -> instant(field, value) |> result.map(fact.Known)
    fact.Unknown(reason) -> Ok(fact.Unknown(reason))
    fact.NotObtained(reason) -> Ok(fact.NotObtained(reason))
    fact.NotApplicable(reason) -> Ok(fact.NotApplicable(reason))
    fact.DecodeFailure(raw, reason) -> Ok(fact.DecodeFailure(raw, reason))
    fact.Conflicting(values, reason) ->
      list.try_map(values, fn(value) { instant(field, value) })
      |> result.map(fn(values) { fact.Conflicting(values, reason) })
  }
}

fn status(value: decode.StatusInput) -> Result(trial.Status, DomainError) {
  case value {
    decode.StatusInput("completed", None, None, None, None) ->
      Ok(trial.Completed)
    decode.StatusInput("failed", Some(reason), None, None, None) ->
      Ok(trial.Failed(reason))
    decode.StatusInput("cancelled", None, Some(at), Some(by), None) -> {
      use at <- result.try(instant("events[].status.atUnixMilliseconds", at))
      Ok(trial.Cancelled(at, by))
    }
    decode.StatusInput("truncated", Some(reason), None, None, None) ->
      Ok(trial.Truncated(reason))
    decode.StatusInput("duplicate_of", None, None, None, Some(existing)) ->
      Ok(trial.DuplicateOf(existing))
    decode.StatusInput("unperformed", Some(reason), None, None, None) ->
      Ok(trial.Unperformed(reason))
    _ ->
      Error(InvalidField(
        "events[].status",
        "state-specific fields are missing or extraneous",
      ))
  }
}

fn author(
  field: String,
  value: decode.AuthorInput,
) -> Result(trial.AuthorKind, DomainError) {
  use _ <- result.try(validate_author(field, value))
  case value {
    decode.AuthorInput("llm", None) -> Ok(trial.Llm)
    decode.AuthorInput("user", None) -> Ok(trial.User)
    decode.AuthorInput("imported", Some(source)) -> Ok(trial.Imported(source))
    _ -> Error(InvalidField(field, "invalid author fields"))
  }
}

fn validate_author(
  field: String,
  value: decode.AuthorInput,
) -> Result(Nil, DomainError) {
  case value {
    decode.AuthorInput("llm", None) | decode.AuthorInput("user", None) ->
      Ok(Nil)
    decode.AuthorInput("imported", Some(source)) ->
      exact_text(field <> ".importSource", source)
    _ ->
      Error(InvalidField(
        field,
        "expected llm, user, or imported with importSource",
      ))
  }
}

fn privacy(value: String) -> Result(trial.Privacy, DomainError) {
  case value {
    "private" -> Ok(trial.Private)
    "research_context" -> Ok(trial.ResearchContext)
    "exportable" -> Ok(trial.Exportable)
    _ -> Error(InvalidField("events[].trial.privacy", "unknown privacy class"))
  }
}

fn rounding(value: String) -> Result(decimal.RoundingMode, DomainError) {
  case value {
    "toward_zero" -> Ok(decimal.TowardZero)
    "away_from_zero" -> Ok(decimal.AwayFromZero)
    "half_up" -> Ok(decimal.HalfUp)
    "half_even" -> Ok(decimal.HalfEven)
    _ -> Error(InvalidField("metadata.rounding", "unknown rounding mode"))
  }
}

fn sha(field: String, value: String) -> Result(Sha256, DomainError) {
  identity.sha256(value)
  |> result.map_error(fn(_) {
    InvalidField(field, "expected 64 hexadecimal characters")
  })
}

fn shas(
  field: String,
  values: List(String),
) -> Result(List(Sha256), DomainError) {
  list.try_map(values, fn(value) { sha(field, value) })
}

fn optional_sha(
  field: String,
  value: Option(String),
) -> Result(Option(Sha256), DomainError) {
  case value {
    Some(value) -> sha(field, value) |> result.map(Some)
    None -> Ok(None)
  }
}

fn instant(field: String, value: Int) -> Result(time.Instant, DomainError) {
  time.instant(value)
  |> result.map_error(fn(_) { InvalidField(field, "invalid Unix milliseconds") })
}

fn optional_instant(
  field: String,
  value: Option(Int),
) -> Result(Option(time.Instant), DomainError) {
  case value {
    Some(value) -> instant(field, value) |> result.map(Some)
    None -> Ok(None)
  }
}

fn exact_text(field: String, value: String) -> Result(Nil, DomainError) {
  case
    value != ""
    && string.trim(value) == value
    && string.length(value) <= maximum_text
    && !string.contains(value, "\n")
    && !string.contains(value, "\r")
  {
    True -> Ok(Nil)
    False ->
      Error(InvalidField(field, "must be nonblank, bounded, and single-line"))
  }
}

fn optional_text(
  field: String,
  value: Option(String),
) -> Result(Nil, DomainError) {
  case value {
    Some(value) -> exact_text(field, value)
    None -> Ok(Nil)
  }
}

fn count_bound(
  field: String,
  values: List(a),
  maximum: Int,
) -> Result(Nil, DomainError) {
  let count = list.length(values)
  case count <= maximum {
    True -> Ok(Nil)
    False ->
      Error(InvalidField(
        field,
        "received "
          <> int.to_string(count)
          <> ", maximum "
          <> int.to_string(maximum),
      ))
  }
}

fn page(offset: Int, limit: Int, total: Int) -> Result(Nil, DomainError) {
  case
    offset >= 0 && offset <= total,
    limit >= 1 && limit <= maximum_page_size
  {
    True, True -> Ok(Nil)
    _, _ ->
      Error(InvalidField(
        "page",
        "offset must be within the retained population and limit must be 1..200",
      ))
  }
}
