# DSH all-in-one plugin (builder + compatibility shell)

This directory is the DeepSeek Harness lane of pi-sparkles. It builds a DSH
Cordis plugin from compatible compiled Pi effect shells without changing the
Pi builder, aggregate, tier ledger, or maturity. Shared finance behavior stays
in the existing pure Gleam/domain modules; only host effects are adapted.

- `scripts/dsh-bundle.js` builds the bundle (`bun run dsh:bundle`).
- `scripts/dsh-npm-package.js` builds the separate npm preview.
- `scripts/dsh-verify.js` validates schemas and executes the generated bundle
  through the installed DSH runtime (`bun run dsh:verify`).
- `dsh/bundle.json` owns DSH release status, Pi-shell exclusions, reasons, and
  future DSH-native entries.
- `dsh/pi-api.mjs` maps the supported Pi effect surface to DSH.
- `dsh/plugins/` is reserved for DSH-native Cordis shells; it is separate from
  Pi `plugins/` and is empty today.

## Inventory and release boundary

The effective inventory is `Pi tier closure − excluded Pi shells + DSH-native
shells`. The current T6 preview contains 131 compatible Pi plugin components.
Four Pi shells are excluded, with normative reasons in `bundle.json`:

- `finance_track_status`: Pi TUI/system-prompt navigation needs a DSH-native
  per-agent surface.
- `swing_workbench` and `watchlist`: their Pi shells use session-tree lifecycle
  and extension-global mutable state.
- `portfolio`: its Pi shell owns one extension-global imported snapshot.

Loading those state shells once at DSH process scope would mix independent
agents. Their pure cores remain available for native, session-scoped DSH shells.
An `extra_dsh` entry resolves only to `dsh/plugins/<name>.mjs`; it can never
silently pull a Pi plugin into the DSH-only lane.

DSH maturity is independent from Pi maturity. `dsh_release.status` is currently
`preview`, so both T5 and T6 npm outputs are private blocked previews even when
the corresponding Pi aggregate is ProductUseful. Promotion requires a DSH role
acceptance lane and completion or explicit product disposition of the excluded
host shells.

## Host mapping

| Pi surface | DSH behavior |
| --- | --- |
| tools | Registered with `ctx.tools`; actual DSH call ID, signal, and agent are forwarded. Pi results are normalized to canonical JSON and `output.render` returns `ContentBlock[]`. |
| commands | Registered with `ctx.commands`; Pi UI notifications become command result text. |
| queued user messages | Routed to the invoking agent's `followup` or `steer` inbox. |
| custom entries/session reads | Stored in and projected from the invoking DSH agent's session log. |
| session lifecycle | Pi start/shutdown hooks follow `agent/session-start` and `agent/disposed`. |
| flags | Defaults may be overridden by bundle `config.flags` or `PI_SPARKLES_FLAG_<NAME>`. |
| unsupported Pi effects | Fail explicitly; they never return placeholder success. |

DSH images are attachment references, while Pi chart images are inline base64
blocks. The bridge therefore retains chart text and structured details but
omits the incompatible Pi image block. A future DSH-native chart shell can mint
host attachments and browser presentation.

Provider HTTP does not depend on a Pi fetch helper. The shared
`finance_http` transport uses standard `globalThis.fetch`, AbortSignal,
redirect rejection, response budgets, and timeouts, which are available in the
pinned Node 22.19+ host. Provider credentials come only from the DSH process
environment. Some adapters initialize at plugin boot, so restart DSH after
changing variables.

## Build and verify

```sh
bun run dsh:bundle
bun run dsh:verify
bun run dsh:npm:preview:verify
dsh plugin --profile <name> add ./dist/dsh/dsh-sparkles
dsh --profile <name> --dump-config
```

`bun test test/dsh test/workflow/dsh_npm_package.test.js` covers the adapter,
parallel invocation isolation, lifecycle/session mapping, image projection,
release gate, locks, and npm inventory. `bun run dsh:verify` uses the installed
DSH rc.6 implementation to validate schemas, mount the generated entrypoint,
and execute `finance_capabilities` through the real ToolRuntime.

The generated package pins its tested DSH service peers to `0.1.0-rc.6`, pins
`pdfjs-dist`, requires Node 22.19+, carries exact locks/checksums, and contains
no lifecycle scripts or credential values.
