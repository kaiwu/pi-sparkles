# Functional design standard

## Principle

The repository uses Gleam to obtain more than nicer JavaScript types. Plugin
behavior should be expressed as immutable data transformations that compose,
can be tested without Pi, and leave effects at narrow, replaceable boundaries.

Gleam strongly favors immutable functional programming, but its compiler does
not track effects: JavaScript FFI, promises, clocks, random values, process
state, and Pi objects can still make an arbitrary function impure. Purity is
therefore a module-architecture rule that this repository must review and test.

The default shape is:

```text
untrusted Pi/provider value
          │ decode once
          v
typed immutable input ──> pure policy/domain/state transition
                                  │
                                  v
                         typed decision/effects as data
                                  │ interpret
                                  v
                       Pi / HTTP / clock / cache / storage
```

## Functional core, effectful shell

A loadable plugin has three layers:

1. **Boundary adapters** decode Pi/provider values into domain types and encode
   domain outputs into host-compatible values.
2. **Functional core** validates, decides, calculates, and transitions immutable
   state. It imports neither `pi` nor JavaScript FFI.
3. **Effect shell** registers callbacks and interprets typed effects with Pi,
   promises, HTTP, storage, clocks, and the smallest possible FFI modules.

The plugin root module should mostly wire those layers. Reusable finance
libraries are functional cores or explicit effect abstractions; they never
import `pi_gleam`.

Not every feature needs a framework. A stateless rule can remain a plain pure
function. When workflow state or several effects exist, prefer an Elm-style
model:

```gleam
pub type Event {
  SessionStarted(restored: Option(Snapshot))
  QuoteReceived(Result(Quote, QuoteError))
  UserRequestedReport(ReportRequest)
}

pub type Effect {
  FetchQuote(InstrumentId)
  PersistSnapshot(Snapshot)
  NotifyUser(Notification)
}

pub fn update(model: Model, event: Event) -> #(Model, List(Effect))
```

`update` is total and pure. The Pi shell interprets returned effects and feeds
their typed outcomes back as events. A test can therefore exercise an entire
workflow as values without starting Pi or mocking global functions.

## Composition rules

- Prefer small functions over objects with hidden mutable state.
- Represent policies as data plus functions, so policies can be combined,
  mapped, folded, and interpreted independently.
- Pass dependencies explicitly. Time, randomness, HTTP transport, cache,
  storage, environment, and entitlement lookup are capabilities supplied by the
  shell, never read secretly by domain code.
- Prefer returning effects as data when a workflow benefits from inspection,
  batching, replay, or audit. Use injected effectful functions at lower-level
  transport boundaries where an effect algebra would add no value.
- Parse external values once into opaque smart-constructor types. Internal code
  should not repeatedly inspect `Dynamic`, strings, or unvalidated JSON.
- Use algebraic data types to make invalid states unrepresentable. Do not encode
  state machines as loosely related booleans or sentinel strings.
- Keep `Option` for genuine absence and `Result` for expected failure. Do not
  panic for provider errors, invalid user input, inactive workflow state, rate
  limits, or missing entitlements.
- Preserve unknown host/provider enum values with an explicit `Other(String)`
  when forward-compatible observation is safe.
- Use `List.map`, `filter`, `fold`, `result`, and pipelines for declarative
  transformations; avoid mutation-shaped recursion that obscures invariants.
- Make ordering, conflict resolution, aggregation, and truncation deterministic.
  The same typed inputs and configuration must produce the same output.

## State and persistence

Domain state is an immutable Gleam value. A transition receives the previous
state and returns the next state or a typed error. Durable state is encoded as a
versioned snapshot/event and persisted by the shell.

Pi invokes callbacks independently, so a plugin may need one mutable reference
to the latest immutable state. That reference is infrastructure only:

- it is isolated in a generic store module with `read` and `write`;
- no business decision or transition is implemented in its FFI;
- callbacks read once, call a pure transition, then write the returned value;
- session replacement rebuilds the store from decoded persisted state;
- cleanup remains an idempotent pure transition before effects are closed.

Concurrent async operations must not blindly overwrite a newer state. Workflows
carry generation/request IDs and apply results through a pure reducer that can
reject stale completions.

## Effects and capabilities

Effects include Pi calls, UI, promises, HTTP, filesystem/database access,
environment variables, subprocesses, clocks, randomness, logs, and mutable
caches. These belong in named boundary modules.

Capabilities are narrow and task-specific. Prefer `fetch_quote` over handing
domain code an unrestricted HTTP client, and prefer `now` over reading a global
clock. Production and deterministic test interpreters implement the same
contract.

Effect shells must:

- propagate cancellation and timeouts;
- bound concurrency, retries, response sizes, and queued work;
- decode every success and error value before it reaches the core;
- redact secrets before forming errors, logs, cache keys, or evidence;
- return explicit freshness, entitlement, and provenance metadata;
- define non-interactive behavior instead of assuming a TUI;
- avoid module-level mutable singletons.

FFI should translate representation or perform an unavoidable platform effect.
It should not contain finance rules, authorization policy, state transitions,
retry classification, rendering decisions, or data validation that Gleam can
express.

## Testing at the functional level

The test pyramid intentionally favors pure tests:

1. **Examples:** table-driven valid, invalid, boundary, and regression cases.
2. **Laws/invariants:** encode/decode round trips, normalization idempotence,
   stable ordering, state invariants, and algebraic properties where valid.
3. **State-machine sequences:** fold event lists through `update` and assert the
   final model plus ordered effect list, including duplicates and stale results.
4. **Interpreter contracts:** run the same effect plan through deterministic
   clocks, scripted transports, stores, and Pi fakes.
5. **FFI contracts:** test only the narrow JavaScript boundary, including
   malformed values, callbacks, options, promises, cancellation, and failures.
6. **Artifact/Pi smoke tests:** prove wiring and host compatibility, not domain
   correctness already covered by pure tests.

Tests should compare values, not incidental call structure, unless ordering is
part of the contract. Real sleeps, live provider calls, ambient environment,
and shared global fixtures are prohibited in unit tests.

Property-based testing is preferred for decimals, canonical encoders,
identifiers, table round trips, redaction, and state-machine invariants once an
appropriate Gleam library is selected. Until then, deterministic generated
vectors and exhaustive small-domain folds provide the same style of evidence.

## Review gates

A new package or feature is not complete until reviewers can answer yes:

- Can its business behavior run without Pi, Bun FFI, networking, filesystem,
  environment, wall-clock time, or randomness?
- Are all inputs validated into domain types at one boundary?
- Are state transitions visible as pure functions over immutable values?
- Are dependencies/capabilities explicit and replaceable?
- Are effects returned as inspectable data where workflow composition benefits?
- Are expected failures exhaustive typed values rather than throws or magic
  strings?
- Are outputs deterministic for equal inputs and configuration?
- Are laws and multi-step transition sequences tested in addition to examples?
- Is FFI small, mechanical, and covered by boundary contracts?
- Could another Gleam program reuse the core without depending on Pi?

Exceptions must be documented in the package README with the effect involved,
why it cannot be isolated further, and how deterministic tests control it.
