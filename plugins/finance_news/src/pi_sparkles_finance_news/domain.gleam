import finance_core/time.{type Instant}
import finance_market_alpaca/news
import finance_provenance/identity.{type Sha256}
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub type Venue {
  Xnys
  Xnas
}

pub type Plan {
  Plan(venue: Venue, query: news.Query)
}

pub type Pagination {
  Complete
  TruncatedByPageBudget(maximum_pages: Int)
  TruncatedByArticleBudget(maximum_articles: Int)
}

pub type SourcePage {
  SourcePage(
    sequence: Int,
    request_id: Option(String),
    response_byte_length: Int,
    content_sha256: Sha256,
    news: news.Page,
  )
}

pub type Output {
  Output(summary: String, details: json.Json)
}

pub type Error {
  WrongTrack(received: String)
  WrongVenue(received: String)
  InvalidQuery(news.QueryError)
  NoSourcePages
  InvalidPageSequence
  TooManyArticles(maximum: Int, received: Int)
  InvalidPagination
  SourceMismatch(id: Int, source: String)
  SymbolAssociationMismatch(id: Int)
  InvalidArticleTime(id: Int)
  OutOfOrderPages(id: Int)
}

pub fn plan(
  track: String,
  venue: String,
  symbol: String,
  start_at: String,
  end_at: String,
  page_size: Int,
  maximum_pages: Int,
  maximum_articles: Int,
) -> Result(Plan, Error) {
  use Nil <- result.try(case track {
    "us" -> Ok(Nil)
    value -> Error(WrongTrack(value))
  })
  use venue_value <- result.try(case venue {
    "XNYS" -> Ok(Xnys)
    "XNAS" -> Ok(Xnas)
    value -> Error(WrongVenue(value))
  })
  news.query(
    symbol,
    start_at,
    end_at,
    page_size,
    maximum_pages,
    maximum_articles,
  )
  |> result.map(fn(query) { Plan(venue_value, query) })
  |> result.map_error(InvalidQuery)
}

