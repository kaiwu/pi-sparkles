import finance_provenance/hash
import finance_provenance/identity
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub const maximum_events = 10_000

pub const maximum_characters = 10_000_000

pub type Subject {
  Subject(
    track: String,
    issuer_id: String,
    listing_id: String,
    mic: String,
    symbol: String,
  )
}

pub type EvidenceLink {
  EvidenceLink(
    link_id: String,
    relation: String,
    receipt_sha256: String,
    source_state: String,
    corrected_by: Option(String),
  )
}

pub type Claim {
  Claim(
    claim_id: String,
    text: String,
    state: String,
    evidence: List(EvidenceLink),
  )
}

pub type Draft {
  Draft(
    journal_id: String,
    thesis_id: String,
    event_id: String,
    kind: String,
    version: Int,
    parent_event_id: Option(String),
    author_kind: String,
    author_id: String,
    recorded_at: String,
    subject: Subject,
    horizon: String,
    claims: List(Claim),
    privacy: String,
    reason: Option(String),
    idempotency_key: String,
  )
}

pub opaque type Event {
  Event(draft: Draft, event_sha256: String)
}

pub opaque type State {
  State(revision: Int, events: List(Event))
}

pub type AppendOutcome {
  Stored(event: Event)
  AlreadyStored(event: Event)
}

pub type ThesisError {
  InvalidText(field: String)
  InvalidKind
  InvalidVersion
  InvalidParent
  InvalidAuthor
  InvalidSubject
  InvalidPrivacy
  TooManyClaims
  DuplicateClaimId
  InvalidClaim
  TooManyEvidence
  DuplicateEvidenceLink
  InvalidEvidence
  InvalidReason
  HashFailure
  InvalidJson
  HashMismatch
  EmptyLine(line: Int)
  DecodeFailure(line: Int)
  TooManyEvents
  TooManyCharacters
  JournalMismatch
  DuplicateEventId
  IdempotencyConflict
  ThesisAlreadyExists
  ThesisNotFound
  ParentMismatch
  VersionGap
  IdentityChanged
  ThesisWithdrawn
  InvalidWithdrawal
  DuplicatePersistedEvent
  EventNotFound
  InvalidInspection
}

pub fn new(draft: Draft) -> Result(Event, ThesisError) {
  use _ <- result.try(validate_draft(draft))
  let canonical = draft_json(draft) |> json.to_string
  case hash.text(canonical) {
    Error(_) -> Error(HashFailure)
    Ok(value) -> Ok(Event(draft, identity.sha256_value(value)))
  }
}

pub fn empty() -> State {
  State(0, [])
}

pub fn revision(value: State) -> Int {
  value.revision
}

pub fn event_hash(value: Event) -> String {
  value.event_sha256
}

pub fn event_id(value: Event) -> String {
  value.draft.event_id
}

pub fn append(
  state: State,
  event: Event,
) -> Result(#(State, AppendOutcome), ThesisError) {
  use _ <- result.try(validate_journal(state.events, event))
  case find_by_idempotency(state.events, event.draft.idempotency_key) {
    Some(existing) ->
      case existing.event_sha256 == event.event_sha256 {
        True -> Ok(#(state, AlreadyStored(existing)))
        False -> Error(IdempotencyConflict)
      }
    None ->
      case find_by_event_id(state.events, event.draft.event_id) {
        Some(_) -> Error(DuplicateEventId)
        None -> {
          use _ <- result.try(validate_transition(state.events, event))
          Ok(#(
            State(state.revision + 1, list.append(state.events, [event])),
            Stored(event),
          ))
        }
      }
  }
}

pub fn decode_jsonl(text: String) -> Result(State, ThesisError) {
  case string.length(text) > maximum_characters {
    True -> Error(TooManyCharacters)
    False -> {
      let lines = jsonl_lines(text)
      case list.length(lines) > maximum_events {
        True -> Error(TooManyEvents)
        False -> decode_lines(lines, 1, empty())
      }
    }
  }
}

