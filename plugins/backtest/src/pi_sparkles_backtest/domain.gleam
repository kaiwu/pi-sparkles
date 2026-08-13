import finance_core/time
import finance_provenance/hash
import finance_provenance/identity.{type Sha256}
import finance_replay/definition
import finance_replay/event
import finance_replay/fact
import finance_replay/fold
import finance_replay/reproduction
import finance_replay/scripted
import finance_replay/wire
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import pi_sparkles_backtest/decode

const cadence_policy = "caller_declared_completed_daily_cash_equity_v1"

const maximum_definition_bytes = 2_000_000

const maximum_event_bytes = 200_000

const maximum_supplied_events = 10_000

pub type Response {
  Response(summary: String, details: Json)
}

pub type DomainError {
  InvalidField(field: String, reason: String)
  TooManyEvents(received: Int, maximum: Int)
  DefinitionFailure(String)
  DefinitionNotCanonical
  DefinitionHashMismatch(expected: String, actual: String)
  EventFailure(index: Int, reason: String)
  EventNotCanonical(index: Int)
  EventHashMismatch(index: Int, expected: String, actual: String)
  EventRunMismatch(index: Int, expected: String, received: String)
  ReplayFailure(String)
  PageOutside(offset: Int, count: Int)
  ManifestFailure(String)
  ExportEventTooLarge(index: Int, required: Int, maximum: Int)
}

type PreparedEvent {
  PreparedEvent(
    value: event.Event,
    encoded_bytes: Int,
    elapsed_milliseconds: Int,
    session_increment: Int,
  )
}

type PreparedRun {
  PreparedRun(
    input: decode.RunInput,
    definition: definition.RunDefinition,
    supplied_events: List(PreparedEvent),
    result: scripted.RunResult,
    result_handle: Sha256,
  )
}

pub fn error_message(error: DomainError) -> String {
  case error {
    InvalidField(field, reason) -> field <> ": " <> reason
    TooManyEvents(received, maximum) ->
      "events contains "
      <> int.to_string(received)
      <> " entries; maximum is "
      <> int.to_string(maximum)
    DefinitionFailure(reason) ->
      "definition canonicalJson is not a valid finance_replay definition: "
      <> reason
    DefinitionNotCanonical ->
      "definition canonicalJson is valid but is not the exact canonical encoding"
    DefinitionHashMismatch(expected, actual) ->
      "definition contentHash mismatch: expected "
      <> expected
      <> ", calculated "
      <> actual
    EventFailure(index, reason) ->
      "events[" <> int.to_string(index) <> "]: " <> reason
    EventNotCanonical(index) ->
      "events["
      <> int.to_string(index)
      <> "].canonicalJson is not the exact canonical encoding"
    EventHashMismatch(index, expected, actual) ->
      "events["
      <> int.to_string(index)
      <> "].contentHash mismatch: expected "
      <> expected
      <> ", calculated "
      <> actual
    EventRunMismatch(index, expected, received) ->
      "events["
      <> int.to_string(index)
      <> "] names run "
      <> received
      <> "; expected verified definition ID "
      <> expected
    ReplayFailure(reason) -> "scripted replay failed: " <> reason
    PageOutside(offset, count) ->
      "offset "
      <> int.to_string(offset)
      <> " is outside retained event count "
      <> int.to_string(count)
    ManifestFailure(reason) ->
      "reproduction manifest could not be constructed: " <> reason
    ExportEventTooLarge(index, required, maximum) ->
      "retained event at offset "
      <> int.to_string(index)
      <> " requires "
      <> int.to_string(required)
      <> " JSONL characters; maximumCharacters is "
      <> int.to_string(maximum)
  }
}

