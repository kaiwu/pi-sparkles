import finance_calendar/calendar as market_calendar
import finance_core/time.{type Date}
import gleam/list

pub type Rule {
  AllOpen
  AnyOpen
}

pub opaque type JointCalendar {
  JointCalendar(calendars: List(market_calendar.Calendar), rule: Rule)
}

pub type JointError {
  EmptyCalendars
}

pub fn new(
  calendars calendars: List(market_calendar.Calendar),
  rule rule: Rule,
) -> Result(JointCalendar, JointError) {
  case calendars {
    [] -> Error(EmptyCalendars)
    _ -> Ok(JointCalendar(calendars, rule))
  }
}

pub fn is_open_date(joint: JointCalendar, date date_value: Date) -> Bool {
  let JointCalendar(calendars, rule) = joint
  case rule {
    AllOpen ->
      list.all(calendars, fn(item) {
        market_calendar.is_open_date(item, date_value)
      })
    AnyOpen ->
      list.any(calendars, fn(item) {
        market_calendar.is_open_date(item, date_value)
      })
  }
}
