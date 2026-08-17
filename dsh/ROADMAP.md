# DSH-dedicated plugins — roadmap

DSH runs in a browser web app and one process may host several agents. The DSH
lane therefore separates global-safe Pi shells, per-agent shared-core
counterparts, and genuinely DSH-only host surfaces.

## Implemented counterparts

All four formerly missing ledger components are now present in the DSH T6
inventory without entering the global Pi-shell lane:

- `finance_track_status` mounts its existing compiled Gleam state, readiness,
  tools, commands, persistence, and routing-prompt core once per DSH agent.
  Pi `setStatus` writes a whole-value `pi-sparkles/status` session event;
  `finance_track_overlay` folds it into the `piSparklesStatus` projection.
- The package browser half declares `dsh.client` and registers the
  `pi-sparkles-finance-track` component in DSH's root `shell.overlay` slot.
  It reads only the current session summary projection and renders no ambient
  process state.
- `watchlist`, `swing_workbench`, and `portfolio` each receive a new compiled
  extension instance in `agent.ctx`. Their existing Gleam/domain cores remain
  the single functional implementation; only ownership of the effect shell
  changes.
- DSH does not navigate a Pi-style branch tree inside one live session.
  Session-tree hooks are accepted but never synthetically fired; fresh and
  resumed agents restore from their own append-only session logs during the
  real `agent/session-start` lifecycle.

The bundle manifest records the separation explicitly:

- `exclude_pi`: shells forbidden at process-global DSH scope;
- `scoped_pi`: excluded ledger shells re-instantiated per agent;
- `extra_dsh`: DSH-native Cordis surfaces under `dsh/plugins/`.

The real-runtime lane creates two installed-DSH agent scopes, checks the 244
effective tools, commands and shared routing prompt, switches the track through
the DSH command runtime, reads the overlay projection, and proves a watchlist
mutation in one agent leaves the other at revision zero. The installed DSH web
server also discovers and serves the package browser entry after
`@deepseek-ai/dsh-client-ui-layout`.

This completes the counterpart implementation, but does not by itself promote
the independent DSH release gate. `dsh_release.status` remains `preview` until
the DSH role-level acceptance lane is declared complete.

## Remaining DSH-only opportunity — browser finance charts

`finance_charts` remains included as text plus structured details; its inline
Pi PNG is deliberately not projected as a DSH image attachment. A later
DSH-native chart surface can add:

### Server half

- A pure `chart_spec` constructor over validated series (`line`, `candles`,
  `area`, or `bars`) with exact metric/unit/period, axes and annotations.
- A DSH content-block or presentation-metadata projection that retains the
  existing model-visible text and numeric rows.
- No interpolation, implicit provider acquisition, duplicate-period coercion,
  or plugin-to-plugin source imports.

### Client half

- A renderer registered through DSH's client slot/content presentation seams.
- Browser-native SVG interaction while preserving replay from content-bound
  session data.

This feature belongs only in the DSH lane unless a host-neutral chart spec is
first factored into a pure finance package. It is not a missing product-tier
component and must not weaken the existing Pi distribution.
