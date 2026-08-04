import finance_http/queue.{type Queue}
import finance_http/request.{type Request}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub opaque type Job(value) {
  Job(id: String, origin: String, value: value)
}

pub opaque type Scheduler(value) {
  Scheduler(
    maximum_in_flight: Int,
    maximum_per_origin: Int,
    active: List(Job(value)),
    waiting: Queue(Job(value)),
  )
}

pub type SchedulerError {
  NonPositiveGlobalLimit
  NonPositiveOriginLimit
  NonPositiveQueueLimit
  InvalidJobId
  InvalidOrigin
  DuplicateJobId
  QueueFull
  UnknownJob
}

pub type Admission(value) {
  Started(job: Job(value))
  Queued(position: Int)
}

pub type Cancellation(value) {
  CancelledWaiting(job: Job(value))
  CancelledActive(job: Job(value))
}

pub fn job(
  id id: String,
  origin origin: String,
  value value: value,
) -> Result(Job(value), SchedulerError) {
  let candidate = Job(id, origin, value)
  case validate_job(candidate) {
    Ok(Nil) -> Ok(candidate)
    Error(error) -> Error(error)
  }
}

/// Construct a job whose concurrency namespace cannot diverge from the
/// validated request origin.
pub fn for_request(
  id id: String,
  request request_value: Request,
  value value: value,
) -> Result(Job(value), SchedulerError) {
  job(id, request.origin(request_value), value)
}

pub fn id(job: Job(value)) -> String {
  job.id
}

pub fn origin(job: Job(value)) -> String {
  job.origin
}

pub fn value(job: Job(value)) -> value {
  job.value
}

pub fn new(
  maximum_in_flight maximum_in_flight: Int,
  maximum_per_origin maximum_per_origin: Int,
  maximum_waiting maximum_waiting: Int,
) -> Result(Scheduler(value), SchedulerError) {
  case maximum_in_flight > 0, maximum_per_origin > 0, maximum_waiting > 0 {
    False, _, _ -> Error(NonPositiveGlobalLimit)
    _, False, _ -> Error(NonPositiveOriginLimit)
    _, _, False -> Error(NonPositiveQueueLimit)
    True, True, True -> {
      let assert Ok(waiting) = queue.new(capacity: maximum_waiting)
      Ok(Scheduler(maximum_in_flight, maximum_per_origin, [], waiting))
    }
  }
}

pub fn submit(
  scheduler: Scheduler(value),
  job: Job(value),
) -> Result(#(Scheduler(value), Admission(value)), SchedulerError) {
  let Scheduler(maximum_in_flight, maximum_per_origin, active, waiting) =
    scheduler
  case validate_job(job), contains_id(scheduler, job.id) {
    Error(error), _ -> Error(error)
    _, True -> Error(DuplicateJobId)
    Ok(Nil), False ->
      case can_start(maximum_in_flight, maximum_per_origin, active, job) {
        True ->
          Ok(#(
            Scheduler(
              maximum_in_flight,
              maximum_per_origin,
              list.append(active, [job]),
              waiting,
            ),
            Started(job),
          ))
        False ->
          case queue.enqueue(waiting, job) {
            Error(_) -> Error(QueueFull)
            Ok(next_waiting) ->
              Ok(#(
                Scheduler(
                  maximum_in_flight,
                  maximum_per_origin,
                  active,
                  next_waiting,
                ),
                Queued(queue.size(next_waiting)),
              ))
          }
      }
  }
}

/// Mark an active job complete and admit as many eligible waiting jobs as the
/// newly available capacity permits.
pub fn complete(
  scheduler: Scheduler(value),
  id id: String,
) -> Result(#(Scheduler(value), List(Job(value))), SchedulerError) {
  let Scheduler(maximum_in_flight, maximum_per_origin, active, waiting) =
    scheduler
  let #(remaining, completed) = take_job(active, id, [])
  case completed {
    None -> Error(UnknownJob)
    Some(_) -> {
      let #(next_active, next_waiting, started) =
        drain(maximum_in_flight, maximum_per_origin, remaining, waiting, [])
      Ok(#(
        Scheduler(
          maximum_in_flight,
          maximum_per_origin,
          next_active,
          next_waiting,
        ),
        started,
      ))
    }
  }
}

