import finance_core/time
import finance_http
import finance_http/request
import finance_http/retry
import gleam/option.{type Option, None, Some}
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn package_is_implementing_test() {
  finance_http.status()
  |> should.equal(finance_http.Implementing)
}

pub fn request_rejects_credential_bearing_origin_test() {
  request.new(
    method: request.Get,
    origin: "https://token@example.test",
    path: "/quotes",
    idempotency_key: None,
  )
  |> should.equal(Error(request.InvalidOrigin))
  request.new(
    method: request.Get,
    origin: "https://example.test/path",
    path: "/quotes",
    idempotency_key: None,
  )
  |> should.equal(Error(request.InvalidOrigin))
}

pub fn post_requires_idempotency_key_to_retry_test() {
  let post = post_request(None)

  retry.decide(
    retry_policy(),
    post,
    1,
    duration(0),
    retry.Transport(retry.Timeout),
  )
  |> should.equal(retry.Stop(retry.NonIdempotentRequest))
}

pub fn keyed_post_can_retry_test() {
  let post = post_request(Some("order-123"))

  retry.decide(
    retry_policy(),
    post,
    1,
    duration(0),
    retry.Transport(retry.ConnectionReset),
  )
  |> should.equal(retry.RetryAfter(duration(100), 2))
}

pub fn retry_after_is_respected_and_bounded_test() {
  retry.decide(
    retry_policy(),
    get_request(),
    1,
    duration(0),
    retry.Status(429, Some(duration(10_000))),
  )
  |> should.equal(retry.RetryAfter(duration(1000), 2))
}

pub fn exponential_backoff_is_pure_and_capped_test() {
  let policy = retry_policy()
  let request = get_request()

  retry.decide(
    policy,
    request,
    2,
    duration(50),
    retry.Transport(retry.NetworkUnavailable),
  )
  |> should.equal(retry.RetryAfter(duration(200), 3))
  retry.decide(
    policy,
    request,
    4,
    duration(50),
    retry.Transport(retry.NetworkUnavailable),
  )
  |> should.equal(retry.RetryAfter(duration(800), 5))
}

pub fn retry_stops_for_permanent_and_exhausted_failures_test() {
  let policy = retry_policy()
  let request = get_request()

  retry.decide(
    policy,
    request,
    1,
    duration(0),
    retry.Transport(retry.CertificateFailure),
  )
  |> should.equal(retry.Stop(retry.PermanentFailure))
  retry.decide(policy, request, 5, duration(100), retry.Status(503, None))
  |> should.equal(retry.Stop(retry.AttemptsExhausted))
}

pub fn retry_does_not_schedule_past_elapsed_budget_test() {
  retry.decide(
    retry_policy(),
    get_request(),
    1,
    duration(4950),
    retry.Transport(retry.Timeout),
  )
  |> should.equal(retry.Stop(retry.ElapsedBudgetExhausted))
}

fn retry_policy() -> retry.Policy {
  let assert Ok(policy) =
    retry.policy(
      maximum_attempts: 5,
      maximum_elapsed: duration(5000),
      base_delay: duration(100),
      maximum_delay: duration(1000),
    )
  policy
}

fn get_request() -> request.Request {
  let assert Ok(value) =
    request.new(
      method: request.Get,
      origin: "https://data.example.test",
      path: "/quotes",
      idempotency_key: None,
    )
  value
}

fn post_request(key: Option(String)) -> request.Request {
  let assert Ok(value) =
    request.new(
      method: request.Post,
      origin: "https://data.example.test",
      path: "/query",
      idempotency_key: key,
    )
  value
}

fn duration(milliseconds: Int) -> time.Duration {
  let assert Ok(value) = time.duration(milliseconds)
  value
}
