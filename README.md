# pi-sparkles

Gleam plugins for the Pi coding agent, compiled with Gleam and bundled for Pi
with Bun.

See [ROADMAP.md](ROADMAP.md) for the proposed finance and stock-market plugin
family.

## Status

This approach is feasible and the first end-to-end implementation works. The
repository currently contains:

- `pi_gleam`, a common Gleam binding for Pi's extension API;
- `hello`, a reference command and typed tool;
- `safety_gate`, a reference result-bearing event handler with asynchronous UI;
- Bun-driven checking, testing, bundling, artifact tests, and Pi load tests.

The implementation was developed against Pi `0.83.0` at commit `305c014dc`,
Gleam `1.18.0`, and Bun `1.3.14`. Both reference plugins build to standalone
ESM artifacts and load with Pi `0.83.0` without model credentials.

The binding is an initial `0.1.0` implementation, not a published Hex package.
Its typed surface covers normal plugin authoring, while `pi/raw` makes the
entire JavaScript API reachable when a typed wrapper is not available yet.

## The Hex model

Hex distributes the Gleam **source**, not a directly loadable Pi plugin. A Hex
release contains the plugin's Gleam modules, JavaScript FFI, metadata, and
documentation. A consumer must compile that package and bundle its named
Gleam export into a Pi extension:

```text
Hex package or local source
        |
        | gleam build --target javascript
        v
Gleam-generated ESM with named `extension` export
        |
        | generated adapter + Bun.build()
        v
dist/<plugin>/index.js + package.json
        |
        | pi -e dist/<plugin>
        v
Pi
```

Pi never loads the Hex package directly. Publishing a prebuilt npm package is
not required. Prebuilt bundles could later be attached to releases, but that is
separate from the Hex source package.

## Try it

Requirements: Gleam, Bun, and either a hydrated Pi source checkout or an
installed `pi` executable.

```sh
bun run check
bun run test
bun run build
pi --no-extensions -e ./dist/hello --list-models
```

Build or test one plugin by its directory or Gleam package name:

```sh
bun run build -- hello
bun run test:unit -- safety_gate
bun run test:pi -- pi_sparkles_hello
```

`test:pi` uses `PI_SOURCE_DIR` when that checkout has its dependencies. It
defaults to `/home/kaiwu/Documents/github/pi-mono` in this workspace and falls
back to the installed Pi when the source checkout is not hydrated.

## Pi extension contract

Pi expects the default export of an extension module to be a factory receiving
an `ExtensionAPI`. Gleam emits named ES module exports, so every plugin exposes:

```gleam
pub fn extension(api: pi.ExtensionApi) -> Promise(Nil)
```

The Bun builder generates a tiny adapter that imports this named function and
exports it as the module default. It emits:

```text
dist/<name>/
├── index.js
├── index.js.map
├── package.json       declares pi.extensions = ["./index.js"]
├── build.json         source and compatibility metadata
└── metafile.json      Bun bundle graph for auditing
```

Pi can load either `index.js` or the directory. The bundle includes the plugin,
the binding, and Gleam dependencies. Pi host modules are kept external through
an explicit allowlist.

Pi extensions run with the user's full permissions. A built plugin is trusted
code, not a sandbox.

## Repository layout

```text
pi-sparkles/
├── bindings/
│   └── pi_gleam/                 independent Gleam package
│       ├── src/pi.gleam
│       ├── src/pi/
│       │   ├── context.gleam
│       │   ├── event.gleam
│       │   ├── event_bus.gleam
│       │   ├── raw.gleam
│       │   ├── schema.gleam
│       │   ├── tool.gleam
│       │   └── ui.gleam
│       └── test/
├── plugins/
│   ├── hello/                    command and typed-tool example
│   └── safety_gate/              typed event/async-UI example
├── scripts/                      Bun task drivers
├── test/
│   ├── binding/                  FFI contract tests
│   └── artifacts/                bundled-extension tests
├── package.json                  private root task runner
└── dist/                         generated, gitignored Pi artifacts
```

The root is not a Gleam package. Every directory below `bindings/` and
`plugins/` owns its `gleam.toml`, version, README, source, and tests, so it can
be versioned and released independently.

## Common binding

`pi_gleam` translates Pi's object-oriented, callback-heavy JavaScript API into
Gleam values and functions. Runtime-owned values such as `ExtensionApi`,
`Context`, `Ui`, and `AbortSignal` are opaque. Values crossing untrusted FFI
boundaries are dynamically decoded where a typed API is offered.

