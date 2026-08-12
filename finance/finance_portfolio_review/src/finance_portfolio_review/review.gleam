import finance_provenance/hash
import finance_provenance/identity
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub opaque type State {
  State(
    revision: Int,
    events_reversed: List(Event),
    events_by_id: Dict(String, Event),
    events_by_idempotency: Dict(String, Event),
    events_by_review_id: Dict(String, Event),
  )
}

pub type Outcome {
  Stored(event_id: String)
  AlreadyStored(event_id: String)
}

type Event {
  Event(
    revision: Int,
    event_id: String,
    idempotency_key: String,
    review_id: String,
    snapshot_id: String,
    review_as_of: String,
    reviewer_kind: String,
    reviewer_id: String,
    prior_review_id: Option(String),
    supersedes: Option(String),
    changed_sections: List(String),
    receipt_links: List(ReceiptLink),
    conclusion_ref: Option(String),
    privacy: String,
    canonical_hash: String,
  )
}

type ReceiptLink {
  ReceiptLink(section: String, receipt: String)
}

type Draft {
  Draft(
    schema_version: Int,
    contract_id: String,
    review_id: String,
    snapshot_id: String,
    review_as_of: String,
    reviewer_kind: String,
    reviewer_id: String,
    prior_review_id: Option(String),
    supersedes: Option(String),
    changed_sections: List(String),
    receipt_links: List(ReceiptLink),
    conclusion_ref: Option(String),
    privacy: String,
  )
}

pub type ReviewError {
  InvalidJson
  ContentHashMismatch
  InvalidDraft
  InvalidReceipt(section: String)
  DuplicateSection(section: String)
  RevisionConflict(current: Int)
  IdempotencyConflict(key: String)
  DuplicateEventId(event_id: String)
  DuplicateReviewId(review_id: String)
  PriorReviewMissing(review_id: String)
  SupersededReviewMissing(review_id: String)
  ReviewNotFound(review_id: String)
  InvalidJournal(line: Int)
  TooManyEvents
}

pub fn empty() -> State {
  State(0, [], dict.new(), dict.new(), dict.new())
}

pub fn revision(state: State) -> Int {
  state.revision
}

pub fn append(
  state: State,
  expected_revision: Int,
  event_id: String,
  idempotency_key: String,
  packet: String,
  expected_sha256: String,
) -> Result(#(State, Outcome, json.Json), ReviewError) {
  use _ <- result.try(verify_hash(packet, expected_sha256))
  use draft <- result.try(
    json.parse(packet, draft_decoder())
    |> result.map_error(fn(_) { InvalidJson }),
  )
  case dict.get(state.events_by_idempotency, idempotency_key) {
    Ok(existing) ->
      case same_draft(existing, draft) {
        True ->
          Ok(#(state, AlreadyStored(existing.event_id), event_json(existing)))
        False -> Error(IdempotencyConflict(idempotency_key))
      }
    Error(_) -> {
      use _ <- result.try(case state.revision == expected_revision {
        True -> Ok(Nil)
        False -> Error(RevisionConflict(state.revision))
      })
      append_new(state, event_id, idempotency_key, draft)
    }
  }
}

fn append_new(
  state: State,
  event_id: String,
  idempotency_key: String,
  draft: Draft,
) -> Result(#(State, Outcome, json.Json), ReviewError) {
  use _ <- result.try(validate_draft(state, draft))
  use _ <- result.try(validate_texts([event_id, idempotency_key]))
  let next_revision = state.revision + 1
  let semantic = semantic_json(next_revision, event_id, idempotency_key, draft)
  let assert Ok(digest) = semantic |> json.to_string |> hash.text
  let event =
    Event(
      next_revision,
      event_id,
      idempotency_key,
      draft.review_id,
      draft.snapshot_id,
      draft.review_as_of,
      draft.reviewer_kind,
      draft.reviewer_id,
      draft.prior_review_id,
      draft.supersedes,
      draft.changed_sections,
      draft.receipt_links,
      draft.conclusion_ref,
      draft.privacy,
      identity.sha256_value(digest),
    )
  case state.revision >= 10_000 {
    True -> Error(TooManyEvents)
    False ->
      case dict.has_key(state.events_by_id, event_id) {
        True -> Error(DuplicateEventId(event_id))
        False ->
          Ok(#(retain_event(state, event), Stored(event_id), event_json(event)))
      }
  }
}

pub fn inspect(
  state: State,
  review_id: String,
  include_private: Bool,
  maximum_history: Int,
) -> Result(json.Json, ReviewError) {
  use current <- result.try(find_review(state, review_id))
  let history =
    state
    |> events
    |> list.filter(fn(event) {
      { event.review_id == review_id || event.supersedes == Some(review_id) }
      && { include_private || event.privacy != "private" }
    })
  let selected = list.take(history, int.max(0, maximum_history))
  let payload =
    json.object([
      #("schemaVersion", json.int(1)),
      #("journalRevision", json.int(state.revision)),
      #("selected", event_json(current)),
      #("historyCount", json.int(list.length(history))),
      #("history", json.array(selected, event_json)),
      #("persistence", json.string("user_owned_append_only_jsonl_atomic_cas")),
      #(
        "correctionMeaning",
        json.string("immutable_new_review_supersedes_prior"),
      ),
      #(
        "availableOperations",
        json.array(
          [
            "inspect_receipt_links",
            "compare_review_receipts",
            "record_correction",
          ],
          json.string,
        ),
      ),
    ])
  let assert Ok(digest) = payload |> json.to_string |> hash.text
  Ok(
    json.object([
      #("portfolioReview", payload),
      #("canonicalContentHash", digest |> identity.sha256_value |> json.string),
    ]),
  )
}

