import finance_provenance/hash
import finance_provenance/identity
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string

pub type Token {
  Token(text: String, start_offset: Int, end_offset: Int)
}

pub type Document {
  Document(
    document_id: String,
    source_identity: String,
    language: String,
    rights: String,
    published_at: String,
    retrieved_at: String,
    text: String,
    text_sha256: String,
    tokens: List(Token),
  )
}

pub type Hit {
  Hit(label: String, weight: Int, token: Token)
}

pub type Analysis {
  Analysis(
    document: Document,
    positive_score: Int,
    negative_score: Int,
    hits: List(Hit),
    warnings: List(String),
  )
}

pub opaque type Response {
  Response(
    aggregation: String,
    documents: List(Analysis),
    packet_sha256: String,
  )
}

pub type SentimentError {
  InvalidJson
  ContentHashMismatch
  WrongSchema
  WrongContract
  UnsupportedModel
  UnsupportedAggregation
  TooManyDocuments
  InvalidDocument
  InvalidDocumentHash
  TooManyTokens
  InvalidToken
  OverlappingTokens
}

pub fn analyze(
  expected_sha256: String,
  bytes: String,
) -> Result(Response, SentimentError) {
  use _ <- result.try(verify_hash(bytes, expected_sha256))
  use packet <- result.try(case json.parse(bytes, packet_decoder()) {
    Ok(value) -> Ok(value)
    Error(_) -> Error(InvalidJson)
  })
  let #(version, contract, model, aggregation, documents) = packet
  use _ <- result.try(case version == 1 {
    True -> Ok(Nil)
    False -> Error(WrongSchema)
  })
  use _ <- result.try(case contract == "finance_sentiment_v1" {
    True -> Ok(Nil)
    False -> Error(WrongContract)
  })
  use _ <- result.try(case model == "finance_lexicon_v1" {
    True -> Ok(Nil)
    False -> Error(UnsupportedModel)
  })
  use _ <- result.try(case list.contains(["none", "sum"], aggregation) {
    True -> Ok(Nil)
    False -> Error(UnsupportedAggregation)
  })
  use _ <- result.try(
    case list.length(documents) >= 1 && list.length(documents) <= 100 {
      True -> Ok(Nil)
      False -> Error(TooManyDocuments)
    },
  )
  use _ <- result.try(validate_documents(documents))
  Ok(Response(aggregation, list.map(documents, classify), expected_sha256))
}

pub fn details(value: Response) -> json.Json {
  let aggregate = case value.aggregation {
    "sum" ->
      json.object([
        #("positiveScore", json.int(sum_positive(value.documents))),
        #("negativeScore", json.int(sum_negative(value.documents))),
      ])
    _ -> json.null()
  }
  json.object([
    #("schemaVersion", json.int(1)),
    #("contractId", json.string("finance_sentiment_v1")),
    #("model", json.string("finance_lexicon_v1")),
    #(
      "modelParameters",
      json.object([
        #("tokenMatching", json.string("exact_case_folded_v1")),
        #("positiveWeight", json.int(1)),
        #("negativeWeight", json.int(-1)),
      ]),
    ),
    #("aggregationPolicy", json.string(value.aggregation)),
    #("aggregate", aggregate),
    #("packetSha256", json.string(value.packet_sha256)),
    #("documents", json.array(value.documents, analysis_json)),
    #("decisionOwner", json.string("llm")),
    #(
      "pluginDecisionFields",
      json.array(["fixed_lexicon_membership_and_sum"], json.string),
    ),
    #(
      "explicitNonClaims",
      json.array(
        [
          "truth",
          "credibility",
          "market_impact",
          "mood_regime",
          "recommendation",
          "trade_mapping",
        ],
        json.string,
      ),
    ),
  ])
}

pub fn summary(value: Response) -> String {
  "finance_sentiment_v1: classified "
  <> int.to_string(list.length(value.documents))
  <> " exact document(s) with finance_lexicon_v1; positive="
  <> int.to_string(sum_positive(value.documents))
  <> ", negative="
  <> int.to_string(sum_negative(value.documents))
  <> "; interpretation remains with the LLM"
}

