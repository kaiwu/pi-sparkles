# Changelog — @dsh-sparkles/dsh-sparkles

All notable changes to the `@dsh-sparkles/dsh-sparkles` npm package. Versions
follow Semantic Versioning. The exact tier, plugin inventory, maturity, and
content hashes remain authoritative in each tarball's `dsh-lock.json` and
`release-lock.json`.

## Unreleased

- Make the finance-track overlay draggable and keyboard-movable, with bounded
  placement and an explicit reset gesture.
- Register Sparkles' required custom/status event vocabulary before DSH cold
  session loading so rc.6 can resume persisted scoped state.
- Add DSH runtime-date and bounded-history guidance, and clarify the one-based
  stock-technicals projection and basis-field rules after auditing a real
  failed-call trajectory.
- Preserve Pi length, value, and item-count bounds as model-visible constraint
  annotations when translating through DSH's narrower tool-schema subset.
- Correct DSH tool rendering to return `ContentBlock[]`, forward real call IDs
  and cancellation, and normalize Pi inline images without forging DSH
  attachment references.
- Isolate concurrent invocations and bind queued messages, custom entries, cwd,
  and lifecycle to the exact DSH agent/session.
- Exclude the Pi-global `watchlist`, `swing_workbench`, and `portfolio` shells;
  mount fresh copies of their existing compiled Gleam cores in each DSH agent
  scope, and verify that state cannot cross agents.
- Restore `finance_track_status` as a per-agent shared-core counterpart,
  contribute its exported routing guidance through DSH `systemPrompt`, and map
  its status updates into a session projection.
- Ship a browser client entry that renders finance track status through DSH's
  `shell.overlay` slot; the installed DSH web server discovers and serves it.
- Cover all 135 T1–T6 ledger components in DSH (131 global-safe shells and four
  scoped counterparts), while retaining explicit global-shell exclusions.
- Add an independent blocked-preview release gate, exact rc.6 service peers,
  stronger bundle/client locks and checksums, and real two-agent ToolRuntime,
  command, prompt, projection, and isolation verification.

## 0.1.5 - 2026-08-15

- First DeepSeek Harness distribution of the pi-sparkles T1–T6 ledger: the
  read-only finance evidence tools (quotes, OHLCV, calendars, rules,
  fundamentals, SEC filings, portfolio, quant, macro, and tape review)
  registered as native Harness tools behind one Pi-API compatibility facade.
- Pi-specific surfaces are excluded via `dsh/bundle.json`; the TUI
  statusline/track-navigation plugin is the first exclusion, and the bundle
  ships the ledger minus exclusions plus any future DSH-dedicated plugins.
- Commands registered through `ctx.commands`; `sendUserMessage` output becomes
  the command result text.
- Pi JSON Schema translated to the dsh-tools raw JSON-Schema subset; the
  embedded Pi decoders still enforce the full argument contract at call time.
- `dsh.bundle.patch` manifest for `dsh plugin --profile <name> add`; the
  package is provider-free, credential-free, and order-mutation-free.
