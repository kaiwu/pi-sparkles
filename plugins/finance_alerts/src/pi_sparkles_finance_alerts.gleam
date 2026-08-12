import finance_local_import
import finance_local_state
import finance_monitoring/alerts
import finance_notification_scripted as notification
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/json
import gleam/list
import pi
import pi/raw
import pi/schema
import pi/tool

pub type PacketInput {
  PacketInput(
    journal_path: String,
    maximum_journal_bytes: Int,
    expected_revision: Int,
    event_id: String,
    idempotency_key: String,
    occurred_at_unix_ms: Int,
    privacy: String,
    packet_path: String,
    expected_sha256: String,
    maximum_packet_bytes: Int,
  )
}

pub type DisableInput {
  DisableInput(
    journal_path: String,
    maximum_journal_bytes: Int,
    expected_revision: Int,
    event_id: String,
    idempotency_key: String,
    monitor_id: String,
    occurred_at_unix_ms: Int,
    privacy: String,
    reason: String,
  )
}

pub type InspectInput {
  InspectInput(
    journal_path: String,
    maximum_journal_bytes: Int,
    monitor_id: String,
    include_private: Bool,
    maximum_events: Int,
  )
}

pub type NotifyInput {
  NotifyInput(
    journal_path: String,
    maximum_journal_bytes: Int,
    expected_revision: Int,
    event_id: String,
    idempotency_key: String,
    monitor_id: String,
    match_id: String,
    authorization_id: String,
    channel: String,
    destination_ref: String,
    attempt: Int,
    scripted_outcome: String,
    occurred_at_unix_ms: Int,
    privacy: String,
  )
}

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  register_packet(api, "alert_define", "Define or amend durable monitor", True)
  register_packet(
    api,
    "alert_evaluate",
    "Evaluate durable monitor batch",
    False,
  )
  register_disable(api)
  register_inspect(api)
  register_notify(api)
  promise.resolve(Nil)
}

fn register_packet(
  api: pi.ExtensionApi,
  name: String,
  label: String,
  definition: Bool,
) -> Nil {
  tool.register(
    api,
    name,
    label,
    case definition {
      True ->
        "Atomically append one complete versioned caller-authored company or portfolio monitor definition to explicit local JSONL with exact scope, predicate, temporal policy, dedupe, cooldown, budgets, entitlements, retention, notification authorization, correction lineage and content hash"
      False ->
        "Evaluate the current durable predicate over one exact content-bound observation batch and atomically append matched, not-matched, cannot-evaluate, duplicate, cooldown and match-budget facts without dropping observations"
    },
    "All monitor meaning, scope, thresholds, cadence, cooldown and response remain caller-owned; silence is not all-clear and notification is a separate exact authorization/effect",
    tool.parameters(packet_schema(), packet_decoder()),
    tool.Sequential,
    fn(_id, input, signal, _updates, _ctx) {
      process_packet(input, definition, raw.dynamic(signal))
    },
  )
}

