import finance_http/request
import gleam/result
import gleam/string

pub type Status {
  Experimental
}

pub opaque type Access {
  Access(key_id: String, secret_key: String, user_agent: String)
}

pub type AccessError {
  InvalidKeyId
  InvalidSecretKey
  InvalidProduct
  InvalidContact
  InvalidHeader(request.RequestError)
}

pub fn status() -> Status {
  Experimental
}

pub fn access(
  key_id: String,
  secret_key: String,
  product: String,
  contact: String,
) -> Result(Access, AccessError) {
  case
    valid_secret(key_id),
    valid_secret(secret_key),
    valid_identity(product),
    valid_identity(contact)
  {
    False, _, _, _ -> Error(InvalidKeyId)
    _, False, _, _ -> Error(InvalidSecretKey)
    _, _, False, _ -> Error(InvalidProduct)
    _, _, _, False -> Error(InvalidContact)
    True, True, True, True ->
      Ok(Access(key_id, secret_key, product <> " " <> contact))
  }
}

pub fn authorize(
  value: Access,
  request_value: request.Request,
) -> Result(request.Request, AccessError) {
  use with_id <- result.try(
    request.with_header(
      request_value,
      name: "APCA-API-KEY-ID",
      value: value.key_id,
      sensitivity: request.Secret,
    )
    |> result.map_error(InvalidHeader),
  )
  use with_secret <- result.try(
    request.with_header(
      with_id,
      name: "APCA-API-SECRET-KEY",
      value: value.secret_key,
      sensitivity: request.Secret,
    )
    |> result.map_error(InvalidHeader),
  )
  request.with_header(
    with_secret,
    name: "User-Agent",
    value: value.user_agent,
    sensitivity: request.Public,
  )
  |> result.map_error(InvalidHeader)
}

fn valid_secret(value: String) -> Bool {
  value != ""
  && string.length(value) <= 500
  && !string.contains(value, "\r")
  && !string.contains(value, "\n")
}

fn valid_identity(value: String) -> Bool {
  value != ""
  && string.trim(value) == value
  && string.length(value) <= 200
  && !string.contains(value, "\r")
  && !string.contains(value, "\n")
}
