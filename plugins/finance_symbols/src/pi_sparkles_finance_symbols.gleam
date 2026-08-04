import finance_core/identifier
import finance_http/pool
import finance_http/response as http_response
import finance_http/transport
import finance_openfigi
import finance_openfigi/mapping
import finance_openfigi/response
import finance_openfigi/runtime
import finance_openfigi/search
import gleam/dynamic/decode
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import pi
import pi/context
import pi/raw
import pi/schema
import pi/tool
import pi/ui
import pi_sparkles_finance_symbols/effect/environment
import pi_sparkles_finance_symbols/symbols

pub type SearchInput {
  SearchInput(query: search.Query)
}

pub type ResolveInput {
  ResolveInput(job: mapping.Job)
}

type Provider {
  Ready(access: finance_openfigi.Access, runtime: runtime.Runtime)
  InvalidConfiguration(reason: String)
}

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  let provider = provider()

  pi.register_command(
    api,
    "symbol",
    "Resolve a ticker with OpenFIGI v3; ambiguity is never guessed",
    fn(args, ctx) {
      case provider, ticker_job(args) {
        InvalidConfiguration(reason), _ -> {
          notify(ctx, reason, ui.Error)
          promise.resolve(Nil)
        }
        _, Error(error) -> {
          notify(
            ctx,
            "Invalid symbol request: " <> string.inspect(error),
            ui.Error,
          )
          promise.resolve(Nil)
        }
        Ready(access, provider_runtime), Ok(job) ->
          case mapping.request(access, [job]) {
            Error(error) -> {
              notify(
                ctx,
                "Invalid symbol request: " <> string.inspect(error),
                ui.Error,
              )
              promise.resolve(Nil)
            }
            Ok(request) -> {
              use outcome <- promise.await(runtime.send(
                provider_runtime,
                id: "command-symbol",
                request: request,
                cancellation: transport.new_cancellation(),
              ))
              case decode_mapping_response(outcome, access) {
                Ok(result) ->
                  notify(
                    ctx,
                    render_resolution(symbols.resolve(result.candidates)),
                    ui.Info,
                  )
                Error(message) -> notify(ctx, message, ui.Error)
              }
              promise.resolve(Nil)
            }
          }
      }
    },
  )

  tool.register(
    api,
    "security_search",
    "Security search",
    "Search OpenFIGI v3 for instrument candidates; results remain candidates and are not silently selected",
    "Search for securities by name, ticker, or description",
    tool.parameters(search_schema(), search_decoder()),
    tool.Sequential,
    fn(id, input, signal, _updates, _ctx) {
      case provider {
        InvalidConfiguration(reason) -> tool.reject(reason)
        Ready(access, provider_runtime) ->
          case search.request(access, input.query) {
            Error(error) ->
              tool.reject("Invalid OpenFIGI search: " <> string.inspect(error))
            Ok(request) -> {
              use outcome <- promise.await(runtime.send(
                provider_runtime,
                id: id,
                request: request,
                cancellation: transport.from_abort_signal(raw.dynamic(signal)),
              ))
              provider_tool_result(outcome, response.decode_search, access)
            }
          }
      }
    },
  )

  tool.register(
    api,
    "security_resolve",
    "Security resolve",
    "Map an identifier through OpenFIGI v3 and return no-match, unique, or ambiguous without guessing",
    "Resolve a security identifier before requesting market or filing data",
    tool.parameters(resolve_schema(), resolve_decoder()),
    tool.Sequential,
    fn(id, input, signal, _updates, _ctx) {
      resolve_tool(provider, input, id, signal)
    },
  )

  tool.register(
    api,
    "security_identifiers",
    "Security identifiers",
    "Look up the FIGI, composite FIGI, and share-class FIGI associated with an identifier",
    "Inspect identifiers for an already-known security",
    tool.parameters(resolve_schema(), resolve_decoder()),
    tool.Sequential,
    fn(id, input, signal, _updates, _ctx) {
      resolve_tool(provider, input, id, signal)
    },
  )

  promise.resolve(Nil)
}

fn provider() -> Provider {
  case
    environment.openfigi_api_key()
    |> finance_openfigi.optional_access
  {
    Error(_) ->
      InvalidConfiguration(
        "OPENFIGI_API_KEY is invalid; remove it for anonymous access or provide a non-empty key without whitespace",
      )
    Ok(access) ->
      case runtime.new(access) {
        Error(_) ->
          InvalidConfiguration("OpenFIGI runtime could not initialize safely")
        Ok(provider_runtime) -> Ready(access, provider_runtime)
      }
  }
}

