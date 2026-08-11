import finance_provenance/hash
import finance_provenance/identity
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub type Descriptor {
  Descriptor(
    contract_id: String,
    track: String,
    allowed_mics: List(String),
    record_kinds: List(String),
    required_fields: List(String),
  )
}

pub type Subject {
  Subject(
    issuer_id: String,
    listing_id: String,
    mic: String,
    share_class: String,
  )
}

pub type Source {
  Source(
    provider: String,
    authority_role: String,
    document_id: String,
    published_at: String,
    retrieved_at: String,
    language: String,
    rights: String,
    source_url: String,
  )
}

pub type Field {
  Field(
    name: String,
    state: String,
    value_lexeme: Option(String),
    unit: Option(String),
    source_span: Option(String),
  )
}

pub type Record {
  Record(
    record_id: String,
    kind: String,
    effective_at: String,
    published_at: String,
    correction_of: Option(String),
    fields: List(Field),
  )
}

pub type Packet {
  Packet(
    schema_version: Int,
    contract_id: String,
    track: String,
    subject: Subject,
    source: Source,
    records: List(Record),
    omissions: List(String),
  )
}

pub type Input {
  Input(path: String, expected_sha256: String, offset: Int, limit: Int)
}

pub type DrillInput {
  DrillInput(path: String, expected_sha256: String, record_id: String)
}

pub type Response {
  Response(summary: String, details: json.Json)
}

pub type ContractError {
  InvalidJson
  ContentHashMismatch
  WrongSchema
  WrongContract
  WrongTrack
  WrongMic
  InvalidSubject
  InvalidSource
  TooManyRecords
  TooManyOmissions
  DuplicateRecordId
  UnsupportedRecordKind
  MissingRequiredField(String)
  DuplicateField
  InvalidFieldState
  InvalidCorrectionReference
  InvalidPage
  RecordNotFound
}

pub fn input(
  path: String,
  expected_sha256: String,
  offset: Int,
  limit: Int,
) -> Input {
  Input(path, expected_sha256, offset, limit)
}

pub fn drill_input(
  path: String,
  expected_sha256: String,
  record_id: String,
) -> DrillInput {
  DrillInput(path, expected_sha256, record_id)
}

pub fn path(value: Input) -> String {
  value.path
}

pub fn expected_sha256(value: Input) -> String {
  value.expected_sha256
}

pub fn drill_path(value: DrillInput) -> String {
  value.path
}

pub fn drill_expected_sha256(value: DrillInput) -> String {
  value.expected_sha256
}

pub fn inspect(
  descriptor: Descriptor,
  input: Input,
  bytes: String,
) -> Result(Response, ContractError) {
  use packet <- result_try(decode_and_validate(
    descriptor,
    input.expected_sha256,
    bytes,
  ))
  case input.offset >= 0 && input.limit >= 1 && input.limit <= 100 {
    False -> Error(InvalidPage)
    True -> {
      let total = list.length(packet.records)
      let page =
        packet.records |> list.drop(input.offset) |> list.take(input.limit)
      let next_offset = case input.offset + list.length(page) < total {
        True -> json.int(input.offset + list.length(page))
        False -> json.null()
      }
      let details =
        json.object([
          #("schemaVersion", json.int(1)),
          #("contractId", json.string(packet.contract_id)),
          #("track", json.string(packet.track)),
          #("subject", subject_json(packet.subject)),
          #("source", source_json(packet.source)),
          #("packetSha256", json.string(input.expected_sha256)),
          #("recordCount", json.int(total)),
          #("omissionCount", json.int(list.length(packet.omissions))),
          #("offset", json.int(input.offset)),
          #("nextOffset", next_offset),
          #("records", json.array(page, record_header_json)),
          #("omissions", json.array(packet.omissions, json.string)),
          #("decisionOwner", json.string("llm")),
          #("pluginDecisionFields", json.array([], json.string)),
          #(
            "availableOperations",
            json.array(["inspect_page", "drill_record"], json.string),
          ),
        ])
      Ok(Response(
        descriptor.contract_id
          <> ": "
          <> int.to_string(total)
          <> " exact record(s), "
          <> int.to_string(list.length(packet.omissions))
          <> " omission(s); interpretation remains with the LLM",
        details,
      ))
    }
  }
}

