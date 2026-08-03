import gleam/dynamic/decode
import gleam/javascript/promise.{type Promise}
import gleam/option.{None, Some}
import pi
import pi/context
import pi/event
import pi/ui
import pi_sparkles_safety_gate/check

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  event.on_tool_call(api, fn(call, ctx) {
    case call.tool_name, command(call.input) {
      "bash", Ok(command) ->
        case check.is_dangerous(command) {
          True -> decide(command, ctx)
          False -> promise.resolve(None)
        }
      _, _ -> promise.resolve(None)
    }
  })

  promise.resolve(Nil)
}

fn decide(command: String, ctx: pi.Context) {
  case context.has_ui(ctx) {
    False ->
      event.block_tool("Dangerous command blocked because no UI is available")
      |> Some
      |> promise.resolve
    True -> {
      use allowed <- promise.await(ui.confirm(
        context.ui(ctx),
        "Dangerous command",
        "Allow this command?\n\n" <> command,
      ))
      case allowed {
        True -> promise.resolve(None)
        False ->
          event.block_tool("Dangerous command rejected by the user")
          |> Some
          |> promise.resolve
      }
    }
  }
}

fn command(input: decode.Dynamic) -> Result(String, List(decode.DecodeError)) {
  input
  |> decode.run(decode.at(["command"], decode.string))
}
