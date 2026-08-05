import finance_calendar/calendar
import finance_calendar/local
import finance_core/source
import finance_core/time
import finance_market_calendar/dataset
import finance_provenance/evidence
import finance_track/context as track_context
import finance_track/json as track_json
import gleam/dynamic/decode
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import pi
import pi/schema
import pi/tool
import pi_sparkles_hk_market_calendar/query

pub type Input {
  Input(date: time.Date)
}

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  tool.register(
    api,
    "hk_market_calendar",
    "HK market calendar",
    "Classify one date with HKEX circular CT/075/25 for the 2026 securities market; preserve full closures, half-days, sessions, source, coverage, entitlement, and limitations",
    "Check whether the Hong Kong securities market is scheduled to trade on a 2026 date",
    tool.parameters(input_schema(), input_decoder()),
    tool.Parallel,
    fn(_id, input, _signal, _updates, _ctx) {
      case query.run(on: input.date) {
        Error(query.OutsideCoverage(_)) ->
          tool.reject(
            "HK official calendar covers only 2026; no weekday fallback was used",
          )
        Error(_) -> tool.reject("HK official calendar query was invalid")
        Ok(value) ->
          tool.text_result(render(value), result_json(value))
          |> promise.resolve
      }
    },
  )
  promise.resolve(Nil)
}

fn input_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "date",
      schema.string()
        |> schema.with_string_length(10, 10)
        |> schema.described("Gregorian date YYYY-MM-DD within 2026"),
    ),
  ])
}

fn input_decoder() -> decode.Decoder(Input) {
  use date_text <- decode.field("date", decode.string)
  let assert Ok(placeholder_date) = time.date(2026, 1, 1)
  case parse_date(date_text) {
    Ok(date) -> decode.success(Input(date))
    Error(_) -> decode.failure(Input(placeholder_date), "valid Gregorian date")
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

fn render(value: query.ResultValue) -> String {
  "HK track | HKEX official 2026 securities calendar | "
  <> date_text(value.date)
  <> " | "
  <> day_text(value.day)
  <> " | source "
  <> source.reference(dataset.source(value.dataset))
}

fn day_text(value: calendar.TradingDay) -> String {
  case value {
    calendar.Closed(reason) -> "closed (" <> reason <> ")"
    calendar.Open(sessions) ->
      open_kind(sessions)
      <> " ("
      <> int.to_string(list.length(sessions))
      <> " sessions)"
  }
}

fn result_json(value: query.ResultValue) -> json.Json {
  let #(coverage_start, coverage_end) = dataset.coverage(value.dataset)
  json.object(
    list.append(track_json.result_fields(dataset.context(value.dataset)), [
      #("venue", json.string("hkex")),
      #("date", json.string(date_text(value.date))),
      #("calendar", json.string(dataset.calendar_name(value.dataset))),
      #("version", json.string(dataset.version(value.dataset))),
      #(
        "coverage",
        json.object([
          #("start", json.string(date_text(coverage_start))),
          #("end", json.string(date_text(coverage_end))),
        ]),
      ),
      #("source", source_json(dataset.source(value.dataset))),
      #("licence", licence_json(dataset.licence(value.dataset))),
      #("day", day_json(value.day)),
      #(
        "limitations",
        json.array(
          track_context.limitations(dataset.context(value.dataset)),
          json.string,
        ),
      ),
    ]),
  )
}

fn day_json(value: calendar.TradingDay) -> json.Json {
  case value {
    calendar.Closed(reason) ->
      json.object([
        #("status", json.string("closed")),
        #("dayKind", json.string("closed")),
        #("reason", json.string(reason)),
        #("sessions", json.array([], json.string)),
      ])
    calendar.Open(sessions) ->
      json.object([
        #("status", json.string("open")),
        #("dayKind", json.string(open_kind(sessions))),
        #("reason", json.null()),
        #("sessions", json.array(sessions, session_json)),
      ])
  }
}

fn open_kind(sessions: List(calendar.Session)) -> String {
  case list.length(sessions) {
    2 -> "half_day"
    _ -> "full_day"
  }
}

fn session_json(value: calendar.Session) -> json.Json {
  json.object([
    #("label", json.string(calendar.label(value))),
    #("opensAt", json.string(clock_text(calendar.opens_at(value)))),
    #("closesAt", json.string(clock_text(calendar.closes_at(value)))),
    #("timezone", json.string("Asia/Hong_Kong")),
  ])
}

fn source_json(value: source.SourceRef) -> json.Json {
  json.object([
    #("provider", json.string(source.provider(value))),
    #("reference", json.string(source.reference(value))),
    #("kind", json.string("exchange")),
  ])
}

fn licence_json(value: evidence.Licence) -> json.Json {
  let evidence.Licence(label, redistribution, notes) = value
  json.object([
    #("label", json.string(label)),
    #("redistribution", json.string(redistribution_name(redistribution))),
    #("notes", case notes {
      Some(value) -> json.string(value)
      None -> json.null()
    }),
  ])
}

fn redistribution_name(value: evidence.Redistribution) -> String {
  case value {
    evidence.PublicDomain -> "public_domain"
    evidence.AttributionRequired -> "attribution_required"
    evidence.InternalUseOnly -> "internal_use_only"
    evidence.NoRedistribution -> "no_redistribution"
    evidence.UnknownRedistribution -> "unknown_redistribution"
  }
}

fn date_text(value: time.Date) -> String {
  let #(year, month, day) = time.date_parts(value)
  int.to_string(year) <> "-" <> two_digits(month) <> "-" <> two_digits(day)
}

fn clock_text(value: time.TimeOfDay) -> String {
  let #(hour, minute) = local.time_parts(value)
  two_digits(hour) <> ":" <> two_digits(minute)
}

fn two_digits(value: Int) -> String {
  case value < 10 {
    True -> "0" <> int.to_string(value)
    False -> int.to_string(value)
  }
}
