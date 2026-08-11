import finance_provenance/hash
import finance_provenance/identity
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None}
import gleam/result
import gleam/string

pub type Claim {
  Claim(
    claim_id: String,
    text: String,
    entities: List(String),
    predicate: String,
    value_lexeme: String,
    unit: Option(String),
    effective_date: String,
    jurisdiction: String,
    claimant: String,
    claimant_source: String,
    extraction_confidence: String,
  )
}

pub type Passage {
  Passage(passage_id: String, text: String, start_offset: Int, end_offset: Int)
}

pub type Assertion {
  Assertion(
    predicate: String,
    value_lexeme: String,
    unit: Option(String),
    negated: Bool,
    exclusive: Bool,
    passage_id: String,
  )
}

pub type Evidence {
  Evidence(
    evidence_id: String,
    source_identity: String,
    authority_role: String,
    published_at: String,
    retrieved_at: String,
    access_state: String,
    independence_id: String,
    circular_sources: List(String),
    source_url: String,
    passages: List(Passage),
    assertions: List(Assertion),
  )
}

pub type Classified {
  Classified(evidence: Evidence, relation: String)
}

pub opaque type Response {
  Response(
    claim: Claim,
    search_scope: List(String),
    cutoff: String,
    omissions: List(String),
    evidence: List(Classified),
    packet_sha256: String,
  )
}

pub type RumorError {
  InvalidJson
  ContentHashMismatch
  WrongSchema
  WrongContract
  InvalidClaim
  InvalidSearchScope
  TooManyEvidence
  TooManyOmissions
  DuplicateEvidence
  InvalidEvidence
  DuplicatePassage
  InvalidPassage
  InvalidAssertion
  MissingPassage
}

pub fn check(
  expected_sha256: String,
  bytes: String,
) -> Result(Response, RumorError) {
  use _ <- result.try(verify_hash(bytes, expected_sha256))
  use packet <- result.try(case json.parse(bytes, packet_decoder()) {
    Ok(value) -> Ok(value)
    Error(_) -> Error(InvalidJson)
  })
  let #(version, contract, claim, scope, cutoff, omissions, evidence) = packet
  use _ <- result.try(case version == 1 {
    True -> Ok(Nil)
    False -> Error(WrongSchema)
  })
  use _ <- result.try(case contract == "finance_rumor_check_v1" {
    True -> Ok(Nil)
    False -> Error(WrongContract)
  })
  use _ <- result.try(case valid_claim(claim) {
    True -> Ok(Nil)
    False -> Error(InvalidClaim)
  })
  use _ <- result.try(
    case
      list.length(scope) >= 1
      && list.length(scope) <= 50
      && list.all(scope, nonempty)
      && nonempty(cutoff)
    {
      True -> Ok(Nil)
      False -> Error(InvalidSearchScope)
    },
  )
  use _ <- result.try(case list.length(evidence) <= 100 {
    True -> Ok(Nil)
    False -> Error(TooManyEvidence)
  })
  use _ <- result.try(case list.length(omissions) <= 200 {
    True -> Ok(Nil)
    False -> Error(TooManyOmissions)
  })
  use _ <- result.try(case unique_evidence(evidence) {
    True -> Ok(Nil)
    False -> Error(DuplicateEvidence)
  })
  use _ <- result.try(validate_evidence(evidence))
  Ok(Response(
    claim,
    scope,
    cutoff,
    omissions,
    list.map(evidence, fn(value) { Classified(value, classify(claim, value)) }),
    expected_sha256,
  ))
}

pub fn details(value: Response) -> json.Json {
  json.object([
    #("schemaVersion", json.int(1)),
    #("contractId", json.string("finance_rumor_check_v1")),
    #("claim", claim_json(value.claim)),
    #("searchScope", json.array(value.search_scope, json.string)),
    #("cutoff", json.string(value.cutoff)),
    #("omissions", json.array(value.omissions, json.string)),
    #("packetSha256", json.string(value.packet_sha256)),
    #("evidenceCount", json.int(list.length(value.evidence))),
    #("evidence", json.array(value.evidence, classified_json)),
    #("aggregateVerdict", json.null()),
    #("decisionOwner", json.string("llm")),
    #(
      "pluginDecisionFields",
      json.array(["exact_claim_evidence_relation_v1"], json.string),
    ),
    #(
      "explicitNonClaims",
      json.array(
        [
          "true_false",
          "verified_debunked",
          "credibility",
          "source_quality",
          "materiality",
          "recommendation",
          "trade_action",
        ],
        json.string,
      ),
    ),
  ])
}

