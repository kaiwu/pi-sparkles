import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/javascript/array
import gleam/javascript/promise.{type Promise}
import gleam/option.{type Option, None}
import gleam/result
import pi.{type Ui}

pub type Notification {
  Info
  Warning
  Error
}

pub type WidgetPlacement {
  AboveEditor
  BelowEditor
}

@external(javascript, "./ui_ffi.mjs", "notify")
fn do_notify(ui: Ui, message: String, kind: String) -> Nil

pub fn notify(ui: Ui, message: String, kind: Notification) -> Nil {
  do_notify(ui, message, notification_name(kind))
}

@external(javascript, "./ui_ffi.mjs", "select")
fn select_value(
  ui: Ui,
  title: String,
  options: array.Array(String),
) -> Promise(Dynamic)

pub fn select(
  ui: Ui,
  title: String,
  options: List(String),
) -> Promise(Option(String)) {
  ui
  |> select_value(title, array.from_list(options))
  |> promise.map(fn(value) {
    decode.run(value, decode.optional(decode.string))
    |> result.unwrap(None)
  })
}

@external(javascript, "./ui_ffi.mjs", "confirm")
pub fn confirm(ui: Ui, title: String, message: String) -> Promise(Bool)

@external(javascript, "./ui_ffi.mjs", "input")
fn input_value(ui: Ui, title: String, placeholder: String) -> Promise(Dynamic)

pub fn input(
  ui: Ui,
  title: String,
  placeholder: String,
) -> Promise(Option(String)) {
  ui
  |> input_value(title, placeholder)
  |> promise.map(fn(value) {
    decode.run(value, decode.optional(decode.string))
    |> result.unwrap(None)
  })
}

@external(javascript, "./ui_ffi.mjs", "set_status")
pub fn set_status(ui: Ui, key: String, text: String) -> Nil

@external(javascript, "./ui_ffi.mjs", "clear_status")
pub fn clear_status(ui: Ui, key: String) -> Nil

@external(javascript, "./ui_ffi.mjs", "set_working_message")
pub fn set_working_message(ui: Ui, message: String) -> Nil

@external(javascript, "./ui_ffi.mjs", "clear_working_message")
pub fn clear_working_message(ui: Ui) -> Nil

@external(javascript, "./ui_ffi.mjs", "set_working_visible")
pub fn set_working_visible(ui: Ui, visible: Bool) -> Nil

@external(javascript, "./ui_ffi.mjs", "set_hidden_thinking_label")
pub fn set_hidden_thinking_label(ui: Ui, label: String) -> Nil

@external(javascript, "./ui_ffi.mjs", "clear_hidden_thinking_label")
pub fn clear_hidden_thinking_label(ui: Ui) -> Nil

@external(javascript, "./ui_ffi.mjs", "set_widget")
fn set_widget_array(
  ui: Ui,
  key: String,
  lines: array.Array(String),
  placement: String,
) -> Nil

pub fn set_widget(
  ui: Ui,
  key: String,
  lines: List(String),
  placement: WidgetPlacement,
) -> Nil {
  set_widget_array(ui, key, array.from_list(lines), placement_name(placement))
}

@external(javascript, "./ui_ffi.mjs", "clear_widget")
pub fn clear_widget(ui: Ui, key: String) -> Nil

@external(javascript, "./ui_ffi.mjs", "set_title")
pub fn set_title(ui: Ui, title: String) -> Nil

@external(javascript, "./ui_ffi.mjs", "paste_to_editor")
pub fn paste_to_editor(ui: Ui, text: String) -> Nil

@external(javascript, "./ui_ffi.mjs", "set_editor_text")
pub fn set_editor_text(ui: Ui, text: String) -> Nil

@external(javascript, "./ui_ffi.mjs", "get_editor_text")
pub fn get_editor_text(ui: Ui) -> String

@external(javascript, "./ui_ffi.mjs", "editor")
fn editor_value(ui: Ui, title: String, prefill: String) -> Promise(Dynamic)

pub fn editor(
  ui: Ui,
  title: String,
  prefill: String,
) -> Promise(Option(String)) {
  ui
  |> editor_value(title, prefill)
  |> promise.map(fn(value) {
    decode.run(value, decode.optional(decode.string))
    |> result.unwrap(None)
  })
}

@external(javascript, "./ui_ffi.mjs", "set_theme")
pub fn set_theme(ui: Ui, name: String) -> Dynamic

@external(javascript, "./ui_ffi.mjs", "get_all_themes")
pub fn get_all_themes(ui: Ui) -> array.Array(Dynamic)

@external(javascript, "./ui_ffi.mjs", "get_tools_expanded")
pub fn get_tools_expanded(ui: Ui) -> Bool

@external(javascript, "./ui_ffi.mjs", "set_tools_expanded")
pub fn set_tools_expanded(ui: Ui, expanded: Bool) -> Nil

fn notification_name(notification: Notification) -> String {
  case notification {
    Info -> "info"
    Warning -> "warning"
    Error -> "error"
  }
}

fn placement_name(placement: WidgetPlacement) -> String {
  case placement {
    AboveEditor -> "aboveEditor"
    BelowEditor -> "belowEditor"
  }
}