pub fn encode_state(state: State) -> String {
  case events(state) {
    [] -> ""
    events ->
      events
      |> list.map(fn(value) { value |> event_json |> json.to_string })
      |> string.join(with: "\n")
      |> fn(value) { value <> "\n" }
  }
}

pub fn decode_jsonl(input: String) -> Result(State, ReviewError) {
  let lines = case input {
    "" -> []
    _ -> {
      let values = string.split(input, on: "\n")
      case list.last(values) {
        Ok("") -> list.take(values, list.length(values) - 1)
        _ -> values
      }
    }
  }
  decode_lines(lines, empty(), 1)
}

pub fn error_message(error: ReviewError) -> String {
  case error {
    InvalidJson -> "Portfolio review packet is not valid versioned JSON"
    ContentHashMismatch ->
      "Portfolio review packet does not match expectedSha256"
    InvalidDraft ->
      "Portfolio review identity, reviewer, correction, privacy, changed sections, or receipt inventory is invalid"
    InvalidReceipt(section) ->
      "Portfolio review receipt is invalid for section: " <> section
    DuplicateSection(section) ->
      "Portfolio review section appears more than once: " <> section
    RevisionConflict(current) ->
      "Portfolio review revision conflict; currentRevision="
      <> int.to_string(current)
    IdempotencyConflict(key) -> "Portfolio review idempotency conflict: " <> key
    DuplicateEventId(id) -> "Portfolio review eventId is already used: " <> id
    DuplicateReviewId(id) -> "Portfolio review reviewId is already used: " <> id
    PriorReviewMissing(id) -> "Portfolio priorReviewId was not found: " <> id
    SupersededReviewMissing(id) ->
      "Portfolio supersedes review was not found: " <> id
    ReviewNotFound(id) -> "Portfolio review was not found: " <> id
    InvalidJournal(line) ->
      "Portfolio review journal replay failed at line " <> int.to_string(line)
    TooManyEvents -> "Portfolio review journal reached its event budget"
  }
}

