import finance_core/decimal
import finance_core/identifier
import finance_core/time
import finance_execution/instruction
import finance_execution/tape_scenario_decode as decode
import finance_execution/tape_simulation
import finance_provenance/hash
import finance_provenance/identity
import finance_tape
import finance_track
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub opaque type ScenarioResult {
  ScenarioResult(summary: String, details: Json)
}

pub type ScenarioError {
  InvalidField(field: String, reason: String)
  TapeError(error: finance_tape.TapeError)
  SimulationError(error: tape_simulation.TapeSimulationError)
}

pub fn run(
  input: decode.Input,
  expected_track: String,
  expected_provider: Option(String),
) -> Result(ScenarioResult, ScenarioError) {
  use _ <- result.try(valid_text("operationId", input.operation_id, 1, 500))
  use _ <- result.try(valid_text("provider", input.provider, 1, 200))
  use _ <- result.try(case expected_provider {
    Some(value) if value != input.provider ->
      Error(InvalidField("provider", "expected exactly " <> value))
    _ -> Ok(Nil)
  })
  use track <- result.try(
    finance_track.from_name(input.track)
    |> result.map_error(fn(_) {
      InvalidField("track", "must be exactly cn, hk, or us")
    }),
  )
  use _ <- result.try(case input.track == expected_track {
    True -> Ok(Nil)
    False -> Error(InvalidField("track", "expected exactly " <> expected_track))
  })
  use mic <- result.try(
    identifier.mic(input.mic)
    |> result.map_error(fn(_) { InvalidField("mic", "must be a valid MIC") }),
  )
  use provider_receipt <- result.try(parse_hash(
    "providerReceiptHash",
    input.provider_receipt_hash,
  ))
  use condition_reference <- result.try(parse_hash(
    "conditionReferenceHash",
    input.condition_reference_hash,
  ))
  use instruction_receipt <- result.try(parse_hash(
    "instructionReceiptHash",
    input.instruction_receipt_hash,
  ))
  use account_reference <- result.try(parse_hash(
    "accountReference",
    input.account_reference,
  ))
  use rule_references <- result.try(parse_hashes(
    "ruleReferences",
    input.rule_references,
    True,
  ))
  use capability_references <- result.try(parse_hashes(
    "capabilityReferences",
    input.capability_references,
    True,
  ))
  use quantity <- result.try(parse_decimal("quantity", input.quantity_lexeme))
  use limit_price <- result.try(parse_decimal(
    "limitPrice",
    input.limit_price_lexeme,
  ))
  use side <- result.try(case input.side {
    "buy" -> Ok(instruction.Buy)
    "sell" -> Ok(instruction.Sell)
    _ -> Error(InvalidField("side", "must be buy or sell"))
  })
  use activation <- result.try(parse_optional_instant(
    "activationUnixMilliseconds",
    input.activation_unix_milliseconds,
  ))
  use expiry <- result.try(parse_optional_instant(
    "expiryUnixMilliseconds",
    input.expiry_unix_milliseconds,
  ))
  use desired <- result.try(
    instruction.desired(
      instruction_id: input.instruction_id,
      instruction_receipt: instruction_receipt,
      track: track,
      listing_id: input.listing_id,
      mic: input.mic,
      account_scope: "sha256:" <> input.account_reference,
      currency: input.currency,
      side: side,
      intent: None,
      quantity: quantity,
      quantity_unit: instruction.Shares,
      order_behavior: instruction.Limit(limit_price),
      time_in_force: instruction.Day,
      requested_session: Some(instruction.Regular),
      activation_time: activation,
      expiry_time: expiry,
      timezone: input.timezone,
      rule_references: rule_references,
      capability_references: capability_references,
      account_references: [account_reference],
      retained_alternatives: instruction.AlternativesNotApplicable(
        "one exact non-executable limit scenario",
      ),
    )
    |> result.map_error(fn(_) {
      InvalidField("instruction", "failed typed desired-instruction laws")
    }),
  )
  use coverage <- result.try(parse_coverage(
    input.coverage,
    input.coverage_reason,
    provider_receipt,
  ))
  use events <- result.try(input.events |> list.try_map(parse_event))
  use packet <- result.try(
    finance_tape.packet(
      track: track,
      listing_id: input.listing_id,
      mic: mic,
      session_id: input.session_id,
      provider: input.provider,
      feed: "transaction_tape",
      entitlement: input.entitlement,
      licence: input.licence,
      coverage: coverage,
      condition_coverage: finance_tape.DocumentedConditions(
        input.condition_codes,
        condition_reference,
      ),
      maximum_events: input.maximum_events,
      events: events,
    )
    |> result.map_error(TapeError),
  )
  use policy <- result.try(
    tape_simulation.eligibility_policy(
      input.eligible_venue_lexemes,
      input.eligible_condition_codes,
      input.allow_unconditioned_events,
    )
    |> result.map_error(SimulationError),
  )
  use simulation <- result.try(
    tape_simulation.simulate(desired, packet, policy)
    |> result.map_error(SimulationError),
  )
  let projection = simulation_json(input, simulation, provider_receipt)
  use receipt <- result.try(case projection |> json.to_string |> hash.text {
    Ok(value) -> Ok(value)
    Error(_) -> Error(InvalidField("scenarioReceipt", "could not hash result"))
  })
  Ok(ScenarioResult(
    input.track
      <> " deterministic transaction-tape possible-fill scenario | "
      <> input.listing_id,
    json.object([
      #("maturity", json.string("experimental")),
      #("contractVersion", json.string("transaction_tape_possible_fill_v1")),
      #("operationId", json.string(input.operation_id)),
      #("result", projection),
      #("scenarioReceipt", json.string(identity.sha256_value(receipt))),
      #(
        "providerDependency",
        json.object([
          #("provider", json.string(input.provider)),
          #("mode", json.string("explicit_external_transaction_tape")),
          #("requiredAtRuntime", json.bool(True)),
          #("adapterBundled", json.bool(False)),
          #("sdkBundled", json.bool(False)),
          #("credentialAcceptedByPlugin", json.bool(False)),
        ]),
      ),
      #("networkPerformed", json.bool(False)),
      #("brokerAuthorityAccepted", json.bool(False)),
      #("providerAuthenticated", json.bool(False)),
      #("executable", json.bool(False)),
    ]),
  ))
}

