# stock_fundamentals

`stock_fundamentals` is an **Experimental** Pi plugin that turns a deliberately
small set of raw SEC XBRL facts into named fundamentals under inspectable,
exact-period rules. It never resolves amendments, duplicate contexts, or
alternative tags by guessing.

This is a `us` market-track plugin. Human results begin with `US track`, and
every structured result—including the network-free registry—contains top-level
`track: "us"` plus a versioned `finance_track` context. Generic-looking
`stock_fundamental*` names are Experimental compatibility surfaces; a `us_*`
migration or alias policy is required before stability.

## User stories

- Ask for one directly reported fundamental for an exact instant or duration.
- Inspect the complete tag/unit/period interpretation policy without making a
  network request.
- Distinguish no match, a unique source fact, and multiple plausible facts.
- Derive a fourth quarter from explicitly selected annual and nine-month YTD
  facts without losing either source identity.
- Build a chronological trend only from proven-comparable direct facts.
- Calculate free cash flow, net margin, and diluted EPS from exact same-filing
  inputs with the full formula and source graph visible.
- Calculate exact quarter-over-quarter or year-over-year growth and sum four
  contiguous direct quarters into TTM without bridging missing periods.
- Retain the raw SEC number and its canonical exact-decimal representation,
  source tag, period, accession, form, amendment, filed date, and frame.

## Tools

Run `/fundamentals` for a short, network-free guide to the supported metrics and
the recommended tool path. It does not fetch data or choose a filing policy.

| Tool | Behavior |
| --- | --- |
| `stock_fundamental_definitions` | Returns the complete initial metric registry; no configuration or network access is needed. |
| `stock_fundamental` | Downloads bounded company-facts data and resolves one metric for an exact CIK, unit, period, and optional form. |
| `stock_fundamental_period` | Matches an instant, quarter, half-year YTD, nine-month YTD, or annual shape ending on an exact date under an explicit filing policy. |
| `stock_fundamental_q4` | Derives Q4 as annual minus nine-month YTD after both sources resolve uniquely and pass strict additive/comparability laws. |
| `stock_fundamental_trend` | Resolves two to twenty exact period ends and returns a sorted series only when every direct fact is unique and comparable. |
| `stock_fundamental_growth` | Calculates an ordered percentage-point series only when every adjacent end-date gap matches an explicit quarter-over-quarter or year-over-year policy. |
| `stock_fundamental_ttm` | Sums exactly four contiguous direct-quarter facts for one additive monetary metric. |
| `stock_fundamental_ttm_bridge` | Calculates annual + current YTD − prior comparable YTD under three independently selectable source policies. |
| `stock_fundamental_ttm_composed` | Resolves three direct quarters plus one strict derived Q4 and expands the derived quarter into annual/YTD formula leaves. |
| `stock_fundamental_metric` | Evaluates one exact `finance_math` formula after every required SEC input resolves uniquely to the same period and filing context. |

`stock_fundamental` inputs are:

- `cik`: validated SEC CIK;
- `metric`: one registry name below;
- `unit`: exact SEC unit key, such as `USD` or `shares`;
- `start`: exact `YYYY-MM-DD`, required for duration metrics and forbidden for
  instant metrics;
- `end`: exact instant or duration end date;
- `form`: optional exact form such as `10-K`, `10-K/A`, or `10-Q`.

The classified-period tool replaces `start` with `period` and requires the same
exact `end`. Its filing policy is one of:

- `preserve_all` (default): retain every matching filing/context;
- `original_only`: exclude `/A` forms;
- `amendments_only`: retain only `/A` forms;
- `latest_filed`: retain candidates on the latest validated filing date;
- `exact_accession`: require and select the supplied accession.

Filtering can still produce more than one candidate. Latest-filed ties and
duplicate contexts remain ambiguous.

The Q4 tool accepts only `revenue`, `net_income`, `operating_cash_flow`, and
`capital_expenditures_reported`. `annualEnd` and `nineMonthEnd` are exact dates;
forms and a base filing policy are optional. Either source may instead be pinned
with `annualAccession` or `nineMonthAccession`, which changes that source's
reported policy to `exact_accession`. If either resolution is absent or
ambiguous, the tool returns structured unresolved sources and performs no
arithmetic.

