import finance_core/time
import finance_http/request
import gleam/int
import gleam/list
import gleam/result
import gleam/string

pub type Status {
  Experimental
}

pub opaque type Access {
  Access(user_agent: String)
}

pub opaque type DocumentRef {
  DocumentRef(date: time.Date, identifier: String)
}

pub type AccessError {
  InvalidProduct
  InvalidContact
  InvalidHeader(request.RequestError)
}

pub type DocumentError {
  InvalidDate
  InvalidIdentifier
}

pub fn status() -> Status {
  Experimental
}

pub fn access(product: String, contact: String) -> Result(Access, AccessError) {
  case valid_identity(product), valid_identity(contact) {
    False, _ -> Error(InvalidProduct)
    _, False -> Error(InvalidContact)
    True, True -> Ok(Access(product <> " " <> contact))
  }
}

pub fn document(
  year: Int,
  month: Int,
  day: Int,
  identifier: String,
) -> Result(DocumentRef, DocumentError) {
  case time.date(year, month, day), valid_identifier(identifier) {
    Error(_), _ -> Error(InvalidDate)
    _, False -> Error(InvalidIdentifier)
    Ok(date), True -> Ok(DocumentRef(date, identifier))
  }
}

pub fn authorize(
  access: Access,
  request_value: request.Request,
) -> Result(request.Request, AccessError) {
  let Access(user_agent) = access
  request.with_header(
    request_value,
    name: "User-Agent",
    value: user_agent,
    sensitivity: request.Public,
  )
  |> result.map_error(InvalidHeader)
}

pub fn path(value: DocumentRef) -> String {
  let DocumentRef(date, identifier) = value
  "/finalpage/" <> date_path(date) <> "/" <> identifier <> ".PDF"
}

pub fn canonical_url(value: DocumentRef) -> String {
  "https://static.cninfo.com.cn" <> path(value)
}

pub fn identifier(value: DocumentRef) -> String {
  value.identifier
}

fn date_path(value: time.Date) -> String {
  let #(year, month, day) = time.date_parts(value)
  int.to_string(year) <> "-" <> two_digits(month) <> "-" <> two_digits(day)
}

fn two_digits(value: Int) -> String {
  case value < 10 {
    True -> "0" <> int.to_string(value)
    False -> int.to_string(value)
  }
}

fn valid_identifier(value: String) -> Bool {
  string.length(value) == 10
  && {
    value
    |> string.to_graphemes
    |> list.all(fn(character) { string.contains("0123456789", character) })
  }
}

fn valid_identity(value: String) -> Bool {
  value != ""
  && string.trim(value) == value
  && string.length(value) <= 200
  && !string.contains(value, "\r")
  && !string.contains(value, "\n")
}
