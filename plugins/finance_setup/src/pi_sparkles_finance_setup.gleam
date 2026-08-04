import gleam/dynamic/decode
import gleam/javascript/promise.{type Promise}
import gleam/json
import gleam/option.{Some}
import pi
import pi/context
import pi/schema
import pi/tool
import pi/ui
import pi_sparkles_finance_setup/capability

pub type CapabilitiesInput {
  CapabilitiesInput(currency: String, timezone: String)
}

pub type ProviderInput {
  ProviderInput(provider: String)
}

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  pi.register_string_flag(
    api,
    "finance-currency",
    "Default three-letter reporting currency",
    "USD",
  )
  pi.register_string_flag(
    api,
    "finance-timezone",
    "Default market timezone (UTC or IANA Area/Location)",
    "UTC",
  )

  pi.register_command(
    api,
    "finance-setup",
    "Inspect finance foundations, defaults, and provider readiness",
    fn(_args, ctx) {
      notify(
        ctx,
        report(api, configured_currency(api), configured_timezone(api)),
      )
      promise.resolve(Nil)
    },
  )

  tool.register(
    api,
    "finance_capabilities",
    "Finance capabilities",
    "Inspect installed finance capabilities and validate reporting defaults without revealing secrets",
    "Check finance capabilities and configuration before doing research",
    tool.parameters(
      schema.object([
        schema.Optional(
          "currency",
          schema.string()
            |> schema.with_default(json.string("USD"))
            |> schema.described("Three-letter reporting currency"),
        ),
        schema.Optional(
          "timezone",
          schema.string()
            |> schema.with_default(json.string("UTC"))
            |> schema.described("UTC or IANA Area/Location timezone"),
        ),
      ]),
      capabilities_decoder(),
    ),
    tool.Parallel,
    fn(_id, input, _signal, _updates, _ctx) {
      let value =
        capability.inspect(
          input.currency,
          input.timezone,
          pi.get_active_tools(api),
        )
      tool.text_result(capability.render(value), report_json(value))
      |> promise.resolve
    },
  )

  tool.register(
    api,
    "finance_provider_health",
    "Finance provider health",
    "Report whether a provider-specific adapter is installed; connectivity remains unchecked until that adapter supplies a probe",
    "Check whether a named finance provider adapter is available",
    tool.parameters(
      schema.object([
        schema.Required(
          "provider",
          schema.string()
            |> schema.described("Provider name, for example openfigi"),
        ),
      ]),
      provider_decoder(),
    ),
    tool.Parallel,
    fn(_id, input, _signal, _updates, _ctx) {
      let value =
        capability.provider_health(input.provider, pi.get_active_tools(api))
      tool.text_result(
        capability.render_capability(value),
        capability_json(value),
      )
      |> promise.resolve
    },
  )

  promise.resolve(Nil)
}

fn report(api: pi.ExtensionApi, currency: String, timezone: String) -> String {
  capability.inspect(currency, timezone, pi.get_active_tools(api))
  |> capability.render
}

fn configured_currency(api: pi.ExtensionApi) -> String {
  case pi.get_flag(api, "finance-currency") {
    Some(pi.StringFlag(value)) -> value
    _ -> "USD"
  }
}

fn configured_timezone(api: pi.ExtensionApi) -> String {
  case pi.get_flag(api, "finance-timezone") {
    Some(pi.StringFlag(value)) -> value
    _ -> "UTC"
  }
}

fn capabilities_decoder() -> decode.Decoder(CapabilitiesInput) {
  use currency <- decode.optional_field("currency", "USD", decode.string)
  use timezone <- decode.optional_field("timezone", "UTC", decode.string)
  decode.success(CapabilitiesInput(currency:, timezone:))
}

fn provider_decoder() -> decode.Decoder(ProviderInput) {
  use provider <- decode.field("provider", decode.string)
  decode.success(ProviderInput(provider:))
}

fn report_json(value: capability.Report) -> json.Json {
  json.object([
    #("currency", json.string(value.currency)),
    #("timezone", json.string(value.timezone)),
    #("configurationValid", json.bool(value.configuration_valid)),
    #("capabilities", json.array(value.capabilities, capability_json)),
  ])
}

fn capability_json(value: capability.Capability) -> json.Json {
  json.object([
    #("name", json.string(value.name)),
    #("state", json.string(capability.state_name(value.state))),
    #("detail", json.string(value.detail)),
  ])
}

fn notify(ctx: pi.CommandContext, message: String) -> Nil {
  case context.has_ui(ctx) {
    True -> ui.notify(context.ui(ctx), message, ui.Info)
    False -> Nil
  }
}
