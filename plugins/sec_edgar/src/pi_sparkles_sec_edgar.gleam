import finance_http/pool
import finance_http/response as http_response
import finance_http/transport
import finance_sec
import finance_sec/request
import finance_sec/response.{type Filing, type Submissions}
import finance_sec/runtime
import finance_track
import finance_track/context as track_context
import finance_track/json as track_json
import gleam/dynamic/decode
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/json
import gleam/list
import gleam/option.{type Option, None}
import gleam/string
import pi
import pi/context
import pi/raw
import pi/schema
import pi/tool
import pi/ui
import pi_sparkles_sec_edgar/company_search
import pi_sparkles_sec_edgar/effect/environment
import pi_sparkles_sec_edgar/filing_selection

pub type CompanySearchInput {
  CompanySearchInput(plan: company_search.Plan)
}

pub type SubmissionsInput {
  SubmissionsInput(cik: finance_sec.Cik, plan: filing_selection.Plan)
}

type Provider {
  Ready(access: finance_sec.Access, runtime: runtime.Runtime)
  InvalidConfiguration(reason: String)
}

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  let provider = provider()

  pi.register_command(
    api,
    "sec-company",
    "Search SEC's company ticker association file without guessing a CIK",
    fn(args, ctx) {
      case provider, company_search.plan(args, 10) {
        InvalidConfiguration(reason), _ -> {
          notify(ctx, reason, ui.Error)
          promise.resolve(Nil)
        }
        _, Error(_) -> {
          notify(ctx, "Usage: /sec-company <ticker or company name>", ui.Error)
          promise.resolve(Nil)
        }
        Ready(access, provider_runtime), Ok(plan) -> {
          use outcome <- promise.await(fetch_company_matches(
            provider_runtime,
            access,
            plan,
            "command-sec-company",
            transport.new_cancellation(),
          ))
          case outcome {
            Error(message) -> notify(ctx, message, ui.Error)
            Ok(matches) -> notify(ctx, render_company_matches(matches), ui.Info)
          }
          promise.resolve(Nil)
        }
      }
    },
  )

  tool.register(
    api,
    "sec_company_search",
    "SEC company search",
    "Search the SEC-published ticker/CIK association file; return ranked candidates and never infer a CIK",
    "Find a US public-company CIK before retrieving EDGAR submissions",
    tool.parameters(company_search_schema(), company_search_decoder()),
    tool.Parallel,
    fn(id, input, signal, _updates, _ctx) {
      case provider {
        InvalidConfiguration(reason) -> tool.reject(reason)
        Ready(access, provider_runtime) -> {
          use outcome <- promise.await(fetch_company_matches(
            provider_runtime,
            access,
            input.plan,
            id,
            transport.from_abort_signal(raw.dynamic(signal)),
          ))
          case outcome {
            Error(message) -> tool.reject(message)
            Ok(matches) ->
              tool.text_result(
                render_company_matches(matches),
                company_matches_json(matches),
              )
              |> promise.resolve
          }
        }
      }
    },
  )

  tool.register(
    api,
    "sec_company_submissions",
    "SEC company submissions",
    "Retrieve a company's recent EDGAR submission metadata by validated CIK, optionally filtering by exact form type",
    "List recent 10-K, 10-Q, 8-K, or other filing metadata from SEC EDGAR",
    tool.parameters(submissions_schema(), submissions_decoder()),
    tool.Parallel,
    fn(id, input, signal, _updates, _ctx) {
      case provider {
        InvalidConfiguration(reason) -> tool.reject(reason)
        Ready(access, provider_runtime) -> {
          use outcome <- promise.await(fetch_submissions(
            provider_runtime,
            access,
            input.cik,
            id,
            transport.from_abort_signal(raw.dynamic(signal)),
          ))
          case outcome {
            Error(message) -> tool.reject(message)
            Ok(submissions) -> {
              let filings = filing_selection.select(submissions, input.plan)
              tool.text_result(
                render_filings(submissions, filings),
                submissions_json(submissions, filings),
              )
              |> promise.resolve
            }
          }
        }
      }
    },
  )

  promise.resolve(Nil)
}

fn provider() -> Provider {
  case finance_sec.access(environment.product(), environment.contact()) {
    Error(_) ->
      InvalidConfiguration(
        "SEC access requires AGENT_CONTACT (for example ops@example.com)",
      )
    Ok(access) ->
      case runtime.new(access) {
        Error(_) ->
          InvalidConfiguration("SEC runtime could not initialize safely")
        Ok(provider_runtime) -> Ready(access, provider_runtime)
      }
  }
}

