# pi_sparkles_finance_cache

Status: **Implemented in ProductUseful T1** · branch-local cache product

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 41](../../../trading-course/sessions/41_market_structure_source_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 17](../../../trading-course/sessions/17_product_plugin_portfolio_steering_20260807.md) and canonical replay/provenance laws.

## Reviewed first slice

Provide bounded local inspection of cache entries, source/provider usage accounting, explicit expiry of selected entries, and offline replay/export of canonical content receipts. Entries retain cache key hash, provider/source, request semantic hash, created/retrieved/expires times, byte size, entitlement/licence, redacted request identity, content hash and validation state.

The cache is never a source of truth: hits preserve original observation metadata and are visibly cached. Expiry is an explicit targeted mutation with a receipt; no broad path/glob deletion. Secrets and unsafe URLs are redacted. Storage, clock and policy are injected capabilities; domain policy stays pure.

## Explicit exclusions

No silent caching/fallback, provider choice, freshness/correctness verdict, durable credential storage, arbitrary filesystem access, automatic bulk deletion, rights extension, recommendation, or trade action.

## Implemented T1 scope

`finance_cache_inspect` returns bounded entry metadata plus provider usage
counts without response bodies. `finance_cache_export` retrieves one exact
cache-key receipt for offline replay and includes canonical response content
only when explicitly requested. `finance_cache_expire` requires both the exact
cache-key SHA-256 and the expected content SHA-256, then appends a content-bound
expiry receipt to the active Pi session branch. There is no wildcard or
provider-wide deletion.

The shared `finance_cache_contract` package validates entry timestamps, byte
and count budgets, provider/source, entitlement/licence, a redacted HTTP
request identity, semantic/content hashes and validation state. Replay fails
closed on malformed or impossible event histories. The T1 CN quote and history
adapters are initial producers; they append only schema-validated provider
responses and preserve cached state as replay evidence rather than truth.
