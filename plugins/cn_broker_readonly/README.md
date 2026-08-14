# pi_sparkles_cn_broker_readonly

Status: **Experimental implementation — owned by T6** · explicit external CN read-only capability

`review_cn_broker_activity` validates a bounded normalized packet from one named
external CN provider capability. The packet must bind exact CN listing/MIC,
board, share class, native CNY, settlement observation, capability scope,
entitlement scope, provider identity, and read-only authority. It preserves
account/position/order/fill facts, lifecycle status lexemes, time order,
duplicates, conflicts, unknowns, limitations, and a semantic receipt.

The plugin ships no provider, OpenD, SDK, credential, adapter, or transport and
performs no network request. It rejects provider mismatches, cross-track
identity, credential-shaped data, market-depth fields, write-capable modes, and
broker mutation.

Focused checks:

```sh
bun run test:unit -- cn_broker_readonly
bun run build -- cn_broker_readonly
bun test test/binding/cn_broker_readonly.test.js
```
