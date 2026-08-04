import finance_http/cassette.{type Cassette, type Outcome, type ReplayError}
import finance_http/request.{type Request}
import gleam/list

pub type Replay {
  Replay(cassette: Cassette, outcomes: List(Outcome))
}

pub fn from_pairs(pairs: List(#(Request, Outcome))) -> Cassette {
  pairs
  |> list.map(fn(pair) { cassette.interaction(pair.0, pair.1) })
  |> cassette.new
}

pub fn replay_all(
  cassette: Cassette,
  requests: List(Request),
) -> Result(Replay, ReplayError) {
  replay_requests(cassette, requests, [])
}

fn replay_requests(
  cassette: Cassette,
  requests: List(Request),
  outcomes: List(Outcome),
) -> Result(Replay, ReplayError) {
  case requests {
    [] -> Ok(Replay(cassette, list.reverse(outcomes)))
    [request, ..rest] ->
      case cassette.replay(cassette, request) {
        Error(error) -> Error(error)
        Ok(#(next, outcome)) ->
          replay_requests(next, rest, [outcome, ..outcomes])
      }
  }
}
