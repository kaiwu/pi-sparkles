import finance_tape/stream
import gleam/option.{Some}
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn normal_lifecycle_tracks_queue_and_confirms_exact_cleanup_test() {
  let state = initial()
  let #(state, effects) = apply(state, stream.Start(0))
  effects |> should.equal([stream.Subscribe("hk:HK.00700:ticker", 1)])
  let #(state, _) = apply(state, stream.SubscriptionAcknowledged(1, 1))
  let #(state, effects) =
    apply(state, stream.BatchReceived(1, 3, 30, Some("3"), 2))
  effects |> should.equal([stream.AcceptBatch(1, 3, 30)])
  stream.total_events(state) |> should.equal(3)
  stream.total_bytes(state) |> should.equal(30)
  stream.queued_events(state) |> should.equal(3)
  stream.queue_high_water(state) |> should.equal(3)
  stream.last_sequence(state) |> should.equal(Some("3"))
  let #(state, _) = apply(state, stream.QueueConsumed(2, 3))
  stream.queued_events(state) |> should.equal(1)
  let #(state, effects) = apply(state, stream.StopRequested(4))
  effects |> should.equal([stream.Unsubscribe("hk:HK.00700:ticker", 1)])
  stream.cleanup_requested(state) |> should.be_true
  let #(state, duplicate_effects) = apply(state, stream.StopRequested(5))
  duplicate_effects |> should.equal([])
  let #(state, effects) = apply(state, stream.UnsubscribeAcknowledged(1, 6))
  stream.phase(state) |> should.equal(stream.Closed)
  effects |> should.equal([stream.Complete(stream.CleanupConfirmed)])
}

pub fn event_budget_failure_requests_cleanup_once_and_reports_confirmation_test() {
  let state = active()
  let #(state, effects) =
    apply(state, stream.BatchReceived(1, 11, 100, Some("11"), 2))
  stream.phase(state)
  |> should.equal(stream.FailingCleanup("event_budget_exceeded"))
  effects |> should.equal([stream.Unsubscribe("hk:HK.00700:ticker", 1)])
  let #(state, duplicate_effects) = apply(state, stream.StopRequested(3))
  duplicate_effects |> should.equal([])
  let #(state, effects) = apply(state, stream.UnsubscribeAcknowledged(1, 4))
  stream.phase(state)
  |> should.equal(stream.Failed("event_budget_exceeded"))
  effects
  |> should.equal([
    stream.ReportFailure("event_budget_exceeded", stream.CleanupConfirmed),
  ])
}

pub fn queue_budget_is_independent_and_consumption_releases_capacity_test() {
  let state = active()
  let #(state, _) = apply(state, stream.BatchReceived(1, 5, 50, Some("5"), 2))
  let #(state, _) = apply(state, stream.QueueConsumed(4, 3))
  let #(state, _) = apply(state, stream.BatchReceived(1, 4, 40, Some("9"), 4))
  stream.queued_events(state) |> should.equal(5)
  stream.queue_high_water(state) |> should.equal(5)
  let #(state, effects) =
    apply(state, stream.BatchReceived(1, 1, 10, Some("10"), 5))
  stream.phase(state)
  |> should.equal(stream.FailingCleanup("queue_budget_exceeded"))
  effects |> should.equal([stream.Unsubscribe("hk:HK.00700:ticker", 1)])
}

pub fn reconnect_uses_new_generation_and_requests_bounded_recovery_test() {
  let state = active()
  let #(state, _) = apply(state, stream.BatchReceived(1, 1, 10, Some("100"), 2))
  let #(state, effects) =
    apply(state, stream.Disconnected(1, "provider disconnect", 3))
  stream.phase(state) |> should.equal(stream.RecoveringSubscription)
  stream.generation(state) |> should.equal(2)
  stream.reconnect_count(state) |> should.equal(1)
  effects |> should.equal([stream.Subscribe("hk:HK.00700:ticker", 2)])

  let #(state, stale_effects) =
    apply(state, stream.SubscriptionAcknowledged(1, 4))
  stale_effects |> should.equal([])
  stream.stale_completion_count(state) |> should.equal(1)
  let #(state, effects) = apply(state, stream.SubscriptionAcknowledged(2, 5))
  stream.phase(state) |> should.equal(stream.RecoveringBackfill)
  effects
  |> should.equal([
    stream.RequestRecovery("hk:HK.00700:ticker", 2, Some("100")),
  ])
  let #(state, effects) =
    apply(state, stream.RecoveryCompleted(2, stream.OverlapProved, 6))
  stream.phase(state) |> should.equal(stream.Active)
  effects |> should.equal([])
}

pub fn unrecoverable_gap_fails_closed_with_subscription_cleanup_test() {
  let state = recovering_backfill()
  let #(state, effects) =
    apply(
      state,
      stream.RecoveryCompleted(
        2,
        stream.UnrecoverableGap("backfill does not overlap watermark"),
        5,
      ),
    )
  stream.phase(state)
  |> should.equal(stream.FailingCleanup(
    "unrecoverable_gap:backfill does not overlap watermark",
  ))
  effects |> should.equal([stream.Unsubscribe("hk:HK.00700:ticker", 2)])
}

