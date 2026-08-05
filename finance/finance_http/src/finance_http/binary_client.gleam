import finance_core/time
import finance_http/binary_response.{type Response}
import finance_http/client.{type Clock, type Sleeper, type StatusAcceptor}
import finance_http/request.{type Request}
import finance_http/response
import finance_http/retry.{type Policy, type StopReason}
import finance_http/retry_after
import finance_http/transport.{type Cancellation, type TransportError}
import gleam/javascript/promise.{type Promise}
import gleam/option

pub type Sender =
  fn(Request, Cancellation) -> Promise(Result(Response, TransportError))

pub opaque type Client {
  Client(
    policy: Policy,
    sender: Sender,
    sleeper: Sleeper,
    clock: Clock,
    accepts: StatusAcceptor,
  )
}

pub type SafeFailure {
  TransportFailure(error: TransportError)
  StatusFailure(summary: response.SafeSummary)
}

pub type ClientError {
  Cancelled
  RetryStopped(reason: StopReason, attempts: Int, last: SafeFailure)
}

pub fn new(
  policy policy: Policy,
  sender sender: Sender,
  sleeper sleeper: Sleeper,
  clock clock: Clock,
) -> Client {
  Client(policy, sender, sleeper, clock, successful_status)
}

/// Construct the byte-preserving interpreter used for bounded authority
/// artifacts such as PDFs and ZIP archives.
pub fn default(policy: Policy) -> Client {
  new(
    policy,
    transport.send_binary,
    client.cancellable_sleep,
    client.system_clock,
  )
}

pub fn with_status_acceptor(
  client: Client,
  accepts accepts: StatusAcceptor,
) -> Client {
  let Client(policy, sender, sleeper, clock, _) = client
  Client(policy, sender, sleeper, clock, accepts)
}

pub fn send(
  client: Client,
  request request_value: Request,
  cancellation cancellation: Cancellation,
) -> Promise(Result(Response, ClientError)) {
  let Client(_, _, _, clock, _) = client
  case transport.is_cancelled(cancellation) {
    True -> promise.resolve(Error(Cancelled))
    False -> attempt(client, request_value, cancellation, 1, clock())
  }
}

fn attempt(
  client: Client,
  request_value: Request,
  cancellation: Cancellation,
  attempt_number: Int,
  started_at: time.Instant,
) -> Promise(Result(Response, ClientError)) {
  let Client(_, sender, _, clock, accepts) = client
  use outcome <- promise.await(sender(request_value, cancellation))
  let now = clock()
  let elapsed = elapsed_since(started_at, now)
  case outcome {
    Ok(response_value) ->
      case accepts(binary_response.status(response_value)) {
        True -> promise.resolve(Ok(response_value))
        False -> {
          let retry_after =
            binary_response.first_header(response_value, name: "retry-after")
            |> option.then(fn(value) { retry_after.parse(value, now) })
          retry_or_stop(
            client,
            request_value,
            cancellation,
            attempt_number,
            started_at,
            elapsed,
            retry.Status(binary_response.status(response_value), retry_after),
            StatusFailure(binary_response.safe_summary(response_value)),
          )
        }
      }
    Error(transport.Cancelled) -> promise.resolve(Error(Cancelled))
    Error(error) ->
      retry_or_stop(
        client,
        request_value,
        cancellation,
        attempt_number,
        started_at,
        elapsed,
        retry.Transport(retry_transport_failure(error)),
        TransportFailure(error),
      )
  }
}

fn retry_or_stop(
  client: Client,
  request_value: Request,
  cancellation: Cancellation,
  attempt_number: Int,
  started_at: time.Instant,
  elapsed: time.Duration,
  failure: retry.Failure,
  safe_failure: SafeFailure,
) -> Promise(Result(Response, ClientError)) {
  let Client(policy, _, sleeper, _, _) = client
  case retry.decide(policy, request_value, attempt_number, elapsed, failure) {
    retry.Stop(reason) ->
      promise.resolve(Error(RetryStopped(reason, attempt_number, safe_failure)))
    retry.RetryAfter(delay, next_attempt) -> {
      use completed <- promise.await(sleeper(delay, cancellation))
      case completed {
        False -> promise.resolve(Error(Cancelled))
        True ->
          attempt(client, request_value, cancellation, next_attempt, started_at)
      }
    }
  }
}

fn retry_transport_failure(error: TransportError) -> retry.TransportFailure {
  case error {
    transport.Timeout -> retry.Timeout
    transport.NetworkFailure -> retry.NetworkUnavailable
    transport.ResponseTooLarge(_)
    | transport.InvalidTransportResult
    | transport.InvalidResponse(_)
    | transport.InvalidBinaryResponse(_) -> retry.InvalidResponse
    transport.Cancelled -> retry.NetworkUnavailable
  }
}

fn successful_status(status: Int) -> Bool {
  status >= 200 && status <= 299
}

fn elapsed_since(started_at: time.Instant, now: time.Instant) -> time.Duration {
  let difference =
    time.unix_milliseconds(now) - time.unix_milliseconds(started_at)
  let normalized = case difference < 0 {
    True -> 0
    False -> difference
  }
  case time.duration(normalized) {
    Ok(elapsed) -> elapsed
    Error(_) -> {
      let assert Ok(maximum) = time.duration(8_640_000_000_000_000)
      maximum
    }
  }
}
