# pi_sparkles_stock_tape

Status: **Designing — owned by T6 three-track day trader/execution review; not independently queued** · no plugin manifest or Pi shell; private pure core implemented in `finance_tape`

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 41](../../../trading-course/sessions/41_market_structure_source_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 22](../../../trading-course/sessions/22_cg_day_full_workflow_contract_20260809.md), Session 11 market-data laws, the [tier workflow](../../PRODUCT_TIERS.md), and the [active ledger](../../R2.md#active-delivery-ledger--2026-08-11).

## T6 role contribution and completion contract

The recurring professional task is to inspect the exact executed tape for one
listing and bounded session window, including venue, conditions, corrections,
cancels/busts, sequence integrity and measured clock differences. The first
user-facing operation is
`stock_tape(symbol, mic, from_time, to_time, max_events)`. It returns a compact
summary plus a stable handle for bounded event and lineage drill-down.

This plugin has no standalone implementation or promotion phase. Its private,
provider-neutral `finance_tape` core is implemented and focused-testable during
blocker resolution, but no user-visible tool or provider adapter is wired. The
plugin begins only when T6 enters `building`, after the tier's three required
Futu live-data legs are independently exercised and the blocker is resolved.
Its provider capabilities, Pi shell, and day-workbench/read-only receipt handoffs are
implemented as one atomic T6 change set; every touched package remains buildable
and focused-test green throughout.

T6 cannot verify until `stock_tape` provides all of the following together:

1. the private pure `finance_tape` event, ordering, sequence, gap/reset,
   duplicate, correction/cancel-lineage, clock, condition and bounded-packet
   laws plus generation-safe bounded streaming/recovery/cleanup transitions,
   already implemented without a Pi or provider surface;
2. separately exercised Futu real-time transaction paths for the declared
   `cn`, `hk`, and `us` legs, using shared bounded streaming mechanics but exact
   track-owned feeds, identities, rights, source receipts and limitations; SSE
   Level-2 remains a stronger optional CN sequence/rebuild contract;
3. live-session gap/reset/duplicate/out-of-order detection, real correction →
   cancel/bust lineage, populated exchange/provider/receipt clocks with
   measured latency, and exact documented sale-condition codes;
4. compact Pi output, stable bounded drill-down, data-subscription
   cancellation/outage recovery, and the single composed T6 role journey with
   mandatory, separately labelled CN, HK and US legs.

A caller-packet validator may exist as private, tested internal code while T6 is
building, but it is never exposed, promoted, or recorded as a completed product
slice. Missing provider access keeps T6 blocked rather than producing an
adapter-missing public shell. No live track path is inferred from another;
missing CN, HK or US Futu conformance keeps the entire T6 acceptance profile
incomplete. Alternative providers are explicit optional breadth and never a
silent fallback.

The Pi tool returns a bounded tape window; it never exposes an unbounded stream.
A WebSocket adapter may acquire events incrementally behind that boundary. The
incremental `volume_profile` calculation is deferred until complete-session
coverage can be proved and explicitly requested.

## Reviewed core packet

`stock_trades` accepts a bounded caller/provider-adapter packet for one exact `cn`, `hk` or `us` listing/MIC/session leg. Events distinguish original trade, correction and cancel with provider trade/event IDs, references and lineage; preserve exact price/size/condition/venue lexemes, exchange/provider/retrieval clocks, sequence scope/value, gap/reset state, feed, entitlement/licence, raw receipt and unavailable/conflicting facts.

The packet validates identity, event ordering and correction references without reconstructing missing state. Requested `volume_profile` or condition summaries operate only over the retained bounded packet and expose coverage, excluded/unknown conditions, formulas and receipt hashes. No aggressor side is inferred unless an explicit sourced field exists.

A pure tape core owns event/lineage validation and requested summaries. The Pi
shell is wired only when the complete T6 capability path exists; provider
acquisition and bounded streaming state remain typed injected effects rather
than business logic in JavaScript.

## Acceptance and exclusions

Test normal/out-of-order trades, corrections/cancels, duplicate IDs, unknown
conditions, venue mixtures, gaps/resets, multiple clocks, packet truncation,
exact lexemes and canonical receipts. Provider promotion additionally requires
real response/message fixtures, entitlement and correction behavior, live
sequence scenarios, bounded acquisition, cancellation and outage recovery. No
durable reconstruction, NBBO/order-book merge, hidden-liquidity or completeness
claim, aggressor inference, signal, recommendation, or trade action.
