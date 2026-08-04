import gleeunit
import gleeunit/should
import pi_sparkles_lifecycle/policy
import pi_sparkles_lifecycle/state

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn blocked_session_is_cancelled_test() {
  policy.cancel_switch("/blocked-session.jsonl")
  |> should.be_true
}

pub fn ordinary_session_is_allowed_test() {
  policy.cancel_switch("/sessions/next.jsonl")
  |> should.be_false
}

pub fn reserved_fork_skips_restore_test() {
  policy.skip_fork_restore("skip-restore")
  |> should.be_true
}

pub fn immutable_state_transitions_compose_test() {
  let restored = state.initial() |> state.restore(41, "resume")
  let assert Ok(#(incremented, 42)) = state.increment(restored)
  let observed = state.observe(incremented, "session_info_changed:research")

  state.describe(restored)
  |> should.equal(
    "active=true value=41 start=resume shutdown=none cleanups=0 last=session_start:resume error=none",
  )
  state.describe(observed)
  |> should.equal(
    "active=true value=42 start=resume shutdown=none cleanups=0 last=session_info_changed:research error=none",
  )
}

pub fn cleanup_is_idempotent_test() {
  let active = state.initial() |> state.restore(2, "new")
  let once = state.cleanup(active, "reload")
  let twice = state.cleanup(once, "reload")

  state.describe(twice)
  |> should.equal(
    "active=false value=2 start=new shutdown=reload cleanups=1 last=session_shutdown:reload error=none",
  )
}

pub fn inactive_increment_is_a_typed_error_test() {
  state.initial()
  |> state.increment
  |> should.equal(Error(state.Inactive))
}

pub fn transition_order_is_explicit_test() {
  let state =
    state.initial()
    |> state.restore(1, "start")
    |> state.observe("first")
    |> state.observe("second")

  state.describe(state)
  |> should.equal(
    "active=true value=1 start=start shutdown=none cleanups=0 last=second error=none",
  )
}
