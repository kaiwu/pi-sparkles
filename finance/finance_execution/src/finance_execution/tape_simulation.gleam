import finance_core/decimal.{type Decimal}
import finance_core/identifier
import finance_core/time.{type Instant}
import finance_execution/instruction.{type DesiredInstruction, type Side}
import finance_execution/numeric
import finance_provenance/identity.{type Sha256}
import finance_tape.{type Event, type Packet}
import finance_track
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{Eq, Gt, Lt}
import gleam/result
import gleam/string

pub const transaction_tape_possible_fill_v1 = "transaction_tape_possible_fill_v1"

pub opaque type EligibilityPolicy {
  EligibilityPolicy(
    eligible_venue_lexemes: List(String),
    eligible_condition_codes: List(String),
    allow_unconditioned_events: Bool,
  )
}

pub type CandidateTrade {
  CandidateTrade(
    event_id: String,
    trade_id: String,
    price: Decimal,
    price_lexeme: String,
    size: Decimal,
    size_lexeme: String,
    venue_lexeme: String,
    condition_codes: List(String),
    event_time_unix_milliseconds: Int,
    event_clock_basis: TapeClockBasis,
    raw_receipt_hash: Sha256,
  )
}

pub type TapeClockBasis {
  ExchangeEventClock
  ProviderEventClock
  RetrievalClock
}

pub type ExcludedTrade {
  ExcludedTrade(event_id: String, reason: String)
}

pub type TapeBranch {
  CompatibleNonFill(reason: String)
  CompatibleFillUpTo(quantity: Decimal, reason: String)
}

pub opaque type TapeSimulation {
  TapeSimulation(
    model: String,
    instruction_receipt: Sha256,
    provider: String,
    feed: String,
    session_id: String,
    side: Side,
    limit_price: Decimal,
    requested_quantity: Decimal,
    candidates: List(CandidateTrade),
    excluded: List(ExcludedTrade),
    observed_candidate_quantity: Decimal,
    compatible_fill_quantity: Decimal,
    branches: List(TapeBranch),
    provider_declared_complete: Bool,
    sequence_issue_count: Int,
    condition_documentation_complete: Bool,
  )
}

pub type TapeSimulationError {
  InvalidPolicy(field: String)
  IdentityMismatch(field: String, expected: String, received: String)
  UnsupportedOrderBehavior
  UnsupportedQuantityUnit
  DuplicateOrConflictingEvents
  UnresolvedCorrectionOrCancel(event_id: String)
  InvalidTradeLexeme(event_id: String, field: String)
  InvalidInstructionWindow
}

pub fn eligibility_policy(
  eligible_venue_lexemes venues: List(String),
  eligible_condition_codes conditions: List(String),
  allow_unconditioned_events allow_unconditioned: Bool,
) -> Result(EligibilityPolicy, TapeSimulationError) {
  use _ <- result.try(valid_policy_values("eligibleVenueLexemes", venues, True))
  use _ <- result.try(valid_policy_values(
    "eligibleConditionCodes",
    conditions,
    False,
  ))
  Ok(EligibilityPolicy(venues, conditions, allow_unconditioned))
}

