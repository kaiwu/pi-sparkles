/// The single mutable mechanism in the lifecycle plugin. It stores immutable
/// Gleam values so Pi's independently invoked callbacks share current state.
pub type Store(value)

@external(javascript, "./store_ffi.mjs", "new_store")
pub fn new(value: value) -> Store(value)

@external(javascript, "./store_ffi.mjs", "read_store")
pub fn read(store: Store(value)) -> value

@external(javascript, "./store_ffi.mjs", "write_store")
pub fn write(store: Store(value), value: value) -> Nil

pub fn update(store: Store(value), with transition: fn(value) -> value) -> Nil {
  store
  |> read
  |> transition
  |> write(store, _)
}