pub fn encode_state(value: State) -> String {
  case value.events {
    [] -> ""
    events ->
      events
      |> list.map(encode)
      |> string.join("\n")
      |> fn(text) { text <> "\n" }
  }
}

pub fn inspect(
  value: State,
  thesis_id: String,
  requested_version: Option(Int),
  include_history: Bool,
  include_private: Bool,
  maximum_history: Int,
) -> Result(json.Json, ThesisError) {
  use _ <- result.try(case maximum_history >= 0 && maximum_history <= 100 {
    True -> Ok(Nil)
    False -> Error(InvalidInspection)
  })
  let thesis_events = events_for(value.events, thesis_id)
  use selected <- result.try(case requested_version {
    None ->
      case list.last(thesis_events) {
        Ok(event) -> Ok(event)
        Error(_) -> Error(ThesisNotFound)
      }
    Some(version) ->
      case find_by_version(thesis_events, version) {
        Some(event) -> Ok(event)
        None -> Error(EventNotFound)
      }
  })
  let history = case include_history {
    True -> thesis_events |> list.take(maximum_history)
    False -> []
  }
  Ok(
    json.object([
      #("schemaVersion", json.int(1)),
      #("journalRevision", json.int(value.revision)),
      #("selected", event_json_for_visibility(selected, include_private)),
      #("historyCount", json.int(list.length(thesis_events))),
      #(
        "returnedHistory",
        json.array(history, fn(event) { event_header_json(event) }),
      ),
      #(
        "historyOmitted",
        json.int(int.max(list.length(thesis_events) - list.length(history), 0)),
      ),
      #("decisionOwner", json.string("caller_and_llm")),
      #(
        "pluginDecisionFields",
        json.array(["immutable_transition_validation"], json.string),
      ),
    ]),
  )
}

pub fn compare_versions(
  value: State,
  thesis_id: String,
  left_version: Int,
  right_version: Int,
  include_private: Bool,
) -> Result(json.Json, ThesisError) {
  let thesis_events = events_for(value.events, thesis_id)
  use left <- result.try(case find_by_version(thesis_events, left_version) {
    Some(event) -> Ok(event)
    None -> Error(EventNotFound)
  })
  use right <- result.try(case find_by_version(thesis_events, right_version) {
    Some(event) -> Ok(event)
    None -> Error(EventNotFound)
  })
  let left_claims = left.draft.claims
  let right_claims = right.draft.claims
  let added =
    right_claims
    |> list.filter(fn(claim) { find_claim(left_claims, claim.claim_id) == None })
  let removed =
    left_claims
    |> list.filter(fn(claim) {
      find_claim(right_claims, claim.claim_id) == None
    })
  let changed =
    right_claims
    |> list.filter(fn(claim) {
      case find_claim(left_claims, claim.claim_id) {
        None -> False
        Some(original) -> original != claim
      }
    })
  let private_hidden = !include_private && any_private(left, right)
  Ok(
    json.object([
      #("schemaVersion", json.int(1)),
      #("thesisId", json.string(thesis_id)),
      #("left", event_header_json(left)),
      #("right", event_header_json(right)),
      #("contentRedacted", json.bool(private_hidden)),
      #("addedClaims", case private_hidden {
        True -> json.array([], claim_json)
        False -> json.array(added, claim_json)
      }),
      #("removedClaims", case private_hidden {
        True -> json.array([], claim_json)
        False -> json.array(removed, claim_json)
      }),
      #("changedClaims", case private_hidden {
        True -> json.array([], claim_json)
        False -> json.array(changed, claim_json)
      }),
      #(
        "comparisonMeaning",
        json.string("exact_version_snapshot_difference_only"),
      ),
      #("decisionOwner", json.string("caller_and_llm")),
      #(
        "pluginDecisionFields",
        json.array(["exact_snapshot_diff"], json.string),
      ),
    ]),
  )
}

