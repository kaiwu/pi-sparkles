import finance_http/binary_client.{type Client, type ClientError}
import finance_http/binary_response.{type Response}
import finance_http/request.{type Request}
import finance_http/scheduler.{type Scheduler, type SchedulerError}
import finance_http/transport.{type Cancellation}
import gleam/javascript/promise.{type Promise}
import gleam/list
import gleam/result

type Cell(value)

type Subscriptions

type Call {
  Call(
    request: Request,
    cancellation: Cancellation,
    resolve: fn(Result(Response, PoolError)) -> Nil,
  )
}

/// Byte-preserving pool interpreter over the same pure scheduler used by the
/// UTF-8 client. Binary and text payloads therefore share admission,
/// concurrency, fairness, queueing, and cancellation laws.
pub opaque type Pool {
  Pool(
    client: Client,
    state: Cell(Scheduler(Call)),
    subscriptions: Subscriptions,
  )
}

pub type PoolError {
  AdmissionFailed(error: SchedulerError)
  RequestFailed(error: ClientError)
  UnexpectedClientFailure
}

pub fn new(
  client client_value: Client,
  maximum_in_flight maximum_in_flight: Int,
  maximum_per_origin maximum_per_origin: Int,
  maximum_waiting maximum_waiting: Int,
) -> Result(Pool, SchedulerError) {
  use initial <- result.try(scheduler.new(
    maximum_in_flight,
    maximum_per_origin,
    maximum_waiting,
  ))
  Ok(Pool(client_value, new_cell(initial), new_subscriptions()))
}

pub fn send(
  pool: Pool,
  id id: String,
  request request_value: Request,
  cancellation cancellation: Cancellation,
) -> Promise(Result(Response, PoolError)) {
  let #(pending, resolve) = promise.start()
  let call = Call(request_value, cancellation, resolve)
  let Pool(_, state, subscriptions) = pool

  case scheduler.for_request(id, request_value, call) {
    Error(error) -> resolve(Error(AdmissionFailed(error)))
    Ok(job) ->
      case scheduler.submit(read_cell(state), job) {
        Error(error) -> resolve(Error(AdmissionFailed(error)))
        Ok(#(next, admission)) -> {
          write_cell(state, next)
          subscribe(subscriptions, id, cancellation, fn() {
            let _ = cancel(pool, id)
            Nil
          })
          case admission {
            scheduler.Started(started) -> launch(pool, started)
            scheduler.Queued(_) -> Nil
          }
        }
      }
  }

  pending
}

pub fn cancel(pool: Pool, id id: String) -> Result(Nil, SchedulerError) {
  let Pool(_, state, subscriptions) = pool
  use #(next, cancellation) <- result.try(scheduler.cancel(read_cell(state), id))
  write_cell(state, next)

  case cancellation {
    scheduler.CancelledWaiting(job) -> {
      unsubscribe(subscriptions, id)
      let Call(_, _, resolve) = scheduler.value(job)
      resolve(Error(RequestFailed(binary_client.Cancelled)))
    }
    scheduler.CancelledActive(job) -> {
      unsubscribe(subscriptions, id)
      let Call(_, cancellation, _) = scheduler.value(job)
      transport.cancel(cancellation)
    }
  }

  Ok(Nil)
}

pub fn in_flight(pool: Pool) -> Int {
  let Pool(_, state, _) = pool
  scheduler.in_flight(read_cell(state))
}

pub fn waiting_count(pool: Pool) -> Int {
  let Pool(_, state, _) = pool
  scheduler.waiting_count(read_cell(state))
}

fn launch(pool: Pool, job: scheduler.Job(Call)) -> Nil {
  let Pool(client_value, _, _) = pool
  let Call(request_value, cancellation, _) = scheduler.value(job)
  let id = scheduler.id(job)

  let _ =
    binary_client.send(client_value, request_value, cancellation)
    |> promise.map(fn(outcome) {
      settle(pool, id, outcome |> result.map_error(RequestFailed))
    })
    |> promise.rescue(fn(_) { settle(pool, id, Error(UnexpectedClientFailure)) })

  Nil
}

fn settle(pool: Pool, id: String, outcome: Result(Response, PoolError)) -> Nil {
  let Pool(_, state, subscriptions) = pool
  case scheduler.complete(read_cell(state), id) {
    Error(_) -> Nil
    Ok(#(next, admitted)) -> {
      let completed =
        read_cell(state)
        |> scheduler.active
        |> list.find(fn(job) { scheduler.id(job) == id })
      write_cell(state, next)
      unsubscribe(subscriptions, id)
      case completed {
        Error(_) -> Nil
        Ok(job) -> {
          let Call(_, _, resolve) = scheduler.value(job)
          resolve(outcome)
        }
      }
      list.each(admitted, fn(job) { launch(pool, job) })
    }
  }
}

@external(javascript, "./pool_ffi.mjs", "new_cell")
fn new_cell(value: value) -> Cell(value)

@external(javascript, "./pool_ffi.mjs", "read_cell")
fn read_cell(cell: Cell(value)) -> value

@external(javascript, "./pool_ffi.mjs", "write_cell")
fn write_cell(cell: Cell(value), value: value) -> Nil

@external(javascript, "./pool_ffi.mjs", "new_subscriptions")
fn new_subscriptions() -> Subscriptions

@external(javascript, "./pool_ffi.mjs", "subscribe")
fn subscribe(
  subscriptions: Subscriptions,
  id: String,
  cancellation: Cancellation,
  callback: fn() -> Nil,
) -> Nil

@external(javascript, "./pool_ffi.mjs", "unsubscribe")
fn unsubscribe(subscriptions: Subscriptions, id: String) -> Nil