pub fn submit_run(input: decode.RunInput) -> Result(Response, DomainError) {
  use prepared <- result.try(prepare_run(input))
  let state = scripted.state(prepared.result)
  let consumed = scripted.processed_events(prepared.result)
  let retained = fold.revision(state)
  let omitted = scripted.omitted_events(prepared.result)
  let costs = consumed_costs(prepared.supplied_events, consumed)
  Ok(Response(
    "Replayed "
      <> int.to_string(consumed)
      <> " supplied events; retained "
      <> int.to_string(retained)
      <> ", omitted "
      <> int.to_string(omitted)
      <> ", fold status "
      <> fold.status_name(fold.status(state)),
    json.object([
      #("operation", json.string("submit_run")),
      #("cadencePolicy", json.string(cadence_policy)),
      #("definition", definition_json(prepared.definition)),
      #("runResultHandle", wire.sha_json(prepared.result_handle)),
      #("runStateHandle", wire.sha_json(fold.semantic_hash(state))),
      #(
        "state",
        json.object([
          #("status", json.string(fold.status_name(fold.status(state)))),
          #("revision", json.int(retained)),
          #("consumedEventCount", json.int(consumed)),
          #("retainedEventCount", json.int(retained)),
          #("idempotentRetryCount", json.int(consumed - retained)),
          #("omittedEventCount", json.int(omitted)),
          #("consumedCosts", costs_json(costs)),
          #("stop", stop_json(scripted.stop(prepared.result))),
        ]),
      ),
      #("eventKindCounts", event_kind_counts(fold.events(state))),
      #(
        "orderingFacts",
        json.array(fold.ordering_facts(state), ordering_fact_json),
      ),
      #(
        "limitations",
        json.array(
          [
            "cadence_is_caller_declared_not_provider_or_exchange_proof",
            "input_exhausted_does_not_imply_a_run_completed_event",
            "run_is_local_and_stateless_not_queued_or_persisted",
          ],
          json.string,
        ),
      ),
      #("decisionOwner", json.string("llm")),
      #("pluginDecisionFields", json.array([], json.string)),
      #(
        "availableOperations",
        json.array(
          ["submit_run", "inspect_events", "export_backtest_manifest"],
          json.string,
        ),
      ),
    ]),
  ))
}

pub fn inspect_events(
  input: decode.InspectInput,
) -> Result(Response, DomainError) {
  use prepared <- result.try(prepare_run(input.run))
  let state = scripted.state(prepared.result)
  let events = fold.events(state)
  let total = list.length(events)
  use _ <- result.try(validate_page(input.offset, input.limit, total))
  let page = events |> list.drop(input.offset) |> list.take(input.limit)
  let returned = list.length(page)
  let next_offset = case input.offset + returned < total {
    True -> Some(input.offset + returned)
    False -> None
  }
  Ok(Response(
    "Returned "
      <> int.to_string(returned)
      <> " of "
      <> int.to_string(total)
      <> " retained replay events",
    json.object([
      #("operation", json.string("inspect_events")),
      #("cadencePolicy", json.string(cadence_policy)),
      #("definition", definition_json(prepared.definition)),
      #("runResultHandle", wire.sha_json(prepared.result_handle)),
      #("runStateHandle", wire.sha_json(fold.semantic_hash(state))),
      #("foldStatus", json.string(fold.status_name(fold.status(state)))),
      #("stop", stop_json(scripted.stop(prepared.result))),
      #("retainedEventCount", json.int(total)),
      #(
        "unprocessedInputEventCount",
        json.int(scripted.omitted_events(prepared.result)),
      ),
      #("offset", json.int(input.offset)),
      #("limit", json.int(input.limit)),
      #("returnedCount", json.int(returned)),
      #("nextOffset", json.nullable(next_offset, json.int)),
      #("payloadsIncluded", json.bool(input.include_payloads)),
      #(
        "events",
        json.array(page, fn(value) {
          inspected_event_json(value, input.include_payloads)
        }),
      ),
      #("decisionOwner", json.string("llm")),
      #("pluginDecisionFields", json.array([], json.string)),
      #(
        "availableOperations",
        json.array(
          ["submit_run", "inspect_events", "export_backtest_manifest"],
          json.string,
        ),
      ),
    ]),
  ))
}