fn fetch_company_matches(
  provider_runtime: runtime.Runtime,
  access: finance_sec.Access,
  plan: company_search.Plan,
  id: String,
  cancellation: transport.Cancellation,
) -> Promise(Result(List(company_search.Match), String)) {
  case request.company_tickers(access) {
    Error(_) -> promise.resolve(Error("SEC company request was invalid"))
    Ok(request_value) -> {
      use outcome <- promise.await(runtime.send(
        provider_runtime,
        id: id,
        request: request_value,
        cancellation: cancellation,
      ))
      case checked_body(outcome, "company ticker") {
        Error(message) -> promise.resolve(Error(message))
        Ok(body) ->
          case response.decode_companies(body) {
            Error(_) ->
              promise.resolve(Error(
                "SEC returned an invalid company ticker file",
              ))
            Ok(companies) ->
              promise.resolve(Ok(company_search.find(companies, plan)))
          }
      }
    }
  }
}

fn fetch_submissions(
  provider_runtime: runtime.Runtime,
  access: finance_sec.Access,
  cik: finance_sec.Cik,
  id: String,
  cancellation: transport.Cancellation,
) -> Promise(Result(Submissions, String)) {
  case request.submissions(access, cik) {
    Error(_) -> promise.resolve(Error("SEC submissions request was invalid"))
    Ok(request_value) -> {
      use outcome <- promise.await(runtime.send(
        provider_runtime,
        id: id,
        request: request_value,
        cancellation: cancellation,
      ))
      case checked_body(outcome, "submissions") {
        Error(message) -> promise.resolve(Error(message))
        Ok(body) ->
          case response.decode_submissions(body) {
            Error(_) ->
              promise.resolve(Error("SEC returned invalid submissions data"))
            Ok(submissions) -> promise.resolve(Ok(submissions))
          }
      }
    }
  }
}

fn checked_body(
  outcome: Result(http_response.Response, pool.PoolError),
  resource: String,
) -> Result(String, String) {
  case outcome {
    Error(error) ->
      Error(
        "SEC "
        <> resource
        <> " request failed safely: "
        <> string.inspect(error),
      )
    Ok(value) -> {
      let status = http_response.status(value)
      case status >= 200 && status < 300 {
        True -> Ok(http_response.body(value))
        False ->
          Error(
            "SEC "
            <> resource
            <> " request returned HTTP "
            <> int.to_string(status),
          )
      }
    }
  }
}

fn company_search_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "query",
      schema.string()
        |> schema.with_string_length(1, 200)
        |> schema.described("Ticker or company name"),
    ),
    schema.Optional(
      "limit",
      schema.integer()
        |> schema.with_number_range(1.0, 25.0)
        |> schema.described("Maximum candidates; defaults to 10"),
    ),
  ])
}

fn submissions_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "cik",
      schema.string()
        |> schema.with_string_length(1, 10)
        |> schema.described(
          "SEC Central Index Key, with or without leading zeroes",
        ),
    ),
    schema.Optional(
      "form",
      schema.string()
        |> schema.with_string_length(1, 20)
        |> schema.described("Exact SEC form type, for example 10-K or 8-K"),
    ),
    schema.Optional(
      "limit",
      schema.integer()
        |> schema.with_number_range(1.0, 50.0)
        |> schema.described("Maximum recent filings; defaults to 20"),
    ),
  ])
}

fn company_search_decoder() -> decode.Decoder(CompanySearchInput) {
  use query <- decode.field("query", decode.string)
  use limit <- decode.optional_field("limit", 10, decode.int)
  let assert Ok(placeholder) = company_search.plan("AAPL", 10)
  case company_search.plan(query, limit) {
    Error(_) ->
      decode.failure(
        CompanySearchInput(placeholder),
        "valid SEC company search",
      )
    Ok(plan) -> decode.success(CompanySearchInput(plan))
  }
}

fn submissions_decoder() -> decode.Decoder(SubmissionsInput) {
  use cik_value <- decode.field("cik", decode.string)
  use form <- optional_string_field("form")
  use limit <- decode.optional_field("limit", 20, decode.int)
  let assert Ok(placeholder_cik) = finance_sec.cik("0")
  let assert Ok(placeholder_plan) = filing_selection.plan(None, 20)
  case finance_sec.cik(cik_value), filing_selection.plan(form, limit) {
    Ok(cik), Ok(plan) -> decode.success(SubmissionsInput(cik, plan))
    _, _ ->
      decode.failure(
        SubmissionsInput(placeholder_cik, placeholder_plan),
        "valid SEC submissions selection",
      )
  }
}

fn optional_string_field(
  name: String,
  next: fn(Option(String)) -> decode.Decoder(value),
) -> decode.Decoder(value) {
  decode.optional_field(name, None, decode.optional(decode.string), next)
}

