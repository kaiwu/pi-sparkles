import finance_authority_snapshot/runtime as bounded_runtime
import finance_core/time
import finance_http/client
import finance_http/pool
import finance_http/request as http_request
import finance_http/response.{type Response}
import finance_http/transport.{type Cancellation}
import finance_tushare.{type Access}
import finance_tushare/request
import gleam/javascript/promise.{type Promise}
import gleam/result

pub opaque type Runtime {
  Runtime(inner: bounded_runtime.Runtime)
}

pub type InitError {
  InvalidRuntime(bounded_runtime.InitError)
}

pub type SendError {
  UnexpectedEndpoint
  RequestFailed(pool.PoolError)
}

pub fn new(_access: Access) -> Result(Runtime, InitError) {
  bounded_runtime.new(policy())
  |> result.map(Runtime)
  |> result.map_error(InvalidRuntime)
}

pub fn new_with(
  _access: Access,
  sender: client.Sender,
  sleeper: client.Sleeper,
  clock: client.Clock,
) -> Result(Runtime, InitError) {
  bounded_runtime.new_with(policy(), sender, sleeper, clock)
  |> result.map(Runtime)
  |> result.map_error(InvalidRuntime)
}

pub fn send(
  runtime: Runtime,
  id id: String,
  request_value request_value: http_request.Request,
  cancellation cancellation: Cancellation,
) -> Promise(Result(Response, SendError)) {
  case
    http_request.origin(request_value) == request.origin
    && http_request.path(request_value) == request.path
  {
    False -> promise.resolve(Error(UnexpectedEndpoint))
    True -> {
      use outcome <- promise.await(bounded_runtime.send(
        runtime.inner,
        id,
        request_value,
        cancellation,
      ))
      promise.resolve(outcome |> result.map_error(RequestFailed))
    }
  }
}

fn policy() -> bounded_runtime.Policy {
  let assert Ok(window) = time.duration(1000)
  let assert Ok(maximum_elapsed) = time.duration(15_000)
  let assert Ok(base_delay) = time.duration(500)
  let assert Ok(maximum_delay) = time.duration(2000)
  let assert Ok(value) =
    bounded_runtime.policy(
      origin: request.origin,
      allowed_paths: [request.path],
      admissions_per_window: 1,
      window: window,
      maximum_in_flight: 1,
      maximum_waiting: 20,
      maximum_attempts: 2,
      maximum_elapsed: maximum_elapsed,
      base_delay: base_delay,
      maximum_delay: maximum_delay,
    )
  value
}
