import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode.{type Decoder}
import gleam/javascript/array
import gleam/javascript/promise.{type Promise}
import gleam/option.{type Option, None, Some}
import gleam/string
import pi.{type AbortSignal, type Context, type ExtensionApi}

pub const project_trust = "project_trust"

pub const resources_discover = "resources_discover"

pub const session_start = "session_start"

pub const session_info_changed = "session_info_changed"

pub const session_before_switch = "session_before_switch"

pub const session_before_fork = "session_before_fork"

pub const session_before_compact = "session_before_compact"

pub const session_compact = "session_compact"

pub const session_shutdown = "session_shutdown"

pub const session_before_tree = "session_before_tree"

pub const session_tree = "session_tree"

pub const context = "context"

pub const before_provider_headers = "before_provider_headers"

pub const before_provider_request = "before_provider_request"

pub const after_provider_response = "after_provider_response"

pub const before_agent_start = "before_agent_start"

pub const agent_start = "agent_start"

pub const agent_end = "agent_end"

pub const agent_settled = "agent_settled"

pub const turn_start = "turn_start"

pub const turn_end = "turn_end"

pub const message_start = "message_start"

pub const message_update = "message_update"

pub const message_end = "message_end"

pub const tool_execution_start = "tool_execution_start"

pub const tool_execution_update = "tool_execution_update"

pub const tool_execution_end = "tool_execution_end"

pub const model_select = "model_select"

pub const thinking_level_select = "thinking_level_select"

pub const tool_call = "tool_call"

pub const tool_result = "tool_result"

pub const user_bash = "user_bash"

pub const input = "input"

pub type Event {
  Event(type_: String, raw: Dynamic)
}

pub type SessionStart {
  SessionStart(
    reason: String,
    previous_session_file: Option(String),
    raw: Dynamic,
  )
}

pub type SessionShutdown {
  SessionShutdown(
    reason: String,
    target_session_file: Option(String),
    raw: Dynamic,
  )
}

pub type ToolCall {
  ToolCall(
    tool_call_id: String,
    tool_name: String,
    input: Dynamic,
    raw: Dynamic,
  )
}

pub type Input {
  Input(
    text: String,
    source: String,
    streaming_behavior: Option(String),
    images: List(Dynamic),
    raw: Dynamic,
  )
}

pub type TurnStart {
  TurnStart(index: Int, timestamp: Int, raw: Dynamic)
}

pub type ProviderResponse {
  ProviderResponse(status: Int, headers: Dynamic, raw: Dynamic)
}

pub type ToolExecution {
  ToolExecution(
    tool_call_id: String,
    tool_name: String,
    args: Dynamic,
    raw: Dynamic,
  )
}

@external(javascript, "./event_ffi.mjs", "observe")
fn do_observe(
  api: ExtensionApi,
  event: String,
  handler: fn(Dynamic, Context) -> Promise(Nil),
) -> Nil

@external(javascript, "./event_ffi.mjs", "respond")
fn do_respond(
  api: ExtensionApi,
  event: String,
  handler: fn(Dynamic, Context) -> Promise(Dynamic),
) -> Nil

@external(javascript, "./event_ffi.mjs", "undefined_value")
fn undefined_value() -> Dynamic

@external(javascript, "./event_ffi.mjs", "reject")
fn reject(message: String) -> Promise(value)

/// Observe any Pi event without changing its result.
pub fn observe(
  api: ExtensionApi,
  event: String,
  handler: fn(Event, Context) -> Promise(Nil),
) -> Nil {
  do_observe(api, event, fn(raw, context) {
    handler(Event(type_: event, raw: raw), context)
  })
}

/// Observe an event through a Gleam dynamic decoder.
pub fn observe_decoded(
  api: ExtensionApi,
  event: String,
  decoder: Decoder(value),
  handler: fn(value, Context) -> Promise(Nil),
) -> Nil {
  do_observe(api, event, fn(raw, context) {
    case decode.run(raw, decoder) {
      Ok(value) -> handler(value, context)
      Error(errors) ->
        reject("Could not decode Pi event: " <> string.inspect(errors))
    }
  })
}

/// Handle any result-bearing Pi event. `None` maps to JavaScript `undefined`.
pub fn respond(
  api: ExtensionApi,
  event: String,
  handler: fn(Event, Context) -> Promise(Option(Dynamic)),
) -> Nil {
  do_respond(api, event, fn(raw, context) {
    handler(Event(type_: event, raw: raw), context)
    |> promise.map(fn(result) {
      case result {
        Some(value) -> value
        None -> undefined_value()
      }
    })
  })
}

/// Handle a result-bearing event through a Gleam dynamic decoder.
pub fn respond_decoded(
  api: ExtensionApi,
  event: String,
  decoder: Decoder(value),
  handler: fn(value, Context) -> Promise(Option(Dynamic)),
) -> Nil {
  do_respond(api, event, fn(raw, context) {
    case decode.run(raw, decoder) {
      Ok(value) ->
        handler(value, context)
        |> promise.map(fn(result) {
          case result {
            Some(value) -> value
            None -> undefined_value()
          }
        })
      Error(errors) ->
        reject("Could not decode Pi event: " <> string.inspect(errors))
    }
  })
}

pub fn on_session_start(
  api: ExtensionApi,
  handler: fn(SessionStart, Context) -> Promise(Nil),
) -> Nil {
  observe_decoded(api, session_start, session_start_decoder(), handler)
}

pub fn on_session_shutdown(
  api: ExtensionApi,
  handler: fn(SessionShutdown, Context) -> Promise(Nil),
) -> Nil {
  observe_decoded(api, session_shutdown, session_shutdown_decoder(), handler)
}

