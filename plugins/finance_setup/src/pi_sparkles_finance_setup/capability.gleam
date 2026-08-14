import finance_core/currency
import finance_core/time
import gleam/bool
import gleam/list
import gleam/result
import gleam/string

pub type State {
  Ready
  Available
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
      provider_connectivity(active_tools),
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
            Available,
            "typed read-only US market-data tool is active; this is installation state, not a live health probe",
          )
        False ->
          Capability(
            "Alpaca Market Data",
            MissingDependency,
            "required active tool is not installed: us_stock_quote or us_stock_ohlcv",
          )
      }
    "eastmoney" ->
      provider_surface(
        "Eastmoney",
        [
          "cn_market_overview",
          "cn_raw_vendor_quote",
          "cn_raw_vendor_history",
          "cn_stock_quote",
          "cn_stock_history",
          "hk_stock_quote",
          "hk_stock_history",
        ],
        active_tools,
      )
    "tushare" | "tushare-pro" ->
      provider_surface(
        "Tushare Pro",
        ["cn_stock_quote", "cn_stock_history"],
        active_tools,
      )
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
    Available -> "available"
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
  "Finance reporting defaults (not the active market track)\n"
  <> "reportingCurrency="
  <> report.currency
  <> " reportingTimezone="
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
    True ->
      Capability(
        name,
        Available,
        "typed Pi tool is installed; provider-specific health remains unprobed",
      )
    False ->
      Capability(
        name,
        MissingDependency,
        "required active tool is not installed: " <> tool_name,
      )
  }
}

fn provider_connectivity(active_tools: List(String)) -> Capability {
  case has_any(active_tools, provider_tool_names()) {
    True ->
      Capability(
        "provider adapter surfaces",
        Available,
        "one or more typed provider tools are installed; configured credentials, reachability, freshness, entitlement, and live health remain independently unprobed",
      )
    False ->
      Capability(
        "provider adapter surfaces",
        MissingDependency,
        "install a provider adapter; setup never claims network health from package presence alone",
      )
  }
}

fn provider_surface(
  name: String,
  tool_names: List(String),
  active_tools: List(String),
) -> Capability {
  case has_any(active_tools, tool_names) {
    True ->
      Capability(
        name,
        Available,
        "typed adapter surface is installed; this is installation state only, while configuration, reachability, freshness, entitlement, and live health remain unprobed",
      )
    False ->
      Capability(
        name,
        MissingDependency,
        "no recognized active tool exposes this provider adapter",
      )
  }
}

fn provider_tool_names() -> List(String) {
  [
    "cn_market_overview",
    "cn_raw_vendor_quote",
    "cn_raw_vendor_history",
    "cn_stock_quote",
    "cn_stock_history",
    "hk_stock_quote",
    "hk_stock_history",
    "us_stock_quote",
    "us_stock_ohlcv",
    "sec_company_search",
  ]
}

fn has_any(values: List(String), expected: List(String)) -> Bool {
  list.any(expected, fn(value) { list.contains(values, value) })
}
