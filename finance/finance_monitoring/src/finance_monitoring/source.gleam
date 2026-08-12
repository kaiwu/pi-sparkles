import finance_provenance/hash
import finance_provenance/identity
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None}
import gleam/order.{type Order, Eq, Gt, Lt}
import gleam/result
import gleam/string

pub type Descriptor {
  Descriptor(
    contract_id: String,
    allowed_tracks: List(String),
    allowed_event_kinds: List(String),
  )
}

pub type Response {
  Response(summary: String, details: json.Json)
}

pub type SourceError {
  ContentHashMismatch
  InvalidJson
  WrongSchema
  WrongContract
  InvalidIdentity
  WrongTrack
  WrongEventKind(kind: String)
  InvalidReceipt(field: String)
  DuplicateIdentity(field: String)
  InvalidPage
}

type SourceReceipt {
  SourceReceipt(
    source_id: String,
    provider: String,
    authority_role: String,
    retrieved_at: String,
    coverage: String,
    entitlement: String,
    licence: String,
    content_hash: String,
    status: String,
    limitations: List(String),
  )
}

type Event {
  Event(
    ordinal: Int,
    event_id: String,
    kind: String,
    title: String,
    language: String,
    event_time: Option(String),
    publication_time: String,
    retrieval_time: String,
    effective_time: Option(String),
    source_id: String,
    source_receipt: String,
    document_id: Option(String),
    original_lexeme: String,
    corrects: Option(String),
    retracted: Bool,
  )
}

type Packet {
  Packet(
    schema_version: Int,
    contract_id: String,
    request_id: String,
    track: String,
    listing_id: String,
    mic: String,
    range_start: String,
    range_end: String,
    timezone: String,
    sources: List(SourceReceipt),
    events: List(Event),
    omissions: List(String),
  )
}

pub fn project(
  descriptor: Descriptor,
  bytes: String,
  expected_sha256: String,
  offset: Int,
  limit: Int,
) -> Result(Response, SourceError) {
  use _ <- result.try(verify_hash(bytes, expected_sha256))
  use packet <- result.try(
    json.parse(bytes, packet_decoder())
    |> result.map_error(fn(_) { InvalidJson }),
  )
  use _ <- result.try(validate(descriptor, packet, offset, limit))
  let ordered = list.sort(packet.events, compare_events)
  let page = ordered |> list.drop(offset) |> list.take(limit)
  let next_offset = case offset + list.length(page) < list.length(ordered) {
    True -> json.int(offset + list.length(page))
    False -> json.null()
  }
  let payload =
    json.object([
      #("schemaVersion", json.int(1)),
      #("contractId", json.string(packet.contract_id)),
      #("requestId", json.string(packet.request_id)),
      #("track", json.string(packet.track)),
      #("listingId", json.string(packet.listing_id)),
      #("mic", json.string(packet.mic)),
      #("rangeStart", json.string(packet.range_start)),
      #("rangeEnd", json.string(packet.range_end)),
      #("timezone", json.string(packet.timezone)),
      #("searchedSourceCount", json.int(list.length(packet.sources))),
      #("sourceReceipts", json.array(packet.sources, source_json)),
      #("eventCount", json.int(list.length(ordered))),
      #("offset", json.int(offset)),
      #("returnedCount", json.int(list.length(page))),
      #("nextOffset", next_offset),
      #("events", json.array(page, event_json)),
      #("omissions", json.array(packet.omissions, json.string)),
      #(
        "noMatchMeaning",
        json.string("no_event_in_supplied_bounded_receipts_not_absence_proof"),
      ),
      #("ordering", json.string("publication_time_then_input_ordinal")),
      #("causalFields", json.array([], json.string)),
      #("sourcePacketSha256", json.string(expected_sha256)),
      #(
        "availableOperations",
        json.array(
          ["next_page", "inspect_source_receipts", "inspect_correction_lineage"],
          json.string,
        ),
      ),
    ])
  let assert Ok(receipt) = payload |> json.to_string |> hash.text
  Ok(Response(
    packet.track
      <> ":"
      <> packet.mic
      <> ":"
      <> packet.listing_id
      <> " returned "
      <> int.to_string(list.length(page))
      <> "/"
      <> int.to_string(list.length(ordered))
      <> " exact events; partial failures, coverage and corrections remain visible; no importance or causality judgment",
    json.object([
      #("canonicalTimeline", payload),
      #("canonicalContentHash", receipt |> identity.sha256_value |> json.string),
    ]),
  ))
}

pub fn summary(value: Response) -> String {
  value.summary
}

pub fn details(value: Response) -> json.Json {
  value.details
}