pub fn simulate(
  instruction instruction_value: DesiredInstruction,
  packet packet_value: Packet,
  policy policy_value: EligibilityPolicy,
) -> Result(TapeSimulation, TapeSimulationError) {
  use _ <- result.try(validate_identity(instruction_value, packet_value))
  use limit_price <- result.try(
    case instruction.order_behavior(instruction_value) {
      instruction.Limit(value) -> Ok(value)
      _ -> Error(UnsupportedOrderBehavior)
    },
  )
  use _ <- result.try(case instruction.quantity_unit(instruction_value) {
    instruction.Shares -> Ok(Nil)
    _ -> Error(UnsupportedQuantityUnit)
  })
  use _ <- result.try(valid_instruction_window(instruction_value))
  let tape_review = finance_tape.review(packet_value)
  use _ <- result.try(
    case
      finance_tape.duplicate_event_id_values(tape_review),
      finance_tape.conflicting_event_id_values(tape_review),
      finance_tape.duplicate_original_trade_id_values(tape_review)
    {
      [], [], [] -> Ok(Nil)
      _, _, _ -> Error(DuplicateOrConflictingEvents)
    },
  )
  let events = finance_tape.packet_events(packet_value)
  use _ <- result.try(list.try_each(events, require_original_trade))
  use classified <- result.try(
    classify_events(
      events,
      instruction.side(instruction_value),
      limit_price,
      policy_value,
      instruction.activation_time(instruction_value),
      instruction.expiry_time(instruction_value),
      [],
      [],
    ),
  )
  let #(candidate_values, excluded_values) = classified
  let observed =
    list.fold(candidate_values, decimal.zero(), fn(total, candidate) {
      decimal.add(total, candidate.size)
    })
  let requested = instruction.quantity(instruction_value)
  let compatible_quantity = numeric.minimum(requested, observed)
  let branches = case numeric.positive(compatible_quantity) {
    True -> [
      CompatibleNonFill(
        "transaction prints do not prove queue position or this order's fill",
      ),
      CompatibleFillUpTo(
        compatible_quantity,
        "a hypothetical fill up to observed eligible printed quantity is compatible; it is not an observed order receipt",
      ),
    ]
    False -> [
      CompatibleNonFill(
        "no supplied original transaction matched the explicit venue, condition and limit policy",
      ),
    ]
  }
  Ok(TapeSimulation(
    transaction_tape_possible_fill_v1,
    instruction.instruction_receipt(instruction_value),
    finance_tape.packet_provider(packet_value),
    finance_tape.packet_feed(packet_value),
    finance_tape.packet_session_id(packet_value),
    instruction.side(instruction_value),
    limit_price,
    requested,
    candidate_values,
    excluded_values,
    observed,
    compatible_quantity,
    branches,
    finance_tape.review_provider_declared_complete(tape_review),
    tape_review
      |> finance_tape.review_sequence_issues
      |> list.length,
    finance_tape.review_condition_documentation_complete(tape_review),
  ))
}

pub fn model(value: TapeSimulation) -> String {
  value.model
}

pub fn instruction_receipt(value: TapeSimulation) -> Sha256 {
  value.instruction_receipt
}

pub fn provider(value: TapeSimulation) -> String {
  value.provider
}

pub fn feed(value: TapeSimulation) -> String {
  value.feed
}

pub fn session_id(value: TapeSimulation) -> String {
  value.session_id
}

pub fn side(value: TapeSimulation) -> Side {
  value.side
}

pub fn limit_price(value: TapeSimulation) -> Decimal {
  value.limit_price
}

pub fn requested_quantity(value: TapeSimulation) -> Decimal {
  value.requested_quantity
}

pub fn candidates(value: TapeSimulation) -> List(CandidateTrade) {
  value.candidates
}

pub fn excluded(value: TapeSimulation) -> List(ExcludedTrade) {
  value.excluded
}

pub fn observed_candidate_quantity(value: TapeSimulation) -> Decimal {
  value.observed_candidate_quantity
}

pub fn compatible_fill_quantity(value: TapeSimulation) -> Decimal {
  value.compatible_fill_quantity
}

pub fn branches(value: TapeSimulation) -> List(TapeBranch) {
  value.branches
}

pub fn provider_declared_complete(value: TapeSimulation) -> Bool {
  value.provider_declared_complete
}

pub fn sequence_issue_count(value: TapeSimulation) -> Int {
  value.sequence_issue_count
}

pub fn condition_documentation_complete(value: TapeSimulation) -> Bool {
  value.condition_documentation_complete
}