pub fn drill(
  descriptor: Descriptor,
  input: DrillInput,
  bytes: String,
) -> Result(Response, ContractError) {
  use packet <- result_try(decode_and_validate(
    descriptor,
    input.expected_sha256,
    bytes,
  ))
  case find_record(packet.records, input.record_id) {
    None -> Error(RecordNotFound)
    Some(record) ->
      Ok(Response(
        descriptor.contract_id
          <> " record "
          <> record.record_id
          <> "; source facts only",
        json.object([
          #("schemaVersion", json.int(1)),
          #("contractId", json.string(packet.contract_id)),
          #("track", json.string(packet.track)),
          #("subject", subject_json(packet.subject)),
          #("source", source_json(packet.source)),
          #("packetSha256", json.string(input.expected_sha256)),
          #("record", record_json(record)),
          #("decisionOwner", json.string("llm")),
          #("pluginDecisionFields", json.array([], json.string)),
        ]),
      ))
  }
}

pub fn summary(value: Response) -> String {
  value.summary
}

pub fn details(value: Response) -> json.Json {
  value.details
}

pub fn error_message(error: ContractError) -> String {
  case error {
    InvalidJson -> "Import is not valid research packet JSON"
    ContentHashMismatch -> "Import bytes do not match expectedSha256"
    WrongSchema -> "Research packet schemaVersion must be 1"
    WrongContract -> "Research packet contractId does not match this plugin"
    WrongTrack -> "Research packet track does not match this plugin"
    WrongMic -> "Research packet MIC is not in this plugin's exact scope"
    InvalidSubject -> "Research packet subject identity is incomplete"
    InvalidSource ->
      "Research packet source identity, rights, or times are incomplete"
    TooManyRecords -> "Research packet exceeds the 1000-record budget"
    TooManyOmissions -> "Research packet exceeds the 200-omission budget"
    DuplicateRecordId -> "Research packet contains duplicate recordId values"
    UnsupportedRecordKind ->
      "Research packet contains an unsupported record kind"
    MissingRequiredField(name) ->
      "Research record is missing required field: " <> name
    DuplicateField -> "Research record contains duplicate field names"
    InvalidFieldState ->
      "Research field has an invalid information state/value combination"
    InvalidCorrectionReference -> "Research correction lineage is invalid"
    InvalidPage -> "Research page requires offset >= 0 and limit 1..100"
    RecordNotFound -> "Research recordId was not found in the exact packet"
  }
}

fn decode_and_validate(
  descriptor: Descriptor,
  expected_sha256: String,
  bytes: String,
) -> Result(Packet, ContractError) {
  use _ <- result_try(verify_hash(bytes, expected_sha256))
  case json.parse(bytes, packet_decoder()) {
    Error(_) -> Error(InvalidJson)
    Ok(packet) -> validate_packet(descriptor, packet)
  }
}

fn verify_hash(bytes: String, expected: String) -> Result(Nil, ContractError) {
  case hash.text(bytes) {
    Error(_) -> Error(ContentHashMismatch)
    Ok(actual) ->
      case identity.sha256_value(actual) == expected {
        True -> Ok(Nil)
        False -> Error(ContentHashMismatch)
      }
  }
}

fn validate_packet(
  descriptor: Descriptor,
  packet: Packet,
) -> Result(Packet, ContractError) {
  case packet.schema_version == 1 {
    False -> Error(WrongSchema)
    True ->
      case packet.contract_id == descriptor.contract_id {
        False -> Error(WrongContract)
        True ->
          case packet.track == descriptor.track {
            False -> Error(WrongTrack)
            True -> validate_scope(descriptor, packet)
          }
      }
  }
}

fn validate_scope(
  descriptor: Descriptor,
  packet: Packet,
) -> Result(Packet, ContractError) {
  case valid_subject(packet.subject) {
    False -> Error(InvalidSubject)
    True ->
      case list.contains(descriptor.allowed_mics, packet.subject.mic) {
        False -> Error(WrongMic)
        True ->
          case valid_source(packet.source) {
            False -> Error(InvalidSource)
            True -> validate_collections(descriptor, packet)
          }
      }
  }
}

fn validate_collections(
  descriptor: Descriptor,
  packet: Packet,
) -> Result(Packet, ContractError) {
  case list.length(packet.records) <= 1000 {
    False -> Error(TooManyRecords)
    True ->
      case list.length(packet.omissions) <= 200 {
        False -> Error(TooManyOmissions)
        True ->
          case unique_record_ids(packet.records) {
            False -> Error(DuplicateRecordId)
            True ->
              validate_records(descriptor, packet.records, packet.records)
              |> result.map(fn(_) { packet })
          }
      }
  }
}

