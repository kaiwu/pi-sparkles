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
    allowed_forms: List(String),
    required_language: Option(String),
  )
}

pub type Subject {
  Subject(issuer_id: String, listing_id: String, mic: String)
}

pub type Section {
  Section(
    section_id: String,
    kind: String,
    title: String,
    ordinal: Int,
    start_offset: Int,
    end_offset: Int,
    raw_text: String,
  )
}

pub type Document {
  Document(
    document_id: String,
    form: String,
    accession_or_event_id: String,
    published_at: String,
    effective_date: String,
    correction_of: Option(String),
    language: String,
    source_url: String,
    rights: String,
    content_sha256: String,
    sections: List(Section),
    omissions: List(String),
  )
}

pub type Packet {
  Packet(
    schema_version: Int,
    contract_id: String,
    track: String,
    subject: Subject,
    view: String,
    algorithm_version: String,
    left: Document,
    right: Document,
  )
}

pub type Change {
  Change(
    change_id: String,
    kind: String,
    section_id: String,
    left: Option(Section),
    right: Option(Section),
  )
}

pub opaque type Comparison {
  Comparison(packet: Packet, packet_sha256: String, changes: List(Change))
}

pub type DiffError {
  InvalidJson
  ContentHashMismatch
  WrongSchema
  WrongContract
  WrongTrack
  WrongMic
  InvalidSubject
  UnsupportedView
  UnsupportedAlgorithm
  UnsupportedForm
  WrongLanguage
  InvalidDocument(side: String)
  InvalidDocumentHash(side: String)
  TooManySections(side: String)
  TooManyOmissions(side: String)
  DuplicateSectionId(side: String)
  InvalidSection(side: String)
  InvalidCorrectionLineage
  TooManyChanges
  InvalidPage
  ChangeNotFound
}

pub fn compare(
  descriptor: Descriptor,
  expected_sha256: String,
  bytes: String,
) -> Result(Comparison, DiffError) {
  use _ <- result.try(verify_hash(bytes, expected_sha256))
  use packet <- result.try(case json.parse(bytes, packet_decoder()) {
    Ok(value) -> Ok(value)
    Error(_) -> Error(InvalidJson)
  })
  use _ <- result.try(validate_packet(descriptor, packet))
  let changes =
    build_changes(packet.left.sections, packet.right.sections, packet.view)
  case list.length(changes) <= 10_000 {
    True -> Ok(Comparison(packet, expected_sha256, changes))
    False -> Error(TooManyChanges)
  }
}

pub fn list_changes(
  value: Comparison,
  offset: Int,
  limit: Int,
) -> Result(json.Json, DiffError) {
  case offset >= 0 && limit >= 1 && limit <= 100 {
    False -> Error(InvalidPage)
    True -> {
      let page = value.changes |> list.drop(offset) |> list.take(limit)
      let total = list.length(value.changes)
      let next = case offset + list.length(page) < total {
        True -> json.int(offset + list.length(page))
        False -> json.null()
      }
      Ok(
        json.object([
          #("schemaVersion", json.int(1)),
          #("contractId", json.string(value.packet.contract_id)),
          #("track", json.string(value.packet.track)),
          #("subject", subject_json(value.packet.subject)),
          #("view", json.string(value.packet.view)),
          #("algorithmVersion", json.string(value.packet.algorithm_version)),
          #("packetSha256", json.string(value.packet_sha256)),
          #("leftDocument", document_header_json(value.packet.left)),
          #("rightDocument", document_header_json(value.packet.right)),
          #("changeCount", json.int(total)),
          #("offset", json.int(offset)),
          #("nextOffset", next),
          #("changes", json.array(page, change_header_json)),
          #("decisionOwner", json.string("llm")),
          #("pluginDecisionFields", json.array([], json.string)),
        ]),
      )
    }
  }
}

pub fn drill_change(
  value: Comparison,
  change_id: String,
) -> Result(json.Json, DiffError) {
  case find_change(value.changes, change_id) {
    None -> Error(ChangeNotFound)
    Some(change) ->
      Ok(
        json.object([
          #("schemaVersion", json.int(1)),
          #("contractId", json.string(value.packet.contract_id)),
          #("track", json.string(value.packet.track)),
          #("packetSha256", json.string(value.packet_sha256)),
          #("view", json.string(value.packet.view)),
          #("algorithmVersion", json.string(value.packet.algorithm_version)),
          #("change", change_json(change, value.packet.view)),
          #("decisionOwner", json.string("llm")),
          #("pluginDecisionFields", json.array([], json.string)),
        ]),
      )
  }
}

