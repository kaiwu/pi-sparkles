import finance_core/source.{type SourceRef}
import finance_http/cache
import finance_track.{type Track}
import gleam/list
import gleam/string

/// Trust role is independent of configured priority.
///
/// A secondary observation can improve availability but cannot become
/// canonical evidence merely by being placed first in configuration.
pub type Role {
  CanonicalEvidence
  PrimaryObservation
  SecondaryObservation
}

/// How bytes or observations were obtained, kept separately from their origin.
pub type Route {
  Direct
  Via(adapter: String)
}

/// Operational approval is deliberately narrower than a licence grant.
pub type Access {
  VerifiedReadOnly
  Contracted
  Candidate(reason: String)
}

pub type UsePolicy {
  LocalAnalysisOnly
  AttributionRequired
  Redistributable
  ContractControlled
}

pub type CachePolicy {
  BypassCache
  CacheFirst
  RevalidateCache
  OfflineCache
}

/// The semantic identity that every fallback response must preserve.
///
/// Strings are source-domain vocabulary, not display labels. Source packages
/// expose constructors with their own closed enums where stronger laws exist.
pub opaque type Contract {
  Contract(
    family: String,
    identity: String,
    freshness: String,
    unit_basis: String,
    adjustment_basis: String,
  )
}

pub opaque type Channel {
  Channel(
    track: Track,
    id: String,
    origin: SourceRef,
    route: Route,
    role: Role,
    access: Access,
    use_policy: UsePolicy,
    contract: Contract,
  )
}

pub opaque type Plan {
  Plan(
    track: Track,
    contract: Contract,
    cache_policy: CachePolicy,
    channels: List(Channel),
  )
}

pub type ContractError {
  InvalidFamily
  InvalidIdentity
  InvalidFreshness
  InvalidUnitBasis
  InvalidAdjustmentBasis
}

pub type ChannelError {
  InvalidChannelId
  WrongTrackChannelId(expected_prefix: String)
  InvalidRoute
  InvalidCandidateReason
  CanonicalOriginRequired
}

pub type PlanError {
  EmptyPlan
  TrackMismatch(channel_id: String)
  ContractMismatch(channel_id: String)
  UnapprovedChannel(channel_id: String)
  DuplicateChannel(channel_id: String)
  TrustOrderInversion(channel_id: String)
}

pub type Outcome(value) {
  Succeeded(value: value, observed_contract: Contract)
  Unavailable(reason: String)
  Failed(reason: String)
}

pub opaque type Attempt(value) {
  Attempt(channel: Channel, outcome: Outcome(value))
}

pub opaque type Record(value) {
  Record(channel: Channel, contract: Contract, value: value)
}

pub type Resolution(value) {
  Selected(record: Record(value), trace: List(Attempt(value)))
  Incomplete(next: Channel, trace: List(Attempt(value)))
  Exhausted(trace: List(Attempt(value)))
}

pub type AttemptError {
  InvalidReason
}

pub type ResolveError {
  UnexpectedAttempt(expected: String, received: String)
  ChannelConfigurationMismatch(channel_id: String)
  IncompatibleSuccess(channel_id: String)
  AttemptsAfterSelection(channel_id: String)
}

pub fn contract(
  family family: String,
  identity identity: String,
  freshness freshness: String,
  unit_basis unit_basis: String,
  adjustment_basis adjustment_basis: String,
) -> Result(Contract, ContractError) {
  case
    valid_term(family),
    valid_term(identity),
    valid_term(freshness),
    valid_term(unit_basis),
    valid_term(adjustment_basis)
  {
    False, _, _, _, _ -> Error(InvalidFamily)
    _, False, _, _, _ -> Error(InvalidIdentity)
    _, _, False, _, _ -> Error(InvalidFreshness)
    _, _, _, False, _ -> Error(InvalidUnitBasis)
    _, _, _, _, False -> Error(InvalidAdjustmentBasis)
    True, True, True, True, True ->
      Ok(Contract(family, identity, freshness, unit_basis, adjustment_basis))
  }
}

