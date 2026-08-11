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

pub type Predicate {
  Predicate(predicate_id: String, label: String, rule: String)
}

pub type Fact {
  Fact(
    predicate_id: String,
    state: String,
    observed_value: Option(String),
    source_receipt: String,
  )
}

pub type Candidate {
  Candidate(
    candidate_id: String,
    subject: Subject,
    classifications: List(String),
    currency: String,
    fiscal_period: String,
    facts: List(Fact),
  )
}

pub type ProjectedCandidate {
  ProjectedCandidate(candidate: Candidate, relation: String)
}

pub opaque type PeerSet {
  PeerSet(
    track: String,
    target: Subject,
    evidence_date: String,
    predicates: List(Predicate),
    candidates: List(ProjectedCandidate),
    omissions: List(String),
    packet_sha256: String,
  )
}

pub type PeerError {
  InvalidJson
  ContentHashMismatch
  WrongSchema
  WrongContract
  WrongTrack
  WrongMic
  InvalidTarget
  InvalidEvidenceDate
  TooManyPredicates
  TooManyCandidates
  TooManyOmissions
  DuplicatePredicate
  DuplicateCandidate
  InvalidPredicate
  InvalidCandidate
  DuplicateCandidatePredicate
  MissingCandidatePredicate(candidate_id: String, predicate_id: String)
  InvalidFact
  InvalidPage
  CandidateNotFound
}

pub fn project(
  expected_sha256: String,
  bytes: String,
) -> Result(PeerSet, PeerError) {
  use _ <- result.try(verify_hash(bytes, expected_sha256))
  use packet <- result.try(case json.parse(bytes, packet_decoder()) {
    Ok(value) -> Ok(value)
    Error(_) -> Error(InvalidJson)
  })
  let #(
    schema_version,
    contract_id,
    track,
    target,
    evidence_date,
    predicates,
    candidates,
    omissions,
  ) = packet
  use _ <- result.try(case schema_version == 1 {
    True -> Ok(Nil)
    False -> Error(WrongSchema)
  })
  use _ <- result.try(case contract_id == "stock_peers_v1" {
    True -> Ok(Nil)
    False -> Error(WrongContract)
  })
  use _ <- result.try(case list.contains(["cn", "hk", "us"], track) {
    True -> Ok(Nil)
    False -> Error(WrongTrack)
  })
  use _ <- result.try(case valid_subject(target) {
    True -> Ok(Nil)
    False -> Error(InvalidTarget)
  })
  use _ <- result.try(case valid_track_mic(track, target.mic) {
    True -> Ok(Nil)
    False -> Error(WrongMic)
  })
  use _ <- result.try(case valid_date(evidence_date) {
    True -> Ok(Nil)
    False -> Error(InvalidEvidenceDate)
  })
  use _ <- result.try(
    case list.length(predicates) >= 1 && list.length(predicates) <= 20 {
      True -> Ok(Nil)
      False -> Error(TooManyPredicates)
    },
  )
  use _ <- result.try(case list.length(candidates) <= 200 {
    True -> Ok(Nil)
    False -> Error(TooManyCandidates)
  })
  use _ <- result.try(case list.length(omissions) <= 200 {
    True -> Ok(Nil)
    False -> Error(TooManyOmissions)
  })
  use _ <- result.try(case unique_predicates(predicates) {
    True -> Ok(Nil)
    False -> Error(DuplicatePredicate)
  })
  use _ <- result.try(case unique_candidates(candidates) {
    True -> Ok(Nil)
    False -> Error(DuplicateCandidate)
  })
  use _ <- result.try(case list.all(predicates, valid_predicate) {
    True -> Ok(Nil)
    False -> Error(InvalidPredicate)
  })
  use _ <- result.try(validate_candidates(track, predicates, candidates))
  Ok(PeerSet(
    track,
    target,
    evidence_date,
    predicates,
    list.map(candidates, project_candidate),
    omissions,
    expected_sha256,
  ))
}