pub fn summary(value: Response) -> String {
  "finance_rumor_check_v1: independently classified "
  <> int.to_string(list.length(value.evidence))
  <> " caller-supplied source(s); supports="
  <> int.to_string(count(value.evidence, "supports"))
  <> ", contradicts="
  <> int.to_string(count(value.evidence, "contradicts"))
  <> ", conflicts="
  <> int.to_string(count(value.evidence, "conflict"))
  <> "; no aggregate truth verdict"
}

pub fn error_message(error: RumorError) -> String {
  case error {
    InvalidJson -> "Rumor-check import is not valid JSON"
    ContentHashMismatch -> "Rumor-check bytes do not match expectedSha256"
    WrongSchema -> "Rumor-check schemaVersion must be 1"
    WrongContract -> "Rumor-check contractId must be finance_rumor_check_v1"
    InvalidClaim -> "Rumor-check structured claim is incomplete"
    InvalidSearchScope -> "Rumor-check search scope/cutoff is invalid"
    TooManyEvidence -> "Rumor-check exceeds the 100-source budget"
    TooManyOmissions -> "Rumor-check exceeds the 200-omission budget"
    DuplicateEvidence -> "Rumor-check has duplicate evidenceId values"
    InvalidEvidence ->
      "Rumor-check contains invalid source identity, authority, access, provenance, or bounds"
    DuplicatePassage -> "Rumor-check source contains duplicate passageId values"
    InvalidPassage -> "Rumor-check contains an invalid exact passage or offsets"
    InvalidAssertion ->
      "Rumor-check contains an invalid structured evidence assertion"
    MissingPassage -> "Rumor-check assertion references a missing passageId"
  }
}

fn validate_evidence(values: List(Evidence)) -> Result(Nil, RumorError) {
  case values {
    [] -> Ok(Nil)
    [value, ..rest] -> {
      use _ <- result.try(validate_one(value))
      validate_evidence(rest)
    }
  }
}

fn validate_one(value: Evidence) -> Result(Nil, RumorError) {
  use _ <- result.try(
    case
      nonempty(value.evidence_id)
      && nonempty(value.source_identity)
      && nonempty(value.authority_role)
      && nonempty(value.published_at)
      && nonempty(value.retrieved_at)
      && list.contains(
        ["accessible", "not_found", "inaccessible"],
        value.access_state,
      )
      && nonempty(value.independence_id)
      && list.length(value.circular_sources) <= 50
      && list.all(value.circular_sources, nonempty)
      && nonempty(value.source_url)
      && list.length(value.passages) <= 100
      && list.length(value.assertions) <= 100
    {
      True -> Ok(Nil)
      False -> Error(InvalidEvidence)
    },
  )
  use _ <- result.try(case unique_passages(value.passages) {
    True -> Ok(Nil)
    False -> Error(DuplicatePassage)
  })
  use _ <- result.try(case list.all(value.passages, valid_passage) {
    True -> Ok(Nil)
    False -> Error(InvalidPassage)
  })
  validate_assertions(value.assertions, value.passages)
}

fn validate_assertions(
  values: List(Assertion),
  passages: List(Passage),
) -> Result(Nil, RumorError) {
  case values {
    [] -> Ok(Nil)
    [value, ..rest] ->
      case
        nonempty(value.predicate)
        && nonempty(value.value_lexeme)
        && nonempty(value.passage_id)
      {
        False -> Error(InvalidAssertion)
        True ->
          case
            list.any(passages, fn(passage) {
              passage.passage_id == value.passage_id
            })
          {
            False -> Error(MissingPassage)
            True -> validate_assertions(rest, passages)
          }
      }
  }
}

