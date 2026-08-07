import finance_core/time.{type Date, type Instant}
import finance_provenance/identity.{type Sha256}
import finance_track.{type Track}
import gleam/dynamic/decode
import gleam/json
import gleam/string

pub fn date_json(value: Date) -> json.Json {
  let #(year, month, day) = time.date_parts(value)
  json.object([
    #("year", json.int(year)),
    #("month", json.int(month)),
    #("day", json.int(day)),
  ])
}

pub fn date_decoder() -> decode.Decoder(Date) {
  use year <- decode.field("year", decode.int)
  use month <- decode.field("month", decode.int)
  use day <- decode.field("day", decode.int)
  case time.date(year, month, day) {
    Ok(value) -> decode.success(value)
    Error(_) -> decode.failure(placeholder_date(), "valid Gregorian date")
  }
}

pub fn instant_json(value: Instant) -> json.Json {
  value |> time.unix_milliseconds |> json.int
}

pub fn instant_decoder() -> decode.Decoder(Instant) {
  decode.int
  |> decode.then(fn(value) {
    case time.instant(value) {
      Ok(value) -> decode.success(value)
      Error(_) -> decode.failure(placeholder_instant(), "Unix milliseconds")
    }
  })
}

pub fn sha_json(value: Sha256) -> json.Json {
  value |> identity.sha256_value |> json.string
}

pub fn sha_decoder() -> decode.Decoder(Sha256) {
  decode.string
  |> decode.then(fn(value) {
    case identity.sha256(value) {
      Ok(value) -> decode.success(value)
      Error(_) -> decode.failure(placeholder_sha(), "SHA-256 hex")
    }
  })
}

pub fn track_json(value: Track) -> json.Json {
  value |> finance_track.name |> json.string
}

pub fn track_decoder() -> decode.Decoder(Track) {
  decode.string
  |> decode.then(fn(value) {
    case finance_track.from_name(value) {
      Ok(value) -> decode.success(value)
      Error(_) -> decode.failure(finance_track.Us, "cn, hk, or us")
    }
  })
}

pub fn valid_text(value: String, maximum: Int) -> Bool {
  value != ""
  && string.trim(value) == value
  && string.length(value) <= maximum
  && !string.contains(value, "\n")
  && !string.contains(value, "\r")
}

pub fn placeholder_sha() -> Sha256 {
  let assert Ok(value) =
    identity.sha256(
      "0000000000000000000000000000000000000000000000000000000000000000",
    )
  value
}

pub fn placeholder_instant() -> Instant {
  let assert Ok(value) = time.instant(0)
  value
}

pub fn placeholder_date() -> Date {
  let assert Ok(value) = time.date(1, 1, 1)
  value
}
