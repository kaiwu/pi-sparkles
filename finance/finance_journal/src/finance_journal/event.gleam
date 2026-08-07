import finance_core/time.{type Instant}
import finance_journal/information.{type Information}
import finance_provenance/hash
import finance_provenance/identity.{type Sha256}
import finance_track.{type Track}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub const schema_version = 1

pub const maximum_payload_characters = 65_536

pub const maximum_references = 64

pub type EventKind {
  Declaration
  ObservationReference
  ChecklistResponse
  ReviewConclusion
  Correction
  Redaction
  ImportMarker
  ExportMarker
}

pub type Attribution {
  UserDeclared(author_id: String)
  LlmDeclared(author_id: String, context_receipt: Option(Sha256))
  ImportedDeclaration(source: String)
  ProviderObserved(receipt: Sha256)
  BrokerReported(receipt: Sha256)
  SystemObserved(receipt: Sha256)
  Calculated(request_receipt: Sha256, result_receipt: Sha256)
}

pub type Privacy {
  Private
  ReviewVisible
  Exportable
}

/// Identity is explicit even when it is unavailable. Journal-wide and
/// track-wide reviews do not need to invent a listing.
pub type IdentityScope {
  JournalWide
  TrackWide(track: Track)
  ExactListing(
    track: Track,
    listing_id: String,
    mic: String,
    symbol: Information(String),
  )
  UnresolvedListing(
    track: Information(Track),
    listing_id: Information(String),
    mic: Information(String),
    symbol: Information(String),
  )
}

pub type Scope {
  Scope(
    identity: IdentityScope,
    workflow_id: Option(String),
    position_id: Option(String),
    review_id: Option(String),
  )
}

pub type Reference {
  Reference(kind: String, hash: Sha256)
}

pub opaque type Event {
  Event(
    journal_id: String,
    event_id: String,
    kind: EventKind,
    scope: Scope,
    attribution: Attribution,
    stage: Information(String),
    payload: String,
    occurrence_time: Information(Instant),
    recording_time: Instant,
    timezone: Information(String),
    privacy: Privacy,
    references: List(Reference),
    supersedes: Option(String),
    import_provenance: Information(String),
    idempotency_key: String,
    semantic_content_hash: Sha256,
    canonical_content_hash: Sha256,
  )
}

pub type EventError {
  InvalidText(field: String)
  InvalidInformation(field: String)
  PayloadTooLarge(received: Int, maximum: Int)
  TooManyReferences(received: Int, maximum: Int)
  DuplicateReference(kind: String, hash: String)
  SupersedesRequired
  SupersedesNotAllowed
  HashMismatch
  InvalidJson
}

pub fn new(
  journal_id journal_id_value: String,
  event_id event_id_value: String,
  kind kind_value: EventKind,
  scope scope_value: Scope,
  attribution attribution_value: Attribution,
  stage stage_value: Information(String),
  payload payload_value: String,
  occurrence_time occurrence_value: Information(Instant),
  recording_time recording_value: Instant,
  timezone timezone_value: Information(String),
  privacy privacy_value: Privacy,
  references reference_values: List(Reference),
  supersedes supersedes_value: Option(String),
  import_provenance import_value: Information(String),
  idempotency_key idempotency_value: String,
) -> Result(Event, EventError) {
  use _ <- result.try(valid_identifier(journal_id_value, "journal_id"))
  use _ <- result.try(valid_identifier(event_id_value, "event_id"))
  use _ <- result.try(valid_identifier(idempotency_value, "idempotency_key"))
  use _ <- result.try(validate_scope(scope_value))
  use _ <- result.try(validate_attribution(attribution_value))
  use _ <- result.try(validate_string_information(stage_value, "stage", True))
  use _ <- result.try(validate_string_information(
    timezone_value,
    "timezone",
    True,
  ))
  use _ <- result.try(validate_string_information(
    import_value,
    "import_provenance",
    True,
  ))
  use _ <- result.try(validate_payload(payload_value))
  use _ <- result.try(validate_references(reference_values, []))
  use _ <- result.try(validate_supersedes(kind_value, supersedes_value))
  use _ <- result.try(validate_instant_information(occurrence_value))
  let semantic_payload =
    semantic_json(
      journal_id_value,
      kind_value,
      scope_value,
      attribution_value,
      stage_value,
      payload_value,
      occurrence_value,
      recording_value,
      timezone_value,
      privacy_value,
      reference_values,
      supersedes_value,
      import_value,
    )
  let assert Ok(semantic_hash) = semantic_payload |> json.to_string |> hash.text
  let canonical_payload =
    canonical_json(
      journal_id_value,
      event_id_value,
      kind_value,
      scope_value,
      attribution_value,
      stage_value,
      payload_value,
      occurrence_value,
      recording_value,
      timezone_value,
      privacy_value,
      reference_values,
      supersedes_value,
      import_value,
      idempotency_value,
      semantic_hash,
    )
  let assert Ok(canonical_hash) =
    canonical_payload |> json.to_string |> hash.text
  Ok(Event(
    journal_id_value,
    event_id_value,
    kind_value,
    scope_value,
    attribution_value,
    stage_value,
    payload_value,
    occurrence_value,
    recording_value,
    timezone_value,
    privacy_value,
    reference_values,
    supersedes_value,
    import_value,
    idempotency_value,
    semantic_hash,
    canonical_hash,
  ))
}

