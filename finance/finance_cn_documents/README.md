# finance_cn_documents

Experimental mainland-China disclosure vocabulary over
`finance_market_documents`. It distinguishes periodic reports, forecasts,
preliminary results, ad-hoc announcements, exchange inquiries, and regulatory
documents while retaining exact Chinese originals and explicit language.

A translation is a separate evidence-backed document relation. It never
replaces or silently edits the controlling original.

The `source_strategy` module defines an authority-first, cache-first local
retrieval plan for an exact SSE, SZSE, or BSE document identity. It tries the
issuing venue before CNINFO and records CNINFO only as the retrieval route; the
issuing venue remains the evidence origin only because this plan requires that
identity to have been independently proven. Raw CNINFO capture itself is
repository evidence and cannot manufacture the venue relationship. Both routes
are local-analysis-only until source-specific redistribution and fixture rights
are approved. A route may not return a merely similar or latest document as
fallback.