pub fn export_manifest(
  input: decode.ExportInput,
) -> Result(Response, DomainError) {
  use _ <- result.try(case input.maximum_events {
    value if value >= 1 && value <= 200 -> Ok(Nil)
    _ -> Error(InvalidField("maximumEvents", "expected 1..200"))
  })
  use _ <- result.try(case input.maximum_characters {
    value if value >= 1 && value <= 10_000_000 -> Ok(Nil)
    _ -> Error(InvalidField("maximumCharacters", "expected 1..10000000"))
  })
  use prepared <- result.try(prepare_run(input.run))
  let retained = prepared.result |> scripted.state |> fold.events
  let total = list.length(retained)
  use _ <- result.try(validate_offset(input.offset, total))
  use manifest <- result.try(reproduction_manifest(prepared, input.manifest))
  use page <- result.try(export_page(
    list.drop(retained, input.offset),
    input.offset,
    input.maximum_events,
    input.maximum_characters,
  ))
  let returned = list.length(page)
  let next_offset = case input.offset + returned < total {
    True -> Some(input.offset + returned)
    False -> None
  }
  let reproduction.Bundle(
    manifest_json,
    events_jsonl,
    receipt_directory,
    checkpoint_directory,
  ) = reproduction.export_bundle(manifest, page)
  let bundle_complete = input.offset == 0 && next_offset == None
  Ok(Response(
    "Exported reproduction manifest with "
      <> int.to_string(returned)
      <> " of "
      <> int.to_string(total)
      <> " retained events in this JSONL page",
    json.object([
      #("operation", json.string("export_backtest_manifest")),
      #("cadencePolicy", json.string(cadence_policy)),
      #("definition", definition_json(prepared.definition)),
      #("runResultHandle", wire.sha_json(prepared.result_handle)),
      #(
        "runStateHandle",
        wire.sha_json(fold.semantic_hash(scripted.state(prepared.result))),
      ),
      #("manifestHandle", wire.sha_json(reproduction.content_hash(manifest))),
      #("manifestJson", json.string(manifest_json)),
      #("eventsJsonl", json.string(events_jsonl)),
      #("receiptDirectory", json.string(receipt_directory)),
      #("checkpointDirectory", json.string(checkpoint_directory)),
      #("retainedEventCount", json.int(total)),
      #("offset", json.int(input.offset)),
      #("maximumEvents", json.int(input.maximum_events)),
      #("maximumCharacters", json.int(input.maximum_characters)),
      #("returnedCount", json.int(returned)),
      #("returnedCharacters", json.int(string.length(events_jsonl))),
      #("nextOffset", json.nullable(next_offset, json.int)),
      #("pageComplete", json.bool(next_offset == None)),
      #("bundleComplete", json.bool(bundle_complete)),
      #(
        "integrityScope",
        json.string(
          "content_coherence_only_not_origin_licence_correctness_or_research_quality",
        ),
      ),
      #("decisionOwner", json.string("llm")),
      #("pluginDecisionFields", json.array([], json.string)),
      #(
        "availableOperations",
        json.array(
          ["submit_run", "inspect_events", "export_backtest_manifest"],
          json.string,
        ),
      ),
    ]),
  ))
}

fn prepare_run(input: decode.RunInput) -> Result(PreparedRun, DomainError) {
  use _ <- result.try(case input.cadence_policy == cadence_policy {
    True -> Ok(Nil)
    False -> Error(InvalidField("cadencePolicy", "expected " <> cadence_policy))
  })
  use run_definition <- result.try(run_definition(input.definition))
  let event_count = list.length(input.events)
  use _ <- result.try(case event_count <= maximum_supplied_events {
    True -> Ok(Nil)
    False -> Error(TooManyEvents(event_count, maximum_supplied_events))
  })
  use prepared_events <- result.try(prepare_events(
    input.events,
    definition.id(run_definition),
    0,
  ))
  let decode.BudgetInput(max_events, max_bytes, max_wall, max_sessions) =
    input.budget
  let budget = scripted.Budget(max_events, max_bytes, max_wall, max_sessions)
  use cancellation <- result.try(cancellation(input.cancellation))
  let script =
    prepared_events
    |> list.map(fn(value) {
      scripted.ScriptItem(
        value.value,
        value.encoded_bytes,
        value.elapsed_milliseconds,
        value.session_increment,
      )
    })
  use replay <- result.try(
    scripted.run(
      definition.id(run_definition),
      definition.digest(run_definition),
      script,
      budget,
      cancellation,
    )
    |> result.map_error(fn(error) { ReplayFailure(string.inspect(error)) }),
  )
  let state = scripted.state(replay)
  let handle_payload =
    json.object([
      #("cadence_policy", json.string(cadence_policy)),
      #("definition_hash", wire.sha_json(definition.digest(run_definition))),
      #("state_hash", wire.sha_json(fold.semantic_hash(state))),
      #("budget", budget_json(input.budget)),
      #("cancellation", cancellation_input_json(input.cancellation)),
      #("stop", stop_json(scripted.stop(replay))),
      #("consumed_events", json.int(scripted.processed_events(replay))),
      #("omitted_events", json.int(scripted.omitted_events(replay))),
    ])
  let assert Ok(result_handle) = handle_payload |> json.to_string |> hash.text
  Ok(PreparedRun(input, run_definition, prepared_events, replay, result_handle))
}

