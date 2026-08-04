import finance_core/time.{type Duration}
import finance_http/request.{type Request}
import finance_http/retry.{type Failure, type Policy, type StopReason}

pub opaque type Workflow {
  Workflow(request: Request, policy: Policy, phase: Phase, elapsed: Duration)
}

pub type Phase {
  Ready
  Waiting(attempt: Int)
  Sleeping(delay: Duration, next_attempt: Int)
  Succeeded(status: Int)
  Failed(reason: StopReason)
  Cancelled
}

pub type Event {
  Start
  TransportSucceeded(attempt: Int, status: Int, elapsed: Duration)
  TransportFailed(attempt: Int, failure: Failure, elapsed: Duration)
  SleepFinished(next_attempt: Int)
  Cancel
}

pub type Effect {
  Send(attempt: Int, request: Request)
  Sleep(delay: Duration, next_attempt: Int)
}

pub fn new(request: Request, policy: Policy, elapsed: Duration) -> Workflow {
  Workflow(request, policy, Ready, elapsed)
}

pub fn phase(workflow: Workflow) -> Phase {
  let Workflow(_, _, phase, _) = workflow
  phase
}

pub fn elapsed(workflow: Workflow) -> Duration {
  let Workflow(_, _, _, elapsed) = workflow
  elapsed
}

pub fn update(workflow: Workflow, event: Event) -> #(Workflow, List(Effect)) {
  let Workflow(request, policy, phase, current_elapsed) = workflow
  case phase, event {
    Ready, Start -> #(Workflow(request, policy, Waiting(1), current_elapsed), [
      Send(1, request),
    ])
    Waiting(expected), TransportSucceeded(attempt, status, elapsed)
      if expected == attempt
    -> #(Workflow(request, policy, Succeeded(status), elapsed), [])
    Waiting(expected), TransportFailed(attempt, failure, elapsed)
      if expected == attempt
    ->
      case retry.decide(policy, request, attempt, elapsed, failure) {
        retry.Stop(reason) -> #(
          Workflow(request, policy, Failed(reason), elapsed),
          [],
        )
        retry.RetryAfter(delay, next_attempt) -> #(
          Workflow(request, policy, Sleeping(delay, next_attempt), elapsed),
          [Sleep(delay, next_attempt)],
        )
      }
    Sleeping(_, expected), SleepFinished(attempt) if expected == attempt -> #(
      Workflow(request, policy, Waiting(attempt), current_elapsed),
      [
        Send(attempt, request),
      ],
    )
    Succeeded(_), _ | Failed(_), _ | Cancelled, _ -> #(workflow, [])
    _, Cancel -> #(Workflow(request, policy, Cancelled, current_elapsed), [])
    _, _ -> #(workflow, [])
  }
}
