import finance_broker_review
import finance_broker_review/decode
import finance_execution/tape_scenario
import finance_execution/tape_scenario_decode
import gleam/javascript/promise.{type Promise}
import gleam/option.{None}
import pi
import pi/finance/tape_scenario_schema
import pi/schema
import pi/tool
import pi_sparkles_cn_broker_paper/domain

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  tool.register(
    api,
    "review_cn_paper_evidence",
    "Review an external CN paper receipt packet",
    "Validate bounded normalized CN paper-account, order, fill, capability, entitlement, and lifecycle evidence from one explicitly selected external read-only provider capability",
    "The provider is an external dependency. This plugin ships no SDK, credential, adapter, network transport, or broker mutation surface.",
    tool.parameters(
      review_schema(["external_paper_receipt"], ["external_paper"], ["cn"]),
      decode.explicit_capability_input(),
    ),
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
    "simulate_cn_tape_possible_fill",
    "Simulate one CN transaction-tape possible-fill scenario",
    "Apply the named provider-neutral transaction_tape_possible_fill_v1 model to one exact CN limit instruction and bounded external transaction tape, retaining eligible prints, exclusions, sequence limitations, and both non-fill and possible-fill branches",
    "This deterministic model never proves a fill or queue position and cannot place, route, cancel, replace, or otherwise mutate an order.",
    tool.parameters(
      tape_scenario_schema.input(bounded_string(1, 200), ["cn"], [
        "XSHG",
        "XSHE",
        "XBSE",
      ]),
      tape_scenario_decode.input(),
    ),
    tool.Parallel,
    fn(_id, input, signal, _updates, _ctx) {
      case tool.is_cancelled(signal) {
        True -> tool.reject("CN possible-fill simulation was cancelled")
        False ->
          case tape_scenario.run(input, "cn", None) {
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

fn review_schema(
  modes: List(String),
  environments: List(String),
  tracks: List(String),
) -> schema.Schema {
  schema.object([
    schema.Required("provider", bounded_string(1, 100)),
    schema.Required("operationId", bounded_string(1, 500)),
    schema.Required("mode", schema.string_enum(modes)),
    schema.Required("environment", schema.string_enum(environments)),
    schema.Required("accountReference", hash_schema()),
    schema.Required("track", schema.string_enum(tracks)),
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
