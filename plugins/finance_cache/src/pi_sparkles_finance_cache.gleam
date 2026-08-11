import finance_cache_contract as cache
import gleam/dynamic/decode
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import pi
import pi/raw
import pi/schema
import pi/session
import pi/tool
import pi_sparkles_finance_cache/domain
import pi_sparkles_finance_cache/effect/environment

pub type InspectInput {
  InspectInput(provider: Option(String), maximum_entries: Int)
}

pub type ExportInput {
  ExportInput(cache_key_sha256: String, include_content: Bool)
}

pub type ExpireInput {
  ExpireInput(
    cache_key_sha256: String,
    expected_content_sha256: String,
    reason: String,
  )
}

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  tool.register(
    api,
    "finance_cache_inspect",
    "Inspect finance cache",
    "Inspect bounded branch-local cache receipts and provider/source usage without exposing cached content",
    "Cache entries are replay material, never source-of-truth or a freshness/correctness verdict",
    tool.parameters(inspect_schema(), inspect_decoder()),
    tool.Parallel,
    fn(_id, input, _signal, _updates, ctx) {
      case restore(ctx) {
        Error(message) -> tool.reject(message)
        Ok(state) -> {
          let selected =
            domain.select(
              cache.entries(state),
              input.provider,
              input.maximum_entries,
            )
          tool.text_result(
            "Finance cache revision "
              <> int.to_string(cache.revision(state))
              <> " | selected "
              <> int.to_string(list.length(selected))
              <> " / active "
              <> int.to_string(list.length(cache.entries(state))),
            inspect_json(state, selected),
          )
          |> promise.resolve
        }
      }
    },
  )

  tool.register(
    api,
    "finance_cache_export",
    "Export cached provider response",
    "Export one exact canonical cache receipt for offline replay, optionally including its bounded response content",
    "Requires the complete cache-key hash; export preserves provider rights and cached status",
    tool.parameters(export_schema(), export_decoder()),
    tool.Parallel,
    fn(_id, input, _signal, _updates, ctx) {
      case restore(ctx) {
        Error(message) -> tool.reject(message)
        Ok(state) ->
          case cache.find_entry(state, input.cache_key_sha256) {
            None ->
              tool.reject(
                "Exact finance cache entry was not found on this branch",
              )
            Some(entry) ->
              tool.text_result(
                "Cached replay export | "
                  <> cache.provider(entry)
                  <> " | "
                  <> cache.cache_key_sha256(entry),
                json.object([
                  #("schema", json.string("pi-sparkles/finance-cache-export")),
                  #("schemaVersion", json.int(1)),
                  #("offlineReplay", json.bool(True)),
                  #("entry", cache.entry_json(entry, input.include_content)),
                ]),
              )
              |> promise.resolve
          }
      }
    },
  )

  tool.register(
    api,
    "finance_cache_expire",
    "Expire exact finance cache entry",
    "Expire only one cache entry identified by both its cache-key hash and expected content hash; append a durable branch receipt",
    "There is no wildcard, provider-wide, path-based or automatic bulk deletion",
    tool.parameters(expire_schema(), expire_decoder()),
    tool.Sequential,
    fn(_id, input, _signal, _updates, ctx) {
      case restore(ctx) {
        Error(message) -> tool.reject(message)
        Ok(state) ->
          case
            cache.expired(
              input.cache_key_sha256,
              input.expected_content_sha256,
              environment.now_milliseconds(),
              input.reason,
            )
          {
            Error(error) ->
              tool.reject(
                "Cache expiry request was invalid: " <> error_name(error),
              )
            Ok(event) ->
              case cache.apply(state, event) {
                Error(error) ->
                  tool.reject(
                    "Cache expiry was rejected: " <> error_name(error),
                  )
                Ok(next) -> {
                  pi.append_entry(
                    api,
                    cache.event_type,
                    raw.dynamic(cache.encode_event(event)),
                  )
                  let receipt = case cache.expiry_receipt(event) {
                    Some(value) -> value
                    None -> ""
                  }
                  tool.text_result(
                    "Expired exact finance cache entry | receipt " <> receipt,
                    json.object([
                      #(
                        "schema",
                        json.string("pi-sparkles/finance-cache-expiry-receipt"),
                      ),
                      #("schemaVersion", json.int(1)),
                      #("action", json.string("expired_exact_entry")),
                      #("cacheKeySha256", json.string(input.cache_key_sha256)),
                      #(
                        "expectedContentSha256",
                        json.string(input.expected_content_sha256),
                      ),
                      #("receiptSha256", json.string(receipt)),
                      #("revision", json.int(cache.revision(next))),
                      #("persisted", json.bool(True)),
                    ]),
                  )
                  |> promise.resolve
                }
              }
          }
      }
    },
  )
  promise.resolve(Nil)
}

