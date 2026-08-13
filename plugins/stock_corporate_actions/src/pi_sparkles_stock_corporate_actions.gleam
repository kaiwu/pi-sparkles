import finance_core/time
import finance_http/response as http_response
import finance_http/transport
import finance_market_alpaca
import finance_market_alpaca/corporate_actions
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
import pi_sparkles_stock_corporate_actions/domain
import pi_sparkles_stock_corporate_actions/effect/environment

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
    "corporate_actions",
    "US corporate-action source facts",
    "Fetch bounded Alpaca US cash dividends, stock dividends, forward splits, reverse splits, and name changes for an exact symbol/CUSIP and process-date range; preserve exact numeric lexemes, nullable source fields, identity transitions, duplicates, pagination, and page evidence",
    "Inspect provider source facts without venue authentication, price adjustment, publication-time inference, completeness claims, or economic-impact conclusions",
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
                  tool.reject(
                    "Alpaca corporate-actions retrieval clock was invalid",
                  )
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
        "Alpaca corporate actions requires AGENT_CONTACT, ALPACA_API_KEY_ID, and ALPACA_API_SECRET_KEY",
      )
    Ok(access) ->
      case runtime.new() {
        Ok(provider_runtime) -> Ready(access, provider_runtime)
        Error(_) ->
          InvalidConfiguration(
            "Alpaca bounded corporate-actions runtime could not initialize safely",
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
  actions_fetched: Int,
) -> Promise(Result(FetchOutcome, String)) {
  let remaining = plan.query.maximum_actions - actions_fetched
  let page_limit = int.min(plan.query.page_size, remaining)
  case page_limit <= 0 {
    True ->
      promise.resolve(
        Ok(FetchOutcome(
          pages,
          domain.TruncatedByActionBudget(plan.query.maximum_actions),
        )),
      )
    False ->
      case
        provider_request.corporate_actions(
          access,
          plan.query,
          page_limit,
          page_token,
        )
      {
        Error(_) ->
          promise.resolve(Error("Alpaca corporate-actions request was invalid"))
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
                corporate_actions.decode_page(body, plan.query, page_limit),
                hash.text(body)
              {
                Error(_), _ ->
                  promise.resolve(Error(
                    "Alpaca returned invalid, mismatched, or over-budget corporate actions",
                  ))
                _, Error(_) ->
                  promise.resolve(Error(
                    "Alpaca corporate-actions response could not be content-bound",
                  ))
                Ok(page), Ok(content_sha256) -> {
                  let page_action_count =
                    list.length(page.cash_dividends)
                    + list.length(page.stock_dividends)
                    + list.length(page.forward_splits)
                    + list.length(page.reverse_splits)
                    + list.length(page.name_changes)
                  let next_actions_fetched = actions_fetched + page_action_count
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
                        next_actions_fetched >= plan.query.maximum_actions,
                        sequence >= plan.query.maximum_pages
                      {
                        True, _, _ ->
                          promise.resolve(Error(
                            "Alpaca repeated a corporate-actions pagination token; pagination stopped safely",
                          ))
                        _, True, _ ->
                          promise.resolve(
                            Ok(FetchOutcome(
                              next_pages,
                              domain.TruncatedByActionBudget(
                                plan.query.maximum_actions,
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
                            next_actions_fetched,
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
      Error(
        "Alpaca corporate-actions request failed safely: "
        <> string.inspect(error),
      )
    Ok(value) -> {
      let status = http_response.status(value)
      case status >= 200 && status < 300 {
        True -> Ok(value)
        False if status == 401 || status == 403 ->
          Error(
            "Alpaca rejected the corporate-actions credentials or entitlement (HTTP "
            <> int.to_string(status)
            <> ")",
          )
        False ->
          Error(
            "Alpaca corporate-actions request returned HTTP "
            <> int.to_string(status),
          )
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
          "Exact caller-declared US venue scope; Alpaca corporate-actions does not verify it",
        ),
    ),
    schema.Required(
      "symbol",
      schema.string()
        |> schema.with_string_length(1, 20)
        |> schema.described("Exact uppercase Alpaca symbol"),
    ),
    schema.Required(
      "cusip",
      schema.string()
        |> schema.with_string_length(9, 9)
        |> schema.described("Exact nine-character CUSIP"),
    ),
    schema.Required("startDate", date_schema()),
    schema.Required("endDate", date_schema()),
    schema.Required(
      "types",
      schema.array(
        schema.string_enum([
          "cash_dividend",
          "stock_dividend",
          "forward_split",
          "reverse_split",
          "name_change",
        ]),
      )
        |> schema.with_array_length(1, 5)
        |> schema.described(
          "Explicit unique source action types; duplicates are invalid",
        ),
    ),
    schema.Required(
      "dataQuality",
      schema.string_enum(["complete", "all"])
        |> schema.described("Exact Alpaca data_quality policy"),
    ),
    schema.Required(
      "pageSize",
      schema.integer()
        |> schema.with_number_range(1.0, 1000.0)
        |> schema.described("Maximum actions requested per provider page"),
    ),
    schema.Required(
      "maximumPages",
      schema.integer()
        |> schema.with_number_range(1.0, 10.0)
        |> schema.described("Hard provider page budget"),
    ),
    schema.Required(
      "maximumActions",
      schema.integer()
        |> schema.with_number_range(1.0, 5000.0)
        |> schema.described("Hard total source-action budget"),
    ),
  ])
}

fn date_schema() -> schema.Schema {
  schema.string()
  |> schema.with_string_length(10, 10)
  |> schema.described(
    "Canonical Gregorian YYYY-MM-DD bound on Alpaca process_date",
  )
}

fn input_decoder() -> decode.Decoder(domain.Plan) {
  use track <- decode.field("track", decode.string)
  use venue <- decode.field("venue", decode.string)
  use symbol <- decode.field("symbol", decode.string)
  use cusip <- decode.field("cusip", decode.string)
  use start_date <- decode.field("startDate", decode.string)
  use end_date <- decode.field("endDate", decode.string)
  use types <- decode.field("types", decode.list(of: decode.string))
  use data_quality <- decode.field("dataQuality", decode.string)
  use page_size <- decode.field("pageSize", decode.int)
  use maximum_pages <- decode.field("maximumPages", decode.int)
  use maximum_actions <- decode.field("maximumActions", decode.int)
  case
    domain.plan(
      track,
      venue,
      symbol,
      cusip,
      start_date,
      end_date,
      types,
      data_quality,
      page_size,
      maximum_pages,
      maximum_actions,
    )
  {
    Ok(plan) -> decode.success(plan)
    Error(error) -> {
      let assert Ok(fallback) =
        domain.plan(
          "us",
          "XNAS",
          "AAPL",
          "037833100",
          "2026-01-01",
          "2026-01-31",
          ["cash_dividend"],
          "complete",
          100,
          1,
          100,
        )
      decode.failure(fallback, domain.error_message(error))
    }
  }
}
