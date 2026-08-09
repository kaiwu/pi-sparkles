import finance_calendar/calendar
import finance_calendar/date as calendar_date
import finance_calendar/local
import finance_cn_calendar/dataset as cn_calendar
import finance_cn_identity/identity as cn_identity
import finance_core/source
import finance_core/time
import finance_hk_calendar/dataset as hk_calendar
import finance_market_calendar/dataset
import finance_provenance/evidence
import finance_track/context as track_context
import finance_track/json as track_json
import finance_us_calendar/dataset as us_calendar
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{Eq, Gt, Lt}
import gleam/result
import gleam/string

pub type InspectInput {
  InspectInput(track: String, venue: String, date: String)
}

pub type HolidaysInput {
  HolidaysInput(
    track: String,
    venue: String,
    start_date: String,
    end_date: String,
    offset: Int,
    limit: Int,
  )
}

pub type NextInput {
  NextInput(track: String, venue: String, after: String)
}

pub type Response {
  Response(summary: String, details: Json)
}

pub type DomainError {
  InvalidTrackVenue(track: String, venue: String)
  InvalidDate(field: String, value: String)
  InvalidRange(start: String, end: String)
  OutsideCoverage(field: String, start: String, end: String, received: String)
  InvalidPage(offset: Int, limit: Int, available: Int)
  DatasetUnavailable(track: String, venue: String)
  CalendarFailure
}

type Loaded {
  Loaded(
    track: String,
    venue: String,
    timezone: String,
    dataset: dataset.Dataset,
  )
}

type Holiday {
  Holiday(date: time.Date, reason: String)
}

pub fn error_message(value: DomainError) -> String {
  case value {
    InvalidTrackVenue(track, venue) ->
      "Venue "
      <> venue
      <> " does not belong to track "
      <> track
      <> "; no venue or sibling-track fallback was used"
    InvalidDate(field, value) ->
      "Invalid canonical Gregorian date for " <> field <> ": " <> value
    InvalidRange(start, end) ->
      "Invalid inclusive calendar range " <> start <> " through " <> end
    OutsideCoverage(field, start, end, received) ->
      field
      <> " "
      <> received
      <> " is outside exact calendar coverage "
      <> start
      <> " through "
      <> end
      <> "; no weekday fallback was used"
    InvalidPage(offset, limit, available) ->
      "Invalid holiday page offset "
      <> int.to_string(offset)
      <> " and limit "
      <> int.to_string(limit)
      <> " for "
      <> int.to_string(available)
      <> " published closures"
    DatasetUnavailable(track, venue) ->
      "The source-reviewed 2026 calendar dataset could not be constructed for "
      <> track
      <> " "
      <> venue
    CalendarFailure -> "The bounded calendar query failed safely"
  }
}

pub fn inspect_session(input: InspectInput) -> Result(Response, DomainError) {
  use loaded <- result.try(load(input.track, input.venue))
  use requested <- result.try(parse_date("date", input.date))
  use day <- result.try(trading_day(loaded, "date", requested))
  Ok(Response(
    loaded.track
      <> " "
      <> loaded.venue
      <> " "
      <> input.date
      <> " is "
      <> day_summary(loaded, day),
    details(loaded, "inspect_session", [
      #(
        "query",
        json.object([
          #("date", json.string(input.date)),
          #("datePolicy", json.string("exact_covered_date_v1")),
        ]),
      ),
      #("day", day_json(loaded, requested, day)),
    ]),
  ))
}

