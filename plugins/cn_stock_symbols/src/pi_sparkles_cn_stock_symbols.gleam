import finance_core/time
import finance_http/response as http_response
import finance_http/transport
import finance_provenance/hash
import finance_tushare
import finance_tushare/request
import finance_tushare/runtime
import finance_tushare/stock_basic
import gleam/dynamic/decode
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/option.{type Option, None, Some}
import gleam/string
import pi
import pi/raw
import pi/schema
import pi/tool
import pi_sparkles_cn_stock_symbols/domain
import pi_sparkles_cn_stock_symbols/effect/environment

type Provider {
  Ready(finance_tushare.Access, runtime.Runtime)
  Unavailable(String)
}

pub type SearchInput {
  SearchInput(plan: domain.SearchPlan)
}

pub type AliasInput {
  AliasInput(plan: domain.AliasPlan)
}

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  let provider = provider()
  tool.register(
    api,
    "cn_stock_symbol_search",
    "CN stock symbol search",
    "Search current or historical-status mainland listing candidates by exact code plus venue or by name; preserve ambiguity and vendor identity evidence",
    "No code prefix, name match, or vendor venue field is silently upgraded to exchange-authenticated identity",
    tool.parameters(search_schema(), search_decoder()),
    tool.Parallel,
    fn(id, input, signal, _updates, _ctx) {
      run_search(
        provider,
        input.plan,
        id,
        transport.from_abort_signal(raw.dynamic(signal)),
      )
    },
  )
  tool.register(
    api,
    "cn_stock_alias_history",
    "CN stock historical names",
    "Fetch exact historical name intervals for one already resolved mainland listing while retaining missing dates and change reasons",
    "No historical name is silently substituted for the current listing identity",
    tool.parameters(alias_schema(), alias_decoder()),
    tool.Parallel,
    fn(id, input, signal, _updates, _ctx) {
      run_aliases(
        provider,
        input.plan,
        id,
        transport.from_abort_signal(raw.dynamic(signal)),
      )
    },
  )
  promise.resolve(Nil)
}