pub fn inspect(
  value: PeerSet,
  offset: Int,
  limit: Int,
) -> Result(json.Json, PeerError) {
  use _ <- result.try(validate_page(offset, limit))
  let page = value.candidates |> list.drop(offset) |> list.take(limit)
  let total = list.length(value.candidates)
  let next = case offset + list.length(page) < total {
    True -> json.int(offset + list.length(page))
    False -> json.null()
  }
  Ok(
    json.object(
      list.append(header_fields(value), [
        #("candidateCount", json.int(total)),
        #(
          "acceptedCount",
          json.int(count_relation(value.candidates, "accepted")),
        ),
        #(
          "rejectedCount",
          json.int(count_relation(value.candidates, "rejected")),
        ),
        #(
          "unresolvedCount",
          json.int(count_relation(value.candidates, "unresolved")),
        ),
        #("offset", json.int(offset)),
        #("nextOffset", next),
        #("candidates", json.array(page, candidate_header_json)),
        #("decisionOwner", json.string("caller_and_llm")),
        #(
          "pluginDecisionFields",
          json.array(["mechanical_predicate_projection"], json.string),
        ),
      ]),
    ),
  )
}

pub fn drill(
  value: PeerSet,
  candidate_id: String,
) -> Result(json.Json, PeerError) {
  case find_candidate(value.candidates, candidate_id) {
    None -> Error(CandidateNotFound)
    Some(candidate) ->
      Ok(
        json.object(
          list.append(header_fields(value), [
            #("candidate", candidate_json(candidate)),
            #("decisionOwner", json.string("caller_and_llm")),
            #(
              "pluginDecisionFields",
              json.array(["mechanical_predicate_projection"], json.string),
            ),
          ]),
        ),
      )
  }
}

pub fn summary(value: PeerSet) -> String {
  "stock_peers_v1: "
  <> int.to_string(list.length(value.candidates))
  <> " caller-supplied candidate(s); accepted="
  <> int.to_string(count_relation(value.candidates, "accepted"))
  <> ", rejected="
  <> int.to_string(count_relation(value.candidates, "rejected"))
  <> ", unresolved="
  <> int.to_string(count_relation(value.candidates, "unresolved"))
  <> "; peer choice remains with the caller/LLM"
}

pub fn error_message(error: PeerError) -> String {
  case error {
    InvalidJson -> "Peer-set import is not valid JSON"
    ContentHashMismatch -> "Peer-set import bytes do not match expectedSha256"
    WrongSchema -> "Peer-set schemaVersion must be 1"
    WrongContract -> "Peer-set contractId must be stock_peers_v1"
    WrongTrack -> "Peer-set track must be cn, hk, or us"
    WrongMic ->
      "Peer-set target or candidate MIC does not match the exact track"
    InvalidTarget -> "Peer-set target identity is incomplete"
    InvalidEvidenceDate -> "Peer-set evidenceDate must be YYYY-MM-DD"
    TooManyPredicates -> "Peer-set requires 1..20 explicit predicates"
    TooManyCandidates -> "Peer-set exceeds the 200-candidate budget"
    TooManyOmissions -> "Peer-set exceeds the 200-omission budget"
    DuplicatePredicate -> "Peer-set contains duplicate predicateId values"
    DuplicateCandidate ->
      "Peer-set contains duplicate candidateId or listingId values"
    InvalidPredicate -> "Peer-set contains an invalid predicate"
    InvalidCandidate ->
      "Peer-set contains an invalid candidate identity or metadata"
    DuplicateCandidatePredicate -> "Peer candidate repeats a predicateId"
    MissingCandidatePredicate(candidate, predicate) ->
      "Peer candidate " <> candidate <> " is missing predicate " <> predicate
    InvalidFact ->
      "Peer candidate contains an invalid predicate fact or source receipt"
    InvalidPage -> "Peer page requires offset >= 0 and limit 1..100"
    CandidateNotFound -> "candidateId was not found in the exact peer set"
  }
}

fn validate_candidates(
  track: String,
  predicates: List(Predicate),
  candidates: List(Candidate),
) -> Result(Nil, PeerError) {
  case candidates {
    [] -> Ok(Nil)
    [candidate, ..rest] -> {
      use _ <- result.try(case valid_candidate(candidate) {
        True -> Ok(Nil)
        False -> Error(InvalidCandidate)
      })
      use _ <- result.try(case valid_track_mic(track, candidate.subject.mic) {
        True -> Ok(Nil)
        False -> Error(WrongMic)
      })
      use _ <- result.try(case unique_fact_predicates(candidate.facts) {
        True -> Ok(Nil)
        False -> Error(DuplicateCandidatePredicate)
      })
      use _ <- result.try(case list.all(candidate.facts, valid_fact) {
        True -> Ok(Nil)
        False -> Error(InvalidFact)
      })
      use _ <- result.try(require_all_predicates(candidate, predicates))
      validate_candidates(track, predicates, rest)
    }
  }
}

