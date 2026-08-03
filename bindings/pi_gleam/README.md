# pi_gleam

Gleam bindings for authoring extensions for the Pi coding agent.

`pi_gleam` targets JavaScript. Plugin logic stays in Gleam while small
JavaScript FFI modules adapt Pi's objects, callbacks, promises, optional values,
and plain result objects.

The package is under initial development, is not published to Hex yet, and is
tested against Pi `0.83.0`. The name is provisional until its Hex availability
is confirmed.

## Minimal extension

```gleam
import gleam/javascript/promise.{type Promise}
import pi
import pi/context
import pi/ui

pub fn extension(api: pi.ExtensionApi) -> Promise(Nil) {
  pi.register_command(api, "hello", "Say hello", fn(_args, ctx) {
    ui.notify(context.ui(ctx), "Hello from Gleam!", ui.Info)
    promise.resolve(Nil)
  })

  promise.resolve(Nil)
}
```

Gleam emits `extension` as a named ES module export. A builder must compile the
package, create a default-export adapter, and bundle it for Pi. The root
`pi-sparkles` builder implements that contract; Hex itself only distributes the
source package.

## Typed tool example

```gleam
import gleam/dynamic/decode
import gleam/javascript/promise
import gleam/json
import pi/schema
import pi/tool

pub type Input {
  Input(name: String)
}

let parameters =
  tool.parameters(
    schema.object([
      schema.Required("name", schema.string()),
    ]),
    {
      use name <- decode.field("name", decode.string)
      decode.success(Input(name:))
    },
  )

tool.register(
  api,
  "hello",
  "Hello",
  "Greet a person",
  "Greet a person by name",
  parameters,
  tool.DefaultExecution,
  fn(_id, input, _signal, _updates, _ctx) {
    tool.text_result("Hello, " <> input.name <> "!", json.null())
    |> promise.resolve
  },
)
```

`Parameters(a)` pairs Pi's runtime JSON Schema with a Gleam decoder. The raw
arguments are decoded before the typed callback runs. Decode failures reject
the JavaScript promise and are reported by Pi as tool failures.

## Modules and coverage

| Module | Public coverage |
| --- | --- |
| `pi` | opaque runtime types; commands; shortcuts; Boolean/string flags; user/custom messages; session name and labels; active tools; raw tool/command discovery; thinking/model/provider methods; event bus; `exec` |
| `pi/context` | mode, cwd, UI access, trust/idle/abort/pending state, shutdown/compact, prompt/context usage, scoped models, wait/new/fork/tree/switch/reload command operations |
| `pi/event` | constants for every Pi 0.83 event; generic and decoder-backed observe/respond registration; typed session start/shutdown, tool call, input, turn start, provider response, and tool-execution-start helpers; event-result builders |
| `pi/event_bus` | extension-to-extension emit, subscribe, and unsubscribe |
| `pi/schema` | primitive, object, record, tuple, array, union, nullable, enum, constraint, metadata, and raw JSON schemas |
| `pi/tool` | schema/decoder parameters; execution modes; text/image content; results; incremental updates; abort checks; rejected failures |
| `pi/ui` | notifications, select/confirm/input, status and working indicators, widgets, editor operations, themes, and expanded-tool state |
| `pi/raw` | dynamic conversion, object construction/access/calls, promise conversion, generic events, raw tools, message/entry renderers, and markdown transformers |

The package promises complete **reachability**, not that every JavaScript shape
is already represented by a dedicated Gleam type. Use typed modules for normal
authoring and `pi/raw` for advanced Pi surfaces while typed coverage evolves.
Raw calls trade compile-time guarantees for immediate access and should be
isolated in a small adapter module with boundary tests.

## Event handling

Use typed helpers when one exists:

```gleam
event.on_tool_call(api, fn(call, ctx) {
  // Return Some(event.block_tool(...)) to block, or None to continue.
})
```

For another event, either supply a decoder with `observe_decoded` or
`respond_decoded`, or use `observe`/`respond` and inspect its raw `Dynamic`
value. Result builders construct Pi's required plain JavaScript shapes. `None`
from a responder becomes JavaScript `undefined`.

## Design rules

- Pi-owned objects are opaque types; plugin-owned data uses normal Gleam types.
- Typed tools and typed events decode external values at runtime.
- `Option` is used for JavaScript optional values where a typed wrapper exists.
- Tool errors become rejected promises rather than successful error-looking
  content.
- Tool and event results are built in FFI so Gleam constructors never leak into
  Pi.
- UI-dependent code must check `context.has_ui` and define non-TUI behavior.
- The raw layer is explicit and remains available across Pi API additions.

## Package and build model

A plugin's publishable `gleam.toml` should eventually use a normal Hex
constraint:

```toml
[dependencies]
pi_gleam = ">= 0.1.0 and < 1.0.0"
```

Local reference plugins currently use a path dependency because `pi_gleam` has
not been published. Gleam will not publish that manifest, by design. The binding
must be released first; then plugins can publish source to Hex and consumers can
build those sources into Pi artifacts with Gleam and Bun.

The package's own `gleam export hex-tarball` succeeds and includes its Gleam and
JavaScript FFI sources. No compiled Pi extension belongs in this Hex package.

## Compatibility policy

The initial code is tested against Pi `0.83.0`. Every typed addition should have
a JavaScript boundary contract test and record the Pi version whose API was
studied. Pi additions remain accessible through `pi/raw`; breaking Pi changes
may require a new binding release.

See `plugins/hello` for command/tool registration and `plugins/safety_gate` for
a typed result-bearing event with asynchronous UI and a non-UI fail-safe.
