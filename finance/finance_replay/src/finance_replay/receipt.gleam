import finance_provenance/hash
import finance_provenance/identity.{type Sha256}
import gleam/json.{type Json}

pub opaque type Envelope {
  Envelope(payload: Json, canonical_content_hash: Sha256)
}

pub fn envelope(payload: Json) -> Envelope {
  let assert Ok(content_hash) = payload |> json.to_string |> hash.text
  Envelope(payload, content_hash)
}

pub fn encode(value: Envelope) -> String {
  value |> as_json |> json.to_string
}

pub fn as_json(value: Envelope) -> Json {
  json.object([
    #("payload", value.payload),
    #(
      "canonical_content_hash",
      value.canonical_content_hash
        |> identity.sha256_value
        |> json.string,
    ),
  ])
}

pub fn payload_json(value: Envelope) -> Json {
  value.payload
}

pub fn payload_text(value: Envelope) -> String {
  value.payload |> json.to_string
}

pub fn content_hash(value: Envelope) -> Sha256 {
  value.canonical_content_hash
}

pub fn verify(value: Envelope) -> Bool {
  case value.payload |> json.to_string |> hash.text {
    Ok(actual) -> actual == value.canonical_content_hash
    Error(_) -> False
  }
}
