# finance_ohlcv

Status: **Experimental** · version: `0.1.0` · target: JavaScript/Bun

`finance_ohlcv` is the provider-neutral contract for exact OHLCV batches. It
retains every source numeric lexeme beside its parsed decimal, validates bar
geometry and non-negative volume, rejects decreasing timestamps, collapses
only byte-for-byte-equivalent duplicate bars, and rejects conflicting
duplicates. Validated bars become canonical `finance_core.Observation(Bar)`
values and a `finance_series` timeline.

Bars distinguish a provider-supplied instant from a date-only session anchor.
For date-only sources, UTC midnight is used solely as a deterministic ordering
anchor and remains labelled `SessionDateAnchor`; it is never presented as a
provider timestamp. Volume units are likewise either proven shares or visibly
unknown.

The contract keeps two completeness questions separate:

- pagination says whether every provider page within the requested range was
  consumed or which caller budget truncated acquisition; and
- calendar assessment says whether absent sessions were classified by a
  reviewed market calendar.

Calendar gaps can be represented as `MarketClosure`, `Suspension`,
`ProviderOmission`, or `UnavailableHistory`. A provider without enough evidence
must use `CalendarNotAssessed`; it must not turn a missing row into one of those
facts. No bar interpolation, forward fill, corporate-action adjustment, or
timezone inference occurs here.

`finance_ohlcv/acquisition_receipt` supplies the provider-neutral canonical
receipt law: exact track/provider/source identity fields, retrieval time,
pagination state, sequential bounded pages, optional request IDs, response-byte
lengths and SHA-256 values, plus ordered bar dates. Market packages choose their
own ordered identity fields. A matching digest proves copied-content coherence,
not provider origin or authentication.

`finance_ohlcv/gap_assessment` supplies the provider-neutral four-state
classifier over an explicitly supplied reviewed calendar and listing interval.
It requires complete provider coverage and exact status evidence for every
absent open listing date, and rejects duplicate, out-of-range, closure, or
listing conflicts. The isolated `finance_us_ohlcv`, `finance_cn_ohlcv`, and
`finance_hk_ohlcv` packages provide their market-owned identity, source-plan,
and calendar policy; this generic package imports none of those market domains.

The initial interval contract is deliberately daily; volume is either proven
shares or explicitly unknown. Additional intervals and market-owned volume
meanings require new typed constructors. Exact close-price series and returns compose the existing
`finance_series`/`finance_math` path without converting prices through binary
floating point.
