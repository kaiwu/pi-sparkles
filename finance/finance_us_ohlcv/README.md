# finance_us_ohlcv

Status: **Experimental** · version: `0.1.0` · target: JavaScript/Bun

`finance_us_ohlcv` is the isolated US evidence-composition layer for daily
OHLCV gaps. It composes the provider-neutral `finance_ohlcv` states with the
bounded `finance_us_calendar` dataset, an exact `finance_listing` key and
effective interval, a complete provider acquisition receipt, and one explicit
trading-or-suspended status receipt for every absent open listing date.

The classifier walks every civil date in an inclusive range of at most 366
dates. It returns separate `MarketClosure`, `Suspension`, `ProviderOmission`,
and `UnavailableHistory` outcomes while retaining all evidence legs used for
each decision. It rejects:

- dates outside the source-reviewed 2026 venue calendar;
- a non-US listing or NYSE/XNYS and Nasdaq/XNAS mismatch;
- decreasing or duplicate bar and status dates;
- bars outside the requested/listing interval or on a planned closure;
- status receipts outside the requested/listing interval, on a closure, or for
  a returned bar;
- incomplete provider pagination; and
- any absent open listing date without an explicit status receipt.

Listing and status references are caller-supplied evidence pointers; this
package validates their structure and coherence but does not retrieve or
authenticate them. Its output is therefore a deterministic classification from
supplied receipts, not proof that those receipts came from an authority. It
does not fetch data, mutate a bar batch, synthesize bars, infer suspensions,
assess corporate actions, or grant redistribution rights.