pub fn encode(value: Event) -> String {
  value |> as_json |> json.to_string
}

/// The exact content-bound event envelope for structured tool results.
pub fn as_json(value: Event) -> json.Json {
  json.object([
    #("payload", event_json(value)),
    #(
      "canonical_content_hash",
      value.canonical_content_hash
        |> identity.sha256_value
        |> json.string,
    ),
  ])
}

pub fn decode(input: String) -> Result(Event, EventError) {
  case json.parse(input, event_decoder()) {
    Error(_) -> Error(InvalidJson)
    Ok(#(value, expected_hash)) ->
      case value.canonical_content_hash == expected_hash {
        True -> Ok(value)
        False -> Error(HashMismatch)
      }
  }
}

fn event_decoder() -> decode.Decoder(#(Event, Sha256)) {
  use payload <- decode.field("payload", payload_decoder())
  use expected_hash <- decode.field("canonical_content_hash", sha_decoder())
  let #(
    journal_id,
    event_id,
    kind,
    scope,
    attribution,
    stage,
    event_payload,
    occurrence,
    recording,
    timezone,
    privacy,
    references,
    supersedes,
    import_provenance,
    idempotency_key,
    semantic_hash,
  ) = payload
  case
    new(
      journal_id,
      event_id,
      kind,
      scope,
      attribution,
      stage,
      event_payload,
      occurrence,
      recording,
      timezone,
      privacy,
      references,
      supersedes,
      import_provenance,
      idempotency_key,
    )
  {
    Error(_) -> decode.failure(#(placeholder(), placeholder_sha()), "event")
    Ok(value) ->
      case value.semantic_content_hash == semantic_hash {
        True -> decode.success(#(value, expected_hash))
        False ->
          decode.failure(#(placeholder(), placeholder_sha()), "semantic hash")
      }
  }
}

fn payload_decoder() -> decode.Decoder(
  #(
    String,
    String,
    EventKind,
    Scope,
    Attribution,
    Information(String),
    String,
    Information(Instant),
    Instant,
    Information(String),
    Privacy,
    List(Reference),
    Option(String),
    Information(String),
    String,
    Sha256,
  ),
) {
  use schema <- decode.field("schema", decode.string)
  use version <- decode.field("schema_version", decode.int)
  use journal_id <- decode.field("journal_id", decode.string)
  use event_id <- decode.field("event_id", decode.string)
  use kind <- decode.field("event_kind", kind_decoder())
  use scope <- decode.field("scope", scope_decoder())
  use attribution <- decode.field("attribution", attribution_decoder())
  use stage <- decode.field("stage", string_information_decoder())
  use payload <- decode.field("event_payload", decode.string)
  use occurrence <- decode.field(
    "occurrence_time",
    instant_information_decoder(),
  )
  use recording <- decode.field("recording_time_unix_ms", instant_decoder())
  use timezone <- decode.field("timezone", string_information_decoder())
  use privacy <- decode.field("privacy", privacy_decoder())
  use references <- decode.field(
    "references",
    decode.list(of: reference_decoder()),
  )
  use supersedes <- decode.optional_field(
    "supersedes",
    None,
    decode.optional(decode.string),
  )
  use import_provenance <- decode.field(
    "import_provenance",
    string_information_decoder(),
  )
  use idempotency_key <- decode.field("idempotency_key", decode.string)
  use semantic_hash <- decode.field("semantic_content_hash", sha_decoder())
  case schema == "pi-sparkles/journal-event", version == schema_version {
    True, True ->
      decode.success(#(
        journal_id,
        event_id,
        kind,
        scope,
        attribution,
        stage,
        payload,
        occurrence,
        recording,
        timezone,
        privacy,
        references,
        supersedes,
        import_provenance,
        idempotency_key,
        semantic_hash,
      ))
    _, _ -> decode.failure(placeholder_payload(), "journal event v1")
  }
}

fn event_json(value: Event) -> json.Json {
  canonical_json(
    value.journal_id,
    value.event_id,
    value.kind,
    value.scope,
    value.attribution,
    value.stage,
    value.payload,
    value.occurrence_time,
    value.recording_time,
    value.timezone,
    value.privacy,
    value.references,
    value.supersedes,
    value.import_provenance,
    value.idempotency_key,
    value.semantic_content_hash,
  )
}

fn canonical_json(
  journal_id: String,
  event_id: String,
  kind: EventKind,
  scope: Scope,
  attribution: Attribution,
  stage: Information(String),
  payload: String,
  occurrence: Information(Instant),
  recording: Instant,
  timezone: Information(String),
  privacy: Privacy,
  references: List(Reference),
  supersedes: Option(String),
  import_provenance: Information(String),
  idempotency_key: String,
  semantic_hash: Sha256,
) -> json.Json {
  json.object([
    #("schema", json.string("pi-sparkles/journal-event")),
    #("schema_version", json.int(schema_version)),
    #("journal_id", json.string(journal_id)),
    #("event_id", json.string(event_id)),
    #("event_kind", kind |> kind_name |> json.string),
    #("scope", scope_json(scope)),
    #("attribution", attribution_json(attribution)),
    #("stage", string_information_json(stage)),
    #("event_payload", json.string(payload)),
    #("occurrence_time", instant_information_json(occurrence)),
    #("recording_time_unix_ms", recording |> time.unix_milliseconds |> json.int),
    #("timezone", string_information_json(timezone)),
    #("privacy", privacy |> privacy_name |> json.string),
    #("references", json.array(references, reference_json)),
    #("supersedes", json.nullable(supersedes, json.string)),
    #("import_provenance", string_information_json(import_provenance)),
    #("idempotency_key", json.string(idempotency_key)),
    #(
      "semantic_content_hash",
      semantic_hash |> identity.sha256_value |> json.string,
    ),
  ])
}

