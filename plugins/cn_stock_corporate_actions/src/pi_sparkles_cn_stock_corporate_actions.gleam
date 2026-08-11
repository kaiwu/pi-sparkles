import finance_core/time
import finance_http/response as http_response
import finance_http/transport
import finance_provenance/hash
import finance_tushare
import finance_tushare/request
import finance_tushare/runtime
import gleam/dynamic/decode
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/string
import pi
import pi/raw
import pi/schema
import pi/tool
import pi_sparkles_cn_stock_corporate_actions/domain
import pi_sparkles_cn_stock_corporate_actions/effect/environment

type Provider {
  Ready(finance_tushare.Access, runtime.Runtime)
  Unavailable(String)
}

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  let provider = provider()
  tool.register(
    api,
    "cn_stock_corporate_actions",
    "CN stock corporate actions",
    "Fetch exact structured mainland cash/stock dividend, bonus-share, and capitalization-distribution rows for one resolved A-share; unsupported action classes fail closed",
    "Preserve every process/revision row and every separate date without deriving price-adjustment factors",
    tool.parameters(input_schema(), input_decoder()),
    tool.Parallel,
    fn(id, plan, signal, _updates, _ctx) {
      case provider {
        Unavailable(reason) -> tool.reject(reason)
        Ready(access, provider_runtime) ->
          case request.dividend(access, domain.provider_query(plan)) {
            Error(_) -> tool.reject("Tushare dividend request was invalid")
            Ok(request_value) -> {
              use outcome <- promise.await(runtime.send(
                provider_runtime,
                id,
                request_value,
                transport.from_abort_signal(raw.dynamic(signal)),
              ))
              case outcome {
                Error(error) ->
                  tool.reject(
                    "Tushare dividend request failed safely: "
                    <> string.inspect(error),
                  )
                Ok(response) -> {
                  let status = http_response.status(response)
                  let body = http_response.body(response)
                  case
                    status >= 200 && status < 300,
                    time.instant(environment.now_milliseconds()),
                    hash.text(body)
                  {
                    True, Ok(retrieved_at), Ok(digest) ->
                      domain.decode_and_assemble(
                        plan,
                        body,
                        retrieved_at,
                        http_response.byte_length(response),
                        digest,
                      )
                      |> output_result
                    False, _, _ ->
                      tool.reject(
                        "Tushare dividend request returned HTTP "
                        <> int.to_string(status),
                      )
                    _, Error(_), _ -> tool.reject("retrieval clock was invalid")
                    _, _, Error(_) ->
                      tool.reject("response content could not be hashed")
                  }
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
  case finance_tushare.access(environment.token()) {
    Error(_) ->
      Unavailable(
        "TUSHARE_TOKEN is required for the selected dividend adapter; provider permission/points apply",
      )
    Ok(access) ->
      case runtime.new(access) {
        Ok(value) -> Ready(access, value)
        Error(_) -> Unavailable("Tushare bounded runtime could not initialize")
      }
  }
}

fn output_result(value) {
  case value {
    Ok(output) ->
      tool.text_result(domain.summary(output), domain.details(output))
      |> promise.resolve
    Error(error) -> tool.reject(domain.error_message(error))
  }
}

fn input_schema() -> schema.Schema {
  schema.object([
    schema.Required("track", schema.string_enum(["cn"])),
    schema.Required("venue", schema.string_enum(["sse", "szse", "bse"])),
    schema.Required("code", schema.string() |> schema.with_string_length(6, 6)),
    schema.Required("shareClass", schema.string_enum(["a_share"])),
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

fn input_decoder() -> decode.Decoder(domain.Plan) {
  use track <- decode.field("track", decode.string)
  use venue <- decode.field("venue", decode.string)
  use code <- decode.field("code", decode.string)
  use share_class <- decode.field("shareClass", decode.string)
  use evidence <- decode.field("identityEvidenceId", decode.string)
  use limit <- decode.optional_field("maximumRows", 500, decode.int)
  let assert Ok(placeholder) =
    domain.plan("cn", "sse", "600000", "a_share", "placeholder", 500)
  case domain.plan(track, venue, code, share_class, evidence, limit) {
    Ok(value) -> decode.success(value)
    Error(error) -> decode.failure(placeholder, domain.error_message(error))
  }
}
