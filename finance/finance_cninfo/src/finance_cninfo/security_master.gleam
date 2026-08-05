import finance_core/identifier.{type Resolution}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/string

pub opaque type Security {
  Security(
    code: String,
    organization_id: String,
    short_name: String,
    category: String,
    pinyin: String,
  )
}

type Payload {
  Payload(stock_list: List(Security))
}

pub fn decode(body: String) -> Result(List(Security), json.DecodeError) {
  case json.parse(body, payload_decoder()) {
    Ok(Payload(values)) -> Ok(values)
    Error(error) -> Error(error)
  }
}

pub fn resolve_code(
  values: List(Security),
  code code_value: String,
) -> Resolution(Security) {
  values
  |> list.filter(fn(value) { value.code == code_value })
  |> identifier.resolve
}

pub fn code(value: Security) -> String {
  value.code
}

pub fn organization_id(value: Security) -> String {
  value.organization_id
}

pub fn short_name(value: Security) -> String {
  value.short_name
}

pub fn category(value: Security) -> String {
  value.category
}

pub fn pinyin(value: Security) -> String {
  value.pinyin
}

fn payload_decoder() -> decode.Decoder(Payload) {
  use values <- decode.field("stockList", decode.list(of: security_decoder()))
  decode.success(Payload(values))
}

fn security_decoder() -> decode.Decoder(Security) {
  use code <- decode.field("code", decode.string)
  use organization_id <- decode.field("orgId", decode.string)
  use short_name <- decode.field("zwjc", decode.string)
  use category <- decode.field("category", decode.string)
  use pinyin <- decode.field("pinyin", decode.string)
  let value = Security(code, organization_id, short_name, category, pinyin)
  case
    valid_code(code),
    valid_text(organization_id, 100),
    valid_text(short_name, 200),
    valid_text(category, 100),
    valid_text(pinyin, 100)
  {
    True, True, True, True, True -> decode.success(value)
    _, _, _, _, _ -> decode.failure(value, "valid CNINFO security record")
  }
}

fn valid_code(value: String) -> Bool {
  string.length(value) == 6
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
