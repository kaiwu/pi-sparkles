import finance_http/request.{type Request}
import finance_http/retry.{type Failure}

pub type Response {
  Response(status: Int, body: String)
}

pub type Outcome {
  Responded(Response)
  Failed(Failure)
}

pub type Interaction {
  Interaction(request_key: String, outcome: Outcome)
}

pub opaque type Cassette {
  Cassette(schema_version: Int, remaining: List(Interaction), consumed: Int)
}

pub type ReplayError {
  Exhausted
  RequestMismatch(expected: String, actual: String)
}

pub fn interaction(request: Request, outcome: Outcome) -> Interaction {
  Interaction(request.safe_key(request), outcome)
}

pub fn new(interactions: List(Interaction)) -> Cassette {
  Cassette(1, interactions, 0)
}

pub fn schema_version(cassette: Cassette) -> Int {
  let Cassette(schema_version, _, _) = cassette
  schema_version
}

pub fn replay(
  cassette: Cassette,
  request: Request,
) -> Result(#(Cassette, Outcome), ReplayError) {
  let Cassette(schema_version, remaining, consumed) = cassette
  let actual = request.safe_key(request)
  case remaining {
    [] -> Error(Exhausted)
    [Interaction(expected, outcome), ..rest] ->
      case expected == actual {
        True -> Ok(#(Cassette(schema_version, rest, consumed + 1), outcome))
        False -> Error(RequestMismatch(expected, actual))
      }
  }
}

pub fn consumed(cassette: Cassette) -> Int {
  let Cassette(_, _, consumed) = cassette
  consumed
}