pub fn summary(value: Comparison) -> String {
  value.packet.contract_id
  <> ": "
  <> int.to_string(list.length(value.changes))
  <> " exact section change(s) under "
  <> value.packet.view
  <> "; interpretation remains with the LLM"
}

pub fn error_message(error: DiffError) -> String {
  case error {
    InvalidJson -> "Diff import is not valid JSON"
    ContentHashMismatch -> "Diff import bytes do not match expectedSha256"
    WrongSchema -> "Diff schemaVersion must be 1"
    WrongContract -> "Diff contractId does not match this plugin"
    WrongTrack -> "Diff track does not match this plugin"
    WrongMic -> "Diff subject MIC is outside this plugin scope"
    InvalidSubject -> "Diff subject identity is incomplete"
    UnsupportedView -> "Diff view must be raw or whitespace_v1"
    UnsupportedAlgorithm -> "Diff algorithmVersion must be exact_section_v1"
    UnsupportedForm -> "A document form is outside this plugin scope"
    WrongLanguage -> "A document language is outside this plugin scope"
    InvalidDocument(side) -> side <> " document metadata is invalid"
    InvalidDocumentHash(side) -> side <> " document contentSha256 is invalid"
    TooManySections(side) -> side <> " document exceeds 100 sections"
    TooManyOmissions(side) -> side <> " document exceeds 200 omissions"
    DuplicateSectionId(side) ->
      side <> " document has duplicate sectionId values"
    InvalidSection(side) ->
      side <> " document has an invalid section projection"
    InvalidCorrectionLineage -> "Document correction lineage is inconsistent"
    TooManyChanges -> "Diff exceeds the 10000-change budget"
    InvalidPage -> "Diff page requires offset >= 0 and limit 1..100"
    ChangeNotFound -> "changeId was not found in the exact comparison"
  }
}

fn validate_packet(
  descriptor: Descriptor,
  packet: Packet,
) -> Result(Nil, DiffError) {
  use _ <- result.try(case packet.schema_version == 1 {
    True -> Ok(Nil)
    False -> Error(WrongSchema)
  })
  use _ <- result.try(case packet.contract_id == descriptor.contract_id {
    True -> Ok(Nil)
    False -> Error(WrongContract)
  })
  use _ <- result.try(case packet.track == descriptor.track {
    True -> Ok(Nil)
    False -> Error(WrongTrack)
  })
  use _ <- result.try(case valid_subject(packet.subject) {
    True -> Ok(Nil)
    False -> Error(InvalidSubject)
  })
  use _ <- result.try(
    case list.contains(descriptor.allowed_mics, packet.subject.mic) {
      True -> Ok(Nil)
      False -> Error(WrongMic)
    },
  )
  use _ <- result.try(
    case list.contains(["raw", "whitespace_v1"], packet.view) {
      True -> Ok(Nil)
      False -> Error(UnsupportedView)
    },
  )
  use _ <- result.try(case packet.algorithm_version == "exact_section_v1" {
    True -> Ok(Nil)
    False -> Error(UnsupportedAlgorithm)
  })
  use _ <- result.try(validate_document(descriptor, packet.left, "left"))
  use _ <- result.try(validate_document(descriptor, packet.right, "right"))
  case packet.right.correction_of {
    None -> Ok(Nil)
    Some(id) ->
      case id == packet.left.document_id {
        True -> Ok(Nil)
        False -> Error(InvalidCorrectionLineage)
      }
  }
}

fn validate_document(
  descriptor: Descriptor,
  document: Document,
  side: String,
) -> Result(Nil, DiffError) {
  use _ <- result.try(
    case
      nonempty(document.document_id),
      nonempty(document.accession_or_event_id),
      nonempty(document.published_at),
      nonempty(document.effective_date),
      nonempty(document.source_url),
      nonempty(document.rights)
    {
      True, True, True, True, True, True -> Ok(Nil)
      _, _, _, _, _, _ -> Error(InvalidDocument(side))
    },
  )
  use _ <- result.try(
    case list.contains(descriptor.allowed_forms, document.form) {
      True -> Ok(Nil)
      False -> Error(UnsupportedForm)
    },
  )
  use _ <- result.try(case descriptor.required_language {
    None -> Ok(Nil)
    Some(language) ->
      case document.language == language {
        True -> Ok(Nil)
        False -> Error(WrongLanguage)
      }
  })
  use _ <- result.try(case list.length(document.sections) <= 100 {
    True -> Ok(Nil)
    False -> Error(TooManySections(side))
  })
  use _ <- result.try(case list.length(document.omissions) <= 200 {
    True -> Ok(Nil)
    False -> Error(TooManyOmissions(side))
  })
  use _ <- result.try(case unique_section_ids(document.sections) {
    True -> Ok(Nil)
    False -> Error(DuplicateSectionId(side))
  })
  use _ <- result.try(case list.all(document.sections, valid_section) {
    True -> Ok(Nil)
    False -> Error(InvalidSection(side))
  })
  verify_document_hash(document, side)
}