fn run_definition(
  input: decode.DefinitionInput,
) -> Result(definition.RunDefinition, DomainError) {
  let size = string.byte_size(input.canonical_json)
  use _ <- result.try(case size >= 1 && size <= maximum_definition_bytes {
    True -> Ok(Nil)
    False ->
      Error(InvalidField(
        "definition.canonicalJson",
        "UTF-8 byte length must be 1..2000000",
      ))
  })
  use expected <- result.try(sha("definition.contentHash", input.content_hash))
  use value <- result.try(
    definition.decode(input.canonical_json)
    |> result.map_error(fn(error) { DefinitionFailure(string.inspect(error)) }),
  )
  use _ <- result.try(case definition.encode(value) == input.canonical_json {
    True -> Ok(Nil)
    False -> Error(DefinitionNotCanonical)
  })
  let actual = definition.digest(value)
  case expected == actual {
    True -> Ok(value)
    False ->
      Error(DefinitionHashMismatch(
        identity.sha256_value(expected),
        identity.sha256_value(actual),
      ))
  }
}

fn prepare_events(
  values: List(decode.EventInput),
  run_id: String,
  index: Int,
) -> Result(List(PreparedEvent), DomainError) {
  case values {
    [] -> Ok([])
    [input, ..rest] -> {
      use prepared <- result.try(prepare_event(input, run_id, index))
      use tail <- result.try(prepare_events(rest, run_id, index + 1))
      Ok([prepared, ..tail])
    }
  }
}

fn prepare_event(
  input: decode.EventInput,
  run_id: String,
  index: Int,
) -> Result(PreparedEvent, DomainError) {
  let size = string.byte_size(input.canonical_json)
  use _ <- result.try(case size >= 1 && size <= maximum_event_bytes {
    True -> Ok(Nil)
    False ->
      Error(EventFailure(
        index,
        "canonicalJson UTF-8 byte length must be 1..200000",
      ))
  })
  use _ <- result.try(
    case input.session_increment == 0 || input.session_increment == 1 {
      True -> Ok(Nil)
      False ->
        Error(EventFailure(index, "sessionIncrement must be zero or one"))
    },
  )
  use expected <- result.try(
    sha("events[].contentHash", input.content_hash)
    |> result.map_error(fn(error) { EventFailure(index, error_message(error)) }),
  )
  use value <- result.try(
    event.decode(input.canonical_json)
    |> result.map_error(fn(error) {
      EventFailure(
        index,
        "canonicalJson is not a valid finance_replay event: "
          <> string.inspect(error),
      )
    }),
  )
  use _ <- result.try(case event.encode(value) == input.canonical_json {
    True -> Ok(Nil)
    False -> Error(EventNotCanonical(index))
  })
  let actual = event.canonical_content_hash(value)
  use _ <- result.try(case expected == actual {
    True -> Ok(Nil)
    False ->
      Error(EventHashMismatch(
        index,
        identity.sha256_value(expected),
        identity.sha256_value(actual),
      ))
  })
  use _ <- result.try(case event.run_id(value) == run_id {
    True -> Ok(Nil)
    False -> Error(EventRunMismatch(index, run_id, event.run_id(value)))
  })
  Ok(PreparedEvent(
    value,
    size,
    input.elapsed_milliseconds,
    input.session_increment,
  ))
}

