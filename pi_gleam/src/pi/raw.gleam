import gleam/dynamic.{type Dynamic}
import gleam/javascript/array
import gleam/javascript/promise.{type Promise}
import pi.{type Context, type ExtensionApi}

/// Convert any Gleam/JavaScript value into a dynamic value for a raw Pi API.
@external(javascript, "./raw_ffi.mjs", "identity")
pub fn dynamic(value: value) -> Dynamic

@external(javascript, "./raw_ffi.mjs", "undefined_value")
pub fn undefined() -> Dynamic

@external(javascript, "./raw_ffi.mjs", "null_value")
pub fn null() -> Dynamic

@external(javascript, "./raw_ffi.mjs", "object")
fn object_from_array(entries: array.Array(#(String, Dynamic))) -> Dynamic

pub fn object(entries: List(#(String, Dynamic))) -> Dynamic {
  entries |> array.from_list |> object_from_array
}

@external(javascript, "./raw_ffi.mjs", "get")
pub fn get(target: Dynamic, property: String) -> Dynamic

@external(javascript, "./raw_ffi.mjs", "set")
pub fn set(target: Dynamic, property: String, value: Dynamic) -> Nil

@external(javascript, "./raw_ffi.mjs", "call")
fn call_array(
  target: Dynamic,
  method: String,
  args: array.Array(Dynamic),
) -> Dynamic

pub fn call(target: Dynamic, method: String, args: List(Dynamic)) -> Dynamic {
  call_array(target, method, array.from_list(args))
}

@external(javascript, "./raw_ffi.mjs", "as_promise")
pub fn as_promise(value: Dynamic) -> Promise(Dynamic)

@external(javascript, "./raw_ffi.mjs", "on")
pub fn on(
  api: ExtensionApi,
  event: String,
  handler: fn(Dynamic, Context) -> Promise(Dynamic),
) -> Nil

@external(javascript, "./raw_ffi.mjs", "register_tool")
pub fn register_tool(api: ExtensionApi, definition: Dynamic) -> Nil

@external(javascript, "./raw_ffi.mjs", "register_message_renderer")
pub fn register_message_renderer(
  api: ExtensionApi,
  custom_type: String,
  renderer: fn(Dynamic, Dynamic, Dynamic) -> Dynamic,
) -> Nil

@external(javascript, "./raw_ffi.mjs", "register_entry_renderer")
pub fn register_entry_renderer(
  api: ExtensionApi,
  custom_type: String,
  renderer: fn(Dynamic, Dynamic, Dynamic) -> Dynamic,
) -> Nil

@external(javascript, "./raw_ffi.mjs", "register_markdown_transformer")
pub fn register_markdown_transformer(
  api: ExtensionApi,
  transformer: fn(String, Dynamic) -> String,
) -> Nil
