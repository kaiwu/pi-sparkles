import finance_core/time
import finance_http/client
import finance_http/pool
import finance_http/request
import finance_http/response.{type Response}
import finance_http/retry
import finance_http/scheduler
import finance_http/transport.{type Cancellation}
import finance_twelve_data/request as provider_request
import gleam/javascript/promise.{type Promise}
import gleam/result

pub opaque type Runtime {
  Runtime(pool: pool.Pool)
}

pub type InitError {
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
  let provider_client = client.new(retry_policy(), sender, sleeper, clock)
  pool.new(
    provider_client,
    maximum_in_flight: 1,
    maximum_per_origin: 1,
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
      request.path(request_value) == provider_request.profile_path
      || request.path(request_value) == provider_request.statistics_path
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

fn retry_policy() -> retry.Policy {
  let assert Ok(maximum_elapsed) = time.duration(15_000)
  let assert Ok(base_delay) = time.duration(500)
  let assert Ok(maximum_delay) = time.duration(500)
  let assert Ok(policy) =
    retry.policy(
      maximum_attempts: 1,
      maximum_elapsed: maximum_elapsed,
      base_delay: base_delay,
      maximum_delay: maximum_delay,
    )
  policy
}