/// Remove a waiting job or request abortion of an active job.
///
/// Active jobs continue occupying capacity until the interpreter acknowledges
/// termination with `complete`. This prevents an abort race from temporarily
/// exceeding the configured concurrency limit.
pub fn cancel(
  scheduler: Scheduler(value),
  id id: String,
) -> Result(#(Scheduler(value), Cancellation(value)), SchedulerError) {
  let Scheduler(maximum_in_flight, maximum_per_origin, active, waiting) =
    scheduler
  let #(_, active_job) = take_job(active, id, [])
  case active_job {
    Some(job) -> Ok(#(scheduler, CancelledActive(job)))
    None -> {
      let #(next_waiting, waiting_job) =
        queue.take_first(waiting, fn(job) { job.id == id })
      case waiting_job {
        Some(job) ->
          Ok(#(
            Scheduler(
              maximum_in_flight,
              maximum_per_origin,
              active,
              next_waiting,
            ),
            CancelledWaiting(job),
          ))
        None -> Error(UnknownJob)
      }
    }
  }
}

pub fn active(scheduler: Scheduler(value)) -> List(Job(value)) {
  let Scheduler(_, _, active, _) = scheduler
  active
}

pub fn waiting(scheduler: Scheduler(value)) -> List(Job(value)) {
  let Scheduler(_, _, _, waiting) = scheduler
  queue.to_list(waiting)
}

pub fn in_flight(scheduler: Scheduler(value)) -> Int {
  list.length(active(scheduler))
}

pub fn waiting_count(scheduler: Scheduler(value)) -> Int {
  let Scheduler(_, _, _, waiting) = scheduler
  queue.size(waiting)
}

fn drain(
  maximum_in_flight: Int,
  maximum_per_origin: Int,
  active: List(Job(value)),
  waiting: Queue(Job(value)),
  started: List(Job(value)),
) -> #(List(Job(value)), Queue(Job(value)), List(Job(value))) {
  case list.length(active) >= maximum_in_flight {
    True -> #(active, waiting, list.reverse(started))
    False -> {
      let #(next_waiting, eligible) =
        queue.take_first(waiting, fn(job) {
          origin_count(active, job.origin) < maximum_per_origin
        })
      case eligible {
        None -> #(active, waiting, list.reverse(started))
        Some(job) ->
          drain(
            maximum_in_flight,
            maximum_per_origin,
            list.append(active, [job]),
            next_waiting,
            [job, ..started],
          )
      }
    }
  }
}

fn can_start(
  maximum_in_flight: Int,
  maximum_per_origin: Int,
  active: List(Job(value)),
  job: Job(value),
) -> Bool {
  list.length(active) < maximum_in_flight
  && origin_count(active, job.origin) < maximum_per_origin
}

fn origin_count(active: List(Job(value)), origin: String) -> Int {
  active
  |> list.filter(fn(job) { job.origin == origin })
  |> list.length
}

fn contains_id(scheduler: Scheduler(value), id: String) -> Bool {
  active(scheduler)
  |> list.append(waiting(scheduler))
  |> list.any(fn(job) { job.id == id })
}

fn validate_job(job: Job(value)) -> Result(Nil, SchedulerError) {
  case valid_label(job.id), valid_label(job.origin) {
    False, _ -> Error(InvalidJobId)
    _, False -> Error(InvalidOrigin)
    True, True -> Ok(Nil)
  }
}

fn valid_label(value: String) -> Bool {
  value != ""
  && string.trim(value) == value
  && !string.contains(value, "\r")
  && !string.contains(value, "\n")
}

fn take_job(
  jobs: List(Job(value)),
  id: String,
  before_reversed: List(Job(value)),
) -> #(List(Job(value)), Option(Job(value))) {
  case jobs {
    [] -> #(list.reverse(before_reversed), None)
    [job, ..rest] ->
      case job.id == id {
        True -> #(list.append(list.reverse(before_reversed), rest), Some(job))
        False -> take_job(rest, id, [job, ..before_reversed])
      }
  }
}