pub fn summary(value: ScenarioResult) -> String {
  value.summary
}

pub fn details(value: ScenarioResult) -> Json {
  value.details
}

pub fn error_message(value: ScenarioError) -> String {
  case value {
    InvalidField(field, reason) ->
      "Invalid possible-fill scenario " <> field <> ": " <> reason
    TapeError(error) -> finance_tape.error_message(error)
    SimulationError(error) -> tape_simulation.error_message(error)
  }
}

fn parse_event(
  value: decode.EventInput,
) -> Result(finance_tape.Event, ScenarioError) {
  use clocks <- result.try(
    finance_tape.clocks(
      value.exchange_unix_milliseconds,
      value.provider_unix_milliseconds,
      value.retrieved_unix_milliseconds,
    )
    |> result.map_error(TapeError),
  )
  use receipt <- result.try(parse_hash(
    "events[].rawReceiptHash",
    value.raw_receipt_hash,
  ))
  finance_tape.event(
    event_id: value.event_id,
    trade_id: value.trade_id,
    kind: finance_tape.OriginalTrade,
    price: finance_tape.KnownLexeme(value.price_lexeme),
    size: finance_tape.KnownLexeme(value.size_lexeme),
    condition_codes: value.condition_codes,
    venue_lexeme: value.venue_lexeme,
    clocks: clocks,
    sequence: finance_tape.Sequenced(
      value.sequence_scope,
      value.sequence_lexeme,
    ),
    raw_receipt_hash: receipt,
  )
  |> result.map_error(TapeError)
}

fn parse_coverage(
  value: String,
  reason: Option(String),
  receipt: identity.Sha256,
) -> Result(finance_tape.Coverage, ScenarioError) {
  case value, reason {
    "provider_declared_complete", None ->
      Ok(finance_tape.ProviderDeclaredComplete(receipt))
    "bounded_partial", Some(reason) -> Ok(finance_tape.BoundedPartial(reason))
    "unknown", Some(reason) -> Ok(finance_tape.UnknownCoverage(reason))
    _, _ ->
      Error(InvalidField(
        "coverage",
        "requires matching provider_declared_complete, bounded_partial, or unknown fields",
      ))
  }
}

fn parse_decimal(
  field: String,
  value: String,
) -> Result(decimal.Decimal, ScenarioError) {
  decimal.parse(value)
  |> result.map_error(fn(_) {
    InvalidField(field, "must be an exact decimal lexeme")
  })
}

fn parse_optional_instant(
  field: String,
  value: Option(Int),
) -> Result(Option(time.Instant), ScenarioError) {
  case value {
    None -> Ok(None)
    Some(value) ->
      time.instant(value)
      |> result.map(Some)
      |> result.map_error(fn(_) {
        InvalidField(field, "is outside the supported range")
      })
  }
}

fn parse_hash(
  field: String,
  value: String,
) -> Result(identity.Sha256, ScenarioError) {
  identity.sha256(value)
  |> result.map_error(fn(_) {
    InvalidField(field, "must be a SHA-256 hex digest")
  })
}

