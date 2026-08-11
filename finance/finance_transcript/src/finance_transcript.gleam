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
  Subject(issuer_id: String, listing_id: String, mic: String)
}

pub type Event {
  Event(event_id: String, fiscal_period: String, occurred_at: String)
}

pub type Source {
  Source(
    provider: String,
    source_kind: String,
    published_at: String,
    retrieved_at: String,
    language: String,
    rights: String,
    source_url: String,
    correction_of: Option(String),
    content_sha256: String,
  )
}

pub type Segment {
  Segment(
    segment_id: String,
    ordinal: Int,
    speaker_id: Option(String),
    speaker_name: String,
    speaker_role: String,
    speaker_state: String,
    start_offset: Int,
    end_offset: Int,
    text: String,
  )
}

pub opaque type Transcript {
  Transcript(
    contract_id: String,
    track: String,
    subject: Subject,
    event: Event,
    source: Source,
    segments: List(Segment),
    omissions: List(String),
    packet_sha256: String,
  )
}

pub type TranscriptError {
  InvalidJson
  ContentHashMismatch
  WrongSchema
  WrongContract
  WrongTrack
  WrongMic
  InvalidSubject
  InvalidEvent
  InvalidSource
  RightsNotPermitted
  TooManySegments
  TooManyOmissions
  DuplicateSegmentId
  DuplicateOrdinal
  InvalidSegment
  InvalidContentHash
  InvalidQuery
  InvalidPage
  SegmentNotFound
}

pub fn load(
  expected_sha256: String,
  bytes: String,
) -> Result(Transcript, TranscriptError) {
  use _ <- result.try(verify_hash(bytes, expected_sha256))
  use decoded <- result.try(case json.parse(bytes, packet_decoder()) {
    Ok(value) -> Ok(value)
    Error(_) -> Error(InvalidJson)
  })
  let #(
    schema_version,
    contract_id,
    track,
    subject,
    event,
    source,
    segments,
    omissions,
  ) = decoded
  use _ <- result.try(case schema_version == 1 {
    True -> Ok(Nil)
    False -> Error(WrongSchema)
  })
  use _ <- result.try(case contract_id == "earnings_transcript_v1" {
    True -> Ok(Nil)
    False -> Error(WrongContract)
  })
  use _ <- result.try(case list.contains(["cn", "hk", "us"], track) {
    True -> Ok(Nil)
    False -> Error(WrongTrack)
  })
  use _ <- result.try(case valid_subject(subject) {
    True -> Ok(Nil)
    False -> Error(InvalidSubject)
  })
  use _ <- result.try(case valid_track_mic(track, subject.mic) {
    True -> Ok(Nil)
    False -> Error(WrongMic)
  })
  use _ <- result.try(case valid_event(event) {
    True -> Ok(Nil)
    False -> Error(InvalidEvent)
  })
  use _ <- result.try(validate_source(source))
  use _ <- result.try(case list.length(segments) <= 5000 {
    True -> Ok(Nil)
    False -> Error(TooManySegments)
  })
  use _ <- result.try(case list.length(omissions) <= 200 {
    True -> Ok(Nil)
    False -> Error(TooManyOmissions)
  })
  use _ <- result.try(case unique_ids(segments) {
    True -> Ok(Nil)
    False -> Error(DuplicateSegmentId)
  })
  use _ <- result.try(case unique_ordinals(segments) {
    True -> Ok(Nil)
    False -> Error(DuplicateOrdinal)
  })
  use _ <- result.try(case list.all(segments, valid_segment) {
    True -> Ok(Nil)
    False -> Error(InvalidSegment)
  })
  use _ <- result.try(verify_content_hash(source.content_sha256, segments))
  Ok(Transcript(
    contract_id,
    track,
    subject,
    event,
    source,
    segments,
    omissions,
    expected_sha256,
  ))
}

pub fn search(
  value: Transcript,
  query: String,
  case_sensitive: Bool,
  offset: Int,
  limit: Int,
) -> Result(json.Json, TranscriptError) {
  use _ <- result.try(validate_query(query))
  use _ <- result.try(validate_page(offset, limit))
  let matches =
    value.segments
    |> list.filter(fn(segment) { contains(segment.text, query, case_sensitive) })
  let page = matches |> list.drop(offset) |> list.take(limit)
  let total = list.length(matches)
  let next = case offset + list.length(page) < total {
    True -> json.int(offset + list.length(page))
    False -> json.null()
  }
  Ok(
    json.object(
      list.append(header_fields(value), [
        #("query", json.string(query)),
        #("caseSensitive", json.bool(case_sensitive)),
        #("matchCount", json.int(total)),
        #("offset", json.int(offset)),
        #("nextOffset", next),
        #("matches", json.array(page, segment_json)),
        #("decisionOwner", json.string("llm")),
        #("pluginDecisionFields", json.array([], json.string)),
      ]),
    ),
  )
}

