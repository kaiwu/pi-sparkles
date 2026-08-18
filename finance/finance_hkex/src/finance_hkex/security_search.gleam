import finance_core/identifier.{type Resolution}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import gleam/string

pub const callback = "callback"

pub opaque type Security {
  Security(stock_id: Int, code: String, name: String)
}

pub opaque type Query {
  Query(code: String)
}

pub opaque type Page {
  Page(more: String, securities: List(Security))
}

type Payload {
  Payload(more: String, stock_info: List(Security))
}

pub type DecodeError {
  InvalidJsonp
  InvalidJson(json.DecodeError)
}

pub type QueryError {
  InvalidCode
}

pub fn query(code: String) -> Result(Query, QueryError) {
  case valid_code(code) {
    True -> Ok(Query(code))
    False -> Error(InvalidCode)
  }
}

pub fn query_code(value: Query) -> String {
  value.code
}

pub fn decode(body: String) -> Result(List(Security), DecodeError) {
  body |> decode_page |> result.map(page_securities)
}

pub fn decode_page(body: String) -> Result(Page, DecodeError) {
  let value = string.trim(body)
  let prefix = callback <> "("
  let suffix = ");"
  case
    string.starts_with(value, prefix),
    string.ends_with(value, suffix),
    string.length(value) > string.length(prefix) + string.length(suffix)
  {
    True, True, True -> {
      let json_body =
        value
        |> string.drop_start(up_to: string.length(prefix))
        |> string.slice(
          at_index: 0,
          length: string.length(value)
            - string.length(prefix)
            - string.length(suffix),
        )
      use Payload(more, values) <- result.try(
        json.parse(json_body, payload_decoder())
        |> result.map_error(InvalidJson),
      )
      case valid_text(more, 20) {
        True -> Ok(Page(more, values))
        False -> Error(InvalidJsonp)
      }
    }
    _, _, _ -> Error(InvalidJsonp)
  }
}

pub fn page_more(value: Page) -> String {
  value.more
}

pub fn page_securities(value: Page) -> List(Security) {
  value.securities
}

pub fn resolve_code(
  values: List(Security),
  code code_value: String,
) -> Resolution(Security) {
  values
  |> list.filter(fn(value) { value.code == code_value })
  |> identifier.resolve
}

pub fn stock_id(value: Security) -> Int {
  value.stock_id
}

pub fn code(value: Security) -> String {
  value.code
}

pub fn name(value: Security) -> String {
  value.name
}

fn payload_decoder() -> decode.Decoder(Payload) {
  use more <- decode.field("more", decode.string)
  use values <- decode.field("stockInfo", decode.list(of: security_decoder()))
  decode.success(Payload(more, values))
}

fn security_decoder() -> decode.Decoder(Security) {
  use stock_id <- decode.field("stockId", decode.int)
  use code <- decode.field("code", decode.string)
  use name <- decode.field("name", decode.string)
  let value = Security(stock_id, code, name)
  case stock_id > 0, valid_code(code), valid_text(name, 200) {
    True, True, True -> decode.success(value)
    _, _, _ -> decode.failure(value, "valid HKEXnews security record")
  }
}

fn valid_code(value: String) -> Bool {
  string.length(value) == 5
  && value
  |> string.to_graphemes
  |> list.all(fn(character) { string.contains("0123456789", character) })
}

fn valid_text(value: String, maximum: Int) -> Bool {
  value != ""
  && string.trim(value) == value
  && string.length(value) <= maximum
  && !string.contains(value, "\r")
  && !string.contains(value, "\n")
}
