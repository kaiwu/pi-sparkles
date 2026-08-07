import finance_core/decimal.{type Decimal, type RoundingMode}
import finance_core/time.{type Instant}
import finance_execution/fill.{type Aggregate, type Fill}
import finance_execution/numeric
import finance_provenance/identity.{type Sha256}
import gleam/list
import gleam/string

pub type EventKind {
  DesiredInstructionRecorded
  EncodingSelected(capability_reference: Sha256, instruction_reference: Sha256)
  BrokerAcknowledged
  BrokerRejected(code: String, text: String)
  ExchangeAccepted
  ExchangeRejected(code: String, text: String)
  Working
  TriggerObserved
  ChildActivated
  PartiallyFilled(fill: Fill)
  FullyFilled(fills: List(Fill))
  CancelRequested
  CancelAcknowledged
  CancelRejected(code: String, text: String)
  ReplaceRequested
  ReplaceAcknowledged
  ReplaceRejected(code: String, text: String)
  Expired
  FillCorrected(original_fill_id: String, replacement: Fill)
  FillBusted(fill_id: String)
  FillReversed(fill_id: String)
  StatusUnknown(reason: String)
  SettlementObserved(reference: Sha256)
}

pub opaque type Event {
  Event(
    event_id: String,
    client_instruction_id: String,
    event_time: Instant,
    source_reference: Sha256,
    kind: EventKind,
  )
}

pub type LifecycleState {
  StateUnknown(reason: String)
  DesiredRecordedState
  EncodingSelectedState
  BrokerAcknowledgedState
  WorkingState
  PartiallyFilledState
  FilledState
  CancelledState
  ExpiredState
  BrokerRejectedState(code: String, text: String)
  ExchangeRejectedState(code: String, text: String)
  ConflictingState(reason: String)
}

pub opaque type Projection {
  Projection(
    client_instruction_id: String,
    desired_quantity: Decimal,
    ordered_events: List(Event),
    ordered_fills: List(Fill),
    state: LifecycleState,
    cumulative_filled: Decimal,
    remaining_quantity: Decimal,
    fill_aggregate: Result(Aggregate, String),
    cancel_requested: Bool,
    cancel_acknowledged: Bool,
    fill_after_cancel_request: Bool,
  )
}

pub type LifecycleError {
  InvalidText(field: String)
  NonPositiveDesiredQuantity
  InvalidScale
}

pub fn event(
  event_id event_id_value: String,
  client_instruction_id instruction_value: String,
  event_time event_time_value: Instant,
  source_reference source_value: Sha256,
  kind kind_value: EventKind,
) -> Result(Event, LifecycleError) {
  case valid_text(event_id_value), valid_text(instruction_value) {
    False, _ -> Error(InvalidText("event_id"))
    _, False -> Error(InvalidText("client_instruction_id"))
    True, True ->
      Ok(Event(
        event_id_value,
        instruction_value,
        event_time_value,
        source_value,
        kind_value,
      ))
  }
}

pub fn fold(
  client_instruction_id instruction_value: String,
  desired_quantity quantity_value: Decimal,
  ordered_events event_values: List(Event),
  output_scale output_scale_value: Int,
  rounding rounding_value: RoundingMode,
) -> Result(Projection, LifecycleError) {
  case valid_text(instruction_value), numeric.positive(quantity_value) {
    False, _ -> Error(InvalidText("client_instruction_id"))
    _, False -> Error(NonPositiveDesiredQuantity)
    True, True ->
      case output_scale_value < 0 {
        True -> Error(InvalidScale)
        False ->
          event_values
          |> list.fold(
            initial(instruction_value, quantity_value),
            fn(projection, value) {
              apply(projection, value, output_scale_value, rounding_value)
            },
          )
          |> Ok
      }
  }
}

pub fn initial(
  client_instruction_id instruction_value: String,
  desired_quantity quantity_value: Decimal,
) -> Projection {
  Projection(
    instruction_value,
    quantity_value,
    [],
    [],
    StateUnknown("no_lifecycle_event"),
    decimal.zero(),
    quantity_value,
    Error("empty_fill_list"),
    False,
    False,
    False,
  )
}

pub fn apply(
  projection projection_value: Projection,
  event event_value: Event,
  output_scale output_scale_value: Int,
  rounding rounding_value: RoundingMode,
) -> Projection {
  let identity_matches =
    event_value.client_instruction_id == projection_value.client_instruction_id
  let next_fills = case event_value.kind {
    PartiallyFilled(value) ->
      list.append(projection_value.ordered_fills, [value])
    FullyFilled(values) -> list.append(projection_value.ordered_fills, values)
    FillCorrected(_, replacement) ->
      list.append(projection_value.ordered_fills, [replacement])
    _ -> projection_value.ordered_fills
  }
  let aggregate = fill.aggregate(next_fills, output_scale_value, rounding_value)
  let cumulative =
    list.fold(next_fills, decimal.zero(), fn(total, value) {
      decimal.add(total, fill.quantity(value))
    })
  let remaining =
    decimal.subtract(projection_value.desired_quantity, cumulative)
    |> numeric.nonnegative
  let is_fill_event = case event_value.kind {
    PartiallyFilled(_) | FullyFilled(_) | FillCorrected(_, _) -> True
    _ -> False
  }
  let race =
    projection_value.fill_after_cancel_request
    || { is_fill_event && projection_value.cancel_requested }
  let cancel_requested = case event_value.kind {
    CancelRequested -> True
    _ -> projection_value.cancel_requested
  }
  let cancel_acknowledged = case event_value.kind {
    CancelAcknowledged -> True
    _ -> projection_value.cancel_acknowledged
  }
  let state = case identity_matches {
    False -> ConflictingState("client_instruction_id_mismatch")
    True -> next_state(projection_value.state, event_value.kind)
  }
  Projection(
    projection_value.client_instruction_id,
    projection_value.desired_quantity,
    list.append(projection_value.ordered_events, [event_value]),
    next_fills,
    state,
    cumulative,
    remaining,
    aggregate,
    cancel_requested,
    cancel_acknowledged,
    race,
  )
}