pub fn run(
  plan: Plan,
  pages: List(SourcePage),
  pagination: Pagination,
  retrieved_at: Instant,
) -> Result(Output, Error) {
  use Nil <- result.try(validate_page_sequence(pages, 1))
  let article_count =
    pages
    |> list.fold(from: 0, with: fn(total, page) {
      total + list.length(page.news.articles)
    })
  use Nil <- result.try(case article_count <= plan.query.maximum_articles {
    True -> Ok(Nil)
    False -> Error(TooManyArticles(plan.query.maximum_articles, article_count))
  })
  use Nil <- result.try(validate_articles(pages, plan.query, None))
  use Nil <- result.try(validate_pagination(
    pages,
    pagination,
    article_count,
    plan.query,
  ))
  let state = pagination_name(pagination)
  Ok(Output(
    "Alpaca/Benzinga US news metadata for "
      <> plan.query.symbol
      <> " at caller-declared "
      <> venue_name(plan.venue)
      <> ": "
      <> int.to_string(article_count)
      <> " exact provider article record(s) across "
      <> int.to_string(list.length(pages))
      <> " page(s), pagination "
      <> state
      <> ". Headlines are vendor news metadata, not verified events or catalyst conclusions; article bodies and summaries are withheld.",
    json.object([
      #("schema", json.string("pi-sparkles/finance-news-result")),
      #("schemaVersion", json.int(1)),
      #("operation", json.string("finance_news")),
      #("track", json.string("us")),
      #("venue", json.string(venue_name(plan.venue))),
      #("venueEvidence", json.string("caller_declared_not_provider_verified")),
      #(
        "query",
        json.object([
          #("symbol", json.string(plan.query.symbol)),
          #("startAt", json.string(plan.query.start_at)),
          #("endAt", json.string(plan.query.end_at)),
          #(
            "intervalAxis",
            json.string("alpaca_reference_does_not_explicitly_name_filter_axis"),
          ),
          #("sortAxis", json.string("updated_at")),
          #("sort", json.string("asc")),
          #("includeContent", json.bool(False)),
          #("excludeContentless", json.bool(False)),
          #("pageSize", json.int(plan.query.page_size)),
          #("maximumPages", json.int(plan.query.maximum_pages)),
          #("maximumArticles", json.int(plan.query.maximum_articles)),
        ]),
      ),
      #("articleCount", json.int(article_count)),
      #("pageCount", json.int(list.length(pages))),
      #("pagination", pagination_json(pages, pagination)),
      #("pages", json.array(pages, page_json)),
      #(
        "source",
        json.object([
          #("provider", json.string("Alpaca Market Data")),
          #("upstreamNewsProvider", json.string("Benzinga")),
          #("kind", json.string("credentialed_vendor_news_metadata")),
          #(
            "reference",
            json.string("https://data.alpaca.markets/v1beta1/news"),
          ),
          #(
            "documentation",
            json.string("https://docs.alpaca.markets/us/reference/news-3"),
          ),
          #(
            "retrievedAtUnixMs",
            retrieved_at
              |> time.unix_milliseconds
              |> int.to_string
              |> json.string,
          ),
          #("authentication", json.string("alpaca_api_credentials")),
          #(
            "receiptState",
            json.string(
              "sha256_page_content_bound_not_provider_signature_or_origin_authentication",
            ),
          ),
        ]),
      ),
      #(
        "rights",
        json.object([
          #("use", json.string("personal_noncommercial_local_analysis")),
          #(
            "redistribution",
            json.string("requires_express_prior_written_consent"),
          ),
          #(
            "terms",
            json.string(
              "https://files.alpaca.markets/disclosures/alpaca_terms_and_conditions.pdf",
            ),
          ),
          #("articleBodiesReturned", json.bool(False)),
          #("articleSummariesReturned", json.bool(False)),
          #("imageUrlsReturned", json.bool(False)),
        ]),
      ),
      #(
        "scope",
        json.object([
          #("eventKind", json.string("vendor_news_article_metadata")),
          #(
            "createdAtMeaning",
            json.string("provider_article_creation_timestamp"),
          ),
          #(
            "updatedAtMeaning",
            json.string("provider_article_update_timestamp"),
          ),
          #("timestampZone", json.string("source_rfc3339_utc_z")),
          #("timestampLexemes", json.string("preserved_exactly")),
          #(
            "symbolAssociation",
            json.string(
              "provider_association_not_issuer_listing_or_venue_proof",
            ),
          ),
          #("correctionLineage", json.null()),
          #(
            "updatedAtCorrectionMeaning",
            json.string("update_signal_not_correction_or_revision_lineage"),
          ),
          #("deduplication", json.bool(False)),
          #("clustering", json.bool(False)),
          #("sentiment", json.null()),
          #("impact", json.null()),
          #("catalystClassification", json.null()),
          #("eventVerification", json.null()),
          #("absenceClaim", json.bool(False)),
          #(
            "historicalCoverageClaim",
            json.string("provider_states_since_2015"),
          ),
        ]),
      ),
      #(
        "limitations",
        json.array(
          [
            "Alpaca currently attributes this feed to Benzinga; it is vendor news, not an issuer, exchange, or regulator publication surface.",
            "A provider symbol association does not prove issuer, listing, MIC, asset class, or venue identity.",
            "created_at and updated_at are provider article timestamps; updated_at is not correction or revision lineage.",
            "The reference documents inclusive start/end and sorting by updated_at but does not explicitly name the interval filter axis.",
            "A headline is not a filing notice, scheduled event, observed event, verified fact, or model-inferred catalyst.",
            "Rows and repeated IDs are preserved without deduplication, clustering, sentiment, impact, or recommendation.",
            "Empty results and exhausted pagination do not prove that no relevant news or event exists.",
          ],
          json.string,
        ),
      ),
      #("decisionOwner", json.string("llm")),
      #("pluginDecisionFields", json.array([], json.string)),
    ]),
  ))
}

