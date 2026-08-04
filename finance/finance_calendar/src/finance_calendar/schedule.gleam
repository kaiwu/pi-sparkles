import finance_calendar/business.{type Adjustment, type BusinessError}
import finance_calendar/calendar.{type Calendar}
import finance_calendar/date
import finance_core/time.{type Date}
import gleam/list
import gleam/order.{Eq, Gt, Lt}

pub type StubRule {
  NoStub
  ShortFirst
  ShortLast
  LongFirst
  LongLast
}

pub type Schedule {
  Schedule(dates: List(Date), stub: StubRule, end_of_month: Bool)
}

pub type ScheduleError {
  InvalidRange
  InvalidMonths
  InvalidPeriodLimit
  PeriodLimitExceeded
  StubRequired
  DateFailure
  BusinessAdjustmentFailed(error: BusinessError)
}

/// Generate an immutable boundary schedule including start and end.
///
/// `maximum_periods` is a hard termination budget. End-of-month preservation
/// anchors every date to the relevant month end instead of drifting after
/// February.
pub fn generate(
  start start: Date,
  end end: Date,
  months months: Int,
  stub stub_rule: StubRule,
  preserve_end_of_month preserve_eom: Bool,
  maximum_periods maximum_periods: Int,
) -> Result(Schedule, ScheduleError) {
  case date.compare(start, end), months > 0, maximum_periods > 0 {
    Eq, _, _ -> Error(InvalidRange)
    Gt, _, _ -> Error(InvalidRange)
    _, False, _ -> Error(InvalidMonths)
    _, _, False -> Error(InvalidPeriodLimit)
    Lt, True, True -> {
      let generated = case stub_rule {
        ShortFirst | LongFirst ->
          backward(start, end, months, preserve_eom, maximum_periods, 1, [end])
        _ ->
          forward(start, end, months, preserve_eom, maximum_periods, 1, [start])
      }
      case generated {
        Error(error) -> Error(error)
        Ok(#(dates, irregular)) ->
          case stub_rule, irregular {
            NoStub, True -> Error(StubRequired)
            LongFirst, True ->
              Ok(Schedule(remove_second(dates), stub_rule, preserve_eom))
            LongLast, True ->
              Ok(Schedule(remove_penultimate(dates), stub_rule, preserve_eom))
            _, _ -> Ok(Schedule(dates, stub_rule, preserve_eom))
          }
      }
    }
  }
}

pub fn adjust_payments(
  schedule: Schedule,
  calendar calendar_value: Calendar,
  convention convention: Adjustment,
  maximum_scan_days_per_date maximum_scan_days: Int,
) -> Result(Schedule, ScheduleError) {
  let Schedule(dates, stub, end_of_month) = schedule
  case
    list.try_map(dates, fn(value) {
      business.adjust(
        calendar_value,
        date: value,
        convention: convention,
        maximum_scan_days: maximum_scan_days,
      )
      |> map_business_error
    })
  {
    Ok(adjusted) -> Ok(Schedule(adjusted, stub, end_of_month))
    Error(error) -> Error(error)
  }
}

fn forward(
  start: Date,
  end: Date,
  months: Int,
  preserve_eom: Bool,
  maximum: Int,
  index: Int,
  reversed: List(Date),
) -> Result(#(List(Date), Bool), ScheduleError) {
  case index > maximum {
    True -> Error(PeriodLimitExceeded)
    False ->
      case
        shifted(
          start,
          months * index,
          preserve_eom && date.is_end_of_month(start),
        )
      {
        Error(error) -> Error(error)
        Ok(candidate) ->
          case date.compare(candidate, end) {
            Eq -> Ok(#(list.reverse([end, ..reversed]), False))
            Gt -> Ok(#(list.reverse([end, ..reversed]), True))
            Lt ->
              forward(start, end, months, preserve_eom, maximum, index + 1, [
                candidate,
                ..reversed
              ])
          }
      }
  }
}

fn backward(
  start: Date,
  end: Date,
  months: Int,
  preserve_eom: Bool,
  maximum: Int,
  index: Int,
  accumulated: List(Date),
) -> Result(#(List(Date), Bool), ScheduleError) {
  case index > maximum {
    True -> Error(PeriodLimitExceeded)
    False ->
      case
        shifted(
          end,
          0 - months * index,
          preserve_eom && date.is_end_of_month(end),
        )
      {
        Error(error) -> Error(error)
        Ok(candidate) ->
          case date.compare(candidate, start) {
            Eq -> Ok(#([start, ..accumulated], False))
            Lt -> Ok(#([start, ..accumulated], True))
            Gt ->
              backward(start, end, months, preserve_eom, maximum, index + 1, [
                candidate,
                ..accumulated
              ])
          }
      }
  }
}

fn shifted(
  anchor: Date,
  months: Int,
  preserve_eom: Bool,
) -> Result(Date, ScheduleError) {
  case date.add_months(anchor, months, date.ClampDay) {
    Error(_) -> Error(DateFailure)
    Ok(candidate) ->
      case preserve_eom {
        False -> Ok(candidate)
        True -> {
          let #(year, month, _) = time.date_parts(candidate)
          case time.date(year, month, date.days_in_month(year, month)) {
            Ok(value) -> Ok(value)
            Error(_) -> Error(DateFailure)
          }
        }
      }
  }
}

fn remove_second(values: List(value)) -> List(value) {
  case values {
    [first, _, ..rest] -> [first, ..rest]
    _ -> values
  }
}

fn remove_penultimate(values: List(value)) -> List(value) {
  values |> list.reverse |> remove_second |> list.reverse
}

fn map_business_error(
  result: Result(value, BusinessError),
) -> Result(value, ScheduleError) {
  case result {
    Ok(value) -> Ok(value)
    Error(error) -> Error(BusinessAdjustmentFailed(error))
  }
}