fn cancellation(
  input: decode.CancellationInput,
) -> Result(scripted.Cancellation, DomainError) {
  case input {
    decode.Continue -> Ok(scripted.Continue)
    decode.CancelBefore(clock, at, by) -> {
      use _ <- result.try(case clock >= 0 {
        True -> Ok(Nil)
        False ->
          Error(InvalidField("cancellation.replayClock", "must be nonnegative"))
      })
      use at <- result.try(
        time.instant(at)
        |> result.map_error(fn(_) {
          InvalidField(
            "cancellation.cancelledAtUnixMilliseconds",
            "invalid Unix milliseconds",
          )
        }),
      )
      use _ <- result.try(exact_text("cancellation.cancelledBy", by))
      Ok(scripted.CancelBefore(clock, at, by))
    }
  }
}

fn reproduction_manifest(
  prepared: PreparedRun,
  input: decode.ManifestInput,
) -> Result(reproduction.Manifest, DomainError) {
  use sources <- result.try(shas(
    "manifest.orderedSourceHashes",
    input.ordered_source_hashes,
  ))
  use transformations <- result.try(shas(
    "manifest.transformationReceipts",
    input.transformation_receipts,
  ))
  use calendars <- result.try(shas(
    "manifest.calendarReceipts",
    input.calendar_receipts,
  ))
  use rules <- result.try(shas("manifest.ruleReceipts", input.rule_receipts))
  use actions <- result.try(shas(
    "manifest.corporateActionReceipts",
    input.corporate_action_receipts,
  ))
  use costs <- result.try(shas("manifest.costReceipts", input.cost_receipts))
  use outputs <- result.try(shas(
    "manifest.outputReceiptHashes",
    input.output_receipt_hashes,
  ))
  use checkpoints <- result.try(shas(
    "manifest.checkpointHashes",
    input.checkpoint_hashes,
  ))
  use omitted <- result.try(dependencies(
    "manifest.omittedDependencies",
    input.omitted_dependencies,
  ))
  use unknown <- result.try(dependencies(
    "manifest.unknownDependencies",
    input.unknown_dependencies,
  ))
  use conflicting <- result.try(dependencies(
    "manifest.conflictingDependencies",
    input.conflicting_dependencies,
  ))
  let environments =
    input.environment_versions
    |> list.map(fn(value) {
      reproduction.EnvironmentVersion(value.name, value.version, value.semantic)
    })
  reproduction.new(
    input.manifest_id,
    environments,
    definition.digest(prepared.definition),
    input.trial_ids,
    definition.partition_receipt(prepared.definition),
    definition.universe_manifest(prepared.definition),
    definition.dataset_manifest(prepared.definition),
    sources,
    transformations,
    calendars,
    rules,
    actions,
    definition.execution_receipt(prepared.definition),
    costs,
    input.seed_and_random_stream_facts,
    list.append(
      mechanical_effect_facts(prepared),
      input.additional_effect_facts,
    ),
    outputs,
    checkpoints,
    input.entitlement_limitations,
    omitted,
    unknown,
    conflicting,
    input.export_provenance,
    input.privacy_policy,
  )
  |> result.map_error(fn(error) { ManifestFailure(string.inspect(error)) })
}

fn dependencies(
  field: String,
  values: List(decode.DependencyInput),
) -> Result(List(reproduction.Dependency), DomainError) {
  list.try_map(values, fn(value) {
    use receipt <- result.try(sha_fact(
      field <> ".receiptHash",
      value.receipt_hash,
    ))
    Ok(reproduction.Dependency(receipt, value.reason))
  })
}

fn export_page(
  remaining: List(event.Event),
  absolute_offset: Int,
  maximum_events: Int,
  maximum_characters: Int,
) -> Result(List(event.Event), DomainError) {
  export_page_loop(
    remaining,
    absolute_offset,
    maximum_events,
    maximum_characters,
    0,
    0,
    [],
  )
}

