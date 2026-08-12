# pi_sparkles_broker_readonly_alpaca

Status: **Implemented inventory — `track_partial`** · caller-owned import review only · US network path on hold

## Implemented partial slice

`review_alpaca_activity_import` validates bounded caller-owned account facts and
lifecycle observations for exact `paper` or `live` environment labels. It
retains exact status lexemes, hashes private references, produces a content
receipt, and exposes duplicates and conflicts without network access or
credentials.
Caller-supplied source hashes are retained but are not verified against absent
source bytes and do not authenticate Alpaca.
Market-depth fact names are rejected; this plugin does not read bid/ask/offer
data.
The shared boundary also enforces an aggregate semantic-payload budget,
credential-shaped input rejection, JavaScript-safe event times, cross-track MIC
exclusion, and separate input-order versus occurred-time lifecycle projections.

Missing: Alpaca response decoders and pagination/conformance fixtures; reviewed
proof of read-only credential scope and an opt-in provider check; and the
Alpaca network adapter, which remains on hold with the US path.

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 44](../../../trading-course/sessions/44_broker_live_operational_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Historical input: [Course Session 25](../../../trading-course/sessions/25_cg_live_broker_effect_contract_20260811.md). The repository's [non-executing broker boundary](../../PRODUCT_READINESS.md#non-executing-broker-boundary--controlling-amendment-2026-08-12) controls.

## Reviewed completion target

The completed scope adds a provider-specific, strictly read-only Alpaca adapter
for account capability, account summary, positions, open/recent lifecycle
records, and fills. Every observation retains provider
account/instruction/asset identity, environment, provider status lexemes,
timestamps, pagination/request receipts, entitlement, and
unavailable/conflicting fields.

The adapter must use `finance_http` with bounded responses, cancellation, pacing, credential redaction, and fixture-tested decoders. Credentials remain opaque capabilities and require demonstrably read-only scope. The Pi shell can inspect and page facts but exposes no mutation operation.

Acceptance requires fixtures for all states and pagination, secret-redaction tests, read-only method/host allowlists, cancellation, partial responses, and an opt-in real-account read-only check after access is approved.

## Stop conditions and exclusions

The live Alpaca network adapter is on hold while T6 uses its CN anchor. Fixture
decoding and a caller-owned account-activity export may prove the bounded import
contract; any later network mode requires reviewed rights and a demonstrably
read-only key. No write-capable credential, order placement/routing,
cancellation/replacement, paper/live equivalence, readiness verdict,
recommendation, or credential material in model-visible output.