fn run_search(provider, plan, id, cancellation) {
  case provider {
    Unavailable(reason) -> tool.reject(reason)
    Ready(access, provider_runtime) ->
      case request.stock_basic(access, domain.search_query(plan)) {
        Error(_) -> tool.reject("Tushare stock-basic request was invalid")
        Ok(request_value) -> {
          use outcome <- promise.await(runtime.send(
            provider_runtime,
            id,
            request_value,
            cancellation,
          ))
          case successful_body(outcome) {
            Error(message) -> tool.reject(message)
            Ok(#(response, body)) ->
              case
                stock_basic.decode(body, for: domain.search_query(plan)),
                metadata(body)
              {
                Ok(values), Ok(#(retrieved_at, digest)) -> {
                  let output =
                    domain.assemble_search(
                      plan,
                      values,
                      retrieved_at,
                      http_response.byte_length(response),
                      digest,
                    )
                  tool.text_result(
                    domain.summary(output),
                    domain.details(output),
                  )
                  |> promise.resolve
                }
                Error(_), _ ->
                  tool.reject(
                    "Tushare returned invalid or mismatched stock-basic rows",
                  )
                _, Error(message) -> tool.reject(message)
              }
          }
        }
      }
  }
}

fn run_aliases(provider, plan, id, cancellation) {
  case provider {
    Unavailable(reason) -> tool.reject(reason)
    Ready(access, provider_runtime) ->
      case request.namechange(access, domain.alias_query(plan)) {
        Error(_) -> tool.reject("Tushare name-history request was invalid")
        Ok(request_value) -> {
          use outcome <- promise.await(runtime.send(
            provider_runtime,
            id,
            request_value,
            cancellation,
          ))
          case successful_body(outcome) {
            Error(message) -> tool.reject(message)
            Ok(#(response, body)) ->
              case metadata(body) {
                Error(message) -> tool.reject(message)
                Ok(#(retrieved_at, digest)) ->
                  case
                    domain.decode_aliases(
                      plan,
                      body,
                      retrieved_at,
                      http_response.byte_length(response),
                      digest,
                    )
                  {
                    Ok(output) ->
                      tool.text_result(
                        domain.summary(output),
                        domain.details(output),
                      )
                      |> promise.resolve
                    Error(error) -> tool.reject(domain.error_message(error))
                  }
              }
          }
        }
      }
  }
}

fn successful_body(outcome) {
  case outcome {
    Error(error) ->
      Error("Tushare symbol request failed safely: " <> string.inspect(error))
    Ok(response) ->
      case
        http_response.status(response) >= 200
        && http_response.status(response) < 300
      {
        True -> Ok(#(response, http_response.body(response)))
        False ->
          Error(
            "Tushare symbol request returned HTTP "
            <> int.to_string(http_response.status(response)),
          )
      }
  }
}

fn metadata(body: String) {
  case time.instant(environment.now_milliseconds()), hash.text(body) {
    Ok(retrieved_at), Ok(digest) -> Ok(#(retrieved_at, digest))
    Error(_), _ -> Error("retrieval clock was invalid")
    _, Error(_) -> Error("response content could not be hashed")
  }
}

fn provider() -> Provider {
  case finance_tushare.access(environment.token()) {
    Error(_) ->
      Unavailable(
        "TUSHARE_TOKEN is required for symbol and historical-name discovery; provider permission/points apply",
      )
    Ok(access) ->
      case runtime.new(access) {
        Ok(value) -> Ready(access, value)
        Error(_) -> Unavailable("Tushare bounded runtime could not initialize")
      }
  }
}

fn search_schema() -> schema.Schema {
  schema.object([
    schema.Required("track", schema.string_enum(["cn"])),
    schema.Required("queryKind", schema.string_enum(["code", "name"])),
    schema.Required(
      "query",
      schema.string() |> schema.with_string_length(1, 100),
    ),
    schema.Optional(
      "venue",
      schema.nullable(schema.string_enum(["sse", "szse", "bse"])),
    ),
    schema.Optional(
      "listStatus",
      schema.string_enum(["listed", "delisted", "paused"]),
    ),
    schema.Optional(
      "maximumCandidates",
      schema.integer() |> schema.with_number_range(1.0, 100.0),
    ),
  ])
}

fn search_decoder() -> decode.Decoder(SearchInput) {
  use track <- decode.field("track", decode.string)
  use kind <- decode.field("queryKind", decode.string)
  use query <- decode.field("query", decode.string)
  use venue <- optional_string("venue")
  use status <- decode.optional_field("listStatus", "listed", decode.string)
  use limit <- decode.optional_field("maximumCandidates", 20, decode.int)
  let assert Ok(fallback) =
    domain.search_plan("cn", "code", "600000", Some("sse"), "listed", 20)
  case domain.search_plan(track, kind, query, venue, status, limit) {
    Ok(value) -> decode.success(SearchInput(value))
    Error(error) ->
      decode.failure(SearchInput(fallback), domain.error_message(error))
  }
}

fn alias_schema() -> schema.Schema {
  schema.object([
    schema.Required("track", schema.string_enum(["cn"])),
    schema.Required("venue", schema.string_enum(["sse", "szse", "bse"])),
    schema.Required("code", schema.string() |> schema.with_string_length(6, 6)),
    schema.Required(
      "identityEvidenceId",
      schema.string() |> schema.with_string_length(1, 256),
    ),
    schema.Optional(
      "maximumRows",
      schema.integer() |> schema.with_number_range(1.0, 1000.0),
    ),
  ])
}

fn alias_decoder() -> decode.Decoder(AliasInput) {
  use track <- decode.field("track", decode.string)
  use venue <- decode.field("venue", decode.string)
  use code <- decode.field("code", decode.string)
  use evidence <- decode.field("identityEvidenceId", decode.string)
  use limit <- decode.optional_field("maximumRows", 500, decode.int)
  let assert Ok(fallback) =
    domain.alias_plan("cn", "sse", "600000", "placeholder", 500)
  case domain.alias_plan(track, venue, code, evidence, limit) {
    Ok(value) -> decode.success(AliasInput(value))
    Error(error) ->
      decode.failure(AliasInput(fallback), domain.error_message(error))
  }
}

fn optional_string(
  name: String,
  next: fn(Option(String)) -> decode.Decoder(value),
) -> decode.Decoder(value) {
  decode.optional_field(name, None, decode.optional(decode.string), next)
}
