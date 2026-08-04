import finance_calendar/calendar.{type Calendar}
import finance_calendar/date
import finance_core/time.{type Date}
import gleam/int
import gleam/list
import gleam/order.{Eq, Gt}

pub type Adjustment {
  Unadjusted
  Following
  ModifiedFollowing
  Preceding
  ModifiedPreceding
}

pub type BusinessError {
  InvalidScanLimit
  InvalidRange
  SearchExhausted(last_checked: Date)
  DateFailure
}

/// Apply a named business-day convention with a finite search budget.
pub fn adjust(
  calendar: Calendar,
  date date_value: Date,
  convention convention: Adjustment,
  maximum_scan_days maximum_scan_days: Int,
) -> Result(Date, BusinessError) {
  case convention {
    Unadjusted -> Ok(date_value)
    _ ->
      case maximum_scan_days > 0 {
        False -> Error(InvalidScanLimit)
        True ->
          adjust_bounded(calendar, date_value, convention, maximum_scan_days)
      }
  }
}

pub fn add_business_days(
  calendar: Calendar,
  date date_value: Date,
  days days: Int,
  maximum_scan_days maximum_scan_days: Int,
) -> Result(Date, BusinessError) {
  case days {
    0 -> Ok(date_value)
    _ if maximum_scan_days <= 0 -> Error(InvalidScanLimit)
    _ -> {
      let direction = case days > 0 {
        True -> 1
        False -> -1
      }
      walk_business_days(
        calendar,
        date_value,
        int.absolute_value(days),
        direction,
        maximum_scan_days,
      )
    }
  }
}

/// Enumerate open dates inclusively with a finite calendar-day scan budget.
pub fn open_dates_between(
  calendar: Calendar,
  start start: Date,
  end end: Date,
  maximum_scan_days maximum_scan_days: Int,
) -> Result(List(Date), BusinessError) {
  case maximum_scan_days > 0, date.compare(start, end) {
    False, _ -> Error(InvalidScanLimit)
    _, Gt -> Error(InvalidRange)
    True, _ -> collect_open_dates(calendar, start, end, maximum_scan_days, [])
  }
}

fn adjust_bounded(
  calendar: Calendar,
  date_value: Date,
  convention: Adjustment,
  maximum_scan_days: Int,
) -> Result(Date, BusinessError) {
  case calendar.is_open_date(calendar, date_value) {
    True -> Ok(date_value)
    False ->
      case convention {
        Following -> search(calendar, date_value, 1, maximum_scan_days)
        Preceding -> search(calendar, date_value, -1, maximum_scan_days)
        ModifiedFollowing ->
          case search(calendar, date_value, 1, maximum_scan_days) {
            Error(error) -> Error(error)
            Ok(following) ->
              case same_month(date_value, following) {
                True -> Ok(following)
                False -> search(calendar, date_value, -1, maximum_scan_days)
              }
          }
        ModifiedPreceding ->
          case search(calendar, date_value, -1, maximum_scan_days) {
            Error(error) -> Error(error)
            Ok(preceding) ->
              case same_month(date_value, preceding) {
                True -> Ok(preceding)
                False -> search(calendar, date_value, 1, maximum_scan_days)
              }
          }
        Unadjusted -> Ok(date_value)
      }
  }
}

fn search(
  calendar: Calendar,
  from: Date,
  direction: Int,
  remaining_scan_days: Int,
) -> Result(Date, BusinessError) {
  case date.add_days(from, direction) {
    Error(_) -> Error(DateFailure)
    Ok(candidate) ->
      case
        calendar.is_open_date(calendar, candidate),
        remaining_scan_days == 1
      {
        True, _ -> Ok(candidate)
        False, True -> Error(SearchExhausted(candidate))
        False, False ->
          search(calendar, candidate, direction, remaining_scan_days - 1)
      }
  }
}

fn walk_business_days(
  calendar: Calendar,
  from: Date,
  remaining_business_days: Int,
  direction: Int,
  remaining_scan_days: Int,
) -> Result(Date, BusinessError) {
  case date.add_days(from, direction) {
    Error(_) -> Error(DateFailure)
    Ok(candidate) -> {
      let next_remaining = case calendar.is_open_date(calendar, candidate) {
        True -> remaining_business_days - 1
        False -> remaining_business_days
      }
      case next_remaining == 0, remaining_scan_days == 1 {
        True, _ -> Ok(candidate)
        False, True -> Error(SearchExhausted(candidate))
        False, False ->
          walk_business_days(
            calendar,
            candidate,
            next_remaining,
            direction,
            remaining_scan_days - 1,
          )
      }
    }
  }
}

fn same_month(left: Date, right: Date) -> Bool {
  let #(left_year, left_month, _) = time.date_parts(left)
  let #(right_year, right_month, _) = time.date_parts(right)
  left_year == right_year && left_month == right_month
}

fn collect_open_dates(
  calendar: Calendar,
  current: Date,
  end: Date,
  remaining_scan_days: Int,
  open_reversed: List(Date),
) -> Result(List(Date), BusinessError) {
  let next_open_reversed = case calendar.is_open_date(calendar, current) {
    True -> [current, ..open_reversed]
    False -> open_reversed
  }
  case date.compare(current, end), remaining_scan_days == 1 {
    Eq, _ -> Ok(list.reverse(next_open_reversed))
    _, True -> Error(SearchExhausted(current))
    _, False ->
      case date.add_days(current, 1) {
        Error(_) -> Error(DateFailure)
        Ok(next) ->
          collect_open_dates(
            calendar,
            next,
            end,
            remaining_scan_days - 1,
            next_open_reversed,
          )
      }
  }
}