pub fn list_holidays(input: HolidaysInput) -> Result(Response, DomainError) {
  use loaded <- result.try(load(input.track, input.venue))
  use start <- result.try(parse_date("startDate", input.start_date))
  use end <- result.try(parse_date("endDate", input.end_date))
  use _ <- result.try(case calendar_date.compare(start, end) {
    Gt -> Error(InvalidRange(input.start_date, input.end_date))
    _ -> Ok(Nil)
  })
  use _ <- result.try(require_coverage(loaded, "startDate", start))
  use _ <- result.try(require_coverage(loaded, "endDate", end))
  use holidays <- result.try(collect_holidays(loaded, start, end, []))
  let total = list.length(holidays)
  use _ <- result.try(
    case
      input.offset >= 0,
      input.limit >= 1 && input.limit <= 200,
      input.offset <= total
    {
      True, True, True -> Ok(Nil)
      _, _, _ -> Error(InvalidPage(input.offset, input.limit, total))
    },
  )
  let page = holidays |> list.drop(input.offset) |> list.take(input.limit)
  let returned = list.length(page)
  let next_offset = case input.offset + returned < total {
    True -> Some(input.offset + returned)
    False -> None
  }
  let range_id =
    loaded.track
    <> ":"
    <> loaded.venue
    <> ":"
    <> dataset.version(loaded.dataset)
    <> ":"
    <> input.start_date
    <> ":"
    <> input.end_date
  Ok(Response(
    "Returned "
      <> int.to_string(returned)
      <> " of "
      <> int.to_string(total)
      <> " published full closures for "
      <> loaded.track
      <> " "
      <> loaded.venue,
    details(loaded, "list_holidays", [
      #(
        "query",
        json.object([
          #("startDate", json.string(input.start_date)),
          #("endDate", json.string(input.end_date)),
          #("rangePolicy", json.string("inclusive_published_full_closures_v1")),
          #("weekendsIncluded", json.bool(False)),
        ]),
      ),
      #("rangeId", json.string(range_id)),
      #("offset", json.int(input.offset)),
      #("limit", json.int(input.limit)),
      #("matchedCount", json.int(total)),
      #("returnedCount", json.int(returned)),
      #("nextOffset", json.nullable(next_offset, json.int)),
      #("holidays", json.array(page, holiday_json)),
    ]),
  ))
}

pub fn next_session(input: NextInput) -> Result(Response, DomainError) {
  use loaded <- result.try(load(input.track, input.venue))
  use after <- result.try(parse_date("after", input.after))
  use _ <- result.try(require_coverage(loaded, "after", after))
  let #(_, coverage_end) = dataset.coverage(loaded.dataset)
  use candidate <- result.try(
    calendar_date.add_days(after, 1)
    |> result.map_error(fn(_) { CalendarFailure }),
  )
  use found <- result.try(find_next_open(loaded, candidate, coverage_end))
  case found {
    Some(#(date, sessions)) -> {
      let date_value = date_text(date)
      Ok(Response(
        "Next "
          <> loaded.track
          <> " "
          <> loaded.venue
          <> " session after "
          <> input.after
          <> " is "
          <> date_value,
        details(loaded, "next_session", [
          #(
            "query",
            json.object([
              #("after", json.string(input.after)),
              #(
                "searchPolicy",
                json.string("strictly_after_within_coverage_v1"),
              ),
            ]),
          ),
          #("availability", json.string("available")),
          #("session", day_json(loaded, date, calendar.Open(sessions))),
        ]),
      ))
    }
    None ->
      Ok(Response(
        "No later "
          <> loaded.track
          <> " "
          <> loaded.venue
          <> " session is available inside calendar coverage after "
          <> input.after,
        details(loaded, "next_session", [
          #(
            "query",
            json.object([
              #("after", json.string(input.after)),
              #(
                "searchPolicy",
                json.string("strictly_after_within_coverage_v1"),
              ),
            ]),
          ),
          #("availability", json.string("unavailable")),
          #("unavailableReason", json.string("no_later_open_date_in_coverage")),
          #("session", json.null()),
        ]),
      ))
  }
}

fn load(track: String, venue: String) -> Result(Loaded, DomainError) {
  case track, venue {
    "cn", "XSHG" -> load_cn(venue, cn_identity.Sse)
    "cn", "XSHE" -> load_cn(venue, cn_identity.Szse)
    "cn", "XBSE" -> load_cn(venue, cn_identity.Bse)
    "hk", "XHKG" ->
      case hk_calendar.official_2026() {
        Ok(value) -> Ok(Loaded(track, venue, "Asia/Hong_Kong", value))
        Error(_) -> Error(DatasetUnavailable(track, venue))
      }
    "us", "XNYS" -> load_us(venue, us_calendar.Nyse)
    "us", "XNAS" -> load_us(venue, us_calendar.Nasdaq)
    _, _ -> Error(InvalidTrackVenue(track, venue))
  }
}

fn load_cn(
  venue: String,
  market_venue: cn_identity.Venue,
) -> Result(Loaded, DomainError) {
  case cn_calendar.official_2026(market_venue) {
    Ok(value) -> Ok(Loaded("cn", venue, "Asia/Shanghai", value))
    Error(_) -> Error(DatasetUnavailable("cn", venue))
  }
}