pub fn on_tool_call(
  api: ExtensionApi,
  handler: fn(ToolCall, Context) -> Promise(Option(Dynamic)),
) -> Nil {
  respond_decoded(api, tool_call, tool_call_decoder(), handler)
}

pub fn on_input(
  api: ExtensionApi,
  handler: fn(Input, Context) -> Promise(Option(Dynamic)),
) -> Nil {
  respond_decoded(api, input, input_decoder(), handler)
}

pub fn on_turn_start(
  api: ExtensionApi,
  handler: fn(TurnStart, Context) -> Promise(Nil),
) -> Nil {
  observe_decoded(api, turn_start, turn_start_decoder(), handler)
}

pub fn on_after_provider_response(
  api: ExtensionApi,
  handler: fn(ProviderResponse, Context) -> Promise(Nil),
) -> Nil {
  observe_decoded(
    api,
    after_provider_response,
    provider_response_decoder(),
    handler,
  )
}

pub fn on_tool_execution_start(
  api: ExtensionApi,
  handler: fn(ToolExecution, Context) -> Promise(Nil),
) -> Nil {
  observe_decoded(api, tool_execution_start, tool_execution_decoder(), handler)
}

@external(javascript, "./event_ffi.mjs", "project_trust_result")
fn do_project_trust_result(trusted: String, remember: Bool) -> Dynamic

pub fn project_trust_result(trusted: String, remember: Bool) -> Dynamic {
  do_project_trust_result(trusted, remember)
}

@external(javascript, "./event_ffi.mjs", "resource_paths")
fn resource_paths_arrays(
  skills: array.Array(String),
  prompts: array.Array(String),
  themes: array.Array(String),
) -> Dynamic

pub fn resource_paths(
  skills: List(String),
  prompts: List(String),
  themes: List(String),
) -> Dynamic {
  resource_paths_arrays(
    array.from_list(skills),
    array.from_list(prompts),
    array.from_list(themes),
  )
}

@external(javascript, "./event_ffi.mjs", "cancel")
pub fn cancel() -> Dynamic

@external(javascript, "./event_ffi.mjs", "block_tool")
pub fn block_tool(reason: String) -> Dynamic

@external(javascript, "./event_ffi.mjs", "continue_input")
pub fn continue_input() -> Dynamic

@external(javascript, "./event_ffi.mjs", "transform_input")
pub fn transform_input(text: String) -> Dynamic

@external(javascript, "./event_ffi.mjs", "handled_input")
pub fn handled_input() -> Dynamic

@external(javascript, "./event_ffi.mjs", "system_prompt")
pub fn system_prompt(value: String) -> Dynamic

@external(javascript, "./event_ffi.mjs", "replace_payload")
pub fn replace_payload(value: Dynamic) -> Dynamic

@external(javascript, "./event_ffi.mjs", "replace_messages")
fn replace_messages_array(messages: array.Array(Dynamic)) -> Dynamic

pub fn replace_messages(messages: List(Dynamic)) -> Dynamic {
  messages |> array.from_list |> replace_messages_array
}

@external(javascript, "./event_ffi.mjs", "event_signal")
pub fn signal(raw: Dynamic) -> AbortSignal

fn session_start_decoder() -> Decoder(SessionStart) {
  use reason <- decode.field("reason", decode.string)
  use previous_session_file <- decode.optional_field(
    "previousSessionFile",
    None,
    decode.map(decode.string, Some),
  )
  use raw <- decode.then(decode.dynamic)
  decode.success(SessionStart(reason:, previous_session_file:, raw:))
}

fn session_shutdown_decoder() -> Decoder(SessionShutdown) {
  use reason <- decode.field("reason", decode.string)
  use target_session_file <- decode.optional_field(
    "targetSessionFile",
    None,
    decode.map(decode.string, Some),
  )
  use raw <- decode.then(decode.dynamic)
  decode.success(SessionShutdown(reason:, target_session_file:, raw:))
}

fn tool_call_decoder() -> Decoder(ToolCall) {
  use tool_call_id <- decode.field("toolCallId", decode.string)
  use tool_name <- decode.field("toolName", decode.string)
  use input <- decode.field("input", decode.dynamic)
  use raw <- decode.then(decode.dynamic)
  decode.success(ToolCall(tool_call_id:, tool_name:, input:, raw:))
}

fn input_decoder() -> Decoder(Input) {
  use text <- decode.field("text", decode.string)
  use source <- decode.field("source", decode.string)
  use streaming_behavior <- decode.optional_field(
    "streamingBehavior",
    None,
    decode.map(decode.string, Some),
  )
  use images <- decode.optional_field(
    "images",
    [],
    decode.list(of: decode.dynamic),
  )
  use raw <- decode.then(decode.dynamic)
  decode.success(Input(text:, source:, streaming_behavior:, images:, raw:))
}

fn turn_start_decoder() -> Decoder(TurnStart) {
  use index <- decode.field("turnIndex", decode.int)
  use timestamp <- decode.field("timestamp", decode.int)
  use raw <- decode.then(decode.dynamic)
  decode.success(TurnStart(index:, timestamp:, raw:))
}

fn provider_response_decoder() -> Decoder(ProviderResponse) {
  use status <- decode.field("status", decode.int)
  use headers <- decode.field("headers", decode.dynamic)
  use raw <- decode.then(decode.dynamic)
  decode.success(ProviderResponse(status:, headers:, raw:))
}

fn tool_execution_decoder() -> Decoder(ToolExecution) {
  use tool_call_id <- decode.field("toolCallId", decode.string)
  use tool_name <- decode.field("toolName", decode.string)
  use args <- decode.field("args", decode.dynamic)
  use raw <- decode.then(decode.dynamic)
  decode.success(ToolExecution(tool_call_id:, tool_name:, args:, raw:))
}
