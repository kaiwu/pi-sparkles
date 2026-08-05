import finance_core/identifier
import finance_core/time
import finance_hkex
import finance_hkex/discovery_runtime
import finance_hkex/request
import finance_hkex/security_search.{type Security}
import finance_hkex/title_search
import finance_http/pool
import finance_http/response as http_response
import finance_http/transport
import finance_track
import finance_track/context as track_context
import finance_track/json as track_json
import gleam/dynamic/decode
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import pi
import pi/raw
import pi/schema
import pi/tool
import pi_sparkles_hk_disclosures/effect/environment
import pi_sparkles_hk_disclosures/selection

pub type SecurityInput {
  SecurityInput(code: String)
}

pub type DisclosureInput {
  DisclosureInput(code: String, stock_id: Option(Int), limit: Int)
}

type Provider {
  Ready(access: finance_hkex.Access, runtime: discovery_runtime.Runtime)
  InvalidConfiguration(reason: String)
}

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  let provider = provider()

  tool.register(
    api,
    "hk_security_search",
    "HK security search",
    "Look up an exact five-digit current-security code through HKEXnews and preserve every exact internal stock identity candidate",
    "Resolve an HKEXnews stock ID before searching Hong Kong disclosures",
    tool.parameters(security_schema(), security_decoder()),
    tool.Parallel,
    fn(id, input, signal, _updates, _ctx) {
      case provider {
        InvalidConfiguration(reason) -> tool.reject(reason)
        Ready(access, provider_runtime) -> {
          use outcome <- promise.await(fetch_security_candidates(
            provider_runtime,
            access,
            input.code,
            id,
            transport.from_abort_signal(raw.dynamic(signal)),
          ))
          case outcome {
            Error(message) -> tool.reject(message)
            Ok(values) ->
              tool.text_result(
                render_security(input.code, values),
                security_json(input.code, values),
              )
              |> promise.resolve
          }
        }
      }
    },
  )

  tool.register(
    api,
    "hk_disclosure_search",
    "HK disclosure search",
    "Search HKEXnews listed-company titles after resolving the exact current-security stock ID; return bounded initial-page metadata and exact PDF identities",
    "Find Hong Kong issuer announcements and reports without guessing an HKEXnews stock ID",
    tool.parameters(disclosure_schema(), disclosure_decoder()),
    tool.Parallel,
    fn(id, input, signal, _updates, _ctx) {
      case provider {
        InvalidConfiguration(reason) -> tool.reject(reason)
        Ready(access, provider_runtime) -> {
          let cancellation = transport.from_abort_signal(raw.dynamic(signal))
          use outcome <- promise.await(fetch_disclosures(
            provider_runtime,
            access,
            input,
            id,
            cancellation,
          ))
          case outcome {
            Error(message) -> tool.reject(message)
            Ok(#(security, page)) ->
              tool.text_result(
                render_disclosures(security, page),
                disclosure_json(security, page),
              )
              |> promise.resolve
          }
        }
      }
    },
  )

  promise.resolve(Nil)
}

fn provider() -> Provider {
  case finance_hkex.access(environment.product(), environment.contact()) {
    Error(_) ->
      InvalidConfiguration(
        "HKEXnews access requires HKEX_USER_AGENT_CONTACT (for example ops@example.com); HKEX_USER_AGENT_PRODUCT is optional",
      )
    Ok(access) ->
      case discovery_runtime.new(access) {
        Error(_) ->
          InvalidConfiguration(
            "HKEXnews discovery runtime could not initialize safely",
          )
        Ok(provider_runtime) -> Ready(access, provider_runtime)
      }
  }
}

fn fetch_security_candidates(
  provider_runtime: discovery_runtime.Runtime,
  access: finance_hkex.Access,
  code: String,
  id: String,
  cancellation: transport.Cancellation,
) -> Promise(Result(List(Security), String)) {
  case security_search.query(code) {
    Error(_) -> promise.resolve(Error("HKEXnews security query was invalid"))
    Ok(query) ->
      case request.security_prefix(access, query) {
        Error(_) ->
          promise.resolve(Error("HKEXnews security request was invalid"))
        Ok(request_value) -> {
          use outcome <- promise.await(discovery_runtime.send(
            provider_runtime,
            id: id,
            request: request_value,
            cancellation: cancellation,
          ))
          case checked_body(outcome, "security lookup") {
            Error(message) -> promise.resolve(Error(message))
            Ok(body) ->
              case security_search.decode(body) {
                Error(_) ->
                  promise.resolve(Error(
                    "HKEXnews returned invalid security JSONP",
                  ))
                Ok(values) ->
                  values
                  |> security_search.resolve_code(code: code)
                  |> selection.candidates
                  |> Ok
                  |> promise.resolve
              }
          }
        }
      }
  }
}