fn render_company_matches(matches: List(company_search.Match)) -> String {
  "US track | SEC EDGAR\n"
  <> case matches {
    [] -> "SEC company ticker file found no candidates; do not infer a CIK"
    matches ->
      "SEC company candidates ("
      <> int.to_string(list.length(matches))
      <> "):\n"
      <> {
        matches
        |> list.map(fn(value) {
          "- "
          <> value.company.ticker
          <> " | "
          <> value.company.title
          <> " | CIK "
          <> finance_sec.cik_value(value.company.cik)
          <> " | "
          <> company_search.reason_name(value.reason)
        })
        |> string.join("\n")
      }
  }
}

fn render_filings(value: Submissions, filings: List(Filing)) -> String {
  "US track | SEC EDGAR\n"
  <> case filings {
    [] -> value.name <> ": no recent filings matched the requested form"
    filings ->
      value.name
      <> " recent SEC filings ("
      <> int.to_string(list.length(filings))
      <> "):\n"
      <> {
        filings
        |> list.map(fn(filing) {
          "- "
          <> filing.form
          <> " filed "
          <> filing.filing_date
          <> " | report "
          <> empty_as_unknown(filing.report_date)
          <> " | accession "
          <> filing.accession
          <> " | document "
          <> empty_as_unknown(filing.primary_document)
        })
        |> string.join("\n")
      }
  }
}

fn company_matches_json(matches: List(company_search.Match)) -> json.Json {
  json.object(
    list.append(
      us_track_fields("us_sec_company_reference", [
        "ticker_association_not_guaranteed_current_or_complete",
      ]),
      [
        #("provider", json.string("SEC EDGAR")),
        #(
          "source",
          json.string("https://www.sec.gov/files/company_tickers.json"),
        ),
        #("access", json.string("read_only_public_data")),
        #("entitlement", json.string("sec_public_data_fair_access_terms_apply")),
        #("freshness", json.string("file_timestamp_not_supplied")),
        #("unit", json.string("not_applicable")),
        #(
          "warning",
          json.string(
            "SEC does not guarantee the ticker association file is accurate or current; use results as candidates",
          ),
        ),
        #("candidates", json.array(matches, company_match_json)),
      ],
    ),
  )
}

fn company_match_json(value: company_search.Match) -> json.Json {
  json.object([
    #("cik", json.string(finance_sec.cik_value(value.company.cik))),
    #("ticker", json.string(value.company.ticker)),
    #("title", json.string(value.company.title)),
    #("match", json.string(company_search.reason_name(value.reason))),
  ])
}

fn submissions_json(value: Submissions, filings: List(Filing)) -> json.Json {
  json.object(
    list.append(
      us_track_fields("us_sec_recent_submissions", ["recent_filings_only"]),
      [
        #("provider", json.string("SEC EDGAR")),
        #(
          "source",
          json.string(
            "https://data.sec.gov/submissions/CIK"
            <> finance_sec.cik_value(value.cik)
            <> ".json",
          ),
        ),
        #("access", json.string("read_only_public_data")),
        #("entitlement", json.string("sec_public_data_fair_access_terms_apply")),
        #("freshness", json.string("sec_submissions_updated_in_real_time")),
        #("unit", json.string("not_applicable")),
        #("cik", json.string(finance_sec.cik_value(value.cik))),
        #("company", json.string(value.name)),
        #("tickers", json.array(value.tickers, json.string)),
        #("exchanges", json.array(value.exchanges, json.string)),
        #("filings", json.array(filings, filing_json)),
      ],
    ),
  )
}

fn us_track_fields(
  market_scope: String,
  limitations: List(String),
) -> List(#(String, json.Json)) {
  let assert Ok(value) =
    track_context.new(
      track: finance_track.Us,
      market_scope: market_scope,
      venue_mic: None,
      board: None,
      timezone: None,
      source_language: "en-US",
      providers: ["SEC EDGAR"],
      entitlement: "sec_public_data_fair_access_terms_apply",
      limitations: limitations,
    )
  track_json.result_fields(value)
}

fn filing_json(value: Filing) -> json.Json {
  json.object([
    #("accession", json.string(value.accession)),
    #("filingDate", json.string(value.filing_date)),
    #("reportDate", json.string(value.report_date)),
    #("form", json.string(value.form)),
    #("primaryDocument", json.string(value.primary_document)),
  ])
}

fn empty_as_unknown(value: String) -> String {
  case value {
    "" -> "unknown"
    value -> value
  }
}

fn notify(
  ctx: pi.CommandContext,
  message: String,
  level: ui.Notification,
) -> Nil {
  case context.has_ui(ctx) {
    True -> ui.notify(context.ui(ctx), message, level)
    False -> Nil
  }
}
