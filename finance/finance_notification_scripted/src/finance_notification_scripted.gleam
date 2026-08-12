import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/javascript/promise.{type Promise}

pub type Outcome {
  Delivered(provider_receipt: String)
  RateLimited(provider_receipt: String)
  Failed(provider_receipt: String)
  Cancelled
  InvalidResult
  EffectFailure
}

@external(javascript, "./finance_notification_scripted_ffi.mjs", "deliver")
fn deliver_raw(
  channel: String,
  destination_ref: String,
  attempt: Int,
  scripted_outcome: String,
  signal: Dynamic,
) -> Promise(Dynamic)

pub fn deliver(
  channel: String,
  destination_ref: String,
  attempt: Int,
  scripted_outcome: String,
  signal: Dynamic,
) -> Promise(Outcome) {
  deliver_raw(channel, destination_ref, attempt, scripted_outcome, signal)
  |> promise.map(fn(value) {
    case decode.run(value, outcome_decoder()) {
      Ok(value) -> value
      Error(_) -> InvalidResult
    }
  })
  |> promise.rescue(fn(_) { EffectFailure })
}

fn outcome_decoder() -> decode.Decoder(Outcome) {
  use status <- decode.field("status", decode.string)
  use receipt <- decode.optional_field("receipt", "", decode.string)
  case status {
    "delivered" -> decode.success(Delivered(receipt))
    "rate_limited" -> decode.success(RateLimited(receipt))
    "failed" -> decode.success(Failed(receipt))
    "cancelled" -> decode.success(Cancelled)
    _ -> decode.success(InvalidResult)
  }
}
