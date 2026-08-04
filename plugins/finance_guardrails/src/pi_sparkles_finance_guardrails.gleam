import gleam/dynamic/decode
import gleam/javascript/promise.{type Promise}
import gleam/json
import gleam/string
import pi
import pi/context
import pi/schema
import pi/tool
import pi/ui
import pi_sparkles_finance_guardrails/policy

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  pi.register_command(
    api,
    "finance-policy",
    "Show the active finance evidence policy",
    fn(_args, ctx) {
      notify(ctx, policy.policy_text())
      promise.resolve(Nil)
    },
  )

  tool.register(
    api,
    "finance_validate_evidence",
    "Validate finance evidence",
    "Apply deterministic source, currency, period, adjustment, freshness, and entitlement rules before using finance evidence",
    "Validate finance evidence before calculation or reporting",
    tool.parameters(evidence_schema(), evidence_decoder()),
    tool.Parallel,
    fn(_id, input, _signal, _updates, _ctx) {
      let decision = policy.validate(input)
      tool.text_result(policy.render(decision), decision_json(decision))
      |> promise.resolve
    },
  )

  tool.register(
    api,
    "finance_check_freshness",
    "Check finance freshness",
    "Classify evidence age against an explicit maximum age",
    "Check whether finance evidence is fresh enough for the task",
    tool.parameters(
      schema.object([
        schema.Required(
          "ageMs",
          schema.integer()
            |> schema.described("Non-negative evidence age in milliseconds"),
        ),
        schema.Required(
          "maximumAgeMs",
          schema.integer()
            |> schema.described("Maximum permitted age in milliseconds"),
        ),
      ]),
      freshness_decoder(),
    ),
    tool.Parallel,
    fn(_id, input, _signal, _updates, _ctx) {
      case policy.freshness(input.0, input.1) {
        Ok(value) -> {
          let name = policy.freshness_name(value)
          tool.text_result(
            "Evidence freshness: " <> name,
            json.object([
              #("state", json.string(name)),
              #("ageMs", json.int(input.0)),
              #("maximumAgeMs", json.int(input.1)),
            ]),
          )
          |> promise.resolve
        }
        Error(error) ->
          tool.reject("Invalid freshness input: " <> string.inspect(error))
      }
    },
  )

  promise.resolve(Nil)
}

fn evidence_schema() -> schema.Schema {
  schema.object([
    schema.Required(
      "source",
      schema.string() |> schema.described("Non-secret source reference"),
    ),
    schema.Required("currencies", schema.array(schema.string())),
    schema.Required("periods", schema.array(schema.string())),
    schema.Required("adjustments", schema.array(schema.string())),
    schema.Required("ageMs", schema.integer()),
    schema.Required("maximumAgeMs", schema.integer()),
    schema.Required(
      "entitlement",
      schema.string_enum(["real_time", "delayed", "end_of_day", "unknown"]),
    ),
  ])
}

fn evidence_decoder() -> decode.Decoder(policy.EvidenceFacts) {
  use source <- decode.field("source", decode.string)
  use currencies <- decode.field("currencies", decode.list(of: decode.string))
  use periods <- decode.field("periods", decode.list(of: decode.string))
  use adjustments <- decode.field("adjustments", decode.list(of: decode.string))
  use age_milliseconds <- decode.field("ageMs", decode.int)
  use maximum_age_milliseconds <- decode.field("maximumAgeMs", decode.int)
  use entitlement <- decode.field("entitlement", decode.string)
  decode.success(policy.EvidenceFacts(
    source:,
    currencies:,
    periods:,
    adjustments:,
    age_milliseconds:,
    maximum_age_milliseconds:,
    entitlement:,
  ))
}

fn freshness_decoder() -> decode.Decoder(#(Int, Int)) {
  use age <- decode.field("ageMs", decode.int)
  use maximum <- decode.field("maximumAgeMs", decode.int)
  decode.success(#(age, maximum))
}

fn decision_json(value: policy.Decision) -> json.Json {
  json.object([
    #("accepted", json.bool(value.accepted)),
    #("issues", json.array(value.issues, issue_json)),
  ])
}

fn issue_json(value: policy.Issue) -> json.Json {
  json.object([
    #("code", json.string(value.code)),
    #("severity", json.string(policy.severity_name(value.severity))),
    #("message", json.string(value.message)),
  ])
}

fn notify(ctx: pi.CommandContext, message: String) -> Nil {
  case context.has_ui(ctx) {
    True -> ui.notify(context.ui(ctx), message, ui.Info)
    False -> Nil
  }
}