pub fn excerpt(
  value: Transcript,
  segment_id: String,
  context_segments: Int,
) -> Result(json.Json, TranscriptError) {
  case find_segment(value.segments, segment_id) {
    None -> Error(SegmentNotFound)
    Some(selected) ->
      case context_segments >= 0 && context_segments <= 5 {
        False -> Error(InvalidPage)
        True -> {
          let first = selected.ordinal - context_segments
          let last = selected.ordinal + context_segments
          let excerpt =
            value.segments
            |> list.filter(fn(segment) {
              segment.ordinal >= first && segment.ordinal <= last
            })
          Ok(
            json.object(
              list.append(header_fields(value), [
                #("selectedSegmentId", json.string(segment_id)),
                #("contextSegments", json.int(context_segments)),
                #("segments", json.array(excerpt, segment_json)),
                #("decisionOwner", json.string("llm")),
                #("pluginDecisionFields", json.array([], json.string)),
              ]),
            ),
          )
        }
      }
  }
}

pub fn align(
  left: Transcript,
  right: Transcript,
  query: String,
  case_sensitive: Bool,
  maximum_matches_per_side: Int,
) -> Result(json.Json, TranscriptError) {
  use _ <- result.try(validate_query(query))
  use _ <- result.try(
    case maximum_matches_per_side >= 1 && maximum_matches_per_side <= 50 {
      True -> Ok(Nil)
      False -> Error(InvalidPage)
    },
  )
  let left_matches =
    left.segments
    |> list.filter(fn(segment) { contains(segment.text, query, case_sensitive) })
    |> list.take(maximum_matches_per_side)
  let right_matches =
    right.segments
    |> list.filter(fn(segment) { contains(segment.text, query, case_sensitive) })
    |> list.take(maximum_matches_per_side)
  Ok(
    json.object([
      #("schemaVersion", json.int(1)),
      #("operation", json.string("exact_topic_passage_alignment_v1")),
      #("query", json.string(query)),
      #("caseSensitive", json.bool(case_sensitive)),
      #("leftTranscript", header_json(left)),
      #("rightTranscript", header_json(right)),
      #("leftMatches", json.array(left_matches, segment_json)),
      #("rightMatches", json.array(right_matches, segment_json)),
      #(
        "alignmentMeaning",
        json.string("same_exact_query_only_not_semantic_equivalence"),
      ),
      #("decisionOwner", json.string("llm")),
      #("pluginDecisionFields", json.array([], json.string)),
    ]),
  )
}

pub fn summary(value: Transcript) -> String {
  "earnings_transcript_v1: "
  <> int.to_string(list.length(value.segments))
  <> " exact speaker segment(s), rights="
  <> value.source.rights
  <> "; interpretation remains with the LLM"
}

pub fn error_message(error: TranscriptError) -> String {
  case error {
    InvalidJson -> "Transcript import is not valid JSON"
    ContentHashMismatch -> "Transcript import bytes do not match expectedSha256"
    WrongSchema -> "Transcript schemaVersion must be 1"
    WrongContract -> "Transcript contractId must be earnings_transcript_v1"
    WrongTrack -> "Transcript track must be cn, hk, or us"
    WrongMic -> "Transcript MIC does not match its exact track"
    InvalidSubject -> "Transcript subject identity is incomplete"
    InvalidEvent -> "Transcript event identity is incomplete"
    InvalidSource ->
      "Transcript source identity or correction lineage is incomplete"
    RightsNotPermitted -> "Transcript rights must explicitly permit caller use"
    TooManySegments -> "Transcript exceeds the 5000-segment budget"
    TooManyOmissions -> "Transcript exceeds the 200-omission budget"
    DuplicateSegmentId -> "Transcript has duplicate segmentId values"
    DuplicateOrdinal -> "Transcript has duplicate segment ordinals"
    InvalidSegment -> "Transcript contains an invalid speaker segment or offset"
    InvalidContentHash ->
      "Transcript source contentSha256 does not bind exact segment text"
    InvalidQuery -> "Transcript query must contain 1..200 trimmed characters"
    InvalidPage -> "Transcript bounds are invalid"
    SegmentNotFound -> "segmentId was not found in the exact transcript"
  }
}

