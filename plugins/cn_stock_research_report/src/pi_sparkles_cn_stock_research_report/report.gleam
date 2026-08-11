import finance_provenance/hash
import finance_provenance/identity
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub type Subject {
  Subject(
    issuer_id: String,
    listing_id: String,
    mic: String,
    share_class: String,
  )
}

pub type Fact {
  Fact(
    name: String,
    state: String,
    value_lexeme: Option(String),
    unit: Option(String),
    source_handle: String,
  )
}

pub type Translation {
  Translation(
    original_section_id: String,
    translator: String,
    translated_at: String,
    source_span: String,
  )
}

pub type Section {
  Section(
    section_id: String,
    kind: String,
    language: String,
    receipt_id: String,
    source_role: String,
    content_sha256: String,
    translation: Option(Translation),
    facts: List(Fact),
    conflicts: List(String),
    omissions: List(String),
  )
}

pub opaque type Report {
  Report(
    subject: Subject,
    as_of_date: String,
    sections: List(Section),
    omissions: List(String),
    packet_sha256: String,
  )
}

pub type ReportError {
  InvalidJson
  ContentHashMismatch
  WrongSchema
  WrongContract
  WrongTrack
  WrongMic
  InvalidSubject
  InvalidAsOfDate
  TooManySections
  TooManyOmissions
  DuplicateSectionId
  UnsupportedSectionKind
  InvalidSection
  InvalidTranslation
  InvalidFact
  DuplicateFact
  InvalidPage
  SectionNotFound
}

pub fn compose(
  expected_sha256: String,
  bytes: String,
) -> Result(Report, ReportError) {
  use _ <- result.try(verify_hash(bytes, expected_sha256))
  use packet <- result.try(case json.parse(bytes, packet_decoder()) {
    Ok(value) -> Ok(value)
    Error(_) -> Error(InvalidJson)
  })
  let #(version, contract, track, subject, as_of_date, sections, omissions) =
    packet
  use _ <- result.try(case version == 1 {
    True -> Ok(Nil)
    False -> Error(WrongSchema)
  })
  use _ <- result.try(case contract == "cn_stock_research_report_v1" {
    True -> Ok(Nil)
    False -> Error(WrongContract)
  })
  use _ <- result.try(case track == "cn" {
    True -> Ok(Nil)
    False -> Error(WrongTrack)
  })
  use _ <- result.try(case valid_subject(subject) {
    True -> Ok(Nil)
    False -> Error(InvalidSubject)
  })
  use _ <- result.try(
    case list.contains(["XSHG", "XSHE", "XBSE"], subject.mic) {
      True -> Ok(Nil)
      False -> Error(WrongMic)
    },
  )
  use _ <- result.try(case valid_date(as_of_date) {
    True -> Ok(Nil)
    False -> Error(InvalidAsOfDate)
  })
  use _ <- result.try(case list.length(sections) <= 20 {
    True -> Ok(Nil)
    False -> Error(TooManySections)
  })
  use _ <- result.try(case list.length(omissions) <= 200 {
    True -> Ok(Nil)
    False -> Error(TooManyOmissions)
  })
  use _ <- result.try(case unique_sections(sections) {
    True -> Ok(Nil)
    False -> Error(DuplicateSectionId)
  })
  use _ <- result.try(validate_sections(sections, sections))
  Ok(Report(subject, as_of_date, sections, omissions, expected_sha256))
}

pub fn inspect(
  value: Report,
  offset: Int,
  limit: Int,
) -> Result(json.Json, ReportError) {
  use _ <- result.try(case offset >= 0 && limit >= 1 && limit <= 20 {
    True -> Ok(Nil)
    False -> Error(InvalidPage)
  })
  let page = value.sections |> list.drop(offset) |> list.take(limit)
  let total = list.length(value.sections)
  let next = case offset + list.length(page) < total {
    True -> json.int(offset + list.length(page))
    False -> json.null()
  }
  Ok(
    json.object(
      list.append(header_fields(value), [
        #("sectionCount", json.int(total)),
        #(
          "originalChineseSectionCount",
          json.int(count_original(value.sections)),
        ),
        #(
          "translationSectionCount",
          json.int(count_translations(value.sections)),
        ),
        #(
          "sectionOmissionCount",
          json.int(count_section_omissions(value.sections)),
        ),
        #("offset", json.int(offset)),
        #("nextOffset", next),
        #("sections", json.array(page, section_header_json)),
        #("decisionOwner", json.string("llm")),
        #("pluginDecisionFields", json.array([], json.string)),
      ]),
    ),
  )
}