pub fn channel(
  track track_value: Track,
  id id_value: String,
  origin origin_value: SourceRef,
  route route_value: Route,
  role role_value: Role,
  access access_value: Access,
  use_policy use_policy_value: UsePolicy,
  contract contract_value: Contract,
) -> Result(Channel, ChannelError) {
  let prefix = finance_track.name(track_value) <> "_"
  case
    valid_id(id_value),
    string.starts_with(id_value, prefix),
    valid_route(route_value),
    valid_access(access_value),
    canonical_origin(role_value, origin_value)
  {
    False, _, _, _, _ -> Error(InvalidChannelId)
    _, False, _, _, _ -> Error(WrongTrackChannelId(prefix))
    _, _, False, _, _ -> Error(InvalidRoute)
    _, _, _, False, _ -> Error(InvalidCandidateReason)
    _, _, _, _, False -> Error(CanonicalOriginRequired)
    True, True, True, True, True ->
      Ok(Channel(
        track_value,
        id_value,
        origin_value,
        route_value,
        role_value,
        access_value,
        use_policy_value,
        contract_value,
      ))
  }
}

pub fn plan(
  track track_value: Track,
  contract contract_value: Contract,
  cache_policy cache_policy_value: CachePolicy,
  channels channel_values: List(Channel),
) -> Result(Plan, PlanError) {
  case channel_values {
    [] -> Error(EmptyPlan)
    _ ->
      case
        validate_channels(channel_values, track_value, contract_value, [], -1)
      {
        Error(error) -> Error(error)
        Ok(Nil) ->
          Ok(Plan(
            track_value,
            contract_value,
            cache_policy_value,
            channel_values,
          ))
      }
  }
}

pub fn succeeded(
  channel channel_value: Channel,
  observed_contract observed_contract: Contract,
  value value: value,
) -> Attempt(value) {
  Attempt(channel_value, Succeeded(value, observed_contract))
}

pub fn unavailable(
  channel channel_value: Channel,
  reason reason: String,
) -> Result(Attempt(value), AttemptError) {
  case valid_reason(reason) {
    True -> Ok(Attempt(channel_value, Unavailable(reason)))
    False -> Error(InvalidReason)
  }
}

pub fn failed(
  channel channel_value: Channel,
  reason reason: String,
) -> Result(Attempt(value), AttemptError) {
  case valid_reason(reason) {
    True -> Ok(Attempt(channel_value, Failed(reason)))
    False -> Error(InvalidReason)
  }
}

pub fn resolve(
  plan plan_value: Plan,
  attempts attempts: List(Attempt(value)),
) -> Result(Resolution(value), ResolveError) {
  resolve_next(plan_value.contract, plan_value.channels, attempts, [])
}

pub fn track(value: Plan) -> Track {
  value.track
}

pub fn plan_contract(value: Plan) -> Contract {
  value.contract
}

pub fn cache_policy(value: Plan) -> CachePolicy {
  value.cache_policy
}

pub fn channels(value: Plan) -> List(Channel) {
  value.channels
}

pub fn http_cache_mode(value: CachePolicy) -> cache.Mode {
  case value {
    BypassCache -> cache.Bypass
    CacheFirst -> cache.ReadThrough
    RevalidateCache -> cache.Revalidate
    OfflineCache -> cache.OfflineOnly
  }
}

pub fn contract_family(value: Contract) -> String {
  value.family
}

pub fn contract_identity(value: Contract) -> String {
  value.identity
}

pub fn contract_freshness(value: Contract) -> String {
  value.freshness
}

pub fn contract_unit_basis(value: Contract) -> String {
  value.unit_basis
}

pub fn contract_adjustment_basis(value: Contract) -> String {
  value.adjustment_basis
}

pub fn channel_track(value: Channel) -> Track {
  value.track
}

pub fn channel_id(value: Channel) -> String {
  value.id
}

pub fn channel_origin(value: Channel) -> SourceRef {
  value.origin
}

pub fn channel_route(value: Channel) -> Route {
  value.route
}

pub fn channel_role(value: Channel) -> Role {
  value.role
}

pub fn channel_access(value: Channel) -> Access {
  value.access
}

pub fn channel_use_policy(value: Channel) -> UsePolicy {
  value.use_policy
}

pub fn channel_contract(value: Channel) -> Contract {
  value.contract
}

pub fn attempt_channel(value: Attempt(a)) -> Channel {
  value.channel
}

pub fn attempt_outcome(value: Attempt(a)) -> Outcome(a) {
  value.outcome
}