| Module | Implemented surface |
| --- | --- |
| `pi` | commands, shortcuts, flags, queued messages, session metadata, labels, active tools, models, providers, event bus, and process execution |
| `pi/context` | mode, cwd, UI/trust/idle/abort state, prompt/context usage, scoped models, compaction, shutdown, and command-session navigation |
| `pi/event` | every current event name, generic decoded handlers, typed core events, and Pi-compatible result builders |
| `pi/event_bus` | emit, subscribe, and unsubscribe |
| `pi/schema` | JSON Schema construction, objects, enums, arrays, unions, constraints, and raw schemas |
| `pi/tool` | schema-plus-decoder parameters, typed execution, text/image results, updates, cancellation, and rejected failures |
| `pi/ui` | notifications, prompts, status, widgets, editor text, themes, and tool expansion |
| `pi/raw` | object access/calls and raw event, tool, renderer, and markdown registration |

The binding does not falsely claim that every Pi value has a bespoke Gleam
record. It provides complete API **reachability** through `pi/raw` and typed
coverage for the core authoring path. More surfaces will move behind typed,
tested wrappers as real plugins exercise them.

### Typed tool boundary

Pi validates a tool's JSON Schema. The binding additionally pairs that schema
with a Gleam dynamic decoder:

```text
Parameters(a) = Pi JSON Schema + Dynamic decoder for a
```

Raw arguments are decoded before the typed callback runs. Decode failures
become rejected promises, so malformed JavaScript values cannot masquerade as
typed Gleam data. String enums use the flat `{ type: "string", enum: [...] }`
shape required by Pi's Google-provider compatibility guidance.

### Events

`pi/event` exports constants for every event present in Pi `0.83.0`, generic
`observe`, `respond`, `observe_decoded`, and `respond_decoded` functions, plus
typed helpers for the first high-value events:

- session start and shutdown;
- tool call decisions;
- input decisions;
- turn start;
- provider responses;
- tool execution start.

`None` from a result-bearing handler becomes JavaScript `undefined`; builders
such as `block_tool`, `transform_input`, and `replace_messages` produce the
plain JavaScript shapes Pi expects.

See [the binding README](bindings/pi_gleam/README.md) and the two reference
plugins for authoring examples.

## Plugin project contract

Each plugin should:

- be an ordinary, independent Gleam project targeting JavaScript;
- use Bun as the JavaScript runtime;
- keep its root module as a thin Pi adapter and reusable logic below a package
  namespace;
- export `extension` with the promise-returning signature above;
- use `pi_gleam` as a normal Hex version dependency when published;
- keep policies, transformations, and state machines testable without Pi;
- document its commands, tools, events, state, permissions, and supported Pi
  versions;
- publish source and FFI, excluding `build/`, `dist/`, and caches.

During development the reference plugins use a local path dependency on
`../../bindings/pi_gleam`. Gleam correctly refuses to publish such a package.
After the binding receives its first Hex release, plugin release manifests must
replace that path with a normal version constraint. A staging builder will make
that switch testable without forcing local development through Hex.

## Bun tasks

Commands implemented now:

| Command | Purpose |
| --- | --- |
| `bun run check` | formatting and warnings-as-errors builds for every package |
| `bun run build [-- name]` | build and bundle every plugin or one plugin |
| `bun run test:unit [-- name]` | Gleam tests with Bun |
| `bun run test:ffi` | build and run JavaScript binding contracts |
| `bun run test:artifacts` | build and inspect the generated extension modules |
| `bun run test:pi [-- name]` | load artifacts in Pi without invoking a model |
| `bun run test` | complete repository verification |
| `bun run clean` | remove generated build, work, and distribution output |

Planned release commands are `build:hex`, `hex:check`, and `hex:publish`.
Publishing will always remain an explicit operation; ordinary builds and tests
must never alter Hex or other external state.

## Test strategy

The repository uses four layers:

1. Pure Gleam tests run on the JavaScript target with Bun.
2. Bun FFI tests invoke bundled plugins with strict fake Pi objects and verify
   callbacks, schemas, event results, asynchronous decisions, and failures.
3. Artifact tests ensure every bundle has a callable default export and a Pi
   directory manifest.
4. Pi smoke tests ask the real loader to initialize each extension using
   `--list-models`, which needs no provider credentials.

Before a release, the matrix should also cover a hydrated Pi source runtime,
the published Node runtime, and a compiled Pi Bun binary when available.

## Hex release design

The binding and plugins have independent versions. The release order is:

