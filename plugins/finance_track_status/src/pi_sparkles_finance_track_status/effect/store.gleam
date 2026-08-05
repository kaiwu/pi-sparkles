/// The effect shell's only mutable cell. It stores immutable pure state so
/// independently invoked Pi callbacks share the current track.
pub type Store(value)

@external(javascript, "./store_ffi.mjs", "new_store")
pub fn new(value: value) -> Store(value)

@external(javascript, "./store_ffi.mjs", "read_store")
pub fn read(store: Store(value)) -> value

@external(javascript, "./store_ffi.mjs", "write_store")
pub fn write(store: Store(value), value: value) -> Nil
