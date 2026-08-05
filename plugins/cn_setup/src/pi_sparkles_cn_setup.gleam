import finance_core/time
import finance_market_authorities/authority
import finance_track
import finance_track/context as track_context
import finance_track/json as track_json
import finance_track_capabilities/capability
import gleam/dynamic/decode
import gleam/javascript/promise.{type Promise}
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import pi
import pi/context
import pi/schema
import pi/tool
import pi/ui
import pi_sparkles_cn_setup/authorities

pub type ProviderInput {
  ProviderInput(provider: String)
}

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  pi.register_command(
    api,
    "cn-setup",
    "Inspect isolated mainland-China capabilities and blocked provider decisions",
    fn(_args, ctx) {
      case report(api) {
        Ok(value) -> notify(ctx, capability.render(value), ui.Info)
        Error(_) -> notify(ctx, "CN setup policy is invalid", ui.Error)
      }
      promise.resolve(Nil)
    },
  )

  pi.register_command(
    api,
    "cn-sources",
    "Show verified mainland authorities and source access status",
    fn(_args, ctx) {
      notify(ctx, authority.render(authorities.registry()), ui.Info)
      promise.resolve(Nil)
    },
  )

  tool.register(
    api,
    "cn_capabilities",
    "CN capabilities",
    "Inspect mainland-China identity, calendar, rules, market-data, disclosure, and accounting readiness without using HK or US tools",
    "Check CN track readiness before mainland-China research",
    tool.parameters(schema.object([]), decode.success(Nil)),
    tool.Parallel,
    fn(_id, _input, _signal, _updates, _ctx) {
      case report(api) {
        Ok(value) ->
          tool.text_result(capability.render(value), report_json(value))
          |> promise.resolve
        Error(_) -> tool.reject("CN setup policy is invalid")
      }
    },
  )

  tool.register(
    api,
    "cn_authorities",
    "CN official authorities",
    "List verified mainland regulators, exchange disclosure sources, and accounting-standard owners with honest access and redistribution status",
    "Identify the official CN source for a capability before choosing an adapter",
    tool.parameters(schema.object([]), decode.success(Nil)),
    tool.Parallel,
    fn(_id, _input, _signal, _updates, _ctx) {
      let registry = authorities.registry()
      let values = authority.registry_authorities(registry)
      tool.text_result(authority.render(registry), authorities_json(values))
      |> promise.resolve
    },
  )

  tool.register(
    api,
    "cn_provider_health",
    "CN provider health",
    "Report whether a named mainland-China provider has an approved typed health contract; no connectivity is inferred",
    "Check one named CN provider contract",
    tool.parameters(
      schema.object([
        schema.Required(
          "provider",
          schema.string() |> schema.described("Exact approved provider name"),
        ),
      ]),
      provider_decoder(),
    ),
    tool.Parallel,
    fn(_id, input, _signal, _updates, _ctx) {
      case
        capability.provider_health(
          finance_track.Cn,
          input.provider,
          [],
          pi.get_active_tools(api),
        )
      {
        Ok(value) ->
          tool.text_result(
            "CN track | " <> capability.render_capability(value),
            provider_json(value),
          )
          |> promise.resolve
        Error(_) -> tool.reject("A valid provider name is required")
      }
    },
  )

  promise.resolve(Nil)
}

fn report(
  api: pi.ExtensionApi,
) -> Result(capability.Report, capability.PolicyError) {
  capability.inspect(
    finance_track.Cn,
    result_context("cn_setup"),
    specs(),
    pi.get_active_tools(api),
  )
}

fn specs() -> List(capability.Spec) {
  [
    capability.Foundation(
      "pure market foundations",
      "track, evidence, listing, identity, bounded calendar, effective rules, documents/attachments, and lossless accounting packages are installed",
    ),
    capability.Blocked(
      "provider-backed identity",
      "SSE, SZSE, and BSE authority ownership is verified in cn_authorities, but an accepted security-master product and redistribution terms are not approved",
    ),
    capability.Blocked(
      "authoritative calendar",
      "official exchange ownership is verified in cn_authorities, but supported calendar capture, update cadence, and fixture rights are not approved",
    ),
    capability.Blocked(
      "effective rule tables",
      "the pure selector and official exchange owners exist, but source-reviewed dated mainland rule tables are not approved",
    ),
    capability.Blocked(
      "quote and history",
      "no named licensed mainland quote/history provider is selected",
    ),
    capability.Blocked(
      "disclosures and accounting",
      "official disclosure and accounting owners are listed in cn_authorities, but machine access, fixtures, and audited mappings remain unapproved",
    ),
  ]
}

fn result_context(scope: String) -> track_context.Context {
  let assert Ok(zone) = time.timezone("Asia/Shanghai")
  let assert Ok(value) =
    track_context.new(
      track: finance_track.Cn,
      market_scope: scope,
      venue_mic: None,
      board: None,
      timezone: Some(zone),
      source_language: "zh-CN",
      providers: ["pi-sparkles cn setup"],
      entitlement: "configuration_only",
      limitations: [
        "no_provider_health_contracts",
        "synthetic_domain_fixtures_only",
      ],
    )
  value
}

fn provider_decoder() -> decode.Decoder(ProviderInput) {
  use provider <- decode.field("provider", decode.string)
  decode.success(ProviderInput(provider))
}

fn report_json(value: capability.Report) -> json.Json {
  json.object(
    list.append(track_json.result_fields(value.context), [
      #("currency", json.string(value.currency)),
      #("timezone", json.string(value.timezone)),
      #("capabilities", json.array(value.capabilities, capability_json)),
    ]),
  )
}

fn provider_json(value: capability.Capability) -> json.Json {
  json.object(
    list.append(track_json.result_fields(result_context("cn_provider_health")), [
      #("provider", capability_json(value)),
    ]),
  )
}

fn authorities_json(values: List(authority.Authority)) -> json.Json {
  json.object(
    list.append(track_json.result_fields(result_context("cn_authorities")), [
      #("authorities", json.array(values, authority_json)),
    ]),
  )
}

fn authority_json(value: authority.Authority) -> json.Json {
  json.object([
    #("id", json.string(authority.id(value))),
    #("name", json.string(authority.name(value))),
    #(
      "roles",
      json.array(authority.roles(value), fn(role) {
        json.string(authority.role_name(role))
      }),
    ),
    #("officialUrl", json.string(authority.official_url(value))),
    #("scope", json.string(authority.scope(value))),
    #("access", json.string(authority.access_name(authority.access(value)))),
    #(
      "redistribution",
      json.string(
        authority.redistribution_name(authority.redistribution(value)),
      ),
    ),
    #("limitations", json.array(authority.limitations(value), json.string)),
  ])
}

fn capability_json(value: capability.Capability) -> json.Json {
  json.object([
    #("name", json.string(value.name)),
    #("state", json.string(capability.state_name(value.state))),
    #("detail", json.string(value.detail)),
    #("requiredTool", json.nullable(value.required_tool, json.string)),
  ])
}

fn notify(
  ctx: pi.CommandContext,
  message: String,
  kind: ui.Notification,
) -> Nil {
  case context.has_ui(ctx) {
    True -> ui.notify(context.ui(ctx), message, kind)
    False -> Nil
  }
}