fn validate_records(
  descriptor: Descriptor,
  remaining: List(Record),
  all: List(Record),
) -> Result(Nil, ContractError) {
  case remaining {
    [] -> Ok(Nil)
    [record, ..rest] -> {
      use _ <- result_try(validate_record(descriptor, record, all))
      validate_records(descriptor, rest, all)
    }
  }
}

fn validate_record(
  descriptor: Descriptor,
  record: Record,
  all: List(Record),
) -> Result(Nil, ContractError) {
  case list.contains(descriptor.record_kinds, record.kind) {
    False -> Error(UnsupportedRecordKind)
    True ->
      case unique_field_names(record.fields) {
        False -> Error(DuplicateField)
        True -> {
          use _ <- result_try(require_fields(
            descriptor.required_fields,
            record.fields,
          ))
          use _ <- result_try(validate_fields(record.fields))
          validate_correction(record, all)
        }
      }
  }
}

fn require_fields(
  required: List(String),
  fields: List(Field),
) -> Result(Nil, ContractError) {
  case required {
    [] -> Ok(Nil)
    [name, ..rest] ->
      case list.any(fields, fn(field) { field.name == name }) {
        True -> require_fields(rest, fields)
        False -> Error(MissingRequiredField(name))
      }
  }
}

fn validate_fields(fields: List(Field)) -> Result(Nil, ContractError) {
  case fields {
    [] -> Ok(Nil)
    [field, ..rest] ->
      case valid_field(field) {
        True -> validate_fields(rest)
        False -> Error(InvalidFieldState)
      }
  }
}

fn valid_field(field: Field) -> Bool {
  let known_states = [
    "known",
    "unknown",
    "not_obtained",
    "conflicting",
    "decode_failure",
    "not_applicable",
  ]
  nonempty(field.name)
  && list.contains(known_states, field.state)
  && case field.state, field.value_lexeme {
    "known", Some(value) -> nonempty(value)
    "known", None -> False
    _, _ -> True
  }
}

fn validate_correction(
  record: Record,
  all: List(Record),
) -> Result(Nil, ContractError) {
  case record.correction_of {
    None -> Ok(Nil)
    Some(id) ->
      case id != record.record_id && find_record(all, id) != None {
        True -> Ok(Nil)
        False -> Error(InvalidCorrectionReference)
      }
  }
}

fn valid_subject(subject: Subject) -> Bool {
  nonempty(subject.issuer_id)
  && nonempty(subject.listing_id)
  && nonempty(subject.mic)
  && nonempty(subject.share_class)
}

fn valid_source(source: Source) -> Bool {
  nonempty(source.provider)
  && nonempty(source.authority_role)
  && nonempty(source.document_id)
  && nonempty(source.published_at)
  && nonempty(source.retrieved_at)
  && nonempty(source.language)
  && nonempty(source.rights)
  && nonempty(source.source_url)
}

fn nonempty(value: String) -> Bool {
  value != "" && value == string.trim(value) && string.length(value) <= 20_000
}

fn unique_record_ids(records: List(Record)) -> Bool {
  unique_strings(list.map(records, fn(record) { record.record_id }))
}

fn unique_field_names(fields: List(Field)) -> Bool {
  unique_strings(list.map(fields, fn(field) { field.name }))
}

fn unique_strings(values: List(String)) -> Bool {
  case values {
    [] -> True
    [value, ..rest] -> !list.contains(rest, value) && unique_strings(rest)
  }
}

fn find_record(records: List(Record), id: String) -> Option(Record) {
  case records {
    [] -> None
    [record, ..rest] ->
      case record.record_id == id {
        True -> Some(record)
        False -> find_record(rest, id)
      }
  }
}

fn packet_decoder() -> decode.Decoder(Packet) {
  use schema_version <- decode.field("schemaVersion", decode.int)
  use contract_id <- decode.field("contractId", decode.string)
  use track <- decode.field("track", decode.string)
  use subject <- decode.field("subject", subject_decoder())
  use source <- decode.field("source", source_decoder())
  use records <- decode.field("records", decode.list(record_decoder()))
  use omissions <- decode.field("omissions", decode.list(decode.string))
  decode.success(Packet(
    schema_version,
    contract_id,
    track,
    subject,
    source,
    records,
    omissions,
  ))
}

