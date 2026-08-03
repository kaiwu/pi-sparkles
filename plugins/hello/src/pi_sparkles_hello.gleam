import gleam/dynamic/decode
import gleam/javascript/promise.{type Promise}
import gleam/json
import gleam/string
import pi
import pi/context
import pi/schema
import pi/tool
import pi/ui
import pi_sparkles_hello/greeting

pub type HelloInput {
  HelloInput(name: String)
}

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  pi.register_command(api, "hello", "Greet someone from Gleam", fn(args, ctx) {
    let name = case string.trim(args) {
      "" -> "world"
      value -> value
    }
    ui.notify(context.ui(ctx), greeting.greeting(name), ui.Info)
    promise.resolve(Nil)
  })

  let parameters =
    tool.parameters(
      schema.object([
        schema.Required(
          "name",
          schema.string()
            |> schema.described("Name to greet"),
        ),
      ]),
      hello_input_decoder(),
    )

  tool.register(
    api,
    "hello",
    "Hello",
    "Generate a greeting for a person",
    "Greet a person by name",
    parameters,
    tool.DefaultExecution,
    fn(_tool_call_id, input, _signal, _updates, _ctx) {
      let message = greeting.greeting(input.name)
      let details = json.object([#("greeted", json.string(input.name))])
      tool.text_result(message, details)
      |> promise.resolve
    },
  )

  promise.resolve(Nil)
}

fn hello_input_decoder() -> decode.Decoder(HelloInput) {
  use name <- decode.field("name", decode.string)
  decode.success(HelloInput(name:))
}