pub fn drill(
  value: Report,
  section_id: String,
) -> Result(json.Json, ReportError) {
  case find_section(value.sections, section_id) {
    None -> Error(SectionNotFound)
    Some(section) ->
      Ok(
        json.object(
          list.append(header_fields(value), [
            #("section", section_json(section)),
            #("decisionOwner", json.string("llm")),
            #("pluginDecisionFields", json.array([], json.string)),
          ]),
        ),
      )
  }
}

pub fn summary(value: Report) -> String {
  "cn_stock_research_report_v1: "
  <> int.to_string(list.length(value.sections))
  <> " caller-selected receipt section(s), originals="
  <> int.to_string(count_original(value.sections))
  <> ", translations="
  <> int.to_string(count_translations(value.sections))
  <> "; report interpretation remains with the LLM"
}

pub fn error_message(error: ReportError) -> String {
  case error {
    InvalidJson -> "CN report import is not valid JSON"
    ContentHashMismatch -> "CN report bytes do not match expectedSha256"
    WrongSchema -> "CN report schemaVersion must be 1"
    WrongContract -> "CN report contractId must be cn_stock_research_report_v1"
    WrongTrack -> "CN report track must be cn"
    WrongMic -> "CN report MIC must be XSHG, XSHE, or XBSE"
    InvalidSubject -> "CN report subject identity is incomplete"
    InvalidAsOfDate -> "CN report asOfDate must be YYYY-MM-DD"
    TooManySections -> "CN report exceeds the 20-section budget"
    TooManyOmissions -> "CN report exceeds the 200-report-omission budget"
    DuplicateSectionId -> "CN report has duplicate sectionId values"
    UnsupportedSectionKind -> "CN report contains an unsupported section kind"
    InvalidSection ->
      "CN report contains invalid receipt, source, hash, conflict, or omission metadata"
    InvalidTranslation -> "CN original/translation lineage is invalid"
    InvalidFact -> "CN report contains an invalid fact state or source handle"
    DuplicateFact -> "CN report section contains duplicate fact names"
    InvalidPage -> "CN report page requires offset >= 0 and limit 1..20"
    SectionNotFound -> "sectionId was not found in the exact CN report"
  }
}

fn validate_sections(
  remaining: List(Section),
  all: List(Section),
) -> Result(Nil, ReportError) {
  case remaining {
    [] -> Ok(Nil)
    [section, ..rest] -> {
      use _ <- result.try(validate_section(section, all))
      validate_sections(rest, all)
    }
  }
}

fn validate_section(
  section: Section,
  all: List(Section),
) -> Result(Nil, ReportError) {
  use _ <- result.try(
    case
      list.contains(
        [
          "identity",
          "disclosures",
          "financials",
          "peers",
          "comparables",
          "valuation",
          "industry",
        ],
        section.kind,
      )
    {
      True -> Ok(Nil)
      False -> Error(UnsupportedSectionKind)
    },
  )
  use _ <- result.try(
    case
      nonempty(section.section_id)
      && nonempty(section.language)
      && nonempty(section.receipt_id)
      && nonempty(section.source_role)
      && valid_sha(section.content_sha256)
      && list.length(section.facts) <= 200
      && list.length(section.conflicts) <= 100
      && list.length(section.omissions) <= 100
    {
      True -> Ok(Nil)
      False -> Error(InvalidSection)
    },
  )
  use _ <- result.try(validate_translation(section, all))
  use _ <- result.try(case unique_fact_names(section.facts) {
    True -> Ok(Nil)
    False -> Error(DuplicateFact)
  })
  case list.all(section.facts, valid_fact) {
    True -> Ok(Nil)
    False -> Error(InvalidFact)
  }
}