pub fn record_channel(value: Record(a)) -> Channel {
  value.channel
}

pub fn record_contract(value: Record(a)) -> Contract {
  value.contract
}

pub fn record_value(value: Record(a)) -> a {
  value.value
}

fn resolve_next(
  contract: Contract,
  channels: List(Channel),
  attempts: List(Attempt(value)),
  reversed_trace: List(Attempt(value)),
) -> Result(Resolution(value), ResolveError) {
  case channels, attempts {
    [], [] -> Ok(Exhausted(list.reverse(reversed_trace)))
    [next, ..], [] -> Ok(Incomplete(next, list.reverse(reversed_trace)))
    [], [Attempt(received, _), ..] ->
      Error(UnexpectedAttempt("<none>", received.id))
    [expected, ..remaining_channels], [attempt, ..remaining_attempts] -> {
      let Attempt(received, outcome) = attempt
      case expected.id == received.id, expected == received {
        False, _ -> Error(UnexpectedAttempt(expected.id, received.id))
        True, False -> Error(ChannelConfigurationMismatch(expected.id))
        True, True ->
          case outcome {
            Succeeded(value, observed) ->
              case observed == contract, remaining_attempts {
                False, _ -> Error(IncompatibleSuccess(expected.id))
                True, [_, ..] -> Error(AttemptsAfterSelection(expected.id))
                True, [] ->
                  Ok(Selected(
                    Record(expected, contract, value),
                    list.reverse([attempt, ..reversed_trace]),
                  ))
              }
            Unavailable(_) | Failed(_) ->
              resolve_next(contract, remaining_channels, remaining_attempts, [
                attempt,
                ..reversed_trace
              ])
          }
      }
    }
  }
}

fn validate_channels(
  values: List(Channel),
  track: Track,
  contract: Contract,
  seen: List(String),
  previous_rank: Int,
) -> Result(Nil, PlanError) {
  case values {
    [] -> Ok(Nil)
    [first, ..rest] -> {
      let rank = role_rank(first.role)
      case
        first.track == track,
        first.contract == contract,
        first.access,
        list.contains(seen, first.id),
        rank >= previous_rank
      {
        False, _, _, _, _ -> Error(TrackMismatch(first.id))
        _, False, _, _, _ -> Error(ContractMismatch(first.id))
        _, _, Candidate(_), _, _ -> Error(UnapprovedChannel(first.id))
        _, _, _, True, _ -> Error(DuplicateChannel(first.id))
        _, _, _, _, False -> Error(TrustOrderInversion(first.id))
        True, True, VerifiedReadOnly, False, True
        | True, True, Contracted, False, True
        -> validate_channels(rest, track, contract, [first.id, ..seen], rank)
      }
    }
  }
}

fn role_rank(value: Role) -> Int {
  case value {
    CanonicalEvidence -> 0
    PrimaryObservation -> 1
    SecondaryObservation -> 2
  }
}

fn canonical_origin(role: Role, origin: SourceRef) -> Bool {
  case role, source.kind(origin) {
    CanonicalEvidence, source.Official
    | CanonicalEvidence, source.Exchange
    | CanonicalEvidence, source.Regulator
    -> True
    CanonicalEvidence, _ -> False
    PrimaryObservation, _ | SecondaryObservation, _ -> True
  }
}

fn valid_route(value: Route) -> Bool {
  case value {
    Direct -> True
    Via(adapter) -> valid_text(adapter, 100)
  }
}

fn valid_access(value: Access) -> Bool {
  case value {
    VerifiedReadOnly | Contracted -> True
    Candidate(reason) -> valid_reason(reason)
  }
}

fn valid_id(value: String) -> Bool {
  value != ""
  && string.trim(value) == value
  && string.length(value) <= 100
  && {
    value
    |> string.to_graphemes
    |> list.all(fn(character) {
      string.contains("abcdefghijklmnopqrstuvwxyz0123456789_", character)
    })
  }
}

fn valid_term(value: String) -> Bool {
  valid_text(value, 500)
}

fn valid_reason(value: String) -> Bool {
  valid_text(value, 500)
}

fn valid_text(value: String, maximum: Int) -> Bool {
  value != ""
  && string.trim(value) == value
  && string.length(value) <= maximum
  && !string.contains(value, "\r")
  && !string.contains(value, "\n")
}