fn classify(claim: Claim, value: Evidence) -> String {
  case value.access_state {
    "not_found" -> "not_found"
    "inaccessible" -> "inaccessible"
    _ -> {
      let relevant =
        value.assertions
        |> list.filter(fn(assertion) { assertion.predicate == claim.predicate })
      case relevant {
        [] -> "cannot_evaluate"
        _ -> {
          let supports =
            list.any(relevant, fn(assertion) {
              exact_value(claim, assertion) && !assertion.negated
            })
          let contradicts =
            list.any(relevant, fn(assertion) {
              exact_value(claim, assertion)
              && assertion.negated
              || !exact_value(claim, assertion)
              && assertion.exclusive
            })
          case supports, contradicts {
            True, True -> "conflict"
            True, False -> "supports"
            False, True -> "contradicts"
            False, False -> "related"
          }
        }
      }
    }
  }
}

fn exact_value(claim: Claim, assertion: Assertion) -> Bool {
  claim.value_lexeme == assertion.value_lexeme && claim.unit == assertion.unit
}

fn count(values: List(Classified), relation: String) -> Int {
  values |> list.filter(fn(value) { value.relation == relation }) |> list.length
}

fn valid_claim(value: Claim) -> Bool {
  nonempty(value.claim_id)
  && nonempty(value.text)
  && list.length(value.entities) >= 1
  && list.length(value.entities) <= 50
  && list.all(value.entities, nonempty)
  && nonempty(value.predicate)
  && nonempty(value.value_lexeme)
  && nonempty(value.effective_date)
  && nonempty(value.jurisdiction)
  && nonempty(value.claimant)
  && nonempty(value.claimant_source)
  && nonempty(value.extraction_confidence)
}

fn valid_passage(value: Passage) -> Bool {
  nonempty(value.passage_id)
  && value.start_offset >= 0
  && value.end_offset - value.start_offset == string.length(value.text)
  && string.length(value.text) <= 20_000
}

fn nonempty(value: String) -> Bool {
  value != "" && value == string.trim(value) && string.length(value) <= 20_000
}

fn unique_evidence(values: List(Evidence)) -> Bool {
  unique_strings(list.map(values, fn(value) { value.evidence_id }))
}

fn unique_passages(values: List(Passage)) -> Bool {
  unique_strings(list.map(values, fn(value) { value.passage_id }))
}

fn unique_strings(values: List(String)) -> Bool {
  case values {
    [] -> True
    [value, ..rest] -> !list.contains(rest, value) && unique_strings(rest)
  }
}

