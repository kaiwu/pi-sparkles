import finance_provenance/hash
import finance_provenance/identity
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub const event_type = "pi_sparkles_finance_cache.event.v1"

pub const maximum_active_entries = 200

pub const maximum_content_bytes = 1_000_000

pub const maximum_total_content_bytes = 20_000_000

pub opaque type Entry {
  Entry(
    cache_key_sha256: String,
    provider: String,
    source: String,
    request_semantic_sha256: String,
    created_at_milliseconds: Int,
    retrieved_at_milliseconds: Int,
    expires_at_milliseconds: Int,
    byte_size: Int,
    entitlement: String,
    licence: String,
    safe_request_identity: String,
    content_sha256: String,
    validation_state: String,
    content: String,
  )
}

pub type Event {
  Stored(Entry)
  Expired(
    cache_key_sha256: String,
    expected_content_sha256: String,
    expired_at_milliseconds: Int,
    reason: String,
    receipt_sha256: String,
  )
}

pub opaque type State {
  State(revision: Int, entries: List(Entry), expiry_receipts: List(String))
}

pub type Error {
  InvalidHash
  InvalidProvider
  InvalidSource
  InvalidTimes
  InvalidByteSize
  InvalidEntitlement
  InvalidLicence
  UnsafeRequestIdentity
  InvalidValidationState
  ContentLengthMismatch
  TooManyEntries
  TotalContentBudgetExceeded
  EntryNotFound
  ContentHashMismatch
  InvalidExpiryReason
}

pub fn entry(
  cache_key_sha256 cache_key: String,
  provider provider_value: String,
  source source_value: String,
  request_semantic_sha256 request_hash: String,
  created_at_milliseconds created_at: Int,
  retrieved_at_milliseconds retrieved_at: Int,
  expires_at_milliseconds expires_at: Int,
  byte_size bytes: Int,
  entitlement entitlement_value: String,
  licence licence_value: String,
  safe_request_identity request_identity: String,
  content_sha256 content_hash: String,
  validation_state validation: String,
  content content_value: String,
) -> Result(Entry, Error) {
  case
    valid_hash(cache_key)
    && valid_hash(request_hash)
    && valid_hash(content_hash),
    valid_text(provider_value, 100),
    valid_source(source_value),
    created_at >= 0 && created_at <= retrieved_at && retrieved_at <= expires_at,
    bytes >= 0 && bytes <= maximum_content_bytes,
    valid_text(entitlement_value, 200),
    valid_text(licence_value, 200),
    safe_identity(request_identity),
    list.contains(
      ["provider_decoded", "schema_validated", "content_bound_receipt"],
      validation,
    ),
    string.length(content_value) <= bytes
  {
    False, _, _, _, _, _, _, _, _, _ -> Error(InvalidHash)
    _, False, _, _, _, _, _, _, _, _ -> Error(InvalidProvider)
    _, _, False, _, _, _, _, _, _, _ -> Error(InvalidSource)
    _, _, _, False, _, _, _, _, _, _ -> Error(InvalidTimes)
    _, _, _, _, False, _, _, _, _, _ -> Error(InvalidByteSize)
    _, _, _, _, _, False, _, _, _, _ -> Error(InvalidEntitlement)
    _, _, _, _, _, _, False, _, _, _ -> Error(InvalidLicence)
    _, _, _, _, _, _, _, False, _, _ -> Error(UnsafeRequestIdentity)
    _, _, _, _, _, _, _, _, False, _ -> Error(InvalidValidationState)
    _, _, _, _, _, _, _, _, _, False -> Error(ContentLengthMismatch)
    True, True, True, True, True, True, True, True, True, True ->
      Ok(Entry(
        cache_key,
        provider_value,
        source_value,
        request_hash,
        created_at,
        retrieved_at,
        expires_at,
        bytes,
        entitlement_value,
        licence_value,
        request_identity,
        content_hash,
        validation,
        content_value,
      ))
  }
}

pub fn stored(value: Entry) -> Event {
  Stored(value)
}

pub fn expired(
  cache_key_sha256 cache_key: String,
  expected_content_sha256 content_hash: String,
  expired_at_milliseconds expired_at: Int,
  reason reason_value: String,
) -> Result(Event, Error) {
  case
    valid_hash(cache_key) && valid_hash(content_hash),
    expired_at >= 0,
    valid_text(reason_value, 200)
  {
    False, _, _ -> Error(InvalidHash)
    _, False, _ -> Error(InvalidTimes)
    _, _, False -> Error(InvalidExpiryReason)
    True, True, True -> {
      let canonical =
        "expire\n"
        <> cache_key
        <> "\n"
        <> content_hash
        <> "\n"
        <> int.to_string(expired_at)
        <> "\n"
        <> reason_value
      let assert Ok(digest) = hash.text(canonical)
      Ok(Expired(
        cache_key,
        content_hash,
        expired_at,
        reason_value,
        identity.sha256_value(digest),
      ))
    }
  }
}

pub fn empty() -> State {
  State(0, [], [])
}

pub fn replay(events: List(Event)) -> Result(State, Error) {
  list.try_fold(events, empty(), apply)
}

