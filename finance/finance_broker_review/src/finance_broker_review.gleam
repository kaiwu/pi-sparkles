import finance_broker_review/decode.{
  type EventInput, type FactInput, type ReviewInput,
}
import finance_broker_review/field
import finance_provenance/hash
import finance_provenance/identity
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string

pub opaque type Review {
  Review(summary: String, details: Json, receipt: String)
}

pub type ReviewError {
  InvalidField(field: String, reason: String)
  WrongProviderScope(field: String, expected: String, received: String)
  UnsupportedMode(received: String)
  BudgetExceeded(field: String, maximum: Int)
}

const maximum_facts = 200

const maximum_events = 500

pub fn review(
  input: ReviewInput,
  provider: String,
  expected_track: String,
  allowed_mode_environments: List(#(String, String)),
  required_missing_capabilities: List(String),
) -> Result(Review, ReviewError) {
  use _ <- result.try(valid_text("operationId", input.operation_id, 1, 500))
  use _ <- result.try(valid_text("provider", provider, 1, 100))
  use _ <- result.try(valid_text("environment", input.environment, 1, 100))
  use _ <- result.try(valid_hash("accountReference", input.account_reference))
  use _ <- result.try(valid_track(input.track))
  use _ <- result.try(case expected_track {
    "any" -> Ok(Nil)
    value if value == input.track -> Ok(Nil)
    value -> Error(WrongProviderScope("track", value, input.track))
  })
  use _ <- result.try(valid_text("listingId", input.listing_id, 1, 500))
  use _ <- result.try(valid_text("mic", input.mic, 1, 50))
  use _ <- result.try(valid_hash("sourceContentHash", input.source_content_hash))
  use _ <- result.try(
    case
      list.contains(allowed_mode_environments, #(input.mode, input.environment))
    {
      True -> Ok(Nil)
      False -> Error(UnsupportedMode(input.mode <> "/" <> input.environment))
    },
  )
  use _ <- result.try(within_budget("facts", input.facts, maximum_facts))
  use _ <- result.try(within_budget("events", input.events, maximum_events))
  use _ <- result.try(within_budget(
    "missingCapabilities",
    input.missing_capabilities,
    100,
  ))
  use _ <- result.try(case input.facts, input.events {
    [], [] ->
      Error(InvalidField(
        "evidence",
        "at least one fact or lifecycle observation is required",
      ))
    _, _ -> Ok(Nil)
  })
  use _ <- result.try(case input.mode, input.events {
    "non_executable_handoff", [_first, ..] ->
      Error(InvalidField(
        "events",
        "a non-executable handoff cannot contain external lifecycle observations",
      ))
    _, _ -> Ok(Nil)
  })
  use _ <- result.try(list.try_each(input.facts, validate_fact))
  use _ <- result.try(list.try_each(input.events, validate_event))
  let missing =
    list.append(required_missing_capabilities, input.missing_capabilities)
    |> list.unique
  use _ <- result.try(case missing {
    [] ->
      Error(InvalidField(
        "missingCapabilities",
        "must remain explicit for track_partial output",
      ))
    _ ->
      list.try_each(missing, fn(value) {
        valid_text("missingCapabilities[]", value, 1, 200)
      })
  })

  let duplicate_event_count = duplicate_event_count(input.events)
  let duplicate_fact_count = duplicate_fact_count(input.facts)
  let event_conflicts = conflicting_event_references(input.events)
  let fact_conflicts = conflicting_fact_names(input.facts)
  let state = case event_conflicts, fact_conflicts {
    [], [] -> "reviewed"
    _, _ -> "conflicting"
  }
  let latest_status = case list.last(input.events) {
    Ok(value) -> Some(value.status_lexeme)
    Error(_) -> None
  }
  let semantic =
    json.object([
      #("contractVersion", json.string("broker_review_v1")),
      #("provider", json.string(provider)),
      #("mode", json.string(input.mode)),
      #("environment", json.string(input.environment)),
      #("accountReference", json.string(input.account_reference)),
      #("track", json.string(input.track)),
      #("listingId", json.string(input.listing_id)),
      #("mic", json.string(input.mic)),
      #("sourceContentHash", json.string(input.source_content_hash)),
      #("facts", json.array(input.facts, fact_json)),
      #("events", json.array(input.events, event_json)),
      #("missingCapabilities", json.array(missing, json.string)),
    ])
  use digest <- result.try(case semantic |> json.to_string |> hash.text {
    Ok(value) -> Ok(identity.sha256_value(value))
    Error(_) ->
      Error(InvalidField(
        "semanticReceipt",
        "could not hash canonical projection",
      ))
  })
  let details =
    json.object([
      #("maturity", json.string("track_partial")),
      #("contractVersion", json.string("broker_review_v1")),
      #("operationId", json.string(input.operation_id)),
      #("state", json.string(state)),
      #("provider", json.string(provider)),
      #("mode", json.string(input.mode)),
      #("environment", json.string(input.environment)),
      #("accountReference", json.string(input.account_reference)),
      #("track", json.string(input.track)),
      #("listingId", json.string(input.listing_id)),
      #("mic", json.string(input.mic)),
      #("sourceContentHash", json.string(input.source_content_hash)),
      #("facts", json.array(input.facts, fact_json)),
      #("events", json.array(input.events, event_json)),
      #("duplicateEventCount", json.int(duplicate_event_count)),
      #("duplicateFactCount", json.int(duplicate_fact_count)),
      #("conflictingEventReferences", json.array(event_conflicts, json.string)),
      #("conflictingFactNames", json.array(fact_conflicts, json.string)),
      #("latestStatusLexeme", json.nullable(latest_status, json.string)),
      #("semanticReceipt", json.string(digest)),
      #("missingCapabilities", json.array(missing, json.string)),
      #("networkPerformed", json.bool(False)),
      #("brokerAuthorityAccepted", json.bool(False)),
      #("providerAuthenticated", json.bool(False)),
      #("sourceContentHashVerifiedAgainstBytes", json.bool(False)),
      #("executable", json.bool(False)),
    ])
  Ok(Review(
    "Reviewed bounded caller-owned evidence; result remains track_partial",
    details,
    digest,
  ))
}

pub fn summary(value: Review) -> String {
  value.summary
}

pub fn details(value: Review) -> Json {
  value.details
}

pub fn receipt(value: Review) -> String {
  value.receipt
}

pub fn error_message(value: ReviewError) -> String {
  case value {
    InvalidField(field, reason) ->
      "Invalid broker-review field " <> field <> ": " <> reason
    WrongProviderScope(field, expected, received) ->
      "Invalid broker-review "
      <> field
      <> ": expected "
      <> expected
      <> ", received "
      <> received
    UnsupportedMode(received) ->
      "Unsupported non-executing broker-review mode: " <> received
    BudgetExceeded(field, maximum) ->
      "Broker-review " <> field <> " exceeds maximum " <> int_to_string(maximum)
  }
}

fn validate_fact(value: FactInput) -> Result(Nil, ReviewError) {
  use _ <- result.try(valid_text("facts[].name", value.name, 1, 200))
  use _ <- result.try(case field.is_market_depth_name(value.name) {
    True ->
      Error(InvalidField(
        "facts[].name",
        "market-depth fields are outside every broker-review plugin scope",
      ))
    False -> Ok(Nil)
  })
  use _ <- result.try(
    case
      list.contains(
        ["known", "unknown", "unavailable", "conflicting", "not_applicable"],
        value.state,
      )
    {
      True -> Ok(Nil)
      False -> Error(InvalidField("facts[].state", "unsupported fact state"))
    },
  )
  use _ <- result.try(valid_hash(
    "facts[].sourceReference",
    value.source_reference,
  ))
  case value.state, value.value, value.unit {
    "known", Some(text), Some(unit) -> {
      use _ <- result.try(valid_text("facts[].value", text, 1, 4000))
      valid_text("facts[].unit", unit, 1, 100)
    }
    "known", _, _ ->
      Error(InvalidField("facts[]", "known facts require value and unit"))
    _, None, None -> Ok(Nil)
    _, _, _ ->
      Error(InvalidField("facts[]", "non-known facts forbid value and unit"))
  }
}

fn validate_event(value: EventInput) -> Result(Nil, ReviewError) {
  use _ <- result.try(valid_hash(
    "events[].eventReference",
    value.event_reference,
  ))
  use _ <- result.try(valid_text(
    "events[].statusLexeme",
    value.status_lexeme,
    1,
    500,
  ))
  use _ <- result.try(valid_hash(
    "events[].sourceReference",
    value.source_reference,
  ))
  case value.occurred_at_unix_milliseconds >= 0 {
    True -> Ok(Nil)
    False ->
      Error(InvalidField(
        "events[].occurredAtUnixMilliseconds",
        "must be non-negative",
      ))
  }
}

fn valid_track(value: String) -> Result(Nil, ReviewError) {
  case list.contains(["cn", "hk", "us"], value) {
    True -> Ok(Nil)
    False -> Error(InvalidField("track", "must be cn, hk, or us"))
  }
}

fn valid_hash(field: String, value: String) -> Result(Nil, ReviewError) {
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
) -> Result(Nil, ReviewError) {
  let normalized = string.trim(value)
  case
    string.length(normalized) >= minimum && string.length(normalized) <= maximum
  {
    True -> Ok(Nil)
    False -> Error(InvalidField(field, "outside bounded text length"))
  }
}

fn within_budget(
  field: String,
  values: List(value),
  maximum: Int,
) -> Result(Nil, ReviewError) {
  case list.length(values) <= maximum {
    True -> Ok(Nil)
    False -> Error(BudgetExceeded(field, maximum))
  }
}

fn duplicate_event_count(events: List(EventInput)) -> Int {
  events
  |> list.index_fold(0, fn(total, event, index) {
    let prior = list.take(events, index)
    case list.any(prior, fn(value) { value == event }) {
      True -> total + 1
      False -> total
    }
  })
}

fn duplicate_fact_count(facts: List(FactInput)) -> Int {
  facts
  |> list.index_fold(0, fn(total, fact, index) {
    let prior = list.take(facts, index)
    case list.any(prior, fn(value) { value == fact }) {
      True -> total + 1
      False -> total
    }
  })
}

fn conflicting_event_references(events: List(EventInput)) -> List(String) {
  events
  |> list.filter_map(fn(event) {
    case
      list.any(events, fn(other) {
        other.event_reference == event.event_reference && other != event
      })
    {
      True -> Ok(event.event_reference)
      False -> Error(Nil)
    }
  })
  |> list.unique
}

fn conflicting_fact_names(facts: List(FactInput)) -> List(String) {
  facts
  |> list.filter_map(fn(fact) {
    case
      list.any(facts, fn(other) { other.name == fact.name && other != fact })
    {
      True -> Ok(fact.name)
      False -> Error(Nil)
    }
  })
  |> list.unique
}

fn fact_json(value: FactInput) -> Json {
  json.object([
    #("name", json.string(value.name)),
    #("state", json.string(value.state)),
    #("value", json.nullable(value.value, json.string)),
    #("unit", json.nullable(value.unit, json.string)),
    #("sourceReference", json.string(value.source_reference)),
  ])
}

fn event_json(value: EventInput) -> Json {
  json.object([
    #("eventReference", json.string(value.event_reference)),
    #("statusLexeme", json.string(value.status_lexeme)),
    #(
      "occurredAtUnixMilliseconds",
      json.int(value.occurred_at_unix_milliseconds),
    ),
    #("sourceReference", json.string(value.source_reference)),
  ])
}

fn int_to_string(value: Int) -> String {
  int.to_string(value)
}