fn validate_source(source: Source) -> Result(Nil, TranscriptError) {
  use _ <- result.try(
    case
      nonempty(source.provider),
      nonempty(source.source_kind),
      nonempty(source.published_at),
      nonempty(source.retrieved_at),
      nonempty(source.language),
      nonempty(source.source_url)
    {
      True, True, True, True, True, True -> Ok(Nil)
      _, _, _, _, _, _ -> Error(InvalidSource)
    },
  )
  case
    list.contains(
      ["licensed_for_user", "caller_owned", "public_record"],
      source.rights,
    )
  {
    True -> Ok(Nil)
    False -> Error(RightsNotPermitted)
  }
}

fn verify_content_hash(
  expected: String,
  segments: List(Segment),
) -> Result(Nil, TranscriptError) {
  let text =
    segments |> list.map(fn(segment) { segment.text }) |> string.join("\n")
  case hash.text(text) {
    Error(_) -> Error(InvalidContentHash)
    Ok(actual) ->
      case identity.sha256_value(actual) == expected {
        True -> Ok(Nil)
        False -> Error(InvalidContentHash)
      }
  }
}

fn verify_hash(
  bytes: String,
  expected: String,
) -> Result(Nil, TranscriptError) {
  case hash.text(bytes) {
    Error(_) -> Error(ContentHashMismatch)
    Ok(actual) ->
      case identity.sha256_value(actual) == expected {
        True -> Ok(Nil)
        False -> Error(ContentHashMismatch)
      }
  }
}

fn validate_query(query: String) -> Result(Nil, TranscriptError) {
  case
    query == string.trim(query)
    && string.length(query) >= 1
    && string.length(query) <= 200
  {
    True -> Ok(Nil)
    False -> Error(InvalidQuery)
  }
}

fn validate_page(offset: Int, limit: Int) -> Result(Nil, TranscriptError) {
  case offset >= 0 && limit >= 1 && limit <= 100 {
    True -> Ok(Nil)
    False -> Error(InvalidPage)
  }
}

fn contains(text: String, query: String, case_sensitive: Bool) -> Bool {
  case case_sensitive {
    True -> string.contains(text, query)
    False -> string.contains(string.lowercase(text), string.lowercase(query))
  }
}

fn valid_subject(subject: Subject) -> Bool {
  nonempty(subject.issuer_id)
  && nonempty(subject.listing_id)
  && nonempty(subject.mic)
}

fn valid_track_mic(track: String, mic: String) -> Bool {
  case track {
    "cn" -> list.contains(["XSHG", "XSHE", "XBSE"], mic)
    "hk" -> mic == "XHKG"
    "us" -> list.contains(["XNYS", "XNAS"], mic)
    _ -> False
  }
}

fn valid_event(event: Event) -> Bool {
  nonempty(event.event_id)
  && nonempty(event.fiscal_period)
  && nonempty(event.occurred_at)
}

fn valid_segment(segment: Segment) -> Bool {
  nonempty(segment.segment_id)
  && segment.ordinal >= 0
  && nonempty(segment.speaker_name)
  && nonempty(segment.speaker_role)
  && list.contains(
    ["known", "unknown", "misattributed", "redacted"],
    segment.speaker_state,
  )
  && case segment.speaker_state, segment.speaker_id {
    "known", Some(value) -> nonempty(value)
    "known", None -> False
    _, _ -> True
  }
  && segment.start_offset >= 0
  && segment.end_offset - segment.start_offset == string.length(segment.text)
  && string.length(segment.text) <= 20_000
}

fn nonempty(value: String) -> Bool {
  value != "" && value == string.trim(value) && string.length(value) <= 20_000
}

fn unique_ids(segments: List(Segment)) -> Bool {
  unique_strings(list.map(segments, fn(segment) { segment.segment_id }))
}

fn unique_ordinals(segments: List(Segment)) -> Bool {
  unique_ints(list.map(segments, fn(segment) { segment.ordinal }))
}

fn unique_strings(values: List(String)) -> Bool {
  case values {
    [] -> True
    [value, ..rest] -> !list.contains(rest, value) && unique_strings(rest)
  }
}

fn unique_ints(values: List(Int)) -> Bool {
  case values {
    [] -> True
    [value, ..rest] -> !list.contains(rest, value) && unique_ints(rest)
  }
}

fn find_segment(segments: List(Segment), id: String) -> Option(Segment) {
  case segments {
    [] -> None
    [segment, ..rest] ->
      case segment.segment_id == id {
        True -> Some(segment)
        False -> find_segment(rest, id)
      }
  }
}

fn packet_decoder() -> decode.Decoder(
  #(Int, String, String, Subject, Event, Source, List(Segment), List(String)),
) {
  use schema_version <- decode.field("schemaVersion", decode.int)
  use contract_id <- decode.field("contractId", decode.string)
  use track <- decode.field("track", decode.string)
  use subject <- decode.field("subject", subject_decoder())
  use event <- decode.field("event", event_decoder())
  use source <- decode.field("source", source_decoder())
  use segments <- decode.field("segments", decode.list(segment_decoder()))
  use omissions <- decode.field("omissions", decode.list(decode.string))
  decode.success(#(
    schema_version,
    contract_id,
    track,
    subject,
    event,
    source,
    segments,
    omissions,
  ))
}