fn ticker_job(value: String) -> Result(mapping.Job, mapping.JobError) {
  mapping.job(mapping.Ticker, value, None)
}

fn resolve_tool(
  provider: Provider,
  input: ResolveInput,
  id: String,
  signal: pi.AbortSignal,
) -> Promise(tool.ToolResult) {
  case provider {
    InvalidConfiguration(reason) -> tool.reject(reason)
    Ready(access, provider_runtime) ->
      case mapping.request(access, [input.job]) {
        Error(error) ->
          tool.reject("Invalid OpenFIGI mapping: " <> string.inspect(error))
        Ok(request) -> {
          use outcome <- promise.await(runtime.send(
            provider_runtime,
            id: id,
            request: request,
            cancellation: transport.from_abort_signal(raw.dynamic(signal)),
          ))
          case decode_mapping_response(outcome, access) {
            Error(message) -> tool.reject(message)
            Ok(provider_result) -> {
              let resolution = symbols.resolve(provider_result.candidates)
              tool.text_result(
                render_resolution(resolution),
                resolution_json(resolution, provider_result, access),
              )
              |> promise.resolve
            }
          }
        }
      }
  }
}

fn provider_tool_result(
  outcome: Result(http_response.Response, pool.PoolError),
  decoder: fn(String) -> Result(response.ResultSet, json.DecodeError),
  access: finance_openfigi.Access,
) -> Promise(tool.ToolResult) {
  case outcome {
    Error(error) ->
      tool.reject("OpenFIGI request failed safely: " <> string.inspect(error))
    Ok(value) ->
      case decoder(http_response.body(value)) {
        Error(_) -> tool.reject("OpenFIGI returned an invalid v3 response")
        Ok(result) ->
          case result.error {
            Some(message) ->
              tool.reject(
                "OpenFIGI error: " <> finance_openfigi.redact(access, message),
              )
            None ->
              tool.text_result(
                render_search(result),
                provider_json(result, access),
              )
              |> promise.resolve
          }
      }
  }
}

fn decode_mapping_response(
  outcome: Result(http_response.Response, pool.PoolError),
  access: finance_openfigi.Access,
) -> Result(response.ResultSet, String) {
  case outcome {
    Error(error) ->
      Error("OpenFIGI request failed safely: " <> string.inspect(error))
    Ok(value) ->
      case response.decode_mapping(http_response.body(value)) {
        Error(_) -> Error("OpenFIGI returned an invalid v3 mapping response")
        Ok(results) -> {
          let result = response.first_mapping_result(results)
          case result.error {
            Some(message) ->
              Error(
                "OpenFIGI error: " <> finance_openfigi.redact(access, message),
              )
            None -> Ok(result)
          }
        }
      }
  }
}

fn search_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "query",
      schema.string()
        |> schema.with_string_length(1, 200)
        |> schema.described("Name, ticker, or security description"),
    ),
    schema.Optional(
      "micCode",
      schema.string()
        |> schema.with_string_length(4, 4)
        |> schema.described("Optional four-character ISO 10383 MIC"),
    ),
    schema.Optional(
      "cursor",
      schema.string()
        |> schema.with_string_length(1, 4096)
        |> schema.described(
          "OpenFIGI next cursor from a previous search result",
        ),
    ),
  ])
}

fn resolve_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "idType",
      schema.string_enum([
        "TICKER",
        "ID_BB_GLOBAL",
        "COMPOSITE_ID_BB_GLOBAL",
        "ID_ISIN",
        "ID_CUSIP",
        "ID_SEDOL",
      ]),
    ),
    schema.Required(
      "idValue",
      schema.string() |> schema.with_string_length(1, 200),
    ),
    schema.Optional(
      "micCode",
      schema.string()
        |> schema.with_string_length(4, 4)
        |> schema.described("Optional four-character ISO 10383 MIC"),
    ),
  ])
}

fn search_decoder() -> decode.Decoder(SearchInput) {
  use value <- decode.field("query", decode.string)
  use mic_code <- optional_string_field("micCode")
  use cursor <- optional_string_field("cursor")
  let assert Ok(placeholder) = search.query("IBM", None)
  case search.query(value, mic_code) {
    Error(_) ->
      decode.failure(SearchInput(placeholder), "valid OpenFIGI search")
    Ok(query) ->
      case cursor {
        None -> decode.success(SearchInput(query))
        Some(cursor) ->
          case search.with_cursor(query, cursor) {
            Error(_) ->
              decode.failure(SearchInput(placeholder), "valid OpenFIGI cursor")
            Ok(query) -> decode.success(SearchInput(query))
          }
      }
  }
}

