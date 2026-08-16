# DSH all-in-one plugin (builder + adapter)

This directory is the DeepSeek Harness half of pi-sparkles. It builds an
all-in-one **Harness plugin** from the compiled Pi plugin artifacts without
touching the Pi builder/bundler (`scripts/build.js`,
`scripts/aggregate-bundle.js`) or the tier ledger.

- `scripts/dsh-bundle.js` — the bundler (`bun run dsh:bundle`).
- `scripts/dsh-npm-package.js` — the parallel npm line (`bun run dsh:npm:pack`).
- `scripts/dsh-verify.js` — validates the schema bridge against the real
  `@deepseek-ai/dsh-tools` implementation (`bun run dsh:verify`).
- `dsh/bundle.json` — the DSH inventory: which Pi ledger proposals are excluded
  and which DSH-dedicated plugins are added.
- `dsh/ROADMAP.md` — the planned DSH-dedicated plugins (browser statusline
  counterpart and finance diagrams/plots).
- `dsh/schema-translate.mjs` — Pi JSON Schema → the raw JSON-Schema subset
  dsh-tools accepts for tool `parameters`/`output`.
- `dsh/pi-api.mjs` — the Pi `ExtensionApi` facade over Harness Cordis services.
- `dsh/plugin.mjs` — the Cordis plugin factory that mounts every included
  extension.

## Inventory: ledger minus Pi-specific plugins plus DSH extras

The DSH distribution is not the raw 135-proposal ledger. `dsh/bundle.json`
declares the difference:

```json
{ "schema_version": 1, "exclude_pi": ["finance_track_status"], "extra_dsh": [] }
```

- `exclude_pi` lists Pi ledger proposals whose surface is Pi-specific (the TUI
  statusline / track-navigation plugin is the first and only entry). They stay
  in the Pi product; the DSH bundle omits them and their commands/tools.
- `extra_dsh` lists future DSH-dedicated plugin packages (new `plugins/<name>/`
  directories) that are added on top of the filtered ledger.

The effective inventory is `ledger − exclude_pi + extra_dsh` (currently 134
plugins). Exclusions and extras are recorded in `dsh-lock.json` and the npm
manifest's `dshSparkles` section, so the packed package is always explicit
about what it ships.

## How it works

Each compiled Pi plugin (`dist/<plugin>/index.js`) is a self-contained ESM
bundle whose default export is `extension(api)`. The `api` argument is the Pi
extension API. Across the included ledger artifacts that surface is small and
bounded: `registerTool`, `registerCommand`, `on`, `appendEntry`,
`getActiveTools`, `registerFlag`, `getFlag`, `sendUserMessage`, and `events`.

`dsh/pi-api.mjs` implements that surface over the Harness:

| Pi API | Harness mapping |
| --- | --- |
| `registerTool({name, description, parameters, execute, ...})` | `ctx.tools.register(...)`; `parameters` translated to the dsh-tools raw JSON-Schema subset, `output` fixed to `{ content, details }` with a text renderer, `execute` bridged `(args, exec) → (toolCallId, input, signal, updates, context)` |
| `registerCommand(name, {description, handler})` | `ctx.commands.register(...)`; the Pi handler runs and its `sendUserMessage` output becomes the DSH `CommandResult` success text |
| `registerFlag` / `getFlag` | registered defaults, overridable by the bundle `config.flags` map and `PI_SPARKLES_FLAG_<NAME>` env vars |
| `on("session_start", ...)` | fired once at plugin apply with `{ reason: "startup" }` |
| `on("session_shutdown", ...)` | fired on context dispose |
| `on("before_agent_start", ...)` | never fired (DSH owns its system prompt) |
| `appendEntry` / session reads | a shared in-memory custom-entry store exposed through the synthetic `context.sessionManager` |
| `events` | a local bus (track-change events stay plugin-local) |
| ui/session/prompt/model surfaces | explicit no-ops (`hasUI: false`) |

The Pi-side decoders embedded in each bundle still enforce the full argument
contract (lengths, ranges, enums) when a tool runs, so dropping unsupported
schema keywords only loosens the model-facing argument schema, never the
runtime validation.

## Build and install

```sh
bun run dsh:bundle                      # T6 (T1–T6), ledger minus exclude_pi
bun run dsh:bundle -- T5                # prior release boundary
bun run dsh:verify                      # schema bridge vs real dsh-tools
bun run dsh:npm:pack                    # content-lock + pack, never publish
dsh plugin --profile <name> add ./dist/dsh/dsh-sparkles
```

Output: `dist/dsh/dsh-sparkles/` — an npm bundle with `dsh.bundle.patch`,
`cordis.patch.yml`, a content lock, `CONFIGURATION.md`, and `SHA256SUMS`.
The entry is a self-contained ~22 MB single file; its only runtime dependency
is `pdfjs-dist` (declared, installed into the profile by pnpm).

## Verification

`bun test test/dsh test/workflow/dsh_npm_package.test.js` runs the mirror unit
and npm workflow tests; `bun run dsh:verify` runs the real dsh-tools validator
over the translator. A real boot (`dsh plugin --profile headless add ... &&
dsh --profile headless`) loads every included extension and registers their
tools, commands, flags, and providers without error; set
`DSH_PI_SPARKLES_DEBUG=1` to trace loading.
