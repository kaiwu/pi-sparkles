# finance_hk_ohlcv

Status: **Experimental** · version: `0.1.0` · target: JavaScript/Bun

Hong-Kong-owned composition for bounded daily OHLCV receipts. It combines an
exact HK listing identity/effective interval with the reviewed 2026 HKEX
calendar and the provider-neutral gap classifier. It imports no CN or US market
package.

The `gap_receipt` module fixes an HK-specific canonical identity—XHKG track
scope, board, share class, declared currency, five-digit code, range, and
Eastmoney row limit—over the shared provider-neutral page/body-hash receipt
law. A matching SHA-256 proves copy coherence, not Eastmoney origin or HKEX
authority.

Listing and per-session trading/suspension evidence remain caller supplied and
unverified. Missing evidence, truncation, calendar conflicts, identity
incoherence, and altered canonical receipt content fail closed. The package
does not fetch data, synthesize bars, infer suspensions, normalize unknown
volume/amount semantics, assess corporate actions, or grant redistribution
rights. The calendar retains published half-day schedules, while this daily
gap classifier does not infer intraday completeness from a returned daily row.
