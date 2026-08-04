import finance_core/time.{type Duration}
import finance_http/request.{type Request}
import gleam/int
import gleam/option.{type Option, Some}

pub opaque type Policy {
  Policy(
    maximum_attempts: Int,
    maximum_elapsed: Duration,
    base_delay: Duration,
    maximum_delay: Duration,
  )
}

pub type PolicyError {
  NonPositiveAttempts
  DelayExceedsMaximum
}

pub type TransportFailure {
  Timeout
  NetworkUnavailable
  DnsFailure
  ConnectionReset
  CertificateFailure
  InvalidResponse
}

pub type Failure {
  Transport(TransportFailure)
  Status(code: Int, retry_after: Option(Duration))
}

pub type StopReason {
  InvalidAttempt
  NonIdempotentRequest
  PermanentFailure
  AttemptsExhausted
  ElapsedBudgetExhausted
}

pub type Decision {
  RetryAfter(delay: Duration, next_attempt: Int)
  Stop(reason: StopReason)
}

pub fn policy(
  maximum_attempts maximum_attempts: Int,
  maximum_elapsed maximum_elapsed: Duration,
  base_delay base_delay: Duration,
  maximum_delay maximum_delay: Duration,
) -> Result(Policy, PolicyError) {
  case
    maximum_attempts > 0,
    time.duration_milliseconds(base_delay)
    <= time.duration_milliseconds(maximum_delay)
  {
    False, _ -> Error(NonPositiveAttempts)
    _, False -> Error(DelayExceedsMaximum)
    True, True ->
      Ok(Policy(maximum_attempts, maximum_elapsed, base_delay, maximum_delay))
  }
}

pub fn decide(
  policy: Policy,
  request: Request,
  completed_attempt: Int,
  elapsed: Duration,
  failure: Failure,
) -> Decision {
  let Policy(maximum_attempts, maximum_elapsed, base_delay, maximum_delay) =
    policy
  case completed_attempt <= 0 {
    True -> Stop(InvalidAttempt)
    False ->
      case request.can_retry(request) {
        False -> Stop(NonIdempotentRequest)
        True ->
          case retryable(failure) {
            False -> Stop(PermanentFailure)
            True ->
              case completed_attempt >= maximum_attempts {
                True -> Stop(AttemptsExhausted)
                False ->
                  case
                    time.duration_milliseconds(elapsed)
                    >= time.duration_milliseconds(maximum_elapsed)
                  {
                    True -> Stop(ElapsedBudgetExhausted)
                    False -> {
                      let delay =
                        delay_for(
                          failure,
                          completed_attempt,
                          base_delay,
                          maximum_delay,
                        )
                      case
                        time.duration_milliseconds(elapsed)
                        + time.duration_milliseconds(delay)
                        > time.duration_milliseconds(maximum_elapsed)
                      {
                        True -> Stop(ElapsedBudgetExhausted)
                        False -> RetryAfter(delay, completed_attempt + 1)
                      }
                    }
                  }
              }
          }
      }
  }
}

pub fn retryable(failure: Failure) -> Bool {
  case failure {
    Transport(CertificateFailure) | Transport(InvalidResponse) -> False
    Transport(_) -> True
    Status(408, _) | Status(425, _) | Status(429, _) -> True
    Status(code, _) -> code >= 500 && code <= 599
  }
}

fn delay_for(
  failure: Failure,
  completed_attempt: Int,
  base_delay: Duration,
  maximum_delay: Duration,
) -> Duration {
  case failure {
    Status(_, Some(retry_after)) -> minimum_duration(retry_after, maximum_delay)
    _ -> exponential_delay(base_delay, maximum_delay, completed_attempt - 1)
  }
}

fn exponential_delay(
  current: Duration,
  maximum: Duration,
  doublings: Int,
) -> Duration {
  case doublings <= 0 {
    True -> current
    False -> {
      let current_ms = time.duration_milliseconds(current)
      let maximum_ms = time.duration_milliseconds(maximum)
      let doubled = int.min(current_ms * 2, maximum_ms)
      let assert Ok(next) = time.duration(doubled)
      exponential_delay(next, maximum, doublings - 1)
    }
  }
}

fn minimum_duration(left: Duration, right: Duration) -> Duration {
  case time.duration_milliseconds(left) <= time.duration_milliseconds(right) {
    True -> left
    False -> right
  }
}
