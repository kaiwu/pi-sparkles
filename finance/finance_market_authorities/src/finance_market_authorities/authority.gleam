import finance_track.{type Track}
import gleam/list
import gleam/string

pub type Role {
  SecuritiesRegulator
  FrontlineListingRegulator
  IssuerDisclosureRepository
  AccountingStandardSetter
  ElectronicTaxonomyPublisher
  CalendarAndRulesPublisher
  ProductionIssuerFeed
  MarketDataLicensor
}

/// Operational access is intentionally separate from official ownership.
/// An official public page does not imply a supported machine contract.
pub type Access {
  VerifiedReference
  PublicReadOnlySnapshot
  PublicSearchAccessUnreviewed
  LicenceReviewRequired
  ProductionContractRequired
}

pub type Redistribution {
  ReferenceLinkOnly
  NoRedistribution
  UnreviewedRedistribution
  ContractControlled
}

pub opaque type Authority {
  Authority(
    track: Track,
    id: String,
    name: String,
    roles: List(Role),
    official_url: String,
    scope: String,
    access: Access,
    redistribution: Redistribution,
    limitations: List(String),
  )
}

pub opaque type Registry {
  Registry(track: Track, authorities: List(Authority))
}

pub type AuthorityError {
  WrongTrackId(expected_prefix: String, received: String)
  InvalidId
  InvalidName
  MissingRole
  DuplicateRole(role: Role)
  InvalidOfficialUrl
  InvalidScope
  InvalidLimitation
  DuplicateLimitation(value: String)
}

pub type RegistryError {
  EmptyRegistry
  AuthorityTrackMismatch(id: String, expected: Track, received: Track)
  DuplicateAuthority(id: String)
}

pub fn new(
  track track_value: Track,
  id id_value: String,
  name name_value: String,
  roles role_values: List(Role),
  official_url url: String,
  scope scope_value: String,
  access access_value: Access,
  redistribution redistribution_value: Redistribution,
  limitations limitation_values: List(String),
) -> Result(Authority, AuthorityError) {
  let expected_prefix = finance_track.name(track_value) <> "_"
  case
    valid_id(id_value),
    string.starts_with(id_value, expected_prefix),
    valid_single_line(name_value, 200),
    role_values,
    first_duplicate_role(role_values),
    valid_url(url),
    valid_single_line(scope_value, 1000),
    first_invalid_limitation(limitation_values),
    first_duplicate_limitation(limitation_values)
  {
    False, _, _, _, _, _, _, _, _ -> Error(InvalidId)
    _, False, _, _, _, _, _, _, _ ->
      Error(WrongTrackId(expected_prefix, id_value))
    _, _, False, _, _, _, _, _, _ -> Error(InvalidName)
    _, _, _, [], _, _, _, _, _ -> Error(MissingRole)
    _, _, _, _, SomeRole(role), _, _, _, _ -> Error(DuplicateRole(role))
    _, _, _, _, _, False, _, _, _ -> Error(InvalidOfficialUrl)
    _, _, _, _, _, _, False, _, _ -> Error(InvalidScope)
    _, _, _, _, _, _, _, SomeInvalid, _ -> Error(InvalidLimitation)
    _, _, _, _, _, _, _, _, SomeLimitation(value) ->
      Error(DuplicateLimitation(value))
    True, True, True, _, NoRole, True, True, NoInvalid, NoLimitation ->
      Ok(Authority(
        track: track_value,
        id: id_value,
        name: name_value,
        roles: role_values,
        official_url: url,
        scope: scope_value,
        access: access_value,
        redistribution: redistribution_value,
        limitations: limitation_values,
      ))
  }
}

pub fn track(value: Authority) -> Track {
  value.track
}

pub fn id(value: Authority) -> String {
  value.id
}

pub fn name(value: Authority) -> String {
  value.name
}

pub fn roles(value: Authority) -> List(Role) {
  value.roles
}

pub fn official_url(value: Authority) -> String {
  value.official_url
}

pub fn scope(value: Authority) -> String {
  value.scope
}

pub fn access(value: Authority) -> Access {
  value.access
}

pub fn redistribution(value: Authority) -> Redistribution {
  value.redistribution
}

pub fn limitations(value: Authority) -> List(String) {
  value.limitations
}

pub fn registry(
  track track_value: Track,
  authorities values: List(Authority),
) -> Result(Registry, RegistryError) {
  case values {
    [] -> Error(EmptyRegistry)
    _ -> {
      use _ <- result_try(validate_registry(track_value, values, []))
      Ok(Registry(track_value, values))
    }
  }
}

