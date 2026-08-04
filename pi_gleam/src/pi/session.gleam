import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode.{type DecodeError, type Decoder}
import gleam/option.{type Option, None, Some}
import gleam/result
import pi.{type Context, type SessionManager}

/// Common metadata shared by every persisted Pi session entry.
///
/// The complete host-owned entry remains available as `raw`. Plugins should
/// decode entry-specific fields only when they need them.
pub type Entry {
  Entry(
    type_: String,
    id: String,
    parent_id: Option(String),
    timestamp: String,
    raw: Dynamic,
  )
}

/// A typed extension-owned custom entry.
///
/// `data` is `None` when the entry was appended without a payload.
pub type CustomEntry(value) {
  CustomEntry(
    id: String,
    parent_id: Option(String),
    timestamp: String,
    custom_type: String,
    data: Option(value),
    raw: Dynamic,
  )
}

/// Access the read-only session manager for this callback context.
///
/// Do not retain this value across session replacement or reload. Resolve it
/// again from the fresh context supplied to `session_start` or another handler.
@external(javascript, "./session_ffi.mjs", "manager")
pub fn manager(context: Context) -> SessionManager

@external(javascript, "./session_ffi.mjs", "cwd")
pub fn cwd(manager: SessionManager) -> String

@external(javascript, "./session_ffi.mjs", "directory")
pub fn directory(manager: SessionManager) -> String

@external(javascript, "./session_ffi.mjs", "id")
pub fn id(manager: SessionManager) -> String

@external(javascript, "./session_ffi.mjs", "file")
fn file_value(manager: SessionManager) -> Dynamic

pub fn file(
  manager: SessionManager,
) -> Result(Option(String), List(DecodeError)) {
  manager
  |> file_value
  |> decode.run(decode.optional(decode.string))
}

@external(javascript, "./session_ffi.mjs", "leaf_id")
fn leaf_id_value(manager: SessionManager) -> Dynamic

pub fn leaf_id(
  manager: SessionManager,
) -> Result(Option(String), List(DecodeError)) {
  manager
  |> leaf_id_value
  |> decode.run(decode.optional(decode.string))
}

@external(javascript, "./session_ffi.mjs", "entries")
fn entries_value(manager: SessionManager) -> Dynamic

/// Decode all entries in the session, including entries outside the active
/// branch.
pub fn entries(
  manager: SessionManager,
) -> Result(List(Entry), List(DecodeError)) {
  manager
  |> entries_value
  |> decode.run(decode.list(of: entry_decoder()))
}

@external(javascript, "./session_ffi.mjs", "branch")
fn branch_value(manager: SessionManager) -> Dynamic

/// Decode the entries on the active root-to-leaf branch.
pub fn branch(
  manager: SessionManager,
) -> Result(List(Entry), List(DecodeError)) {
  manager
  |> branch_value
  |> decode.run(decode.list(of: entry_decoder()))
}

@external(javascript, "./session_ffi.mjs", "context_entries")
fn context_entries_value(manager: SessionManager) -> Dynamic

/// Decode the active branch after Pi's compaction rules have been applied.
pub fn context_entries(
  manager: SessionManager,
) -> Result(List(Entry), List(DecodeError)) {
  manager
  |> context_entries_value
  |> decode.run(decode.list(of: entry_decoder()))
}

@external(javascript, "./session_ffi.mjs", "custom_entries")
fn custom_entries_value(manager: SessionManager, custom_type: String) -> Dynamic

/// Decode extension-owned entries with the requested custom type on the active
/// root-to-leaf branch.
///
/// Entries are returned in branch order. A malformed matching entry
/// fails the whole result so corrupted state cannot be silently ignored.
pub fn custom_entries(
  manager: SessionManager,
  custom_type: String,
  data_decoder: Decoder(value),
) -> Result(List(CustomEntry(value)), List(DecodeError)) {
  manager
  |> custom_entries_value(custom_type)
  |> decode.run(decode.list(of: custom_entry_decoder(data_decoder)))
}

@external(javascript, "./session_ffi.mjs", "all_custom_entries")
fn all_custom_entries_value(
  manager: SessionManager,
  custom_type: String,
) -> Dynamic

/// Decode matching extension-owned entries across the complete session tree.
///
/// Prefer `custom_entries` for state restoration. This all-entries view is for
/// auditing or migrations that intentionally inspect inactive branches.
pub fn all_custom_entries(
  manager: SessionManager,
  custom_type: String,
  data_decoder: Decoder(value),
) -> Result(List(CustomEntry(value)), List(DecodeError)) {
  manager
  |> all_custom_entries_value(custom_type)
  |> decode.run(decode.list(of: custom_entry_decoder(data_decoder)))
}

/// Return the most recent matching custom entry on the active branch.
pub fn latest_custom_entry(
  manager: SessionManager,
  custom_type: String,
  data_decoder: Decoder(value),
) -> Result(Option(CustomEntry(value)), List(DecodeError)) {
  use decoded <- result.try(custom_entries(manager, custom_type, data_decoder))
  Ok(last(decoded))
}

pub fn entry_decoder() -> Decoder(Entry) {
  use type_ <- decode.field("type", decode.string)
  use id <- decode.field("id", decode.string)
  use parent_id <- decode.field("parentId", decode.optional(decode.string))
  use timestamp <- decode.field("timestamp", decode.string)
  use raw <- decode.then(decode.dynamic)
  decode.success(Entry(type_:, id:, parent_id:, timestamp:, raw:))
}

fn custom_entry_decoder(
  data_decoder: Decoder(value),
) -> Decoder(CustomEntry(value)) {
  use id <- decode.field("id", decode.string)
  use parent_id <- decode.field("parentId", decode.optional(decode.string))
  use timestamp <- decode.field("timestamp", decode.string)
  use custom_type <- decode.field("customType", decode.string)
  use data <- decode.optional_field(
    "data",
    None,
    decode.map(data_decoder, Some),
  )
  use raw <- decode.then(decode.dynamic)
  decode.success(CustomEntry(
    id:,
    parent_id:,
    timestamp:,
    custom_type:,
    data:,
    raw:,
  ))
}

fn last(values: List(value)) -> Option(value) {
  case values {
    [] -> None
    [value] -> Some(value)
    [_, ..rest] -> last(rest)
  }
}