fn validate_translation(
  section: Section,
  all: List(Section),
) -> Result(Nil, ReportError) {
  case section.translation {
    None ->
      case section.language == "zh-CN" {
        True -> Ok(Nil)
        False -> Error(InvalidTranslation)
      }
    Some(translation) ->
      case
        section.language != "zh-CN",
        nonempty(translation.original_section_id),
        nonempty(translation.translator),
        nonempty(translation.translated_at),
        nonempty(translation.source_span),
        find_section(all, translation.original_section_id)
      {
        True, True, True, True, True, Some(original) ->
          case
            original.translation == None
            && original.language == "zh-CN"
            && original.kind == section.kind
          {
            True -> Ok(Nil)
            False -> Error(InvalidTranslation)
          }
        _, _, _, _, _, _ -> Error(InvalidTranslation)
      }
  }
}

fn valid_fact(value: Fact) -> Bool {
  nonempty(value.name)
  && nonempty(value.source_handle)
  && list.contains(
    ["known", "unknown", "conflicting", "not_obtained", "not_applicable"],
    value.state,
  )
  && case value.state, value.value_lexeme {
    "known", Some(text) -> nonempty(text)
    "known", None -> False
    _, _ -> True
  }
}

fn valid_subject(value: Subject) -> Bool {
  nonempty(value.issuer_id)
  && nonempty(value.listing_id)
  && nonempty(value.mic)
  && nonempty(value.share_class)
}

fn valid_date(value: String) -> Bool {
  string.length(value) == 10
  && string.slice(value, 4, 1) == "-"
  && string.slice(value, 7, 1) == "-"
}

fn valid_sha(value: String) -> Bool {
  string.length(value) == 64
}

fn nonempty(value: String) -> Bool {
  value != "" && value == string.trim(value) && string.length(value) <= 20_000
}

fn unique_sections(values: List(Section)) -> Bool {
  unique_strings(list.map(values, fn(value) { value.section_id }))
}

fn unique_fact_names(values: List(Fact)) -> Bool {
  unique_strings(list.map(values, fn(value) { value.name }))
}

fn unique_strings(values: List(String)) -> Bool {
  case values {
    [] -> True
    [value, ..rest] -> !list.contains(rest, value) && unique_strings(rest)
  }
}

fn count_original(values: List(Section)) -> Int {
  values |> list.filter(fn(value) { value.translation == None }) |> list.length
}

fn count_translations(values: List(Section)) -> Int {
  values |> list.filter(fn(value) { value.translation != None }) |> list.length
}

fn count_section_omissions(values: List(Section)) -> Int {
  values
  |> list.fold(0, fn(total, value) { total + list.length(value.omissions) })
}

fn find_section(values: List(Section), id: String) -> Option(Section) {
  case values {
    [] -> None
    [value, ..rest] ->
      case value.section_id == id {
        True -> Some(value)
        False -> find_section(rest, id)
      }
  }
}

fn verify_hash(bytes: String, expected: String) -> Result(Nil, ReportError) {
  case hash.text(bytes) {
    Error(_) -> Error(ContentHashMismatch)
    Ok(actual) ->
      case identity.sha256_value(actual) == expected {
        True -> Ok(Nil)
        False -> Error(ContentHashMismatch)
      }
  }
}

fn packet_decoder() -> decode.Decoder(
  #(Int, String, String, Subject, String, List(Section), List(String)),
) {
  use version <- decode.field("schemaVersion", decode.int)
  use contract <- decode.field("contractId", decode.string)
  use track <- decode.field("track", decode.string)
  use subject <- decode.field("subject", subject_decoder())
  use as_of <- decode.field("asOfDate", decode.string)
  use sections <- decode.field("sections", decode.list(section_decoder()))
  use omissions <- decode.field("omissions", decode.list(decode.string))
  decode.success(#(
    version,
    contract,
    track,
    subject,
    as_of,
    sections,
    omissions,
  ))
}

fn subject_decoder() -> decode.Decoder(Subject) {
  use issuer <- decode.field("issuerId", decode.string)
  use listing <- decode.field("listingId", decode.string)
  use mic <- decode.field("mic", decode.string)
  use share <- decode.field("shareClass", decode.string)
  decode.success(Subject(issuer, listing, mic, share))
}

fn fact_decoder() -> decode.Decoder(Fact) {
  use name <- decode.field("name", decode.string)
  use state <- decode.field("state", decode.string)
  use value <- optional_string("valueLexeme")
  use unit <- optional_string("unit")
  use source <- decode.field("sourceHandle", decode.string)
  decode.success(Fact(name, state, value, unit, source))
}