fn process_packet(
  input: PacketInput,
  definition: Bool,
  signal: Dynamic,
) -> Promise(tool.ToolResult) {
  use packet <- promise.await(finance_local_import.read(
    input.packet_path,
    input.maximum_packet_bytes,
    signal,
  ))
  case packet {
    finance_local_import.Loaded(text, _) -> {
      use loaded <- promise.await(load(
        input.journal_path,
        input.maximum_journal_bytes,
        signal,
      ))
      case loaded {
        Error(message) -> tool.reject(message)
        Ok(#(original, state)) -> {
          let changed = case definition {
            True ->
              alerts.define(
                state,
                input.expected_revision,
                input.event_id,
                input.idempotency_key,
                input.occurred_at_unix_ms,
                input.privacy,
                text,
                input.expected_sha256,
              )
            False ->
              alerts.evaluate(
                state,
                input.expected_revision,
                input.event_id,
                input.idempotency_key,
                input.occurred_at_unix_ms,
                input.privacy,
                text,
                input.expected_sha256,
              )
          }
          case changed {
            Error(error) -> tool.reject(alerts.error_message(error))
            Ok(#(next, outcome, details)) ->
              persist(
                input.journal_path,
                input.maximum_journal_bytes,
                original,
                next,
                outcome,
                details,
                case definition {
                  True -> "Monitor definition"
                  False -> "Monitor evaluation"
                },
                signal,
              )
          }
        }
      }
    }
    finance_local_import.Truncated(_, total) ->
      tool.reject(
        "Alert packet exceeds maximumPacketBytes: " <> int.to_string(total),
      )
    finance_local_import.Cancelled ->
      tool.reject("Alert packet read was cancelled")
    finance_local_import.Missing -> tool.reject("Alert packet was not found")
    finance_local_import.InvalidUtf8 ->
      tool.reject("Alert packet requires strict UTF-8")
    finance_local_import.Failure(code) ->
      tool.reject("Alert packet read failed safely: " <> code)
    finance_local_import.InvalidResult ->
      tool.reject("Alert packet read returned an invalid effect result")
  }
}

fn register_disable(api: pi.ExtensionApi) -> Nil {
  tool.register(
    api,
    "alert_disable",
    "Disable durable monitor",
    "Append an immutable disable event for one exact durable monitor under compare-and-swap revision control; the definition and prior evaluations remain auditable",
    "Supply an explicit reason; disabling performs no source, notification, portfolio, or trading effect",
    tool.parameters(disable_schema(), disable_decoder()),
    tool.Sequential,
    fn(_id, input, signal, _updates, _ctx) {
      let DisableInput(
        path,
        maximum,
        expected,
        event_id,
        idempotency,
        monitor_id,
        occurred,
        privacy,
        reason,
      ) = input
      use loaded <- promise.await(load(path, maximum, raw.dynamic(signal)))
      case loaded {
        Error(message) -> tool.reject(message)
        Ok(#(original, state)) ->
          case
            alerts.disable(
              state,
              expected,
              event_id,
              idempotency,
              monitor_id,
              occurred,
              privacy,
              reason,
            )
          {
            Error(error) -> tool.reject(alerts.error_message(error))
            Ok(#(next, outcome)) ->
              case alerts.inspect(next, monitor_id, False, 20) {
                Error(error) -> tool.reject(alerts.error_message(error))
                Ok(details) ->
                  persist(
                    path,
                    maximum,
                    original,
                    next,
                    outcome,
                    details,
                    "Monitor disable",
                    raw.dynamic(signal),
                  )
              }
          }
      }
    },
  )
}

fn register_inspect(api: pi.ExtensionApi) -> Nil {
  tool.register(
    api,
    "alert_inspect",
    "Inspect durable monitor and audit events",
    "Replay one bounded user-owned append-only alert journal and return the current definition plus bounded definition, evaluation, disable and notification event envelopes with privacy filtering and a canonical receipt",
    "Inspection never polls a source, evaluates a new batch, sends a notification, or changes state",
    tool.parameters(inspect_schema(), inspect_decoder()),
    tool.Parallel,
    fn(_id, input, signal, _updates, _ctx) {
      let InspectInput(path, maximum, monitor_id, private, max_events) = input
      use loaded <- promise.await(load(path, maximum, raw.dynamic(signal)))
      case loaded {
        Error(message) -> tool.reject(message)
        Ok(#(_, state)) ->
          case alerts.inspect(state, monitor_id, private, max_events) {
            Error(error) -> tool.reject(alerts.error_message(error))
            Ok(details) ->
              tool.text_result(
                "Durable monitor "
                  <> monitor_id
                  <> " journalRevision="
                  <> int.to_string(alerts.revision(state)),
                details,
              )
              |> promise.resolve
          }
      }
    },
  )
}

fn register_notify(api: pi.ExtensionApi) -> Nil {
  tool.register(
    api,
    "alert_notify",
    "Deliver one explicitly authorized match notification",
    "Prove the exact current monitor authorization and durable match, invoke the deterministic scripted channel for one bounded attempt, then atomically journal delivered, rate-limited or failed status and provider receipt",
    "No default channel or destination exists; destinationRef is opaque, production credentials are not accepted, and notification never implies urgency or triggers a trade",
    tool.parameters(notify_schema(), notify_decoder()),
    tool.Sequential,
    fn(_id, input, signal, _updates, _ctx) {
      notify(input, raw.dynamic(signal))
    },
  )
}

fn notify(input: NotifyInput, signal: Dynamic) -> Promise(tool.ToolResult) {
  let NotifyInput(
    path,
    maximum,
    expected,
    event_id,
    idempotency,
    monitor_id,
    match_id,
    authorization_id,
    channel,
    destination,
    attempt,
    scripted,
    occurred,
    privacy,
  ) = input
  use loaded <- promise.await(load(path, maximum, signal))
  case loaded {
    Error(message) -> tool.reject(message)
    Ok(#(original, state)) ->
      case
        alerts.notification_retry(
          state,
          event_id,
          idempotency,
          monitor_id,
          match_id,
          authorization_id,
          channel,
          destination,
          attempt,
          scripted,
          occurred,
          privacy,
        )
      {
        Error(error) -> tool.reject(alerts.error_message(error))
        Ok(True) ->
          tool.text_result(
            "Notification already stored; external effect not repeated",
            json.object([
              #("monitorId", json.string(monitor_id)),
              #("matchId", json.string(match_id)),
              #("idempotencyKey", json.string(idempotency)),
              #("effectRepeated", json.bool(False)),
              #("journalRevision", json.int(alerts.revision(state))),
            ]),
          )
          |> promise.resolve
        Ok(False) ->
          case
            alerts.authorize_notification(
              state,
              monitor_id,
              match_id,
              authorization_id,
              channel,
              destination,
              attempt,
            )
          {
            Error(error) -> tool.reject(alerts.error_message(error))
            Ok(Nil) -> {
              use delivered <- promise.await(notification.deliver(
                channel,
                destination,
                attempt,
                scripted,
                signal,
              ))
              case notification_result(delivered) {
                Error(message) -> tool.reject(message)
                Ok(#(status, receipt)) ->
                  case
                    alerts.record_notification(
                      state,
                      expected,
                      event_id,
                      idempotency,
                      monitor_id,
                      match_id,
                      authorization_id,
                      channel,
                      destination,
                      attempt,
                      status,
                      receipt,
                      occurred,
                      privacy,
                    )
                  {
                    Error(error) -> tool.reject(alerts.error_message(error))
                    Ok(#(next, outcome, details)) ->
                      persist(
                        path,
                        maximum,
                        original,
                        next,
                        outcome,
                        details,
                        "Notification " <> status,
                        signal,
                      )
                  }
              }
            }
          }
      }
  }
}

fn notification_result(
  value: notification.Outcome,
) -> Result(#(String, String), String) {
  case value {
    notification.Delivered(receipt) -> Ok(#("delivered", receipt))
    notification.RateLimited(receipt) -> Ok(#("rate_limited", receipt))
    notification.Failed(receipt) -> Ok(#("failed", receipt))
    notification.Cancelled ->
      Error("Notification delivery was cancelled before journaling")
    notification.InvalidResult ->
      Error("Notification adapter returned an invalid result")
    notification.EffectFailure ->
      Error("Notification adapter effect failed safely")
  }
}

fn load(
  path: String,
  maximum: Int,
  signal: Dynamic,
) -> Promise(Result(#(String, alerts.State), String)) {
  use outcome <- promise.await(finance_local_state.read(path, maximum, signal))
  case outcome {
    finance_local_state.Missing -> promise.resolve(Ok(#("", alerts.empty())))
    finance_local_state.Loaded(text, _) ->
      case alerts.decode_jsonl(text) {
        Ok(state) -> promise.resolve(Ok(#(text, state)))
        Error(error) -> promise.resolve(Error(alerts.error_message(error)))
      }
    finance_local_state.Cancelled ->
      promise.resolve(Error("Alert journal read was cancelled"))
    finance_local_state.TooLarge(bytes, limit) ->
      promise.resolve(Error(
        "Alert journal exceeds maximumJournalBytes: "
        <> int.to_string(bytes)
        <> "/"
        <> int.to_string(limit),
      ))
    finance_local_state.InvalidUtf8 ->
      promise.resolve(Error("Alert journal requires strict UTF-8"))
    finance_local_state.Failure(code) ->
      promise.resolve(Error("Alert journal read failed safely: " <> code))
    finance_local_state.InvalidResult ->
      promise.resolve(Error("Alert journal read returned an invalid result"))
  }
}

fn persist(
  path: String,
  maximum: Int,
  original: String,
  next: alerts.State,
  outcome: alerts.AppendOutcome,
  details: json.Json,
  label: String,
  signal: Dynamic,
) -> Promise(tool.ToolResult) {
  case outcome {
    alerts.AlreadyStored(event_id) ->
      tool.text_result(
        label
          <> " already stored eventId="
          <> event_id
          <> " journalRevision="
          <> int.to_string(alerts.revision(next)),
        details,
      )
      |> promise.resolve
    alerts.Stored(event_id) -> {
      use replaced <- promise.await(finance_local_state.replace(
        path,
        original,
        alerts.encode_state(next),
        maximum,
        signal,
      ))
      case replaced {
        finance_local_state.Replaced(_) ->
          tool.text_result(
            label
              <> " stored eventId="
              <> event_id
              <> " journalRevision="
              <> int.to_string(alerts.revision(next)),
            details,
          )
          |> promise.resolve
        finance_local_state.Changed(bytes) ->
          tool.reject(
            "Alert journal changed concurrently; current bytes="
            <> int.to_string(bytes),
          )
        finance_local_state.Busy ->
          tool.reject(
            "Alert journal is busy; reload and retry with a fresh revision",
          )
        finance_local_state.CancelledReplace ->
          tool.reject("Alert journal replacement was cancelled")
        finance_local_state.TooLargeReplacement(bytes, limit) ->
          tool.reject(
            "Alert journal replacement exceeds maximumJournalBytes: "
            <> int.to_string(bytes)
            <> "/"
            <> int.to_string(limit),
          )
        finance_local_state.InvalidUtf8Current ->
          tool.reject("Alert journal changed to invalid UTF-8")
        finance_local_state.ReplaceFailure(code) ->
          tool.reject("Alert journal replacement failed safely: " <> code)
        finance_local_state.InvalidReplaceResult ->
          tool.reject("Alert journal replacement returned an invalid result")
      }
    }
  }
}

fn packet_schema() -> schema.Schema {
  schema.object(
    list.append(common_event_fields(), [
      schema.Required("packetPath", bounded_string(1, 4096)),
      schema.Required("expectedSha256", bounded_string(64, 64)),
      schema.Required("maximumPacketBytes", bounded_integer(1, 5_000_000)),
    ]),
  )
}

fn disable_schema() -> schema.Schema {
  schema.object(
    list.append(common_event_fields(), [
      schema.Required("monitorId", bounded_string(1, 500)),
      schema.Required("reason", bounded_string(1, 4000)),
    ]),
  )
}

fn inspect_schema() -> schema.Schema {
  schema.object([
    schema.Required("journalPath", bounded_string(1, 4096)),
    schema.Required("maximumJournalBytes", bounded_integer(1, 10_000_000)),
    schema.Required("monitorId", bounded_string(1, 500)),
    schema.Required("includePrivate", schema.boolean()),
    schema.Required("maximumEvents", bounded_integer(0, 10_000)),
  ])
}

fn notify_schema() -> schema.Schema {
  schema.object(
    list.append(common_event_fields(), [
      schema.Required("monitorId", bounded_string(1, 500)),
      schema.Required("matchId", bounded_string(1, 2000)),
      schema.Required("authorizationId", bounded_string(1, 500)),
      schema.Required("channel", schema.string_enum(["scripted_local"])),
      schema.Required("destinationRef", bounded_string(1, 500)),
      schema.Required("attempt", bounded_integer(1, 10)),
      schema.Required(
        "scriptedOutcome",
        schema.string_enum(["delivered", "rate_limited", "failed"]),
      ),
    ]),
  )
}

fn common_event_fields() -> List(schema.Property) {
  [
    schema.Required("journalPath", bounded_string(1, 4096)),
    schema.Required("maximumJournalBytes", bounded_integer(1, 10_000_000)),
    schema.Required("expectedRevision", bounded_integer(0, 10_000)),
    schema.Required("eventId", bounded_string(1, 500)),
    schema.Required("idempotencyKey", bounded_string(1, 500)),
    schema.Required("occurredAtUnixMilliseconds", safe_integer()),
    schema.Required(
      "privacy",
      schema.string_enum(["private", "review_visible", "exportable"]),
    ),
  ]
}

fn packet_decoder() -> decode.Decoder(PacketInput) {
  use path <- decode.field("journalPath", decode.string)
  use maximum <- decode.field("maximumJournalBytes", decode.int)
  use expected <- decode.field("expectedRevision", decode.int)
  use event_id <- decode.field("eventId", decode.string)
  use idempotency <- decode.field("idempotencyKey", decode.string)
  use occurred <- decode.field("occurredAtUnixMilliseconds", decode.int)
  use privacy <- decode.field("privacy", decode.string)
  use packet_path <- decode.field("packetPath", decode.string)
  use digest <- decode.field("expectedSha256", decode.string)
  use packet_maximum <- decode.field("maximumPacketBytes", decode.int)
  decode.success(PacketInput(
    path,
    maximum,
    expected,
    event_id,
    idempotency,
    occurred,
    privacy,
    packet_path,
    digest,
    packet_maximum,
  ))
}

fn disable_decoder() -> decode.Decoder(DisableInput) {
  use path <- decode.field("journalPath", decode.string)
  use maximum <- decode.field("maximumJournalBytes", decode.int)
  use expected <- decode.field("expectedRevision", decode.int)
  use event_id <- decode.field("eventId", decode.string)
  use idempotency <- decode.field("idempotencyKey", decode.string)
  use occurred <- decode.field("occurredAtUnixMilliseconds", decode.int)
  use privacy <- decode.field("privacy", decode.string)
  use monitor_id <- decode.field("monitorId", decode.string)
  use reason <- decode.field("reason", decode.string)
  decode.success(DisableInput(
    path,
    maximum,
    expected,
    event_id,
    idempotency,
    monitor_id,
    occurred,
    privacy,
    reason,
  ))
}

fn inspect_decoder() -> decode.Decoder(InspectInput) {
  use path <- decode.field("journalPath", decode.string)
  use maximum <- decode.field("maximumJournalBytes", decode.int)
  use monitor_id <- decode.field("monitorId", decode.string)
  use private <- decode.field("includePrivate", decode.bool)
  use events <- decode.field("maximumEvents", decode.int)
  decode.success(InspectInput(path, maximum, monitor_id, private, events))
}

fn notify_decoder() -> decode.Decoder(NotifyInput) {
  use path <- decode.field("journalPath", decode.string)
  use maximum <- decode.field("maximumJournalBytes", decode.int)
  use expected <- decode.field("expectedRevision", decode.int)
  use event_id <- decode.field("eventId", decode.string)
  use idempotency <- decode.field("idempotencyKey", decode.string)
  use occurred <- decode.field("occurredAtUnixMilliseconds", decode.int)
  use privacy <- decode.field("privacy", decode.string)
  use monitor_id <- decode.field("monitorId", decode.string)
  use match_id <- decode.field("matchId", decode.string)
  use authorization <- decode.field("authorizationId", decode.string)
  use channel <- decode.field("channel", decode.string)
  use destination <- decode.field("destinationRef", decode.string)
  use attempt <- decode.field("attempt", decode.int)
  use outcome <- decode.field("scriptedOutcome", decode.string)
  decode.success(NotifyInput(
    path,
    maximum,
    expected,
    event_id,
    idempotency,
    monitor_id,
    match_id,
    authorization,
    channel,
    destination,
    attempt,
    outcome,
    occurred,
    privacy,
  ))
}

fn bounded_string(minimum: Int, maximum: Int) -> schema.Schema {
  schema.string() |> schema.with_string_length(minimum, maximum)
}

fn bounded_integer(minimum: Int, maximum: Int) -> schema.Schema {
  schema.integer()
  |> schema.with_number_range(int.to_float(minimum), int.to_float(maximum))
}

fn safe_integer() -> schema.Schema {
  schema.integer() |> schema.with_number_range(0.0, 9_007_199_254_740_991.0)
}
