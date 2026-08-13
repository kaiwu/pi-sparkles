# Changelog

All notable changes to the `@pi-sparkles/pi-sparkles` npm package are recorded
here. Versions follow Semantic Versioning. The exact selected tier, plugin
inventory, maturity, and content hashes remain authoritative in each tarball's
`release-lock.json` and `aggregate-lock.json`.

## 0.1.3 - 2026-08-13

- Replace the npm README's internal tier terminology with a user-facing
  introduction, supported market coverage, primary data sources, example
  questions, minimal environment setup, optional provider credentials, track
  selection, and explicit read-only boundaries.

## 0.1.2 - 2026-08-13

- Use `AGENT_CONTACT` as the single caller-owned operator identity across CN,
  HK, US, Eastmoney, CNINFO, SEC, Alpaca, and other provider adapters; remove
  redundant provider-specific contact and user-agent configuration.
- Route ordinary current-data questions such as whether to buy now or when to
  sell through quote, bounded OHLCV/history, and relevant SMA/RSI/ATR evidence
  by default, without requiring users to ask explicitly for tool evidence.
- Avoid unnecessary symbol search and CNINFO discovery when a familiar name or
  exact active-track identity is already sufficient.
- Keep raw vendor OHLCV details compact in the terminal while exposing complete
  numeric rows to the model, and return compact model-visible indicator values
  without a second projection request.
- Derive ordinary indicator instruction references internally, normalize raw
  basis evidence handoffs, accept compatible rounding aliases, and shorten
  validation failures that previously blocked the model.
- Speed up exact SMA/RSI/ATR calculations with BigInt-backed decimal coefficient
  arithmetic and a rolling SMA window; verify CN/HK/US results against an
  independent decimal oracle.
- Make the stable release workflow build and verify the complete T1-through-T5
  all-in-one extension instead of treating individual plugins as release units.

## 0.1.1 - 2026-08-13

- Fix aggregate startup by giving the legacy raw CN Eastmoney quote/history
  tools names distinct from the ProductUseful provider-port tools.
- Rename the backtest reproduction export so it no longer collides with the
  provenance source-manifest export.
- Restore plain-Pi loading of the complete T1-through-T5 npm entrypoint.
- Emit complete bounded CN, HK, and US daily OHLCV rows in model-visible tool
  content, not only in renderer/session details, so agents can construct
  SMA/RSI/ATR inputs while Pi keeps collapsed results to one summary line.
- Clarify that known exact CN codes, including already-identified ETFs, can use
  the raw Eastmoney history path without Tushare or CNINFO configuration.

## 0.1.0 - 2026-08-12

- Add the first single-entry all-in-one Pi extension package.
- Support an explicit T1-through-T5 or T1-through-T6 aggregate build target.
- Make the current ProductUseful T1-through-T5 artifact publishable.
- Keep the current blocked T6 artifact private and publish-ineligible while
  still allowing local npm-format packing and inspection.
- Add deterministic inventory, checksums, credential-name-only configuration,
  duplicate-registration protection, and a broker order-mutation prohibition.
- Preserve the Pi-required host peer declarations in the published manifest.
- Add a clean tarball installation, exact runtime-dependency, default-export,
  and plain-Pi load gate to the trusted publication workflow.