pub fn export_jsonl(
  value: State,
  include_private: Bool,
  include_review_visible: Bool,
  include_exportable: Bool,
  maximum: Int,
) -> Result(json.Json, ThesisError) {
  use _ <- result.try(case maximum >= 0 && maximum <= maximum_events {
    True -> Ok(Nil)
    False -> Error(InvalidInspection)
  })
  let visible =
    value.events
    |> list.filter(fn(event) {
      case event.draft.privacy {
        "private" -> include_private
        "review_visible" -> include_review_visible
        "exportable" -> include_exportable
        _ -> False
      }
    })
  let selected = list.take(visible, maximum)
  let text = case selected {
    [] -> ""
    _ ->
      selected
      |> list.map(encode)
      |> string.join("\n")
      |> fn(text) { text <> "\n" }
  }
  let assert Ok(digest) = hash.text(text)
  Ok(
    json.object([
      #("schemaVersion", json.int(1)),
      #("journalRevision", json.int(value.revision)),
      #("eventCount", json.int(list.length(selected))),
      #(
        "omittedCount",
        json.int(list.length(value.events) - list.length(selected)),
      ),
      #("contentSha256", json.string(identity.sha256_value(digest))),
      #("jsonl", json.string(text)),
    ]),
  )
}

pub fn summary(value: State) -> String {
  "stock_thesis journal revision="
  <> int.to_string(value.revision)
  <> ", immutable events="
  <> int.to_string(list.length(value.events))
  <> "; thesis interpretation remains with the caller/LLM"
}

pub fn error_message(error: ThesisError) -> String {
  case error {
    InvalidText(field) -> "Invalid thesis text field: " <> field
    InvalidKind -> "Thesis event kind must be created, amended, or withdrawn"
    InvalidVersion -> "Thesis version must be positive"
    InvalidParent -> "Thesis parentEventId shape is invalid"
    InvalidAuthor -> "Thesis author attribution is invalid"
    InvalidSubject -> "Thesis exact listing subject is invalid"
    InvalidPrivacy ->
      "Thesis privacy must be private, review_visible, or exportable"
    TooManyClaims -> "Thesis exceeds the 100-claim budget"
    DuplicateClaimId -> "Thesis contains duplicate claimId values"
    InvalidClaim -> "Thesis contains an invalid claim"
    TooManyEvidence -> "Thesis claim exceeds the 100-evidence-link budget"
    DuplicateEvidenceLink -> "Thesis claim contains duplicate linkId values"
    InvalidEvidence ->
      "Thesis evidence relation, receipt hash, or correction state is invalid"
    InvalidReason -> "Amendment/withdrawal reason is invalid"
    HashFailure -> "Thesis event hashing failed"
    InvalidJson -> "Thesis journal line is not valid JSON"
    HashMismatch -> "Thesis event content hash mismatch"
    EmptyLine(line) ->
      "Thesis journal has an empty line at " <> int.to_string(line)
    DecodeFailure(line) ->
      "Thesis journal decode failed at line " <> int.to_string(line)
    TooManyEvents -> "Thesis journal exceeds the 10000-event budget"
    TooManyCharacters -> "Thesis journal exceeds the 10MB character budget"
    JournalMismatch -> "Thesis event journalId does not match existing storage"
    DuplicateEventId -> "Thesis eventId already exists"
    IdempotencyConflict ->
      "Thesis idempotencyKey conflicts with different content"
    ThesisAlreadyExists -> "Thesis create targets an existing thesisId"
    ThesisNotFound -> "ThesisId was not found"
    ParentMismatch -> "Thesis parentEventId does not match the current version"
    VersionGap -> "Thesis version must increment the current version by one"
    IdentityChanged -> "Thesis subject identity cannot change across versions"
    ThesisWithdrawn -> "A withdrawn thesis cannot be amended"
    InvalidWithdrawal ->
      "Withdrawal must preserve the prior snapshot and supply a reason"
    DuplicatePersistedEvent ->
      "Thesis journal contains a duplicate persisted event"
    EventNotFound -> "Requested thesis version was not found"
    InvalidInspection -> "Thesis inspection/export bounds are invalid"
  }
}