fn require_all_predicates(
  candidate: Candidate,
  predicates: List(Predicate),
) -> Result(Nil, PeerError) {
  case predicates {
    [] -> Ok(Nil)
    [predicate, ..rest] ->
      case
        list.any(candidate.facts, fn(fact) {
          fact.predicate_id == predicate.predicate_id
        })
      {
        True -> require_all_predicates(candidate, rest)
        False ->
          Error(MissingCandidatePredicate(
            candidate.candidate_id,
            predicate.predicate_id,
          ))
      }
  }
}

fn project_candidate(candidate: Candidate) -> ProjectedCandidate {
  let relation = case
    list.any(candidate.facts, fn(fact) { fact.state == "observed_false" })
  {
    True -> "rejected"
    False ->
      case
        list.any(candidate.facts, fn(fact) {
          list.contains(["unknown", "conflicting"], fact.state)
        })
      {
        True -> "unresolved"
        False -> "accepted"
      }
  }
  ProjectedCandidate(candidate, relation)
}

fn count_relation(values: List(ProjectedCandidate), relation: String) -> Int {
  values |> list.filter(fn(value) { value.relation == relation }) |> list.length
}

fn valid_subject(value: Subject) -> Bool {
  nonempty(value.issuer_id)
  && nonempty(value.listing_id)
  && nonempty(value.mic)
  && nonempty(value.share_class)
}

fn valid_predicate(value: Predicate) -> Bool {
  nonempty(value.predicate_id) && nonempty(value.label) && nonempty(value.rule)
}

fn valid_candidate(value: Candidate) -> Bool {
  nonempty(value.candidate_id)
  && valid_subject(value.subject)
  && list.length(value.classifications) <= 20
  && list.all(value.classifications, nonempty)
  && nonempty(value.currency)
  && nonempty(value.fiscal_period)
}

fn valid_fact(value: Fact) -> Bool {
  nonempty(value.predicate_id)
  && list.contains(
    ["observed_true", "observed_false", "unknown", "conflicting"],
    value.state,
  )
  && nonempty(value.source_receipt)
  && case value.state, value.observed_value {
    "observed_true", Some(text) -> nonempty(text)
    "observed_false", Some(text) -> nonempty(text)
    "observed_true", None -> False
    "observed_false", None -> False
    _, _ -> True
  }
}

fn valid_track_mic(track: String, mic: String) -> Bool {
  case track {
    "cn" -> list.contains(["XSHG", "XSHE", "XBSE"], mic)
    "hk" -> mic == "XHKG"
    "us" -> list.contains(["XNYS", "XNAS"], mic)
    _ -> False
  }
}

fn valid_date(value: String) -> Bool {
  string.length(value) == 10
  && string.slice(value, 4, 1) == "-"
  && string.slice(value, 7, 1) == "-"
}

fn nonempty(value: String) -> Bool {
  value != "" && value == string.trim(value) && string.length(value) <= 20_000
}

fn validate_page(offset: Int, limit: Int) -> Result(Nil, PeerError) {
  case offset >= 0 && limit >= 1 && limit <= 100 {
    True -> Ok(Nil)
    False -> Error(InvalidPage)
  }
}

fn unique_predicates(values: List(Predicate)) -> Bool {
  unique_strings(list.map(values, fn(value) { value.predicate_id }))
}

fn unique_candidates(values: List(Candidate)) -> Bool {
  unique_strings(list.map(values, fn(value) { value.candidate_id }))
  && unique_strings(list.map(values, fn(value) { value.subject.listing_id }))
}

fn unique_fact_predicates(values: List(Fact)) -> Bool {
  unique_strings(list.map(values, fn(value) { value.predicate_id }))
}

fn unique_strings(values: List(String)) -> Bool {
  case values {
    [] -> True
    [value, ..rest] -> !list.contains(rest, value) && unique_strings(rest)
  }
}

fn verify_hash(bytes: String, expected: String) -> Result(Nil, PeerError) {
  case hash.text(bytes) {
    Error(_) -> Error(ContentHashMismatch)
    Ok(actual) ->
      case identity.sha256_value(actual) == expected {
        True -> Ok(Nil)
        False -> Error(ContentHashMismatch)
      }
  }
}

fn find_candidate(
  values: List(ProjectedCandidate),
  id: String,
) -> Option(ProjectedCandidate) {
  case values {
    [] -> None
    [value, ..rest] ->
      case value.candidate.candidate_id == id {
        True -> Some(value)
        False -> find_candidate(rest, id)
      }
  }
}

