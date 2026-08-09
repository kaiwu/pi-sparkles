import finance_capco.{type Snapshot}
import finance_capco/request
import finance_capco/response
import finance_capco/runtime
import finance_core/time
import finance_http/transport
import gleam/dynamic/decode
import gleam/javascript/promise.{type Promise}
import gleam/string
import pi
import pi/raw
import pi/schema
import pi/tool
import pi_sparkles_cn_stock_sector_concept/domain
import pi_sparkles_cn_stock_sector_concept/effect/environment

type Provider {
  Ready(snapshot: Snapshot, runtime: runtime.Runtime)
  InvalidConfiguration(reason: String)
}

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  let provider = provider()
  tool.register(
    api,
    "cn_industry_classification",
    "CAPCO CN industry classification",
    "Retrieve one exact stock-code row from the pinned CAPCO 2025-H2 listed-company industry-classification PDF with taxonomy, publication, content-hash, and rights evidence",
    "The result period is not a membership validity interval; MIC, instrument identity, valid-from, and valid-to remain unknown",
    tool.parameters(classification_schema(), classification_decoder()),
    tool.Parallel,
    fn(id, plan, signal, _updates, _ctx) {
      case provider {
        InvalidConfiguration(reason) -> tool.reject(reason)
        Ready(snapshot, provider_runtime) -> {
          use outcome <- promise.await(fetch(
            snapshot,
            provider_runtime,
            plan,
            id,
            transport.from_abort_signal(raw.dynamic(signal)),
          ))
          case outcome {
            Error(message) -> tool.reject(message)
            Ok(capture) ->
              case domain.assemble(plan, capture) {
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
  case finance_capco.select("2025-H2") {
    Error(_) ->
      InvalidConfiguration("CAPCO reviewed result-period contract was invalid")
    Ok(snapshot) ->
      case runtime.new(snapshot) {
        Error(_) ->
          InvalidConfiguration("CAPCO bounded runtime could not initialize")
        Ok(provider_runtime) -> Ready(snapshot, provider_runtime)
      }
  }
}

fn fetch(
  snapshot: Snapshot,
  provider_runtime: runtime.Runtime,
  plan: domain.Plan,
  id: String,
  cancellation: transport.Cancellation,
) -> Promise(Result(response.Capture, String)) {
  case plan.snapshot.result_period == snapshot.result_period {
    False ->
      promise.resolve(Error(
        "CAPCO request period did not match the reviewed runtime period",
      ))
    True ->
      case request.classification_pdf(snapshot) {
        Error(_) -> promise.resolve(Error("CAPCO PDF request was invalid"))
        Ok(request_value) -> {
          use outcome <- promise.await(runtime.send(
            provider_runtime,
            id: id,
            request: request_value,
            cancellation: cancellation,
          ))
          case outcome {
            Error(error) ->
              promise.resolve(Error(
                "CAPCO PDF request failed safely: " <> string.inspect(error),
              ))
            Ok(response_value) ->
              case time.instant(environment.now_milliseconds()) {
                Error(_) ->
                  promise.resolve(Error("CAPCO retrieval clock was invalid"))
                Ok(retrieved_at) ->
                  response.capture(
                    snapshot,
                    response_value,
                    retrieved_at,
                    cancellation,
                  )
                  |> promise.map(fn(result) {
                    case result {
                      Ok(value) -> Ok(value)
                      Error(error) ->
                        Error(
                          "CAPCO PDF was rejected safely: "
                          <> string.inspect(error),
                        )
                    }
                  })
              }
          }
        }
      }
  }
}

fn classification_schema() -> schema.Schema {
  schema.object([
    schema.Required("track", schema.string_enum(["cn"])),
    schema.Required("resultPeriod", schema.string_enum(["2025-H2"])),
    schema.Required(
      "listingCode",
      schema.string()
        |> schema.with_string_length(6, 6)
        |> schema.described(
          "Exact six-digit stock code as printed by CAPCO; no MIC is inferred",
        ),
    ),
  ])
}

fn classification_decoder() -> decode.Decoder(domain.Plan) {
  use track <- decode.field("track", decode.string)
  use result_period <- decode.field("resultPeriod", decode.string)
  use listing_code <- decode.field("listingCode", decode.string)
  case domain.plan(track, result_period, listing_code) {
    Ok(plan) -> decode.success(plan)
    Error(error) -> {
      let assert Ok(fallback) = domain.plan("cn", "2025-H2", "000001")
      decode.failure(fallback, domain.error_message(error))
    }
  }
}
