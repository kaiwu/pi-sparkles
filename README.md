# pi-sparkles

Gleam plugins for the Pi coding agent, compiled with Gleam and bundled for Pi
with Bun.

See [ROADMAP.md](ROADMAP.md) for the proposed finance and stock-market plugin
family, [TRACK_GUIDE.md](TRACK_GUIDE.md) for adding another isolated market
track, and [FUNCTIONAL_DESIGN.md](FUNCTIONAL_DESIGN.md) for the mandatory
functional-core/effect-shell architecture.

## Status

This approach is feasible and the first end-to-end implementation works. The
repository currently contains:

- `pi_gleam`, a common Gleam binding for Pi's extension API;
- twenty-nine Experimental finance packages, including two provider adapters,
  shared track/evidence/rules/document/accounting policy, and isolated CN/HK
  identity, calendar, rules, document, and accounting layers;
- the first F0 finance plugins: `finance_setup`, `finance_track_status`,
  `cn_setup`, `hk_setup`, `finance_guardrails`, and `finance_symbols`;
- the first F1 research slices: `sec_edgar`, `sec_xbrl`, and
  `stock_fundamentals`, backed by the read-only `finance_sec` adapter;
- `hello`, a reference command and typed tool;
- `safety_gate`, a reference result-bearing event handler with asynchronous UI;
- `lifecycle`, a reference for typed state restoration and safe cleanup;
- Bun-driven checking, testing, bundling, artifact tests, and Pi load tests.

The implementation was developed against Pi `0.83.0` at commit `305c014dc`,
Gleam `1.18.0`, and Bun `1.3.14`. The reference and F0 plugins build to
standalone ESM artifacts and load with Pi `0.83.0` without model credentials.
`finance_symbols` uses OpenFIGI v3 only when one of its tools is executed.
`finance_track_status` keeps the active `cn`/`hk`/`us` navigation context visible
with currency, timezone, and an explicit non-secret agent contact, and restores
track choices from the active session branch.
`cn_setup` and `hk_setup` expose separately named capability/provider-health
surfaces with exact track contexts. They report the new pure market foundations
as Experimental while keeping identity data, authoritative calendars/rules,
quotes, disclosures, and accounting providers visibly blocked on source and
licence decisions; sibling or SEC tools cannot satisfy those capabilities.
`sec_edgar` likewise performs no request until invoked and requires an SEC
fair-access contact in `SEC_USER_AGENT_CONTACT`; `sec_xbrl` shares that contract
and preserves SEC numeric source lexemes rather than converting through binary
floats. `stock_fundamentals` adds inspectable exact-period mappings, explicit
filing policies, strict source-retaining Q4 derivation, and comparable direct-fact
trends while keeping alternate/amended facts ambiguous. Its first exact
`finance_math` compositions add free cash flow, net margin, and diluted EPS only
after proving all inputs share one period and filing context. Exact growth and
direct-quarter TTM additionally prove explicit calendar gaps and contiguous
coverage; an independently sourced annual-plus-YTD bridge covers TTM when four
direct quarters are unavailable. A typed `DirectQuarter | DerivedQuarter`
composition expands every derived Q4 back to its annual/YTD source leaves.

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

Live SEC compatibility is an explicit, non-CI lane. It builds and invokes the
real `sec_edgar`, `sec_xbrl`, and `stock_fundamentals` bundles without an LLM,
allows only bounded HTTPS GETs to SEC hosts, and requires a real caller contact:

```sh
SEC_USER_AGENT_CONTACT="you@your-real-domain.com" bun run test:live:sec
```