1. release `pi_gleam` when a plugin needs a new binding API;
2. replace local plugin dependencies with a compatible Hex version range;
3. export and audit each plugin's Hex tarball;
4. install the exact released source into a clean temporary build project;
5. compile and bundle it with Bun;
6. load that artifact in Pi.

`gleam export hex-tarball` already succeeds for `pi_gleam`, proving that the
binding's Gleam and FFI sources form a Hex package. The plugin Hex round trip is
intentionally gated on publishing/finalizing the binding name; the current
local dependency is not publishable and is not presented as if it were.

The future `hex:check` command must reject path/git production dependencies and
generated files, audit package metadata and contents, and perform the clean
source-to-Pi-artifact round trip. `hex:publish` should run the same gates before
performing the explicit external publish action.

## Implementation plan

| Phase | State | Deliverable / acceptance |
| --- | --- | --- |
| 0. End-to-end spike | Complete | Gleam command plugin bundles through Bun and loads in Pi. |
| 1. Core binding | Complete | Typed schemas/tools, decode-before-execute behavior, errors, cancellation, updates, and FFI tests. |
| 2. Events and lifecycle | In progress | Core typed events and `safety_gate` work; remaining work is typed state restoration/cleanup documentation and broader lifecycle fixtures. |
| 3. Hex round trip | Planned | Finalize the binding name, add tarball audits/staging, release binding first, and rebuild an exact plugin Hex version in a clean directory. |
| 4. Typed breadth | Planned | Type resource discovery, compaction/state, message content, model/provider configuration, renderers, and advanced TUI in response to real plugin needs. |
| 5. Release automation | Planned | CI matrix, compatibility table, checksums, and documented release/retirement process. |

Phase 2 completion comes next. It should add lifecycle tests showing safe
cleanup and reconstruction across `/reload`, `/new`, `/resume`, and `/fork`,
then turn the remaining commonly used raw shapes into typed records.

Phase 3 acceptance is the definitive distribution proof: on a clean machine
with Gleam, Bun, Pi, and the builder, fetch a plugin's source by exact Hex
version, produce `dist/<name>/index.js`, and load it without npm.

## Risks and mitigations

| Risk | Mitigation |
| --- | --- |
| Pi's extension API changes | Record the tested Pi version and run boundary tests against configured Pi checkouts. |
| FFI annotations are unsound | Decode external data and contract-test both directions of each typed boundary. |
| Gleam values leak into Pi | Construct all public event/tool results as plain JavaScript objects in FFI. |
| Hex contains no ready-to-run artifact | State the source-only model explicitly and test the Hex-to-bundle path. |
| Local path dependencies block release | Use them only for development; stage version-based manifests for release checks. |
| Bundle duplicates Pi internals | Keep a reviewed host-module allowlist and audit Bun metafiles. |
| UI is unavailable outside TUI mode | Expose `mode` and `has_ui`; require explicit non-UI behavior for interactive plugins. |
| Resources survive reload or session changes | Drive setup/cleanup from lifecycle events and make shutdown idempotent. |

## Decisions before the first release

- Confirm that the global Hex name `pi_gleam` is available and acceptable.
- Select the initial supported Pi version window beyond the tested `0.83.0`.
- Decide whether the Hex consumer builder remains in this repository or becomes
  a separately released Bun tool.
- Choose the first non-reference plugins that will drive additional typed API
  coverage.

These decisions do not block local Gleam plugin authoring or further binding
work. They do block claiming that a reference plugin is already publishable by
an exact final Hex name.

## Study references

Pi sources inspected at commit `305c014dc`:

- `packages/coding-agent/docs/extensions.md`
- `packages/coding-agent/docs/packages.md`
- `packages/coding-agent/src/core/extensions/types.ts`
- `packages/coding-agent/src/core/extensions/loader.ts`
- `packages/coding-agent/src/core/extensions/runner.ts`
- `packages/coding-agent/examples/extensions/`

`nginz-njs` sources inspected at commit `b8a97b9`:

- `README.md` and `CLAUDE.md`
- `scripts/build.js` and `scripts/test.js`
- `modules/*/gleam.toml`
- the downloaded `ngs` Gleam and JavaScript FFI sources

External documentation:

- [Gleam externals guide](https://gleam.run/documentation/externals/)
- [Gleam command-line reference](https://gleam.run/command-line-reference/)
- [Bun bundler](https://bun.sh/docs/bundler)
- [Bun test runner](https://bun.sh/docs/test)