pub fn error_message(value: Error) -> String {
  case value {
    WrongTrack(received) ->
      "finance_news supports exact track us, received " <> received
    WrongVenue(received) ->
      "finance_news venue must be XNYS or XNAS, received " <> received
    InvalidQuery(error) -> query_error_message(error)
    NoSourcePages -> "finance_news requires at least one source page"
    InvalidPageSequence -> "finance_news source page sequence was invalid"
    TooManyArticles(maximum, received) ->
      "finance_news received "
      <> int.to_string(received)
      <> " articles, exceeding maximumArticles "
      <> int.to_string(maximum)
    InvalidPagination -> "finance_news pagination evidence was inconsistent"
    SourceMismatch(id, source) ->
      "finance_news article "
      <> int.to_string(id)
      <> " had unexpected source "
      <> source
    SymbolAssociationMismatch(id) ->
      "finance_news article "
      <> int.to_string(id)
      <> " did not retain the exact queried symbol association"
    InvalidArticleTime(id) ->
      "finance_news article "
      <> int.to_string(id)
      <> " had updated_at before created_at"
    OutOfOrderPages(id) ->
      "finance_news updated_at order regressed at article " <> int.to_string(id)
  }
}

fn validate_page_sequence(
  pages: List(SourcePage),
  expected: Int,
) -> Result(Nil, Error) {
  case pages {
    [] if expected == 1 -> Error(NoSourcePages)
    [] -> Ok(Nil)
    [page, ..rest] ->
      case
        page.sequence == expected,
        page.response_byte_length >= 0,
        valid_request_id(page.request_id)
      {
        True, True, True -> validate_page_sequence(rest, expected + 1)
        _, _, _ -> Error(InvalidPageSequence)
      }
  }
}

fn validate_articles(
  pages: List(SourcePage),
  query: news.Query,
  previous: Option(Instant),
) -> Result(Nil, Error) {
  case pages {
    [] -> Ok(Nil)
    [page, ..rest] -> {
      use next_previous <- result.try(validate_article_list(
        page.news.articles,
        query,
        previous,
      ))
      validate_articles(rest, query, next_previous)
    }
  }
}

fn validate_article_list(
  articles: List(news.Article),
  query: news.Query,
  previous: Option(Instant),
) -> Result(Option(Instant), Error) {
  case articles {
    [] -> Ok(previous)
    [article, ..rest] ->
      case article.source {
        "benzinga" ->
          case list.contains(article.symbols, query.symbol) {
            False -> Error(SymbolAssociationMismatch(article.id))
            True -> {
              let updated_ms = time.unix_milliseconds(article.updated_instant)
              case
                updated_ms < time.unix_milliseconds(article.created_instant)
              {
                True -> Error(InvalidArticleTime(article.id))
                False ->
                  case previous {
                    Some(previous) ->
                      case updated_ms < time.unix_milliseconds(previous) {
                        True -> Error(OutOfOrderPages(article.id))
                        False ->
                          validate_article_list(
                            rest,
                            query,
                            Some(article.updated_instant),
                          )
                      }
                    None ->
                      validate_article_list(
                        rest,
                        query,
                        Some(article.updated_instant),
                      )
                  }
              }
            }
          }
        source -> Error(SourceMismatch(article.id, source))
      }
  }
}

fn validate_pagination(
  pages: List(SourcePage),
  pagination: Pagination,
  article_count: Int,
  query: news.Query,
) -> Result(Nil, Error) {
  let assert Some(last) = last_page(pages)
  case
    pagination,
    last.news.next_page_token,
    list.length(pages) == query.maximum_pages,
    article_count == query.maximum_articles
  {
    Complete, None, _, _ -> Ok(Nil)
    TruncatedByPageBudget(maximum), Some(_), True, _
      if maximum == query.maximum_pages
    -> Ok(Nil)
    TruncatedByArticleBudget(maximum), Some(_), _, True
      if maximum == query.maximum_articles
    -> Ok(Nil)
    _, _, _, _ -> Error(InvalidPagination)
  }
}

