# finance_cn_identity

Status: **Experimental** · version: `0.1.0` · target: JavaScript/Bun

`finance_cn_identity` is the provider-neutral mainland-China identity layer.
Every equity listing requires a canonical instrument ID, exact six-digit code,
explicit SSE/SZSE/BSE venue, compatible board, share class, currency, and
status. It never infers venue, board, or currency from a bare code.

Exact-code resolution delegates to `finance_core.identifier.Resolution` and
preserves `NoMatch`, `Unique`, and every `Ambiguous` candidate. Effective-dated
aliases and evidence-backed A/B, A/H, and CDR-underlying relationships compose
the shared `finance_listing` primitives. An A/H relationship retains a real
`cn` listing key and a separate `hk` key; it does not create a Greater-China
track.

This package contains no security-master dataset, provider lookup, exchange
holiday/rule data, or OpenFIGI fallback. Tests use conspicuously synthetic
records. A plugin cannot claim production identity coverage until the
authoritative SSE/SZSE/BSE source, effective-date behavior, fixture rights, and
redistribution policy are approved.
