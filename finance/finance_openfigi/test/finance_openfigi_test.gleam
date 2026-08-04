import finance_core/time
import finance_http/rate_limit
import finance_http/request
import finance_http/response as http_response
import finance_http/transport
import finance_openfigi
import finance_openfigi/mapping
import finance_openfigi/response
import finance_openfigi/runtime
import finance_openfigi/search
import gleam/javascript/promise
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn package_is_experimental_test() {
  finance_openfigi.status()
  |> should.equal(finance_openfigi.Experimental)
}

pub fn access_is_opaque_validated_and_secret_header_is_labelled_test() {
  finance_openfigi.authenticated("")
  |> should.equal(Error(finance_openfigi.InvalidApiKey))
  let assert Ok(access) = finance_openfigi.authenticated("fixture-key")
  let assert Ok(id_type) = mapping.id_type("TICKER")
  let assert Ok(job) = mapping.job(id_type, "IBM", None)
  let assert Ok(value) = mapping.request(access, [job])
  request.headers(value)
  |> should.equal([
    request.Header("x-openfigi-apikey", "fixture-key", request.Secret),
  ])
  request.safe_key(value)
  |> string.contains("fixture-key")
  |> should.be_false
  finance_openfigi.redact(access, "provider echoed fixture-key")
  |> should.equal("provider echoed [REDACTED]")
}

pub fn anonymous_and_authenticated_limits_are_endpoint_specific_test() {
  let anonymous = finance_openfigi.anonymous()
  let assert Ok(authenticated) = finance_openfigi.authenticated("fixture-key")
  finance_openfigi.limits(anonymous, finance_openfigi.Mapping).requests
  |> should.equal(25)
  finance_openfigi.limits(anonymous, finance_openfigi.Search).requests
  |> should.equal(5)
  finance_openfigi.limits(authenticated, finance_openfigi.Search).requests
  |> should.equal(20)
  finance_openfigi.limits(authenticated, finance_openfigi.Mapping).maximum_mapping_jobs
  |> should.equal(100)
}

pub fn initial_rate_state_obeys_the_selected_profile_test() {
  let assert Ok(now) = time.instant(1000)
  let assert Ok(state) =
    finance_openfigi.initial_rate_state(
      finance_openfigi.anonymous(),
      finance_openfigi.Search,
      now,
    )
  let assert Ok(#(after, rate_limit.Permit)) = rate_limit.acquire(state, now)
  rate_limit.remaining(after) |> should.equal(4)
  time.unix_milliseconds(rate_limit.reset_at(after))
  |> should.equal(61_000)
}

pub fn mapping_batch_limit_and_v3_request_are_deterministic_test() {
  let assert Ok(id_type) = mapping.id_type("ID_BB_GLOBAL")
  let assert Ok(job) = mapping.job(id_type, "BBG000BLNNH6", None)
  let assert Ok(value) = mapping.request(finance_openfigi.anonymous(), [job])
  request.path(value) |> should.equal("/v3/mapping")
  request.can_retry(value) |> should.be_true
  request.idempotency_key(value) |> should.equal(None)
  request.maximum_response_bytes(value) |> should.equal(500_000)
  request.timeout(value) |> time.duration_milliseconds |> should.equal(10_000)
  request.safe_key(value)
  |> string.contains("ID_BB_GLOBAL")
  |> should.be_true
}

pub fn search_pagination_is_an_explicit_immutable_plan_test() {
  let assert Ok(first) =
    search.query("International Business Machines", Some("xnys"))
  let page = response.ResultSet([], None, None, Some("next-cursor"), Some(101))
  let assert Some(second) = search.next(first, page)
  let assert Ok(first_request) =
    search.request(finance_openfigi.anonymous(), first)
  let assert Ok(second_request) =
    search.request(finance_openfigi.anonymous(), second)
  request.safe_key(first_request)
  |> should.not_equal(request.safe_key(second_request))
  request.safe_key(second_request)
  |> string.contains("next-cursor")
  |> should.be_true
}

pub fn v3_mapping_and_search_fixtures_decode_nullable_fields_test() {
  let mapping_fixture =
    "[{\"data\":[{\"figi\":\"BBG000BLNNH6\",\"name\":\"INTL BUSINESS MACHINES CORP\",\"ticker\":\"IBM\",\"exchCode\":\"US\",\"compositeFIGI\":\"BBG000BLNNH6\",\"securityType2\":\"Common Stock\",\"marketSector\":\"Equity\",\"shareClassFIGI\":null}]}]"
  let assert Ok(results) = response.decode_mapping(mapping_fixture)
  let first = response.first_mapping_result(results)
  let assert Ok(candidate) = list.first(first.candidates)
  candidate.figi |> should.equal("BBG000BLNNH6")
  candidate.share_class_figi |> should.equal(None)

  let assert Ok(page) =
    response.decode_search("{\"data\":[],\"next\":\"cursor\",\"total\":101}")
  page.next |> should.equal(Some("cursor"))
  page.total |> should.equal(Some(101))
}

pub fn runtime_constructs_without_network_or_credentials_test() {
  runtime.new(finance_openfigi.anonymous())
  |> should.be_ok
}

pub fn runtime_paces_each_attempt_with_injected_effects_test() {
  let assert Ok(now) = time.instant(1000)
  let assert Ok(query) = search.query("IBM", None)
  let assert Ok(request_value) =
    search.request(finance_openfigi.anonymous(), query)
  let assert Ok(provider_runtime) =
    runtime.new_with(
      finance_openfigi.anonymous(),
      fn(_, _) { promise.resolve(Ok(http_ok())) },
      fn(duration, _) {
        time.duration_milliseconds(duration) |> should.equal(60_000)
        promise.resolve(False)
      },
      fn() { now },
    )

  use first <- promise.await(send(provider_runtime, "search-1", request_value))
  use second <- promise.await(send(provider_runtime, "search-2", request_value))
  use third <- promise.await(send(provider_runtime, "search-3", request_value))
  use fourth <- promise.await(send(provider_runtime, "search-4", request_value))
  use fifth <- promise.await(send(provider_runtime, "search-5", request_value))
  use sixth <- promise.await(send(provider_runtime, "search-6", request_value))
  first |> should.be_ok
  second |> should.be_ok
  third |> should.be_ok
  fourth |> should.be_ok
  fifth |> should.be_ok
  sixth |> should.be_error
  promise.resolve(Nil)
}

fn send(
  runtime_value: runtime.Runtime,
  id: String,
  request_value: request.Request,
) {
  runtime.send(
    runtime_value,
    id: id,
    request: request_value,
    cancellation: transport.new_cancellation(),
  )
}

fn http_ok() -> http_response.Response {
  let assert Ok(value) =
    http_response.new(
      status: 200,
      headers: [],
      body: "{\"data\":[]}",
      byte_length: 11,
      elapsed: duration(1),
    )
  value
}

fn duration(milliseconds: Int) -> time.Duration {
  let assert Ok(value) = time.duration(milliseconds)
  value
}
