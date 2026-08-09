import finance_core/time
import finance_fred
import finance_fred/request as provider_request
import finance_fred/runtime
import finance_fred/series
import finance_http/response as http_response
import finance_http/transport
import finance_provenance/hash
import gleam/dynamic/decode
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/string
import pi
import pi/raw
import pi/schema
import pi/tool
import pi_sparkles_macro_fred/domain
import pi_sparkles_macro_fred/effect/environment

type Provider {
  Ready(access: finance_fred.Access, runtime: runtime.Runtime)
  InvalidConfiguration(reason: String)
}

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  let provider = provider()
  tool.register(
    api,
    "fred_series",
    "Exact point-in-time FRED series range",
    "Retrieve exact FRED v1 series metadata and a bounded raw level observation range, then expose the final source value and exact immediately-prior arithmetic change",
    "Requires a per-user FRED_API_KEY; returns no forecast, release-time inference, percentage change, or economic interpretation",
    tool.parameters(input_schema(), input_decoder()),
    tool.Parallel,
    fn(id, plan, signal, _updates, _ctx) {
      case provider {
        InvalidConfiguration(reason) -> tool.reject(reason)
        Ready(access, provider_runtime) -> {
          use capture <- promise.await(fetch(
            provider_runtime,
            access,
            plan,
            id,
            transport.from_abort_signal(raw.dynamic(signal)),
          ))
          case capture {
            Error(message) -> tool.reject(message)
            Ok(value) ->
              case domain.run(plan, value) {
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
  case finance_fred.access(environment.api_key()) {
    Error(_) ->
      InvalidConfiguration(
        "FRED access requires FRED_API_KEY as the caller's 32-character lowercase API key",
      )
    Ok(access) ->
      case runtime.new() {
        Error(_) ->
          InvalidConfiguration("FRED runtime could not initialize safely")
        Ok(provider_runtime) -> Ready(access, provider_runtime)
      }
  }
}

fn fetch(
  provider_runtime: runtime.Runtime,
  access: finance_fred.Access,
  plan: domain.Plan,
  id: String,
  cancellation: transport.Cancellation,
) -> Promise(Result(domain.Capture, String)) {
  case provider_request.metadata(access, plan.query) {
    Error(_) -> promise.resolve(Error("FRED metadata request was invalid"))
    Ok(metadata_request) -> {
      use metadata_sent <- promise.await(runtime.send(
        provider_runtime,
        id: id <> ":metadata",
        request: metadata_request,
        cancellation: cancellation,
      ))
      case checked_response(metadata_sent, "metadata") {
        Error(message) -> promise.resolve(Error(message))
        Ok(metadata_response) -> {
          let metadata_body = http_response.body(metadata_response)
          case
            series.decode_metadata(metadata_body, plan.query),
            hash.text(metadata_body)
          {
            Error(error), _ ->
              promise.resolve(Error(
                "FRED metadata response was rejected safely: "
                <> string.inspect(error),
              ))
            _, Error(_) ->
              promise.resolve(Error(
                "FRED metadata response could not be content-bound",
              ))
            Ok(metadata), Ok(metadata_hash) ->
              fetch_observations(
                provider_runtime,
                access,
                plan,
                id,
                cancellation,
                metadata,
                domain.Receipt(
                  provider_request.metadata_path,
                  http_response.first_header(
                    metadata_response,
                    name: "x-request-id",
                  ),
                  http_response.byte_length(metadata_response),
                  metadata_hash,
                ),
              )
          }
        }
      }
    }
  }
}

fn fetch_observations(
  provider_runtime: runtime.Runtime,
  access: finance_fred.Access,
  plan: domain.Plan,
  id: String,
  cancellation: transport.Cancellation,
  metadata: series.Metadata,
  metadata_receipt: domain.Receipt,
) -> Promise(Result(domain.Capture, String)) {
  case provider_request.observations(access, plan.query) {
    Error(_) -> promise.resolve(Error("FRED observations request was invalid"))
    Ok(observations_request) -> {
      use observations_sent <- promise.await(runtime.send(
        provider_runtime,
        id: id <> ":observations",
        request: observations_request,
        cancellation: cancellation,
      ))
      case checked_response(observations_sent, "observations") {
        Error(message) -> promise.resolve(Error(message))
        Ok(observations_response) -> {
          let body = http_response.body(observations_response)
          case series.decode_observations(body, plan.query), hash.text(body) {
            Error(error), _ ->
              promise.resolve(Error(
                "FRED observations response was rejected safely: "
                <> string.inspect(error),
              ))
            _, Error(_) ->
              promise.resolve(Error(
                "FRED observations response could not be content-bound",
              ))
            Ok(range), Ok(content_hash) ->
              case time.instant(environment.now_milliseconds()) {
                Error(_) ->
                  promise.resolve(Error("FRED retrieval clock was invalid"))
                Ok(retrieved_at) ->
                  promise.resolve(
                    Ok(domain.Capture(
                      metadata,
                      metadata_receipt,
                      range,
                      domain.Receipt(
                        provider_request.observations_path,
                        http_response.first_header(
                          observations_response,
                          name: "x-request-id",
                        ),
                        http_response.byte_length(observations_response),
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
    Error(error) ->
      Error(
        "FRED " <> label <> " request failed safely: " <> string.inspect(error),
      )
    Ok(value) -> {
      let status = http_response.status(value)
      case status >= 200 && status < 300 {
        True -> Ok(value)
        False if status == 400 || status == 401 || status == 403 ->
          Error(
            "FRED rejected the request or API key (HTTP "
            <> int.to_string(status)
            <> ")",
          )
        False if status == 429 -> Error("FRED rate limit was reached (HTTP 429)")
        False ->
          Error(
            "FRED "
            <> label
            <> " request returned HTTP "
            <> int.to_string(status),
          )
      }
    }
  }
}

fn input_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "seriesId",
      schema.string()
        |> schema.with_string_length(1, 120)
        |> schema.described("Exact FRED series identifier"),
    ),
    schema.Required("observationStart", date_schema()),
    schema.Required("observationEnd", date_schema()),
    schema.Required(
      "asOfDate",
      date_schema()
        |> schema.described(
          "Exact FRED realtime_start and realtime_end point-in-time date",
        ),
    ),
    schema.Required(
      "maximumObservations",
      schema.integer()
        |> schema.with_number_range(1.0, 1000.0)
        |> schema.described(
          "Hard complete-range cap; the tool rejects a larger provider count",
        ),
    ),
  ])
}

fn date_schema() -> schema.Schema {
  schema.string()
  |> schema.with_string_length(10, 10)
  |> schema.described("Canonical Gregorian YYYY-MM-DD")
}

fn input_decoder() -> decode.Decoder(domain.Plan) {
  use series_id <- decode.field("seriesId", decode.string)
  use observation_start <- decode.field("observationStart", decode.string)
  use observation_end <- decode.field("observationEnd", decode.string)
  use as_of_date <- decode.field("asOfDate", decode.string)
  use maximum_observations <- decode.field("maximumObservations", decode.int)
  case
    domain.plan(
      series_id,
      observation_start,
      observation_end,
      as_of_date,
      maximum_observations,
    )
  {
    Ok(plan) -> decode.success(plan)
    Error(error) -> {
      let assert Ok(fallback) =
        domain.plan("CPIAUCSL", "2025-01-01", "2025-12-31", "2026-01-01", 100)
      decode.failure(fallback, domain.error_message(error))
    }
  }
}
