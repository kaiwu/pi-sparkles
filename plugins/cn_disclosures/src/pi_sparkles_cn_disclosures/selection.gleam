import finance_cninfo/security_master.{type Security}
import finance_core/identifier.{type Resolution}
import gleam/list
import gleam/option.{type Option, None, Some}

pub type SelectionError {
  NoCandidate
  AmbiguousCandidates(count: Int)
  OrganizationIdMismatch
}

pub fn candidates(value: Resolution(Security)) -> List(Security) {
  case value {
    identifier.NoMatch -> []
    identifier.Unique(item) -> [item]
    identifier.Ambiguous(first, second, rest) -> [first, second, ..rest]
  }
}

pub fn select(
  resolution: Resolution(Security),
  organization_id: Option(String),
) -> Result(Security, SelectionError) {
  let values = candidates(resolution)
  case organization_id {
    Some(expected) ->
      case
        values
        |> list.filter(fn(value) {
          security_master.organization_id(value) == expected
        })
      {
        [value] -> Ok(value)
        _ -> Error(OrganizationIdMismatch)
      }
    None ->
      case values {
        [] -> Error(NoCandidate)
        [value] -> Ok(value)
        many -> Error(AmbiguousCandidates(list.length(many)))
      }
  }
}
