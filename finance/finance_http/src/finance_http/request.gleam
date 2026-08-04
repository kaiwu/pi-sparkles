import finance_core/time.{type Duration}
import gleam/list
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

pub type Sensitivity {
  Public
  Secret
}

pub type Header {
  Header(name: String, value: String, sensitivity: Sensitivity)
}

pub type QueryParameter {
  QueryParameter(name: String, value: String, sensitivity: Sensitivity)
}

pub type Body {
  TextBody(content_type: String, value: String)
}

pub opaque type Request {
  Request(
    method: Method,
    origin: String,
    path: String,
    idempotency: Idempotency,
    headers: List(Header),
    query: List(QueryParameter),
    body: Option(Body),
    timeout: Duration,
    maximum_response_bytes: Int,
    safe_variant: Option(String),
  )
}

pub type RequestError {
  InvalidOrigin
  InvalidPath
  InvalidIdempotencyKey
  InvalidHeaderName
  InvalidHeaderValue
  InvalidQueryName
  InvalidContentType
  InvalidSafeVariant
  BodyNotAllowed
  NonPositiveResponseLimit
}

pub fn new(
  method method: Method,
  origin origin: String,
  path path: String,
  idempotency_key idempotency_key: Option(String),
) -> Result(Request, RequestError) {
  case
    valid_origin(origin),
    string.starts_with(path, "/")
    && !string.contains(path, "?")
    && !string.contains(path, "#")
  {
    False, _ -> Error(InvalidOrigin)
    _, False -> Error(InvalidPath)
    True, True ->
      case classify_idempotency(method, idempotency_key) {
        Error(error) -> Error(error)
        Ok(idempotency) -> {
          let assert Ok(timeout) = time.duration(30_000)
          Ok(Request(
            method,
            origin,
            path,
            idempotency,
            [],
            [],
            None,
            timeout,
            1_000_000,
            None,
          ))
        }
      }
  }
}

pub fn with_header(
  request: Request,
  name name: String,
  value value: String,
  sensitivity sensitivity: Sensitivity,
) -> Result(Request, RequestError) {
  case valid_header_name(name), valid_header_value(value) {
    False, _ -> Error(InvalidHeaderName)
    _, False -> Error(InvalidHeaderValue)
    True, True -> {
      let Request(
        method,
        origin,
        path,
        idempotency,
        headers,
        query,
        body,
        timeout,
        maximum_response_bytes,
        safe_variant,
      ) = request
      Ok(Request(
        method,
        origin,
        path,
        idempotency,
        list.append(headers, [
          Header(string.lowercase(name), value, sensitivity),
        ]),
        query,
        body,
        timeout,
        maximum_response_bytes,
        safe_variant,
      ))
    }
  }
}

pub fn with_query(
  request: Request,
  name name: String,
  value value: String,
  sensitivity sensitivity: Sensitivity,
) -> Result(Request, RequestError) {
  case valid_query_name(name) {
    False -> Error(InvalidQueryName)
    True -> {
      let Request(
        method,
        origin,
        path,
        idempotency,
        headers,
        query,
        body,
        timeout,
        maximum_response_bytes,
        safe_variant,
      ) = request
      Ok(Request(
        method,
        origin,
        path,
        idempotency,
        headers,
        list.append(query, [QueryParameter(name, value, sensitivity)]),
        body,
        timeout,
        maximum_response_bytes,
        safe_variant,
      ))
    }
  }
}

pub fn with_text_body(
  request: Request,
  content_type content_type: String,
  value value: String,
  safe_variant safe_variant: String,
) -> Result(Request, RequestError) {
  case
    method(request),
    valid_content_type(content_type),
    valid_variant(safe_variant)
  {
    Get, _, _ | Head, _, _ -> Error(BodyNotAllowed)
    _, False, _ -> Error(InvalidContentType)
    _, _, False -> Error(InvalidSafeVariant)
    _, True, True -> {
      let Request(
        method,
        origin,
        path,
        idempotency,
        headers,
        query,
        _,
        timeout,
        maximum_response_bytes,
        _,
      ) = request
      Ok(Request(
        method,
        origin,
        path,
        idempotency,
        headers,
        query,
        Some(TextBody(content_type, value)),
        timeout,
        maximum_response_bytes,
        Some(safe_variant),
      ))
    }
  }
}