pub fn error_message(error: SourceError) -> String {
  case error {
    ContentHashMismatch ->
      "Monitoring receipt packet does not match expectedSha256"
    InvalidJson -> "Monitoring receipt packet is not valid versioned JSON"
    WrongSchema -> "Monitoring receipt packet schemaVersion must be 1"
    WrongContract ->
      "Monitoring receipt packet contractId is wrong for this plugin"
    InvalidIdentity ->
      "Monitoring request identity, time range, source scope, or bounds are invalid"
    WrongTrack ->
      "Monitoring request track is outside this plugin's exact scope"
    WrongEventKind(kind) ->
      "Monitoring event kind is outside this plugin's exact scope: " <> kind
    InvalidReceipt(field) ->
      "Monitoring receipt is not an exact SHA-256: " <> field
    DuplicateIdentity(field) ->
      "Monitoring packet contains duplicate identity: " <> field
    InvalidPage -> "Monitoring page offset or limit is invalid"
  }
}

fn validate(
  descriptor: Descriptor,
  packet: Packet,
  offset: Int,
  limit: Int,
) -> Result(Nil, SourceError) {
  use _ <- result.try(case packet.schema_version == 1 {
    True -> Ok(Nil)
    False -> Error(WrongSchema)
  })
  use _ <- result.try(case packet.contract_id == descriptor.contract_id {
    True -> Ok(Nil)
    False -> Error(WrongContract)
  })
  use _ <- result.try(
    case list.contains(descriptor.allowed_tracks, packet.track) {
      True -> Ok(Nil)
      False -> Error(WrongTrack)
    },
  )
  use _ <- result.try(case offset >= 0 && limit >= 1 && limit <= 200 {
    True -> Ok(Nil)
    False -> Error(InvalidPage)
  })
  use _ <- result.try(
    validate_texts([
      packet.request_id,
      packet.listing_id,
      packet.mic,
      packet.range_start,
      packet.range_end,
      packet.timezone,
    ]),
  )
  use _ <- result.try(
    case
      list.length(packet.sources) >= 1
      && list.length(packet.sources) <= 50
      && list.length(packet.events) <= 10_000
      && list.length(packet.omissions) <= 500
    {
      True -> Ok(Nil)
      False -> Error(InvalidIdentity)
    },
  )
  use _ <- result.try(unique(
    list.map(packet.sources, fn(value) { value.source_id }),
    "source_id",
  ))
  use _ <- result.try(unique(
    list.map(packet.events, fn(value) { value.event_id }),
    "event_id",
  ))
  use _ <- result.try(list.try_each(packet.sources, validate_source))
  list.try_each(packet.events, fn(event) {
    validate_event(event, descriptor, packet)
  })
}

fn validate_source(source: SourceReceipt) -> Result(Nil, SourceError) {
  use _ <- result.try(
    validate_texts([
      source.source_id,
      source.provider,
      source.authority_role,
      source.retrieved_at,
      source.coverage,
      source.entitlement,
      source.licence,
      source.status,
    ]),
  )
  validate_receipt(source.content_hash, source.source_id <> ".content_hash")
}

fn validate_event(
  event: Event,
  descriptor: Descriptor,
  packet: Packet,
) -> Result(Nil, SourceError) {
  use _ <- result.try(
    case list.contains(descriptor.allowed_event_kinds, event.kind) {
      True -> Ok(Nil)
      False -> Error(WrongEventKind(event.kind))
    },
  )
  use _ <- result.try(
    validate_texts([
      event.event_id,
      event.title,
      event.language,
      event.publication_time,
      event.retrieval_time,
      event.source_id,
      event.original_lexeme,
    ]),
  )
  use _ <- result.try(validate_receipt(
    event.source_receipt,
    event.event_id <> ".source_receipt",
  ))
  case
    list.any(packet.sources, fn(source) { source.source_id == event.source_id })
  {
    True -> Ok(Nil)
    False -> Error(InvalidIdentity)
  }
}

fn compare_events(left: Event, right: Event) -> Order {
  case string.compare(left.publication_time, right.publication_time) {
    Eq -> int.compare(left.ordinal, right.ordinal)
    Lt -> Lt
    Gt -> Gt
  }
}

fn source_json(value: SourceReceipt) -> json.Json {
  json.object([
    #("sourceId", json.string(value.source_id)),
    #("provider", json.string(value.provider)),
    #("authorityRole", json.string(value.authority_role)),
    #("retrievedAt", json.string(value.retrieved_at)),
    #("coverage", json.string(value.coverage)),
    #("entitlement", json.string(value.entitlement)),
    #("licence", json.string(value.licence)),
    #("contentHash", json.string(value.content_hash)),
    #("status", json.string(value.status)),
    #("limitations", json.array(value.limitations, json.string)),
  ])
}

