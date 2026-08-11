import finance_cninfo/security_master.{type Security}
import finance_core/identifier.{type Resolution}
import gleam/list
import gleam/option.{type Option, None, Some}

pub type SelectionError {
  NoCandidate
  AmbiguousCandidates(count: Int)
  OrganizationIdMismatch
}

pub fn select(
  resolution: Resolution(Security),
  organization_id: Option(String),
) -> Result(Security, SelectionError) {
  let values = case resolution {
    identifier.NoMatch -> []
    identifier.Unique(value) -> [value]
    identifier.Ambiguous(first, second, rest) -> [first, second, ..rest]
  }
  case organization_id {
    Some(expected) ->
      case
        list.filter(values, fn(value) {
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
