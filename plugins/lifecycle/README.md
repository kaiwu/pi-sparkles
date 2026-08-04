# pi_sparkles_lifecycle

Reference Pi extension demonstrating lifecycle-safe persistent state in Gleam.
It is an executable fixture for `pi_gleam` Phase 2 rather than a user-facing
finance plugin.

The extension:

- restores its latest typed custom entry during `session_start`;
- represents lifecycle state and every transition as immutable Gleam values;
- resolves the session manager from each fresh callback context;
- persists counter changes with `pi.append_entry`;
- makes shutdown cleanup idempotent;
- observes every typed session lifecycle event;
- demonstrates cancellation and custom compaction/tree result builders;
- exposes `/lifecycle` and `/lifecycle-bump` for manual inspection.

## Functional architecture

`state.gleam` is the functional core. `initial`, `restore`, `invalidate`,
`observe`, `increment`, and `cleanup` receive immutable state and return a new
state or typed error. They contain no Pi calls, promises, or JavaScript FFI and
are tested as composable transition sequences. Cleanup idempotence and inactive
mutation are properties of that pure model.

Pi invokes event callbacks separately, so the shell needs a reference to the
latest state. `store.gleam` and `store_ffi.mjs` provide the package's only
mutable mechanism: a generic cell with read/write operations. It stores an
immutable Gleam value and contains no lifecycle behavior. The root module reads
the current value, applies a pure transition, and writes the returned value.

This split is intentional: JavaScript mutation solves only callback wiring;
Gleam owns the state machine, invariants, composition, and tests.

## Lifecycle rule

Do not retain a Pi context or session manager across `/reload`, `/new`,
`/resume`, or `/fork`. A successful replacement emits `session_shutdown`, tears
down the old runtime, creates a new extension instance, and supplies a fresh
context to `session_start`. Persist durable state as custom entries and rebuild
only session-scoped in-memory state from the new context.

Cleanup may be requested more than once during error handling or test fixtures,
so it must be idempotent. This example counts a cleanup only when its state was
active.

The package is not published to Hex.
