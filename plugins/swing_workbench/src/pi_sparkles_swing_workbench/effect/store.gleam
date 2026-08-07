/// The effect shell's sole mutable cell. It stores immutable domain state so
/// independently invoked Pi callbacks observe one sequential branch state.
pub type Store(value)

@external(javascript, "./store_ffi.mjs", "new_store")
pub fn new(value: value) -> Store(value)

@external(javascript, "./store_ffi.mjs", "read_store")
pub fn read(store: Store(value)) -> value

@external(javascript, "./store_ffi.mjs", "write_store")
pub fn write(store: Store(value), value: value) -> Nil