fn resolve_decoder() -> decode.Decoder(ResolveInput) {
  use id_type_name <- decode.field("idType", decode.string)
  use id_value <- decode.field("idValue", decode.string)
  use mic_code <- optional_string_field("micCode")
  let assert Ok(placeholder) = mapping.job(mapping.Ticker, "IBM", None)
  case mapping.id_type(id_type_name) {
    Error(_) ->
      decode.failure(
        ResolveInput(placeholder),
        "supported OpenFIGI identifier type",
      )
    Ok(id_type) ->
      case mapping.job(id_type, id_value, mic_code) {
        Error(_) ->
          decode.failure(
            ResolveInput(placeholder),
            "valid OpenFIGI mapping job",
          )
        Ok(job) -> decode.success(ResolveInput(job))
      }
  }
}

fn optional_string_field(
  name: String,
  next: fn(Option(String)) -> decode.Decoder(value),
) -> decode.Decoder(value) {
  decode.optional_field(name, None, decode.optional(decode.string), next)
}

fn render_search(result: response.ResultSet) -> String {
  case result.candidates {
    [] -> "OpenFIGI found no candidates" <> warning_suffix(result.warning)
    candidates ->
      "OpenFIGI candidates ("
      <> int.to_string(list.length(candidates))
      <> "):\n"
      <> {
        candidates
        |> list.map(fn(value) { "- " <> symbols.candidate_label(value) })
        |> string.join("\n")
      }
  }
}

fn render_resolution(
  value: identifier.Resolution(response.Candidate),
) -> String {
  case value {
    identifier.NoMatch -> "No security matched; do not infer an identifier"
    identifier.Unique(candidate) ->
      "Unique security: " <> symbols.candidate_label(candidate)
    identifier.Ambiguous(first, second, rest) ->
      "Ambiguous security ("
      <> int.to_string(2 + list.length(rest))
      <> "); refine by MIC or identifier:\n"
      <> {
        [first, second, ..rest]
        |> list.map(fn(value) { "- " <> symbols.candidate_label(value) })
        |> string.join("\n")
      }
  }
}

fn provider_json(
  value: response.ResultSet,
  access: finance_openfigi.Access,
) -> json.Json {
  json.object([
    #("provider", json.string("OpenFIGI v3")),
    #("access", json.string(finance_openfigi.access_name(access))),
    #("source", json.string("https://api.openfigi.com/v3/filter")),
    #(
      "entitlement",
      json.string("figi_identifiers_public_domain_metadata_terms_apply"),
    ),
    #("freshness", json.string("reference_data_as_of_not_supplied")),
    #("unit", json.string("not_applicable")),
    #("candidates", json.array(value.candidates, candidate_json)),
    #("warning", optional_json(value.warning)),
    #("next", optional_json(value.next)),
    #("total", optional_int_json(value.total)),
  ])
}

fn resolution_json(
  value: identifier.Resolution(response.Candidate),
  provider_result: response.ResultSet,
  access: finance_openfigi.Access,
) -> json.Json {
  json.object([
    #("resolution", json.string(symbols.resolution_name(value))),
    #(
      "candidates",
      json.array(identifier.resolution_candidates(value), candidate_json),
    ),
    #("provider", json.string("OpenFIGI v3")),
    #("access", json.string(finance_openfigi.access_name(access))),
    #("source", json.string("https://api.openfigi.com/v3/mapping")),
    #(
      "entitlement",
      json.string("figi_identifiers_public_domain_metadata_terms_apply"),
    ),
    #("freshness", json.string("reference_data_as_of_not_supplied")),
    #("unit", json.string("not_applicable")),
    #("warning", optional_json(provider_result.warning)),
  ])
}

fn candidate_json(value: response.Candidate) -> json.Json {
  json.object([
    #("figi", json.string(value.figi)),
    #("name", optional_json(value.name)),
    #("ticker", optional_json(value.ticker)),
    #("exchangeCode", optional_json(value.exchange_code)),
    #("securityType", optional_json(value.security_type)),
    #("marketSector", optional_json(value.market_sector)),
    #("compositeFigi", optional_json(value.composite_figi)),
    #("shareClassFigi", optional_json(value.share_class_figi)),
  ])
}

fn optional_json(value: Option(String)) -> json.Json {
  case value {
    Some(value) -> json.string(value)
    None -> json.null()
  }
}

fn optional_int_json(value: Option(Int)) -> json.Json {
  case value {
    Some(value) -> json.int(value)
    None -> json.null()
  }
}

fn warning_suffix(value: Option(String)) -> String {
  case value {
    Some(value) -> ": " <> value
    None -> ""
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
