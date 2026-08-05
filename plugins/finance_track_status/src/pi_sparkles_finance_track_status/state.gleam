import finance_track.{type Track}

pub opaque type State {
  State(active_track: Track)
}

pub type Transition {
  Unchanged(track: Track)
  Switched(previous: Track, current: Track)
}

pub fn new(track: Track) -> State {
  State(track)
}

pub fn active_track(state: State) -> Track {
  state.active_track
}

pub fn switch(state: State, to track: Track) -> #(State, Transition) {
  case state.active_track == track {
    True -> #(state, Unchanged(track))
    False -> #(State(track), Switched(state.active_track, track))
  }
}