fn verify_document_hash(
  document: Document,
  side: String,
) -> Result(Nil, DiffError) {
  let projection =
    document.sections
    |> list.map(fn(section) { section.raw_text })
    |> string.join("\n")
  case hash.text(projection) {
    Error(_) -> Error(InvalidDocumentHash(side))
    Ok(value) ->
      case identity.sha256_value(value) == document.content_sha256 {
        True -> Ok(Nil)
        False -> Error(InvalidDocumentHash(side))
      }
  }
}

fn verify_hash(bytes: String, expected: String) -> Result(Nil, DiffError) {
  case hash.text(bytes) {
    Error(_) -> Error(ContentHashMismatch)
    Ok(value) ->
      case identity.sha256_value(value) == expected {
        True -> Ok(Nil)
        False -> Error(ContentHashMismatch)
      }
  }
}

fn build_changes(
  left: List(Section),
  right: List(Section),
  view: String,
) -> List(Change) {
  let left_changes = build_left_changes(left, right, view)
  let insertions =
    right
    |> list.filter_map(fn(section) {
      case find_section(left, section.section_id) {
        Some(_) -> Error(Nil)
        None ->
          Ok(Change(
            "insert:" <> section.section_id,
            "insert",
            section.section_id,
            None,
            Some(section),
          ))
      }
    })
  list.append(left_changes, insertions)
}

fn build_left_changes(
  left: List(Section),
  right: List(Section),
  view: String,
) -> List(Change) {
  left
  |> list.filter_map(fn(section) {
    case find_section(right, section.section_id) {
      None ->
        Ok(Change(
          "delete:" <> section.section_id,
          "delete",
          section.section_id,
          Some(section),
          None,
        ))
      Some(other) -> {
        let left_text = project_text(section.raw_text, view)
        let right_text = project_text(other.raw_text, view)
        case
          left_text == right_text,
          section.ordinal == other.ordinal,
          section.title == other.title
        {
          True, True, True -> Error(Nil)
          True, False, True ->
            Ok(Change(
              "move:" <> section.section_id,
              "move",
              section.section_id,
              Some(section),
              Some(other),
            ))
          _, _, _ ->
            Ok(Change(
              "replace:" <> section.section_id,
              "replace",
              section.section_id,
              Some(section),
              Some(other),
            ))
        }
      }
    }
  })
}

fn project_text(value: String, view: String) -> String {
  case view {
    "whitespace_v1" ->
      value
      |> string.split(on: " ")
      |> list.filter(fn(part) { part != "" })
      |> string.join(" ")
      |> string.trim
    _ -> value
  }
}

fn valid_subject(subject: Subject) -> Bool {
  nonempty(subject.issuer_id)
  && nonempty(subject.listing_id)
  && nonempty(subject.mic)
}

fn valid_section(section: Section) -> Bool {
  nonempty(section.section_id)
  && list.contains(
    ["section", "table", "table_row", "attachment_section"],
    section.kind,
  )
  && nonempty(section.title)
  && section.ordinal >= 0
  && section.start_offset >= 0
  && section.end_offset >= section.start_offset
  && section.end_offset - section.start_offset
  == string.length(section.raw_text)
  && string.length(section.raw_text) <= 200_000
}

fn nonempty(value: String) -> Bool {
  value != "" && value == string.trim(value) && string.length(value) <= 20_000
}

fn unique_section_ids(sections: List(Section)) -> Bool {
  let ids = list.map(sections, fn(section) { section.section_id })
  unique(ids)
}

fn unique(values: List(String)) -> Bool {
  case values {
    [] -> True
    [value, ..rest] -> !list.contains(rest, value) && unique(rest)
  }
}

fn find_section(sections: List(Section), id: String) -> Option(Section) {
  case sections {
    [] -> None
    [section, ..rest] ->
      case section.section_id == id {
        True -> Some(section)
        False -> find_section(rest, id)
      }
  }
}

fn find_change(changes: List(Change), id: String) -> Option(Change) {
  case changes {
    [] -> None
    [change, ..rest] ->
      case change.change_id == id {
        True -> Some(change)
        False -> find_change(rest, id)
      }
  }
}