pub fn apply(state: State, event: Event) -> Result(State, Error) {
  case event {
    Stored(value) -> {
      let existing = find(state.entries, cache_key_sha256(value))
      let next = replace(state.entries, value)
      let grows = case existing {
        None -> True
        Some(_) -> False
      }
      case
        grows && list.length(next) > maximum_active_entries,
        total_bytes(next) > maximum_total_content_bytes
      {
        True, _ -> Error(TooManyEntries)
        _, True -> Error(TotalContentBudgetExceeded)
        False, False ->
          Ok(State(state.revision + 1, next, state.expiry_receipts))
      }
    }
    Expired(cache_key, expected_hash, _, _, receipt) ->
      case find(state.entries, cache_key) {
        None -> Error(EntryNotFound)
        Some(value) ->
          case content_sha256(value) == expected_hash {
            False -> Error(ContentHashMismatch)
            True ->
              Ok(
                State(
                  state.revision + 1,
                  list.filter(state.entries, fn(entry) {
                    cache_key_sha256(entry) != cache_key
                  }),
                  [receipt, ..state.expiry_receipts],
                ),
              )
          }
      }
  }
}

pub fn encode_event(event: Event) -> String {
  event_json(event) |> json.to_string
}

pub fn decode_event(value: String) -> Result(Event, json.DecodeError) {
  json.parse(value, event_decoder())
}

pub fn snapshot_json(state: State, include_content: Bool) -> json.Json {
  json.object([
    #("schema", json.string("pi-sparkles/finance-cache-snapshot")),
    #("schemaVersion", json.int(1)),
    #("revision", json.int(state.revision)),
    #(
      "activeEntries",
      json.array(state.entries, fn(value) { entry_json(value, include_content) }),
    ),
    #("activeEntryCount", json.int(list.length(state.entries))),
    #("activeContentBytes", json.int(total_bytes(state.entries))),
    #("expiryReceiptCount", json.int(list.length(state.expiry_receipts))),
    #(
      "expiryReceipts",
      json.array(list.reverse(state.expiry_receipts), json.string),
    ),
    #("sourceOfTruth", json.bool(False)),
  ])
}

pub fn revision(state: State) -> Int {
  state.revision
}

pub fn entries(state: State) -> List(Entry) {
  state.entries
}

pub fn expiry_receipts(state: State) -> List(String) {
  state.expiry_receipts
}

pub fn expiry_receipt(event: Event) -> Option(String) {
  case event {
    Expired(_, _, _, _, receipt) -> Some(receipt)
    Stored(_) -> None
  }
}

pub fn cache_key_sha256(value: Entry) -> String {
  value.cache_key_sha256
}

pub fn provider(value: Entry) -> String {
  value.provider
}

pub fn source(value: Entry) -> String {
  value.source
}

pub fn request_semantic_sha256(value: Entry) -> String {
  value.request_semantic_sha256
}

pub fn created_at_milliseconds(value: Entry) -> Int {
  value.created_at_milliseconds
}

pub fn retrieved_at_milliseconds(value: Entry) -> Int {
  value.retrieved_at_milliseconds
}

pub fn expires_at_milliseconds(value: Entry) -> Int {
  value.expires_at_milliseconds
}

pub fn byte_size(value: Entry) -> Int {
  value.byte_size
}

pub fn entitlement(value: Entry) -> String {
  value.entitlement
}

pub fn licence(value: Entry) -> String {
  value.licence
}

pub fn safe_request_identity(value: Entry) -> String {
  value.safe_request_identity
}

pub fn content_sha256(value: Entry) -> String {
  value.content_sha256
}

pub fn validation_state(value: Entry) -> String {
  value.validation_state
}

pub fn content(value: Entry) -> String {
  value.content
}

pub fn find_entry(state: State, cache_key: String) -> Option(Entry) {
  find(state.entries, cache_key)
}

pub fn provider_count(state: State, expected: String) -> Int {
  state.entries
  |> list.filter(fn(value) { value.provider == expected })
  |> list.length
}

pub fn entry_json(value: Entry, include_content: Bool) -> json.Json {
  json.object([
    #("cacheKeySha256", json.string(value.cache_key_sha256)),
    #("provider", json.string(value.provider)),
    #("source", json.string(value.source)),
    #("requestSemanticSha256", json.string(value.request_semantic_sha256)),
    #("createdAtUnixMilliseconds", json.int(value.created_at_milliseconds)),
    #("retrievedAtUnixMilliseconds", json.int(value.retrieved_at_milliseconds)),
    #("expiresAtUnixMilliseconds", json.int(value.expires_at_milliseconds)),
    #("byteSize", json.int(value.byte_size)),
    #("entitlement", json.string(value.entitlement)),
    #("licence", json.string(value.licence)),
    #("safeRequestIdentity", json.string(value.safe_request_identity)),
    #("contentSha256", json.string(value.content_sha256)),
    #("validationState", json.string(value.validation_state)),
    #("cached", json.bool(True)),
    #("sourceOfTruth", json.bool(False)),
    #("content", case include_content {
      True -> json.string(value.content)
      False -> json.null()
    }),
  ])
}