fn validate_draft(state: State, draft: Draft) -> Result(Nil, ReviewError) {
  use _ <- result.try(
    case
      draft.schema_version == 1
      && draft.contract_id == "portfolio_review_v1"
      && list.length(draft.changed_sections) <= 20
      && list.length(draft.receipt_links) >= 1
      && list.length(draft.receipt_links) <= 20
      && list.contains(["user", "llm"], draft.reviewer_kind)
      && list.contains(
        ["private", "review_visible", "exportable"],
        draft.privacy,
      )
    {
      True -> Ok(Nil)
      False -> Error(InvalidDraft)
    },
  )
  use _ <- result.try(
    validate_texts([
      draft.review_id,
      draft.snapshot_id,
      draft.review_as_of,
      draft.reviewer_id,
    ]),
  )
  use _ <- result.try(unique_sections(draft.receipt_links, []))
  use _ <- result.try(
    list.try_each(draft.receipt_links, fn(link) {
      case valid_hash(link.receipt) {
        True -> Ok(Nil)
        False -> Error(InvalidReceipt(link.section))
      }
    }),
  )
  use _ <- result.try(
    case dict.has_key(state.events_by_review_id, draft.review_id) {
      True -> Error(DuplicateReviewId(draft.review_id))
      False -> Ok(Nil)
    },
  )
  use _ <- result.try(case draft.prior_review_id {
    None -> Ok(Nil)
    Some(id) ->
      case dict.has_key(state.events_by_review_id, id) {
        True -> Ok(Nil)
        False -> Error(PriorReviewMissing(id))
      }
  })
  case draft.supersedes {
    None -> Ok(Nil)
    Some(id) ->
      case dict.has_key(state.events_by_review_id, id) {
        True -> Ok(Nil)
        False -> Error(SupersededReviewMissing(id))
      }
  }
}

fn find_review(state: State, review_id: String) -> Result(Event, ReviewError) {
  state.events_by_review_id
  |> dict.get(review_id)
  |> result.map_error(fn(_) { ReviewNotFound(review_id) })
}

fn unique_sections(
  links: List(ReceiptLink),
  seen: List(String),
) -> Result(Nil, ReviewError) {
  case links {
    [] -> Ok(Nil)
    [link, ..rest] ->
      case list.contains(seen, link.section) {
        True -> Error(DuplicateSection(link.section))
        False -> unique_sections(rest, [link.section, ..seen])
      }
  }
}

fn event_json(value: Event) -> json.Json {
  json.object([
    #("schemaVersion", json.int(1)),
    #("revision", json.int(value.revision)),
    #("eventId", json.string(value.event_id)),
    #("idempotencyKey", json.string(value.idempotency_key)),
    #("reviewId", json.string(value.review_id)),
    #("snapshotId", json.string(value.snapshot_id)),
    #("reviewAsOf", json.string(value.review_as_of)),
    #("reviewerKind", json.string(value.reviewer_kind)),
    #("reviewerId", json.string(value.reviewer_id)),
    #("priorReviewId", json.nullable(value.prior_review_id, json.string)),
    #("supersedes", json.nullable(value.supersedes, json.string)),
    #("changedSections", json.array(value.changed_sections, json.string)),
    #("receiptLinks", json.array(value.receipt_links, receipt_json)),
    #("conclusionRef", json.nullable(value.conclusion_ref, json.string)),
    #("privacy", json.string(value.privacy)),
    #("canonicalContentHash", json.string(value.canonical_hash)),
  ])
}

fn semantic_json(
  revision: Int,
  event_id: String,
  idempotency: String,
  draft: Draft,
) -> json.Json {
  json.object([
    #("schemaVersion", json.int(1)),
    #("revision", json.int(revision)),
    #("eventId", json.string(event_id)),
    #("idempotencyKey", json.string(idempotency)),
    #("reviewId", json.string(draft.review_id)),
    #("snapshotId", json.string(draft.snapshot_id)),
    #("reviewAsOf", json.string(draft.review_as_of)),
    #("reviewerKind", json.string(draft.reviewer_kind)),
    #("reviewerId", json.string(draft.reviewer_id)),
    #("priorReviewId", json.nullable(draft.prior_review_id, json.string)),
    #("supersedes", json.nullable(draft.supersedes, json.string)),
    #("changedSections", json.array(draft.changed_sections, json.string)),
    #("receiptLinks", json.array(draft.receipt_links, receipt_json)),
    #("conclusionRef", json.nullable(draft.conclusion_ref, json.string)),
    #("privacy", json.string(draft.privacy)),
  ])
}

