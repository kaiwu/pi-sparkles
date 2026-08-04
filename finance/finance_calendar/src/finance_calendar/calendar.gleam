import finance_calendar/date.{type Weekday}
import finance_calendar/local.{type LocalTime, type ZoneId, type ZonedDateTime}
import finance_core/time.{type Date}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{Eq}
import gleam/result
import gleam/string

pub type CloseDay {
  SameDay
  NextDay
}

pub opaque type Session {
  Session(
    label: String,
    opens_at: LocalTime,
    closes_at: LocalTime,
    close_day: CloseDay,
  )
}

pub type TradingDay {
  Closed(reason: String)
  Open(sessions: List(Session))
}

pub opaque type Calendar {
  Calendar(
    name: String,
    zone: ZoneId,
    weekly: List(#(Weekday, TradingDay)),
    overrides: List(#(Date, TradingDay)),
  )
}

pub type SessionOccurrence {
  SessionOccurrence(trading_date: Date, session: Session)
}

pub type CalendarError {
  InvalidName
  InvalidSessionLabel
  InvalidSessionRange
  EmptyOpenDay
  SessionsOutOfOrder
  SessionsOverlap
  DuplicateWeekday(weekday: Weekday)
  DuplicateOverride(date: Date)
  ZoneMismatch(expected: String, received: String)
  AmbiguousSession
}

pub fn session(
  label label: String,
  opens_at opens_at: LocalTime,
  closes_at closes_at: LocalTime,
  close_day close_day: CloseDay,
) -> Result(Session, CalendarError) {
  let open_minute = local.minutes_after_midnight(opens_at)
  let close_minute =
    local.minutes_after_midnight(closes_at)
    + case close_day {
      SameDay -> 0
      NextDay -> 1440
    }
  case
    valid_text(label),
    close_minute > open_minute,
    close_minute - open_minute <= 1440
  {
    False, _, _ -> Error(InvalidSessionLabel)
    _, False, _ -> Error(InvalidSessionRange)
    _, _, False -> Error(InvalidSessionRange)
    True, True, True -> Ok(Session(label, opens_at, closes_at, close_day))
  }
}

pub fn label(session: Session) -> String {
  session.label
}

pub fn opens_at(session: Session) -> LocalTime {
  session.opens_at
}

pub fn closes_at(session: Session) -> LocalTime {
  session.closes_at
}

pub fn close_day(session: Session) -> CloseDay {
  session.close_day
}

pub fn new(
  name name: String,
  zone zone: ZoneId,
  weekly weekly: List(#(Weekday, TradingDay)),
  overrides overrides: List(#(Date, TradingDay)),
) -> Result(Calendar, CalendarError) {
  case valid_text(name) {
    False -> Error(InvalidName)
    True -> {
      use _ <- result.try(validate_weekly(weekly, []))
      use _ <- result.try(validate_overrides(overrides, []))
      Ok(Calendar(name, zone, weekly, overrides))
    }
  }
}

pub fn name(calendar: Calendar) -> String {
  calendar.name
}

pub fn zone(calendar: Calendar) -> ZoneId {
  calendar.zone
}

pub fn trading_day(calendar: Calendar, on date_value: Date) -> TradingDay {
  case
    list.find(calendar.overrides, fn(entry) {
      date.compare(entry.0, date_value) == Eq
    })
  {
    Ok(entry) -> entry.1
    Error(_) ->
      case
        list.find(calendar.weekly, fn(entry) {
          entry.0 == date.weekday(date_value)
        })
      {
        Ok(entry) -> entry.1
        Error(_) -> Closed("weekly closure")
      }
  }
}

pub fn is_open_date(calendar: Calendar, date: Date) -> Bool {
  case trading_day(calendar, date) {
    Open(_) -> True
    Closed(_) -> False
  }
}

/// Classify local zoned time into a trading-date session.
///
/// The caller must obtain `ZonedDateTime` from a real timezone resolver. The
/// stored offset is retained evidence that daylight-saving conversion happened
/// outside this pure calendar rule layer.
pub fn session_at(
  calendar: Calendar,
  local_date_time: ZonedDateTime,
) -> Result(Option(SessionOccurrence), CalendarError) {
  let expected = local.zone_name(calendar.zone)
  let received = local.zone_name(local_date_time.zone)
  case expected == received {
    False -> Error(ZoneMismatch(expected, received))
    True -> {
      let current = matching_current(calendar, local_date_time)
      let previous = matching_previous(calendar, local_date_time)
      case list.append(current, previous) {
        [] -> Ok(None)
        [occurrence] -> Ok(Some(occurrence))
        _ -> Error(AmbiguousSession)
      }
    }
  }
}

fn validate_weekly(
  weekly: List(#(Weekday, TradingDay)),
  seen: List(Weekday),
) -> Result(Nil, CalendarError) {
  case weekly {
    [] -> Ok(Nil)
    [#(weekday, day), ..rest] ->
      case list.contains(seen, weekday) {
        True -> Error(DuplicateWeekday(weekday))
        False -> {
          use _ <- result.try(validate_day(day))
          validate_weekly(rest, [weekday, ..seen])
        }
      }
  }
}

fn validate_overrides(
  overrides: List(#(Date, TradingDay)),
  seen: List(Date),
) -> Result(Nil, CalendarError) {
  case overrides {
    [] -> Ok(Nil)
    [#(date_value, day), ..rest] ->
      case list.any(seen, fn(item) { date.compare(item, date_value) == Eq }) {
        True -> Error(DuplicateOverride(date_value))
        False -> {
          use _ <- result.try(validate_day(day))
          validate_overrides(rest, [date_value, ..seen])
        }
      }
  }
}

fn validate_day(day: TradingDay) -> Result(Nil, CalendarError) {
  case day {
    Closed(reason) ->
      case valid_text(reason) {
        True -> Ok(Nil)
        False -> Error(InvalidName)
      }
    Open([]) -> Error(EmptyOpenDay)
    Open(sessions) -> validate_sessions(sessions, None)
  }
}

fn validate_sessions(
  sessions: List(Session),
  previous_close: Option(Int),
) -> Result(Nil, CalendarError) {
  case sessions {
    [] -> Ok(Nil)
    [session, ..rest] -> {
      let open = local.minutes_after_midnight(session.opens_at)
      let close =
        local.minutes_after_midnight(session.closes_at)
        + case session.close_day {
          SameDay -> 0
          NextDay -> 1440
        }
      case previous_close {
        Some(previous) if open < previous -> Error(SessionsOverlap)
        Some(previous) if open == previous ->
          validate_sessions(rest, Some(close))
        Some(_) -> validate_sessions(rest, Some(close))
        None -> validate_sessions(rest, Some(close))
      }
    }
  }
}

fn matching_current(
  calendar: Calendar,
  value: ZonedDateTime,
) -> List(SessionOccurrence) {
  let minute = local.minutes_after_midnight(value.time)
  case trading_day(calendar, value.date) {
    Closed(_) -> []
    Open(sessions) ->
      sessions
      |> list.filter(fn(session) {
        let open = local.minutes_after_midnight(session.opens_at)
        let close = local.minutes_after_midnight(session.closes_at)
        case session.close_day {
          SameDay -> minute >= open && minute < close
          NextDay -> minute >= open
        }
      })
      |> list.map(fn(session) { SessionOccurrence(value.date, session) })
  }
}

fn matching_previous(
  calendar: Calendar,
  value: ZonedDateTime,
) -> List(SessionOccurrence) {
  case date.add_days(value.date, -1) {
    Error(_) -> []
    Ok(previous_date) -> {
      let minute = local.minutes_after_midnight(value.time)
      case trading_day(calendar, previous_date) {
        Closed(_) -> []
        Open(sessions) ->
          sessions
          |> list.filter(fn(session) {
            session.close_day == NextDay
            && minute < local.minutes_after_midnight(session.closes_at)
          })
          |> list.map(fn(session) { SessionOccurrence(previous_date, session) })
      }
    }
  }
}

fn valid_text(value: String) -> Bool {
  value != "" && string.trim(value) == value
}