fn validate_draft(value: Draft) -> Result(Nil, ThesisError) {
  use _ <- result.try(validate_text(value.journal_id, "journalId"))
  use _ <- result.try(validate_text(value.thesis_id, "thesisId"))
  use _ <- result.try(validate_text(value.event_id, "eventId"))
  use _ <- result.try(validate_text(value.idempotency_key, "idempotencyKey"))
  use _ <- result.try(
    case list.contains(["created", "amended", "withdrawn"], value.kind) {
      True -> Ok(Nil)
      False -> Error(InvalidKind)
    },
  )
  use _ <- result.try(case value.version >= 1 {
    True -> Ok(Nil)
    False -> Error(InvalidVersion)
  })
  use _ <- result.try(case value.kind, value.parent_event_id {
    "created", None -> Ok(Nil)
    "created", Some(_) -> Error(InvalidParent)
    _, Some(parent) -> validate_text(parent, "parentEventId")
    _, None -> Error(InvalidParent)
  })
  use _ <- result.try(
    case
      list.contains(["user", "llm", "imported"], value.author_kind)
      && valid_text(value.author_id)
      && valid_text(value.recorded_at)
    {
      True -> Ok(Nil)
      False -> Error(InvalidAuthor)
    },
  )
  use _ <- result.try(case valid_subject(value.subject) {
    True -> Ok(Nil)
    False -> Error(InvalidSubject)
  })
  use _ <- result.try(validate_text(value.horizon, "horizon"))
  use _ <- result.try(
    case
      list.contains(["private", "review_visible", "exportable"], value.privacy)
    {
      True -> Ok(Nil)
      False -> Error(InvalidPrivacy)
    },
  )
  use _ <- result.try(case list.length(value.claims) <= 100 {
    True -> Ok(Nil)
    False -> Error(TooManyClaims)
  })
  use _ <- result.try(case unique_claims(value.claims) {
    True -> Ok(Nil)
    False -> Error(DuplicateClaimId)
  })
  use _ <- result.try(validate_claims(value.claims))
  case value.kind, value.reason {
    "created", None -> Ok(Nil)
    "created", Some(_) -> Error(InvalidReason)
    _, Some(reason) -> validate_text(reason, "reason")
    _, None -> Error(InvalidReason)
  }
}

fn validate_claims(values: List(Claim)) -> Result(Nil, ThesisError) {
  case values {
    [] -> Ok(Nil)
    [value, ..rest] -> {
      use _ <- result.try(validate_claim(value))
      validate_claims(rest)
    }
  }
}

fn validate_claim(value: Claim) -> Result(Nil, ThesisError) {
  use _ <- result.try(
    case
      valid_text(value.claim_id)
      && valid_text(value.text)
      && list.contains(["active", "withdrawn"], value.state)
    {
      True -> Ok(Nil)
      False -> Error(InvalidClaim)
    },
  )
  use _ <- result.try(case list.length(value.evidence) <= 100 {
    True -> Ok(Nil)
    False -> Error(TooManyEvidence)
  })
  use _ <- result.try(case unique_evidence(value.evidence) {
    True -> Ok(Nil)
    False -> Error(DuplicateEvidenceLink)
  })
  case list.all(value.evidence, valid_evidence) {
    True -> Ok(Nil)
    False -> Error(InvalidEvidence)
  }
}

fn valid_evidence(value: EvidenceLink) -> Bool {
  valid_text(value.link_id)
  && list.contains(
    ["supporting", "contradicting", "contextual", "unresolved"],
    value.relation,
  )
  && valid_sha(value.receipt_sha256)
  && list.contains(
    ["current", "stale", "retracted", "corrected"],
    value.source_state,
  )
  && case value.source_state, value.corrected_by {
    "corrected", Some(hash) -> valid_sha(hash)
    "corrected", None -> False
    _, None -> True
    _, Some(_) -> False
  }
}

