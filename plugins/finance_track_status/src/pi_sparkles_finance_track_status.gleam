import finance_core/currency
import finance_core/time
import finance_track
import finance_track/context as track_context
import finance_track/json as track_json
import finance_track/profile
import gleam/dynamic/decode
import gleam/javascript/promise.{type Promise}
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import pi
import pi/context
import pi/event
import pi/event_bus
import pi/raw
import pi/schema
import pi/session
import pi/tool
import pi/ui
import pi_sparkles_finance_track_status/effect/store
import pi_sparkles_finance_track_status/state

const state_entry_type = "pi_sparkles_finance_track_status.active_track"

const status_key = "finance-track"

pub type StatusInput {
  StatusInput
}

pub type SwitchInput {
  SwitchInput(track: finance_track.Track)
}

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  pi.register_string_flag(
    api,
    "finance-track",
    "Initial active finance track: cn, hk, or us",
    "us",
  )
  pi.register_string_flag(
    api,
    "finance-agent-contact",
    "Non-secret agent contact label shown in finance track status",
    "unconfigured",
  )

  let runtime = store.new(state.new(configured_track(api)))

  event.on_session_start(api, fn(_start, ctx) {
    restore(api, runtime, ctx)
    promise.resolve(Nil)
  })
  event.on_session_shutdown(api, fn(_shutdown, ctx) {
    case context.has_ui(ctx) {
      True -> ui.clear_status(context.ui(ctx), status_key)
      False -> Nil
    }
    promise.resolve(Nil)
  })

  pi.register_command(
    api,
    "finance-track",
    "Show or switch the active finance track: cn, hk, or us",
    fn(args, ctx) {
      case string.trim(args) {
        "" -> show_command(api, runtime, ctx)
        value ->
          case finance_track.from_name(value) {
            Ok(track) -> switch_command(api, runtime, track, ctx)
            Error(_) ->
              notify(
                ctx,
                "Unknown finance track '" <> value <> "'; use cn, hk, or us",
                ui.Error,
              )
          }
      }
      promise.resolve(Nil)
    },
  )
  register_direct_command(api, runtime, finance_track.Cn, "cn-track")
  register_direct_command(api, runtime, finance_track.Hk, "hk-track")
  register_direct_command(api, runtime, finance_track.Us, "us-track")

  tool.register(
    api,
    "finance_track_status",
    "Finance track status",
    "Read the active cn, hk, or us navigation track with currency, timezone, and non-secret agent contact",
    "Check the active finance track before choosing a market-specific tool",
    tool.parameters(schema.object([]), decode.success(StatusInput)),
    tool.Parallel,
    fn(_id, _input, _signal, _updates, ctx) {
      let value = current_profile(api, runtime)
      refresh_status(ctx, value.0)
      tool.text_result(profile.describe(value.0), details(value.0, value.1))
      |> promise.resolve
    },
  )

  tool.register(
    api,
    "finance_track_switch",
    "Switch finance track",
    "Explicitly switch the active navigation track; this never relabels observations, tools, providers, or persisted market state",
    "Switch to exactly one of the cn, hk, or us finance tracks",
    tool.parameters(
      schema.object([
        schema.Required("track", schema.string_enum(["cn", "hk", "us"])),
      ]),
      switch_decoder(),
    ),
    tool.Sequential,
    fn(_id, input, _signal, _updates, ctx) {
      switch_track(api, runtime, input.track, ctx, persist: True)
      let value = current_profile(api, runtime)
      tool.text_result(profile.describe(value.0), details(value.0, value.1))
      |> promise.resolve
    },
  )

  promise.resolve(Nil)
}

fn register_direct_command(
  api: pi.ExtensionApi,
  runtime: store.Store(state.State),
  track: finance_track.Track,
  name: String,
) -> Nil {
  pi.register_command(
    api,
    name,
    "Switch the active finance track to " <> finance_track.label(track),
    fn(_args, ctx) {
      switch_command(api, runtime, track, ctx)
      promise.resolve(Nil)
    },
  )
}

fn show_command(
  api: pi.ExtensionApi,
  runtime: store.Store(state.State),
  ctx: pi.CommandContext,
) -> Nil {
  let value = current_profile(api, runtime)
  refresh_status(ctx, value.0)
  notify(ctx, profile.describe(value.0), notification(value.1))
}

fn switch_command(
  api: pi.ExtensionApi,
  runtime: store.Store(state.State),
  track: finance_track.Track,
  ctx: pi.CommandContext,
) -> Nil {
  switch_track(api, runtime, track, ctx, persist: True)
  let value = current_profile(api, runtime)
  notify(ctx, profile.describe(value.0), notification(value.1))
}

fn switch_track(
  api: pi.ExtensionApi,
  runtime: store.Store(state.State),
  track: finance_track.Track,
  ctx: pi.Context,
  persist persist: Bool,
) -> Nil {
  let #(next, transition) = state.switch(store.read(runtime), to: track)
  store.write(runtime, next)
  case transition, persist {
    state.Switched(_, _), True -> {
      pi.append_entry(
        api,
        state_entry_type,
        raw.dynamic(finance_track.name(track)),
      )
      publish(api, track)
    }
    state.Switched(_, _), False -> publish(api, track)
    state.Unchanged(_), False -> publish(api, track)
    _, _ -> Nil
  }
  let value = current_profile(api, runtime)
  refresh_status(ctx, value.0)
}

