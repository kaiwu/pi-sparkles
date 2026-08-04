import finance_core/time as core_time

pub type ZoneId =
  core_time.Timezone

pub type LocalTime =
  core_time.TimeOfDay

pub type ZonedDateTime {
  ZonedDateTime(
    date: core_time.Date,
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
  case core_time.timezone(name) {
    Ok(value) -> Ok(value)
    Error(_) -> Error(InvalidZoneId)
  }
}

pub fn zone_name(zone: ZoneId) -> String {
  core_time.timezone_name(zone)
}

pub fn local_time(hour: Int, minute: Int) -> Result(LocalTime, LocalError) {
  case core_time.time_of_day(hour, minute) {
    Ok(value) -> Ok(value)
    Error(core_time.InvalidHour) -> Error(InvalidHour)
    Error(_) -> Error(InvalidMinute)
  }
}

pub fn time_parts(time: LocalTime) -> #(Int, Int) {
  core_time.time_of_day_parts(time)
}

pub fn minutes_after_midnight(time: LocalTime) -> Int {
  core_time.minutes_after_midnight(time)
}

pub fn zoned_date_time(
  date date: core_time.Date,
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