The trend tool accepts a period class and two to twenty exact `ends`. One
explicit filing policy applies to every point. Input order is irrelevant; a
successful result is chronological. Any absent or ambiguous period blocks the
series, while incompatible metrics, units, concepts, period shapes, or duplicate
ends reject the comparison.

## Initial audited registry

All mappings use the `us-gaap` taxonomy and whole-entity company-facts coverage.
Accepted tags are alternatives, not a preference order.

| Metric | Period | Unit kind | Accepted tags | Exact meaning |
| --- | --- | --- | --- | --- |
| `revenue` | duration | monetary | `RevenueFromContractWithCustomerExcludingAssessedTax`, `RevenueFromContractWithCustomerIncludingAssessedTax`, `Revenues`, `SalesRevenueNet` | Direct reported revenue under the selected tag; tax scope differences remain visible. |
| `net_income` | duration | monetary | `NetIncomeLoss`, `ProfitLoss` | Direct reported profit/loss according to the selected tag; attribution differences are not collapsed. |
| `assets` | instant | monetary | `Assets` | Direct consolidated total-assets fact. |
| `cash_and_equivalents` | instant | monetary | `CashAndCashEquivalentsAtCarryingValue` | Cash and cash equivalents at carrying value; restricted cash is not added. |
| `operating_cash_flow` | duration | monetary | `NetCashProvidedByUsedInOperatingActivities` | Direct reported operating cash flow with the reported sign. |
| `capital_expenditures_reported` | duration | monetary | `PaymentsToAcquirePropertyPlantAndEquipment` | Reported PP&E purchase outflow only; no sign inversion or broader capex reconstruction. |
| `diluted_weighted_average_shares` | duration | shares | `WeightedAverageNumberOfDilutedSharesOutstanding` | Direct diluted weighted-average shares for the exact duration. |

The registry is intentionally small. The 2026 US-GAAP taxonomy is current, but
tag availability varies by filer and historical taxonomy version. SEC staff
also documents that revenue tagging can depend on assessed-tax treatment and
the nature of the reported line. Alternative tags therefore remain separate
candidates rather than a fallback chain.

## Resolution policy

The pure resolver performs only these steps:

1. Select an accepted `us-gaap` concept.
2. Select the exact unit.
3. Match `start`/`end` exactly, including instant versus duration semantics.
4. Apply the optional exact form filter.
5. Parse the preserved numeric lexeme into `finance_core.Decimal`.
6. Return `no_match`, `unique`, or `ambiguous`.

Candidates are ordered by latest filed date and accession only for stable
presentation. Ordering does not select a winner. A 10-K/A does not overwrite a
10-K; comparative facts repeated in later filings and equal duplicate contexts
remain candidates. The result includes both `value` (the original lexical
scale) and `canonicalDecimal` (normalized exact decimal).

### Classified statement periods

The classified tool uses inclusive Gregorian day counts and an exact end date:

| Class | Inclusive duration |
| --- | ---: |
| `instant` | no start date |
| `quarter` | 61–121 days |
| `half_year_ytd` | 152–212 days |
| `nine_month_ytd` | 243–303 days |
| `annual` | 335–395 days |

The SEC frames API describes quarter and annual periods as 91 and 365 days,
each with a 30-day tolerance. The half- and nine-month classifications use the
same disclosed tolerance around 182 and 273 days. This is calendar-shape
classification, not a claim about statement presentation. It deliberately does
not trust `fy` and `fp` to identify a comparative fact's economic period.

### Q4 derivation laws

Q4 is derived only as one unique annual fact minus one unique nine-month YTD
fact when all of these are true:

1. The normalized metric is identical and is additive across the period.
2. The exact unit, taxonomy, and tag are identical.
3. Both facts have the same fiscal start.
4. Inclusive Gregorian classification proves annual and nine-month YTD shapes.
5. The residual interval itself proves a 61–121-day quarter shape.

The result retains both complete candidates, derives the start as the day after
the nine-month end, and labels its method. Weighted-average shares, balance-sheet
instants, alternative-tag combinations, and caller-selected ambiguous inputs
cannot cross this constructor. A directly reported quarter remains available
through `stock_fundamental_period`; the two observations are not silently
treated as interchangeable.

### Comparable trends

A trend contains direct facts rather than calculated or interpolated points.
Every point has the same normalized metric, exact unit, taxonomy and tag, and
requested period class. Exact source accessions remain attached to each point.
The pure constructor sorts by end date and rejects duplicate dates. It does not
fill gaps, annualize, convert currency, join alternative concepts, or decide
which restatement wins.