fn semantic_json(
  journal_id: String,
  kind: EventKind,
  scope: Scope,
  attribution: Attribution,
  stage: Information(String),
  payload: String,
  occurrence: Information(Instant),
  recording: Instant,
  timezone: Information(String),
  privacy: Privacy,
  references: List(Reference),
  supersedes: Option(String),
  import_provenance: Information(String),
) -> json.Json {
  json.object([
    #("journal_id", json.string(journal_id)),
    #("event_kind", kind |> kind_name |> json.string),
    #("scope", scope_json(scope)),
    #("attribution", attribution_json(attribution)),
    #("stage", string_information_json(stage)),
    #("event_payload", json.string(payload)),
    #("occurrence_time", instant_information_json(occurrence)),
    #("recording_time_unix_ms", recording |> time.unix_milliseconds |> json.int),
    #("timezone", string_information_json(timezone)),
    #("privacy", privacy |> privacy_name |> json.string),
    #("references", json.array(references, reference_json)),
    #("supersedes", json.nullable(supersedes, json.string)),
    #("import_provenance", string_information_json(import_provenance)),
  ])
}

fn scope_json(value: Scope) -> json.Json {
  let Scope(identity, workflow_id, position_id, review_id) = value
  json.object([
    #("identity", identity_json(identity)),
    #("workflow_id", json.nullable(workflow_id, json.string)),
    #("position_id", json.nullable(position_id, json.string)),
    #("review_id", json.nullable(review_id, json.string)),
  ])
}