fn export_page_loop(
  remaining: List(event.Event),
  absolute_offset: Int,
  maximum_events: Int,
  maximum_characters: Int,
  selected_count: Int,
  selected_characters: Int,
  reversed: List(event.Event),
) -> Result(List(event.Event), DomainError) {
  case remaining, selected_count >= maximum_events {
    [], _ -> Ok(list.reverse(reversed))
    _, True -> Ok(list.reverse(reversed))
    [value, ..rest], False -> {
      let line_characters = string.length(event.encode(value)) + 1
      case selected_characters + line_characters <= maximum_characters {
        True ->
          export_page_loop(
            rest,
            absolute_offset,
            maximum_events,
            maximum_characters,
            selected_count + 1,
            selected_characters + line_characters,
            [value, ..reversed],
          )
        False if selected_count == 0 ->
          Error(ExportEventTooLarge(
            absolute_offset,
            line_characters,
            maximum_characters,
          ))
        False -> Ok(list.reverse(reversed))
      }
    }
  }
}

fn mechanical_effect_facts(prepared: PreparedRun) -> List(String) {
  let decode.BudgetInput(events, bytes, wall, sessions) = prepared.input.budget
  [
    "cadence_policy=" <> cadence_policy,
    "maximum_events=" <> int.to_string(events),
    "maximum_bytes=" <> int.to_string(bytes),
    "maximum_wall_time_milliseconds=" <> int.to_string(wall),
    "maximum_sessions=" <> int.to_string(sessions),
    "consumed_events="
      <> int.to_string(scripted.processed_events(prepared.result)),
    "retained_events="
      <> int.to_string(fold.revision(scripted.state(prepared.result))),
    "omitted_events=" <> int.to_string(scripted.omitted_events(prepared.result)),
    "stop=" <> stop_name(scripted.stop(prepared.result)),
  ]
}

fn consumed_costs(
  events: List(PreparedEvent),
  consumed: Int,
) -> #(Int, Int, Int) {
  events
  |> list.take(consumed)
  |> list.fold(#(0, 0, 0), fn(acc, value) {
    #(
      acc.0 + value.encoded_bytes,
      acc.1 + value.elapsed_milliseconds,
      acc.2 + value.session_increment,
    )
  })
}

fn costs_json(value: #(Int, Int, Int)) -> Json {
  json.object([
    #("encodedBytes", json.int(value.0)),
    #("elapsedMilliseconds", json.int(value.1)),
    #("sessions", json.int(value.2)),
  ])
}

fn definition_json(value: definition.RunDefinition) -> Json {
  json.object([
    #("runId", json.string(definition.id(value))),
    #("contentHash", wire.sha_json(definition.digest(value))),
    #("version", json.string(definition.version(value))),
    #("universeManifest", wire.sha_json(definition.universe_manifest(value))),
    #("datasetManifest", wire.sha_json(definition.dataset_manifest(value))),
    #("partitionReceipt", wire.sha_json(definition.partition_receipt(value))),
    #("executionReceipt", wire.sha_json(definition.execution_receipt(value))),
  ])
}

fn budget_json(value: decode.BudgetInput) -> Json {
  let decode.BudgetInput(events, bytes, wall, sessions) = value
  json.object([
    #("maximum_events", json.int(events)),
    #("maximum_bytes", json.int(bytes)),
    #("maximum_wall_time_milliseconds", json.int(wall)),
    #("maximum_sessions", json.int(sessions)),
  ])
}

