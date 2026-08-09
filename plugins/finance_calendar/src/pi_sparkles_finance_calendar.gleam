import gleam/dynamic/decode
import gleam/javascript/promise.{type Promise}
import pi
import pi/schema
import pi/tool
import pi_sparkles_finance_calendar/domain

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  tool.register(
    api,
    "inspect_session",
    "Inspect an exact venue session date",
    "Classify one date with the caller-selected CN, HK, or US venue's source-reviewed 2026 calendar and preserve its ordered local phase intervals, source, coverage, entitlement, and limitations",
    "Supply the exact track, MIC, and covered date; no venue, provider, or sibling-track fallback is used",
    tool.parameters(inspect_schema(), inspect_decoder()),
    tool.Parallel,
    fn(_id, input, _signal, _updates, _ctx) {
      case domain.inspect_session(input) {
        Ok(value) ->
          tool.text_result(value.summary, value.details)
          |> promise.resolve
        Error(error) -> tool.reject(domain.error_message(error))
      }
    },
  )
  tool.register(
    api,
    "list_holidays",
    "List published venue holidays",
    "Return a stable date-ordered page of venue-published full closures in one covered inclusive range; ordinary weekends remain distinct and are not called holidays",
    "Supply the exact track, MIC, covered range, offset, and limit; the LLM interprets the closure facts and chooses any next operation",
    tool.parameters(holidays_schema(), holidays_decoder()),
    tool.Parallel,
    fn(_id, input, _signal, _updates, _ctx) {
      case domain.list_holidays(input) {
        Ok(value) ->
          tool.text_result(value.summary, value.details)
          |> promise.resolve
        Error(error) -> tool.reject(domain.error_message(error))
      }
    },
  )
  tool.register(
    api,
    "next_session",
    "Find the next exact venue session",
    "Return the first scheduled open date strictly after one covered date, including its ordered local phase intervals, or report that no later session is available inside coverage",
    "Supply the exact track, MIC, and covered after date; this reports a calendar fact and does not schedule or recommend an action",
    tool.parameters(next_schema(), next_decoder()),
    tool.Parallel,
    fn(_id, input, _signal, _updates, _ctx) {
      case domain.next_session(input) {
        Ok(value) ->
          tool.text_result(value.summary, value.details)
          |> promise.resolve
        Error(error) -> tool.reject(domain.error_message(error))
      }
    },
  )
  promise.resolve(Nil)
}

fn inspect_schema() -> schema.Schema {
  schema.object([
    schema.Required("track", track_schema()),
    schema.Required("venue", venue_schema()),
    schema.Required("date", date_schema()),
  ])
}

fn holidays_schema() -> schema.Schema {
  schema.object([
    schema.Required("track", track_schema()),
    schema.Required("venue", venue_schema()),
    schema.Required("startDate", date_schema()),
    schema.Required("endDate", date_schema()),
    schema.Required(
      "offset",
      schema.integer() |> schema.with_number_range(0.0, 366.0),
    ),
    schema.Required(
      "limit",
      schema.integer() |> schema.with_number_range(1.0, 200.0),
    ),
  ])
}

fn next_schema() -> schema.Schema {
  schema.object([
    schema.Required("track", track_schema()),
    schema.Required("venue", venue_schema()),
    schema.Required("after", date_schema()),
  ])
}

fn track_schema() -> schema.Schema {
  schema.string_enum(["cn", "hk", "us"])
}

fn venue_schema() -> schema.Schema {
  schema.string_enum(["XSHG", "XSHE", "XBSE", "XHKG", "XNYS", "XNAS"])
  |> schema.described(
    "Exact ISO 10383 MIC; it must belong to the supplied track",
  )
}

fn date_schema() -> schema.Schema {
  schema.string()
  |> schema.with_string_length(10, 10)
  |> schema.described("Canonical Gregorian YYYY-MM-DD within dataset coverage")
}

fn inspect_decoder() -> decode.Decoder(domain.InspectInput) {
  use track <- decode.field("track", decode.string)
  use venue <- decode.field("venue", decode.string)
  use date <- decode.field("date", decode.string)
  decode.success(domain.InspectInput(track, venue, date))
}

fn holidays_decoder() -> decode.Decoder(domain.HolidaysInput) {
  use track <- decode.field("track", decode.string)
  use venue <- decode.field("venue", decode.string)
  use start_date <- decode.field("startDate", decode.string)
  use end_date <- decode.field("endDate", decode.string)
  use offset <- decode.field("offset", decode.int)
  use limit <- decode.field("limit", decode.int)
  decode.success(domain.HolidaysInput(
    track,
    venue,
    start_date,
    end_date,
    offset,
    limit,
  ))
}

fn next_decoder() -> decode.Decoder(domain.NextInput) {
  use track <- decode.field("track", decode.string)
  use venue <- decode.field("venue", decode.string)
  use after <- decode.field("after", decode.string)
  decode.success(domain.NextInput(track, venue, after))
}
