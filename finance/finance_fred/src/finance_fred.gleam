import finance_http/request
import gleam/list
import gleam/result
import gleam/string

pub type Status {
  Experimental
}

pub opaque type Access {
  Access(api_key: String)
}

pub type AccessError {
  InvalidApiKey
  InvalidRequest(request.RequestError)
}

pub fn status() -> Status {
  Experimental
}

/// Validate the per-user FRED v1 API key without exposing it to callers.
pub fn access(api_key: String) -> Result(Access, AccessError) {
  case
    string.length(api_key) == 32
    && {
      api_key
      |> string.to_graphemes
      |> list.all(fn(character) {
        string.contains("abcdefghijklmnopqrstuvwxyz0123456789", character)
      })
    }
  {
    True -> Ok(Access(api_key))
    False -> Error(InvalidApiKey)
  }
}

/// Add the FRED credential as a secret query parameter.
pub fn authorize(
  access: Access,
  request_value: request.Request,
) -> Result(request.Request, AccessError) {
  request.with_query(
    request_value,
    name: "api_key",
    value: access.api_key,
    sensitivity: request.Secret,
  )
  |> result.map_error(InvalidRequest)
}
