import finance_core/time
import finance_http/response as http_response
import finance_http/transport
import finance_market_alpaca
import finance_market_alpaca/news
import finance_market_alpaca/request as provider_request
import finance_market_alpaca/runtime
import finance_provenance/hash
import gleam/dynamic/decode
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import pi
import pi/raw
import pi/schema
import pi/tool
import pi_sparkles_finance_news/domain
import pi_sparkles_finance_news/effect/environment

type Provider {
  Ready(access: finance_market_alpaca.Access, runtime: runtime.Runtime)
  InvalidConfiguration(reason: String)
}

type FetchOutcome {
  FetchOutcome(pages: List(domain.SourcePage), pagination: domain.Pagination)
}

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  let provider = provider()
  tool.register(
    api,
    "finance_news",
    "US vendor news metadata",
    "Fetch bounded Alpaca/Benzinga news article metadata for one exact caller-declared US listing scope and UTC interval; preserve provider IDs, headlines, authors, created/updated timestamps, URLs, symbol associations, pagination, and content-bound page receipts",
    "Inspect exact vendor news metadata without returning article bodies or summaries and without deduplication, sentiment, impact, event verification, catalyst classification, venue proof, absence claims, or recommendations",
    tool.parameters(input_schema(), input_decoder()),
    tool.Parallel,
    fn(id, plan, signal, _updates, _ctx) {
      case provider {
        InvalidConfiguration(reason) -> tool.reject(reason)
        Ready(access, provider_runtime) -> {
          use fetched <- promise.await(fetch_pages(
            provider_runtime,
            access,
            plan,
            id,
            transport.from_abort_signal(raw.dynamic(signal)),
            None,
            [],
            [],
            0,
          ))
          case fetched {
            Error(message) -> tool.reject(message)
            Ok(outcome) ->
              case time.instant(environment.now_milliseconds()) {
                Error(_) ->
                  tool.reject("Alpaca news retrieval clock was invalid")
                Ok(retrieved_at) ->
                  case
                    domain.run(
                      plan,
                      outcome.pages,
                      outcome.pagination,
                      retrieved_at,
                    )
                  {
                    Error(error) -> tool.reject(domain.error_message(error))
                    Ok(output) ->
                      tool.text_result(output.summary, output.details)
                      |> promise.resolve
                  }
              }
          }
        }
      }
    },
  )
  promise.resolve(Nil)
}

fn provider() -> Provider {
  case
    finance_market_alpaca.access(
      environment.key_id(),
      environment.secret_key(),
      environment.product(),
      environment.contact(),
    )
  {
    Error(_) ->
      InvalidConfiguration(
        "Alpaca news requires ALPACA_API_KEY_ID, ALPACA_API_SECRET_KEY, and ALPACA_USER_AGENT_CONTACT; ALPACA_USER_AGENT_PRODUCT is optional",
      )
    Ok(access) ->
      case runtime.new() {
        Ok(provider_runtime) -> Ready(access, provider_runtime)
        Error(_) ->
          InvalidConfiguration(
            "Alpaca bounded news runtime could not initialize safely",
          )
      }
  }
}

fn fetch_pages(
  provider_runtime: runtime.Runtime,
  access: finance_market_alpaca.Access,
  plan: domain.Plan,
  id: String,
  cancellation: transport.Cancellation,
  page_token: Option(String),
  seen_tokens: List(String),
  pages: List(domain.SourcePage),
  articles_fetched: Int,
) -> Promise(Result(FetchOutcome, String)) {
  let remaining = plan.query.maximum_articles - articles_fetched
  let page_limit = int.min(plan.query.page_size, remaining)
  case page_limit <= 0 {
    True ->
      promise.resolve(
        Ok(FetchOutcome(
          pages,
          domain.TruncatedByArticleBudget(plan.query.maximum_articles),
        )),
      )
    False ->
      case provider_request.news(access, plan.query, page_limit, page_token) {
        Error(_) -> promise.resolve(Error("Alpaca news request was invalid"))
        Ok(request_value) -> {
          let sequence = list.length(pages) + 1
          use sent <- promise.await(runtime.send(
            provider_runtime,
            id: id <> ":page:" <> int.to_string(sequence),
            request: request_value,
            cancellation: cancellation,
          ))
          case checked_response(sent) {
            Error(message) -> promise.resolve(Error(message))
            Ok(response_value) -> {
              let body = http_response.body(response_value)
              case
                news.decode_page(body, plan.query, page_limit),
                hash.text(body)
              {
                Error(_), _ ->
                  promise.resolve(Error(
                    "Alpaca returned invalid, mismatched, or over-budget news metadata",
                  ))
                _, Error(_) ->
                  promise.resolve(Error(
                    "Alpaca news response could not be content-bound",
                  ))
                Ok(page), Ok(content_sha256) -> {
                  let next_articles_fetched =
                    articles_fetched + list.length(page.articles)
                  let next_pages =
                    list.append(pages, [
                      domain.SourcePage(
                        sequence,
                        http_response.first_header(
                          response_value,
                          name: "x-request-id",
                        ),
                        http_response.byte_length(response_value),
                        content_sha256,
                        page,
                      ),
                    ])
                  case page.next_page_token {
                    None ->
                      promise.resolve(
                        Ok(FetchOutcome(next_pages, domain.Complete)),
                      )
                    Some(next_token) ->
                      case
                        list.contains(seen_tokens, next_token)
                        || page_token == Some(next_token),
                        next_articles_fetched >= plan.query.maximum_articles,
                        sequence >= plan.query.maximum_pages
                      {
                        True, _, _ ->
                          promise.resolve(Error(
                            "Alpaca repeated a news pagination token; pagination stopped safely",
                          ))
                        _, True, _ ->
                          promise.resolve(
                            Ok(FetchOutcome(
                              next_pages,
                              domain.TruncatedByArticleBudget(
                                plan.query.maximum_articles,
                              ),
                            )),
                          )
                        _, _, True ->
                          promise.resolve(
                            Ok(FetchOutcome(
                              next_pages,
                              domain.TruncatedByPageBudget(
                                plan.query.maximum_pages,
                              ),
                            )),
                          )
                        False, False, False ->
                          fetch_pages(
                            provider_runtime,
                            access,
                            plan,
                            id,
                            cancellation,
                            Some(next_token),
                            [next_token, ..seen_tokens],
                            next_pages,
                            next_articles_fetched,
                          )
                      }
                  }
                }
              }
            }
          }
        }
      }
  }
}

