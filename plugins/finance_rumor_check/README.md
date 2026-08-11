# pi_sparkles_finance_rumor_check

Status: **Designing** · claim-evidence contract · no package manifest or code

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 42](../../../trading-course/sessions/42_research_portfolio_monitoring_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 31](../../../trading-course/sessions/31_sentiment_market_claim_verification_contract_20260811.md).

## Reviewed first slice

`rumor_check` accepts a structured market claim and caller-supplied bounded evidence set. A claim retains exact text, entities/listings, predicate, quantities/units, dates, jurisdiction, claimant/source and extraction confidence as supplied. Each source is classified independently as `Supports`, `Contradicts`, `Related`, `NotFound`, `Inaccessible`, `CannotEvaluate`, or `Conflict` with exact passages and receipts.

Outputs also expose source authority role, provenance chain, independence/circular-reporting facts, search scope and cutoff, omissions, and reproducible hashes. `NotFound` never means false, and authority never implies truth.

Claim parsing and evidence-state classification are pure. Live SEC/CNINFO/HKEX/news searches are later bounded adapter effects after source/rights review.

## Explicit exclusions

No true/false, verified/debunked, credibility or source-quality score, impact/materiality judgment, moderation, recommendation, or trade action.
