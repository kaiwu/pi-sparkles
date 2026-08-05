import finance_authority_snapshot/runtime as authority_runtime
import finance_core/time
import finance_hkex.{type Access, type DocumentRef}
import finance_hkex/request as hkex_request
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

pub fn new(
  _access: Access,
  document: DocumentRef,
) -> Result(Runtime, InitError) {
  authority_runtime.new_binary(policy(document))
  |> map_result(Runtime, InvalidRuntime)
}

pub fn new_with(
  _access: Access,
  document: DocumentRef,
  sender: binary_client.Sender,
  sleeper: client.Sleeper,
  clock: client.Clock,
) -> Result(Runtime, InitError) {
  authority_runtime.new_binary_with(policy(document), sender, sleeper, clock)
  |> map_result(Runtime, InvalidRuntime)
}

pub fn send(
  runtime: Runtime,
  id id: String,
  request request_value: Request,
  cancellation cancellation: Cancellation,
) -> Promise(Result(Response, binary_pool.PoolError)) {
  authority_runtime.send_binary(runtime.inner, id, request_value, cancellation)
}

fn policy(document: DocumentRef) -> authority_runtime.Policy {
  let assert Ok(window) = time.duration(1000)
  let assert Ok(maximum_elapsed) = time.duration(20_000)
  let assert Ok(base_delay) = time.duration(500)
  let assert Ok(maximum_delay) = time.duration(2000)
  let assert Ok(value) =
    authority_runtime.policy(
      origin: hkex_request.origin,
      allowed_paths: [finance_hkex.path(document)],
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