pub fn error_message(error: SentimentError) -> String {
  case error {
    InvalidJson -> "Sentiment import is not valid JSON"
    ContentHashMismatch -> "Sentiment import bytes do not match expectedSha256"
    WrongSchema -> "Sentiment schemaVersion must be 1"
    WrongContract -> "Sentiment contractId must be finance_sentiment_v1"
    UnsupportedModel -> "Sentiment model must be finance_lexicon_v1"
    UnsupportedAggregation -> "Sentiment aggregationPolicy must be none or sum"
    TooManyDocuments -> "Sentiment requires 1..100 documents"
    InvalidDocument ->
      "Sentiment document identity, rights, times, language, or text is invalid"
    InvalidDocumentHash ->
      "Sentiment document textSha256 does not bind exact text"
    TooManyTokens -> "Sentiment document exceeds the 10000-token budget"
    InvalidToken ->
      "Sentiment token text and offsets do not match exact source text"
    OverlappingTokens -> "Sentiment token offsets overlap or are out of order"
  }
}

fn validate_documents(values: List(Document)) -> Result(Nil, SentimentError) {
  case values {
    [] -> Ok(Nil)
    [value, ..rest] -> {
      use _ <- result.try(validate_document(value))
      validate_documents(rest)
    }
  }
}

fn validate_document(value: Document) -> Result(Nil, SentimentError) {
  use _ <- result.try(
    case
      nonempty(value.document_id)
      && nonempty(value.source_identity)
      && nonempty(value.language)
      && nonempty(value.rights)
      && nonempty(value.published_at)
      && nonempty(value.retrieved_at)
      && string.length(value.text) <= 500_000
    {
      True -> Ok(Nil)
      False -> Error(InvalidDocument)
    },
  )
  use _ <- result.try(case list.length(value.tokens) <= 10_000 {
    True -> Ok(Nil)
    False -> Error(TooManyTokens)
  })
  use _ <- result.try(verify_document_hash(value))
  validate_tokens(value.text, value.tokens, 0)
}

fn validate_tokens(
  text: String,
  tokens: List(Token),
  prior_end: Int,
) -> Result(Nil, SentimentError) {
  case tokens {
    [] -> Ok(Nil)
    [token, ..rest] ->
      case
        token.start_offset >= prior_end
        && token.end_offset >= token.start_offset
        && string.slice(
          text,
          token.start_offset,
          token.end_offset - token.start_offset,
        )
        == token.text
        && token.text != ""
      {
        True -> validate_tokens(text, rest, token.end_offset)
        False ->
          case token.start_offset < prior_end {
            True -> Error(OverlappingTokens)
            False -> Error(InvalidToken)
          }
      }
  }
}

fn verify_document_hash(value: Document) -> Result(Nil, SentimentError) {
  case hash.text(value.text) {
    Error(_) -> Error(InvalidDocumentHash)
    Ok(actual) ->
      case identity.sha256_value(actual) == value.text_sha256 {
        True -> Ok(Nil)
        False -> Error(InvalidDocumentHash)
      }
  }
}

fn verify_hash(bytes: String, expected: String) -> Result(Nil, SentimentError) {
  case hash.text(bytes) {
    Error(_) -> Error(ContentHashMismatch)
    Ok(actual) ->
      case identity.sha256_value(actual) == expected {
        True -> Ok(Nil)
        False -> Error(ContentHashMismatch)
      }
  }
}

fn classify(value: Document) -> Analysis {
  let hits =
    value.tokens
    |> list.filter_map(fn(token) {
      let normalized = string.lowercase(token.text)
      case label(value.language, normalized) {
        "positive" -> Ok(Hit("positive", 1, token))
        "negative" -> Ok(Hit("negative", -1, token))
        _ -> Error(Nil)
      }
    })
  let positive =
    hits |> list.filter(fn(hit) { hit.label == "positive" }) |> list.length
  let negative =
    hits |> list.filter(fn(hit) { hit.label == "negative" }) |> list.length
  let warnings = case language_supported(value.language) {
    True -> ["sarcasm_not_detected", "caller_supplied_token_coverage"]
    False -> [
      "unknown_language",
      "sarcasm_not_detected",
      "caller_supplied_token_coverage",
    ]
  }
  Analysis(value, positive, 0 - negative, hits, warnings)
}

