# finance_hk_documents

Experimental Hong Kong disclosure vocabulary over
`finance_market_documents`. It distinguishes financial reports, results,
announcements, circulars, listing documents, and regulatory material while
retaining exact traditional-Chinese, simplified-Chinese, English, or other
source language.

Parallel official-language publications keep both document identities and
evidence. One language is never silently treated as the controlling copy of the
other.

The `source_strategy` module defines a cache-first local retrieval plan for one
exact HKEXnews document identity. HKEXnews is currently the only canonical
channel. AKShare/Eastmoney, Yahoo, Finnhub, and other vendor observations are
not filing fallback. The route remains local-analysis-only until redistribution
and fixture rights are approved.

The module also exposes the track-scoped 85% operational coverage policy for
the `issuer_disclosures` family. HKEXnews is currently one canonical source
group; the policy does not require a second copy of an official artifact merely
to inflate a channel count. Critical identity, version, language, time, source,
and entitlement requirements remain mandatory when the denominator is defined.
