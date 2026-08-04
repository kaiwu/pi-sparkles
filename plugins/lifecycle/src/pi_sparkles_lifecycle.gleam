import gleam/dynamic/decode
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import pi
import pi/context
import pi/event
import pi/raw
import pi/session
import pi/ui
import pi_sparkles_lifecycle/policy
import pi_sparkles_lifecycle/state
import pi_sparkles_lifecycle/store

const state_entry_type = "pi_sparkles_lifecycle.counter"

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  let runtime = store.new(state.initial())

  event.on_session_start(api, fn(start, ctx) { restore(runtime, start, ctx) })

  event.on_session_info_changed(api, fn(info, _ctx) {
    let name = case info.name {
      Some(value) -> value
      None -> "none"
    }
    store.update(runtime, state.observe(_, "session_info_changed:" <> name))
    promise.resolve(Nil)
  })

  event.on_session_before_switch(api, fn(switch, _ctx) {
    store.update(runtime, state.observe(
      _,
      "session_before_switch:"
        <> event.session_switch_reason_name(switch.reason),
    ))
    case switch.target_session_file {
      Some(target) ->
        case policy.cancel_switch(target) {
          True ->
            event.cancel()
            |> Some
            |> promise.resolve
          False -> promise.resolve(None)
        }
      _ -> promise.resolve(None)
    }
  })

  event.on_session_before_fork(api, fn(fork, _ctx) {
    store.update(runtime, state.observe(
      _,
      "session_before_fork:" <> event.fork_position_name(fork.position),
    ))
    case policy.skip_fork_restore(fork.entry_id) {
      True ->
        event.skip_conversation_restore()
        |> Some
        |> promise.resolve
      False -> promise.resolve(None)
    }
  })

  event.on_session_before_compact(api, fn(compact, _ctx) {
    store.update(runtime, state.observe(
      _,
      "session_before_compact:" <> event.compaction_reason_name(compact.reason),
    ))
    case compact.custom_instructions {
      Some("reference-custom") ->
        event.custom_compaction(
          "Reference custom summary",
          compact.preparation.first_kept_entry_id,
          compact.preparation.tokens_before,
        )
        |> Some
        |> promise.resolve
      _ -> promise.resolve(None)
    }
  })

  event.on_session_compact(api, fn(compact, _ctx) {
    store.update(runtime, state.observe(
      _,
      "session_compact:" <> event.compaction_reason_name(compact.reason),
    ))
    promise.resolve(Nil)
  })

  event.on_session_before_tree(api, fn(tree, _ctx) {
    store.update(runtime, state.observe(
      _,
      "session_before_tree:" <> tree.preparation.target_id,
    ))
    case tree.preparation.label {
      Some("reference-custom") ->
        event.tree_summary("Reference branch summary")
        |> Some
        |> promise.resolve
      _ -> promise.resolve(None)
    }
  })

  event.on_session_tree(api, fn(tree, _ctx) {
    let leaf = case tree.new_leaf_id {
      Some(value) -> value
      None -> "root"
    }
    store.update(runtime, state.observe(_, "session_tree:" <> leaf))
    promise.resolve(Nil)
  })

  event.on_session_shutdown(api, fn(shutdown, _ctx) {
    store.update(runtime, state.cleanup(
      _,
      event.session_shutdown_reason_name(shutdown.reason),
    ))
    promise.resolve(Nil)
  })

  pi.register_command(
    api,
    "lifecycle",
    "Show restored lifecycle state",
    fn(_args, ctx) {
      notify(ctx, runtime |> store.read |> state.describe)
      promise.resolve(Nil)
    },
  )

  pi.register_command(
    api,
    "lifecycle-bump",
    "Increment and persist lifecycle state",
    fn(_args, ctx) {
      case runtime |> store.read |> state.increment {
        Ok(#(next, value)) -> {
          store.write(runtime, next)
          pi.append_entry(api, state_entry_type, raw.dynamic(value))
          notify(ctx, state.describe(next))
        }
        Error(state.Inactive) ->
          notify(ctx, "Lifecycle state is inactive; mutation was not persisted")
      }
      promise.resolve(Nil)
    },
  )

  pi.register_command(
    api,
    "lifecycle-session",
    "Show decoded read-only session state",
    fn(_args, ctx) {
      notify(ctx, session_description(ctx))
      promise.resolve(Nil)
    },
  )

  promise.resolve(Nil)
}

fn restore(
  runtime: store.Store(state.State),
  start: event.SessionStart,
  ctx: pi.Context,
) -> Promise(Nil) {
  let restored =
    session.latest_custom_entry(
      session.manager(ctx),
      state_entry_type,
      decode.int,
    )

  case restored {
    Ok(Some(entry)) -> {
      store.update(runtime, state.restore(
        _,
        entry.data |> option_value(0),
        event.session_start_reason_name(start.reason),
      ))
      promise.resolve(Nil)
    }
    Ok(None) -> {
      store.update(runtime, state.restore(
        _,
        0,
        event.session_start_reason_name(start.reason),
      ))
      promise.resolve(Nil)
    }
    Error(errors) -> {
      store.update(runtime, state.invalidate(_, string.inspect(errors)))
      case context.has_ui(ctx) {
        True ->
          ui.notify(
            context.ui(ctx),
            "Lifecycle state could not be restored; mutations are disabled",
            ui.Error,
          )
        False -> Nil
      }
      promise.resolve(Nil)
    }
  }
}

fn notify(ctx: pi.CommandContext, message: String) -> Nil {
  case context.has_ui(ctx) {
    True -> ui.notify(context.ui(ctx), message, ui.Info)
    False -> Nil
  }
}

fn session_description(ctx: pi.CommandContext) -> String {
  let manager = session.manager(ctx)
  case
    session.file(manager),
    session.leaf_id(manager),
    session.entries(manager),
    session.branch(manager),
    session.context_entries(manager)
  {
    Ok(file), Ok(leaf), Ok(entries), Ok(branch), Ok(context_entries) ->
      [
        "cwd=" <> session.cwd(manager),
        "dir=" <> session.directory(manager),
        "id=" <> session.id(manager),
        "file=" <> option_value(file, "ephemeral"),
        "leaf=" <> option_value(leaf, "root"),
        "entries=" <> int.to_string(list.length(entries)),
        "branch=" <> int.to_string(list.length(branch)),
        "context=" <> int.to_string(list.length(context_entries)),
      ]
      |> string.join(" ")
    _, _, _, _, _ -> "session state could not be decoded"
  }
}

fn option_value(value: Option(value), default: value) -> value {
  case value {
    Some(value) -> value
    None -> default
  }
}
