import finance_http/request.{type Request}
import finance_http/response.{type Response}
import finance_http/transport.{type TransportError}
import gleam/list

pub opaque type Script {
  Script(
    remaining: List(Result(Response, TransportError)),
    captured_reversed: List(String),
  )
}

pub type ScriptError {
  Exhausted
}

pub fn new(
  outcomes outcomes: List(Result(Response, TransportError)),
) -> Script {
  Script(outcomes, [])
}

/// Consume one outcome and capture only the request's redacted stable key.
///
/// The original script is unchanged. This pure transition is intentionally
/// separate from `Promise`; tests can fold it through a workflow reducer and
/// add `promise.resolve` only at the outer interpreter boundary.
pub fn send(
  script: Script,
  request_value: Request,
) -> Result(#(Script, Result(Response, TransportError)), ScriptError) {
  let Script(remaining, captured_reversed) = script
  case remaining {
    [] -> Error(Exhausted)
    [outcome, ..rest] ->
      Ok(#(
        Script(rest, [request.safe_key(request_value), ..captured_reversed]),
        outcome,
      ))
  }
}

pub fn captured(script: Script) -> List(String) {
  let Script(_, captured_reversed) = script
  list.reverse(captured_reversed)
}

pub fn remaining(script: Script) -> Int {
  let Script(remaining, _) = script
  list.length(remaining)
}
