import finance_core/time.{type Duration, type Instant}

pub opaque type State {
  State(limit: Int, remaining: Int, reset_at: Instant, window: Duration)
}

pub type RateLimitError {
  NonPositiveLimit
  InvalidRemaining
  ResetOverflow
}

pub type Decision {
  Permit
  WaitUntil(Instant)
}

pub fn new(
  limit limit: Int,
  remaining remaining: Int,
  reset_at reset_at: Instant,
  window window: Duration,
) -> Result(State, RateLimitError) {
  case limit > 0, remaining >= 0 && remaining <= limit {
    False, _ -> Error(NonPositiveLimit)
    _, False -> Error(InvalidRemaining)
    True, True -> Ok(State(limit, remaining, reset_at, window))
  }
}

pub fn remaining(state: State) -> Int {
  let State(_, remaining, _, _) = state
  remaining
}

pub fn reset_at(state: State) -> Instant {
  let State(_, _, reset_at, _) = state
  reset_at
}

pub fn acquire(
  state: State,
  now: Instant,
) -> Result(#(State, Decision), RateLimitError) {
  let State(limit, remaining, reset_at, window) = state
  case time.unix_milliseconds(now) >= time.unix_milliseconds(reset_at) {
    True -> {
      let next_reset =
        time.unix_milliseconds(now) + time.duration_milliseconds(window)
      case time.instant(next_reset) {
        Error(_) -> Error(ResetOverflow)
        Ok(next_reset) ->
          Ok(#(State(limit, limit - 1, next_reset, window), Permit))
      }
    }
    False ->
      case remaining > 0 {
        True -> Ok(#(State(limit, remaining - 1, reset_at, window), Permit))
        False -> Ok(#(state, WaitUntil(reset_at)))
      }
  }
}

pub fn observe(
  state: State,
  remaining remaining: Int,
  reset_at reset_at: Instant,
) -> Result(State, RateLimitError) {
  let State(limit, _, _, window) = state
  new(limit: limit, remaining: remaining, reset_at: reset_at, window: window)
}
