import gleam/dynamic.{type Dynamic}
import pi.{type EventBus}

pub type Unsubscribe

@external(javascript, "./event_bus_ffi.mjs", "emit")
pub fn emit(bus: EventBus, channel: String, data: Dynamic) -> Nil

@external(javascript, "./event_bus_ffi.mjs", "on")
pub fn on(
  bus: EventBus,
  channel: String,
  handler: fn(Dynamic) -> Nil,
) -> Unsubscribe

@external(javascript, "./event_bus_ffi.mjs", "unsubscribe")
pub fn unsubscribe(subscription: Unsubscribe) -> Nil