The runner makes at most ten sequential attempts, refuses redirects, and emits
a JSON compatibility report. It is intentionally excluded from `bun run test`;
deterministic unit and binding tests never contact public providers.

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
├── pi_gleam/                     shared Gleam binding package
│   ├── src/pi.gleam
│   ├── src/pi/
│   │   ├── context.gleam
│   │   ├── event.gleam
│   │   ├── event_bus.gleam
│   │   ├── raw.gleam
│   │   ├── schema.gleam
│   │   ├── session.gleam
│   │   ├── tool.gleam
│   │   └── ui.gleam
│   └── test/
├── finance/                      reusable non-Pi Gleam libraries
│   ├── finance_calendar/
│   ├── finance_cn_calendar/
│   ├── finance_cn_accounting/
│   ├── finance_cn_documents/
│   ├── finance_cn_identity/
│   ├── finance_cn_rules/
│   ├── finance_cn_testkit/
│   ├── finance_core/
│   ├── finance_document_attachment/
│   ├── finance_evidence/
│   ├── finance_hk_accounting/
│   ├── finance_hk_calendar/
│   ├── finance_hk_documents/
│   ├── finance_hk_identity/
│   ├── finance_hk_rules/
│   ├── finance_hk_testkit/
│   ├── finance_http/
│   ├── finance_listing/
│   ├── finance_market_accounting/
│   ├── finance_market_authorities/
│   ├── finance_market_calendar/
│   ├── finance_market_documents/
│   ├── finance_market_rules/
│   ├── finance_math/
│   ├── finance_openfigi/
│   ├── finance_provenance/
│   ├── finance_sec/
│   ├── finance_series/
│   ├── finance_table/
│   ├── finance_testkit/
│   ├── finance_track/
│   └── finance_track_capabilities/
├── plugins/
│   ├── cn_setup/                 isolated mainland capability preflight
│   ├── hk_setup/                 isolated Hong Kong capability preflight
│   ├── finance_setup/            capability/configuration preflight
│   ├── finance_track_status/     visible cn/hk/us state and switching
│   ├── finance_guardrails/       evidence and freshness policy
│   ├── finance_symbols/          OpenFIGI v3 identity resolution
│   ├── sec_edgar/                SEC company and recent filing metadata
│   ├── sec_xbrl/                 exact SEC XBRL concept and fact evidence
│   ├── stock_fundamentals/       audited direct-fact normalization
│   ├── hello/                    command and typed-tool example
│   ├── lifecycle/                state restoration/lifecycle example
│   └── safety_gate/              typed event/async-UI example
├── scripts/                      Bun task drivers
├── test/
│   ├── binding/                  FFI contract tests
│   └── artifacts/                bundled-extension tests
├── package.json                  private root task runner
└── dist/                         generated, gitignored Pi artifacts
```

The root is not a Gleam package. The root-level `pi_gleam/` binding and every
package below `finance/` and `plugins/` own a `gleam.toml`, version, README,
source, and tests, so each can be versioned and released independently. Finance
libraries are checked and unit-tested by the root tasks but are not Pi bundles.

## Finance foundations

The finance directory is a reusable Gleam substrate, not a collection of Pi
extensions. Plugins compose these packages behind typed Pi boundaries:

| Package | Role |
| --- | --- |
| `finance_core` | Exact decimals, money, identifiers, instruments, sources, time, and the canonical `Observation(a)` envelope. |
| `finance_track` | Closed `cn`/`hk`/`us` market identity plus validated, versioned result context and explicit cross-track legs. |
| `finance_evidence` | Typed observation/evidence compatibility for units, quality, time ordering, licences, and same/cross-track composition. |
| `finance_listing` | Track/MIC-scoped listing keys plus effective aliases and evidence-backed relationships. |
| `finance_cn_identity` / `finance_hk_identity` | Isolated code, venue, board, ambiguity, alias, and A/H identity laws without provider fallback. |
| `finance_market_calendar` | Source/licence/version-labelled calendar datasets that fail outside declared coverage. |
| `finance_market_authorities` | Track-scoped official roles and links with access and redistribution kept separate from ownership. |
| `finance_cn_calendar` / `finance_hk_calendar` | Track-specific calendar constructors over the shared engine; authoritative data remains injected. |
| `finance_market_rules` | Source-labelled effective rule validation and strict unknown/conflict selection without market constants. |
| `finance_cn_rules` / `finance_hk_rules` | Track-owned security/status/board/share-class rule vocabulary over injected source-reviewed tables. |
| `finance_market_documents` | Track/issuer-scoped original documents, correction/version/translation lineage, attachment identities, and strict versioned lossless JSON. |
| `finance_document_attachment` | Fail-closed media/size/page/redirect/hash/cancellation acceptance with archives and OCR explicitly unsupported. |
| `finance_cn_documents` / `finance_hk_documents` | Isolated disclosure classes and source-language policy retaining exact Unicode originals. |
| `finance_market_accounting` | Exact reported lexemes/scales, statement context, executable mappings, duplicate-preserving resolution, and strict string-numeric JSON. |
| `finance_cn_accounting` / `finance_hk_accounting` | Track-owned standard/report vocabularies with strict source-document issuer coherence. |
| `finance_track_capabilities` | Pure track-prefixed setup and provider-health policy that rejects sibling-tool substitution. |
| `finance_provenance` | Evidence identities, assumptions, licences, manifests, canonical encoding, hashing, redaction, and verification plans. |
| `finance_http` | Safe requests, bounded fetch transport, cancellation, retry/`Retry-After`, rate limits, pooling, scheduling, caching, and cassettes. |
| `finance_math` | Composable exact formula trees plus explicit approximate statistics, regression, risk, cash-flow, and fixed-income policies. |
| `finance_openfigi` | OpenFIGI v3 access, mapping/search plans, pagination, decoding, authenticated/anonymous rate profiles, and a bounded shared runtime. |
| `finance_sec` | Identified read-only SEC access, normalized CIKs, bounded EDGAR request plans, typed submissions/XBRL facts, lossless numeric lexemes, explicit filing/period resolution, strict Q4/trend derivation, and conservative shared pacing. |
| `finance_series` | Ordered observations, alignment, as-of joins, returns, windows, resampling, portfolio paths, and analytics. |
| `finance_calendar` | Dates, market calendars, business-day rules, schedules, joint calendars, and day-count conventions. |
| `finance_table` | Typed tables with validated cells and deterministic Markdown, CSV, and JSON rendering. |
| `finance_testkit` | Seeded fixtures, scripted clocks/transports, cassette helpers, generators, scenarios, and redaction assertions. |
| `finance_cn_testkit` / `finance_hk_testkit` | Isolated seed-stable market scenarios composing each track's identity, calendar, rules, documents, and accounting laws. |

Dependencies point inward: core imports no finance package; track and other
provider-neutral packages build on core where needed; series composes core and math;
testkit supports core and HTTP; OpenFIGI and SEC compose core/HTTP as needed.
None imports Pi.
Pure calculation and policy can therefore run in any Gleam program and in tests
without Pi, networking, filesystem access, ambient time, or secrets.

Finance plugins preserve source, as-of/retrieval time when known, freshness,
units, adjustment basis, quality, and entitlement through to tool results.
Unknown metadata stays unknown. Provider adapters interpret `finance_http`
instead of adding another fetch/retry/cache stack, and metrics compose
`finance_math` and `finance_series` instead of hiding arithmetic in an effect
shell.

The first F0 plugin batch demonstrates this direction:

- `finance_setup` validates defaults and reports only capabilities it can prove;
- `finance_track_status` visibly marks and explicitly switches the active
  `cn`/`hk`/`us` navigation context without relabelling market evidence;
- `cn_setup` and `hk_setup` provide isolated readiness reports and refuse to
  treat sibling/SEC tools or unapproved providers as available;
- `finance_guardrails` composes evidence checks and accumulates typed issues;
- `finance_symbols` consumes `finance_openfigi`, then applies a small pure policy
  returning `NoMatch`, `Unique`, or `Ambiguous` instead of guessing.
- `sec_edgar` consumes `finance_sec`, then applies pure deterministic company
  ranking and filing selection before its Pi shell renders source-labelled
  results.
- `sec_xbrl` composes the same adapter with pure concept discovery and explicit
  unit/form fact selection; it preserves raw periods, accessions, amendments,
  frames, and duplicates instead of prematurely naming metrics.
- `stock_fundamentals` exposes a seven-metric executable registry and resolves
  exact or calendar-classified statement periods under explicit filing policies
  to `NoMatch`, `Unique`, or `Ambiguous`; its Q4 and trend tools then consume
  only unique, proven-compatible sources and retain every accession. Its metric
  tool exposes exact formula trees and source graphs for free cash flow, net
  margin, diluted EPS, growth, and direct-quarter TTM.
  The TTM bridge retains its annual, current-YTD, and prior-YTD source graph and
  permits independent exact-accession selection.
  General multi-input metrics likewise accept a named accession per input, but
  still reject combinations whose resolved facts do not share one filing context.

All foundation interfaces are Experimental. Local path dependencies are
intentional during monorepo development; published packages must use Hex
version constraints.

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
| `pi/session` | read-only metadata and decoder-backed persisted custom-state restoration |
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

- the complete session lifecycle: start, metadata, switch, fork, compaction,
  tree navigation, and shutdown;
- tool call decisions;
- input decisions;
- turn start;
- provider responses;
- tool execution start.

`None` from a result-bearing handler becomes JavaScript `undefined`; builders
such as `block_tool`, `transform_input`, and `replace_messages` produce the
plain JavaScript shapes Pi expects.

See [the binding README](pi_gleam/README.md) and the three reference
plugins for authoring examples.

## Plugin project contract

Each plugin should:

- be an ordinary, independent Gleam project targeting JavaScript;
- use Bun as the JavaScript runtime;
- keep its root module as a thin Pi effect shell and reusable logic below a
  package namespace;
- decode external values once, then express policy, calculation, and workflow
  state as pure functions over immutable Gleam types;
- return typed decisions/effects as data when workflows benefit from replay,
  composition, or audit, and interpret them only at the shell;
- inject clocks, transports, storage, randomness, and entitlements explicitly;
- export `extension` with the promise-returning signature above;
- use `pi_gleam` as a normal Hex version dependency when published;
- keep policies, transformations, and state machines testable without Pi, Bun,
  network access, filesystem access, or real time;
- document its commands, tools, events, state, permissions, and supported Pi
  versions;
- publish source and FFI, excluding `build/`, `dist/`, and caches.

During development the reference plugins use a local path dependency on
`../../pi_gleam`. Gleam correctly refuses to publish such a package.
After the binding receives its first Hex release, plugin release manifests must
replace that path with a normal version constraint. A staging builder will make
that switch testable without forcing local development through Hex.

## Bun tasks

Commands implemented now:

| Command | Purpose |
| --- | --- |
| `bun run check` | formatting and warnings-as-errors builds for every package |
| `bun run build [-- name]` | build and bundle every plugin or one plugin |
| `bun run test:unit [-- name]` | Gleam tests with Bun for the binding, finance libraries, and plugins |
| `bun run test:architecture` | enforce functional-core/effect-shell import and FFI boundaries |
| `bun run test:ffi` | build and run JavaScript binding contracts |
| `bun run test:artifacts` | build and inspect the generated extension modules |
| `bun run test:pi [-- name]` | load artifacts in Pi without invoking a model |
| `bun run test:live:sec` | run opt-in bounded compatibility checks against live read-only SEC APIs |
| `bun run test` | complete repository verification |
| `bun run clean` | remove generated build, work, and distribution output |

Planned release commands are `build:hex`, `hex:check`, and `hex:publish`.
Publishing will always remain an explicit operation; ordinary builds and tests
must never alter Hex or other external state.

## Test strategy

The repository uses five layers:

1. Pure Gleam tests run on the JavaScript target with Bun.
2. Architecture tests reject Pi/Promise imports in plugin domain modules,
   Pi imports in finance libraries, and misplaced plugin FFI.
3. Bun FFI tests invoke bundled plugins with strict fake Pi objects and verify
   callbacks, schemas, event results, asynchronous decisions, and failures.
4. Artifact tests ensure every bundle has a callable default export and a Pi
   directory manifest.
5. Pi smoke tests ask the real loader to initialize each extension using
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
| 2. Events and lifecycle | Complete | Typed lifecycle records/results, decoded custom-state restoration, idempotent cleanup guidance, and replacement/compaction/tree fixtures. |
| 3. Hex round trip | Planned | Finalize the binding name, add tarball audits/staging, release binding first, and rebuild an exact plugin Hex version in a clean directory. |
| 4. Typed breadth | Planned | Type resource discovery, message content, model/provider configuration, full compaction payloads, renderers, and advanced TUI in response to real plugin needs. |
| 5. Release automation | Planned | CI matrix, compatibility table, checksums, and documented release/retirement process. |

Phase 3 comes next. Phase 2 now proves cleanup and reconstruction across
`/reload`, `/new`, `/resume`, and `/fork`, rejects malformed persisted state,
and contract-tests typed replacement, compaction, and tree-navigation shapes.

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
