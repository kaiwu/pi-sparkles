# Changelog

All notable changes to the `pi-sparkles-all-in-one` npm package are recorded
here. Versions follow Semantic Versioning. The exact selected tier, plugin
inventory, maturity, and content hashes remain authoritative in each tarball's
`release-lock.json` and `aggregate-lock.json`.

## 0.1.0 - 2026-08-12

- Add the first single-entry all-in-one Pi extension package.
- Support an explicit T1-through-T5 or T1-through-T6 aggregate build target.
- Make the current ProductUseful T1-through-T5 artifact publishable.
- Keep the current blocked T6 artifact private and publish-ineligible while
  still allowing local npm-format packing and inspection.
- Add deterministic inventory, checksums, credential-name-only configuration,
  duplicate-registration protection, and a broker order-mutation prohibition.
