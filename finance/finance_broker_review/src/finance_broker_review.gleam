import finance_broker_review/decode.{
  type EventInput, type FactInput, type ReviewInput, FactInput,
}
import finance_broker_review/field
import finance_provenance/hash
import finance_provenance/identity
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
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

const maximum_payload_bytes = 250_000

const maximum_safe_unix_milliseconds = 9_007_199_254_740_991

pub fn review(
  input: ReviewInput,
  provider: String,
  expected_track: String,
  allowed_mode_environments: List(#(String, String)),
  required_missing_capabilities: List(String),
) -> Result(Review, ReviewError) {
  review_with_policy(
    input,
    provider,
    expected_track,
    allowed_mode_environments,
    required_missing_capabilities,
    False,
    "track_partial",
    True,
  )
}

/// Review evidence whose exact UTF-8 source bytes were hashed and matched to
/// `source_content_hash` by the caller before decoding.
pub fn review_content_bound(
  input: ReviewInput,
  provider: String,
  expected_track: String,
  allowed_mode_environments: List(#(String, String)),
  required_missing_capabilities: List(String),
) -> Result(Review, ReviewError) {
  review_with_policy(
    input,
    provider,
    expected_track,
    allowed_mode_environments,
    required_missing_capabilities,
    True,
    "track_partial",
    True,
  )
}

/// Review a packet emitted by a caller-selected external read-only provider
/// capability. The capability remains an explicit runtime dependency: this
/// package neither accepts its credentials nor bundles or invokes its SDK.
/// Unknown provider facts stay explicit, but the packet is not forced into the
/// historical `track_partial` backlog merely because the provider lives
/// outside the distribution.
pub fn review_explicit_capability(
  input: ReviewInput,
  provider: String,
  expected_track: String,
  allowed_mode_environments: List(#(String, String)),
) -> Result(Review, ReviewError) {
  review_with_policy(
    input,
    provider,
    expected_track,
    allowed_mode_environments,
    [],
    False,
    "experimental",
    False,
  )
}

/// Content-bound variant for a caller-owned local receipt whose exact UTF-8
/// bytes were hashed and matched before decoding.
pub fn review_explicit_capability_content_bound(
  input: ReviewInput,
  provider: String,
  expected_track: String,
  allowed_mode_environments: List(#(String, String)),
) -> Result(Review, ReviewError) {
  review_with_policy(
    input,
    provider,
    expected_track,
    allowed_mode_environments,
    [],
    True,
    "experimental",
    False,
  )
}

fn review_with_policy(
  input: ReviewInput,
  provider: String,
  expected_track: String,
  allowed_mode_environments: List(#(String, String)),
  required_missing_capabilities: List(String),
  source_content_hash_verified_against_bytes: Bool,
  maturity: String,
  require_missing_capabilities: Bool,
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
  use _ <- result.try(valid_track_mic(input.track, input.mic))
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
  use _ <- result.try(case missing, require_missing_capabilities {
    [], True ->
      Error(InvalidField(
        "missingCapabilities",
        "must remain explicit for track_partial output",
      ))
    _, _ ->
      list.try_each(missing, fn(value) {
        valid_text("missingCapabilities[]", value, 1, 200)
      })
  })
  let semantic = semantic_json(input, provider, missing)
  let semantic_text = json.to_string(semantic)
  use _ <- result.try(
    case
      string.byte_size(input.operation_id) + string.byte_size(semantic_text)
    {
      total if total <= maximum_payload_bytes -> Ok(Nil)
      _ -> Error(BudgetExceeded("payloadBytes", maximum_payload_bytes))
    },
  )

  let duplicate_event_count = duplicate_event_count(input.events)
  let duplicate_fact_count = duplicate_fact_count(input.facts)
  let event_conflicts = conflicting_event_references(input.events)
  let fact_conflicts = conflicting_fact_names(input.facts)
  let state = case event_conflicts, fact_conflicts {
    [], [] -> "reviewed"
    _, _ -> "conflicting"
  }
  let last_input_status = case list.last(input.events) {
    Ok(value) -> Some(value.status_lexeme)
    Error(_) -> None
  }
  let #(latest_occurred_at, latest_occurred_statuses) =
    latest_event_projection(input.events)
  use digest <- result.try(case hash.text(semantic_text) {
    Ok(value) -> Ok(identity.sha256_value(value))
    Error(_) ->
      Error(InvalidField(
        "semanticReceipt",
        "could not hash canonical projection",
      ))
  })
  let details =
    json.object([
      #("maturity", json.string(maturity)),
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
      #("lastInputStatusLexeme", json.nullable(last_input_status, json.string)),
      #("eventTimeOrder", json.string(event_time_order(input.events))),
      #(
        "latestOccurredAtUnixMilliseconds",
        json.nullable(latest_occurred_at, json.int),
      ),
      #(
        "latestOccurredStatusLexemes",
        json.array(latest_occurred_statuses, json.string),
      ),
      #("semanticReceipt", json.string(digest)),
      #("missingCapabilities", json.array(missing, json.string)),
      #(
        "providerDependency",
        json.object([
          #("mode", json.string("explicit_external_capability")),
          #("requiredAtRuntime", json.bool(True)),
          #("adapterBundled", json.bool(False)),
          #("sdkBundled", json.bool(False)),
          #("credentialAcceptedByPlugin", json.bool(False)),
          #("openDRequiredByPackage", json.bool(False)),
        ]),
      ),
      #("networkPerformed", json.bool(False)),
      #("brokerAuthorityAccepted", json.bool(False)),
      #("providerAuthenticated", json.bool(False)),
      #(
        "sourceContentHashVerifiedAgainstBytes",
        json.bool(source_content_hash_verified_against_bytes),
      ),
      #("executable", json.bool(False)),
    ])
  Ok(Review(
    case maturity {
      "track_partial" ->
        "Reviewed bounded caller-owned evidence; result remains track_partial"
      _ ->
        "Reviewed bounded evidence from an explicit external read-only provider capability"
    },
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

pub fn require_unique_known_fact_names(
  input: ReviewInput,
  required_names: List(String),
) -> Result(Nil, ReviewError) {
  let invalid =
    list.filter(required_names, fn(name) {
      let matches = list.filter(input.facts, fn(fact) { fact.name == name })
      case matches {
        [fact] -> fact.state != "known"
        _ -> True
      }
    })
  case invalid {
    [] -> Ok(Nil)
    _ ->
      Error(InvalidField(
        "facts",
        "requires exactly one known fact for: " <> string.join(invalid, ", "),
      ))
  }
}

/// Require one exact known fact that binds an external capability declaration.
/// This validates a normalized packet boundary; it does not authenticate the
/// provider that produced the packet.
pub fn require_unique_known_fact(
  input: ReviewInput,
  name: String,
  expected_value: String,
  expected_unit: String,
) -> Result(Nil, ReviewError) {
  case list.filter(input.facts, fn(fact) { fact.name == name }) {
    [FactInput(_, "known", Some(value), Some(unit), _)]
      if value == expected_value && unit == expected_unit
    -> Ok(Nil)
    _ ->
      Error(InvalidField(
        "facts",
        name
          <> " must bind exactly "
          <> expected_value
          <> " with unit "
          <> expected_unit,
      ))
  }
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
  use _ <- result.try(case field.is_sensitive_name(value.name) {
    True ->
      Error(InvalidField(
        "facts[].name",
        "credential, secret, and direct-account identifiers are forbidden",
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
  case
    value.occurred_at_unix_milliseconds >= 0
    && value.occurred_at_unix_milliseconds <= maximum_safe_unix_milliseconds
  {
    True -> Ok(Nil)
    False ->
      Error(InvalidField(
        "events[].occurredAtUnixMilliseconds",
        "must be a non-negative JavaScript-safe integer",
      ))
  }
}

fn valid_track(value: String) -> Result(Nil, ReviewError) {
  case list.contains(["cn", "hk", "us"], value) {
    True -> Ok(Nil)
    False -> Error(InvalidField("track", "must be cn, hk, or us"))
  }
}

fn valid_track_mic(track: String, mic: String) -> Result(Nil, ReviewError) {
  let normalized = mic |> string.trim |> string.uppercase
  let known_cn = ["XSHG", "XSHE", "XBSE"]
  case track {
    "cn" ->
      case list.contains(known_cn, normalized) {
        True -> Ok(Nil)
        False -> Error(WrongProviderScope("mic", "XSHG, XSHE, or XBSE", mic))
      }
    "hk" if normalized == "XHKG" -> Ok(Nil)
    "hk" -> Error(WrongProviderScope("mic", "XHKG", mic))
    "us" ->
      case list.contains(["XSHG", "XSHE", "XBSE", "XHKG"], normalized) {
        True -> Error(WrongProviderScope("mic", "a non-CN/HK MIC", mic))
        False -> Ok(Nil)
      }
    _ -> Ok(Nil)
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
    string.length(normalized) >= minimum
    && string.length(normalized) <= maximum
    && !field.has_control_characters(value)
    && !field.contains_sensitive_lexeme(value)
  {
    True -> Ok(Nil)
    False ->
      Error(InvalidField(
        field,
        "outside bounded plain-text policy or contains credential-shaped data",
      ))
  }
}

fn semantic_json(
  input: ReviewInput,
  provider: String,
  missing: List(String),
) -> Json {
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
}

fn event_time_order(events: List(EventInput)) -> String {
  case events {
    [] -> "not_applicable"
    [_] -> "not_applicable"
    [first, ..rest] ->
      event_time_order_loop(first.occurred_at_unix_milliseconds, rest)
  }
}

fn event_time_order_loop(previous: Int, events: List(EventInput)) -> String {
  case events {
    [] -> "nondecreasing"
    [event, ..] if event.occurred_at_unix_milliseconds < previous ->
      "nonmonotonic"
    [event, ..rest] ->
      event_time_order_loop(event.occurred_at_unix_milliseconds, rest)
  }
}

fn latest_event_projection(
  events: List(EventInput),
) -> #(Option(Int), List(String)) {
  case events {
    [] -> #(None, [])
    [first, ..rest] ->
      latest_event_projection_loop(
        first.occurred_at_unix_milliseconds,
        [first.status_lexeme],
        rest,
      )
  }
}

fn latest_event_projection_loop(
  latest: Int,
  statuses: List(String),
  events: List(EventInput),
) -> #(Option(Int), List(String)) {
  case events {
    [] -> #(Some(latest), list.unique(statuses))
    [event, ..rest] if event.occurred_at_unix_milliseconds > latest ->
      latest_event_projection_loop(
        event.occurred_at_unix_milliseconds,
        [event.status_lexeme],
        rest,
      )
    [event, ..rest] if event.occurred_at_unix_milliseconds == latest ->
      latest_event_projection_loop(
        latest,
        list.append(statuses, [event.status_lexeme]),
        rest,
      )
    [_, ..rest] -> latest_event_projection_loop(latest, statuses, rest)
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