fn parse_hashes(
  field: String,
  values: List(String),
  require_nonempty: Bool,
) -> Result(List(identity.Sha256), ScenarioError) {
  use _ <- result.try(case require_nonempty && list.is_empty(values) {
    True -> Error(InvalidField(field, "must contain at least one receipt"))
    False -> Ok(Nil)
  })
  values |> list.try_map(fn(value) { parse_hash(field <> "[]", value) })
}

fn valid_text(
  field: String,
  value: String,
  minimum: Int,
  maximum: Int,
) -> Result(Nil, ScenarioError) {
  let size = string.byte_size(value)
  case string.trim(value) == value && size >= minimum && size <= maximum {
    True -> Ok(Nil)
    False ->
      Error(InvalidField(field, "must be trimmed and within its byte budget"))
  }
}

fn simulation_json(
  input: decode.Input,
  value: tape_simulation.TapeSimulation,
  provider_receipt: identity.Sha256,
) -> Json {
  json.object([
    #("model", json.string(tape_simulation.model(value))),
    #("track", json.string(input.track)),
    #("listingId", json.string(input.listing_id)),
    #("mic", json.string(input.mic)),
    #("sessionId", json.string(tape_simulation.session_id(value))),
    #("provider", json.string(tape_simulation.provider(value))),
    #("feed", json.string(tape_simulation.feed(value))),
    #(
      "providerReceiptHash",
      json.string(identity.sha256_value(provider_receipt)),
    ),
    #("side", json.string(instruction.side_name(tape_simulation.side(value)))),
    #(
      "limitPrice",
      json.string(decimal.to_string(tape_simulation.limit_price(value))),
    ),
    #(
      "requestedQuantity",
      json.string(decimal.to_string(tape_simulation.requested_quantity(value))),
    ),
    #(
      "observedCandidateQuantity",
      json.string(
        decimal.to_string(tape_simulation.observed_candidate_quantity(value)),
      ),
    ),
    #(
      "compatibleFillQuantity",
      json.string(
        decimal.to_string(tape_simulation.compatible_fill_quantity(value)),
      ),
    ),
    #(
      "candidates",
      json.array(tape_simulation.candidates(value), candidate_json),
    ),
    #("excluded", json.array(tape_simulation.excluded(value), excluded_json)),
    #("branches", json.array(tape_simulation.branches(value), branch_json)),
    #(
      "providerDeclaredComplete",
      json.bool(tape_simulation.provider_declared_complete(value)),
    ),
    #(
      "sequenceIssueCount",
      json.int(tape_simulation.sequence_issue_count(value)),
    ),
    #(
      "conditionDocumentationComplete",
      json.bool(tape_simulation.condition_documentation_complete(value)),
    ),
    #("resultKind", json.string("hypothetical_non_executing")),
    #("fillObserved", json.bool(False)),
    #("queuePositionKnown", json.bool(False)),
  ])
}

fn candidate_json(value: tape_simulation.CandidateTrade) -> Json {
  let tape_simulation.CandidateTrade(
    event_id,
    trade_id,
    _,
    price,
    _,
    size,
    venue,
    conditions,
    event_time,
    clock,
    receipt,
  ) = value
  json.object([
    #("eventId", json.string(event_id)),
    #("tradeId", json.string(trade_id)),
    #("price", json.string(price)),
    #("size", json.string(size)),
    #("venueLexeme", json.string(venue)),
    #("conditionCodes", json.array(conditions, json.string)),
    #("eventTimeUnixMilliseconds", json.int(event_time)),
    #("eventClockBasis", json.string(clock_name(clock))),
    #("rawReceiptHash", json.string(identity.sha256_value(receipt))),
  ])
}

fn excluded_json(value: tape_simulation.ExcludedTrade) -> Json {
  let tape_simulation.ExcludedTrade(event_id, reason) = value
  json.object([
    #("eventId", json.string(event_id)),
    #("reason", json.string(reason)),
  ])
}

fn branch_json(value: tape_simulation.TapeBranch) -> Json {
  case value {
    tape_simulation.CompatibleNonFill(reason) ->
      json.object([
        #("kind", json.string("compatible_non_fill")),
        #("reason", json.string(reason)),
      ])
    tape_simulation.CompatibleFillUpTo(quantity, reason) ->
      json.object([
        #("kind", json.string("compatible_fill_up_to")),
        #("quantity", json.string(decimal.to_string(quantity))),
        #("reason", json.string(reason)),
      ])
  }
}

fn clock_name(value: tape_simulation.TapeClockBasis) -> String {
  case value {
    tape_simulation.ExchangeEventClock -> "exchange"
    tape_simulation.ProviderEventClock -> "provider"
    tape_simulation.RetrievalClock -> "retrieval"
  }
}
