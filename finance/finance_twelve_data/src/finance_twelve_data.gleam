import finance_http/request
import gleam/list
import gleam/result
import gleam/string

pub opaque type Access {
  Access(api_key: String)
}

pub type AccessError {
  InvalidApiKey
  InvalidRequest(request.RequestError)
}

/// Keep the caller's Twelve Data credential opaque and out of result values.
pub fn access(api_key: String) -> Result(Access, AccessError) {
  case
    string.length(api_key) >= 8
    && string.length(api_key) <= 200
    && string.trim(api_key) == api_key
    && {
      api_key
      |> string.to_graphemes
      |> list.all(fn(character) { !string.contains(" \t\r\n", character) })
    }
  {
    True -> Ok(Access(api_key))
    False -> Error(InvalidApiKey)
  }
}

/// Use Twelve Data's recommended authorization header without exposing the key.
pub fn authorize(
  access: Access,
  request_value: request.Request,
) -> Result(request.Request, AccessError) {
  let Access(api_key) = access
  request.with_header(
    request_value,
    name: "Authorization",
    value: "apikey " <> api_key,
    sensitivity: request.Secret,
  )
  |> result.map_error(InvalidRequest)
}
