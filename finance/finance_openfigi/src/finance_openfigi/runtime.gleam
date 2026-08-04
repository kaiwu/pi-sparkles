import finance_core/time
import finance_http/client
import finance_http/pool
import finance_http/rate_limit
import finance_http/request
import finance_http/response.{type Response}
import finance_http/retry
import finance_http/scheduler
import finance_http/transport.{type Cancellation, type TransportError}
import finance_openfigi.{type Access, type Endpoint}
import gleam/javascript/promise.{type Promise}
import gleam/result

type Cell(value)

pub opaque type Runtime {
  Runtime(pool: pool.Pool)
}

pub type InitError {
  InvalidMappingRate(finance_openfigi.LimitError)
  InvalidSearchRate(finance_openfigi.LimitError)
  InvalidPool(scheduler.SchedulerError)
}

pub fn new(access: Access) -> Result(Runtime, InitError) {
  new_with(
    access,
    transport.send,
    client.cancellable_sleep,
    client.system_clock,
  )
}

/// Construct a runtime from explicit effects for deterministic interpreters.
pub fn new_with(
  access: Access,
  sender: client.Sender,
  sleeper: client.Sleeper,
  clock: client.Clock,
) -> Result(Runtime, InitError) {
  let now = clock()
  use mapping_rate <- result.try(
    finance_openfigi.initial_rate_state(access, finance_openfigi.Mapping, now)
    |> result.map_error(InvalidMappingRate),
  )
  use search_rate <- result.try(
    finance_openfigi.initial_rate_state(access, finance_openfigi.Search, now)
    |> result.map_error(InvalidSearchRate),
  )
  let mapping_cell = new_cell(mapping_rate)
  let search_cell = new_cell(search_rate)
  let policy_client =
    client.new(
      retry_policy(),
      fn(request_value, cancellation) {
        gated_send(
          mapping_cell,
          search_cell,
          request_value,
          cancellation,
          sender,
          sleeper,
          clock,
        )
      },
      sleeper,
      clock,
    )
  pool.new(
    policy_client,
    maximum_in_flight: 1,
    maximum_per_origin: 1,
    maximum_waiting: 100,
  )
  |> result.map(Runtime)
  |> result.map_error(InvalidPool)
}

pub fn send(
  runtime: Runtime,
  id id: String,
  request request_value: request.Request,
  cancellation cancellation: Cancellation,
) -> Promise(Result(Response, pool.PoolError)) {
  let Runtime(pool_value) = runtime
  pool.send(
    pool_value,
    id: id,
    request: request_value,
    cancellation: cancellation,
  )
}

fn gated_send(
  mapping_cell: Cell(rate_limit.State),
  search_cell: Cell(rate_limit.State),
  request_value: request.Request,
  cancellation: Cancellation,
  sender: client.Sender,
  sleeper: client.Sleeper,
  clock: client.Clock,
) -> Promise(Result(Response, TransportError)) {
  case endpoint(request.path(request_value)) {
    Error(_) -> promise.resolve(Error(transport.InvalidTransportResult))
    Ok(endpoint_value) -> {
      let cell = case endpoint_value {
        finance_openfigi.Mapping -> mapping_cell
        finance_openfigi.Search -> search_cell
      }
      use admitted <- promise.await(admit(cell, cancellation, sleeper, clock))
      case admitted {
        Error(error) -> promise.resolve(Error(error))
        Ok(Nil) -> sender(request_value, cancellation)
      }
    }
  }
}

fn admit(
  cell: Cell(rate_limit.State),
  cancellation: Cancellation,
  sleeper: client.Sleeper,
  clock: client.Clock,
) -> Promise(Result(Nil, TransportError)) {
  case transport.is_cancelled(cancellation) {
    True -> promise.resolve(Error(transport.Cancelled))
    False -> {
      let now = clock()
      case rate_limit.acquire(read_cell(cell), now) {
        Error(_) -> promise.resolve(Error(transport.InvalidTransportResult))
        Ok(#(next, rate_limit.Permit)) -> {
          write_cell(cell, next)
          promise.resolve(Ok(Nil))
        }
        Ok(#(_, rate_limit.WaitUntil(reset_at))) -> {
          let wait_milliseconds =
            time.unix_milliseconds(reset_at) - time.unix_milliseconds(now)
          case time.duration(wait_milliseconds) {
            Error(_) -> promise.resolve(Error(transport.InvalidTransportResult))
            Ok(duration) -> {
              use completed <- promise.await(sleeper(duration, cancellation))
              case completed {
                False -> promise.resolve(Error(transport.Cancelled))
                True -> admit(cell, cancellation, sleeper, clock)
              }
            }
          }
        }
      }
    }
  }
}

fn endpoint(path: String) -> Result(Endpoint, Nil) {
  case path {
    "/v3/mapping" -> Ok(finance_openfigi.Mapping)
    "/v3/filter" -> Ok(finance_openfigi.Search)
    _ -> Error(Nil)
  }
}

fn retry_policy() -> retry.Policy {
  let assert Ok(maximum_elapsed) = time.duration(12_000)
  let assert Ok(base_delay) = time.duration(500)
  let assert Ok(maximum_delay) = time.duration(4000)
  let assert Ok(policy) =
    retry.policy(
      maximum_attempts: 3,
      maximum_elapsed: maximum_elapsed,
      base_delay: base_delay,
      maximum_delay: maximum_delay,
    )
  policy
}

@external(javascript, "./runtime_ffi.mjs", "new_cell")
fn new_cell(value: value) -> Cell(value)

@external(javascript, "./runtime_ffi.mjs", "read_cell")
fn read_cell(cell: Cell(value)) -> value

@external(javascript, "./runtime_ffi.mjs", "write_cell")
fn write_cell(cell: Cell(value), value: value) -> Nil
