import finance_broker_review
import finance_broker_review/decode
import finance_execution/tape_scenario
import finance_execution/tape_scenario_decode
import gleam/javascript/promise.{type Promise}
import gleam/option.{Some}
import pi
import pi/finance/tape_scenario_schema
import pi/schema
import pi/tool
import pi_sparkles_broker_paper_ibkr/domain

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  tool.register(
    api,
    "review_ibkr_paper_evidence",
    "Review an external IBKR paper receipt packet",
    "Validate bounded normalized IBKR paper-account, order, fill, capability, entitlement, and lifecycle evidence from the explicit external read-only provider capability",
    "IBKR is an external dependency. This plugin ships no Gateway, SDK, credential, adapter, network transport, or broker mutation surface.",
    tool.parameters(review_schema(), decode.explicit_capability_input()),
    tool.Parallel,
    fn(_id, input, _signal, _updates, _ctx) {
      case domain.run(input) {
        Ok(value) ->
          tool.text_result(
            finance_broker_review.summary(value),
            finance_broker_review.details(value),
          )
          |> promise.resolve
        Error(error) -> tool.reject(finance_broker_review.error_message(error))
      }
    },
  )
  register_simulation(api)
  promise.resolve(Nil)
}

fn register_simulation(api: pi.ExtensionApi) -> Nil {
  tool.register(
    api,
    "simulate_ibkr_tape_possible_fill",
    "Simulate one IBKR transaction-tape possible-fill scenario",
    "Apply the named provider-neutral transaction_tape_possible_fill_v1 model to one exact US limit instruction and bounded external IBKR transaction tape, retaining eligible prints, exclusions, sequence limitations, and both non-fill and possible-fill branches",
    "This deterministic model never proves a fill or queue position and cannot place, route, cancel, replace, or otherwise mutate an order.",
    tool.parameters(
      tape_scenario_schema.input(schema.string_enum(["ibkr"]), ["us"], [
        "XNYS",
        "XNAS",
      ]),
      tape_scenario_decode.input(),
    ),
    tool.Parallel,
    fn(_id, input, signal, _updates, _ctx) {
      case tool.is_cancelled(signal) {
        True -> tool.reject("IBKR possible-fill simulation was cancelled")
        False ->
          case tape_scenario.run(input, "us", Some("ibkr")) {
            Ok(value) ->
              tool.text_result(
                tape_scenario.summary(value),
                tape_scenario.details(value),
              )
              |> promise.resolve
            Error(error) -> tool.reject(tape_scenario.error_message(error))
          }
      }
    },
  )
}

fn review_schema() -> schema.Schema {
  schema.object([
    schema.Required("provider", schema.string_enum(["ibkr"])),
    schema.Required("operationId", bounded_string(1, 500)),
    schema.Required("mode", schema.string_enum(["external_paper_receipt"])),
    schema.Required("environment", schema.string_enum(["external_paper"])),
    schema.Required("accountReference", hash_schema()),
    schema.Required("track", schema.string_enum(["us"])),
    schema.Required("listingId", bounded_string(1, 500)),
    schema.Required("mic", bounded_string(1, 50)),
    schema.Required("sourceContentHash", hash_schema()),
    schema.Required(
      "facts",
      schema.array(fact_schema()) |> schema.with_array_length(0, 200),
    ),
    schema.Required(
      "events",
      schema.array(event_schema()) |> schema.with_array_length(0, 500),
    ),
    schema.Required(
      "missingCapabilities",
      schema.array(bounded_string(1, 200)) |> schema.with_array_length(0, 100),
    ),
  ])
}

fn fact_schema() -> schema.Schema {
  schema.object([
    schema.Required("name", bounded_string(1, 200)),
    schema.Required(
      "state",
      schema.string_enum([
        "known",
        "unknown",
        "unavailable",
        "conflicting",
        "not_applicable",
      ]),
    ),
    schema.Optional("value", schema.nullable(bounded_string(1, 4000))),
    schema.Optional("unit", schema.nullable(bounded_string(1, 100))),
    schema.Required("sourceReference", hash_schema()),
  ])
}

fn event_schema() -> schema.Schema {
  schema.object([
    schema.Required("eventReference", hash_schema()),
    schema.Required("statusLexeme", bounded_string(1, 500)),
    schema.Required(
      "occurredAtUnixMilliseconds",
      schema.integer() |> schema.with_number_range(0.0, 9_007_199_254_740_991.0),
    ),
    schema.Required("sourceReference", hash_schema()),
  ])
}

fn bounded_string(minimum: Int, maximum: Int) -> schema.Schema {
  schema.string() |> schema.with_string_length(minimum, maximum)
}

fn hash_schema() -> schema.Schema {
  bounded_string(64, 64)
}