fn load_us(
  venue: String,
  market_venue: us_calendar.Venue,
) -> Result(Loaded, DomainError) {
  case us_calendar.official_2026(market_venue) {
    Ok(value) -> Ok(Loaded("us", venue, "America/New_York", value))
    Error(_) -> Error(DatasetUnavailable("us", venue))
  }
}

fn parse_date(field: String, value: String) -> Result(time.Date, DomainError) {
  case string.split(value, "-") {
    [year, month, day] ->
      case int.parse(year), int.parse(month), int.parse(day) {
        Ok(year), Ok(month), Ok(day) ->
          case time.date(year, month, day) {
            Ok(parsed) ->
              case date_text(parsed) == value {
                True -> Ok(parsed)
                False -> Error(InvalidDate(field, value))
              }
            Error(_) -> Error(InvalidDate(field, value))
          }
        _, _, _ -> Error(InvalidDate(field, value))
      }
    _ -> Error(InvalidDate(field, value))
  }
}

fn require_coverage(
  loaded: Loaded,
  field: String,
  value: time.Date,
) -> Result(Nil, DomainError) {
  let #(start, end) = dataset.coverage(loaded.dataset)
  case
    calendar_date.compare(value, start) == Lt
    || calendar_date.compare(value, end) == Gt
  {
    True ->
      Error(OutsideCoverage(
        field,
        date_text(start),
        date_text(end),
        date_text(value),
      ))
    False -> Ok(Nil)
  }
}

fn trading_day(
  loaded: Loaded,
  field: String,
  value: time.Date,
) -> Result(calendar.TradingDay, DomainError) {
  case dataset.trading_day(loaded.dataset, on: value) {
    Ok(day) -> Ok(day)
    Error(dataset.OutsideCoverage(start, end, received)) ->
      Error(OutsideCoverage(
        field,
        date_text(start),
        date_text(end),
        date_text(received),
      ))
    Error(_) -> Error(CalendarFailure)
  }
}

fn collect_holidays(
  loaded: Loaded,
  current: time.Date,
  end: time.Date,
  reversed: List(Holiday),
) -> Result(List(Holiday), DomainError) {
  use day <- result.try(trading_day(loaded, "range", current))
  let next_reversed = case day {
    calendar.Closed("weekly closure") -> reversed
    calendar.Closed(reason) -> [Holiday(current, reason), ..reversed]
    calendar.Open(_) -> reversed
  }
  case calendar_date.compare(current, end) {
    Eq -> Ok(list.reverse(next_reversed))
    _ -> {
      use next <- result.try(
        calendar_date.add_days(current, 1)
        |> result.map_error(fn(_) { CalendarFailure }),
      )
      collect_holidays(loaded, next, end, next_reversed)
    }
  }
}

