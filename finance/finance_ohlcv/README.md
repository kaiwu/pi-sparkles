# finance_ohlcv

Status: **Experimental** · version: `0.1.0` · target: JavaScript/Bun

`finance_ohlcv` is the provider-neutral contract for exact OHLCV evidence and
batches. The information-contract entry points preserve raw, partial, unusual,
unknown, conflicting, and interrupted evidence for the LLM. The older validated
`Bar`/`Batch` projection remains available for calculations that request its
stricter shape: it retains source numeric lexemes beside parsed decimals,
validates bar geometry and non-negative volume, rejects decreasing timestamps,
collapses only equivalent duplicate bars, and rejects conflicting duplicates.
Those projection failures do not authorize a plugin to discard the preceding
information packet or make a market/workflow decision.

The `CG-MARKET-DATA` information-only slice adds:

- `finance_ohlcv/fact`, whose `Known`, `Unknown`, `NotObtained`, `Conflicting`,
  and `DecodeFailure` states never become an aggregate verdict;
- `finance_ohlcv/reported_row`, which separates decimal decoding from visible
  non-negativity and OHLC-order comparisons while preserving every raw lexeme;
- `finance_ohlcv/quantity`, `rights`, and `timing`, which retain explicit unit,
  authority, entitlement, timing, and caller-requested comparison facts;
- `finance_ohlcv/acquisition_attempt`, which content-binds effective budgets,
  cancellation/provider outcomes, and partial bar dates around the existing
  acquisition receipt; and
- `finance_ohlcv/evidence_packet`, which composes typed identity, session, row,
  acquisition, adjustment, quantity, rights, quality, evidence-root, and
  available-operation slots without choosing what the LLM should do next.

Plugins never decide correctness, trustworthiness, sufficiency, usability,
freshness, readiness, provider preference, setup quality, next action, or a
trade. They may carry out an explicit LLM calculation or transformation and
return its instruction, inputs, expression, and receipt as a separate artifact.

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

The initial interval contract is deliberately daily. The validated `Batch`
projection still exposes its legacy `Shares | UnknownVolumeUnit` type, while
the information packet can retain shares, evidenced lots, monetary turnover,
provider scaling, or an unknown quantity without guessing. Exact close-price
series and returns compose the existing `finance_series`/`finance_math` path
without converting prices through binary floating point.
