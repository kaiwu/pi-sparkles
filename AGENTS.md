# Repository Guidelines

## Project Structure & Module Organization

The root is a private Bun task runner, not a Gleam package. The shared Pi binding
lives in `pi_gleam/`. Reusable non-Pi libraries live in `finance/<name>/`, and
loadable extensions live in `plugins/<name>/`. Each package is an independent
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

Use the functional-core/effect-shell rules in `FUNCTIONAL_DESIGN.md`. Domain
modules operate on immutable Gleam values and must not import Pi, promises, or
FFI. Decode at the shell, run pure total transitions, then interpret typed
effects. Pass clocks, transport, storage, randomness, and entitlements as
explicit capabilities. Keep unavoidable mutable cells generic and put no
business logic in JavaScript.

The finance foundations are `finance_core`, `finance_provenance`,
`finance_http`, `finance_math`, `finance_series`, `finance_calendar`,
`finance_table`, and `finance_testkit`. They are Experimental independent Gleam
packages, not Pi plugins. Keep their dependency graph acyclic: core imports no
finance package; provider-neutral packages may build inward on core; series may
compose core, math, and calendar; testkit may support core and HTTP. Finance
packages must never import `pi_gleam`.

Provider adapters such as `finance_openfigi` and `finance_sec` are also independent finance
packages but sit outside the provider-neutral foundation. They may compose core
and HTTP, must keep credentials opaque, and must expose validated request plans,
fixture-tested decoders, explicit pacing/entitlement/licence policy, bounded
execution, cancellation, and pagination budgets without importing Pi.

Use `finance_core.Observation(a)` as the canonical provider-to-plugin envelope.
Preserve source, as-of/retrieval time, freshness, unit, adjustment, quality, and
entitlement rather than flattening them into display strings. Keep unknown facts
unknown. Use math and series for calculations, calendar for market-time
semantics, provenance for evidence graphs, table for rendering, and testkit for
deterministic interpreters. Provider adapters use `finance_http`; do not add
plugin-local fetch, retry, rate-limit, cache, or redaction stacks.

The initial real-plugin batch is `plugins/finance_setup/`,
`plugins/finance_guardrails/`, and `plugins/finance_symbols/`; the first F1
slices are `plugins/sec_edgar/` and `plugins/sec_xbrl/`, and the first normalized
SEC consumer is `plugins/stock_fundamentals/`. Treat these root
modules as Pi/Promise effect shells and keep configuration, policy, decoding,
normalization, and resolution in pure namespaced modules. Provider network code
must have bounded responses, cancellation, rate-limit behavior, fixture-tested
decoding, and source/licence documentation.

SEC XBRL numeric JSON tokens must remain exact source strings until an explicit
decimal/metric layer converts them. Preserve taxonomy, tag, unit, start/end,
accession, fiscal period, form/amendment, filed date, frame, and duplicates.
Company-facts covers only non-custom taxonomy facts applying to the whole
entity; do not present it as complete filing or segment coverage.

Fundamental mappings must be executable data with accepted tags, unit kind,
period kind, and method visible to callers. Statement-period classification uses
inclusive Gregorian durations and exact end dates; do not treat `fy`/`fp` as a
comparative fact's economic period. Alternative tags, amendments, comparative
repetitions, and duplicates remain an explicit identifier resolution. Filing
precedence defaults to preserve-all; latest, original-only, amendment-only, and
exact-accession behavior must be an explicit caller policy.

SEC derivations consume resolved candidates, never raw candidate lists. Q4 may
subtract only additive duration metrics after proving identical metric, exact
unit, taxonomy/tag, fiscal start, and annual/nine-month shapes; retain both
source candidates in the result and prove the residual is quarter-shaped.
Comparable trends require unique points with
one metric, unit, taxonomy/tag, and period class, then sort by exact end date and
reject duplicates. Never interpolate, coerce alternative tags, or choose a
restatement inside a derivation. Keep these laws in pure Gleam modules so
downstream formulas can compose and test them without Pi or HTTP.

Multi-input SEC formulas live in pure plugin domain modules and compose
`finance_math`; do not reimplement decimal arithmetic in the Pi shell. Resolve
every named input independently, require uniqueness, then prove exact period and
filing-context coherence before calculation. Formula results must expose the
expression tree, ordered input names, declared output unit, rounding/scale and
accounting assumptions, plus every complete source candidate. Zero denominators,
wrong units, cross-filing combinations, and unsupported metrics are errors, not
missing values or coercions.
Per-input accession overrides may replace the base filing policy for selection,
but must never bypass the subsequent same-filing proof. Report each effective
source policy alongside its named candidate.

Multi-period formulas consume an already validated comparable trend. Growth
must declare and validate the calendar gap between every adjacent end date;
never label skipped observations quarter-over-quarter or year-over-year. Direct
TTM requires exactly four additive quarter facts with `next.start` equal to the
day after `previous.end`, and the complete span must independently classify as
annual; do not fill gaps, average weighted-share facts, or mix derived quarters
unless a later typed constructor explicitly models that source variant. Retain
both candidates for every growth edge and all four candidates for every TTM sum.

An annual/YTD TTM bridge is `annual + current_ytd - prior_ytd`. Require an
additive metric; identical unit and taxonomy/tag; annual and prior-YTD fiscal
starts to match; current YTD to begin the day after annual end; comparable YTD
classes and a year-over-year end gap; and an annual-shaped resulting window.
Resolve and retain all three sources independently. This bridge does not imply
that derived and directly reported quarter values are interchangeable.

Represent quarter provenance as an explicit `DirectQuarter | DerivedQuarter`
sum type. Any downstream composition must revalidate derived Q4 from its annual
and nine-month candidates, label the variant in output, and expand its formula
to direct source leaves rather than treating the derived decimal as a provider
fact. Mixed-quarter TTM still requires exact continuity, one metric/unit/tag,
and an annual-shaped complete window.

## Build, Test, and Development Commands

- `bun run check`: check formatting and warnings-as-errors builds.
- `bun run build [-- hello]`: bundle all plugins or one named plugin.
- `bun run test:unit [-- hello]`: run Gleam/gleeunit tests using Bun.
- `bun run test:architecture`: enforce functional core/effect shell boundaries.
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
promises, options, failures, and callbacks. Finance libraries need deterministic
unit tests, laws/invariants, transition-sequence tests, and FFI contracts where
applicable. Plugins additionally need artifact and Pi-load smoke tests. Run
`bun run test` before submission.
Provider plugin unit tests use fixtures or scripted transports, never live
network calls, real sleeps, ambient credentials, or mutable shared caches.
The sole live-provider lane is the explicit `bun run test:live:sec` runner. It
must remain opt-in, read-only, caller-identified, host/method allowlisted,
request-budgeted, and excluded from `bun run test`.

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
