import finance_core/time
import finance_hkex
import finance_hkex/board_meeting
import finance_hkex/board_meeting_runtime
import finance_hkex/request
import finance_http/transport
import gleam/dynamic/decode
import gleam/javascript/promise.{type Promise}
import gleam/result
import gleam/string
import pi
import pi/raw
import pi/schema
import pi/tool
import pi_sparkles_stock_earnings_calendar/domain
import pi_sparkles_stock_earnings_calendar/effect/environment

type Provider {
  Ready(access: finance_hkex.Access, runtime: board_meeting_runtime.Runtime)
  InvalidConfiguration(reason: String)
}

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  let provider = provider()
  tool.register(
    api,
    "earnings_calendar",
    "HKEX result-related board-meeting calendar",
    "Retrieve exact HKEX Main Board or GEM issuer-announced board-meeting dates whose raw purpose carries a visible results marker; preserve non-results rows and source evidence",
    "These are board-meeting start dates, not earnings publication timestamps, and the source page is explicitly non-exhaustive",
    tool.parameters(calendar_schema(), calendar_decoder()),
    tool.Parallel,
    fn(id, plan, signal, _updates, _ctx) {
      case provider {
        InvalidConfiguration(reason) -> tool.reject(reason)
        Ready(access, runtime) -> {
          use outcome <- promise.await(fetch(
            runtime,
            access,
            plan,
            id,
            transport.from_abort_signal(raw.dynamic(signal)),
          ))
          case outcome {
            Error(message) -> tool.reject(message)
            Ok(captured) ->
              case domain.run(plan, captured) {
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
  case finance_hkex.access(environment.product(), environment.contact()) {
    Error(_) ->
      InvalidConfiguration(
        "HKEX access requires HKEX_USER_AGENT_CONTACT (for example ops@example.com); HKEX_USER_AGENT_PRODUCT is optional",
      )
    Ok(access) ->
      case board_meeting_runtime.new(access) {
        Error(_) ->
          InvalidConfiguration(
            "HKEX board-meeting runtime could not initialize safely",
          )
        Ok(runtime) -> Ready(access, runtime)
      }
  }
}

fn fetch(
  runtime: board_meeting_runtime.Runtime,
  access: finance_hkex.Access,
  plan: domain.Plan,
  id: String,
  cancellation: transport.Cancellation,
) -> Promise(Result(board_meeting.Capture, String)) {
  case request.board_meetings(access, plan.board) {
    Error(_) -> promise.resolve(Error("HKEX board-meeting request was invalid"))
    Ok(request_value) -> {
      use outcome <- promise.await(board_meeting_runtime.send(
        runtime,
        id: id,
        request: request_value,
        cancellation: cancellation,
      ))
      case outcome {
        Error(error) ->
          promise.resolve(Error(
            "HKEX board-meeting request failed safely: "
            <> string.inspect(error),
          ))
        Ok(response_value) ->
          case time.instant(environment.now_milliseconds()) {
            Error(_) ->
              promise.resolve(Error(
                "HKEX board-meeting retrieval clock was invalid",
              ))
            Ok(retrieved_at) ->
              board_meeting.capture(plan.board, response_value, retrieved_at)
              |> result.map_error(fn(error) {
                "HKEX board-meeting response was rejected safely: "
                <> string.inspect(error)
              })
              |> promise.resolve
          }
      }
    }
  }
}

fn calendar_schema() -> schema.Schema {
  schema.object([
    schema.Required("track", schema.string_enum(["hk"])),
    schema.Required("venue", schema.string_enum(["XHKG"])),
    schema.Required(
      "board",
      schema.string_enum(["main", "gem"])
        |> schema.described("Exact HKEX Board Meeting Notifications page"),
    ),
    schema.Required(
      "code",
      schema.string()
        |> schema.with_string_length(5, 5)
        |> schema.described("Exact normalized five-digit HKEX security code"),
    ),
    schema.Required("startDate", date_schema()),
    schema.Required("endDate", date_schema()),
  ])
}

fn date_schema() -> schema.Schema {
  schema.string()
  |> schema.with_string_length(10, 10)
  |> schema.described("Canonical Gregorian YYYY-MM-DD inclusive range bound")
}

fn calendar_decoder() -> decode.Decoder(domain.Plan) {
  use track <- decode.field("track", decode.string)
  use venue <- decode.field("venue", decode.string)
  use board <- decode.field("board", decode.string)
  use code <- decode.field("code", decode.string)
  use start_date <- decode.field("startDate", decode.string)
  use end_date <- decode.field("endDate", decode.string)
  case domain.plan(track, venue, board, code, start_date, end_date) {
    Ok(plan) -> decode.success(plan)
    Error(error) -> {
      let assert Ok(fallback) =
        domain.plan("hk", "XHKG", "main", "00700", "2026-01-01", "2026-12-31")
      decode.failure(fallback, domain.error_message(error))
    }
  }
}