pub fn error_message(value: TapeSimulationError) -> String {
  case value {
    InvalidPolicy(field) ->
      "Invalid transaction-tape simulation policy: " <> field
    IdentityMismatch(field, expected, received) ->
      "Transaction-tape simulation "
      <> field
      <> " mismatch: expected "
      <> expected
      <> ", received "
      <> received
    UnsupportedOrderBehavior ->
      "Transaction-tape possible-fill model supports limit instructions only"
    UnsupportedQuantityUnit ->
      "Transaction-tape possible-fill model supports share quantities only"
    DuplicateOrConflictingEvents ->
      "Transaction-tape possible-fill model rejects duplicate or conflicting events"
    UnresolvedCorrectionOrCancel(event_id) ->
      "Transaction-tape possible-fill model requires reconciled original trades; found "
      <> event_id
    InvalidTradeLexeme(event_id, field) ->
      "Transaction-tape event "
      <> event_id
      <> " has no positive known "
      <> field
    InvalidInstructionWindow ->
      "Transaction-tape simulation activation time follows expiry time"
  }
}

fn validate_identity(
  instruction_value: DesiredInstruction,
  packet_value: Packet,
) -> Result(Nil, TapeSimulationError) {
  use _ <- result.try(
    case
      instruction.track(instruction_value)
      == finance_tape.packet_track(packet_value)
    {
      True -> Ok(Nil)
      False ->
        Error(IdentityMismatch(
          "track",
          finance_track.name(instruction.track(instruction_value)),
          finance_track.name(finance_tape.packet_track(packet_value)),
        ))
    },
  )
  use _ <- result.try(
    case
      instruction.listing_id(instruction_value)
      == finance_tape.packet_listing_id(packet_value)
    {
      True -> Ok(Nil)
      False ->
        Error(IdentityMismatch(
          "listingId",
          instruction.listing_id(instruction_value),
          finance_tape.packet_listing_id(packet_value),
        ))
    },
  )
  let packet_mic =
    packet_value |> finance_tape.packet_mic |> identifier.mic_value
  case instruction.mic(instruction_value) == packet_mic {
    True -> Ok(Nil)
    False ->
      Error(IdentityMismatch(
        "mic",
        instruction.mic(instruction_value),
        packet_mic,
      ))
  }
}

fn require_original_trade(event: Event) -> Result(Nil, TapeSimulationError) {
  case finance_tape.event_kind(event) {
    finance_tape.OriginalTrade -> Ok(Nil)
    _ -> Error(UnresolvedCorrectionOrCancel(finance_tape.event_id(event)))
  }
}

fn classify_events(
  events: List(Event),
  side: Side,
  limit: Decimal,
  policy: EligibilityPolicy,
  activation_time: Option(Instant),
  expiry_time: Option(Instant),
  candidates: List(CandidateTrade),
  excluded: List(ExcludedTrade),
) -> Result(#(List(CandidateTrade), List(ExcludedTrade)), TapeSimulationError) {
  case events {
    [] -> Ok(#(list.reverse(candidates), list.reverse(excluded)))
    [event, ..rest] -> {
      use #(price, price_lexeme) <- result.try(known_positive_lexeme(
        event,
        "price",
        finance_tape.event_price(event),
      ))
      use #(size, size_lexeme) <- result.try(known_positive_lexeme(
        event,
        "size",
        finance_tape.event_size(event),
      ))
      let #(event_time, clock_basis) = event_time(event)
      let reason =
        exclusion_reason(
          event,
          side,
          price,
          limit,
          policy,
          event_time,
          activation_time,
          expiry_time,
        )
      case reason {
        "" -> {
          let candidate =
            CandidateTrade(
              finance_tape.event_id(event),
              finance_tape.trade_id(event),
              price,
              price_lexeme,
              size,
              size_lexeme,
              finance_tape.event_venue_lexeme(event),
              finance_tape.event_condition_codes(event),
              event_time,
              clock_basis,
              finance_tape.event_raw_receipt_hash(event),
            )
          classify_events(
            rest,
            side,
            limit,
            policy,
            activation_time,
            expiry_time,
            [candidate, ..candidates],
            excluded,
          )
        }
        reason ->
          classify_events(
            rest,
            side,
            limit,
            policy,
            activation_time,
            expiry_time,
            candidates,
            [ExcludedTrade(finance_tape.event_id(event), reason), ..excluded],
          )
      }
    }
  }
}

