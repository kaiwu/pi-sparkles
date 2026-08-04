import gleam/list

pub opaque type Script(value, failure) {
  Script(remaining: List(Result(value, failure)), consumed: Int)
}

pub type ScriptError {
  Exhausted
}

pub fn new(steps: List(Result(value, failure))) -> Script(value, failure) {
  Script(steps, 0)
}

pub fn next(
  script: Script(value, failure),
) -> Result(#(Script(value, failure), Result(value, failure)), ScriptError) {
  let Script(remaining, consumed) = script
  case remaining {
    [] -> Error(Exhausted)
    [step, ..rest] -> Ok(#(Script(rest, consumed + 1), step))
  }
}

pub fn consumed(script: Script(value, failure)) -> Int {
  let Script(_, consumed) = script
  consumed
}

pub fn remaining(script: Script(value, failure)) -> Int {
  let Script(remaining, _) = script
  list.length(remaining)
}