fn fetch_disclosures(
  provider_runtime: discovery_runtime.Runtime,
  access: finance_hkex.Access,
  input: DisclosureInput,
  id: String,
  cancellation: transport.Cancellation,
) -> Promise(Result(#(Security, title_search.Page), String)) {
  use candidates <- promise.await(fetch_security_candidates(
    provider_runtime,
    access,
    input.code,
    id <> "-identity",
    cancellation,
  ))
  case candidates {
    Error(message) -> promise.resolve(Error(message))
    Ok(values) -> {
      let resolution = identifier.resolve(values)
      case selection.select(resolution, input.stock_id) {
        Error(selection.NoCandidate) ->
          promise.resolve(Error(
            "HKEXnews found no exact current-security candidate for "
            <> input.code,
          ))
        Error(selection.AmbiguousCandidates(count)) ->
          promise.resolve(Error(
            "HKEXnews returned "
            <> int.to_string(count)
            <> " exact candidates; supply stockId",
          ))
        Error(selection.StockIdMismatch) ->
          promise.resolve(Error(
            "stockId does not match an exact HKEXnews code candidate",
          ))
        Ok(security) ->
          case
            title_search.plan(
              security_search.stock_id(security),
              security_search.code(security),
              input.limit,
            )
          {
            Error(_) ->
              promise.resolve(Error("HKEXnews title-search plan was invalid"))
            Ok(plan) ->
              case request.titles(access, plan) {
                Error(_) ->
                  promise.resolve(Error(
                    "HKEXnews title-search request was invalid",
                  ))
                Ok(request_value) -> {
                  use outcome <- promise.await(discovery_runtime.send(
                    provider_runtime,
                    id: id <> "-titles",
                    request: request_value,
                    cancellation: cancellation,
                  ))
                  case checked_body(outcome, "title search") {
                    Error(message) -> promise.resolve(Error(message))
                    Ok(body) ->
                      case title_search.decode(body, plan) {
                        Error(_) ->
                          promise.resolve(Error(
                            "HKEXnews returned an invalid title-search page",
                          ))
                        Ok(page) -> promise.resolve(Ok(#(security, page)))
                      }
                  }
                }
              }
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
        "HKEXnews "
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
            "HKEXnews "
            <> resource
            <> " request returned HTTP "
            <> int.to_string(status),
          )
      }
    }
  }
}

fn security_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "code",
      schema.string()
        |> schema.with_string_length(5, 5)
        |> schema.described("Exact five-digit HKEX security code"),
    ),
  ])
}

fn disclosure_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "code",
      schema.string()
        |> schema.with_string_length(5, 5)
        |> schema.described("Exact five-digit current HKEX security code"),
    ),
    schema.Optional(
      "stockId",
      schema.integer()
        |> schema.with_number_range(1.0, 999_999_999.0)
        |> schema.described(
          "Exact HKEXnews internal stock ID if candidates are ambiguous",
        ),
    ),
    schema.Optional(
      "limit",
      schema.integer()
        |> schema.with_number_range(1.0, 100.0)
        |> schema.described("Maximum initial-page rows; defaults to 20"),
    ),
  ])
}

fn security_decoder() -> decode.Decoder(SecurityInput) {
  use code <- decode.field("code", decode.string)
  case valid_code(code) {
    True -> decode.success(SecurityInput(code))
    False -> decode.failure(SecurityInput("00700"), "valid five-digit HK code")
  }
}

fn disclosure_decoder() -> decode.Decoder(DisclosureInput) {
  use code <- decode.field("code", decode.string)
  use stock_id <- optional_int_field("stockId")
  use limit <- decode.optional_field("limit", 20, decode.int)
  case
    valid_code(code),
    valid_optional_stock_id(stock_id),
    limit >= 1 && limit <= 100
  {
    True, True, True -> decode.success(DisclosureInput(code, stock_id, limit))
    _, _, _ ->
      decode.failure(
        DisclosureInput("00700", None, 20),
        "valid HKEXnews disclosure query",
      )
  }
}

fn optional_int_field(
  name: String,
  next: fn(Option(Int)) -> decode.Decoder(value),
) -> decode.Decoder(value) {
  decode.optional_field(name, None, decode.optional(decode.int), next)
}

fn valid_code(value: String) -> Bool {
  string.length(value) == 5
  && value
  |> string.to_graphemes
  |> list.all(fn(character) { string.contains("0123456789", character) })
}

