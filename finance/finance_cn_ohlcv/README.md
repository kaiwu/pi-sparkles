# finance_cn_ohlcv

Status: **Experimental** · version: `0.1.0` · target: JavaScript/Bun

Mainland-China-owned composition for bounded daily OHLCV receipts. It combines
an exact CN listing identity/effective interval with the reviewed 2026
SSE/SZSE/BSE calendar and the provider-neutral gap classifier. It does not
import US or HK market packages.

The `gap_receipt` module fixes a CN-specific canonical identity—venue, board,
share class, currency, six-digit code, range, and Eastmoney row limit—over the
shared provider-neutral page/body-hash receipt law. A matching SHA-256 proves
copy coherence, not Eastmoney origin or exchange authority.

Listing and per-session trading/suspension evidence remain caller supplied and
unverified. Missing evidence, truncation, calendar conflicts, identity
incoherence, and altered canonical receipt content fail closed. The package
does not fetch data, synthesize bars, infer suspensions, normalize unknown
volume/amount semantics, assess corporate actions, or grant redistribution
rights.
