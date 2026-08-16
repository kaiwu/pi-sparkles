# DSH-dedicated plugins — roadmap

DSH runs in a browser web app (React, `dsh-client-web-react`), not a terminal
TUI. Two Pi ledger plugins are therefore Pi-specific and excluded from the DSH
bundle (`dsh/bundle.json`):

- `finance_track_status` — owns Pi's TUI statusline (excluded; the DSH bundle
  currently ships 134 plugins).
- `finance_charts` — renders terminal/ASCII charts.

Their DSH-native counterparts are planned here. Each has a **server half**
(Cordis plugin, bundled by `dsh:bundle` and listed under `extra_dsh`) and a
**client half** (browser React component, loaded by the DSH web app — a
separate packaging lane, not the current `dsh:bundle`).

## Confirmed DSH extension points

- **Content blocks** (`@deepseek-ai/dsh-llm` `ContentBlockMap`) are
  merge-extensible: a plugin can declare a new block type (e.g. `finance-chart`)
  and a tool's `render(args, value)` can return it alongside `text`.
- **Tool presentation**: `defineTool`'s `output.presentationMeta` carries
  structured data persisted with the session log; `presentResult` returns a
  `ToolResultView` (`card`-tagged) for the browser.
- **Browser UI slots** (`@deepseek-ai/dsh-client-ui-slots` `SlotMap`) are
  merge-extensible: a client plugin registers a React component into a slot
  (`ctx.slots.register(...)`, e.g. the tool-owned `tool.call.toolview` slot or
  a layout header/status slot). This is how browser-native rendering plugs in.
- Server tools/commands register through `ctx.tools` / `ctx.commands` (already
  used by the DSH adapter in this repo).

## Plugin 1 — `dsh_track_status` (statusline counterpart)

Reproduce the active-finance-track state, DSH-natively: a persistent track
badge in the browser instead of a terminal statusline.

### Server half (Cordis plugin, `extra_dsh`)

- Session-scoped track state `cn | hk | us` (default `us`), overridable by the
  bundle `config.flags.finance-track` and `PI_SPARKLES_FLAG_FINANCE_TRACK`.
- Tools: `finance_track_status` (read active track + currency/timezone
  defaults + coverage) and `finance_track_switch` (switch, with the same "never
  relabels observations/substitutes providers" law as the Pi original).
- Commands: `/finance-track`, `/cn-track`, `/hk-track`, `/us-track` via
  `ctx.commands`.
- Publishes a `finance/track-changed` session event and a session-scoped store
  seat (the slot store family) so the client badge can subscribe.

### Client half (browser plugin)

- Registers a React component into the app layout header/status slot (exact
  `SlotMap` key confirmed at implementation), rendering a `CN`/`HK`/`US` badge
  that subscribes to the track store. No terminal writes.

## Plugin 2 — `dsh_finance_charts` (browser diagram/plot)

Replace Pi's ASCII charts with browser-native SVG charts for validated series.

### Server half (Gleam functional core + DSH shell)

- Pure `chart_spec` module (no Pi/DSH imports): validated series → a chart
  spec (`kind: line | candles | area | bars`, one metric/unit/period class,
  axes, markers, annotations). Reuses `finance_series`/`finance_ohlcv` and the
  existing "unique points, one metric/unit/tag, reject duplicates" laws.
- Tools `finance_chart_line`, `finance_chart_candles` (or one `finance_chart`
  with a `kind` enum). Input preconditions: exact series, unique sorted points,
  no interpolation/coercion.
- Output: a `text` content block (model-visible summary + numeric rows) plus a
  `finance-chart` content block (declared via `ContentBlockMap` augmentation)
  carrying the spec; `output.presentationMeta` persists the spec for replay.

### Client half (browser plugin)

- Registers a React renderer for the `finance-chart` content block: SVG
  candlestick/line/area with tooltip + zoom, reusing `dsh-client-ui-primitives`.
  Interactive where a terminal chart can only be static text.

## Packaging boundary (important)

- The **server halves** are normal DSH-dedicated packages: added to
  `plugins/<name>/` and listed in `dsh/bundle.json` → `extra_dsh`; `bun run
  dsh:bundle` compiles them exactly like the Pi plugins today.
- The **client halves** are browser assets, not part of the `dsh.bundle.patch`
  server bundle. They need a separate lane: either a companion client plugin
  package loaded by the DSH web app's client-module loader, or a small
  `dsh:client:bundle` task. This lane does not exist yet and is the first
  implementation prerequisite for either plugin's browser half.

## Proposed order

1. Add the client-packaging lane (confirm how a client plugin is loaded by the
   DSH web app and produce a buildable client bundle).
2. `dsh_track_status` server half (track state + tools/commands) — usable
   headlessly even before the badge exists.
3. `dsh_track_status` client badge (statusline counterpart).
4. `dsh_finance_charts` server half (chart-spec core + tools + content block).
5. `dsh_finance_charts` client renderer (SVG charts).

Each step is independently buildable and testable (pure laws for the server
cores, fixture-driven for the client renderers); none is a tier or ledger
change.
