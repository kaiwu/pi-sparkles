# Acceptance receipt fixture

This test-only Gleam package constructs the dependent canonical receipt catalog
consumed by the bundled swing acceptance and opt-in live-tutor lanes. The
acceptance shell first invokes the real bundled CN/HK/US OHLCV tools over exact
scripted response bytes, copies their complete result and market-owned gap
receipt, and passes those exact digests into this package. The package then uses
the real pure APIs rather than hashes of descriptive labels:

- the copied market-owned OHLCV digest as the root for every dependent receipt;
- `finance_indicators` and `finance_risk` request envelopes selected by the
  caller/LLM fixture;
- effective rule projections constructed from the track-owned CN, HK, and US
  rule packages; and
- a `finance_execution` semantic receipt retaining stop-first, target-first,
  and unknown-ordering daily-bar branches.

Every copy includes its payload, canonical content hash, schema, and integrity
meaning. The acceptance shell independently recalculates every market receipt
digest and proves the receipt is an exact field-for-field copy of the bundled
tool result. The rule projection hash is explicitly a content hash, not a
provider signature or authority proof. Scripted market bytes do not authenticate
or recreate a live-provider response.

The package has no Pi dependency and makes no network, filesystem, model, or
workflow decision. Build it with:

```sh
bun scripts/build-acceptance-fixture.js
```