fn find_next_open(
  loaded: Loaded,
  current: time.Date,
  coverage_end: time.Date,
) -> Result(Option(#(time.Date, List(calendar.Session))), DomainError) {
  case calendar_date.compare(current, coverage_end) {
    Gt -> Ok(None)
    _ -> {
      use day <- result.try(trading_day(loaded, "after", current))
      case day {
        calendar.Open(sessions) -> Ok(Some(#(current, sessions)))
        calendar.Closed(_) -> {
          use next <- result.try(
            calendar_date.add_days(current, 1)
            |> result.map_error(fn(_) { CalendarFailure }),
          )
          find_next_open(loaded, next, coverage_end)
        }
      }
    }
  }
}

fn details(
  loaded: Loaded,
  operation: String,
  operation_fields: List(#(String, Json)),
) -> Json {
  let #(coverage_start, coverage_end) = dataset.coverage(loaded.dataset)
  let source_value = dataset.source(loaded.dataset)
  json.object(
    list.append(track_json.result_fields(dataset.context(loaded.dataset)), [
      #("operation", json.string(operation)),
      #("venue", json.string(loaded.venue)),
      #("calendar", json.string(dataset.calendar_name(loaded.dataset))),
      #("version", json.string(dataset.version(loaded.dataset))),
      #(
        "coverage",
        json.object([
          #("start", json.string(date_text(coverage_start))),
          #("end", json.string(date_text(coverage_end))),
        ]),
      ),
      #(
        "source",
        json.object([
          #("provider", json.string(source.provider(source_value))),
          #("reference", json.string(source.reference(source_value))),
          #("kind", json.string("exchange")),
        ]),
      ),
      #("licence", licence_json(dataset.licence(loaded.dataset))),
      #(
        "limitations",
        json.array(
          track_context.limitations(dataset.context(loaded.dataset)),
          json.string,
        ),
      ),
      #("decisionOwner", json.string("llm")),
      #("pluginDecisionFields", json.array([], json.string)),
      ..operation_fields
    ]),
  )
}

fn day_json(loaded: Loaded, date: time.Date, day: calendar.TradingDay) -> Json {
  let base = [
    #("date", json.string(date_text(date))),
    #("weekday", json.string(weekday_text(calendar_date.weekday(date)))),
  ]
  case day {
    calendar.Closed(reason) ->
      json.object(
        list.append(base, [
          #("status", json.string("closed")),
          #("sessionType", json.string("closed")),
          #(
            "closureKind",
            json.string(case reason == "weekly closure" {
              True -> "weekly_closure"
              False -> "published_full_closure"
            }),
          ),
          #("reason", json.string(reason)),
          #("phaseIntervals", json.array([], json.string)),
        ]),
      )
    calendar.Open(sessions) ->
      json.object(
        list.append(base, [
          #("status", json.string("open")),
          #("sessionType", json.string(session_type(loaded, sessions))),
          #("closureKind", json.null()),
          #("reason", json.null()),
          #(
            "phaseIntervals",
            json.array(sessions, fn(session) { phase_json(loaded, session) }),
          ),
        ]),
      )
  }
}

fn session_type(loaded: Loaded, sessions: List(calendar.Session)) -> String {
  let labels = list.map(sessions, calendar.label)
  case
    loaded.venue == "XHKG" && !list.contains(labels, "continuous_afternoon"),
    list.contains(labels, "regular_market_early_close")
  {
    True, _ -> "regular_shortened"
    _, True -> "regular_shortened"
    False, False -> "regular_full"
  }
}

fn phase_json(loaded: Loaded, session: calendar.Session) -> Json {
  json.object([
    #("label", json.string(calendar.label(session))),
    #("opensAt", json.string(clock_text(calendar.opens_at(session)))),
    #("closesAt", json.string(clock_text(calendar.closes_at(session)))),
    #(
      "closeDay",
      json.string(case calendar.close_day(session) {
        calendar.SameDay -> "same_day"
        calendar.NextDay -> "next_day"
      }),
    ),
    #("timezone", json.string(loaded.timezone)),
    #("timeBasis", json.string("venue_local_wall_clock")),
  ])
}

fn holiday_json(value: Holiday) -> Json {
  json.object([
    #("date", json.string(date_text(value.date))),
    #("weekday", json.string(weekday_text(calendar_date.weekday(value.date)))),
    #("kind", json.string("published_full_closure")),
    #("reason", json.string(value.reason)),
  ])
}

fn licence_json(value: evidence.Licence) -> Json {
  let evidence.Licence(label, redistribution, notes) = value
  json.object([
    #("label", json.string(label)),
    #(
      "redistribution",
      json.string(case redistribution {
        evidence.PublicDomain -> "public_domain"
        evidence.AttributionRequired -> "attribution_required"
        evidence.InternalUseOnly -> "internal_use_only"
        evidence.NoRedistribution -> "no_redistribution"
        evidence.UnknownRedistribution -> "unknown_redistribution"
      }),
    ),
    #("notes", case notes {
      Some(value) -> json.string(value)
      None -> json.null()
    }),
  ])
}

fn day_summary(loaded: Loaded, value: calendar.TradingDay) -> String {
  case value {
    calendar.Closed(reason) -> "closed (" <> reason <> ")"
    calendar.Open(sessions) ->
      session_type(loaded, sessions)
      <> " with "
      <> int.to_string(list.length(sessions))
      <> " phases"
  }
}

fn weekday_text(value: calendar_date.Weekday) -> String {
  case value {
    calendar_date.Monday -> "monday"
    calendar_date.Tuesday -> "tuesday"
    calendar_date.Wednesday -> "wednesday"
    calendar_date.Thursday -> "thursday"
    calendar_date.Friday -> "friday"
    calendar_date.Saturday -> "saturday"
    calendar_date.Sunday -> "sunday"
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