### Calculated metrics

`stock_fundamental_metric` initially exposes three formula compositions over the
audited direct registry:

| Metric | Exact formula | Output | Required direct inputs |
| --- | --- | --- | --- |
| `free_cash_flow` | operating cash flow − reported PP&E purchases | requested currency | `operating_cash_flow`, `capital_expenditures_reported` |
| `net_margin` | net income × 100 ÷ revenue | percentage points | `net_income`, `revenue` |
| `diluted_eps` | net income ÷ diluted weighted-average shares | currency/share | `net_income`, `diluted_weighted_average_shares` |

The caller supplies `currencyUnit`, a duration `period`, exact `end`, optional
form, a base filing policy, and an optional division scale from 0 through 18
(default 4). `sourceAccessions` may independently pin any required named input;
unspecified inputs retain the base policy. Diluted EPS additionally accepts
`sharesUnit`, defaulting to the exact SEC unit `shares`. Division uses half-even
rounding and zero denominators are errors. Free cash flow follows the registry's explicit sign convention:
`PaymentsToAcquirePropertyPlantAndEquipment` is treated as a reported positive
purchase outflow and subtracted without first negating it.

Every input must resolve uniquely. The pure metric constructor then independently
proves the expected metric, duration class, exact start/end, accession, form,
filed date, fiscal year, and fiscal period are coherent. Monetary inputs must
use one three-letter currency unit; EPS requires the exact shares unit. A
successful result contains the immutable `finance_math` expression tree,
ordered input names, assumptions, output unit, exact decimal, and every complete
source candidate. It never combines facts from separate filings merely because
their end dates match. Independent selection does not weaken this law: if two
explicit accessions belong to different filing contexts, both resolutions may
succeed but the metric constructor rejects the cross-filing calculation.

### Multi-period metrics

`stock_fundamental_growth` first constructs the same comparable direct-fact
trend described above. The caller must then declare `comparison`:

- `quarter_over_quarter` requires each adjacent end-date gap to classify as
  61–121 days; or
- `year_over_year` requires each adjacent end-date gap to classify as 335–395
  days.

For every adjacent pair it evaluates `(current - previous) × 100 / previous`
with the requested 0–18 scale and half-even rounding. A zero previous value is
an error. Every point retains both complete candidates, its formula tree,
assumptions, and exact percentage-point output. Consequently, two individually
valid annual or quarterly facts cannot be labelled consecutive when their end
dates skip the declared comparison interval.

`stock_fundamental_ttm` accepts exactly four end dates and only additive
monetary direct metrics: revenue, net income, operating cash flow, and reported
PP&E purchases. After comparable-trend validation, each next fact's start must
equal the day after the previous fact's end, and the complete first-start through
fourth-end span must independently classify as annual. The formula is an exact
four-input sum. Weighted-average shares and instant facts are rejected, and the
tool does not fill a missing quarter or use the derived-Q4 constructor. Each quarter may
naturally come from a different filing, but all retain the same metric, exact
unit, taxonomy and tag established by the trend proof.

`stock_fundamental_ttm_bridge` covers the complementary direct-fact formula
`annual + current YTD - prior comparable YTD`. YTD may be quarter, half-year, or
nine-month. The constructor proves the annual and prior YTD share a fiscal
start, current YTD starts the day after the annual end, both YTD facts have the
same period class and a year-over-year end gap, and the resulting trailing
window is annual-shaped. Metric, exact unit, taxonomy, and tag must also match.
The annual, current-YTD, and prior-YTD sources each accept an independent exact
accession override; ambiguity in any source prevents calculation.

The pure quarter model is `DirectQuarter(candidate) |
DerivedQuarter(derived_q4)`. `composed_trailing_twelve_months` accepts four of
these typed observations in any order, revalidates every derived Q4 from its
retained annual and nine-month candidates, sorts the quarters, proves exact
continuity and an annual-shaped window, and checks metric/unit/tag compatibility.
Its formula does not contain an opaque derived-quarter input: a derived leaf is
expanded to `quarter_N_annual - quarter_N_nine_month_ytd`, so the calculated
metric references only direct SEC facts.

