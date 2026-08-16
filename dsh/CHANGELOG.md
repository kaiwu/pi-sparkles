# Changelog — @dsh-sparkles/dsh-sparkles

All notable changes to the `@dsh-sparkles/dsh-sparkles` npm package. Versions
follow Semantic Versioning. The exact tier, plugin inventory, maturity, and
content hashes remain authoritative in each tarball's `dsh-lock.json` and
`release-lock.json`.

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