fn checked_response(
  outcome: Result(http_response.Response, runtime.SendError),
) -> Result(http_response.Response, String) {
  case outcome {
    Error(error) ->
      Error("Alpaca news request failed safely: " <> string.inspect(error))
    Ok(value) -> {
      let status = http_response.status(value)
      case status >= 200 && status < 300 {
        True -> Ok(value)
        False if status == 401 || status == 403 ->
          Error(
            "Alpaca rejected the news credentials or entitlement (HTTP "
            <> int.to_string(status)
            <> ")",
          )
        False ->
          Error("Alpaca news request returned HTTP " <> int.to_string(status))
      }
    }
  }
}

fn input_schema() -> schema.Schema {
  schema.object([
    schema.Required("track", schema.string_enum(["us"])),
    schema.Required(
      "venue",
      schema.string_enum(["XNYS", "XNAS"])
        |> schema.described(
          "Exact caller-declared US venue scope; Alpaca news does not verify it",
        ),
    ),
    schema.Required(
      "symbol",
      schema.string()
        |> schema.with_string_length(1, 20)
        |> schema.described(
          "Exact uppercase Alpaca stock symbol; provider association is not listing proof",
        ),
    ),
    schema.Required("startAt", timestamp_schema("Inclusive UTC lower bound")),
    schema.Required("endAt", timestamp_schema("Inclusive UTC upper bound")),
    schema.Required(
      "pageSize",
      schema.integer()
        |> schema.with_number_range(1.0, 50.0)
        |> schema.described(
          "Maximum article records requested per provider page",
        ),
    ),
    schema.Required(
      "maximumPages",
      schema.integer()
        |> schema.with_number_range(1.0, 10.0)
        |> schema.described("Hard provider page budget"),
    ),
    schema.Required(
      "maximumArticles",
      schema.integer()
        |> schema.with_number_range(1.0, 500.0)
        |> schema.described("Hard total article-record budget"),
    ),
  ])
}

fn timestamp_schema(description: String) -> schema.Schema {
  schema.string()
  |> schema.with_string_length(20, 40)
  |> schema.described(description <> "; RFC3339 UTC timestamp ending Z")
}

fn input_decoder() -> decode.Decoder(domain.Plan) {
  use track <- decode.field("track", decode.string)
  use venue <- decode.field("venue", decode.string)
  use symbol <- decode.field("symbol", decode.string)
  use start_at <- decode.field("startAt", decode.string)
  use end_at <- decode.field("endAt", decode.string)
  use page_size <- decode.field("pageSize", decode.int)
  use maximum_pages <- decode.field("maximumPages", decode.int)
  use maximum_articles <- decode.field("maximumArticles", decode.int)
  case
    domain.plan(
      track,
      venue,
      symbol,
      start_at,
      end_at,
      page_size,
      maximum_pages,
      maximum_articles,
    )
  {
    Ok(plan) -> decode.success(plan)
    Error(error) -> {
      let assert Ok(fallback) =
        domain.plan(
          "us",
          "XNAS",
          "AAPL",
          "2026-07-01T00:00:00Z",
          "2026-07-02T00:00:00Z",
          10,
          1,
          10,
        )
      decode.failure(fallback, domain.error_message(error))
    }
  }
}
