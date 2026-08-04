import finance_core/time.{type Duration, type Instant}

pub opaque type ManualClock {
  ManualClock(now: Instant)
}

pub type ClockError {
  InstantOutOfRange
}

pub fn new(now: Instant) -> ManualClock {
  ManualClock(now)
}

pub fn now(clock: ManualClock) -> Instant {
  let ManualClock(now) = clock
  now
}

pub fn advance(
  clock: ManualClock,
  by duration: Duration,
) -> Result(ManualClock, ClockError) {
  let next =
    time.unix_milliseconds(now(clock)) + time.duration_milliseconds(duration)
  case time.instant(next) {
    Ok(instant) -> Ok(ManualClock(instant))
    Error(_) -> Error(InstantOutOfRange)
  }
}
