import finance_core/time
import finance_http/client
import finance_http/pool
import finance_http/rate_limit
import finance_http/request
import finance_http/response.{type Response}
import finance_http/retry
import finance_http/scheduler
import finance_http/transport.{type Cancellation, type TransportError}
import finance_market_alpaca/request as provider_request
import gleam/javascript/promise.{type Promise}
import gleam/result

type Cell(value)

pub opaque type Runtime {
  Runtime(pool: pool.Pool)
}

pub type InitError {
  InvalidRate(rate_limit.RateLimitError)
  InvalidPool(scheduler.SchedulerError)
}

pub type SendError {
  UnexpectedTarget
  RequestFailed(pool.PoolError)
}

pub fn new() -> Result(Runtime, InitError) {
  new_with(transport.send, client.cancellable_sleep, client.system_clock)
}

pub fn new_with(
  sender: client.Sender,
  sleeper: client.Sleeper,
  clock: client.Clock,
) -> Result(Runtime, InitError) {
  let now = clock()
  let assert Ok(window) = time.duration(60_000)
  let assert Ok(reset_at) = time.instant(time.unix_milliseconds(now) + 60_000)
  use state <- result.try(
    rate_limit.new(limit: 180, remaining: 180, reset_at:, window:)
    |> result.map_error(InvalidRate),
  )
  let cell = new_cell(state)
  let policy_client =
    client.new(
      retry_policy(),
      fn(req, cancel) { gated_send(cell, req, cancel, sender, sleeper, clock) },
      sleeper,
      clock,
    )
  pool.new(
    policy_client,
    maximum_in_flight: 2,
    maximum_per_origin: 2,
    maximum_waiting: 20,
  )
  |> result.map(Runtime)
  |> result.map_error(InvalidPool)
}

pub fn send(
  runtime: Runtime,
  id id: String,
  request request_value: request.Request,
  cancellation cancellation: Cancellation,
) -> Promise(Result(Response, SendError)) {
  case
    request.origin(request_value) == provider_request.origin
    && {
      request.path(request_value) == provider_request.bars_path
      || request.path(request_value) == provider_request.latest_quotes_path
    }
  {
    False -> promise.resolve(Error(UnexpectedTarget))
    True -> {
      let Runtime(pool_value) = runtime
      use outcome <- promise.await(pool.send(
        pool_value,
        id: id,
        request: request_value,
        cancellation: cancellation,
      ))
      promise.resolve(outcome |> result.map_error(RequestFailed))
    }
  }
}

fn gated_send(
  cell: Cell(rate_limit.State),
  req: request.Request,
  cancel: Cancellation,
  sender: client.Sender,
  sleeper: client.Sleeper,
  clock: client.Clock,
) -> Promise(Result(Response, TransportError)) {
  use admitted <- promise.await(admit(cell, cancel, sleeper, clock))
  case admitted {
    Error(error) -> promise.resolve(Error(error))
    Ok(Nil) -> sender(req, cancel)
  }
}

fn admit(
  cell: Cell(rate_limit.State),
  cancel: Cancellation,
  sleeper: client.Sleeper,
  clock: client.Clock,
) -> Promise(Result(Nil, TransportError)) {
  case transport.is_cancelled(cancel) {
    True -> promise.resolve(Error(transport.Cancelled))
    False -> {
      let now = clock()
      case rate_limit.acquire(read_cell(cell), now) {
        Error(_) -> promise.resolve(Error(transport.InvalidTransportResult))
        Ok(#(next, rate_limit.Permit)) -> {
          write_cell(cell, next)
          promise.resolve(Ok(Nil))
        }
        Ok(#(_, rate_limit.WaitUntil(reset))) ->
          case
            time.duration(
              time.unix_milliseconds(reset) - time.unix_milliseconds(now),
            )
          {
            Error(_) -> promise.resolve(Error(transport.InvalidTransportResult))
            Ok(wait) -> {
              use done <- promise.await(sleeper(wait, cancel))
              case done {
                False -> promise.resolve(Error(transport.Cancelled))
                True -> admit(cell, cancel, sleeper, clock)
              }
            }
          }
      }
    }
  }
}

fn retry_policy() -> retry.Policy {
  let assert Ok(elapsed) = time.duration(20_000)
  let assert Ok(base) = time.duration(250)
  let assert Ok(maximum) = time.duration(2000)
  let assert Ok(value) =
    retry.policy(
      maximum_attempts: 3,
      maximum_elapsed: elapsed,
      base_delay: base,
      maximum_delay: maximum,
    )
  value
}

@external(javascript, "./runtime_ffi.mjs", "new_cell")
fn new_cell(value: value) -> Cell(value)

@external(javascript, "./runtime_ffi.mjs", "read_cell")
fn read_cell(cell: Cell(value)) -> value

@external(javascript, "./runtime_ffi.mjs", "write_cell")
fn write_cell(cell: Cell(value), value: value) -> Nil
