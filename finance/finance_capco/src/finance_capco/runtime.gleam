import finance_authority_snapshot/runtime as authority_runtime
import finance_capco.{type Snapshot}
import finance_core/time
import finance_http/binary_client
import finance_http/binary_pool
import finance_http/binary_response.{type Response}
import finance_http/client
import finance_http/request.{type Request}
import finance_http/transport.{type Cancellation}
import gleam/javascript/promise.{type Promise}

pub opaque type Runtime {
  Runtime(inner: authority_runtime.BinaryRuntime)
}

pub type InitError {
  InvalidRuntime(authority_runtime.InitError)
}

pub fn new(snapshot: Snapshot) -> Result(Runtime, InitError) {
  case authority_runtime.new_binary(policy(snapshot)) {
    Ok(value) -> Ok(Runtime(value))
    Error(error) -> Error(InvalidRuntime(error))
  }
}

pub fn new_with(
  snapshot: Snapshot,
  sender: binary_client.Sender,
  sleeper: client.Sleeper,
  clock: client.Clock,
) -> Result(Runtime, InitError) {
  case
    authority_runtime.new_binary_with(policy(snapshot), sender, sleeper, clock)
  {
    Ok(value) -> Ok(Runtime(value))
    Error(error) -> Error(InvalidRuntime(error))
  }
}

pub fn send(
  runtime: Runtime,
  id id: String,
  request request_value: Request,
  cancellation cancellation_value: Cancellation,
) -> Promise(Result(Response, binary_pool.PoolError)) {
  authority_runtime.send_binary(
    runtime.inner,
    id: id,
    request: request_value,
    cancellation: cancellation_value,
  )
}

fn policy(snapshot: Snapshot) -> authority_runtime.Policy {
  let assert Ok(window) = time.duration(1000)
  let assert Ok(maximum_elapsed) = time.duration(20_000)
  let assert Ok(base_delay) = time.duration(500)
  let assert Ok(maximum_delay) = time.duration(2000)
  let assert Ok(value) =
    authority_runtime.policy(
      origin: snapshot.pdf_origin,
      allowed_paths: [snapshot.pdf_path],
      admissions_per_window: 1,
      window: window,
      maximum_in_flight: 1,
      maximum_waiting: 10,
      maximum_attempts: 2,
      maximum_elapsed: maximum_elapsed,
      base_delay: base_delay,
      maximum_delay: maximum_delay,
    )
  value
}
