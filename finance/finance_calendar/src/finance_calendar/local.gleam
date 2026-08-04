import finance_core/time.{type Date}
import gleam/string

pub opaque type ZoneId {
  ZoneId(name: String)
}

pub opaque type LocalTime {
  LocalTime(minutes_after_midnight: Int)
}

pub type ZonedDateTime {
  ZonedDateTime(
    date: Date,
    time: LocalTime,
    zone: ZoneId,
    utc_offset_minutes: Int,
  )
}

pub type LocalError {
  InvalidZoneId
  InvalidHour
  InvalidMinute
  InvalidUtcOffset
}

pub fn zone_id(name: String) -> Result(ZoneId, LocalError) {
  case
    name != ""
    && string.trim(name) == name
    && { name == "UTC" || string.contains(name, "/") }
    && !string.contains(name, " ")
  {
    True -> Ok(ZoneId(name))
    False -> Error(InvalidZoneId)
  }
}

pub fn zone_name(zone: ZoneId) -> String {
  let ZoneId(name) = zone
  name
}

pub fn local_time(hour: Int, minute: Int) -> Result(LocalTime, LocalError) {
  case hour >= 0 && hour <= 23, minute >= 0 && minute <= 59 {
    False, _ -> Error(InvalidHour)
    _, False -> Error(InvalidMinute)
    True, True -> Ok(LocalTime(hour * 60 + minute))
  }
}

pub fn time_parts(time: LocalTime) -> #(Int, Int) {
  let LocalTime(minutes) = time
  #(minutes / 60, minutes % 60)
}

pub fn minutes_after_midnight(time: LocalTime) -> Int {
  let LocalTime(minutes) = time
  minutes
}

pub fn zoned_date_time(
  date date: Date,
  time time: LocalTime,
  zone zone: ZoneId,
  utc_offset_minutes utc_offset_minutes: Int,
) -> Result(ZonedDateTime, LocalError) {
  // IANA offsets currently fit inside -12:00..+14:00. The wider symmetric
  // bound admits historical offsets while rejecting malformed minute counts.
  case utc_offset_minutes >= -840 && utc_offset_minutes <= 840 {
    True -> Ok(ZonedDateTime(date, time, zone, utc_offset_minutes))
    False -> Error(InvalidUtcOffset)
  }
}
