import finance_track
import gleeunit
import gleeunit/should
import pi_sparkles_finance_track_status/state

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn switching_is_explicit_and_idempotent_test() {
  let initial = state.new(finance_track.Us)
  let #(cn, first) = state.switch(initial, to: finance_track.Cn)
  let #(same, second) = state.switch(cn, to: finance_track.Cn)

  first |> should.equal(state.Switched(finance_track.Us, finance_track.Cn))
  second |> should.equal(state.Unchanged(finance_track.Cn))
  state.active_track(same) |> should.equal(finance_track.Cn)
}