fn valid_subject(value: Subject) -> Bool {
  valid_text(value.issuer_id)
  && valid_text(value.listing_id)
  && valid_text(value.symbol)
  && case value.track {
    "cn" -> list.contains(["XSHG", "XSHE", "XBSE"], value.mic)
    "hk" -> value.mic == "XHKG"
    "us" -> list.contains(["XNYS", "XNAS"], value.mic)
    _ -> False
  }
}

fn validate_text(value: String, field: String) -> Result(Nil, ThesisError) {
  case valid_text(value) {
    True -> Ok(Nil)
    False -> Error(InvalidText(field))
  }
}

fn valid_text(value: String) -> Bool {
  value != ""
  && value == string.trim(value)
  && string.length(value) <= 65_536
  && !string.contains(value, "\n")
  && !string.contains(value, "\r")
}

fn valid_sha(value: String) -> Bool {
  string.length(value) == 64
}

fn unique_claims(values: List(Claim)) -> Bool {
  unique_strings(list.map(values, fn(value) { value.claim_id }))
}

fn unique_evidence(values: List(EvidenceLink)) -> Bool {
  unique_strings(list.map(values, fn(value) { value.link_id }))
}

fn unique_strings(values: List(String)) -> Bool {
  case values {
    [] -> True
    [value, ..rest] -> !list.contains(rest, value) && unique_strings(rest)
  }
}

fn validate_journal(
  events: List(Event),
  new_event: Event,
) -> Result(Nil, ThesisError) {
  case events {
    [] -> Ok(Nil)
    [first, ..] ->
      case first.draft.journal_id == new_event.draft.journal_id {
        True -> Ok(Nil)
        False -> Error(JournalMismatch)
      }
  }
}

fn validate_transition(
  events: List(Event),
  new_event: Event,
) -> Result(Nil, ThesisError) {
  let prior = latest_for(events, new_event.draft.thesis_id)
  case new_event.draft.kind, prior {
    "created", None ->
      case new_event.draft.version == 1 {
        True -> Ok(Nil)
        False -> Error(VersionGap)
      }
    "created", Some(_) -> Error(ThesisAlreadyExists)
    _, None -> Error(ThesisNotFound)
    kind, Some(previous) -> {
      use _ <- result.try(case previous.draft.kind == "withdrawn" {
        True -> Error(ThesisWithdrawn)
        False -> Ok(Nil)
      })
      use _ <- result.try(
        case new_event.draft.parent_event_id == Some(previous.draft.event_id) {
          True -> Ok(Nil)
          False -> Error(ParentMismatch)
        },
      )
      use _ <- result.try(
        case new_event.draft.version == previous.draft.version + 1 {
          True -> Ok(Nil)
          False -> Error(VersionGap)
        },
      )
      use _ <- result.try(
        case new_event.draft.subject == previous.draft.subject {
          True -> Ok(Nil)
          False -> Error(IdentityChanged)
        },
      )
      case kind {
        "withdrawn" ->
          case
            new_event.draft.claims == previous.draft.claims
            && new_event.draft.horizon == previous.draft.horizon
          {
            True -> Ok(Nil)
            False -> Error(InvalidWithdrawal)
          }
        _ -> Ok(Nil)
      }
    }
  }
}

fn encode(value: Event) -> String {
  json.object([
    #("event", draft_json(value.draft)),
    #("eventSha256", json.string(value.event_sha256)),
  ])
  |> json.to_string
}

fn decode_event(text: String) -> Result(Event, ThesisError) {
  case json.parse(text, event_decoder()) {
    Error(_) -> Error(InvalidJson)
    Ok(#(draft, expected)) -> {
      use event <- result.try(new(draft))
      case event.event_sha256 == expected {
        True -> Ok(event)
        False -> Error(HashMismatch)
      }
    }
  }
}

fn jsonl_lines(text: String) -> List(String) {
  case text {
    "" -> []
    _ -> {
      let lines = string.split(text, on: "\n")
      case list.last(lines) {
        Ok("") -> list.take(lines, list.length(lines) - 1)
        _ -> lines
      }
    }
  }
}

