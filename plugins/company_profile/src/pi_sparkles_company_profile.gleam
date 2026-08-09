import finance_core/time
import finance_http/client
import finance_http/pool
import finance_http/response as http_response
import finance_http/transport
import finance_provenance/hash
import finance_provenance/identity.{type Sha256}
import finance_twelve_data
import finance_twelve_data/request as provider_request
import finance_twelve_data/response as provider_response
import finance_twelve_data/runtime
import gleam/dynamic/decode
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/string
import pi
import pi/raw
import pi/schema
import pi/tool
import pi_sparkles_company_profile/domain
import pi_sparkles_company_profile/effect/environment

type Provider {
  Ready(access: finance_twelve_data.Access, runtime: runtime.Runtime)
  InvalidConfiguration(reason: String)
}

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  let provider = provider()
  tool.register(
    api,
    "company_profile",
    "Exact US company profile snapshot",
    "Retrieve one exact Twelve Data US listing profile and MIC-matched share snapshot without fallback, identity relabelling, quality scoring, or investment judgment",
    "Requires the caller's TWELVE_DATA_API_KEY with access to the profile and statistics endpoints",
    tool.parameters(input_schema(), input_decoder()),
    tool.Parallel,
    fn(id, input, signal, _updates, _ctx) {
      case provider {
        InvalidConfiguration(reason) -> tool.reject(reason)
        Ready(access, provider_runtime) -> {
          use capture <- promise.await(fetch(
            provider_runtime,
            access,
            input,
            id,
            transport.from_abort_signal(raw.dynamic(signal)),
          ))
          case capture {
            Error(message) -> tool.reject(message)
            Ok(value) ->
              case domain.assemble(input, value) {
                Error(error) -> tool.reject(domain.error_message(error))
                Ok(output) ->
                  tool.text_result(output.summary, output.details)
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
  case finance_twelve_data.access(environment.api_key()) {
    Error(_) ->
      InvalidConfiguration(
        "company_profile requires the caller's TWELVE_DATA_API_KEY with Twelve Data profile and statistics access",
      )
    Ok(access) ->
      case runtime.new() {
        Error(_) ->
          InvalidConfiguration(
            "Twelve Data company profile runtime could not initialize safely",
          )
        Ok(provider_runtime) -> Ready(access, provider_runtime)
      }
  }
}

fn fetch(
  provider_runtime: runtime.Runtime,
  access: finance_twelve_data.Access,
  input: domain.Input,
  id: String,
  cancellation: transport.Cancellation,
) -> Promise(Result(domain.Capture, String)) {
  case provider_request.profile(access, input.symbol, input.mic) {
    Error(_) ->
      promise.resolve(Error("Twelve Data profile request was invalid"))
    Ok(request_value) -> {
      use sent <- promise.await(runtime.send(
        provider_runtime,
        id: id <> ":profile",
        request: request_value,
        cancellation: cancellation,
      ))
      case checked_response(sent, "profile") {
        Error(message) -> promise.resolve(Error(message))
        Ok(response) -> {
          let body = http_response.body(response)
          case provider_response.decode_profile(body), hash.text(body) {
            Error(_), _ ->
              promise.resolve(Error(
                "Twelve Data returned an invalid profile response",
              ))
            _, Error(_) ->
              promise.resolve(Error(
                "Twelve Data profile response could not be content-bound",
              ))
            Ok(profile), Ok(content_hash) ->
              case profile.symbol == input.symbol && profile.mic == input.mic {
                False ->
                  promise.resolve(Error(
                    "Twelve Data profile did not match the exact requested symbol and MIC",
                  ))
                True ->
                  fetch_statistics(
                    provider_runtime,
                    access,
                    input,
                    id,
                    cancellation,
                    profile,
                    receipt(
                      provider_request.profile_path,
                      response,
                      content_hash,
                    ),
                  )
              }
          }
        }
      }
    }
  }
}

fn fetch_statistics(
  provider_runtime: runtime.Runtime,
  access: finance_twelve_data.Access,
  input: domain.Input,
  id: String,
  cancellation: transport.Cancellation,
  profile: provider_response.Profile,
  profile_receipt: domain.Receipt,
) -> Promise(Result(domain.Capture, String)) {
  case provider_request.statistics(access, input.symbol, input.mic) {
    Error(_) ->
      promise.resolve(Error("Twelve Data statistics request was invalid"))
    Ok(request_value) -> {
      use sent <- promise.await(runtime.send(
        provider_runtime,
        id: id <> ":statistics",
        request: request_value,
        cancellation: cancellation,
      ))
      case checked_response(sent, "statistics") {
        Error(message) -> promise.resolve(Error(message))
        Ok(response) -> {
          let body = http_response.body(response)
          case provider_response.decode_statistics(body), hash.text(body) {
            Error(_), _ ->
              promise.resolve(Error(
                "Twelve Data returned an invalid statistics response",
              ))
            _, Error(_) ->
              promise.resolve(Error(
                "Twelve Data statistics response could not be content-bound",
              ))
            Ok(statistics), Ok(content_hash) ->
              case time.instant(environment.now_milliseconds()) {
                Error(_) ->
                  promise.resolve(Error(
                    "company_profile retrieval clock was invalid",
                  ))
                Ok(retrieved_at) ->
                  promise.resolve(
                    Ok(domain.Capture(
                      profile,
                      profile_receipt,
                      statistics,
                      receipt(
                        provider_request.statistics_path,
                        response,
                        content_hash,
                      ),
                      retrieved_at,
                    )),
                  )
              }
          }
        }
      }
    }
  }
}

fn checked_response(
  outcome: Result(http_response.Response, runtime.SendError),
  label: String,
) -> Result(http_response.Response, String) {
  case outcome {
    Error(runtime.RequestFailed(pool.RequestFailed(client.RetryStopped(
      _,
      _,
      client.StatusFailure(http_response.SafeSummary(status, _, _)),
    )))) -> provider_status_error(label, status)
    Error(error) ->
      Error(
        "Twelve Data "
        <> label
        <> " request failed safely: "
        <> string.inspect(error),
      )
    Ok(value) -> {
      let status = http_response.status(value)
      case status >= 200 && status < 300 {
        True -> Ok(value)
        False -> provider_status_error(label, status)
      }
    }
  }
}

fn provider_status_error(label: String, status: Int) -> Result(value, String) {
  case status {
    400 | 404 ->
      Error(
        "Twelve Data rejected or could not resolve the exact listing (HTTP "
        <> int.to_string(status)
        <> ")",
      )
    401 -> Error("Twelve Data rejected TWELVE_DATA_API_KEY (HTTP 401)")
    403 ->
      Error(
        "Twelve Data subscription does not permit the requested endpoint (HTTP 403)",
      )
    429 ->
      Error(
        "Twelve Data API credit limit was reached (HTTP 429); no automatic retry was made",
      )
    _ ->
      Error(
        "Twelve Data "
        <> label
        <> " request returned HTTP "
        <> int.to_string(status),
      )
  }
}

fn receipt(
  endpoint: String,
  response: http_response.Response,
  content_hash: Sha256,
) -> domain.Receipt {
  domain.Receipt(
    endpoint,
    http_response.byte_length(response),
    content_hash,
    http_response.first_header(response, name: "api-credits-used"),
    http_response.first_header(response, name: "api-credits-left"),
    http_response.first_header(response, name: "api-credits-request"),
  )
}

fn input_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "symbol",
      schema.string()
        |> schema.with_string_length(1, 20)
        |> schema.described("Exact uppercase US listing symbol"),
    ),
    schema.Required(
      "mic",
      schema.string_enum(["XNYS", "XNAS", "XNGS", "XNCM", "XNMS"])
        |> schema.described(
          "Exact provider MIC; Nasdaq segment MICs are preserved and never relabelled as XNAS",
        ),
    ),
  ])
}

fn input_decoder() -> decode.Decoder(domain.Input) {
  use symbol <- decode.field("symbol", decode.string)
  use mic <- decode.field("mic", decode.string)
  case domain.input(symbol, mic) {
    Ok(input) -> decode.success(input)
    Error(error) -> {
      let assert Ok(fallback) = domain.input("AAPL", "XNGS")
      decode.failure(fallback, domain.error_message(error))
    }
  }
}
