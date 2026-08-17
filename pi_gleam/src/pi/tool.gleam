import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode.{type Decoder}
import gleam/javascript/array
import gleam/javascript/promise.{type Promise}
import gleam/json.{type Json}
import gleam/string
import pi.{type AbortSignal, type Context, type ExtensionApi, type UpdateSink}
import pi/schema.{type Schema}

/// A runtime schema paired with the decoder that admits values into typed
/// Gleam plugin code.
pub opaque type Parameters(value) {
  Parameters(schema: Schema, decoder: Decoder(value))
}

pub type ExecutionMode {
  DefaultExecution
  Sequential
  Parallel
}

/// Plain JavaScript content accepted by Pi tool results.
pub type Content

/// Plain JavaScript object accepted by Pi as a tool result.
pub type ToolResult

/// Host renderer called by Pi for a completed tool result. The returned value
/// is a Pi TUI Component. Plugins keep host-specific component construction in
/// their JavaScript effect shell while typed decoding/execution stays here.
pub type ResultRenderer =
  fn(Dynamic, Bool, Dynamic, Dynamic) -> Dynamic

pub fn parameters(
  schema: Schema,
  decoder: Decoder(value),
) -> Parameters(value) {
  Parameters(schema, decoder)
}

@external(javascript, "./tool_ffi.mjs", "register")
fn do_register(
  api: ExtensionApi,
  name: String,
  label: String,
  description: String,
  prompt_snippet: String,
  schema: Schema,
  execution_mode: String,
  execute: fn(String, Dynamic, AbortSignal, UpdateSink, Context) ->
    Promise(ToolResult),
) -> Nil

@external(javascript, "./tool_ffi.mjs", "register_compact")
fn do_register_compact(
  api: ExtensionApi,
  name: String,
  label: String,
  description: String,
  prompt_snippet: String,
  schema: Schema,
  execution_mode: String,
  execute: fn(String, Dynamic, AbortSignal, UpdateSink, Context) ->
    Promise(ToolResult),
) -> Nil

@external(javascript, "./tool_ffi.mjs", "register_rendered")
fn do_register_rendered(
  api: ExtensionApi,
  name: String,
  label: String,
  description: String,
  prompt_snippet: String,
  schema: Schema,
  execution_mode: String,
  execute: fn(String, Dynamic, AbortSignal, UpdateSink, Context) ->
    Promise(ToolResult),
  renderer: ResultRenderer,
) -> Nil

/// Register a typed tool. Invalid raw parameters reject before `execute` runs.
pub fn register(
  api: ExtensionApi,
  name: String,
  label: String,
  description: String,
  prompt_snippet: String,
  parameters: Parameters(value),
  execution_mode: ExecutionMode,
  execute: fn(String, value, AbortSignal, UpdateSink, Context) ->
    Promise(ToolResult),
) -> Nil {
  let Parameters(schema, decoder) = parameters
  do_register(
    api,
    name,
    label,
    description,
    prompt_snippet,
    schema,
    execution_mode_name(execution_mode),
    fn(tool_call_id, raw, signal, updates, context) {
      case decode.run(raw, decoder) {
        Ok(value) -> execute(tool_call_id, value, signal, updates, context)
        Error(errors) ->
          reject(
            "Invalid parameters for tool "
            <> name
            <> ": "
            <> string.inspect(errors),
          )
      }
    },
  )
}

/// Register a typed tool whose default TUI result is only the first content
/// line. Pi still sends the complete content to the LLM and keeps details in
/// session state; users can explicitly expand the result to inspect content.
pub fn register_compact(
  api: ExtensionApi,
  name: String,
  label: String,
  description: String,
  prompt_snippet: String,
  parameters: Parameters(value),
  execution_mode: ExecutionMode,
  execute: fn(String, value, AbortSignal, UpdateSink, Context) ->
    Promise(ToolResult),
) -> Nil {
  let Parameters(schema, decoder) = parameters
  do_register_compact(
    api,
    name,
    label,
    description,
    prompt_snippet,
    schema,
    execution_mode_name(execution_mode),
    fn(tool_call_id, raw, signal, updates, context) {
      case decode.run(raw, decoder) {
        Ok(value) -> execute(tool_call_id, value, signal, updates, context)
        Error(errors) ->
          reject(
            "Invalid parameters for tool "
            <> name
            <> ": "
            <> string.inspect(errors),
          )
      }
    },
  )
}

/// Register a typed tool with a host-native Pi result component. `renderer`
/// receives the raw result, expanded state, theme, and prior component so the
/// effect shell can reuse a width-responsive component across rerenders.
pub fn register_rendered(
  api: ExtensionApi,
  name: String,
  label: String,
  description: String,
  prompt_snippet: String,
  parameters: Parameters(value),
  execution_mode: ExecutionMode,
  renderer: ResultRenderer,
  execute: fn(String, value, AbortSignal, UpdateSink, Context) ->
    Promise(ToolResult),
) -> Nil {
  let Parameters(schema, decoder) = parameters
  do_register_rendered(
    api,
    name,
    label,
    description,
    prompt_snippet,
    schema,
    execution_mode_name(execution_mode),
    fn(tool_call_id, raw, signal, updates, context) {
      case decode.run(raw, decoder) {
        Ok(value) -> execute(tool_call_id, value, signal, updates, context)
        Error(errors) ->
          reject(
            "Invalid parameters for tool "
            <> name
            <> ": "
            <> string.inspect(errors),
          )
      }
    },
    renderer,
  )
}

@external(javascript, "./tool_ffi.mjs", "text")
pub fn text(value: String) -> Content

@external(javascript, "./tool_ffi.mjs", "image")
pub fn image(data: String, mime_type: String) -> Content

@external(javascript, "./tool_ffi.mjs", "result")
fn result_array(
  content: array.Array(Content),
  details: Json,
  terminate: Bool,
) -> ToolResult

pub fn result(
  content: List(Content),
  details: Json,
  terminate: Bool,
) -> ToolResult {
  result_array(array.from_list(content), details, terminate)
}

@external(javascript, "./tool_ffi.mjs", "text_result")
pub fn text_result(value: String, details: Json) -> ToolResult

@external(javascript, "./tool_ffi.mjs", "update")
pub fn update(sink: UpdateSink, result: ToolResult) -> Nil

@external(javascript, "./tool_ffi.mjs", "is_cancelled")
pub fn is_cancelled(signal: AbortSignal) -> Bool

@external(javascript, "./tool_ffi.mjs", "reject")
pub fn reject(message: String) -> Promise(value)

/// Reject with a stable machine-readable code and safe structured context.
/// Pi versions that only render `Error.message` still retain the code prefix.
@external(javascript, "./tool_ffi.mjs", "reject_typed")
pub fn reject_typed(
  code: String,
  message: String,
  details: Json,
) -> Promise(value)

fn execution_mode_name(mode: ExecutionMode) -> String {
  case mode {
    DefaultExecution -> ""
    Sequential -> "sequential"
    Parallel -> "parallel"
  }
}