fn known_positive_lexeme(
  event: Event,
  field: String,
  value: finance_tape.Lexeme,
) -> Result(#(Decimal, String), TapeSimulationError) {
  case value {
    finance_tape.KnownLexeme(lexeme) ->
      case decimal.parse(lexeme) {
        Ok(value) ->
          case numeric.positive(value) {
            True -> Ok(#(value, lexeme))
            False ->
              Error(InvalidTradeLexeme(finance_tape.event_id(event), field))
          }
        _ -> Error(InvalidTradeLexeme(finance_tape.event_id(event), field))
      }
    _ -> Error(InvalidTradeLexeme(finance_tape.event_id(event), field))
  }
}

fn exclusion_reason(
  event: Event,
  side: Side,
  price: Decimal,
  limit: Decimal,
  policy: EligibilityPolicy,
  event_time: Int,
  activation_time: Option(Instant),
  expiry_time: Option(Instant),
) -> String {
  let venue = finance_tape.event_venue_lexeme(event)
  let conditions = finance_tape.event_condition_codes(event)
  case within_instruction_window(event_time, activation_time, expiry_time) {
    False -> "outside_instruction_time_window"
    True ->
      case list.contains(policy.eligible_venue_lexemes, venue) {
        False -> "venue_not_eligible"
        True ->
          case conditions {
            [] if !policy.allow_unconditioned_events ->
              "unconditioned_event_not_eligible"
            values ->
              case
                list.all(values, fn(value) {
                  list.contains(policy.eligible_condition_codes, value)
                })
              {
                False -> "condition_not_eligible"
                True ->
                  case price_allowed(side, price, limit) {
                    True -> ""
                    False -> "outside_limit"
                  }
              }
          }
      }
  }
}

fn event_time(event: Event) -> #(Int, TapeClockBasis) {
  let clocks = finance_tape.event_clocks(event)
  case
    finance_tape.exchange_unix_milliseconds(clocks),
    finance_tape.provider_unix_milliseconds(clocks)
  {
    Some(value), _ -> #(value, ExchangeEventClock)
    None, Some(value) -> #(value, ProviderEventClock)
    None, None -> #(
      finance_tape.retrieved_unix_milliseconds(clocks),
      RetrievalClock,
    )
  }
}

fn valid_instruction_window(
  instruction_value: DesiredInstruction,
) -> Result(Nil, TapeSimulationError) {
  case
    instruction.activation_time(instruction_value),
    instruction.expiry_time(instruction_value)
  {
    Some(activation), Some(expiry) ->
      case time.unix_milliseconds(activation) > time.unix_milliseconds(expiry) {
        True -> Error(InvalidInstructionWindow)
        False -> Ok(Nil)
      }
    _, _ -> Ok(Nil)
  }
}

fn within_instruction_window(
  event_time: Int,
  activation_time: Option(Instant),
  expiry_time: Option(Instant),
) -> Bool {
  let after_activation = case activation_time {
    None -> True
    Some(value) -> event_time >= time.unix_milliseconds(value)
  }
  let before_expiry = case expiry_time {
    None -> True
    Some(value) -> event_time <= time.unix_milliseconds(value)
  }
  after_activation && before_expiry
}

fn price_allowed(side: Side, price: Decimal, limit: Decimal) -> Bool {
  case side, decimal.compare(price, limit) {
    instruction.Buy, Lt | instruction.Buy, Eq -> True
    instruction.Sell, Gt | instruction.Sell, Eq -> True
    _, _ -> False
  }
}

fn valid_policy_values(
  field: String,
  values: List(String),
  required: Bool,
) -> Result(Nil, TapeSimulationError) {
  use _ <- result.try(case required && list.is_empty(values) {
    True -> Error(InvalidPolicy(field <> " must not be empty"))
    False -> Ok(Nil)
  })
  use _ <- result.try(
    case list.length(values) == list.length(list.unique(values)) {
      True -> Ok(Nil)
      False -> Error(InvalidPolicy(field <> " must contain unique values"))
    },
  )
  case
    list.all(values, fn(value) {
      value != "" && string.trim(value) == value && string.length(value) <= 200
    })
  {
    True -> Ok(Nil)
    False -> Error(InvalidPolicy(field <> " contains invalid text"))
  }
}
