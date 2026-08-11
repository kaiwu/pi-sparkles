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
import gleam/result
import gleam/string
import pi
import pi/raw
import pi/schema
import pi/tool
import pi_sparkles_cn_stock_earnings/domain
import pi_sparkles_cn_stock_earnings/effect/environment

type Provider {
  Ready(finance_tushare.Access, runtime.Runtime)
  Unavailable(String)
}

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  let provider = provider()
  tool.register(
    api,
    "cn_stock_earnings",
    "CN stock earnings events",
    "Fetch one exact structured CN earnings event class—forecast, express report, or disclosure schedule—without substituting one class for another",
    "Preserve provider rows, exact numeric lexemes, report periods, announcement dates, revisions, unknowns, and content receipt",
    tool.parameters(input_schema(), input_decoder()),
    tool.Parallel,
    fn(id, plan, signal, _updates, _ctx) {
      case provider {
        Unavailable(reason) -> tool.reject(reason)
        Ready(access, provider_runtime) ->
          case make_request(access, plan) {
            Error(message) -> tool.reject(message)
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
                    "Tushare earnings request failed safely: "
                    <> string.inspect(error),
                  )
                Ok(response) -> process_response(plan, response)
              }
            }
          }
      }
    },
  )
  promise.resolve(Nil)
}

fn make_request(access, plan) {
  case domain.event_class(plan) {
    domain.Forecast ->
      case domain.dated_query(plan) {
        Ok(query) ->
          request.forecast(access, query)
          |> result.map_error(fn(_) { "Tushare forecast request was invalid" })
        Error(error) -> Error(domain.error_message(error))
      }
    domain.ExpressReport ->
      case domain.dated_query(plan) {
        Ok(query) ->
          request.express(access, query)
          |> result.map_error(fn(_) { "Tushare express request was invalid" })
        Error(error) -> Error(domain.error_message(error))
      }
    domain.DisclosureSchedule ->
      case domain.security_query(plan) {
        Ok(query) ->
          request.disclosure_dates(access, query)
          |> result.map_error(fn(_) {
            "Tushare disclosure schedule request was invalid"
          })
        Error(error) -> Error(domain.error_message(error))
      }
  }
}

fn process_response(plan, response) {
  let status = http_response.status(response)
  let body = http_response.body(response)
  case
    status >= 200 && status < 300,
    time.instant(environment.now_milliseconds()),
    hash.text(body)
  {
    True, Ok(retrieved_at), Ok(digest) ->
      case
        domain.decode_and_assemble(
          plan,
          body,
          retrieved_at,
          http_response.byte_length(response),
          digest,
        )
      {
        Ok(output) ->
          tool.text_result(domain.summary(output), domain.details(output))
          |> promise.resolve
        Error(error) -> tool.reject(domain.error_message(error))
      }
    False, _, _ ->
      tool.reject(
        "Tushare earnings request returned HTTP " <> int.to_string(status),
      )
    _, Error(_), _ -> tool.reject("retrieval clock was invalid")
    _, _, Error(_) -> tool.reject("response content could not be hashed")
  }
}

fn provider() -> Provider {
  case finance_tushare.access(environment.token()) {
    Error(_) ->
      Unavailable(
        "TUSHARE_TOKEN is required for the selected earnings adapter; provider permission/points apply",
      )
    Ok(access) ->
      case runtime.new(access) {
        Ok(value) -> Ready(access, value)
        Error(_) -> Unavailable("Tushare bounded runtime could not initialize")
      }
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
    schema.Required(
      "eventClass",
      schema.string_enum(["forecast", "express_report", "disclosure_schedule"]),
    ),
    schema.Required(
      "startDate",
      schema.string() |> schema.with_string_length(10, 10),
    ),
    schema.Required(
      "endDate",
      schema.string() |> schema.with_string_length(10, 10),
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
  use class <- decode.field("eventClass", decode.string)
  use start_text <- decode.field("startDate", decode.string)
  use end_text <- decode.field("endDate", decode.string)
  use limit <- decode.optional_field("maximumRows", 500, decode.int)
  let assert Ok(fallback_date) = time.date(2026, 1, 1)
  let assert Ok(fallback) =
    domain.plan(
      "cn",
      "sse",
      "600000",
      "a_share",
      "placeholder",
      "forecast",
      fallback_date,
      fallback_date,
      500,
    )
  case parse_date(start_text), parse_date(end_text) {
    Ok(start_date), Ok(end_date) ->
      case
        domain.plan(
          track,
          venue,
          code,
          share_class,
          evidence,
          class,
          start_date,
          end_date,
          limit,
        )
      {
        Ok(value) -> decode.success(value)
        Error(error) -> decode.failure(fallback, domain.error_message(error))
      }
    _, _ -> decode.failure(fallback, "valid Gregorian date range")
  }
}

fn parse_date(value: String) -> Result(time.Date, Nil) {
  case string.split(value, "-") {
    [year, month, day] -> {
      use year <- result.try(int.parse(year) |> result.map_error(fn(_) { Nil }))
      use month <- result.try(
        int.parse(month) |> result.map_error(fn(_) { Nil }),
      )
      use day <- result.try(int.parse(day) |> result.map_error(fn(_) { Nil }))
      time.date(year, month, day) |> result.map_error(fn(_) { Nil })
    }
    _ -> Error(Nil)
  }
}