fn receipt_json(value: ReceiptLink) -> json.Json {
  json.object([
    #("section", json.string(value.section)),
    #("receipt", json.string(value.receipt)),
  ])
}

fn same_draft(event: Event, draft: Draft) -> Bool {
  event.review_id == draft.review_id
  && event.snapshot_id == draft.snapshot_id
  && event.review_as_of == draft.review_as_of
  && event.reviewer_kind == draft.reviewer_kind
  && event.reviewer_id == draft.reviewer_id
  && event.prior_review_id == draft.prior_review_id
  && event.supersedes == draft.supersedes
  && event.changed_sections == draft.changed_sections
  && event.receipt_links == draft.receipt_links
  && event.conclusion_ref == draft.conclusion_ref
  && event.privacy == draft.privacy
}

fn verify_event(event: Event) -> Bool {
  let draft =
    Draft(
      1,
      "portfolio_review_v1",
      event.review_id,
      event.snapshot_id,
      event.review_as_of,
      event.reviewer_kind,
      event.reviewer_id,
      event.prior_review_id,
      event.supersedes,
      event.changed_sections,
      event.receipt_links,
      event.conclusion_ref,
      event.privacy,
    )
  case
    semantic_json(event.revision, event.event_id, event.idempotency_key, draft)
    |> json.to_string
    |> hash.text
  {
    Ok(digest) -> identity.sha256_value(digest) == event.canonical_hash
    Error(_) -> False
  }
}

fn decode_lines(
  lines: List(String),
  state: State,
  line: Int,
) -> Result(State, ReviewError) {
  case lines {
    [] -> Ok(state)
    [encoded, ..rest] ->
      case json.parse(encoded, event_decoder()) {
        Error(_) -> Error(InvalidJournal(line))
        Ok(event) ->
          case event.revision == state.revision + 1 && verify_event(event) {
            False -> Error(InvalidJournal(line))
            True ->
              case validate_decoded_event(state, event) {
                Error(_) -> Error(InvalidJournal(line))
                Ok(next) -> decode_lines(rest, next, line + 1)
              }
          }
      }
  }
}

fn validate_decoded_event(
  state: State,
  event: Event,
) -> Result(State, ReviewError) {
  let draft =
    Draft(
      1,
      "portfolio_review_v1",
      event.review_id,
      event.snapshot_id,
      event.review_as_of,
      event.reviewer_kind,
      event.reviewer_id,
      event.prior_review_id,
      event.supersedes,
      event.changed_sections,
      event.receipt_links,
      event.conclusion_ref,
      event.privacy,
    )
  use _ <- result.try(case state.revision >= 10_000 {
    True -> Error(TooManyEvents)
    False -> Ok(Nil)
  })
  use _ <- result.try(validate_draft(state, draft))
  use _ <- result.try(validate_texts([event.event_id, event.idempotency_key]))
  use _ <- result.try(case dict.has_key(state.events_by_id, event.event_id) {
    True -> Error(DuplicateEventId(event.event_id))
    False -> Ok(Nil)
  })
  use _ <- result.try(
    case dict.has_key(state.events_by_idempotency, event.idempotency_key) {
      True -> Error(IdempotencyConflict(event.idempotency_key))
      False -> Ok(Nil)
    },
  )
  Ok(retain_event(state, event))
}

fn retain_event(state: State, event: Event) -> State {
  State(
    event.revision,
    [event, ..state.events_reversed],
    dict.insert(state.events_by_id, event.event_id, event),
    dict.insert(state.events_by_idempotency, event.idempotency_key, event),
    dict.insert(state.events_by_review_id, event.review_id, event),
  )
}

fn events(state: State) -> List(Event) {
  list.reverse(state.events_reversed)
}

