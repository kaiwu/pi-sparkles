import finance_core/time
import finance_http/cassette
import finance_http/request
import finance_http/response
import finance_http/retry
import finance_http/transport as http_transport
import finance_http/workflow
import finance_testkit
import finance_testkit/cassette as cassette_testkit
import finance_testkit/clock
import finance_testkit/scenario
import finance_testkit/script
import finance_testkit/seed
import finance_testkit/transport as transport_testkit
import gleam/list
import gleam/option.{None}
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn package_is_implementing_test() {
  finance_testkit.status()
  |> should.equal(finance_testkit.Implementing)
}

pub fn manual_clock_advances_without_wall_time_test() {
  let assert Ok(start) = time.instant(1000)
  let assert Ok(delta) = time.duration(250)
  let assert Ok(advanced) = clock.new(start) |> clock.advance(delta)

  advanced
  |> clock.now
  |> time.unix_milliseconds
  |> should.equal(1250)
  start
  |> time.unix_milliseconds
  |> should.equal(1000)
}

pub fn scripted_results_are_immutable_and_ordered_test() {
  let original = script.new([Ok("first"), Error("rate-limited"), Ok("last")])
  let assert Ok(#(after_first, Ok("first"))) = script.next(original)
  let assert Ok(#(after_second, Error("rate-limited"))) =
    script.next(after_first)

  script.consumed(original)
  |> should.equal(0)
  script.remaining(original)
  |> should.equal(3)
  script.consumed(after_second)
  |> should.equal(2)
  script.remaining(after_second)
  |> should.equal(1)
}

pub fn exhausted_script_is_a_typed_error_test() {
  script.new([])
  |> script.next
  |> should.equal(Error(script.Exhausted))
}

pub fn seeded_generation_is_repeatable_test() {
  let assert Ok(left) = seed.new(42)
  let assert Ok(right) = seed.new(42)
  let #(left_next, left_value) = seed.next(left)
  let #(right_next, right_value) = seed.next(right)

  left_value
  |> should.equal(right_value)
  left_value
  |> should.equal(2_027_382)
  seed.value(left_next)
  |> should.equal(seed.value(right_next))
  seed.value(left)
  |> should.equal(42)
}

pub fn seeded_range_is_explicit_test() {
  let assert Ok(seed) = seed.new(7)
  let assert Ok(#(_, value)) = seed.between(seed, 10, 12)
  let in_range = value >= 10 && value <= 12

  in_range
  |> should.be_true
  seed
  |> seed.between(12, 10)
  |> should.equal(Error(seed.InvalidRange))
}

pub fn scenario_folds_http_workflow_without_an_interpreter_test() {
  let request = test_request()
  let initial = workflow.new(request, test_policy(), duration(0))
  let trace =
    scenario.run(
      initial,
      [
        workflow.Start,
        workflow.TransportFailed(
          1,
          retry.Transport(retry.Timeout),
          duration(10),
        ),
        workflow.SleepFinished(2),
      ],
      workflow.update,
    )

  trace.effects
  |> should.equal([
    workflow.Send(1, request),
    workflow.Sleep(duration(100), 2),
    workflow.Send(2, request),
  ])
  trace.states
  |> list.length
  |> should.equal(4)
  trace.final
  |> workflow.phase
  |> should.equal(workflow.Waiting(2))
}

pub fn cassette_helper_replays_a_complete_pure_scenario_test() {
  let first = test_request()
  let second = test_request_at("/bars")
  let cassette =
    cassette_testkit.from_pairs([
      #(first, cassette.Responded(cassette.Response(200, "quote"))),
      #(second, cassette.Responded(cassette.Response(200, "bars"))),
    ])
  let assert Ok(replay) = cassette_testkit.replay_all(cassette, [first, second])

  replay.outcomes
  |> should.equal([
    cassette.Responded(cassette.Response(200, "quote")),
    cassette.Responded(cassette.Response(200, "bars")),
  ])
  cassette.schema_version(replay.cassette)
  |> should.equal(1)
  cassette.consumed(replay.cassette)
  |> should.equal(2)
}

pub fn scripted_transport_is_pure_ordered_and_captures_only_safe_keys_test() {
  let assert Ok(base) =
    request.new(
      method: request.Get,
      origin: "https://data.example.test",
      path: "/quotes",
      idempotency_key: None,
    )
  let assert Ok(with_secret) =
    request.with_query(
      base,
      name: "api_key",
      value: "never-capture-this",
      sensitivity: request.Secret,
    )
  let assert Ok(success) =
    response.new(
      status: 200,
      headers: [],
      body: "quote",
      byte_length: 5,
      elapsed: duration(10),
    )
  let original =
    transport_testkit.new([Ok(success), Error(http_transport.Timeout)])
  let assert Ok(#(after_success, Ok(actual))) =
    transport_testkit.send(original, with_secret)
  let assert Ok(#(after_timeout, Error(http_transport.Timeout))) =
    transport_testkit.send(after_success, with_secret)

  response.body(actual) |> should.equal("quote")
  transport_testkit.remaining(original) |> should.equal(2)
  transport_testkit.remaining(after_timeout) |> should.equal(0)
  transport_testkit.captured(after_timeout)
  |> should.equal([
    "GET https://data.example.test/quotes?api_key=[REDACTED]",
    "GET https://data.example.test/quotes?api_key=[REDACTED]",
  ])
  transport_testkit.send(after_timeout, with_secret)
  |> should.equal(Error(transport_testkit.Exhausted))
}

fn test_request() -> request.Request {
  test_request_at("/quotes")
}

fn test_request_at(path: String) -> request.Request {
  let assert Ok(value) =
    request.new(
      method: request.Get,
      origin: "https://data.example.test",
      path: path,
      idempotency_key: None,
    )
  value
}

fn test_policy() -> retry.Policy {
  let assert Ok(value) =
    retry.policy(
      maximum_attempts: 3,
      maximum_elapsed: duration(5000),
      base_delay: duration(100),
      maximum_delay: duration(1000),
    )
  value
}

fn duration(milliseconds: Int) -> time.Duration {
  let assert Ok(value) = time.duration(milliseconds)
  value
}