fn language_supported(language: String) -> Bool {
  list.contains(["en", "en-US", "zh-CN"], language)
}

fn label(language: String, token: String) -> String {
  case language {
    "en" | "en-US" ->
      case
        list.contains(
          [
            "growth",
            "beat",
            "raised",
            "strong",
            "improved",
            "profit",
            "upgrade",
          ],
          token,
        )
      {
        True -> "positive"
        False ->
          case
            list.contains(
              [
                "decline",
                "miss",
                "lowered",
                "weak",
                "risk",
                "loss",
                "downgrade",
              ],
              token,
            )
          {
            True -> "negative"
            False -> "unclassified"
          }
      }
    "zh-CN" ->
      case list.contains(["增长", "超预期", "上调", "改善", "盈利"], token) {
        True -> "positive"
        False ->
          case list.contains(["下滑", "低于预期", "下调", "风险", "亏损"], token) {
            True -> "negative"
            False -> "unclassified"
          }
      }
    _ -> "unclassified"
  }
}

fn sum_positive(values: List(Analysis)) -> Int {
  values |> list.fold(0, fn(total, value) { total + value.positive_score })
}

fn sum_negative(values: List(Analysis)) -> Int {
  values |> list.fold(0, fn(total, value) { total + value.negative_score })
}

fn nonempty(value: String) -> Bool {
  value != "" && value == string.trim(value) && string.length(value) <= 20_000
}

fn packet_decoder() -> decode.Decoder(
  #(Int, String, String, String, List(Document)),
) {
  use version <- decode.field("schemaVersion", decode.int)
  use contract <- decode.field("contractId", decode.string)
  use model <- decode.field("model", decode.string)
  use aggregation <- decode.field("aggregationPolicy", decode.string)
  use documents <- decode.field("documents", decode.list(document_decoder()))
  decode.success(#(version, contract, model, aggregation, documents))
}

fn document_decoder() -> decode.Decoder(Document) {
  use id <- decode.field("documentId", decode.string)
  use source <- decode.field("sourceIdentity", decode.string)
  use language <- decode.field("language", decode.string)
  use rights <- decode.field("rights", decode.string)
  use published <- decode.field("publishedAt", decode.string)
  use retrieved <- decode.field("retrievedAt", decode.string)
  use text <- decode.field("text", decode.string)
  use text_hash <- decode.field("textSha256", decode.string)
  use tokens <- decode.field("tokens", decode.list(token_decoder()))
  decode.success(Document(
    id,
    source,
    language,
    rights,
    published,
    retrieved,
    text,
    text_hash,
    tokens,
  ))
}

fn token_decoder() -> decode.Decoder(Token) {
  use text <- decode.field("text", decode.string)
  use start <- decode.field("startOffset", decode.int)
  use end <- decode.field("endOffset", decode.int)
  decode.success(Token(text, start, end))
}

fn analysis_json(value: Analysis) -> json.Json {
  json.object([
    #("document", document_header_json(value.document)),
    #(
      "scores",
      json.object([
        #("positive", json.int(value.positive_score)),
        #("negative", json.int(value.negative_score)),
      ]),
    ),
    #("contributingSpans", json.array(value.hits, hit_json)),
    #("warnings", json.array(value.warnings, json.string)),
  ])
}

fn document_header_json(value: Document) -> json.Json {
  json.object([
    #("documentId", json.string(value.document_id)),
    #("sourceIdentity", json.string(value.source_identity)),
    #("language", json.string(value.language)),
    #("rights", json.string(value.rights)),
    #("publishedAt", json.string(value.published_at)),
    #("retrievedAt", json.string(value.retrieved_at)),
    #("textSha256", json.string(value.text_sha256)),
    #("tokenCount", json.int(list.length(value.tokens))),
  ])
}

fn hit_json(value: Hit) -> json.Json {
  json.object([
    #("label", json.string(value.label)),
    #("weight", json.int(value.weight)),
    #("text", json.string(value.token.text)),
    #("startOffset", json.int(value.token.start_offset)),
    #("endOffset", json.int(value.token.end_offset)),
  ])
}