fn page_json(page: SourcePage) -> json.Json {
  json.object([
    #("sequence", json.int(page.sequence)),
    #("requestId", option_json(page.request_id)),
    #("responseByteLength", json.int(page.response_byte_length)),
    #(
      "contentSha256",
      page.content_sha256 |> identity.sha256_value |> json.string,
    ),
    #(
      "contentDigestMeaning",
      json.string(
        "page_content_binding_not_provider_signature_or_origin_authentication",
      ),
    ),
    #("articleCount", json.int(list.length(page.news.articles))),
    #("articles", json.array(page.news.articles, article_json)),
    #("nextPageToken", option_json(page.news.next_page_token)),
  ])
}

fn article_json(article: news.Article) -> json.Json {
  json.object([
    #("providerArticleId", json.int(article.id)),
    #("headline", json.string(article.headline)),
    #("author", json.string(article.author)),
    #("createdAt", json.string(article.created_at)),
    #("updatedAt", json.string(article.updated_at)),
    #("url", json.string(article.url)),
    #("symbols", json.array(article.symbols, json.string)),
    #("source", json.string(article.source)),
    #("summaryAvailableAtProvider", json.bool(article.summary_present)),
    #("contentAvailableInResponse", json.bool(article.content_present)),
    #("imageCountAtProvider", json.int(article.image_count)),
    #("summaryReturned", json.bool(False)),
    #("contentReturned", json.bool(False)),
    #("imageUrlsReturned", json.bool(False)),
    #("eventType", json.null()),
    #("sentiment", json.null()),
    #("impact", json.null()),
  ])
}

fn pagination_json(
  pages: List(SourcePage),
  pagination: Pagination,
) -> json.Json {
  let assert Some(last) = last_page(pages)
  let budget = case pagination {
    Complete -> json.null()
    TruncatedByPageBudget(value) | TruncatedByArticleBudget(value) ->
      json.int(value)
  }
  json.object([
    #("state", json.string(pagination_name(pagination))),
    #("budget", budget),
    #("nextPageToken", option_json(last.news.next_page_token)),
  ])
}

fn pagination_name(value: Pagination) -> String {
  case value {
    Complete -> "complete"
    TruncatedByPageBudget(_) -> "truncated_by_page_budget"
    TruncatedByArticleBudget(_) -> "truncated_by_article_budget"
  }
}

fn last_page(pages: List(SourcePage)) -> Option(SourcePage) {
  case pages {
    [] -> None
    [page] -> Some(page)
    [_, ..rest] -> last_page(rest)
  }
}

fn valid_request_id(value: Option(String)) -> Bool {
  case value {
    None -> True
    Some(value) ->
      value != ""
      && string.trim(value) == value
      && string.length(value) <= 1024
      && !string.contains(value, "\r")
      && !string.contains(value, "\n")
  }
}

fn option_json(value: Option(String)) -> json.Json {
  case value {
    Some(value) -> json.string(value)
    None -> json.null()
  }
}

fn venue_name(value: Venue) -> String {
  case value {
    Xnys -> "XNYS"
    Xnas -> "XNAS"
  }
}

fn query_error_message(value: news.QueryError) -> String {
  case value {
    news.InvalidSymbol ->
      "finance_news symbol must be exact uppercase Alpaca syntax"
    news.InvalidStartTimestamp ->
      "finance_news startAt must be a canonical RFC3339 UTC timestamp ending Z"
    news.InvalidEndTimestamp ->
      "finance_news endAt must be a canonical RFC3339 UTC timestamp ending Z"
    news.InvalidRange -> "finance_news startAt must not follow endAt"
    news.RangeTooLarge -> "finance_news UTC interval must not exceed 31 days"
    news.InvalidPageSize -> "finance_news pageSize must be between 1 and 50"
    news.InvalidMaximumPages ->
      "finance_news maximumPages must be between 1 and 10"
    news.InvalidMaximumArticles ->
      "finance_news maximumArticles must be between 1 and 500"
  }
}
