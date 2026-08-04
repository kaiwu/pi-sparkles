# finance_sec

`finance_sec` is an **Experimental**, reusable Gleam adapter for the SEC's
read-only EDGAR JSON data. It contains no Pi imports and composes
`finance_http` for bounded transport, retries, cancellation, pooling, and
pacing.

## Scope

The implemented boundary provides:

- validated caller identification as an opaque `Access` value;
- validated, normalized ten-digit `Cik` values;
- bounded request plans for the SEC company-ticker file, submissions JSON, and
  company-facts/company-concept JSON;
- typed decoders for the ticker/CIK association file and recent submission
  metadata, plus exact-value XBRL company facts;
- a shared runtime limited to two concurrent requests and eight admissions per
  one-second window;
- explicit cancellation and injected sender, sleeper, and clock capabilities.

XBRL decoding preserves taxonomy, tag, label, description, unit, start/end,
exact value lexeme, accession, fiscal year/period, form, filed date, frame,
amendments, and duplicates. These are typed raw facts, not normalized financial
statements or automatically selected metrics.

## Public modules

| Module | Responsibility |
| --- | --- |
| `finance_sec` | `Access`, `Cik`, validation, request authorization, status |
| `finance_sec/request` | bounded GET plans for company tickers, submissions, and company facts |
| `finance_sec/response` | typed company, filing, and submissions decoders |
| `finance_sec/runtime` | conservative shared pacing, retry, pooling, and cancellation |
| `finance_sec/xbrl` | validated concept identities and lossless company-facts/company-concept decoding |
| `finance_sec/fundamentals` | audited initial US-GAAP direct-tag registry and exact-period ambiguity-preserving resolution |
| `finance_sec/periods` | Gregorian instant/quarter/YTD/annual classification and exact end-date matching |
| `finance_sec/derivation` | strict source-retaining Q4 subtraction and comparable direct-fact trend construction |

`Access` and `Cik` are opaque, so callers cannot construct an unidentified
request or a malformed SEC path after crossing the constructors. Recent filing
arrays are zipped only when their lengths agree; malformed columnar responses
are rejected instead of truncated.

## SEC access contract

The JSON APIs at `data.sec.gov` require no API key. The SEC asks automated
clients to declare a descriptive user agent with contact information and caps
automated access at ten requests per second. This package requires a product
and contact value and uses a conservative eight-request-per-second budget. It
does not try to evade throttling, rotate identities, scrape search pages, or
fall back to an unlabelled cache.

| Resource | Endpoint | Bound | Decoder |
| --- | --- | ---: | --- |
| Company associations | `https://www.sec.gov/files/company_tickers.json` | 2 MB | implemented |
| Submissions | `https://data.sec.gov/submissions/CIK##########.json` | 5 MB | implemented |
| Company facts | `https://data.sec.gov/api/xbrl/companyfacts/CIK##########.json` | 20 MB | implemented |
| Company concept | `https://data.sec.gov/api/xbrl/companyconcept/CIK##########/<taxonomy>/<tag>.json` | 5 MB | implemented |

Requests time out after 15 seconds. Naturally idempotent GETs may be retried up
to three attempts within a 15-second elapsed budget with bounded backoff.
Non-success HTTP status handling remains the consumer's responsibility because
the response is still useful for provider-specific interpretation.

This package covers public, read-only data APIs. It does not implement EDGAR
Next enrollment, filing submission, account tokens, or any write capability.

## Functional design

Validation, URL planning, response decoding, filing-column consistency, rate
state transitions, and retry policy are Gleam values/functions. The network,
clock, sleep, cancellation flag, and the tiny generic mutable rate-state cell
are explicit effects at the runtime edge. `runtime.new_with` permits complete
deterministic tests without real HTTP or sleeping.

That split lets another Gleam application reuse the same provider laws without
Pi, and lets plugins compose SEC data with other pure finance packages before
interpreting any UI or tool effect.

