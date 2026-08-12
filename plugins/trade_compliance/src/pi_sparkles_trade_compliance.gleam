import gleam/javascript/promise.{type Promise}
import pi
import pi/schema
import pi/tool
import pi_sparkles_trade_compliance/decode
import pi_sparkles_trade_compliance/domain

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  tool.register(
    api,
    "evaluate_supplied_trade_rules",
    "Evaluate supplied trade rules",
    "Evaluate bounded caller-supplied boolean rules and facts independently as True, False, Unknown, NotApplicable, or Conflict; no legal, aggregate, or execution verdict is produced",
    "Supply exact rule versions, effective intervals, hashed sources, and facts. Every output remains track_partial because authority and completeness are not authenticated.",
    tool.parameters(evaluation_schema(), decode.evaluation_input()),
    tool.Parallel,
    fn(_id, input, _signal, _updates, _ctx) {
      case domain.evaluate(input) {
        Ok(value) ->
          tool.text_result(domain.summary(value), domain.details(value))
          |> promise.resolve
        Error(error) -> tool.reject(domain.error_message(error))
      }
    },
  )
  promise.resolve(Nil)
}

fn evaluation_schema() -> schema.Schema {
  schema.object([
    schema.Required("operationId", bounded_string(1, 500)),
    schema.Required("track", schema.string_enum(["cn", "hk", "us"])),
    schema.Required("accountReference", hash_schema()),
    schema.Required(
      "asOfUnixMilliseconds",
      schema.integer() |> schema.with_number_range(0.0, 9_007_199_254_740_991.0),
    ),
    schema.Required("ruleSetContentHash", hash_schema()),
    schema.Required(
      "facts",
      schema.array(fact_schema()) |> schema.with_array_length(0, 200),
    ),
    schema.Required(
      "rules",
      schema.array(rule_schema()) |> schema.with_array_length(1, 200),
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
    schema.Optional("value", schema.nullable(schema.boolean())),
    schema.Required("sourceReference", hash_schema()),
  ])
}

fn rule_schema() -> schema.Schema {
  schema.object([
    schema.Required("ruleId", bounded_string(1, 200)),
    schema.Required("version", bounded_string(1, 100)),
    schema.Required(
      "effectiveFromUnixMilliseconds",
      schema.integer() |> schema.with_number_range(0.0, 9_007_199_254_740_991.0),
    ),
    schema.Optional(
      "effectiveUntilUnixMilliseconds",
      schema.nullable(
        schema.integer()
        |> schema.with_number_range(0.0, 9_007_199_254_740_991.0),
      ),
    ),
    schema.Required("factName", bounded_string(1, 200)),
    schema.Required("expected", schema.boolean()),
    schema.Required("severity", bounded_string(1, 100)),
    schema.Required("authorityReference", hash_schema()),
  ])
}

fn bounded_string(minimum: Int, maximum: Int) -> schema.Schema {
  schema.string() |> schema.with_string_length(minimum, maximum)
}

fn hash_schema() -> schema.Schema {
  bounded_string(64, 64)
}