fn verify_hash(bytes: String, expected: String) -> Result(Nil, RumorError) {
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
  #(Int, String, Claim, List(String), String, List(String), List(Evidence)),
) {
  use version <- decode.field("schemaVersion", decode.int)
  use contract <- decode.field("contractId", decode.string)
  use claim <- decode.field("claim", claim_decoder())
  use scope <- decode.field("searchScope", decode.list(decode.string))
  use cutoff <- decode.field("cutoff", decode.string)
  use omissions <- decode.field("omissions", decode.list(decode.string))
  use evidence <- decode.field("evidence", decode.list(evidence_decoder()))
  decode.success(#(version, contract, claim, scope, cutoff, omissions, evidence))
}

fn claim_decoder() -> decode.Decoder(Claim) {
  use id <- decode.field("claimId", decode.string)
  use text <- decode.field("text", decode.string)
  use entities <- decode.field("entities", decode.list(decode.string))
  use predicate <- decode.field("predicate", decode.string)
  use value <- decode.field("valueLexeme", decode.string)
  use unit <- optional_string("unit")
  use date <- decode.field("effectiveDate", decode.string)
  use jurisdiction <- decode.field("jurisdiction", decode.string)
  use claimant <- decode.field("claimant", decode.string)
  use source <- decode.field("claimantSource", decode.string)
  use confidence <- decode.field("extractionConfidence", decode.string)
  decode.success(Claim(
    id,
    text,
    entities,
    predicate,
    value,
    unit,
    date,
    jurisdiction,
    claimant,
    source,
    confidence,
  ))
}

fn passage_decoder() -> decode.Decoder(Passage) {
  use id <- decode.field("passageId", decode.string)
  use text <- decode.field("text", decode.string)
  use start <- decode.field("startOffset", decode.int)
  use end <- decode.field("endOffset", decode.int)
  decode.success(Passage(id, text, start, end))
}

fn assertion_decoder() -> decode.Decoder(Assertion) {
  use predicate <- decode.field("predicate", decode.string)
  use value <- decode.field("valueLexeme", decode.string)
  use unit <- optional_string("unit")
  use negated <- decode.field("negated", decode.bool)
  use exclusive <- decode.field("exclusive", decode.bool)
  use passage <- decode.field("passageId", decode.string)
  decode.success(Assertion(predicate, value, unit, negated, exclusive, passage))
}

fn evidence_decoder() -> decode.Decoder(Evidence) {
  use id <- decode.field("evidenceId", decode.string)
  use source <- decode.field("sourceIdentity", decode.string)
  use role <- decode.field("authorityRole", decode.string)
  use published <- decode.field("publishedAt", decode.string)
  use retrieved <- decode.field("retrievedAt", decode.string)
  use access <- decode.field("accessState", decode.string)
  use independence <- decode.field("independenceId", decode.string)
  use circular <- decode.field("circularSources", decode.list(decode.string))
  use url <- decode.field("sourceUrl", decode.string)
  use passages <- decode.field("passages", decode.list(passage_decoder()))
  use assertions <- decode.field("assertions", decode.list(assertion_decoder()))
  decode.success(Evidence(
    id,
    source,
    role,
    published,
    retrieved,
    access,
    independence,
    circular,
    url,
    passages,
    assertions,
  ))
}

fn optional_string(
  name: String,
  next: fn(Option(String)) -> decode.Decoder(value),
) -> decode.Decoder(value) {
  decode.optional_field(name, None, decode.optional(decode.string), next)
}

fn claim_json(value: Claim) -> json.Json {
  json.object([
    #("claimId", json.string(value.claim_id)),
    #("text", json.string(value.text)),
    #("entities", json.array(value.entities, json.string)),
    #("predicate", json.string(value.predicate)),
    #("valueLexeme", json.string(value.value_lexeme)),
    #("unit", json.nullable(value.unit, json.string)),
    #("effectiveDate", json.string(value.effective_date)),
    #("jurisdiction", json.string(value.jurisdiction)),
    #("claimant", json.string(value.claimant)),
    #("claimantSource", json.string(value.claimant_source)),
    #("extractionConfidence", json.string(value.extraction_confidence)),
  ])
}

fn passage_json(value: Passage) -> json.Json {
  json.object([
    #("passageId", json.string(value.passage_id)),
    #("text", json.string(value.text)),
    #("startOffset", json.int(value.start_offset)),
    #("endOffset", json.int(value.end_offset)),
  ])
}

fn assertion_json(value: Assertion) -> json.Json {
  json.object([
    #("predicate", json.string(value.predicate)),
    #("valueLexeme", json.string(value.value_lexeme)),
    #("unit", json.nullable(value.unit, json.string)),
    #("negated", json.bool(value.negated)),
    #("exclusive", json.bool(value.exclusive)),
    #("passageId", json.string(value.passage_id)),
  ])
}

fn classified_json(value: Classified) -> json.Json {
  json.object([
    #("evidenceId", json.string(value.evidence.evidence_id)),
    #("relation", json.string(value.relation)),
    #("sourceIdentity", json.string(value.evidence.source_identity)),
    #("authorityRole", json.string(value.evidence.authority_role)),
    #("publishedAt", json.string(value.evidence.published_at)),
    #("retrievedAt", json.string(value.evidence.retrieved_at)),
    #("accessState", json.string(value.evidence.access_state)),
    #("independenceId", json.string(value.evidence.independence_id)),
    #(
      "circularSources",
      json.array(value.evidence.circular_sources, json.string),
    ),
    #("sourceUrl", json.string(value.evidence.source_url)),
    #("passages", json.array(value.evidence.passages, passage_json)),
    #("assertions", json.array(value.evidence.assertions, assertion_json)),
  ])
}