fn restore(ctx: pi.Context) -> Result(cache.State, String) {
  use entries <- result.try(
    session.custom_entries(
      session.manager(ctx),
      cache.event_type,
      decode.string,
    )
    |> result.map_error(fn(_) {
      "Finance cache event entries could not be decoded; cache tools fail closed"
    }),
  )
  use events <- result.try(decode_events(entries, []))
  cache.replay(events)
  |> result.map_error(fn(error) {
    "Finance cache event replay failed: " <> error_name(error)
  })
}

fn decode_events(
  entries: List(session.CustomEntry(String)),
  reversed: List(cache.Event),
) -> Result(List(cache.Event), String) {
  case entries {
    [] -> Ok(list.reverse(reversed))
    [entry, ..rest] ->
      case entry.data {
        None -> Error("Finance cache event entry had no payload")
        Some(payload) ->
          case cache.decode_event(payload) {
            Error(_) -> Error("Finance cache event payload was invalid")
            Ok(event) -> decode_events(rest, [event, ..reversed])
          }
      }
  }
}

fn inspect_json(state: cache.State, selected: List(cache.Entry)) -> json.Json {
  let all = cache.entries(state)
  json.object([
    #("schema", json.string("pi-sparkles/finance-cache-inspection")),
    #("schemaVersion", json.int(1)),
    #("revision", json.int(cache.revision(state))),
    #("activeEntryCount", json.int(list.length(all))),
    #("selectedEntryCount", json.int(list.length(selected))),
    #(
      "entries",
      json.array(selected, fn(value) { cache.entry_json(value, False) }),
    ),
    #(
      "providerUsage",
      json.array(domain.providers(all), fn(provider) {
        json.object([
          #("provider", json.string(provider)),
          #("activeEntryCount", json.int(cache.provider_count(state, provider))),
        ])
      }),
    ),
    #("expiryReceiptCount", json.int(list.length(cache.expiry_receipts(state)))),
    #("sourceOfTruth", json.bool(False)),
  ])
}

fn inspect_schema() -> schema.Schema {
  schema.object([
    schema.Optional("provider", schema.nullable(bounded_string(1, 100))),
    schema.Optional(
      "maximumEntries",
      schema.integer() |> schema.with_number_range(1.0, 200.0),
    ),
  ])
}

fn export_schema() -> schema.Schema {
  schema.object([
    schema.Required("cacheKeySha256", bounded_string(64, 64)),
    schema.Optional("includeContent", schema.boolean()),
  ])
}

fn expire_schema() -> schema.Schema {
  schema.object([
    schema.Required("cacheKeySha256", bounded_string(64, 64)),
    schema.Required("expectedContentSha256", bounded_string(64, 64)),
    schema.Required("reason", bounded_string(1, 200)),
  ])
}

fn inspect_decoder() -> decode.Decoder(InspectInput) {
  use provider <- decode.optional_field(
    "provider",
    None,
    decode.optional(decode.string),
  )
  use maximum <- decode.optional_field("maximumEntries", 50, decode.int)
  decode.success(InspectInput(provider, maximum))
}

fn export_decoder() -> decode.Decoder(ExportInput) {
  use key <- decode.field("cacheKeySha256", decode.string)
  use include <- decode.optional_field("includeContent", False, decode.bool)
  decode.success(ExportInput(key, include))
}

fn expire_decoder() -> decode.Decoder(ExpireInput) {
  use key <- decode.field("cacheKeySha256", decode.string)
  use content <- decode.field("expectedContentSha256", decode.string)
  use reason <- decode.field("reason", decode.string)
  decode.success(ExpireInput(key, content, reason))
}

fn bounded_string(minimum: Int, maximum: Int) -> schema.Schema {
  schema.string() |> schema.with_string_length(minimum, maximum)
}

fn error_name(error: cache.Error) -> String {
  case error {
    cache.InvalidHash -> "invalid_hash"
    cache.InvalidProvider -> "invalid_provider"
    cache.InvalidSource -> "invalid_source"
    cache.InvalidTimes -> "invalid_times"
    cache.InvalidByteSize -> "invalid_byte_size"
    cache.InvalidEntitlement -> "invalid_entitlement"
    cache.InvalidLicence -> "invalid_licence"
    cache.UnsafeRequestIdentity -> "unsafe_request_identity"
    cache.InvalidValidationState -> "invalid_validation_state"
    cache.ContentLengthMismatch -> "content_length_mismatch"
    cache.TooManyEntries -> "entry_budget_exceeded"
    cache.TotalContentBudgetExceeded -> "content_budget_exceeded"
    cache.EntryNotFound -> "entry_not_found"
    cache.ContentHashMismatch -> "content_hash_mismatch"
    cache.InvalidExpiryReason -> "invalid_expiry_reason"
  }
}