fn scope_decoder() -> decode.Decoder(Scope) {
  use identity <- decode.field("identity", identity_decoder())
  use workflow <- decode.optional_field(
    "workflow_id",
    None,
    decode.optional(decode.string),
  )
  use position <- decode.optional_field(
    "position_id",
    None,
    decode.optional(decode.string),
  )
  use review <- decode.optional_field(
    "review_id",
    None,
    decode.optional(decode.string),
  )
  decode.success(Scope(identity, workflow, position, review))
}

fn identity_json(value: IdentityScope) -> json.Json {
  case value {
    JournalWide -> json.object([#("state", json.string("journal_wide"))])
    TrackWide(track) ->
      json.object([
        #("state", json.string("track_wide")),
        #("track", track |> finance_track.name |> json.string),
      ])
    ExactListing(track, listing_id, mic, symbol) ->
      json.object([
        #("state", json.string("exact_listing")),
        #("track", track |> finance_track.name |> json.string),
        #("listing_id", json.string(listing_id)),
        #("mic", json.string(mic)),
        #("symbol", string_information_json(symbol)),
      ])
    UnresolvedListing(track, listing_id, mic, symbol) ->
      json.object([
        #("state", json.string("unresolved_listing")),
        #("track", track_information_json(track)),
        #("listing_id", string_information_json(listing_id)),
        #("mic", string_information_json(mic)),
        #("symbol", string_information_json(symbol)),
      ])
  }
}

fn identity_decoder() -> decode.Decoder(IdentityScope) {
  use state <- decode.field("state", decode.string)
  case state {
    "journal_wide" -> decode.success(JournalWide)
    "track_wide" -> {
      use track <- decode.field("track", track_decoder())
      decode.success(TrackWide(track))
    }
    "exact_listing" -> {
      use track <- decode.field("track", track_decoder())
      use listing_id <- decode.field("listing_id", decode.string)
      use mic <- decode.field("mic", decode.string)
      use symbol <- decode.field("symbol", string_information_decoder())
      decode.success(ExactListing(track, listing_id, mic, symbol))
    }
    "unresolved_listing" -> {
      use track <- decode.field("track", track_information_decoder())
      use listing_id <- decode.field("listing_id", string_information_decoder())
      use mic <- decode.field("mic", string_information_decoder())
      use symbol <- decode.field("symbol", string_information_decoder())
      decode.success(UnresolvedListing(track, listing_id, mic, symbol))
    }
    _ -> decode.failure(JournalWide, "known identity scope")
  }
}

fn attribution_json(value: Attribution) -> json.Json {
  case value {
    UserDeclared(id) -> attributed("user_declared", id, [])
    LlmDeclared(id, context) ->
      attributed("llm_declared", id, [
        #(
          "context_receipt",
          json.nullable(context, fn(value) {
            value |> identity.sha256_value |> json.string
          }),
        ),
      ])
    ImportedDeclaration(source) ->
      attributed("imported_declaration", source, [])
    ProviderObserved(receipt) ->
      receipt_attribution("provider_observed", receipt)
    BrokerReported(receipt) -> receipt_attribution("broker_reported", receipt)
    SystemObserved(receipt) -> receipt_attribution("system_observed", receipt)
    Calculated(request, result) ->
      json.object([
        #("kind", json.string("calculated")),
        #("request_receipt", request |> identity.sha256_value |> json.string),
        #("result_receipt", result |> identity.sha256_value |> json.string),
      ])
  }
}

fn attributed(
  kind: String,
  id: String,
  additional: List(#(String, json.Json)),
) -> json.Json {
  json.object(list.append(
    [
      #("kind", json.string(kind)),
      #("author_or_source_id", json.string(id)),
    ],
    additional,
  ))
}

fn receipt_attribution(kind: String, receipt: Sha256) -> json.Json {
  json.object([
    #("kind", json.string(kind)),
    #("receipt", receipt |> identity.sha256_value |> json.string),
  ])
}

fn attribution_decoder() -> decode.Decoder(Attribution) {
  use kind <- decode.field("kind", decode.string)
  case kind {
    "user_declared" -> {
      use id <- decode.field("author_or_source_id", decode.string)
      decode.success(UserDeclared(id))
    }
    "llm_declared" -> {
      use id <- decode.field("author_or_source_id", decode.string)
      use context <- decode.optional_field(
        "context_receipt",
        None,
        decode.optional(sha_decoder()),
      )
      decode.success(LlmDeclared(id, context))
    }
    "imported_declaration" -> {
      use source <- decode.field("author_or_source_id", decode.string)
      decode.success(ImportedDeclaration(source))
    }
    "provider_observed" -> receipt_attribution_decoder(ProviderObserved)
    "broker_reported" -> receipt_attribution_decoder(BrokerReported)
    "system_observed" -> receipt_attribution_decoder(SystemObserved)
    "calculated" -> {
      use request <- decode.field("request_receipt", sha_decoder())
      use result <- decode.field("result_receipt", sha_decoder())
      decode.success(Calculated(request, result))
    }
    _ -> decode.failure(UserDeclared("placeholder"), "known attribution")
  }
}

fn receipt_attribution_decoder(
  constructor: fn(Sha256) -> Attribution,
) -> decode.Decoder(Attribution) {
  use receipt <- decode.field("receipt", sha_decoder())
  decode.success(constructor(receipt))
}

fn string_information_json(value: Information(String)) -> json.Json {
  information_json(value, json.string)
}

fn string_information_decoder() -> decode.Decoder(Information(String)) {
  information_decoder(decode.string)
}

fn instant_information_json(value: Information(Instant)) -> json.Json {
  information_json(value, fn(value) {
    value |> time.unix_milliseconds |> json.int
  })
}

fn instant_information_decoder() -> decode.Decoder(Information(Instant)) {
  information_decoder(instant_decoder())
}

fn track_information_json(value: Information(Track)) -> json.Json {
  information_json(value, fn(value) {
    value |> finance_track.name |> json.string
  })
}

fn track_information_decoder() -> decode.Decoder(Information(Track)) {
  information_decoder(track_decoder())
}

fn information_json(
  value: Information(a),
  encode_value: fn(a) -> json.Json,
) -> json.Json {
  case value {
    information.Known(value) ->
      json.object([
        #("state", json.string("known")),
        #("value", encode_value(value)),
      ])
    information.Unknown(reason) -> reason_state("unknown", reason)
    information.NotAsked -> tagged_state("not_asked")
    information.NotObtained(reason) -> reason_state("not_obtained", reason)
    information.Declined -> tagged_state("declined")
    information.NotApplicable(reason) -> reason_state("not_applicable", reason)
    information.Conflicting(values, reason) ->
      json.object([
        #("state", json.string("conflicting")),
        #("alternatives", json.array(values, encode_value)),
        #("reason", json.string(reason)),
      ])
    information.DecodeFailure(raw, reason) ->
      json.object([
        #("state", json.string("decode_failure")),
        #("raw", json.string(raw)),
        #("reason", json.string(reason)),
      ])
    information.Redacted(metadata) -> reason_state("redacted", metadata)
    information.Superseded(id) -> reason_state("superseded", id)
  }
}

fn information_decoder(
  value_decoder: decode.Decoder(a),
) -> decode.Decoder(Information(a)) {
  use state <- decode.field("state", decode.string)
  case state {
    "known" -> {
      use value <- decode.field("value", value_decoder)
      decode.success(information.Known(value))
    }
    "unknown" -> reason_decoder(information.Unknown)
    "not_asked" -> decode.success(information.NotAsked)
    "not_obtained" -> reason_decoder(information.NotObtained)
    "declined" -> decode.success(information.Declined)
    "not_applicable" -> reason_decoder(information.NotApplicable)
    "conflicting" -> {
      use alternatives <- decode.field(
        "alternatives",
        decode.list(of: value_decoder),
      )
      use reason <- decode.field("reason", decode.string)
      decode.success(information.Conflicting(alternatives, reason))
    }
    "decode_failure" -> {
      use raw <- decode.field("raw", decode.string)
      use reason <- decode.field("reason", decode.string)
      decode.success(information.DecodeFailure(raw, reason))
    }
    "redacted" -> reason_decoder(information.Redacted)
    "superseded" -> reason_decoder(information.Superseded)
    _ -> decode.failure(information.NotAsked, "known information state")
  }
}

fn reason_decoder(
  constructor: fn(String) -> Information(a),
) -> decode.Decoder(Information(a)) {
  use reason <- decode.field("reason", decode.string)
  decode.success(constructor(reason))
}

fn tagged_state(state: String) -> json.Json {
  json.object([#("state", json.string(state))])
}

fn reason_state(state: String, reason: String) -> json.Json {
  json.object([
    #("state", json.string(state)),
    #("reason", json.string(reason)),
  ])
}

fn reference_json(value: Reference) -> json.Json {
  let Reference(kind, hash) = value
  json.object([
    #("kind", json.string(kind)),
    #("hash", hash |> identity.sha256_value |> json.string),
  ])
}

fn reference_decoder() -> decode.Decoder(Reference) {
  use kind <- decode.field("kind", decode.string)
  use hash <- decode.field("hash", sha_decoder())
  decode.success(Reference(kind, hash))
}

fn kind_decoder() -> decode.Decoder(EventKind) {
  decode.string
  |> decode.then(fn(value) {
    case kind_from_name(value) {
      Ok(value) -> decode.success(value)
      Error(_) -> decode.failure(Declaration, "known event kind")
    }
  })
}

fn privacy_decoder() -> decode.Decoder(Privacy) {
  decode.string
  |> decode.then(fn(value) {
    case privacy_from_name(value) {
      Ok(value) -> decode.success(value)
      Error(_) -> decode.failure(Private, "known privacy state")
    }
  })
}

fn track_decoder() -> decode.Decoder(Track) {
  decode.string
  |> decode.then(fn(value) {
    case finance_track.from_name(value) {
      Ok(value) -> decode.success(value)
      Error(_) -> decode.failure(finance_track.Us, "cn, hk, or us")
    }
  })
}

fn instant_decoder() -> decode.Decoder(Instant) {
  decode.int
  |> decode.then(fn(value) {
    case time.instant(value) {
      Ok(value) -> decode.success(value)
      Error(_) ->
        decode.failure(placeholder_instant(), "valid Unix milliseconds")
    }
  })
}

fn sha_decoder() -> decode.Decoder(Sha256) {
  decode.string
  |> decode.then(fn(value) {
    case identity.sha256(value) {
      Ok(value) -> decode.success(value)
      Error(_) -> decode.failure(placeholder_sha(), "SHA-256 hex")
    }
  })
}

fn validate_scope(value: Scope) -> Result(Nil, EventError) {
  let Scope(identity, workflow, position, review) = value
  use _ <- result.try(validate_optional(workflow, "workflow_id"))
  use _ <- result.try(validate_optional(position, "position_id"))
  use _ <- result.try(validate_optional(review, "review_id"))
  case identity {
    JournalWide | TrackWide(_) -> Ok(Nil)
    ExactListing(_, listing_id, mic, symbol) -> {
      use _ <- result.try(valid_identifier(listing_id, "listing_id"))
      use _ <- result.try(valid_identifier(mic, "mic"))
      validate_string_information(symbol, "symbol", True)
    }
    UnresolvedListing(track, listing_id, mic, symbol) -> {
      use _ <- result.try(validate_track_information(track))
      use _ <- result.try(validate_string_information(
        listing_id,
        "listing_id",
        True,
      ))
      use _ <- result.try(validate_string_information(mic, "mic", True))
      validate_string_information(symbol, "symbol", True)
    }
  }
}

fn validate_attribution(value: Attribution) -> Result(Nil, EventError) {
  case value {
    UserDeclared(id) | LlmDeclared(id, _) -> valid_identifier(id, "author_id")
    ImportedDeclaration(source) -> valid_identifier(source, "import_source")
    _ -> Ok(Nil)
  }
}

fn validate_payload(value: String) -> Result(Nil, EventError) {
  let length = string.length(value)
  case length, length > maximum_payload_characters {
    0, _ -> Error(InvalidText("payload"))
    _, True -> Error(PayloadTooLarge(length, maximum_payload_characters))
    _, False -> Ok(Nil)
  }
}

fn validate_references(
  values: List(Reference),
  seen: List(#(String, String)),
) -> Result(Nil, EventError) {
  case list.length(values) > maximum_references {
    True -> Error(TooManyReferences(list.length(values), maximum_references))
    False -> validate_reference_loop(values, seen)
  }
}

fn validate_reference_loop(
  values: List(Reference),
  seen: List(#(String, String)),
) -> Result(Nil, EventError) {
  case values {
    [] -> Ok(Nil)
    [Reference(kind, hash), ..rest] -> {
      use _ <- result.try(valid_identifier(kind, "reference_kind"))
      let key = #(kind, identity.sha256_value(hash))
      case list.contains(seen, key) {
        True -> Error(DuplicateReference(kind, key.1))
        False -> validate_reference_loop(rest, [key, ..seen])
      }
    }
  }
}

fn validate_supersedes(
  kind: EventKind,
  supersedes: Option(String),
) -> Result(Nil, EventError) {
  case kind, supersedes {
    Correction, None | Redaction, None -> Error(SupersedesRequired)
    Correction, Some(id) | Redaction, Some(id) ->
      valid_identifier(id, "supersedes")
    _, Some(_) -> Error(SupersedesNotAllowed)
    _, None -> Ok(Nil)
  }
}

fn validate_optional(
  value: Option(String),
  field: String,
) -> Result(Nil, EventError) {
  case value {
    None -> Ok(Nil)
    Some(value) -> valid_identifier(value, field)
  }
}

fn validate_string_information(
  value: Information(String),
  field: String,
  allow_absent: Bool,
) -> Result(Nil, EventError) {
  case value {
    information.Known(value) -> valid_text(value, field)
    information.Conflicting([], _) -> Error(InvalidInformation(field))
    information.Conflicting(values, reason) -> {
      use _ <- result.try(valid_text(reason, field))
      case list.all(values, fn(value) { is_valid_text(value) }) {
        True -> Ok(Nil)
        False -> Error(InvalidInformation(field))
      }
    }
    information.DecodeFailure(_, reason)
    | information.Unknown(reason)
    | information.NotObtained(reason)
    | information.NotApplicable(reason)
    | information.Redacted(reason)
    | information.Superseded(reason) -> valid_text(reason, field)
    information.NotAsked | information.Declined ->
      case allow_absent {
        True -> Ok(Nil)
        False -> Error(InvalidInformation(field))
      }
  }
}

fn validate_track_information(
  value: Information(Track),
) -> Result(Nil, EventError) {
  case value {
    information.Conflicting([], _) -> Error(InvalidInformation("track"))
    information.Unknown(reason)
    | information.NotObtained(reason)
    | information.NotApplicable(reason)
    | information.Redacted(reason)
    | information.Superseded(reason) -> valid_text(reason, "track")
    information.DecodeFailure(_, reason) -> valid_text(reason, "track")
    _ -> Ok(Nil)
  }
}

fn validate_instant_information(
  value: Information(Instant),
) -> Result(Nil, EventError) {
  case value {
    information.Conflicting([], _) ->
      Error(InvalidInformation("occurrence_time"))
    information.Unknown(reason)
    | information.NotObtained(reason)
    | information.NotApplicable(reason)
    | information.Redacted(reason)
    | information.Superseded(reason) -> valid_text(reason, "occurrence_time")
    information.DecodeFailure(_, reason) ->
      valid_text(reason, "occurrence_time")
    _ -> Ok(Nil)
  }
}

fn valid_identifier(value: String, field: String) -> Result(Nil, EventError) {
  case
    is_valid_text(value)
    && string.length(value) <= 200
    && !string.contains(value, "\n")
    && !string.contains(value, "\r")
  {
    True -> Ok(Nil)
    False -> Error(InvalidText(field))
  }
}

fn valid_text(value: String, field: String) -> Result(Nil, EventError) {
  case is_valid_text(value) {
    True -> Ok(Nil)
    False -> Error(InvalidText(field))
  }
}

fn is_valid_text(value: String) -> Bool {
  value != "" && string.trim(value) == value
}

pub fn kind_name(value: EventKind) -> String {
  case value {
    Declaration -> "declaration"
    ObservationReference -> "observation_reference"
    ChecklistResponse -> "checklist_response"
    ReviewConclusion -> "review_conclusion"
    Correction -> "correction"
    Redaction -> "redaction"
    ImportMarker -> "import_marker"
    ExportMarker -> "export_marker"
  }
}

pub fn kind_from_name(value: String) -> Result(EventKind, Nil) {
  case value {
    "declaration" -> Ok(Declaration)
    "observation_reference" -> Ok(ObservationReference)
    "checklist_response" -> Ok(ChecklistResponse)
    "review_conclusion" -> Ok(ReviewConclusion)
    "correction" -> Ok(Correction)
    "redaction" -> Ok(Redaction)
    "import_marker" -> Ok(ImportMarker)
    "export_marker" -> Ok(ExportMarker)
    _ -> Error(Nil)
  }
}

pub fn privacy_name(value: Privacy) -> String {
  case value {
    Private -> "private"
    ReviewVisible -> "review_visible"
    Exportable -> "exportable"
  }
}

pub fn privacy_from_name(value: String) -> Result(Privacy, Nil) {
  case value {
    "private" -> Ok(Private)
    "review_visible" -> Ok(ReviewVisible)
    "exportable" -> Ok(Exportable)
    _ -> Error(Nil)
  }
}

pub fn attribution_name(value: Attribution) -> String {
  case value {
    UserDeclared(_) -> "user_declared"
    LlmDeclared(_, _) -> "llm_declared"
    ImportedDeclaration(_) -> "imported_declaration"
    ProviderObserved(_) -> "provider_observed"
    BrokerReported(_) -> "broker_reported"
    SystemObserved(_) -> "system_observed"
    Calculated(_, _) -> "calculated"
  }
}

pub fn journal_id(value: Event) -> String {
  value.journal_id
}

pub fn event_id(value: Event) -> String {
  value.event_id
}

pub fn kind(value: Event) -> EventKind {
  value.kind
}

pub fn scope(value: Event) -> Scope {
  value.scope
}

pub fn attribution(value: Event) -> Attribution {
  value.attribution
}

pub fn stage(value: Event) -> Information(String) {
  value.stage
}

pub fn payload(value: Event) -> String {
  value.payload
}

pub fn occurrence_time(value: Event) -> Information(Instant) {
  value.occurrence_time
}

pub fn recording_time(value: Event) -> Instant {
  value.recording_time
}

pub fn timezone(value: Event) -> Information(String) {
  value.timezone
}

pub fn privacy(value: Event) -> Privacy {
  value.privacy
}

pub fn references(value: Event) -> List(Reference) {
  value.references
}

pub fn supersedes(value: Event) -> Option(String) {
  value.supersedes
}

pub fn import_provenance(value: Event) -> Information(String) {
  value.import_provenance
}

pub fn idempotency_key(value: Event) -> String {
  value.idempotency_key
}

pub fn semantic_content_hash(value: Event) -> Sha256 {
  value.semantic_content_hash
}

pub fn canonical_content_hash(value: Event) -> Sha256 {
  value.canonical_content_hash
}

pub fn workflow_id(value: Scope) -> Option(String) {
  let Scope(_, workflow, _, _) = value
  workflow
}

pub fn identity_scope(value: Scope) -> IdentityScope {
  let Scope(identity, _, _, _) = value
  identity
}

pub fn reference_kind(value: Reference) -> String {
  let Reference(kind, _) = value
  kind
}

pub fn reference_hash(value: Reference) -> Sha256 {
  let Reference(_, hash) = value
  hash
}

fn placeholder() -> Event {
  let assert Ok(value) =
    new(
      "placeholder",
      "placeholder-event",
      Declaration,
      Scope(JournalWide, None, None, None),
      UserDeclared("placeholder-user"),
      information.NotAsked,
      "placeholder",
      information.Unknown("placeholder"),
      placeholder_instant(),
      information.Unknown("placeholder"),
      Private,
      [],
      None,
      information.NotApplicable("placeholder"),
      "placeholder-key",
    )
  value
}

fn placeholder_payload() -> #(
  String,
  String,
  EventKind,
  Scope,
  Attribution,
  Information(String),
  String,
  Information(Instant),
  Instant,
  Information(String),
  Privacy,
  List(Reference),
  Option(String),
  Information(String),
  String,
  Sha256,
) {
  #(
    "placeholder",
    "placeholder-event",
    Declaration,
    Scope(JournalWide, None, None, None),
    UserDeclared("placeholder-user"),
    information.NotAsked,
    "placeholder",
    information.Unknown("placeholder"),
    placeholder_instant(),
    information.Unknown("placeholder"),
    Private,
    [],
    None,
    information.NotApplicable("placeholder"),
    "placeholder-key",
    placeholder_sha(),
  )
}

fn placeholder_sha() -> Sha256 {
  let assert Ok(value) = identity.sha256(string.repeat("0", 64))
  value
}

fn placeholder_instant() -> Instant {
  let assert Ok(value) = time.instant(0)
  value
}