`stock_fundamental_ttm_composed` exposes the common rolling case of one derived
Q4 plus three directly reported quarters. `directAccessions`, when present, is
positionally aligned with the three `directEnds`; annual and nine-month sources
have their own accession overrides. Results label every quarter as `direct` or
`derived_q4` and retain the nested source candidates.

## Explicit non-goals

Beyond the formulas and typed growth/TTM paths above, this slice does
not calculate debt, EBITDA, gross/operating margins, ROE/ROA/ROIC, currency
conversion, valuation multiples, arbitrary user-supplied formulas, or implicit
restatement precedence. It does not add current and non-current components,
infer fiscal dates, choose among revenue tags, or reconstruct statements.

Those features require explicit formulas and selection rules over source fact
identities. `finance_math` is available for the arithmetic once the input facts
are resolved; arithmetic must not be used to disguise unresolved accounting
ambiguity.

## Functional architecture

```text
typed Pi arguments
       |
       v
root effect shell ----> finance_sec bounded company-facts runtime
       |                              |
       v                              v
finance_sec/fundamentals pure registry + exact resolver
       |
       v
NoMatch | Unique(candidate) | Ambiguous(candidates)
       |
       v
finance_sec/derivation pure Q4/trend proof boundary
       |
       v
stock_fundamentals/metrics pure source laws + finance_math formulas
```

The registry, validated query, exact period matching, numeric conversion,
resolution, Q4 subtraction, trend validation, direct/derived-quarter
composition, source-coherence checks, and formula evaluation are pure Gleam
functions over immutable typed facts. The
provider runtime, abort signal, environment, and tool rendering stay in the
plugin root. The metric module consumes `finance_math` through a local path
dependency; it does not duplicate decimal or formula machinery.
The definitions tool returns the same registry values used by the resolver, so
documentation cannot silently diverge from executable policy.

## Provider, configuration, and trust

```sh
export SEC_USER_AGENT_CONTACT="ops@example.com"
export SEC_USER_AGENT_PRODUCT="my-research-agent/1.0" # optional
```

The data tool uses `finance_sec`: eight requests/second, two concurrent
requests, a 20 MB response bound, cancellable retries for idempotent GETs, and
no unlabelled cache. It performs only the official company-facts HTTPS request.
The definitions tool performs no I/O and works without SEC configuration.

Results report provider, source URL, access, entitlement, freshness, coverage,
definition, candidates, and an interpretation warning. SEC company-facts
contains non-custom taxonomy facts applying to the whole entity; custom tags,
segments, dimensional contexts, and statement relationships remain outside the
coverage.

Pi plugins execute with the user's permissions. This plugin reads only the SEC
user-agent environment values, writes no files, stores no session data, and has
no trading or filing-submission capability.

## Lifecycle and failure behavior

The SEC runtime is created at extension load and shared by calls. The plugin
registers no events, timers, background polling, widgets, or persistent custom
state. Reload creates a new bounded runtime; new/resumed/forked/compacted and
headless sessions need no restoration.

Invalid arguments, unsupported period shapes, incompatible derivations,
malformed provider values, transport failures, and non-success status reject
safely. A valid direct query with no fact returns `no_match`; multiple valid
source facts return `ambiguous`. Q4, trend, growth, TTM, and calculated-metric
tools expose unresolved source resolutions and do no arithmetic when uniqueness
has not been proved. Incoherent unique sources, invalid comparison gaps,
non-contiguous quarters, and zero denominators reject explicitly.

## Testing, compatibility, and distribution

- Pure tests cover the seven-definition registry, period-kind validation,
  exact form matching, arbitrary-precision values, amendment ambiguity, strict
  Q4 source laws, trend sorting, duplicate-period rejection, all three exact
  formulas, same-filing enforcement, exact growth gaps, direct and composed TTM
  continuity/provenance, and zero-denominator failure.
- The Bun contract verifies the inspectable registry, official endpoint,
  caller identification, exact source numbers, ambiguous structured result,
  exact Q4 subtraction, retained accessions, ordered comparable trends, formula
  trees, exact large-number metrics, growth/direct-TTM/bridge/composed outputs,
  assumptions, nested derived leaves, and source graphs.
- Architecture, artifact, and installed-Pi smoke tests cover integration.
- Tests use fixtures and never contact the live SEC service.

### Opt-in live compatibility

The repository also provides a separate production-read compatibility runner:

```sh
SEC_USER_AGENT_CONTACT="you@your-real-domain.com" bun run test:live:sec
```

