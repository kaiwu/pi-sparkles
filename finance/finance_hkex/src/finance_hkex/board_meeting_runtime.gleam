import finance_authority_snapshot/runtime as authority_runtime
import finance_core/time
import finance_hkex.{type Access}
import finance_hkex/request as hkex_request
import finance_http/client
import finance_http/pool
import finance_http/request.{type Request}
import finance_http/response.{type Response}
import finance_http/transport.{type Cancellation}
import gleam/javascript/promise.{type Promise}
import gleam/result

pub opaque type Runtime {
  Runtime(inner: authority_runtime.Runtime)
}

pub type InitError {
  InvalidRuntime(authority_runtime.InitError)
}

pub fn new(_access: Access) -> Result(Runtime, InitError) {
  authority_runtime.new(policy())
  |> result.map(Runtime)
  |> result.map_error(InvalidRuntime)
}

pub fn new_with(
  _access: Access,
  sender: client.Sender,
  sleeper: client.Sleeper,
  clock: client.Clock,
) -> Result(Runtime, InitError) {
  authority_runtime.new_with(policy(), sender, sleeper, clock)
  |> result.map(Runtime)
  |> result.map_error(InvalidRuntime)
}

pub fn send(
  runtime: Runtime,
  id id: String,
  request request_value: Request,
  cancellation cancellation_value: Cancellation,
) -> Promise(Result(Response, pool.PoolError)) {
  authority_runtime.send(runtime.inner, id, request_value, cancellation_value)
}

fn policy() -> authority_runtime.Policy {
  let assert Ok(window) = time.duration(1000)
  let assert Ok(maximum_elapsed) = time.duration(30_000)
  let assert Ok(base_delay) = time.duration(500)
  let assert Ok(maximum_delay) = time.duration(2000)
  let assert Ok(value) =
    authority_runtime.policy(
      origin: hkex_request.board_meeting_origin,
      allowed_paths: [
        hkex_request.main_board_meetings_path,
        hkex_request.gem_board_meetings_path,
      ],
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
