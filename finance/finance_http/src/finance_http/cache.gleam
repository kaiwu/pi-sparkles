import finance_core/time.{type Duration, type Instant}
import gleam/int
import gleam/option.{type Option, None, Some}

pub opaque type Entry(value) {
  Entry(value: value, stored_at: Instant, expires_at: Instant)
}

pub type EntryError {
  ExpiryBeforeStorage
}

pub type Mode {
  Bypass
  ReadThrough
  Revalidate
  OfflineOnly
}

pub type Decision(value) {
  Fetch
  UseFresh(value: value, age: Duration)
  RevalidateStale(value: value, age: Duration)
  UseStaleOffline(value: value, age: Duration)
  OfflineMiss
}

pub fn entry(
  value value: value,
  stored_at stored_at: Instant,
  expires_at expires_at: Instant,
) -> Result(Entry(value), EntryError) {
  case time.unix_milliseconds(expires_at) < time.unix_milliseconds(stored_at) {
    True -> Error(ExpiryBeforeStorage)
    False -> Ok(Entry(value, stored_at, expires_at))
  }
}

pub fn decide(
  mode: Mode,
  entry: Option(Entry(value)),
  now: Instant,
) -> Decision(value) {
  case mode, entry {
    Bypass, _ -> Fetch
    OfflineOnly, None -> OfflineMiss
    ReadThrough, None | Revalidate, None -> Fetch
    _, Some(Entry(value, stored_at, expires_at)) -> {
      let age = age(now, stored_at)
      case time.unix_milliseconds(now) <= time.unix_milliseconds(expires_at) {
        True -> UseFresh(value, age)
        False ->
          case mode {
            Bypass | ReadThrough -> Fetch
            Revalidate -> RevalidateStale(value, age)
            OfflineOnly -> UseStaleOffline(value, age)
          }
      }
    }
  }
}

fn age(now: Instant, stored_at: Instant) -> Duration {
  let milliseconds =
    int.max(time.unix_milliseconds(now) - time.unix_milliseconds(stored_at), 0)
  let assert Ok(duration) = time.duration(milliseconds)
  duration
}