This is not a unit test or an SEC sandbox. It invokes the built `sec_edgar`,
`sec_xbrl`, and `stock_fundamentals` bundles directly, without a model. The
runner allows only HTTPS GET requests to `www.sec.gov` and `data.sec.gov`, caps
the complete run at ten attempts, refuses redirects, enforces a 30-second
timeout per tool call, and prints a bounded JSON report. Its historical fundamental cases cover a
52/53-week filer, a June fiscal year-end, a calendar-year filer, instant and
duration facts, and multiple filing vintages. Live values are not snapshotted;
the assertions concern provider shape, exact-number preservation, filtering,
and non-empty audited mappings.

Package `pi_sparkles_stock_fundamentals` `0.1.0` targets Pi `0.83.0` and uses
the same modern JavaScript exact-JSON runtime requirement as `finance_sec`.

```sh
bun run test:unit -- stock_fundamentals
bun run build -- stock_fundamentals
bun run test:pi -- stock_fundamentals
```

Hex distributes Gleam and FFI source. Pi loads the generated
`dist/stock_fundamentals/index.js`; local development paths must become released
Hex constraints before publication.

## v0.1 completion status

The scoped first plugin is approximately **95% complete**. Its provider,
precision, ambiguity, period, derivation, formula, provenance, cancellation,
artifact, Pi-load, and concise `/fundamentals` workflow are implemented.

### Required before declaring v0.1 complete

- [ ] **Pass the live SEC compatibility lane.** The bounded runner is
  implemented, but an identified production run has not yet been recorded.
  Supply a real fair-access contact and run:

  ```sh
  SEC_USER_AGENT_CONTACT="you@your-real-domain.com" bun run test:live:sec
  ```

  Completion requires every company, filing, raw-XBRL, and normalized-metric
  check to pass within the ten-attempt budget. The report must cover the
  calendar-year, June-year-end, and 52/53-week fixtures, multiple historical
  filing vintages, instant and duration facts, exact numeric lexemes, and a
  non-empty audited fundamental mapping. Record the run date and report outcome;
  do not commit the caller contact or downloaded payloads.

- [ ] **Complete the Hex dependency and package audit.** Publish or otherwise
  finalize compatible releases of `pi_gleam`, `finance_core`, `finance_http`,
  `finance_math`, and `finance_sec`, then replace all five monorepo `path`
  dependencies in `gleam.toml` with released version ranges. Add and verify the
  declared Apache-2.0 licence file and package metadata. Export the Hex tarball
  and reject generated build output, manifests, credentials, live reports, or
  unrelated monorepo files.

- [ ] **Prove the clean distribution round trip.** Install the exact packaged
  source into a fresh temporary Gleam project, resolve only released
  dependencies, build it, generate `dist/stock_fundamentals/index.js`, inspect
  the Bun metafile/external allowlist, and load the resulting directory with Pi.
  This proof must not rely on the monorepo's local package paths.

- [ ] **Finish the release compatibility matrix.** The installed Pi `0.83.0`
  smoke load already passes. Before release, also load the artifact with a
  hydrated Pi source checkout and the intended packaged runtime or compiled Bun
  binary, then document the supported Pi version window. Any host-contract
  difference must receive a binding contract test before widening that window.

These are validation and distribution tasks; no additional binding or finance
logic is known to block local plugin development.

Debt, EBITDA, ROIC, segments, and full statement reconstruction are later
product scope, not blockers for this deliberately narrow v0.1.

## Next layer

The next release increment is live compatibility and package validation. Debt
and leverage still require an effective-dated component graph before joining
the registry.
Broader profitability and return metrics need new audited direct mappings for
gross/operating profit, equity, and beginning/ending balance policies; formula
algebra alone cannot supply missing semantics.

Official references:

- [SEC operating-company taxonomies](https://www.sec.gov/data-research/structured-data/taxonomies-schemas/standard-taxonomies/operating-companies)
- [SEC EDGAR XBRL APIs](https://www.sec.gov/search-filings/edgar-application-programming-interfaces)
- [FASB revenue taxonomy implementation guide](https://xbrl.fasb.org/impdocs/Rev2_TIG/Revenue.htm)
- [SEC observations on revenue tagging](https://www.sec.gov/data-research/structured-data/common-noninterest-income-tagging-errors)
