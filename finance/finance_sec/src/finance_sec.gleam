import finance_http/request
import gleam/int
import gleam/result
import gleam/string

pub type Status {
  Experimental
}

pub opaque type Access {
  Access(user_agent: String)
}

pub opaque type Cik {
  Cik(value: String)
}

pub type AccessError {
  InvalidProduct
  InvalidContact
  InvalidHeader(request.RequestError)
}

pub type CikError {
  InvalidCik
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

pub fn authorize(
  value: Access,
  request_value: request.Request,
) -> Result(request.Request, AccessError) {
  let Access(user_agent) = value
  request.with_header(
    request_value,
    name: "User-Agent",
    value: user_agent,
    sensitivity: request.Public,
  )
  |> result.map_error(InvalidHeader)
}

pub fn cik(value: String) -> Result(Cik, CikError) {
  case int.parse(value) {
    Error(_) -> Error(InvalidCik)
    Ok(number) -> cik_from_int(number)
  }
}

pub fn cik_from_int(value: Int) -> Result(Cik, CikError) {
  case value >= 0 && value <= 9_999_999_999 {
    False -> Error(InvalidCik)
    True -> {
      let raw = int.to_string(value)
      Ok(Cik(string.repeat("0", 10 - string.length(raw)) <> raw))
    }
  }
}

pub fn cik_value(value: Cik) -> String {
  let Cik(value) = value
  value
}

fn valid_identity(value: String) -> Bool {
  value != ""
  && string.trim(value) == value
  && string.length(value) <= 200
  && !string.contains(value, "\r")
  && !string.contains(value, "\n")
}
