import finance_core/currency
import finance_core/time
import finance_track.{type Track}
import finance_track/context.{type Context}
import finance_track/profile
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub type State {
  Ready
  Experimental
  MissingDependency
  BlockedDecision
  Unknown
}

pub type Spec {
  Foundation(name: String, detail: String)
  RequiresTool(name: String, tool: String, detail: String)
  Blocked(name: String, detail: String)
}

pub type Capability {
  Capability(
    name: String,
    state: State,
    detail: String,
    required_tool: Option(String),
  )
}

pub type Report {
  Report(
    track: Track,
    context: Context,
    currency: String,
    timezone: String,
    capabilities: List(Capability),
  )
}

pub opaque type ProviderContract {
  ProviderContract(track: Track, name: String, health_tool: String)
}

pub type PolicyError {
  ContextTrackMismatch
  InvalidName
  InvalidDetail
  WrongTrackTool(expected_prefix: String, received: String)
  DuplicateCapability(name: String)
  DuplicateProvider(name: String)
}

pub fn inspect(
  track track_value: Track,
  context track_context: Context,
  specs specs: List(Spec),
  active_tools active_tools: List(String),
) -> Result(Report, PolicyError) {
  case context.track(track_context) == track_value {
    False -> Error(ContextTrackMismatch)
    True -> {
      use _ <- result.try(validate_specs(track_value, specs, []))
      let assert Ok(defaults) = profile.defaults(track_value, "setup")
      Ok(Report(
        track: track_value,
        context: track_context,
        currency: defaults |> profile.currency |> currency.code,
        timezone: defaults |> profile.timezone |> time.timezone_name,
        capabilities: specs |> list.map(spec_capability(_, active_tools)),
      ))
    }
  }
}

pub fn provider_contract(
  track track_value: Track,
  name name_value: String,
  health_tool health_tool_value: String,
) -> Result(ProviderContract, PolicyError) {
  case
    valid_name(name_value),
    valid_track_tool(track_value, health_tool_value)
  {
    False, _ -> Error(InvalidName)
    _, False ->
      Error(WrongTrackTool(
        finance_track.tool_prefix(track_value),
        health_tool_value,
      ))
    True, True ->
      Ok(ProviderContract(track_value, name_value, health_tool_value))
  }
}

pub fn provider_health(
  track track_value: Track,
  provider provider_name: String,
  contracts contracts: List(ProviderContract),
  active_tools active_tools: List(String),
) -> Result(Capability, PolicyError) {
  use _ <- result.try(validate_contracts(track_value, contracts, []))
  let normalized = provider_name |> string.trim |> string.lowercase
  case valid_name(normalized) {
    False -> Error(InvalidName)
    True ->
      case
        contracts
        |> list.filter(fn(contract) { contract.name == normalized })
      {
        [] ->
          Ok(Capability(
            normalized,
            Unknown,
            "no provider health contract is approved for this track",
            None,
          ))
        [contract] ->
          case list.contains(active_tools, contract.health_tool) {
            True ->
              Ok(Capability(
                contract.name,
                Experimental,
                "typed provider health tool is installed; invoke it to prove connectivity, credentials, entitlement, and freshness",
                Some(contract.health_tool),
              ))
            False ->
              Ok(Capability(
                contract.name,
                MissingDependency,
                "approved provider health tool is not installed",
                Some(contract.health_tool),
              ))
          }
        _ -> Error(DuplicateProvider(normalized))
      }
  }
}

pub fn state_name(value: State) -> String {
  case value {
    Ready -> "ready"
    Experimental -> "experimental"
    MissingDependency -> "missing_dependency"
    BlockedDecision -> "blocked_decision"
    Unknown -> "unknown"
  }
}

pub fn render(report: Report) -> String {
  let lines =
    report.capabilities
    |> list.map(render_capability)
    |> string.join("\n")
  string.uppercase(finance_track.name(report.track))
  <> " track ("
  <> finance_track.label(report.track)
  <> ") setup\n"
  <> "currency="
  <> report.currency
  <> " timezone="
  <> report.timezone
  <> "\n"
  <> lines
}

pub fn render_capability(value: Capability) -> String {
  "- " <> value.name <> ": " <> state_name(value.state) <> " — " <> value.detail
}

fn spec_capability(spec: Spec, active_tools: List(String)) -> Capability {
  case spec {
    Foundation(name, detail) -> Capability(name, Experimental, detail, None)
    Blocked(name, detail) -> Capability(name, BlockedDecision, detail, None)
    RequiresTool(name, tool, detail) ->
      case list.contains(active_tools, tool) {
        True -> Capability(name, Experimental, detail, Some(tool))
        False ->
          Capability(
            name,
            MissingDependency,
            detail <> "; required active tool is not installed: " <> tool,
            Some(tool),
          )
      }
  }
}

fn validate_specs(
  track: Track,
  specs: List(Spec),
  seen: List(String),
) -> Result(Nil, PolicyError) {
  case specs {
    [] -> Ok(Nil)
    [spec, ..rest] -> {
      let #(name, detail, tool) = case spec {
        Foundation(name, detail) | Blocked(name, detail) -> #(
          name,
          detail,
          None,
        )
        RequiresTool(name, tool, detail) -> #(name, detail, Some(tool))
      }
      case
        valid_name(name),
        valid_detail(detail),
        list.contains(seen, name),
        tool
      {
        False, _, _, _ -> Error(InvalidName)
        _, False, _, _ -> Error(InvalidDetail)
        _, _, True, _ -> Error(DuplicateCapability(name))
        True, True, False, Some(tool_name) ->
          case valid_track_tool(track, tool_name) {
            True -> validate_specs(track, rest, [name, ..seen])
            False ->
              Error(WrongTrackTool(finance_track.tool_prefix(track), tool_name))
          }
        True, True, False, None -> validate_specs(track, rest, [name, ..seen])
      }
    }
  }
}

fn validate_contracts(
  track: Track,
  contracts: List(ProviderContract),
  seen: List(String),
) -> Result(Nil, PolicyError) {
  case contracts {
    [] -> Ok(Nil)
    [contract, ..rest] ->
      case
        contract.track == track,
        list.contains(seen, contract.name),
        valid_track_tool(track, contract.health_tool)
      {
        False, _, _ ->
          Error(WrongTrackTool(
            finance_track.tool_prefix(track),
            contract.health_tool,
          ))
        _, True, _ -> Error(DuplicateProvider(contract.name))
        _, _, False ->
          Error(WrongTrackTool(
            finance_track.tool_prefix(track),
            contract.health_tool,
          ))
        True, False, True ->
          validate_contracts(track, rest, [contract.name, ..seen])
      }
  }
}

fn valid_track_tool(track: Track, value: String) -> Bool {
  valid_name(value)
  && string.starts_with(value, finance_track.tool_prefix(track))
}

fn valid_name(value: String) -> Bool {
  value != ""
  && string.trim(value) == value
  && string.length(value) <= 100
  && !string.contains(value, "\n")
  && !string.contains(value, "\r")
}

fn valid_detail(value: String) -> Bool {
  value != ""
  && string.trim(value) == value
  && string.length(value) <= 1000
  && !string.contains(value, "\n")
  && !string.contains(value, "\r")
}