fn subject_decoder() -> decode.Decoder(Subject) {
  use issuer <- decode.field("issuerId", decode.string)
  use listing <- decode.field("listingId", decode.string)
  use mic <- decode.field("mic", decode.string)
  decode.success(Subject(issuer, listing, mic))
}

fn event_decoder() -> decode.Decoder(Event) {
  use id <- decode.field("eventId", decode.string)
  use period <- decode.field("fiscalPeriod", decode.string)
  use occurred <- decode.field("occurredAt", decode.string)
  decode.success(Event(id, period, occurred))
}

fn source_decoder() -> decode.Decoder(Source) {
  use provider <- decode.field("provider", decode.string)
  use kind <- decode.field("sourceKind", decode.string)
  use published <- decode.field("publishedAt", decode.string)
  use retrieved <- decode.field("retrievedAt", decode.string)
  use language <- decode.field("language", decode.string)
  use rights <- decode.field("rights", decode.string)
  use url <- decode.field("sourceUrl", decode.string)
  use correction <- optional_string("correctionOf")
  use content_hash <- decode.field("contentSha256", decode.string)
  decode.success(Source(
    provider,
    kind,
    published,
    retrieved,
    language,
    rights,
    url,
    correction,
    content_hash,
  ))
}

fn segment_decoder() -> decode.Decoder(Segment) {
  use id <- decode.field("segmentId", decode.string)
  use ordinal <- decode.field("ordinal", decode.int)
  use speaker_id <- optional_string("speakerId")
  use name <- decode.field("speakerName", decode.string)
  use role <- decode.field("speakerRole", decode.string)
  use state <- decode.field("speakerState", decode.string)
  use start <- decode.field("startOffset", decode.int)
  use end <- decode.field("endOffset", decode.int)
  use text <- decode.field("text", decode.string)
  decode.success(Segment(
    id,
    ordinal,
    speaker_id,
    name,
    role,
    state,
    start,
    end,
    text,
  ))
}

fn optional_string(
  name: String,
  next: fn(Option(String)) -> decode.Decoder(value),
) -> decode.Decoder(value) {
  decode.optional_field(name, None, decode.optional(decode.string), next)
}

fn header_fields(value: Transcript) -> List(#(String, json.Json)) {
  [
    #("schemaVersion", json.int(1)),
    #("contractId", json.string(value.contract_id)),
    #("track", json.string(value.track)),
    #("subject", subject_json(value.subject)),
    #("event", event_json(value.event)),
    #("source", source_json(value.source)),
    #("packetSha256", json.string(value.packet_sha256)),
    #("segmentCount", json.int(list.length(value.segments))),
    #("omissions", json.array(value.omissions, json.string)),
  ]
}

fn header_json(value: Transcript) -> json.Json {
  json.object(header_fields(value))
}

fn subject_json(value: Subject) -> json.Json {
  json.object([
    #("issuerId", json.string(value.issuer_id)),
    #("listingId", json.string(value.listing_id)),
    #("mic", json.string(value.mic)),
  ])
}

fn event_json(value: Event) -> json.Json {
  json.object([
    #("eventId", json.string(value.event_id)),
    #("fiscalPeriod", json.string(value.fiscal_period)),
    #("occurredAt", json.string(value.occurred_at)),
  ])
}

fn source_json(value: Source) -> json.Json {
  json.object([
    #("provider", json.string(value.provider)),
    #("sourceKind", json.string(value.source_kind)),
    #("publishedAt", json.string(value.published_at)),
    #("retrievedAt", json.string(value.retrieved_at)),
    #("language", json.string(value.language)),
    #("rights", json.string(value.rights)),
    #("sourceUrl", json.string(value.source_url)),
    #("correctionOf", json.nullable(value.correction_of, json.string)),
    #("contentSha256", json.string(value.content_sha256)),
  ])
}

fn segment_json(value: Segment) -> json.Json {
  json.object([
    #("segmentId", json.string(value.segment_id)),
    #("ordinal", json.int(value.ordinal)),
    #("speakerId", json.nullable(value.speaker_id, json.string)),
    #("speakerName", json.string(value.speaker_name)),
    #("speakerRole", json.string(value.speaker_role)),
    #("speakerState", json.string(value.speaker_state)),
    #("startOffset", json.int(value.start_offset)),
    #("endOffset", json.int(value.end_offset)),
    #("text", json.string(value.text)),
  ])
}
