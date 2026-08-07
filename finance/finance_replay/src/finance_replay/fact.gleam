import gleam/dynamic/decode
import gleam/json

/// An information slot. It is never a correctness or sufficiency verdict.
pub type Fact(value) {
  Known(value)
  Unknown(reason: String)
  Conflicting(alternatives: List(value), reason: String)
  DecodeFailure(raw: String, reason: String)
  NotObtained(reason: String)
  NotApplicable(reason: String)
}

pub fn state_name(value: Fact(a)) -> String {
  case value {
    Known(_) -> "known"
    Unknown(_) -> "unknown"
    Conflicting(_, _) -> "conflicting"
    DecodeFailure(_, _) -> "decode_failure"
    NotObtained(_) -> "not_obtained"
    NotApplicable(_) -> "not_applicable"
  }
}

pub fn to_json(value: Fact(a), encode: fn(a) -> json.Json) -> json.Json {
  case value {
    Known(value) ->
      json.object([
        #("state", json.string("known")),
        #("value", encode(value)),
      ])
    Unknown(reason) -> reason_json("unknown", reason)
    NotObtained(reason) -> reason_json("not_obtained", reason)
    NotApplicable(reason) -> reason_json("not_applicable", reason)
    Conflicting(alternatives, reason) ->
      json.object([
        #("state", json.string("conflicting")),
        #("alternatives", json.array(alternatives, encode)),
        #("reason", json.string(reason)),
      ])
    DecodeFailure(raw, reason) ->
      json.object([
        #("state", json.string("decode_failure")),
        #("raw", json.string(raw)),
        #("reason", json.string(reason)),
      ])
  }
}

pub fn decoder(value_decoder: decode.Decoder(a)) -> decode.Decoder(Fact(a)) {
  use state <- decode.field("state", decode.string)
  case state {
    "known" -> {
      use value <- decode.field("value", value_decoder)
      decode.success(Known(value))
    }
    "unknown" -> reason_decoder(Unknown)
    "not_obtained" -> reason_decoder(NotObtained)
    "not_applicable" -> reason_decoder(NotApplicable)
    "conflicting" -> {
      use alternatives <- decode.field(
        "alternatives",
        decode.list(of: value_decoder),
      )
      use reason <- decode.field("reason", decode.string)
      decode.success(Conflicting(alternatives, reason))
    }
    "decode_failure" -> {
      use raw <- decode.field("raw", decode.string)
      use reason <- decode.field("reason", decode.string)
      decode.success(DecodeFailure(raw, reason))
    }
    _ -> decode.failure(Unknown("placeholder"), "known replay fact state")
  }
}

fn reason_json(state: String, reason: String) -> json.Json {
  json.object([
    #("state", json.string(state)),
    #("reason", json.string(reason)),
  ])
}

fn reason_decoder(
  constructor: fn(String) -> Fact(a),
) -> decode.Decoder(Fact(a)) {
  use reason <- decode.field("reason", decode.string)
  decode.success(constructor(reason))
}
