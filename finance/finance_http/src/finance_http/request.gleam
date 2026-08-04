import gleam/option.{type Option, None, Some}
import gleam/string

pub type Method {
  Get
  Head
  Options
  Post
  Put
  Patch
  Delete
}

pub type Idempotency {
  NaturallyIdempotent
  IdempotencyKey(String)
  NonIdempotent
}

pub opaque type Request {
  Request(
    method: Method,
    origin: String,
    path: String,
    idempotency: Idempotency,
  )
}

pub type RequestError {
  InvalidOrigin
  InvalidPath
  InvalidIdempotencyKey
}

pub fn new(
  method method: Method,
  origin origin: String,
  path path: String,
  idempotency_key idempotency_key: Option(String),
) -> Result(Request, RequestError) {
  case valid_origin(origin), string.starts_with(path, "/") {
    False, _ -> Error(InvalidOrigin)
    _, False -> Error(InvalidPath)
    True, True ->
      case classify_idempotency(method, idempotency_key) {
        Error(error) -> Error(error)
        Ok(idempotency) -> Ok(Request(method, origin, path, idempotency))
      }
  }
}

pub fn method(request: Request) -> Method {
  let Request(method, _, _, _) = request
  method
}

pub fn origin(request: Request) -> String {
  let Request(_, origin, _, _) = request
  origin
}

pub fn path(request: Request) -> String {
  let Request(_, _, path, _) = request
  path
}

pub fn idempotency(request: Request) -> Idempotency {
  let Request(_, _, _, idempotency) = request
  idempotency
}

pub fn can_retry(request: Request) -> Bool {
  case idempotency(request) {
    NaturallyIdempotent | IdempotencyKey(_) -> True
    NonIdempotent -> False
  }
}

fn classify_idempotency(
  method: Method,
  key: Option(String),
) -> Result(Idempotency, RequestError) {
  case method, key {
    Get, _ | Head, _ | Options, _ | Put, _ | Delete, _ ->
      Ok(NaturallyIdempotent)
    _, Some(key) ->
      case key != "" && string.trim(key) == key {
        True -> Ok(IdempotencyKey(key))
        False -> Error(InvalidIdempotencyKey)
      }
    _, None -> Ok(NonIdempotent)
  }
}

fn valid_origin(origin: String) -> Bool {
  case origin {
    "https://" <> authority ->
      authority != ""
      && !string.contains(authority, "/")
      && !string.contains(authority, "@")
      && !string.contains(authority, "?")
      && !string.contains(authority, "#")
      && string.trim(authority) == authority
    _ -> False
  }
}
