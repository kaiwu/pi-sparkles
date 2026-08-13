# Changelog

All notable changes to the `@pi-sparkles/pi-sparkles` npm package are recorded
here. Versions follow Semantic Versioning. The exact selected tier, plugin
inventory, maturity, and content hashes remain authoritative in each tarball's
`release-lock.json` and `aggregate-lock.json`.

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