pub fn with_limits(
  request: Request,
  timeout timeout: Duration,
  maximum_response_bytes maximum_response_bytes: Int,
) -> Result(Request, RequestError) {
  case maximum_response_bytes > 0 {
    False -> Error(NonPositiveResponseLimit)
    True -> {
      let Request(
        method,
        origin,
        path,
        idempotency,
        headers,
        query,
        body,
        _,
        _,
        safe_variant,
      ) = request
      Ok(Request(
        method,
        origin,
        path,
        idempotency,
        headers,
        query,
        body,
        timeout,
        maximum_response_bytes,
        safe_variant,
      ))
    }
  }
}

pub fn method(request: Request) -> Method {
  let Request(method, ..) = request
  method
}

pub fn origin(request: Request) -> String {
  let Request(_, origin, ..) = request
  origin
}

pub fn path(request: Request) -> String {
  let Request(_, _, path, ..) = request
  path
}

pub fn idempotency(request: Request) -> Idempotency {
  let Request(_, _, _, idempotency, ..) = request
  idempotency
}

pub fn idempotency_key(request: Request) -> Option(String) {
  case idempotency(request) {
    IdempotencyKey(key) -> Some(key)
    NaturallyIdempotent | NonIdempotent -> None
  }
}

pub fn headers(request: Request) -> List(Header) {
  let Request(_, _, _, _, headers, ..) = request
  headers
}

pub fn query(request: Request) -> List(QueryParameter) {
  let Request(_, _, _, _, _, query, ..) = request
  query
}

pub fn body(request: Request) -> Option(Body) {
  let Request(_, _, _, _, _, _, body, ..) = request
  body
}

pub fn timeout(request: Request) -> Duration {
  let Request(_, _, _, _, _, _, _, timeout, ..) = request
  timeout
}

pub fn maximum_response_bytes(request: Request) -> Int {
  let Request(_, _, _, _, _, _, _, _, maximum, _) = request
  maximum
}

pub fn can_retry(request: Request) -> Bool {
  case idempotency(request) {
    NaturallyIdempotent | IdempotencyKey(_) -> True
    NonIdempotent -> False
  }
}

pub fn safe_key(request: Request) -> String {
  let Request(_, _, _, _, _, query, _, _, _, safe_variant) = request
  let query_key =
    query
    |> list.map(fn(parameter) {
      let QueryParameter(name, value, sensitivity) = parameter
      case sensitivity {
        Public -> name <> "=" <> value
        Secret -> name <> "=[REDACTED]"
      }
    })
    |> list.sort(by: string.compare)
    |> string.join("&")
  let suffix = case query_key, safe_variant {
    "", None -> ""
    "", Some(variant) -> " variant=" <> variant
    query, None -> "?" <> query
    query, Some(variant) -> "?" <> query <> " variant=" <> variant
  }
  method_name(method(request))
  <> " "
  <> origin(request)
  <> path(request)
  <> suffix
}

pub fn method_name(method: Method) -> String {
  case method {
    Get -> "GET"
    Head -> "HEAD"
    Options -> "OPTIONS"
    Post -> "POST"
    Put -> "PUT"
    Patch -> "PATCH"
    Delete -> "DELETE"
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
      case valid_variant(key) {
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

fn valid_header_name(name: String) -> Bool {
  name != ""
  && {
    name
    |> string.to_graphemes
    |> list.all(fn(character) {
      string.contains(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!#$%&'*+-.^_`|~",
        character,
      )
    })
  }
}

fn valid_header_value(value: String) -> Bool {
  !string.contains(value, "\r") && !string.contains(value, "\n")
}

fn valid_query_name(name: String) -> Bool {
  name != ""
  && string.trim(name) == name
  && !string.contains(name, "&")
  && !string.contains(name, "=")
  && !string.contains(name, "#")
}

fn valid_content_type(value: String) -> Bool {
  value != ""
  && string.trim(value) == value
  && !string.contains(value, "\r")
  && !string.contains(value, "\n")
}

fn valid_variant(value: String) -> Bool {
  value != ""
  && string.trim(value) == value
  && !string.contains(value, "\r")
  && !string.contains(value, "\n")
}
