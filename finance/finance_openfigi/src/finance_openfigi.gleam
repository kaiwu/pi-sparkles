import finance_core/time.{type Duration, type Instant}
import finance_http/rate_limit
import finance_http/request
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub const origin = "https://api.openfigi.com"

pub type Status {
  Experimental
}

pub opaque type Access {
  Anonymous
  Authenticated(api_key: String)
}

pub type AccessError {
  InvalidApiKey
  InvalidAuthHeader(request.RequestError)
}

pub type Endpoint {
  Mapping
  Search
}

pub type Limits {
  Limits(
    requests: Int,
    window: Duration,
    maximum_mapping_jobs: Int,
    maximum_results_per_page: Int,
  )
}

pub type LimitError {
  ResetOverflow
  InvalidRateState(rate_limit.RateLimitError)
}

pub fn status() -> Status {
  Experimental
}

pub fn anonymous() -> Access {
  Anonymous
}

pub fn authenticated(api_key: String) -> Result(Access, AccessError) {
  case
    api_key != ""
    && string.trim(api_key) == api_key
    && string.length(api_key) <= 512
    && !string.contains(api_key, "\r")
    && !string.contains(api_key, "\n")
  {
    True -> Ok(Authenticated(api_key))
    False -> Error(InvalidApiKey)
  }
}

pub fn is_authenticated(access: Access) -> Bool {
  case access {
    Anonymous -> False
    Authenticated(_) -> True
  }
}

pub fn access_name(access: Access) -> String {
  case access {
    Anonymous -> "anonymous"
    Authenticated(_) -> "authenticated"
  }
}

/// Remove the configured credential from provider-controlled diagnostic text.
pub fn redact(access: Access, value: String) -> String {
  case access {
    Anonymous -> value
    Authenticated(api_key) -> string.replace(value, api_key, "[REDACTED]")
  }
}

/// Apply authentication without exposing the opaque key to callers.
pub fn authorize(
  access: Access,
  request_value: request.Request,
) -> Result(request.Request, AccessError) {
  case access {
    Anonymous -> Ok(request_value)
    Authenticated(api_key) ->
      request.with_header(
        request_value,
        name: "X-OPENFIGI-APIKEY",
        value: api_key,
        sensitivity: request.Secret,
      )
      |> result.map_error(InvalidAuthHeader)
  }
}

/// Conservative limits from the OpenFIGI v3 documentation.
///
/// Mapping allows 25 requests/minute anonymously or 25/6 seconds with a key.
/// Filter/search allows 5 or 20 requests/minute respectively. Five anonymous
/// mapping jobs is deliberately stricter than older examples that mention ten.
pub fn limits(access: Access, endpoint: Endpoint) -> Limits {
  let assert Ok(six_seconds) = time.duration(6000)
  let assert Ok(one_minute) = time.duration(60_000)
  case access, endpoint {
    Anonymous, Mapping -> Limits(25, one_minute, 5, 100)
    Authenticated(_), Mapping -> Limits(25, six_seconds, 100, 100)
    Anonymous, Search -> Limits(5, one_minute, 5, 100)
    Authenticated(_), Search -> Limits(20, one_minute, 100, 100)
  }
}

pub fn initial_rate_state(
  access: Access,
  endpoint: Endpoint,
  now: Instant,
) -> Result(rate_limit.State, LimitError) {
  let profile = limits(access, endpoint)
  let reset_milliseconds =
    time.unix_milliseconds(now) + time.duration_milliseconds(profile.window)
  use reset_at <- result.try(
    time.instant(reset_milliseconds)
    |> result.map_error(fn(_) { ResetOverflow }),
  )
  rate_limit.new(
    limit: profile.requests,
    remaining: profile.requests,
    reset_at: reset_at,
    window: profile.window,
  )
  |> result.map_error(InvalidRateState)
}

pub fn optional_access(api_key: Option(String)) -> Result(Access, AccessError) {
  case api_key {
    None -> Ok(anonymous())
    Some(value) -> authenticated(value)
  }
}
