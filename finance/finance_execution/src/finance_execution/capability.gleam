import finance_execution/fact.{type Fact}
import finance_execution/instruction.{
  type Side, type TimeInForce, type TriggerBasis,
}
import finance_track.{type Track}
import gleam/list
import gleam/string

pub type TickHandling {
  RoundToTick
  RejectOffTick
  AcceptTickAsIs
}

pub type LotHandling {
  RoundToLot
  RejectOffLot
  AcceptLotAsIs
}

pub type NativeOrderType {
  NativeOrderType(
    code: String,
    required_fields: List(String),
    optional_fields: List(String),
  )
}

pub opaque type Capability {
  Capability(
    provider_id: String,
    account_id: String,
    track: Track,
    listing_scope: List(String),
    mic_scope: List(String),
    session_scope: List(String),
    supported_order_types: List(NativeOrderType),
    supported_sides: List(Side),
    supported_time_in_force: List(TimeInForce),
    trigger_bases: List(TriggerBasis),
    cancel_support: Fact(Bool),
    replace_support: Fact(Bool),
    tick_handling: Fact(TickHandling),
    lot_handling: Fact(LotHandling),
    version: String,
  )
}

pub type CapabilityError {
  InvalidText(field: String)
  EmptyOrderTypes
  EmptySides
  EmptyTimeInForce
}

pub fn capability(
  provider_id provider_value: String,
  account_id account_value: String,
  track track_value: Track,
  listing_scope listing_values: List(String),
  mic_scope mic_values: List(String),
  session_scope session_values: List(String),
  supported_order_types order_type_values: List(NativeOrderType),
  supported_sides side_values: List(Side),
  supported_time_in_force tif_values: List(TimeInForce),
  trigger_bases trigger_values: List(TriggerBasis),
  cancel_support cancel_value: Fact(Bool),
  replace_support replace_value: Fact(Bool),
  tick_handling tick_value: Fact(TickHandling),
  lot_handling lot_value: Fact(LotHandling),
  version version_value: String,
) -> Result(Capability, CapabilityError) {
  case
    valid_text(provider_value),
    valid_text(account_value),
    valid_text(version_value)
  {
    False, _, _ -> Error(InvalidText("provider_id"))
    _, False, _ -> Error(InvalidText("account_id"))
    _, _, False -> Error(InvalidText("version"))
    True, True, True ->
      case
        list.is_empty(order_type_values),
        list.is_empty(side_values),
        list.is_empty(tif_values)
      {
        True, _, _ -> Error(EmptyOrderTypes)
        _, True, _ -> Error(EmptySides)
        _, _, True -> Error(EmptyTimeInForce)
        False, False, False ->
          Ok(Capability(
            provider_value,
            account_value,
            track_value,
            listing_values,
            mic_values,
            session_values,
            order_type_values,
            side_values,
            tif_values,
            trigger_values,
            cancel_value,
            replace_value,
            tick_value,
            lot_value,
            version_value,
          ))
      }
  }
}

pub fn provider_id(value: Capability) -> String {
  value.provider_id
}

pub fn account_id(value: Capability) -> String {
  value.account_id
}

pub fn track(value: Capability) -> Track {
  value.track
}

pub fn supported_order_types(value: Capability) -> List(NativeOrderType) {
  value.supported_order_types
}

pub fn supported_sides(value: Capability) -> List(Side) {
  value.supported_sides
}

pub fn supported_time_in_force(value: Capability) -> List(TimeInForce) {
  value.supported_time_in_force
}

pub fn cancel_support(value: Capability) -> Fact(Bool) {
  value.cancel_support
}

pub fn replace_support(value: Capability) -> Fact(Bool) {
  value.replace_support
}

pub fn native_code(value: NativeOrderType) -> String {
  let NativeOrderType(code, _, _) = value
  code
}

pub fn required_fields(value: NativeOrderType) -> List(String) {
  let NativeOrderType(_, fields, _) = value
  fields
}

pub fn optional_fields(value: NativeOrderType) -> List(String) {
  let NativeOrderType(_, _, fields) = value
  fields
}

fn valid_text(value: String) -> Bool {
  value != "" && string.trim(value) == value
}
