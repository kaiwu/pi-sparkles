import gleam/dynamic/decode
import gleam/json
import gleam/option.{type Option, None}

pub type Candidate {
  Candidate(
    figi: String,
    name: Option(String),
    ticker: Option(String),
    exchange_code: Option(String),
    security_type: Option(String),
    market_sector: Option(String),
    composite_figi: Option(String),
    share_class_figi: Option(String),
  )
}

pub type ResultSet {
  ResultSet(
    candidates: List(Candidate),
    warning: Option(String),
    error: Option(String),
    next: Option(String),
    total: Option(Int),
  )
}

pub fn decode_search(body: String) -> Result(ResultSet, json.DecodeError) {
  json.parse(body, result_set_decoder())
}

pub fn decode_mapping(
  body: String,
) -> Result(List(ResultSet), json.DecodeError) {
  json.parse(body, decode.list(of: result_set_decoder()))
}

pub fn first_mapping_result(results: List(ResultSet)) -> ResultSet {
  case results {
    [result, ..] -> result
    [] -> ResultSet([], None, None, None, None)
  }
}

fn result_set_decoder() -> decode.Decoder(ResultSet) {
  use candidates <- decode.optional_field(
    "data",
    [],
    decode.list(of: candidate_decoder()),
  )
  use warning <- optional_string("warning")
  use error <- optional_string("error")
  use next <- optional_string("next")
  use total <- decode.optional_field("total", None, decode.optional(decode.int))
  decode.success(ResultSet(candidates:, warning:, error:, next:, total:))
}

fn candidate_decoder() -> decode.Decoder(Candidate) {
  use figi <- decode.field("figi", decode.string)
  use name <- optional_string("name")
  use ticker <- optional_string("ticker")
  use exchange_code <- optional_string("exchCode")
  use security_type <- optional_string("securityType2")
  use market_sector <- optional_string("marketSector")
  use composite_figi <- optional_string("compositeFIGI")
  use share_class_figi <- optional_string("shareClassFIGI")
  decode.success(Candidate(
    figi:,
    name:,
    ticker:,
    exchange_code:,
    security_type:,
    market_sector:,
    composite_figi:,
    share_class_figi:,
  ))
}

fn optional_string(
  name: String,
  next: fn(Option(String)) -> decode.Decoder(value),
) -> decode.Decoder(value) {
  decode.optional_field(name, None, decode.optional(decode.string), next)
}
