import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/javascript/promise.{type Promise}

pub type ReadOutcome {
  Loaded(text: String, byte_count: Int)
  Truncated(text: String, retained_bytes: Int, total_bytes: Int)
  Cancelled
  Missing
  InvalidUtf8
  Failure(code: String)
  InvalidResult
}

@external(javascript, "./pi_sparkles_portfolio_local_file_ffi.mjs", "read_text")
fn read_raw(
  path: String,
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
    case decode.run(value, outcome_decoder()) {
      Ok(value) -> value
      Error(_) -> InvalidResult
    }
  })
  |> promise.rescue(fn(_) { Failure("effect_rejected") })
}

fn outcome_decoder() -> decode.Decoder(ReadOutcome) {
  use state <- decode.field("state", decode.string)
  use text <- decode.optional_field("text", "", decode.string)
  use bytes <- decode.optional_field("bytes", 0, decode.int)
  use total <- decode.optional_field("total", 0, decode.int)
  use code <- decode.optional_field("code", "unknown", decode.string)
  case state {
    "loaded" -> decode.success(Loaded(text, bytes))
    "truncated" -> decode.success(Truncated(text, bytes, total))
    "cancelled" -> decode.success(Cancelled)
    "missing" -> decode.success(Missing)
    "invalid_utf8" -> decode.success(InvalidUtf8)
    "failure" -> decode.success(Failure(code))
    _ -> decode.success(InvalidResult)
  }
}
