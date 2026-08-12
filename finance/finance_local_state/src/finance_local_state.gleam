import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/javascript/promise.{type Promise}

pub type ReadOutcome {
  Loaded(text: String, byte_count: Int)
  Missing
  Cancelled
  TooLarge(received: Int, maximum: Int)
  InvalidUtf8
  Failure(code: String)
  InvalidResult
}

pub type ReplaceOutcome {
  Replaced(byte_count: Int)
  Changed(current_byte_count: Int)
  Busy
  CancelledReplace
  TooLargeReplacement(received: Int, maximum: Int)
  InvalidUtf8Current
  ReplaceFailure(code: String)
  InvalidReplaceResult
}

@external(javascript, "./finance_local_state_ffi.mjs", "read_text")
fn read_raw(
  path: String,
  maximum_bytes: Int,
  signal: Dynamic,
) -> Promise(Dynamic)

@external(javascript, "./finance_local_state_ffi.mjs", "replace_if_unchanged")
fn replace_raw(
  path: String,
  expected: String,
  replacement: String,
  maximum_bytes: Int,
  signal: Dynamic,
) -> Promise(Dynamic)

pub fn read(
  path: String,
  maximum_bytes: Int,
  signal: Dynamic,
) -> Promise(ReadOutcome) {
  read_raw(path, maximum_bytes, signal)
  |> promise.map(fn(value) {
    case decode.run(value, read_decoder()) {
      Ok(value) -> value
      Error(_) -> InvalidResult
    }
  })
  |> promise.rescue(fn(_) { Failure("effect_rejected") })
}

pub fn replace(
  path: String,
  expected: String,
  replacement: String,
  maximum_bytes: Int,
  signal: Dynamic,
) -> Promise(ReplaceOutcome) {
  replace_raw(path, expected, replacement, maximum_bytes, signal)
  |> promise.map(fn(value) {
    case decode.run(value, replace_decoder()) {
      Ok(value) -> value
      Error(_) -> InvalidReplaceResult
    }
  })
  |> promise.rescue(fn(_) { ReplaceFailure("effect_rejected") })
}

fn read_decoder() -> decode.Decoder(ReadOutcome) {
  use state <- decode.field("state", decode.string)
  use text <- decode.optional_field("text", "", decode.string)
  use bytes <- decode.optional_field("bytes", 0, decode.int)
  use maximum <- decode.optional_field("maximum", 0, decode.int)
  use code <- decode.optional_field("code", "unknown", decode.string)
  case state {
    "loaded" -> decode.success(Loaded(text, bytes))
    "missing" -> decode.success(Missing)
    "cancelled" -> decode.success(Cancelled)
    "too_large" -> decode.success(TooLarge(bytes, maximum))
    "invalid_utf8" -> decode.success(InvalidUtf8)
    "failure" -> decode.success(Failure(code))
    _ -> decode.success(InvalidResult)
  }
}

fn replace_decoder() -> decode.Decoder(ReplaceOutcome) {
  use state <- decode.field("state", decode.string)
  use bytes <- decode.optional_field("bytes", 0, decode.int)
  use maximum <- decode.optional_field("maximum", 0, decode.int)
  use code <- decode.optional_field("code", "unknown", decode.string)
  case state {
    "replaced" -> decode.success(Replaced(bytes))
    "changed" -> decode.success(Changed(bytes))
    "busy" -> decode.success(Busy)
    "cancelled" -> decode.success(CancelledReplace)
    "too_large" -> decode.success(TooLargeReplacement(bytes, maximum))
    "invalid_utf8" -> decode.success(InvalidUtf8Current)
    "failure" -> decode.success(ReplaceFailure(code))
    _ -> decode.success(InvalidReplaceResult)
  }
}