pub fn reconnect_budget_exhaustion_never_hides_disconnected_failure_test() {
  let state = recovering_backfill()
  let #(state, _) =
    apply(state, stream.RecoveryCompleted(2, stream.OverlapProved, 5))
  let #(state, effects) = apply(state, stream.Disconnected(2, "again", 6))
  stream.phase(state)
  |> should.equal(stream.Failed("reconnect_budget_exhausted:again"))
  effects
  |> should.equal([
    stream.ReportFailure(
      "reconnect_budget_exhausted:again",
      stream.CleanupNotRequired,
    ),
  ])
}

pub fn operation_and_cleanup_timeouts_are_bounded_test() {
  let state = initial()
  let #(state, _) = apply(state, stream.Start(0))
  let #(state, effects) = apply(state, stream.Tick(101))
  stream.phase(state)
  |> should.equal(stream.FailingCleanup("subscribe_timeout"))
  effects |> should.equal([stream.Unsubscribe("hk:HK.00700:ticker", 1)])
  let #(state, effects) = apply(state, stream.Tick(152))
  stream.phase(state) |> should.equal(stream.Failed("subscribe_timeout"))
  effects
  |> should.equal([
    stream.ReportFailure("subscribe_timeout", stream.CleanupUnconfirmed),
  ])
}

pub fn old_generation_batches_are_ignored_without_changing_totals_test() {
  let state = recovering_backfill()
  let #(state, _) =
    apply(state, stream.RecoveryCompleted(2, stream.OverlapProved, 5))
  let #(state, effects) =
    apply(state, stream.BatchReceived(1, 5, 50, Some("old"), 6))
  effects |> should.equal([])
  stream.total_events(state) |> should.equal(0)
  stream.stale_completion_count(state) |> should.equal(1)
}

pub fn same_generation_callbacks_after_stop_are_ignored_without_new_cleanup_test() {
  let state = active()
  let #(state, effects) = apply(state, stream.StopRequested(2))
  effects |> should.equal([stream.Unsubscribe("hk:HK.00700:ticker", 1)])
  let #(state, effects) =
    apply(state, stream.BatchReceived(1, 2, 20, Some("2"), 3))
  effects |> should.equal([])
  stream.total_events(state) |> should.equal(0)
  stream.stale_completion_count(state) |> should.equal(1)
  let #(state, effects) = apply(state, stream.UnsubscribeAcknowledged(1, 4))
  effects |> should.equal([stream.Complete(stream.CleanupConfirmed)])
  let #(state, effects) = apply(state, stream.UnsubscribeAcknowledged(1, 5))
  effects |> should.equal([])
  stream.stale_completion_count(state) |> should.equal(2)
}

pub fn invalid_budgets_clocks_and_transitions_fail_closed_test() {
  stream.budgets(
    maximum_events: 0,
    maximum_bytes: 100,
    maximum_queued_events: 5,
    maximum_reconnects: 1,
    maximum_session_milliseconds: 1000,
    operation_timeout_milliseconds: 100,
    cleanup_timeout_milliseconds: 50,
  )
  |> should.be_error

  let state = active()
  stream.transition(state, stream.Tick(0)) |> should.be_error
  let assert Ok(late) =
    stream.transition(
      state,
      stream.RecoveryCompleted(1, stream.OverlapProved, 2),
    )
  late
  |> stream.transition_state
  |> stream.stale_completion_count
  |> should.equal(1)
  stream.transition(state, stream.QueueConsumed(1, 2)) |> should.be_error
}

fn initial() -> stream.State {
  let assert Ok(value) = stream.initial("hk:HK.00700:ticker", default_budgets())
  value
}

fn active() -> stream.State {
  let state = initial()
  let #(state, _) = apply(state, stream.Start(0))
  let #(state, _) = apply(state, stream.SubscriptionAcknowledged(1, 1))
  state
}

fn recovering_backfill() -> stream.State {
  let state = active()
  let #(state, _) =
    apply(state, stream.Disconnected(1, "provider disconnect", 2))
  let #(state, _) = apply(state, stream.SubscriptionAcknowledged(2, 3))
  state
}

fn apply(
  state: stream.State,
  event: stream.StreamEvent,
) -> #(stream.State, List(stream.Effect)) {
  let assert Ok(value) = stream.transition(state, event)
  #(stream.transition_state(value), stream.transition_effects(value))
}

fn default_budgets() -> stream.Budgets {
  let assert Ok(value) =
    stream.budgets(
      maximum_events: 10,
      maximum_bytes: 1000,
      maximum_queued_events: 5,
      maximum_reconnects: 1,
      maximum_session_milliseconds: 1000,
      operation_timeout_milliseconds: 100,
      cleanup_timeout_milliseconds: 50,
    )
  value
}