fn next_state(current: LifecycleState, event: EventKind) -> LifecycleState {
  case event {
    DesiredInstructionRecorded -> DesiredRecordedState
    EncodingSelected(_, _) -> EncodingSelectedState
    BrokerAcknowledged -> BrokerAcknowledgedState
    BrokerRejected(code, text) -> BrokerRejectedState(code, text)
    ExchangeAccepted | Working -> WorkingState
    ExchangeRejected(code, text) -> ExchangeRejectedState(code, text)
    TriggerObserved
    | ChildActivated
    | CancelRequested
    | CancelRejected(_, _)
    | ReplaceRequested
    | ReplaceAcknowledged
    | ReplaceRejected(_, _)
    | FillBusted(_)
    | FillReversed(_)
    | SettlementObserved(_) -> current
    PartiallyFilled(_) | FillCorrected(_, _) -> PartiallyFilledState
    FullyFilled(_) -> FilledState
    CancelAcknowledged -> CancelledState
    Expired -> ExpiredState
    StatusUnknown(reason) -> StateUnknown(reason)
  }
}

pub fn event_id(value: Event) -> String {
  value.event_id
}

pub fn client_instruction_id(value: Event) -> String {
  value.client_instruction_id
}

pub fn event_time(value: Event) -> Instant {
  value.event_time
}

pub fn source_reference(value: Event) -> Sha256 {
  value.source_reference
}

pub fn event_kind(value: Event) -> EventKind {
  value.kind
}

pub fn ordered_events(value: Projection) -> List(Event) {
  value.ordered_events
}

pub fn ordered_fills(value: Projection) -> List(Fill) {
  value.ordered_fills
}

pub fn state(value: Projection) -> LifecycleState {
  value.state
}

pub fn cumulative_filled(value: Projection) -> Decimal {
  value.cumulative_filled
}

pub fn remaining_quantity(value: Projection) -> Decimal {
  value.remaining_quantity
}

pub fn fill_aggregate(value: Projection) -> Result(Aggregate, String) {
  value.fill_aggregate
}

pub fn cancel_requested(value: Projection) -> Bool {
  value.cancel_requested
}

pub fn cancel_acknowledged(value: Projection) -> Bool {
  value.cancel_acknowledged
}

pub fn fill_after_cancel_request(value: Projection) -> Bool {
  value.fill_after_cancel_request
}

pub fn state_name(value: LifecycleState) -> String {
  case value {
    StateUnknown(_) -> "unknown"
    DesiredRecordedState -> "desired_instruction_recorded"
    EncodingSelectedState -> "encoding_selected"
    BrokerAcknowledgedState -> "broker_acknowledged"
    WorkingState -> "working"
    PartiallyFilledState -> "partially_filled"
    FilledState -> "filled"
    CancelledState -> "cancelled"
    ExpiredState -> "expired"
    BrokerRejectedState(_, _) -> "broker_rejected"
    ExchangeRejectedState(_, _) -> "exchange_rejected"
    ConflictingState(_) -> "conflicting"
  }
}

pub fn event_kind_name(value: EventKind) -> String {
  case value {
    DesiredInstructionRecorded -> "desired_instruction_recorded"
    EncodingSelected(_, _) -> "encoding_selected"
    BrokerAcknowledged -> "broker_acknowledged"
    BrokerRejected(_, _) -> "broker_rejected"
    ExchangeAccepted -> "exchange_accepted"
    ExchangeRejected(_, _) -> "exchange_rejected"
    Working -> "working"
    TriggerObserved -> "trigger_observed"
    ChildActivated -> "child_activated"
    PartiallyFilled(_) -> "partially_filled"
    FullyFilled(_) -> "filled"
    CancelRequested -> "cancel_requested"
    CancelAcknowledged -> "cancel_acknowledged"
    CancelRejected(_, _) -> "cancel_rejected"
    ReplaceRequested -> "replace_requested"
    ReplaceAcknowledged -> "replace_acknowledged"
    ReplaceRejected(_, _) -> "replace_rejected"
    Expired -> "expired"
    FillCorrected(_, _) -> "fill_corrected"
    FillBusted(_) -> "fill_busted"
    FillReversed(_) -> "fill_reversed"
    StatusUnknown(_) -> "status_unknown"
    SettlementObserved(_) -> "settlement_observed"
  }
}

fn valid_text(value: String) -> Bool {
  value != "" && string.trim(value) == value
}