fn render_security(code: String, values: List(Security)) -> String {
  "HK track | HKEXnews current securities\n"
  <> case values {
    [] -> "No exact HKEXnews candidate for " <> code
    candidates ->
      "Exact-code candidates ("
      <> int.to_string(list.length(candidates))
      <> "):\n"
      <> candidates
      |> list.map(fn(value) {
        "- "
        <> security_search.code(value)
        <> " | "
        <> security_search.name(value)
        <> " | stockId "
        <> int.to_string(security_search.stock_id(value))
      })
      |> string.join("\n")
  }
}

fn render_disclosures(security: Security, page: title_search.Page) -> String {
  "HK track | HKEXnews listed-company titles\n"
  <> security_search.code(security)
  <> " "
  <> security_search.name(security)
  <> " | initial-page records "
  <> int.to_string(list.length(title_search.documents(page)))
  <> " / site total "
  <> int.to_string(title_search.total_records(page))
}

fn security_json(code: String, values: List(Security)) -> json.Json {
  json.object(
    list.append(
      hk_track_fields("hk_hkexnews_security_reference", [
        "current_securities_only",
        "stock_id_is_hkexnews_internal_identity",
        "source_update_timestamp_not_supplied",
        "redistribution_not_approved",
      ]),
      [
        #("provider", json.string("HKEXnews")),
        #("source", json.string("https://www1.hkexnews.hk/search/prefix.do")),
        #("access", json.string("read_only_public_local_analysis")),
        #("queryCode", json.string(code)),
        #("resolution", json.string(resolution_name(values))),
        #("candidates", json.array(values, security_candidate_json)),
      ],
    ),
  )
}

fn security_candidate_json(value: Security) -> json.Json {
  json.object([
    #("stockId", json.int(security_search.stock_id(value))),
    #("code", json.string(security_search.code(value))),
    #("name", json.string(security_search.name(value))),
    #("venueMic", json.string("XHKG")),
  ])
}

fn disclosure_json(security: Security, page: title_search.Page) -> json.Json {
  json.object(
    list.append(
      hk_track_fields("hk_hkexnews_disclosure_search", [
        "initial_rendered_page_only_maximum_100_rows",
        "historical_results_can_be_truncated",
        "hkex_does_not_verify_issuer_materials",
        "response_retrieval_time_not_yet_captured",
        "redistribution_not_approved",
      ]),
      [
        #("provider", json.string("HKEXnews")),
        #(
          "source",
          json.string("https://www1.hkexnews.hk/search/titlesearch.xhtml"),
        ),
        #("access", json.string("read_only_public_local_analysis")),
        #("stockId", json.int(security_search.stock_id(security))),
        #("code", json.string(title_search.requested_code(page))),
        #("name", json.string(title_search.requested_name(page))),
        #("totalRecords", json.int(title_search.total_records(page))),
        #("truncated", json.bool(title_search.truncated(page))),
        #("documents", json.array(title_search.documents(page), document_json)),
      ],
    ),
  )
}

fn document_json(value: title_search.Document) -> json.Json {
  json.object([
    #("releaseTime", json.string(title_search.release_time(value))),
    #("releaseTimezone", json.string("Asia/Hong_Kong")),
    #("codes", json.array(title_search.codes(value), json.string)),
    #("names", json.array(title_search.names(value), json.string)),
    #("headlineHtml", json.string(title_search.headline_html(value))),
    #("title", json.string(title_search.title(value))),
    #(
      "documentUrl",
      json.string(finance_hkex.canonical_url(title_search.reference(value))),
    ),
    #("displayedFileSize", json.string(title_search.file_size(value))),
  ])
}

fn hk_track_fields(
  market_scope: String,
  limitations: List(String),
) -> List(#(String, json.Json)) {
  let assert Ok(zone) = time.timezone("Asia/Hong_Kong")
  let assert Ok(value) =
    track_context.new(
      track: finance_track.Hk,
      market_scope: market_scope,
      venue_mic: Some(finance_hkex_mic()),
      board: None,
      timezone: Some(zone),
      source_language: "en-HK",
      providers: ["HKEXnews"],
      entitlement: "read_only_public_local_analysis_no_redistribution",
      limitations: limitations,
    )
  track_json.result_fields(value)
}

fn finance_hkex_mic() -> identifier.Mic {
  let assert Ok(value) = identifier.mic("XHKG")
  value
}

fn valid_optional_stock_id(value: Option(Int)) -> Bool {
  case value {
    None -> True
    Some(value) -> value > 0
  }
}

fn resolution_name(values: List(Security)) -> String {
  case values {
    [] -> "no_match"
    [_] -> "unique"
    [_, _, ..] -> "ambiguous"
  }
}
