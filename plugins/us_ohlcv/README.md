# pi_sparkles_us_ohlcv

Status: **Experimental** · version: `0.1.0` · target: JavaScript/Bun

This isolated US-track plugin exposes `us_stock_ohlcv`, the first daily,
read-only OHLCV slice. It composes the provider-neutral `finance_ohlcv`
contract with `finance_market_alpaca`; it does not import CN/HK market packages
or relabel another track's observations.

The caller must provide an exact uppercase Alpaca symbol, inclusive start/end
dates, an `asOf` symbol-mapping date, and either `iex` or `sip`. There is no
default or fallback feed. Requests always use `1Day`, USD, ascending order, and
raw adjustment. Caller-visible page/bar budgets cap pagination, cancellation is
propagated to every page, and repeated tokens fail closed.

An optional exact caller-proven `mic` (`XNYS` or `XNAS`) enables the canonical
active-session OHLCV handoff. When present, the tool appends
`pi_sparkles_finance_ohlcv.series_handoff.v1` and returns `seriesReceipt` for
`sma`, `rsi`, `atr`, and `chart_ohlcv`. Alpaca does not prove listing venue, so
when `mic` is absent the receipt capability is explicitly `track_partial`; the
gap digest is never substituted as a series receipt.

Every result includes:

- source and normalized OHLCV values, provider UTC timestamp, US session date,
  trade count, and VWAP;
- `America/New_York`, USD, shares, provider-defined daily aggregation, and
  raw-adjustment semantics; exact trade-session membership remains an explicit
  unverified provider limitation;
- Alpaca request IDs, pages fetched, truncation reason, exact duplicate count,
  retrieval time, feed entitlement, and redistribution limitations;
- a copy-ready `gapAssessmentReceipt` with SHA-256 for each exact response body
  and one canonical SHA-256 binding provider plan identity, retrieval time,
  pagination, page receipts, and ordered normalized bar dates; and
- an explicit `calendar_not_assessed` receipt. This acquisition tool never
  guesses that a missing session is a closure, suspension, provider omission,
  or unavailable history.

The de-duplicated bounded rows are also emitted as exact model-visible CSV for
indicator calculations. Pi renders only the summary line by default; expansion
reveals the CSV while the complete structured evidence remains in `details`.

The separately loadable, network-free `us_ohlcv_gaps` plugin can now compose
copied output fields with the reviewed 2026 venue calendar, an exact listing
interval, and explicit status receipts. It does not mutate this tool's result,
and incomplete pagination or missing/conflicting evidence rejects the
assessment. The digest detects a changed or incomplete copy; it is not an
Alpaca signature and does not authenticate provider origin.

Configure credentials only through the runtime environment:

- `ALPACA_API_KEY_ID`
- `ALPACA_API_SECRET_KEY`
- `AGENT_CONTACT` (shared non-secret operator identity, for example `ops@example.com`)

The plugin supplies its fixed outbound product label.

Secrets are sent only as sensitive request headers and never enter tool details,
safe request identities, errors, fixtures, or session output. Normal tests mock
`fetch`; no live Alpaca call is part of `bun run test`.