pub fn registry_track(value: Registry) -> Track {
  value.track
}

pub fn registry_authorities(value: Registry) -> List(Authority) {
  value.authorities
}

pub fn role_name(value: Role) -> String {
  case value {
    SecuritiesRegulator -> "securities_regulator"
    FrontlineListingRegulator -> "frontline_listing_regulator"
    IssuerDisclosureRepository -> "issuer_disclosure_repository"
    AccountingStandardSetter -> "accounting_standard_setter"
    ElectronicTaxonomyPublisher -> "electronic_taxonomy_publisher"
    CalendarAndRulesPublisher -> "calendar_and_rules_publisher"
    ProductionIssuerFeed -> "production_issuer_feed"
    MarketDataLicensor -> "market_data_licensor"
  }
}

pub fn access_name(value: Access) -> String {
  case value {
    VerifiedReference -> "verified_reference"
    PublicReadOnlySnapshot -> "public_read_only_snapshot"
    PublicSearchAccessUnreviewed -> "public_search_access_unreviewed"
    LicenceReviewRequired -> "licence_review_required"
    ProductionContractRequired -> "production_contract_required"
  }
}

pub fn redistribution_name(value: Redistribution) -> String {
  case value {
    ReferenceLinkOnly -> "reference_link_only"
    NoRedistribution -> "no_redistribution"
    UnreviewedRedistribution -> "unreviewed"
    ContractControlled -> "contract_controlled"
  }
}

pub fn render(registry value: Registry) -> String {
  let prefix = string.uppercase(finance_track.name(value.track))
  let lines =
    value.authorities
    |> list.map(fn(value) {
      let roles = value.roles |> list.map(role_name) |> string.join(",")
      "- "
      <> value.name
      <> " ["
      <> roles
      <> "] — access="
      <> access_name(value.access)
      <> " redistribution="
      <> redistribution_name(value.redistribution)
      <> "\n  "
      <> value.official_url
      <> "\n  scope: "
      <> value.scope
    })
    |> string.join("\n")
  prefix
  <> " track official authorities and sources\n"
  <> "Official ownership does not imply unrestricted automation or redistribution.\n"
  <> lines
}

fn validate_registry(
  track: Track,
  values: List(Authority),
  seen: List(String),
) -> Result(Nil, RegistryError) {
  case values {
    [] -> Ok(Nil)
    [first, ..rest] ->
      case first.track == track, list.contains(seen, first.id) {
        False, _ -> Error(AuthorityTrackMismatch(first.id, track, first.track))
        _, True -> Error(DuplicateAuthority(first.id))
        True, False -> validate_registry(track, rest, [first.id, ..seen])
      }
  }
}

type DuplicateRole {
  NoRole
  SomeRole(Role)
}

type InvalidLimitation {
  NoInvalid
  SomeInvalid
}

type DuplicateLimitation {
  NoLimitation
  SomeLimitation(String)
}

fn first_duplicate_role(values: List(Role)) -> DuplicateRole {
  case values {
    [] -> NoRole
    [first, ..rest] ->
      case list.contains(rest, first) {
        True -> SomeRole(first)
        False -> first_duplicate_role(rest)
      }
  }
}

fn first_invalid_limitation(values: List(String)) -> InvalidLimitation {
  case list.any(values, fn(value) { !valid_single_line(value, 500) }) {
    True -> SomeInvalid
    False -> NoInvalid
  }
}

fn first_duplicate_limitation(values: List(String)) -> DuplicateLimitation {
  case values {
    [] -> NoLimitation
    [first, ..rest] ->
      case list.contains(rest, first) {
        True -> SomeLimitation(first)
        False -> first_duplicate_limitation(rest)
      }
  }
}

fn valid_id(value: String) -> Bool {
  value != ""
  && string.length(value) <= 100
  && {
    value
    |> string.to_graphemes
    |> list.all(fn(character) {
      string.contains("abcdefghijklmnopqrstuvwxyz0123456789_", character)
    })
  }
}

fn valid_url(value: String) -> Bool {
  string.starts_with(value, "https://")
  && string.trim(value) == value
  && !string.contains(value, " ")
  && !string.contains(value, "\n")
  && !string.contains(value, "\r")
}

fn valid_single_line(value: String, maximum: Int) -> Bool {
  value != ""
  && string.trim(value) == value
  && string.length(value) <= maximum
  && !string.contains(value, "\n")
  && !string.contains(value, "\r")
}

fn result_try(
  result: Result(value, error),
  next: fn(value) -> Result(next, error),
) -> Result(next, error) {
  case result {
    Ok(value) -> next(value)
    Error(error) -> Error(error)
  }
}
