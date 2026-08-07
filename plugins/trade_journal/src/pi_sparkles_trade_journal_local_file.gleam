import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/javascript/promise.{type Promise}

pub type ReadOutcome {
  Loaded(text: String, byte_count: Int)
  Missing
  ReadCancelled
  ReadTooLarge(received: Int, maximum: Int)
  ReadFailure(code: String)
  InvalidReadResult
}

pub type ReplaceOutcome {
  Replaced(byte_count: Int)
  StorageChanged(current_byte_count: Int)
  StorageBusy
  ReplaceCancelled
  ReplacementTooLarge(received: Int, maximum: Int)
  ReplaceFailure(code: String)
  InvalidReplaceResult
}

@external(javascript, "./pi_sparkles_trade_journal/effect/local_file_ffi.mjs", "read_text")
fn read_raw(
  path: String,
  maximum_bytes: Int,
  signal: Dynamic,
) -> Promise(Dynamic)

@external(javascript, "./pi_sparkles_trade_journal/effect/local_file_ffi.mjs", "replace_if_unchanged")
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
      Error(_) -> InvalidReadResult
    }
  })
  |> promise.rescue(fn(_) { ReadFailure("effect_rejected") })
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
    "cancelled" -> decode.success(ReadCancelled)
    "too_large" -> decode.success(ReadTooLarge(bytes, maximum))
    "failure" -> decode.success(ReadFailure(code))
    _ -> decode.success(InvalidReadResult)
  }
}

fn replace_decoder() -> decode.Decoder(ReplaceOutcome) {
  use state <- decode.field("state", decode.string)
  use bytes <- decode.optional_field("bytes", 0, decode.int)
  use maximum <- decode.optional_field("maximum", 0, decode.int)
  use code <- decode.optional_field("code", "unknown", decode.string)
  case state {
    "replaced" -> decode.success(Replaced(bytes))
    "changed" -> decode.success(StorageChanged(bytes))
    "busy" -> decode.success(StorageBusy)
    "cancelled" -> decode.success(ReplaceCancelled)
    "too_large" -> decode.success(ReplacementTooLarge(bytes, maximum))
    "failure" -> decode.success(ReplaceFailure(code))
    _ -> decode.success(InvalidReplaceResult)
  }
}