fn publish(api: pi.ExtensionApi, track: finance_track.Track) -> Nil {
  event_bus.emit(
    pi.events(api),
    finance_track.changed_channel,
    raw.dynamic(finance_track.name(track)),
  )
}

fn restore(
  api: pi.ExtensionApi,
  runtime: store.Store(state.State),
  ctx: pi.Context,
) -> Nil {
  case
    session.latest_custom_entry(
      session.manager(ctx),
      state_entry_type,
      decode.string,
    )
  {
    Ok(Some(entry)) ->
      case entry.data {
        Some(name) ->
          case finance_track.from_name(name) {
            Ok(track) -> switch_track(api, runtime, track, ctx, persist: False)
            Error(_) -> restore_warning(api, runtime, ctx)
          }
        _ -> restore_warning(api, runtime, ctx)
      }
    Ok(_) -> {
      let track = configured_track(api)
      switch_track(api, runtime, track, ctx, persist: False)
    }
    Error(_) -> restore_warning(api, runtime, ctx)
  }
}

fn restore_warning(
  api: pi.ExtensionApi,
  runtime: store.Store(state.State),
  ctx: pi.Context,
) -> Nil {
  let track = configured_track(api)
  switch_track(api, runtime, track, ctx, persist: False)
  notify(
    ctx,
    "Finance track state could not be restored; using configured "
      <> finance_track.name(track)
      <> " track",
    ui.Warning,
  )
}

fn current_profile(
  api: pi.ExtensionApi,
  runtime: store.Store(state.State),
) -> #(profile.Profile, Bool) {
  let track = runtime |> store.read |> state.active_track
  case profile.defaults(track, configured_contact(api)) {
    Ok(value) -> #(value, True)
    Error(_) -> {
      let assert Ok(value) = profile.defaults(track, "invalid-contact")
      #(value, False)
    }
  }
}

fn configured_track(api: pi.ExtensionApi) -> finance_track.Track {
  case pi.get_flag(api, "finance-track") {
    Some(pi.StringFlag(value)) ->
      case finance_track.from_name(value) {
        Ok(track) -> track
        Error(_) -> finance_track.Us
      }
    _ -> finance_track.Us
  }
}

fn configured_contact(api: pi.ExtensionApi) -> String {
  case pi.get_flag(api, "finance-agent-contact") {
    Some(pi.StringFlag(value)) -> value
    _ -> "unconfigured"
  }
}

fn refresh_status(ctx: pi.Context, value: profile.Profile) -> Nil {
  case context.has_ui(ctx) {
    True ->
      ui.set_status(context.ui(ctx), status_key, profile.status_line(value))
    False -> Nil
  }
}

fn notify(ctx: pi.Context, message: String, kind: ui.Notification) -> Nil {
  case context.has_ui(ctx) {
    True -> ui.notify(context.ui(ctx), message, kind)
    False -> Nil
  }
}

fn notification(configuration_valid: Bool) -> ui.Notification {
  case configuration_valid {
    True -> ui.Info
    False -> ui.Warning
  }
}

fn details(value: profile.Profile, configuration_valid: Bool) -> json.Json {
  let context = result_context(value)
  json.object(
    list.append(track_json.result_fields(context), [
      #("currency", json.string(currency.code(profile.currency(value)))),
      #("timezone", json.string(time.timezone_name(profile.timezone(value)))),
      #("agentContact", json.string(profile.agent_contact(value))),
      #("statusLine", json.string(profile.status_line(value))),
      #("configurationValid", json.bool(configuration_valid)),
      #("persistence", json.string("session_branch")),
    ]),
  )
}

fn result_context(value: profile.Profile) -> track_context.Context {
  let track = profile.track(value)
  let assert Ok(context) =
    track_context.new(
      track: track,
      market_scope: finance_track.name(track) <> "_active_track",
      venue_mic: None,
      board: None,
      timezone: Some(profile.timezone(value)),
      source_language: source_language(track),
      providers: ["pi-sparkles track status"],
      entitlement: "configuration_only",
      limitations: [
        "navigation_context_only",
        "does_not_relabel_market_data",
      ],
    )
  context
}

fn source_language(track: finance_track.Track) -> String {
  case track {
    finance_track.Cn -> "zh-CN"
    finance_track.Hk -> "zh-HK"
    finance_track.Us -> "en-US"
  }
}

fn switch_decoder() -> decode.Decoder(SwitchInput) {
  use name <- decode.field("track", decode.string)
  case finance_track.from_name(name) {
    Ok(track) -> decode.success(SwitchInput(track))
    Error(_) ->
      decode.failure(SwitchInput(finance_track.Us), "cn, hk, or us track")
  }
}