SEC numeric JSON tokens are captured from the runtime's `JSON.parse` source
context before binary-number rounding and represented as `Numeric(raw:
String)`. The JavaScript FFI only preserves the lexical token and contains no
selection or accounting policy. Bun/Node runtimes used to compile and run this
package must support the standardized `JSON.parse` reviver source context; an
unsupported runtime fails decoding instead of silently losing precision.

The SEC XBRL APIs aggregate facts that use non-custom taxonomies and apply to
the whole filing entity. Company extensions, segment/dimensional contexts, and
many presentation relationships therefore require filing-level XBRL sources.
Even within company facts, equal concepts can carry different units, periods,
forms, amended accessions, or duplicate contexts; consumers must choose through
an explicit policy.

The initial `fundamentals` module provides seven narrowly defined direct facts:
revenue, net income, assets, cash and equivalents, operating cash flow,
reported PP&E purchases, and diluted weighted-average shares. Queries require
an exact unit and exact instant/duration dates. All accepted tags have equal
candidate status; original/amended filings, alternative tags, and duplicates
produce an explicit `NoMatch`, `Unique`, or `Ambiguous` resolution. Debt, free
cash flow, scale conversion, tag precedence, and statement reconstruction are
not hidden inside this layer.

The statement-period layer additionally classifies inclusive durations by
calendar shape: quarter 61–121 days, half-year YTD 152–212, nine-month YTD
243–303, and annual 335–395. Quarter and annual bands follow the SEC frame
definition of 91 or 365 days plus/minus 30; half- and nine-month bands apply the
same explicit tolerance around 182 and 273 days. Classification always requires
an exact end date and never uses `fy`/`fp` as the fact's economic period because
those fields can accompany comparative facts.

Fundamental resolution supports explicit `preserve_all`, `original_only`,
`amendments_only`, `latest_filed`, and `exact_accession` policies. The default
remains `preserve_all`. Latest-filed is never implicit, validates ISO filing
dates, and retains ambiguity when multiple candidates share the latest date.
No policy deduplicates equal facts.

## Strict derivations

`finance_sec/derivation` is a pure layer over already resolved candidates. It
does not fetch data or choose among ambiguous sources.

`q4` accepts exactly one annual candidate and one nine-month YTD candidate. It
subtracts only revenue, net income, operating cash flow, or reported PP&E
purchases, and only when both facts have the same normalized metric, exact unit,
taxonomy and tag, fiscal start, and valid annual/nine-month calendar shapes. It
rejects instant facts and non-additive duration facts such as weighted-average
shares. The remaining interval from the day after the nine-month end through the
annual end must itself classify as a quarter. The result retains both complete
source candidates and states that it is derived rather than directly reported.

`trend` requires at least two unique candidates with one metric, unit, taxonomy
and tag, and one caller-declared period class. It validates every period, sorts
by exact end date, and rejects duplicate ends. It performs no interpolation,
restatement selection, tag coercion, unit conversion, or gap filling. These
constraints make the constructors composable laws: downstream metric code can
accept a `DerivedQ4` or `Trend` knowing source comparability was already proven.

## Build and test

```sh
cd finance/finance_sec
gleam format --check src test
gleam build --target javascript --warnings-as-errors
gleam test
```

The tests use small provider fixtures and do not access the live SEC service.
Before publishing, local path dependencies must be replaced with released Hex
version constraints.

## Sources and limitations

- [SEC EDGAR application programming interfaces](https://www.sec.gov/search-filings/edgar-application-programming-interfaces)
- [SEC fair-access rate-control announcement](https://www.sec.gov/filergroup/announcements-old/new-rate-control-limits)
- [SEC guidance for accessing EDGAR data](https://www.sec.gov/search-filings/edgar-search-assistance/accessing-edgar-data)
- [SEC company ticker associations](https://www.sec.gov/file/company-tickers)

The SEC says the ticker association data is provided as a convenience and does
not guarantee its accuracy or scope. Consumers must preserve it as candidate
identity data, not silently treat a ticker as a permanent unique identifier.
