import finance_authority_snapshot/runtime as authority_runtime
import finance_core/time
import finance_http/client
import finance_http/pool
import finance_http/request.{type Request}
import finance_http/response.{type Response}
import finance_http/transport.{type Cancellation}
import finance_sfc.{type Access}
import finance_sfc/request as sfc_request
import gleam/javascript/promise.{type Promise}

pub opaque type Runtime {
  Runtime(inner: authority_runtime.Runtime)
}

pub type InitError {
  InvalidRuntime(authority_runtime.InitError)
}

pub fn new(_access: Access) -> Result(Runtime, InitError) {
  authority_runtime.new(policy())
  |> map_result(Runtime, InvalidRuntime)
}

pub fn new_with(
  _access: Access,
  sender: client.Sender,
  sleeper: client.Sleeper,
  clock: client.Clock,
) -> Result(Runtime, InitError) {
  authority_runtime.new_with(policy(), sender, sleeper, clock)
  |> map_result(Runtime, InvalidRuntime)
}

pub fn send(
  runtime: Runtime,
  id id: String,
  request request_value: Request,
  cancellation cancellation: Cancellation,
) -> Promise(Result(Response, pool.PoolError)) {
  authority_runtime.send(runtime.inner, id, request_value, cancellation)
}

fn policy() -> authority_runtime.Policy {
  let assert Ok(window) = time.duration(1000)
  let assert Ok(maximum_elapsed) = time.duration(15_000)
  let assert Ok(base_delay) = time.duration(500)
  let assert Ok(maximum_delay) = time.duration(2000)
  let assert Ok(value) =
    authority_runtime.policy(
      origin: sfc_request.origin,
      allowed_paths: [sfc_request.press_releases_path],
      admissions_per_window: 1,
      window: window,
      maximum_in_flight: 1,
      maximum_waiting: 50,
      maximum_attempts: 2,
      maximum_elapsed: maximum_elapsed,
      base_delay: base_delay,
      maximum_delay: maximum_delay,
    )
  value
}

fn map_result(
  value: Result(a, e),
  success: fn(a) -> b,
  failure: fn(e) -> f,
) -> Result(b, f) {
  case value {
    Ok(value) -> Ok(success(value))
    Error(error) -> Error(failure(error))
  }
}
