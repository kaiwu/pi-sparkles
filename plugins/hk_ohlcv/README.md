# pi_sparkles_hk_ohlcv

Status: **Experimental** · version: `0.1.0` · target: JavaScript/Bun

`hk_stock_ohlcv` converts one bounded Eastmoney `klt=101`, `fqt=0` Hong Kong
history response into the shared `finance_ohlcv` contract. The caller must give
an exact five-digit code, HKEX board, share class, and listing currency. The
plugin does not assume HKD or claim Eastmoney proves the declared identity.

Every source numeric lexeme is retained. Provider amount, amplitude, change,
and turnover fields remain separate raw evidence rather than being coerced into
OHLCV. Eastmoney supplies a civil date, not an exact bar timestamp, so canonical
observations use a visibly labelled UTC-midnight ordering anchor. The provider
volume unit and session membership remain unknown; the plugin does not infer
half-days or suspensions, fill gaps, or apply adjustments.

Every bounded provider row is also emitted as model-visible CSV so an agent can
calculate indicators from exact values. Pi renders only the summary line by
default; expansion reveals the CSV while the full receipt stays in `details`.

The request is read-only, caller-identified, limited to 1–1000 rows, bounded to
2 MB, cancellable, conservatively paced, and never retried through another
provider. If the response reaches the row limit, pagination is reported as
truncated because Eastmoney exposes no continuation token on this route.

Every successful result also emits a versioned `gapAssessmentReceipt`. Its
canonical SHA-256 binds the exact HK identity and range, Eastmoney source plan,
retrieval time, pagination state, ordered normalized bar dates, and response
byte length/body hash. The separate network-free `hk_ohlcv_gap_assessment`
tool can verify and compose that copied receipt with independently supplied
listing, 2026 HKEX calendar, and status evidence. The digest is a content
coherence check, not an Eastmoney signature or HKEX proof.

Runtime configuration:

- `AGENT_CONTACT` (shared non-secret operator identity, for example `ops@example.com`)

The plugin supplies its fixed outbound product label.

Eastmoney is vendor-origin public-web evidence with unknown service level,
licence, and redistribution rights. Normal tests use fixtures only.
