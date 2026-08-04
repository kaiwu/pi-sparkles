import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/javascript/array
import gleam/javascript/promise.{type Promise}
import gleam/option.{type Option, None}
import gleam/result
import pi.{type AbortSignal, type CommandContext, type Context, type Ui}

pub type Mode {
  Tui
  Rpc
  Json
  Print
  UnknownMode(String)
}

pub type ContextUsage {
  ContextUsage(tokens: Option(Int), context_window: Int, percent: Option(Float))
}

@external(javascript, "./context_ffi.mjs", "ui")
pub fn ui(context: Context) -> Ui

@external(javascript, "./context_ffi.mjs", "cwd")
pub fn cwd(context: Context) -> String

@external(javascript, "./context_ffi.mjs", "mode")
fn mode_name(context: Context) -> String

pub fn mode(context: Context) -> Mode {
  case mode_name(context) {
    "tui" -> Tui
    "rpc" -> Rpc
    "json" -> Json
    "print" -> Print
    value -> UnknownMode(value)
  }
}

@external(javascript, "./context_ffi.mjs", "has_ui")
pub fn has_ui(context: Context) -> Bool

@external(javascript, "./context_ffi.mjs", "is_idle")
pub fn is_idle(context: Context) -> Bool

@external(javascript, "./context_ffi.mjs", "is_project_trusted")
pub fn is_project_trusted(context: Context) -> Bool

@external(javascript, "./context_ffi.mjs", "has_signal")
pub fn has_signal(context: Context) -> Bool

/// Return the active signal. Call only when `has_signal(context)` is true.
@external(javascript, "./context_ffi.mjs", "signal")
pub fn signal(context: Context) -> AbortSignal

@external(javascript, "./context_ffi.mjs", "signal_aborted")
pub fn signal_aborted(signal: AbortSignal) -> Bool

@external(javascript, "./context_ffi.mjs", "abort")
pub fn abort(context: Context) -> Nil

@external(javascript, "./context_ffi.mjs", "has_pending_messages")
pub fn has_pending_messages(context: Context) -> Bool

@external(javascript, "./context_ffi.mjs", "shutdown")
pub fn shutdown(context: Context) -> Nil

@external(javascript, "./context_ffi.mjs", "compact")
pub fn compact(context: Context) -> Nil

@external(javascript, "./context_ffi.mjs", "get_system_prompt")
pub fn get_system_prompt(context: Context) -> String

@external(javascript, "./context_ffi.mjs", "get_context_usage")
fn get_context_usage_value(context: Context) -> Dynamic

pub fn get_context_usage(context: Context) -> Option(ContextUsage) {
  let decoder = {
    use tokens <- decode.field("tokens", decode.optional(decode.int))
    use context_window <- decode.field("contextWindow", decode.int)
    use percent <- decode.field("percent", decode.optional(decode.float))
    decode.success(ContextUsage(tokens:, context_window:, percent:))
  }

  context
  |> get_context_usage_value
  |> decode.run(decode.optional(decoder))
  |> result.unwrap(None)
}

@external(javascript, "./context_ffi.mjs", "get_scoped_models")
fn get_scoped_models_array(context: Context) -> array.Array(Dynamic)

pub fn get_scoped_models(context: Context) -> List(Dynamic) {
  context |> get_scoped_models_array |> array.to_list
}

@external(javascript, "./context_ffi.mjs", "wait_for_idle")
pub fn wait_for_idle(context: CommandContext) -> Promise(Nil)

@external(javascript, "./context_ffi.mjs", "new_session")
pub fn new_session(context: CommandContext) -> Promise(Dynamic)

@external(javascript, "./context_ffi.mjs", "fork")
pub fn fork(
  context: CommandContext,
  entry_id: String,
  position: String,
) -> Promise(Dynamic)

@external(javascript, "./context_ffi.mjs", "navigate_tree")
pub fn navigate_tree(
  context: CommandContext,
  target_id: String,
  summarize: Bool,
) -> Promise(Dynamic)

@external(javascript, "./context_ffi.mjs", "switch_session")
pub fn switch_session(
  context: CommandContext,
  session_path: String,
) -> Promise(Dynamic)

@external(javascript, "./context_ffi.mjs", "reload")
pub fn reload(context: CommandContext) -> Promise(Nil)