fn event_json(value: Event) -> json.Json {
  json.object([
    #("ordinal", json.int(value.ordinal)),
    #("eventId", json.string(value.event_id)),
    #("kind", json.string(value.kind)),
    #("title", json.string(value.title)),
    #("language", json.string(value.language)),
    #("eventTime", json.nullable(value.event_time, json.string)),
    #("publicationTime", json.string(value.publication_time)),
    #("retrievalTime", json.string(value.retrieval_time)),
    #("effectiveTime", json.nullable(value.effective_time, json.string)),
    #("sourceId", json.string(value.source_id)),
    #("sourceReceipt", json.string(value.source_receipt)),
    #("documentId", json.nullable(value.document_id, json.string)),
    #("originalLexeme", json.string(value.original_lexeme)),
    #("corrects", json.nullable(value.corrects, json.string)),
    #("retracted", json.bool(value.retracted)),
  ])
}

fn validate_texts(values: List(String)) -> Result(Nil, SourceError) {
  case
    list.all(values, fn(value) {
      value != ""
      && string.trim(value) == value
      && string.length(value) <= 65_536
    })
  {
    True -> Ok(Nil)
    False -> Error(InvalidIdentity)
  }
}

fn unique(values: List(String), field: String) -> Result(Nil, SourceError) {
  case list.length(values) == list.length(list.unique(values)) {
    True -> Ok(Nil)
    False -> Error(DuplicateIdentity(field))
  }
}

fn validate_receipt(value: String, field: String) -> Result(Nil, SourceError) {
  case
    string.length(value) == 64
    && list.all(string.to_graphemes(value), fn(character) {
      string.contains("0123456789abcdef", character)
    })
  {
    True -> Ok(Nil)
    False -> Error(InvalidReceipt(field))
  }
}

fn verify_hash(bytes: String, expected: String) -> Result(Nil, SourceError) {
  case hash.text(bytes) {
    Ok(actual) ->
      case identity.sha256_value(actual) == expected {
        True -> Ok(Nil)
        False -> Error(ContentHashMismatch)
      }
    Error(_) -> Error(ContentHashMismatch)
  }
}

fn packet_decoder() -> decode.Decoder(Packet) {
  use schema <- decode.field("schemaVersion", decode.int)
  use contract <- decode.field("contractId", decode.string)
  use request_id <- decode.field("requestId", decode.string)
  use track <- decode.field("track", decode.string)
  use listing_id <- decode.field("listingId", decode.string)
  use mic <- decode.field("mic", decode.string)
  use range_start <- decode.field("rangeStart", decode.string)
  use range_end <- decode.field("rangeEnd", decode.string)
  use timezone <- decode.field("timezone", decode.string)
  use sources <- decode.field("sources", decode.list(of: source_decoder()))
  use events <- decode.field("events", decode.list(of: event_decoder()))
  use omissions <- decode.field("omissions", decode.list(of: decode.string))
  decode.success(Packet(
    schema,
    contract,
    request_id,
    track,
    listing_id,
    mic,
    range_start,
    range_end,
    timezone,
    sources,
    events,
    omissions,
  ))
}

fn source_decoder() -> decode.Decoder(SourceReceipt) {
  use id <- decode.field("sourceId", decode.string)
  use provider <- decode.field("provider", decode.string)
  use role <- decode.field("authorityRole", decode.string)
  use retrieved <- decode.field("retrievedAt", decode.string)
  use coverage <- decode.field("coverage", decode.string)
  use entitlement <- decode.field("entitlement", decode.string)
  use licence <- decode.field("licence", decode.string)
  use content_hash <- decode.field("contentHash", decode.string)
  use status <- decode.field("status", decode.string)
  use limitations <- decode.field("limitations", decode.list(of: decode.string))
  decode.success(SourceReceipt(
    id,
    provider,
    role,
    retrieved,
    coverage,
    entitlement,
    licence,
    content_hash,
    status,
    limitations,
  ))
}

fn event_decoder() -> decode.Decoder(Event) {
  use ordinal <- decode.field("ordinal", decode.int)
  use id <- decode.field("eventId", decode.string)
  use kind <- decode.field("kind", decode.string)
  use title <- decode.field("title", decode.string)
  use language <- decode.field("language", decode.string)
  use event_time <- decode.optional_field(
    "eventTime",
    None,
    decode.optional(decode.string),
  )
  use publication <- decode.field("publicationTime", decode.string)
  use retrieval <- decode.field("retrievalTime", decode.string)
  use effective <- decode.optional_field(
    "effectiveTime",
    None,
    decode.optional(decode.string),
  )
  use source_id <- decode.field("sourceId", decode.string)
  use receipt <- decode.field("sourceReceipt", decode.string)
  use document <- decode.optional_field(
    "documentId",
    None,
    decode.optional(decode.string),
  )
  use lexeme <- decode.field("originalLexeme", decode.string)
  use corrects <- decode.optional_field(
    "corrects",
    None,
    decode.optional(decode.string),
  )
  use retracted <- decode.field("retracted", decode.bool)
  decode.success(Event(
    ordinal,
    id,
    kind,
    title,
    language,
    event_time,
    publication,
    retrieval,
    effective,
    source_id,
    receipt,
    document,
    lexeme,
    corrects,
    retracted,
  ))
}
