import finance_core/currency
import finance_core/time
import gleam/bool
import gleam/list
import gleam/result
import gleam/string

pub type State {
  Ready
  Experimental
  MissingDependency
  InvalidConfiguration
  Unknown
}

pub type Capability {
  Capability(name: String, state: State, detail: String)
}

pub type Report {
  Report(
    currency: String,
    timezone: String,
    configuration_valid: Bool,
    capabilities: List(Capability),
  )
}

pub fn inspect(
  currency_code: String,
  timezone_name: String,
  active_tools: List(String),
) -> Report {
  let currency_valid = result.is_ok(currency.from_code(currency_code))
  let timezone_valid = result.is_ok(time.timezone(timezone_name))
  Report(
    currency: string.uppercase(currency_code),
    timezone: timezone_name,
    configuration_valid: currency_valid && timezone_valid,
    capabilities: [
      Capability(
        "finance foundations",
        Ready,
        "exact values, observations, provenance, HTTP, tables, metrics, series, calendars, and deterministic test support",
      ),
      registered(
        "evidence guardrails",
        "finance_validate_evidence",
        active_tools,
      ),
      registered("symbol resolution", "security_resolve", active_tools),
      Capability(
        "provider connectivity",
        MissingDependency,
        "install a provider adapter; setup never claims network health without performing a provider-specific probe",
      ),
      case currency_valid && timezone_valid {
        True ->
          Capability(
            "finance defaults",
            Ready,
            "currency and timezone are valid",
          )
        False ->
          Capability(
            "finance defaults",
            InvalidConfiguration,
            "currency must be a three-letter code and timezone must be UTC or an IANA-style Area/Location name",
          )
      },
    ],
  )
}

pub fn provider_health(
  provider: String,
  active_tools: List(String),
) -> Capability {
  case string.lowercase(string.trim(provider)) {
    "openfigi" -> registered("OpenFIGI v3", "security_resolve", active_tools)
    "sec" | "sec-edgar" | "edgar" ->
      registered("SEC EDGAR", "sec_company_search", active_tools)
    "alpaca" | "alpaca-market-data" ->
      case has_any(active_tools, ["us_stock_quote", "us_stock_ohlcv"]) {
        True ->
          Capability(
            "Alpaca Market Data",
            Experimental,
            "typed read-only US market-data tool is active; this is installation state, not a live health probe",
          )
        False ->
          Capability(
            "Alpaca Market Data",
            MissingDependency,
            "required active tool is not installed: us_stock_quote or us_stock_ohlcv",
          )
      }
    "" -> Capability("provider", InvalidConfiguration, "provider is required")
    name ->
      Capability(
        name,
        Unknown,
        "no provider health contract is registered for this name",
      )
  }
}

pub fn state_name(state: State) -> String {
  case state {
    Ready -> "ready"
    Experimental -> "experimental"
    MissingDependency -> "missing_dependency"
    InvalidConfiguration -> "invalid_configuration"
    Unknown -> "unknown"
  }
}

pub fn render(report: Report) -> String {
  let lines =
    report.capabilities
    |> list.map(fn(item) {
      "- "
      <> item.name
      <> ": "
      <> state_name(item.state)
      <> " — "
      <> item.detail
    })
    |> string.join("\n")
  "Finance configuration\n"
  <> "currency="
  <> report.currency
  <> " timezone="
  <> report.timezone
  <> " valid="
  <> bool.to_string(report.configuration_valid)
  <> "\n"
  <> lines
}

pub fn render_capability(value: Capability) -> String {
  value.name <> ": " <> state_name(value.state) <> " — " <> value.detail
}

fn registered(
  name: String,
  tool_name: String,
  active_tools: List(String),
) -> Capability {
  case list.contains(active_tools, tool_name) {
    True -> Capability(name, Experimental, "typed Pi tool is active")
    False ->
      Capability(
        name,
        MissingDependency,
        "required active tool is not installed: " <> tool_name,
      )
  }
}

fn has_any(values: List(String), expected: List(String)) -> Bool {
  list.any(expected, fn(value) { list.contains(values, value) })
}
