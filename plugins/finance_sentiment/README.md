# pi_sparkles_finance_sentiment

Status: **Designing** · transparent-classification contract · no package manifest or code

Product-readiness evidence: [Session 40](../../../trading-course/sessions/40_professional_product_readiness_audit_20260811.md), [Session 42](../../../trading-course/sessions/42_research_portfolio_monitoring_product_contract_20260811.md), [Session 45](../../../trading-course/sessions/45_cross_plugin_persona_acceptance_contract_20260811.md), and [Session 46](../../../trading-course/sessions/46_product_readiness_corrections_20260811.md). Shared implementation standard: [PRODUCT_READINESS.md](../../PRODUCT_READINESS.md).

Controlling evidence: [Course Session 31](../../../trading-course/sessions/31_sentiment_market_claim_verification_contract_20260811.md).

## Reviewed first slice

`sentiment_analyze` runs an explicitly selected, versioned classification model over caller-supplied bounded documents. The initial model is a local finance lexicon; a remote model is a later licensed effect. Inputs retain document/source identity, language, rights, times, exact text hash and caller-selected labels/aggregation policy.

Outputs expose per-label scores, model/version/parameters, contributing and conflicting spans with offsets, unknown-language/sarcasm/truncation warnings, document-level aggregation only when requested, multi-model disagreement, and a reproducible receipt. Original text is not rewritten or silently translated.

The local core is deterministic and pure. Any remote model adapter must be bounded, cancellable, paced, credential-redacted and independently attributed.

## Explicit exclusions

No default/model selection, truth or credibility judgment, market-impact inference, mood/regime label, moderation, recommendation, or sentiment-to-trade mapping.