fn cancellation_input_json(value: decode.CancellationInput) -> Json {
  case value {
    decode.Continue -> json.object([#("kind", json.string("continue"))])
    decode.CancelBefore(clock, at, by) ->
      json.object([
        #("kind", json.string("cancel_before")),
        #("replay_clock", json.int(clock)),
        #("cancelled_at", json.int(at)),
        #("cancelled_by", json.string(by)),
      ])
  }
}

fn stop_json(value: scripted.Stop) -> Json {
  case value {
    scripted.InputExhausted ->
      json.object([
        #("kind", json.string("input_exhausted")),
        #("continuationReplayClock", json.null()),
      ])
    scripted.BudgetTruncated(reason, clock) ->
      json.object([
        #("kind", json.string("budget_truncated")),
        #("reason", json.string(reason)),
        #("continuationReplayClock", json.int(clock)),
      ])
    scripted.Cancelled(at, by, clock) ->
      json.object([
        #("kind", json.string("cancelled")),
        #("cancelledAtUnixMilliseconds", json.int(time.unix_milliseconds(at))),
        #("cancelledBy", json.string(by)),
        #("continuationReplayClock", json.int(clock)),
      ])
  }
}

fn stop_name(value: scripted.Stop) -> String {
  case value {
    scripted.InputExhausted -> "input_exhausted"
    scripted.BudgetTruncated(reason, clock) ->
      "budget_truncated:" <> reason <> ":replay_clock=" <> int.to_string(clock)
    scripted.Cancelled(at, by, clock) ->
      "cancelled:at="
      <> int.to_string(time.unix_milliseconds(at))
      <> ":by="
      <> by
      <> ":replay_clock="
      <> int.to_string(clock)
  }
}

fn inspected_event_json(value: event.Event, include_payload: Bool) -> Json {
  json.object([
    #("eventId", json.string(event.event_id(value))),
    #("kind", json.string(event.kind_name(event.kind(value)))),
    #("replayClock", json.int(event.replay_clock(value))),
    #("semanticContentHash", wire.sha_json(event.semantic_content_hash(value))),
    #(
      "canonicalContentHash",
      wire.sha_json(event.canonical_content_hash(value)),
    ),
    #("canonicalEnvelopeBytes", json.int(string.byte_size(event.encode(value)))),
    #("eventEnvelope", case include_payload {
      True -> event.as_json(value)
      False -> json.null()
    }),
  ])
}

fn event_kind_counts(values: List(event.Event)) -> Json {
  json.array(
    [
      event_kind_count(values, event.UniverseMembershipAvailable),
      event_kind_count(values, event.MarketObservationAvailable),
      event_kind_count(values, event.MarketObservationCorrected),
      event_kind_count(values, event.FeatureResultProduced),
      event_kind_count(values, event.FeatureResultOmitted),
      event_kind_count(values, event.StrategyPredicateFact),
      event_kind_count(values, event.DesiredInstructionDeclared),
      event_kind_count(values, event.ExecutionBranchEmitted),
      event_kind_count(values, event.PositionLedgerChanged),
      event_kind_count(values, event.BenchmarkObservationAvailable),
      event_kind_count(values, event.RunCompleted),
      event_kind_count(values, event.RunTruncated),
      event_kind_count(values, event.RunCancelled),
      event_kind_count(values, event.RunResumed),
    ],
    fn(value) { value },
  )
}

fn event_kind_count(values: List(event.Event), kind: event.Kind) -> Json {
  json.object([
    #("kind", json.string(event.kind_name(kind))),
    #(
      "count",
      json.int(
        values
        |> list.filter(fn(value) { event.kind(value) == kind })
        |> list.length,
      ),
    ),
  ])
}

fn ordering_fact_json(value: fold.OrderingFact) -> Json {
  case value {
    fold.OrderedPair(left, right) ->
      json.object([
        #("state", json.string("ordered")),
        #("leftEventId", json.string(left)),
        #("rightEventId", json.string(right)),
      ])
    fold.AmbiguousOrdering(left, right, reason, alternatives) ->
      json.object([
        #("state", json.string("ambiguous")),
        #("leftEventId", json.string(left)),
        #("rightEventId", json.string(right)),
        #("reason", json.string(reason)),
        #("alternatives", json.array(alternatives, json.string)),
      ])
  }
}

fn validate_page(
  offset: Int,
  limit: Int,
  count: Int,
) -> Result(Nil, DomainError) {
  use _ <- result.try(validate_offset(offset, count))
  case limit >= 1 && limit <= 200 {
    True -> Ok(Nil)
    False -> Error(InvalidField("limit", "expected 1..200"))
  }
}

fn validate_offset(offset: Int, count: Int) -> Result(Nil, DomainError) {
  case offset >= 0 && offset <= count {
    True -> Ok(Nil)
    False -> Error(PageOutside(offset, count))
  }
}

fn exact_text(field: String, value: String) -> Result(Nil, DomainError) {
  case
    value == string.trim(value),
    string.length(value) >= 1,
    string.length(value) <= 65_536,
    string.contains(value, "\n"),
    string.contains(value, "\r")
  {
    True, True, True, False, False -> Ok(Nil)
    _, _, _, _, _ ->
      Error(InvalidField(
        field,
        "must be trimmed, non-empty, newline-free, and at most 65536 characters",
      ))
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
