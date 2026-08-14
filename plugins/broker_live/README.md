# pi_sparkles_broker_live

Status: **Experimental implementation — owned by T6** · non-executable handoff and external receipt reconciliation

`review_external_execution_evidence` has two exact modes. A non-executable
handoff requires one unambiguous instruction side/kind/quantity/unit/time in
force plus plan, rule, provider-capability, provider-identity, and read-only
authority receipts. External receipt reconciliation requires exact entitlement,
capability, handoff, and execution-receipt linkage and retains provider status
lexemes, chronology, duplicates, conflicts, and unknowns.

The unregistered local-file import is bounded to a regular UTF-8 file, rejects
symlinks, honors cancellation, verifies exact byte count and caller-supplied
SHA-256 before decoding, and never returns raw content. The selected provider,
SDK, credentials, and transport are external; this plugin has no order mutation
surface.

Focused checks:

```sh
bun run test:unit -- broker_live
bun test test/binding/broker_live.test.js
```