fn packet_decoder() -> decode.Decoder(
  #(
    Int,
    String,
    String,
    Subject,
    String,
    List(Predicate),
    List(Candidate),
    List(String),
  ),
) {
  use version <- decode.field("schemaVersion", decode.int)
  use contract <- decode.field("contractId", decode.string)
  use track <- decode.field("track", decode.string)
  use target <- decode.field("target", subject_decoder())
  use date <- decode.field("evidenceDate", decode.string)
  use predicates <- decode.field("predicates", decode.list(predicate_decoder()))
  use candidates <- decode.field("candidates", decode.list(candidate_decoder()))
  use omissions <- decode.field("omissions", decode.list(decode.string))
  decode.success(#(
    version,
    contract,
    track,
    target,
    date,
    predicates,
    candidates,
    omissions,
  ))
}

fn subject_decoder() -> decode.Decoder(Subject) {
  use issuer <- decode.field("issuerId", decode.string)
  use listing <- decode.field("listingId", decode.string)
  use mic <- decode.field("mic", decode.string)
  use share_class <- decode.field("shareClass", decode.string)
  decode.success(Subject(issuer, listing, mic, share_class))
}

fn predicate_decoder() -> decode.Decoder(Predicate) {
  use id <- decode.field("predicateId", decode.string)
  use label <- decode.field("label", decode.string)
  use rule <- decode.field("rule", decode.string)
  decode.success(Predicate(id, label, rule))
}

fn fact_decoder() -> decode.Decoder(Fact) {
  use id <- decode.field("predicateId", decode.string)
  use state <- decode.field("state", decode.string)
  use value <- optional_string("observedValue")
  use receipt <- decode.field("sourceReceipt", decode.string)
  decode.success(Fact(id, state, value, receipt))
}

fn candidate_decoder() -> decode.Decoder(Candidate) {
  use id <- decode.field("candidateId", decode.string)
  use subject <- decode.field("subject", subject_decoder())
  use classifications <- decode.field(
    "classifications",
    decode.list(decode.string),
  )
  use currency <- decode.field("currency", decode.string)
  use period <- decode.field("fiscalPeriod", decode.string)
  use facts <- decode.field("facts", decode.list(fact_decoder()))
  decode.success(Candidate(
    id,
    subject,
    classifications,
    currency,
    period,
    facts,
  ))
}

fn optional_string(
  name: String,
  next: fn(Option(String)) -> decode.Decoder(value),
) -> decode.Decoder(value) {
  decode.optional_field(name, None, decode.optional(decode.string), next)
}

fn header_fields(value: PeerSet) -> List(#(String, json.Json)) {
  [
    #("schemaVersion", json.int(1)),
    #("contractId", json.string("stock_peers_v1")),
    #("track", json.string(value.track)),
    #("target", subject_json(value.target)),
    #("evidenceDate", json.string(value.evidence_date)),
    #("packetSha256", json.string(value.packet_sha256)),
    #("predicates", json.array(value.predicates, predicate_json)),
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

fn predicate_json(value: Predicate) -> json.Json {
  json.object([
    #("predicateId", json.string(value.predicate_id)),
    #("label", json.string(value.label)),
    #("rule", json.string(value.rule)),
  ])
}

fn fact_json(value: Fact) -> json.Json {
  json.object([
    #("predicateId", json.string(value.predicate_id)),
    #("state", json.string(value.state)),
    #("observedValue", json.nullable(value.observed_value, json.string)),
    #("sourceReceipt", json.string(value.source_receipt)),
  ])
}

fn candidate_header_json(value: ProjectedCandidate) -> json.Json {
  json.object([
    #("candidateId", json.string(value.candidate.candidate_id)),
    #("subject", subject_json(value.candidate.subject)),
    #("relation", json.string(value.relation)),
    #("currency", json.string(value.candidate.currency)),
    #("fiscalPeriod", json.string(value.candidate.fiscal_period)),
  ])
}

fn candidate_json(value: ProjectedCandidate) -> json.Json {
  json.object([
    #("candidateId", json.string(value.candidate.candidate_id)),
    #("subject", subject_json(value.candidate.subject)),
    #("relation", json.string(value.relation)),
    #(
      "classifications",
      json.array(value.candidate.classifications, json.string),
    ),
    #("currency", json.string(value.candidate.currency)),
    #("fiscalPeriod", json.string(value.candidate.fiscal_period)),
    #("facts", json.array(value.candidate.facts, fact_json)),
  ])
}
