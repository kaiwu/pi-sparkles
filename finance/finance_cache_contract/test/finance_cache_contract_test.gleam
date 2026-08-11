import finance_cache_contract as cache
import finance_cache_contract/http
import finance_core/time
import finance_http/request
import finance_http/response
import gleam/list
import gleam/option.{None}
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn targeted_expiry_requires_matching_content_test() {
  let value = fixture_entry("a", "b")
  let assert Ok(stored) = cache.apply(cache.empty(), cache.stored(value))
  let assert Ok(expiry) =
    cache.expired(hash("a"), hash("c"), 3000, "operator_request")
  cache.apply(stored, expiry) |> should.equal(Error(cache.ContentHashMismatch))
}

pub fn event_round_trip_and_replay_test() {
  let event = cache.stored(fixture_entry("a", "b"))
  let assert Ok(decoded) = event |> cache.encode_event |> cache.decode_event
  let assert Ok(state) = cache.replay([decoded])
  cache.entries(state) |> list.length |> should.equal(1)
}

pub fn unsafe_request_identity_is_rejected_test() {
  cache.entry(
    hash("a"),
    "provider",
    "https://example.com/data",
    hash("b"),
    1000,
    2000,
    3000,
    2,
    "local_analysis",
    "provider_terms",
    "token=secret",
    hash("c"),
    "schema_validated",
    "{}",
  )
  |> should.equal(Error(cache.UnsafeRequestIdentity))
}

pub fn http_capture_uses_only_the_redacted_safe_request_test() {
  let assert Ok(base) =
    request.new(request.Post, "https://example.com", "/", None)
  let assert Ok(with_body) =
    request.with_text_body(
      base,
      "application/json",
      "{\"token\":\"actual-secret\"}",
      "{\"token\":\"[REDACTED]\",\"query\":\"000001.SZ\"}",
    )
  let assert Ok(duration) = time.duration(1)
  let assert Ok(response) = response.new(200, [], "{}", 2, duration)
  let assert Ok(value) =
    http.capture(
      with_body,
      response,
      "provider",
      "https://example.com/data",
      1000,
      2000,
      3000,
      "local_analysis",
      "provider_terms",
      "schema_validated",
    )
  cache.safe_request_identity(value)
  |> string.contains("actual-secret")
  |> should.be_false
}

fn fixture_entry(key: String, content: String) -> cache.Entry {
  let assert Ok(value) =
    cache.entry(
      hash(key),
      "provider",
      "https://example.com/data",
      hash("d"),
      1000,
      2000,
      3000,
      2,
      "local_analysis",
      "provider_terms",
      "daily:000001.SZ",
      hash(content),
      "schema_validated",
      "{}",
    )
  value
}

fn hash(seed: String) -> String {
  let fill = case seed {
    "" -> "0"
    value -> string.slice(value, 0, 1)
  }
  string.repeat(fill, 64)
}