fn translation_decoder() -> decode.Decoder(Translation) {
  use original <- decode.field("originalSectionId", decode.string)
  use translator <- decode.field("translator", decode.string)
  use at <- decode.field("translatedAt", decode.string)
  use span <- decode.field("sourceSpan", decode.string)
  decode.success(Translation(original, translator, at, span))
}

fn section_decoder() -> decode.Decoder(Section) {
  use id <- decode.field("sectionId", decode.string)
  use kind <- decode.field("kind", decode.string)
  use language <- decode.field("language", decode.string)
  use receipt <- decode.field("receiptId", decode.string)
  use role <- decode.field("sourceRole", decode.string)
  use content_hash <- decode.field("contentSha256", decode.string)
  use translation <- optional_translation("translation")
  use facts <- decode.field("facts", decode.list(fact_decoder()))
  use conflicts <- decode.field("conflicts", decode.list(decode.string))
  use omissions <- decode.field("omissions", decode.list(decode.string))
  decode.success(Section(
    id,
    kind,
    language,
    receipt,
    role,
    content_hash,
    translation,
    facts,
    conflicts,
    omissions,
  ))
}

fn optional_string(
  name: String,
  next: fn(Option(String)) -> decode.Decoder(value),
) -> decode.Decoder(value) {
  decode.optional_field(name, None, decode.optional(decode.string), next)
}

fn optional_translation(
  name: String,
  next: fn(Option(Translation)) -> decode.Decoder(value),
) -> decode.Decoder(value) {
  decode.optional_field(
    name,
    None,
    decode.optional(translation_decoder()),
    next,
  )
}

fn header_fields(value: Report) -> List(#(String, json.Json)) {
  [
    #("schemaVersion", json.int(1)),
    #("contractId", json.string("cn_stock_research_report_v1")),
    #("track", json.string("cn")),
    #("subject", subject_json(value.subject)),
    #("asOfDate", json.string(value.as_of_date)),
    #("packetSha256", json.string(value.packet_sha256)),
    #("omissions", json.array(value.omissions, json.string)),
  ]
}

fn subject_json(value: Subject) -> json.Json {
  json.object([
    #("issuerId", json.string(value.issuer_id)),
    #("listingId", json.string(value.listing_id)),
    #("mic", json.string(value.mic)),
    #("shareClass", json.string(value.share_class)),
  ])
}

fn fact_json(value: Fact) -> json.Json {
  json.object([
    #("name", json.string(value.name)),
    #("state", json.string(value.state)),
    #("valueLexeme", json.nullable(value.value_lexeme, json.string)),
    #("unit", json.nullable(value.unit, json.string)),
    #("sourceHandle", json.string(value.source_handle)),
  ])
}

fn translation_json(value: Translation) -> json.Json {
  json.object([
    #("originalSectionId", json.string(value.original_section_id)),
    #("translator", json.string(value.translator)),
    #("translatedAt", json.string(value.translated_at)),
    #("sourceSpan", json.string(value.source_span)),
  ])
}

fn section_header_json(value: Section) -> json.Json {
  json.object([
    #("sectionId", json.string(value.section_id)),
    #("kind", json.string(value.kind)),
    #("language", json.string(value.language)),
    #("receiptId", json.string(value.receipt_id)),
    #("sourceRole", json.string(value.source_role)),
    #("contentSha256", json.string(value.content_sha256)),
    #("translation", json.nullable(value.translation, translation_json)),
    #("factCount", json.int(list.length(value.facts))),
    #("conflictCount", json.int(list.length(value.conflicts))),
    #("omissionCount", json.int(list.length(value.omissions))),
  ])
}

fn section_json(value: Section) -> json.Json {
  json.object([
    #("sectionId", json.string(value.section_id)),
    #("kind", json.string(value.kind)),
    #("language", json.string(value.language)),
    #("receiptId", json.string(value.receipt_id)),
    #("sourceRole", json.string(value.source_role)),
    #("contentSha256", json.string(value.content_sha256)),
    #("translation", json.nullable(value.translation, translation_json)),
    #("facts", json.array(value.facts, fact_json)),
    #("conflicts", json.array(value.conflicts, json.string)),
    #("omissions", json.array(value.omissions, json.string)),
  ])
}