fn packet_decoder() -> decode.Decoder(Packet) {
  use schema_version <- decode.field("schemaVersion", decode.int)
  use contract_id <- decode.field("contractId", decode.string)
  use track <- decode.field("track", decode.string)
  use subject <- decode.field("subject", subject_decoder())
  use view <- decode.field("view", decode.string)
  use algorithm_version <- decode.field("algorithmVersion", decode.string)
  use left <- decode.field("left", document_decoder())
  use right <- decode.field("right", document_decoder())
  decode.success(Packet(
    schema_version,
    contract_id,
    track,
    subject,
    view,
    algorithm_version,
    left,
    right,
  ))
}

fn subject_decoder() -> decode.Decoder(Subject) {
  use issuer_id <- decode.field("issuerId", decode.string)
  use listing_id <- decode.field("listingId", decode.string)
  use mic <- decode.field("mic", decode.string)
  decode.success(Subject(issuer_id, listing_id, mic))
}

fn document_decoder() -> decode.Decoder(Document) {
  use document_id <- decode.field("documentId", decode.string)
  use form <- decode.field("form", decode.string)
  use accession <- decode.field("accessionOrEventId", decode.string)
  use published_at <- decode.field("publishedAt", decode.string)
  use effective_date <- decode.field("effectiveDate", decode.string)
  use correction_of <- optional_string("correctionOf")
  use language <- decode.field("language", decode.string)
  use source_url <- decode.field("sourceUrl", decode.string)
  use rights <- decode.field("rights", decode.string)
  use content_sha256 <- decode.field("contentSha256", decode.string)
  use sections <- decode.field("sections", decode.list(section_decoder()))
  use omissions <- decode.field("omissions", decode.list(decode.string))
  decode.success(Document(
    document_id,
    form,
    accession,
    published_at,
    effective_date,
    correction_of,
    language,
    source_url,
    rights,
    content_sha256,
    sections,
    omissions,
  ))
}

fn section_decoder() -> decode.Decoder(Section) {
  use section_id <- decode.field("sectionId", decode.string)
  use kind <- decode.field("kind", decode.string)
  use title <- decode.field("title", decode.string)
  use ordinal <- decode.field("ordinal", decode.int)
  use start_offset <- decode.field("startOffset", decode.int)
  use end_offset <- decode.field("endOffset", decode.int)
  use raw_text <- decode.field("rawText", decode.string)
  decode.success(Section(
    section_id,
    kind,
    title,
    ordinal,
    start_offset,
    end_offset,
    raw_text,
  ))
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
  ])
}

fn document_header_json(document: Document) -> json.Json {
  json.object([
    #("documentId", json.string(document.document_id)),
    #("form", json.string(document.form)),
    #("accessionOrEventId", json.string(document.accession_or_event_id)),
    #("publishedAt", json.string(document.published_at)),
    #("effectiveDate", json.string(document.effective_date)),
    #("correctionOf", json.nullable(document.correction_of, json.string)),
    #("language", json.string(document.language)),
    #("sourceUrl", json.string(document.source_url)),
    #("rights", json.string(document.rights)),
    #("contentSha256", json.string(document.content_sha256)),
    #("sectionCount", json.int(list.length(document.sections))),
    #("omissions", json.array(document.omissions, json.string)),
  ])
}

fn change_header_json(change: Change) -> json.Json {
  json.object([
    #("changeId", json.string(change.change_id)),
    #("kind", json.string(change.kind)),
    #("sectionId", json.string(change.section_id)),
    #("leftAnchor", json.nullable(change.left, section_anchor_json)),
    #("rightAnchor", json.nullable(change.right, section_anchor_json)),
  ])
}

fn change_json(change: Change, view: String) -> json.Json {
  json.object([
    #("changeId", json.string(change.change_id)),
    #("kind", json.string(change.kind)),
    #("sectionId", json.string(change.section_id)),
    #("left", json.nullable(change.left, section_json)),
    #("right", json.nullable(change.right, section_json)),
    #(
      "leftProjectedText",
      json.nullable(change.left, fn(section) {
        json.string(project_text(section.raw_text, view))
      }),
    ),
    #(
      "rightProjectedText",
      json.nullable(change.right, fn(section) {
        json.string(project_text(section.raw_text, view))
      }),
    ),
  ])
}

fn section_anchor_json(section: Section) -> json.Json {
  json.object([
    #("title", json.string(section.title)),
    #("ordinal", json.int(section.ordinal)),
    #("startOffset", json.int(section.start_offset)),
    #("endOffset", json.int(section.end_offset)),
  ])
}

fn section_json(section: Section) -> json.Json {
  json.object([
    #("sectionId", json.string(section.section_id)),
    #("kind", json.string(section.kind)),
    #("title", json.string(section.title)),
    #("ordinal", json.int(section.ordinal)),
    #("startOffset", json.int(section.start_offset)),
    #("endOffset", json.int(section.end_offset)),
    #("rawText", json.string(section.raw_text)),
  ])
}
