# Repository Guidelines

## Project Structure & Module Organization

The root is a private Bun task runner, not a Gleam package. The shared Pi binding
lives in `pi_gleam/`. Each `plugins/<name>/` directory is an independent
Gleam project with its own `gleam.toml`, `src/`, `test/`, and `README.md`.
Orchestration lives in `scripts/`; FFI and bundle tests live in `test/binding/`
and `test/artifacts/`. Generated `build/`, `dist/`, `.work/`, and
`manifest.toml` files are ignored. Keep proposals in `ROADMAP.md`; create plugin
directories only when implementation starts.

## Architecture & Distribution

Plugin root modules export
`extension(api: pi.ExtensionApi) -> Promise(Nil)`. Bun generates Pi's required
default-export adapter and `dist/<plugin>/index.js`. Hex distributes Gleam and
FFI source; users must build it before Pi can load it. Put typed APIs in
`pi_gleam` and isolate unsupported surfaces behind `pi/raw`.

## Build, Test, and Development Commands

- `bun run check`: check formatting and warnings-as-errors builds.
- `bun run build [-- hello]`: bundle all plugins or one named plugin.
- `bun run test:unit [-- hello]`: run Gleam/gleeunit tests using Bun.
- `bun run test:ffi`: run binding contract tests.
- `bun run test:artifacts`: verify bundled extension exports.
- `bun run test:pi [-- hello]`: smoke-load bundles without a model call.
- `bun run test`: run all verification layers.
- `bun run clean`: remove generated outputs.

## Coding Style & Naming Conventions

Run `gleam format`; use snake_case modules and functions. Plugin packages follow
`pi_sparkles_<name>` and directories use the short name, such as
`plugins/safety_gate/`. JavaScript is ESM with two spaces, semicolons, and small
FFI functions. Decode external values at typed boundaries; FFI annotations are
not runtime validation.

## Testing Guidelines

Use gleeunit for pure logic. Name Gleam tests `*_test.gleam` and Bun tests
`*.test.js`. New binding wrappers need Bun contract tests for applicable shapes,
promises, options, failures, and callbacks. Plugins need artifact and Pi-load
smoke tests. Run `bun run test` before submission.

## Commit & Pull Request Guidelines

History has no established convention beyond the initial empty commit. Use
short, imperative subjects such as `Add typed quote schema`, and separate
unrelated changes. Pull requests should explain behavior, packages, provider/API
assumptions, tests, and compatibility impact; link the roadmap item or issue.
Add screenshots only for interactive TUI changes.

## Security & Configuration

Pi extensions execute with full user permissions. Never commit or emit secrets.
Finance plugins must report source, freshness, units, and data entitlement, and
keep read-only, paper, and live-trading capabilities separate.