fn event_json(value: Event) -> json.Json {
  case value {
    Stored(entry) ->
      json.object([
        #("kind", json.string("stored")),
        #("entry", entry_json(entry, True)),
      ])
    Expired(cache_key, expected_hash, expired_at, reason, receipt) ->
      json.object([
        #("kind", json.string("expired")),
        #("cacheKeySha256", json.string(cache_key)),
        #("expectedContentSha256", json.string(expected_hash)),
        #("expiredAtUnixMilliseconds", json.int(expired_at)),
        #("reason", json.string(reason)),
        #("receiptSha256", json.string(receipt)),
      ])
  }
}

fn event_decoder() -> decode.Decoder(Event) {
  use kind <- decode.field("kind", decode.string)
  case kind {
    "stored" -> {
      use entry <- decode.field("entry", entry_decoder())
      decode.success(Stored(entry))
    }
    "expired" -> {
      use cache_key <- decode.field("cacheKeySha256", decode.string)
      use expected_hash <- decode.field("expectedContentSha256", decode.string)
      use expired_at <- decode.field("expiredAtUnixMilliseconds", decode.int)
      use reason <- decode.field("reason", decode.string)
      use supplied_receipt <- decode.field("receiptSha256", decode.string)
      let placeholder =
        Expired(cache_key, expected_hash, expired_at, reason, supplied_receipt)
      case expired(cache_key, expected_hash, expired_at, reason) {
        Ok(Expired(_, _, _, _, calculated)) if calculated == supplied_receipt ->
          decode.success(placeholder)
        _ ->
          decode.failure(
            placeholder,
            "valid content-bound targeted expiry event",
          )
      }
    }
    _ -> decode.failure(Stored(placeholder_entry()), "finance cache event kind")
  }
}

fn entry_decoder() -> decode.Decoder(Entry) {
  use cache_key <- decode.field("cacheKeySha256", decode.string)
  use provider <- decode.field("provider", decode.string)
  use source <- decode.field("source", decode.string)
  use request_hash <- decode.field("requestSemanticSha256", decode.string)
  use created <- decode.field("createdAtUnixMilliseconds", decode.int)
  use retrieved <- decode.field("retrievedAtUnixMilliseconds", decode.int)
  use expires <- decode.field("expiresAtUnixMilliseconds", decode.int)
  use bytes <- decode.field("byteSize", decode.int)
  use entitlement <- decode.field("entitlement", decode.string)
  use licence <- decode.field("licence", decode.string)
  use safe_identity <- decode.field("safeRequestIdentity", decode.string)
  use content_hash <- decode.field("contentSha256", decode.string)
  use validation <- decode.field("validationState", decode.string)
  use content <- decode.field("content", decode.string)
  case
    entry(
      cache_key,
      provider,
      source,
      request_hash,
      created,
      retrieved,
      expires,
      bytes,
      entitlement,
      licence,
      safe_identity,
      content_hash,
      validation,
      content,
    )
  {
    Ok(value) -> decode.success(value)
    Error(_) ->
      decode.failure(placeholder_entry(), "valid bounded finance cache entry")
  }
}

fn placeholder_entry() -> Entry {
  let hash = string.repeat("0", 64)
  Entry(
    hash,
    "invalid",
    "invalid",
    hash,
    0,
    0,
    0,
    0,
    "invalid",
    "invalid",
    "invalid",
    hash,
    "provider_decoded",
    "",
  )
}

fn find(values: List(Entry), key: String) -> Option(Entry) {
  case values {
    [] -> None
    [value, ..rest] ->
      case value.cache_key_sha256 == key {
        True -> Some(value)
        False -> find(rest, key)
      }
  }
}

fn replace(values: List(Entry), replacement: Entry) -> List(Entry) {
  [
    replacement,
    ..list.filter(values, fn(value) {
      value.cache_key_sha256 != replacement.cache_key_sha256
    })
  ]
}

fn total_bytes(values: List(Entry)) -> Int {
  list.fold(values, 0, fn(total, value) { total + value.byte_size })
}

fn valid_hash(value: String) -> Bool {
  string.length(value) == 64
  && value
  |> string.to_graphemes
  |> list.all(fn(character) { string.contains("0123456789abcdef", character) })
}

fn valid_text(value: String, maximum: Int) -> Bool {
  value != ""
  && string.trim(value) == value
  && string.length(value) <= maximum
  && !string.contains(value, "\r")
  && !string.contains(value, "\n")
}

fn valid_source(value: String) -> Bool {
  valid_text(value, 1000)
  && {
    string.starts_with(value, "https://")
    || string.starts_with(value, "http://")
  }
  && !string.contains(value, "@")
}

fn safe_identity(value: String) -> Bool {
  let lowered = string.lowercase(value)
  let has_sensitive_label =
    string.contains(lowered, "authorization")
    || string.contains(lowered, "api_key")
    || string.contains(lowered, "apikey")
    || string.contains(lowered, "secret")
    || string.contains(lowered, "token")
  valid_text(value, 500)
  && !string.contains(lowered, "bearer ")
  && { !has_sensitive_label || string.contains(lowered, "[redacted]") }
}