fn subject_decoder() -> decode.Decoder(Subject) {
  use issuer_id <- decode.field("issuerId", decode.string)
  use listing_id <- decode.field("listingId", decode.string)
  use mic <- decode.field("mic", decode.string)
  use share_class <- decode.field("shareClass", decode.string)
  decode.success(Subject(issuer_id, listing_id, mic, share_class))
}

fn source_decoder() -> decode.Decoder(Source) {
  use provider <- decode.field("provider", decode.string)
  use authority_role <- decode.field("authorityRole", decode.string)
  use document_id <- decode.field("documentId", decode.string)
  use published_at <- decode.field("publishedAt", decode.string)
  use retrieved_at <- decode.field("retrievedAt", decode.string)
  use language <- decode.field("language", decode.string)
  use rights <- decode.field("rights", decode.string)
  use source_url <- decode.field("sourceUrl", decode.string)
  decode.success(Source(
    provider,
    authority_role,
    document_id,
    published_at,
    retrieved_at,
    language,
    rights,
    source_url,
  ))
}

fn record_decoder() -> decode.Decoder(Record) {
  use record_id <- decode.field("recordId", decode.string)
  use kind <- decode.field("kind", decode.string)
  use effective_at <- decode.field("effectiveAt", decode.string)
  use published_at <- decode.field("publishedAt", decode.string)
  use correction_of <- optional_string("correctionOf")
  use fields <- decode.field("fields", decode.list(field_decoder()))
  decode.success(Record(
    record_id,
    kind,
    effective_at,
    published_at,
    correction_of,
    fields,
  ))
}

fn field_decoder() -> decode.Decoder(Field) {
  use name <- decode.field("name", decode.string)
  use state <- decode.field("state", decode.string)
  use value_lexeme <- optional_string("valueLexeme")
  use unit <- optional_string("unit")
  use source_span <- optional_string("sourceSpan")
  decode.success(Field(name, state, value_lexeme, unit, source_span))
}

fn optional_string(
  name: String,
  next: fn(Option(String)) -> decode.Decoder(value),
) -> decode.Decoder(value) {
  decode.optional_field(name, None, decode.optional(decode.string), next)
}

fn subject_json(subject: Subject) -> json.Json {
  json.object([
    #("issuerId", json.string(subject.issuer_id)),
    #("listingId", json.string(subject.listing_id)),
    #("mic", json.string(subject.mic)),
    #("shareClass", json.string(subject.share_class)),
  ])
}

fn source_json(source: Source) -> json.Json {
  json.object([
    #("provider", json.string(source.provider)),
    #("authorityRole", json.string(source.authority_role)),
    #("documentId", json.string(source.document_id)),
    #("publishedAt", json.string(source.published_at)),
    #("retrievedAt", json.string(source.retrieved_at)),
    #("language", json.string(source.language)),
    #("rights", json.string(source.rights)),
    #("sourceUrl", json.string(source.source_url)),
  ])
}

fn record_header_json(record: Record) -> json.Json {
  json.object([
    #("recordId", json.string(record.record_id)),
    #("kind", json.string(record.kind)),
    #("effectiveAt", json.string(record.effective_at)),
    #("publishedAt", json.string(record.published_at)),
    #("correctionOf", json.nullable(record.correction_of, json.string)),
    #("fieldCount", json.int(list.length(record.fields))),
  ])
}

fn record_json(record: Record) -> json.Json {
  json.object([
    #("recordId", json.string(record.record_id)),
    #("kind", json.string(record.kind)),
    #("effectiveAt", json.string(record.effective_at)),
    #("publishedAt", json.string(record.published_at)),
    #("correctionOf", json.nullable(record.correction_of, json.string)),
    #("fields", json.array(record.fields, field_json)),
  ])
}

fn field_json(field: Field) -> json.Json {
  json.object([
    #("name", json.string(field.name)),
    #("state", json.string(field.state)),
    #("valueLexeme", json.nullable(field.value_lexeme, json.string)),
    #("unit", json.nullable(field.unit, json.string)),
    #("sourceSpan", json.nullable(field.source_span, json.string)),
  ])
}

fn result_try(
  result: Result(value, error),
  next: fn(value) -> Result(next_value, error),
) -> Result(next_value, error) {
  case result {
    Ok(value) -> next(value)
    Error(error) -> Error(error)
  }
}