fn decode_lines(
  lines: List(String),
  line: Int,
  state: State,
) -> Result(State, ThesisError) {
  case lines {
    [] -> Ok(state)
    ["", ..] -> Error(EmptyLine(line))
    [text, ..rest] ->
      case decode_event(text) {
        Error(_) -> Error(DecodeFailure(line))
        Ok(event) ->
          case append(state, event) {
            Error(_) -> Error(DecodeFailure(line))
            Ok(#(_, AlreadyStored(_))) -> Error(DuplicatePersistedEvent)
            Ok(#(next, Stored(_))) -> decode_lines(rest, line + 1, next)
          }
      }
  }
}

fn events_for(events: List(Event), thesis_id: String) -> List(Event) {
  events |> list.filter(fn(event) { event.draft.thesis_id == thesis_id })
}

fn latest_for(events: List(Event), thesis_id: String) -> Option(Event) {
  case list.last(events_for(events, thesis_id)) {
    Ok(value) -> Some(value)
    Error(_) -> None
  }
}

fn find_by_event_id(events: List(Event), id: String) -> Option(Event) {
  case events {
    [] -> None
    [event, ..rest] ->
      case event.draft.event_id == id {
        True -> Some(event)
        False -> find_by_event_id(rest, id)
      }
  }
}

fn find_by_idempotency(events: List(Event), key: String) -> Option(Event) {
  case events {
    [] -> None
    [event, ..rest] ->
      case event.draft.idempotency_key == key {
        True -> Some(event)
        False -> find_by_idempotency(rest, key)
      }
  }
}

fn find_by_version(events: List(Event), version: Int) -> Option(Event) {
  case events {
    [] -> None
    [event, ..rest] ->
      case event.draft.version == version {
        True -> Some(event)
        False -> find_by_version(rest, version)
      }
  }
}

fn find_claim(claims: List(Claim), id: String) -> Option(Claim) {
  case claims {
    [] -> None
    [claim, ..rest] ->
      case claim.claim_id == id {
        True -> Some(claim)
        False -> find_claim(rest, id)
      }
  }
}

fn any_private(left: Event, right: Event) -> Bool {
  left.draft.privacy == "private" || right.draft.privacy == "private"
}

fn event_decoder() -> decode.Decoder(#(Draft, String)) {
  use draft <- decode.field("event", draft_decoder())
  use expected <- decode.field("eventSha256", decode.string)
  decode.success(#(draft, expected))
}

fn draft_decoder() -> decode.Decoder(Draft) {
  use journal <- decode.field("journalId", decode.string)
  use thesis <- decode.field("thesisId", decode.string)
  use event <- decode.field("eventId", decode.string)
  use kind <- decode.field("kind", decode.string)
  use version <- decode.field("version", decode.int)
  use parent <- optional_string("parentEventId")
  use author_kind <- decode.field("authorKind", decode.string)
  use author <- decode.field("authorId", decode.string)
  use recorded <- decode.field("recordedAt", decode.string)
  use subject <- decode.field("subject", subject_decoder())
  use horizon <- decode.field("horizon", decode.string)
  use claims <- decode.field("claims", decode.list(claim_decoder()))
  use privacy <- decode.field("privacy", decode.string)
  use reason <- optional_string("reason")
  use key <- decode.field("idempotencyKey", decode.string)
  decode.success(Draft(
    journal,
    thesis,
    event,
    kind,
    version,
    parent,
    author_kind,
    author,
    recorded,
    subject,
    horizon,
    claims,
    privacy,
    reason,
    key,
  ))
}

fn subject_decoder() -> decode.Decoder(Subject) {
  use track <- decode.field("track", decode.string)
  use issuer <- decode.field("issuerId", decode.string)
  use listing <- decode.field("listingId", decode.string)
  use mic <- decode.field("mic", decode.string)
  use symbol <- decode.field("symbol", decode.string)
  decode.success(Subject(track, issuer, listing, mic, symbol))
}

fn evidence_decoder() -> decode.Decoder(EvidenceLink) {
  use id <- decode.field("linkId", decode.string)
  use relation <- decode.field("relation", decode.string)
  use receipt <- decode.field("receiptSha256", decode.string)
  use state <- decode.field("sourceState", decode.string)
  use corrected <- optional_string("correctedBy")
  decode.success(EvidenceLink(id, relation, receipt, state, corrected))
}

fn claim_decoder() -> decode.Decoder(Claim) {
  use id <- decode.field("claimId", decode.string)
  use text <- decode.field("text", decode.string)
  use state <- decode.field("state", decode.string)
  use evidence <- decode.field("evidence", decode.list(evidence_decoder()))
  decode.success(Claim(id, text, state, evidence))
}

fn optional_string(
  name: String,
  next: fn(Option(String)) -> decode.Decoder(value),
) -> decode.Decoder(value) {
  decode.optional_field(name, None, decode.optional(decode.string), next)
}

fn draft_json(value: Draft) -> json.Json {
  json.object([
    #("schemaVersion", json.int(1)),
    #("journalId", json.string(value.journal_id)),
    #("thesisId", json.string(value.thesis_id)),
    #("eventId", json.string(value.event_id)),
    #("kind", json.string(value.kind)),
    #("version", json.int(value.version)),
    #("parentEventId", json.nullable(value.parent_event_id, json.string)),
    #("authorKind", json.string(value.author_kind)),
    #("authorId", json.string(value.author_id)),
    #("recordedAt", json.string(value.recorded_at)),
    #("subject", subject_json(value.subject)),
    #("horizon", json.string(value.horizon)),
    #("claims", json.array(value.claims, claim_json)),
    #("privacy", json.string(value.privacy)),
    #("reason", json.nullable(value.reason, json.string)),
    #("idempotencyKey", json.string(value.idempotency_key)),
  ])
}

fn subject_json(value: Subject) -> json.Json {
  json.object([
    #("track", json.string(value.track)),
    #("issuerId", json.string(value.issuer_id)),
    #("listingId", json.string(value.listing_id)),
    #("mic", json.string(value.mic)),
    #("symbol", json.string(value.symbol)),
  ])
}

fn evidence_json(value: EvidenceLink) -> json.Json {
  json.object([
    #("linkId", json.string(value.link_id)),
    #("relation", json.string(value.relation)),
    #("receiptSha256", json.string(value.receipt_sha256)),
    #("sourceState", json.string(value.source_state)),
    #("correctedBy", json.nullable(value.corrected_by, json.string)),
  ])
}

fn claim_json(value: Claim) -> json.Json {
  json.object([
    #("claimId", json.string(value.claim_id)),
    #("text", json.string(value.text)),
    #("state", json.string(value.state)),
    #("evidence", json.array(value.evidence, evidence_json)),
  ])
}

fn event_header_json(value: Event) -> json.Json {
  json.object([
    #("thesisId", json.string(value.draft.thesis_id)),
    #("eventId", json.string(value.draft.event_id)),
    #("kind", json.string(value.draft.kind)),
    #("version", json.int(value.draft.version)),
    #("parentEventId", json.nullable(value.draft.parent_event_id, json.string)),
    #("authorKind", json.string(value.draft.author_kind)),
    #("authorId", json.string(value.draft.author_id)),
    #("recordedAt", json.string(value.draft.recorded_at)),
    #("privacy", json.string(value.draft.privacy)),
    #("eventSha256", json.string(value.event_sha256)),
  ])
}

fn event_json_for_visibility(value: Event, include_private: Bool) -> json.Json {
  case value.draft.privacy == "private" && !include_private {
    True ->
      json.object([
        #("header", event_header_json(value)),
        #("contentRedacted", json.bool(True)),
      ])
    False ->
      json.object([
        #("header", event_header_json(value)),
        #("subject", subject_json(value.draft.subject)),
        #("horizon", json.string(value.draft.horizon)),
        #("claims", json.array(value.draft.claims, claim_json)),
        #("reason", json.nullable(value.draft.reason, json.string)),
        #("contentRedacted", json.bool(False)),
      ])
  }
}