fn event_decoder() -> decode.Decoder(Event) {
  use schema <- decode.field("schemaVersion", decode.int)
  use revision <- decode.field("revision", decode.int)
  use event_id <- decode.field("eventId", decode.string)
  use idempotency <- decode.field("idempotencyKey", decode.string)
  use review_id <- decode.field("reviewId", decode.string)
  use snapshot_id <- decode.field("snapshotId", decode.string)
  use review_as_of <- decode.field("reviewAsOf", decode.string)
  use reviewer_kind <- decode.field("reviewerKind", decode.string)
  use reviewer_id <- decode.field("reviewerId", decode.string)
  use prior <- decode.optional_field(
    "priorReviewId",
    None,
    decode.optional(decode.string),
  )
  use supersedes <- decode.optional_field(
    "supersedes",
    None,
    decode.optional(decode.string),
  )
  use changed <- decode.field("changedSections", decode.list(of: decode.string))
  use links <- decode.field("receiptLinks", decode.list(of: receipt_decoder()))
  use conclusion <- decode.optional_field(
    "conclusionRef",
    None,
    decode.optional(decode.string),
  )
  use privacy <- decode.field("privacy", decode.string)
  use canonical <- decode.field("canonicalContentHash", decode.string)
  case schema == 1 {
    True ->
      decode.success(Event(
        revision,
        event_id,
        idempotency,
        review_id,
        snapshot_id,
        review_as_of,
        reviewer_kind,
        reviewer_id,
        prior,
        supersedes,
        changed,
        links,
        conclusion,
        privacy,
        canonical,
      ))
    False -> decode.failure(placeholder(), "schema")
  }
}

fn draft_decoder() -> decode.Decoder(Draft) {
  use schema <- decode.field("schemaVersion", decode.int)
  use contract <- decode.field("contractId", decode.string)
  use review_id <- decode.field("reviewId", decode.string)
  use snapshot_id <- decode.field("snapshotId", decode.string)
  use review_as_of <- decode.field("reviewAsOf", decode.string)
  use reviewer_kind <- decode.field("reviewerKind", decode.string)
  use reviewer_id <- decode.field("reviewerId", decode.string)
  use prior <- decode.optional_field(
    "priorReviewId",
    None,
    decode.optional(decode.string),
  )
  use supersedes <- decode.optional_field(
    "supersedes",
    None,
    decode.optional(decode.string),
  )
  use changed <- decode.field("changedSections", decode.list(of: decode.string))
  use links <- decode.field("receiptLinks", decode.list(of: receipt_decoder()))
  use conclusion <- decode.optional_field(
    "conclusionRef",
    None,
    decode.optional(decode.string),
  )
  use privacy <- decode.field("privacy", decode.string)
  decode.success(Draft(
    schema,
    contract,
    review_id,
    snapshot_id,
    review_as_of,
    reviewer_kind,
    reviewer_id,
    prior,
    supersedes,
    changed,
    links,
    conclusion,
    privacy,
  ))
}

fn receipt_decoder() -> decode.Decoder(ReceiptLink) {
  use section <- decode.field("section", decode.string)
  use receipt <- decode.field("receipt", decode.string)
  decode.success(ReceiptLink(section, receipt))
}

fn placeholder() -> Event {
  Event(0, "", "", "", "", "", "", "", None, None, [], [], None, "", "")
}

fn validate_texts(values: List(String)) -> Result(Nil, ReviewError) {
  case
    list.all(values, fn(value) {
      value != "" && string.trim(value) == value && string.length(value) <= 4096
    })
  {
    True -> Ok(Nil)
    False -> Error(InvalidDraft)
  }
}

fn valid_hash(value: String) -> Bool {
  string.length(value) == 64
  && list.all(string.to_graphemes(value), fn(character) {
    string.contains("0123456789abcdef", character)
  })
}

fn verify_hash(bytes: String, expected: String) -> Result(Nil, ReviewError) {
  case hash.text(bytes) {
    Ok(actual) ->
      case identity.sha256_value(actual) == expected {
        True -> Ok(Nil)
        False -> Error(ContentHashMismatch)
      }
    Error(_) -> Error(ContentHashMismatch)
  }
}
