import gleam/int
import gleam/javascript/promise.{type Promise}
import pi
import pi/schema
import pi/tool
import pi_sparkles_trade_compliance/advanced_decode as decode
import pi_sparkles_trade_compliance/advanced_domain as domain

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  register_evaluate(api)
  register_explain(api)
  register_compare(api)
  promise.resolve(Nil)
}

fn register_evaluate(api: pi.ExtensionApi) -> Nil {
  tool.register(
    api,
    "evaluate_supplied_trade_rules",
    "Evaluate supplied typed trade rules",
    "Evaluate bounded caller-supplied, effective-dated compound boolean rules independently as True, False, Unknown, NotApplicable, or Conflict with complete predicate explanation trees and correction lineage",
    "A rule provider is an explicit external dependency. This package authenticates no authority or completeness, performs no network request, produces no aggregate legal verdict, and cannot mutate an order or account.",
    tool.parameters(evaluation_schema(), decode.evaluation_input()),
    tool.Parallel,
    fn(_id, input, signal, _updates, _ctx) {
      complete(signal, domain.evaluate(input))
    },
  )
}

fn register_explain(api: pi.ExtensionApi) -> Nil {
  tool.register(
    api,
    "explain_supplied_trade_predicate",
    "Explain one supplied typed compliance expression",
    "Evaluate one bounded prefix-encoded predicate, all, any, or negated expression and retain every child explanation, matched fact, conflict, unknown, not-applicable state, and exact duplicate count",
    "This is mechanical explanation over supplied facts, not legal interpretation, provider authentication, an aggregate verdict, or execution authority.",
    tool.parameters(explanation_schema(), decode.explanation_input()),
    tool.Parallel,
    fn(_id, input, signal, _updates, _ctx) {
      complete(signal, domain.explain(input))
    },
  )
}

fn register_compare(api: pi.ExtensionApi) -> Nil {
  tool.register(
    api,
    "compare_supplied_trade_rule_versions",
    "Compare two supplied compliance-rule versions",
    "Compare two bounded versions of the same supplied rule across scope, effective interval, typed expression, severity, authority receipt, and declared correction links",
    "Correction lineage is validated within the supplied pair but remains caller-supplied; it is not proof that an authority issued either version.",
    tool.parameters(comparison_schema(), decode.comparison_input()),
    tool.Parallel,
    fn(_id, input, signal, _updates, _ctx) {
      complete(signal, domain.compare(input))
    },
  )
}

fn complete(
  signal: pi.AbortSignal,
  outcome: Result(domain.Response, domain.DomainError),
) -> Promise(tool.ToolResult) {
  case tool.is_cancelled(signal) {
    True -> tool.reject("Trade-compliance review was cancelled")
    False ->
      case outcome {
        Ok(value) ->
          tool.text_result(domain.summary(value), domain.details(value))
          |> promise.resolve
        Error(error) -> tool.reject(domain.error_message(error))
      }
  }
}

fn evaluation_schema() -> schema.Schema {
  schema.object([
    schema.Required("operationId", bounded_string(1, 500)),
    schema.Required("track", track_schema()),
    schema.Required("accountReference", hash_schema()),
    schema.Required("asOfUnixMilliseconds", unix_milliseconds()),
    schema.Required("ruleSetContentHash", hash_schema()),
    schema.Required(
      "completeness",
      schema.string_enum(["unproved", "caller_declared_complete"]),
    ),
    schema.Required("completenessReason", bounded_string(1, 500)),
    schema.Required(
      "facts",
      schema.array(fact_schema()) |> schema.with_array_length(0, 200),
    ),
    schema.Required(
      "rules",
      schema.array(rule_schema()) |> schema.with_array_length(1, 200),
    ),
  ])
}

fn explanation_schema() -> schema.Schema {
  schema.object([
    schema.Required("operationId", bounded_string(1, 500)),
    schema.Required(
      "expressionNodes",
      schema.array(expression_node_schema()) |> schema.with_array_length(1, 500),
    ),
    schema.Required(
      "facts",
      schema.array(fact_schema()) |> schema.with_array_length(0, 200),
    ),
  ])
}

fn comparison_schema() -> schema.Schema {
  schema.object([
    schema.Required("operationId", bounded_string(1, 500)),
    schema.Required("before", rule_schema()),
    schema.Required("after", rule_schema()),
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
    schema.Optional("value", schema.nullable(schema.boolean())),
    schema.Required(
      "values",
      schema.array(schema.boolean()) |> schema.with_array_length(0, 2),
    ),
    schema.Optional("reason", schema.nullable(bounded_string(1, 500))),
    schema.Required("sourceReference", hash_schema()),
  ])
}

fn expression_node_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "kind",
      schema.string_enum(["predicate", "all", "any", "not"]),
    ),
    schema.Required("childCount", bounded_integer(0, 500)),
    schema.Optional("factName", schema.nullable(bounded_string(1, 200))),
    schema.Optional("expected", schema.nullable(schema.boolean())),
  ])
}

fn rule_schema() -> schema.Schema {
  schema.object([
    schema.Required("ruleId", bounded_string(1, 200)),
    schema.Required("version", bounded_string(1, 100)),
    schema.Required("track", track_schema()),
    schema.Required("jurisdiction", bounded_string(1, 200)),
    schema.Required("accountScope", hash_schema()),
    schema.Required("effectiveFromUnixMilliseconds", unix_milliseconds()),
    schema.Optional(
      "effectiveUntilUnixMilliseconds",
      schema.nullable(unix_milliseconds()),
    ),
    schema.Required(
      "expressionNodes",
      schema.array(expression_node_schema()) |> schema.with_array_length(1, 500),
    ),
    schema.Required("severity", bounded_string(1, 100)),
    schema.Required("authorityReference", hash_schema()),
    schema.Required(
      "corrections",
      schema.array(correction_schema()) |> schema.with_array_length(0, 50),
    ),
  ])
}

fn correction_schema() -> schema.Schema {
  schema.object([
    schema.Required("fromVersion", bounded_string(1, 100)),
    schema.Required("authorityReference", hash_schema()),
    schema.Required("reason", bounded_string(1, 500)),
  ])
}

fn track_schema() -> schema.Schema {
  schema.string_enum(["cn", "hk", "us"])
}

fn unix_milliseconds() -> schema.Schema {
  bounded_integer(0, 9_007_199_254_740_991)
}

fn bounded_integer(minimum: Int, maximum: Int) -> schema.Schema {
  schema.integer()
  |> schema.with_number_range(int.to_float(minimum), int.to_float(maximum))
}

fn bounded_string(minimum: Int, maximum: Int) -> schema.Schema {
  schema.string() |> schema.with_string_length(minimum, maximum)
}

fn hash_schema() -> schema.Schema {
  bounded_string(64, 64)
}
