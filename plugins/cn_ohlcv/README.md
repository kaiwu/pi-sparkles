# pi_sparkles_cn_ohlcv

Status: **Experimental** · version: `0.1.0` · target: JavaScript/Bun

`cn_stock_ohlcv` converts one bounded Eastmoney `klt=101`, `fqt=0` mainland
history response into the shared `finance_ohlcv` contract. The caller must give
an exact six-digit code, venue, board, share class, and currency. The plugin
validates the declared combinations but does not claim Eastmoney proves that
identity.

Every source numeric lexeme is retained. Provider amount, amplitude, change,
and turnover fields remain separate raw evidence rather than being coerced into
OHLCV. Eastmoney supplies a civil date, not an exact bar timestamp, so canonical
observations use a visibly labelled UTC-midnight ordering anchor. The provider
volume unit and session membership remain unknown; the plugin does not call the
value shares, infer suspensions, fill gaps, or apply adjustments.

The request is read-only, caller-identified, limited to 1–1000 rows, bounded to
2 MB, cancellable, conservatively paced, and never retried through another
provider. If the response reaches the row limit, pagination is reported as
truncated because Eastmoney exposes no continuation token on this route.

Every successful result also emits a versioned `gapAssessmentReceipt`. Its
canonical SHA-256 binds the exact CN identity and range, Eastmoney source plan,
retrieval time, pagination state, ordered normalized bar dates, and response
byte length/body hash. The separate network-free `cn_ohlcv_gap_assessment`
tool can verify and compose that copied receipt with independently supplied
listing, 2026 venue-calendar, and status evidence. The digest is a content
coherence check, not an Eastmoney signature or exchange proof.

The same successful call separately appends the canonical
`pi_sparkles_finance_ohlcv.series_handoff.v1` entry to the invoking Pi or DSH
session and returns its exact `seriesReceipt`. `sma`, `rsi`, `atr`, and
`chart_ohlcv` consume that short receipt without copying rows. The gap digest
and the series receipt have different contracts and are never interchangeable.

Runtime configuration:

- `AGENT_CONTACT` (shared non-secret operator identity, for example `ops@example.com`)

The plugin supplies its fixed outbound product label.

Eastmoney is vendor-origin public-web evidence with unknown service level,
licence, and redistribution rights. Normal tests use fixtures only.

The tool emits its complete bounded provider rows and normalized OHLCV bars in
model-visible content as well as structured details, so agents can consume the
exact series rather than only the compact bar-count summary.

## T1 provider-port migration

This implementation is the first adapter evidence. T1 introduces one canonical
CN daily-series provider port and keeps this exact Eastmoney decoder behind it;
Tushare Pro becomes the second conformance adapter using caller-owned
`TUSHARE_TOKEN` only from the runtime or opt-in-test environment. Both adapters
must preserve their own lexemes, timestamps, adjustment, units, rights,
pagination and limitations while returning the same canonical envelope. There
is no automatic fallback and no duplicated swing acceptance journey per
provider.
