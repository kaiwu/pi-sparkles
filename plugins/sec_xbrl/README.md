# sec_xbrl

Tier coverage: **ProductUseful T2** · package behavior is promoted and verified only through the complete tier

`sec_xbrl` is an **Experimental** read-only Pi plugin for discovering SEC XBRL
concepts and retrieving exact raw company facts. It composes `finance_sec` and
keeps accounting selection policy outside the HTTP and Pi shells.

This is a `us` market-track plugin. Human results begin with `US track`, and
structured details include top-level `track: "us"` plus a versioned
`finance_track` context. Its SEC taxonomies, filing classes, periods, and
coverage are not reused as `cn` or `hk` accounting laws.

## User stories

- Discover the exact SEC taxonomy/tag used for a company concept instead of
  guessing that “revenue” always maps to one universal tag.
- Retrieve raw values for one concept with units, periods, filings, fiscal
  metadata, frames, amendments, and duplicates intact.
- Preserve decimal tokens exactly even when they exceed JavaScript's safe
  integer range or contain meaningful trailing scale.
- Filter by an exact unit or form and receive explicit total/truncation fields.

## Tools

| Tool | Input | Result |
| --- | --- | --- |
| `sec_xbrl_concepts` | `cik`, search `query`, optional `taxonomy`, optional `limit` 1–50 | ranked standard entity-wide concept candidates and their available units |
| `sec_xbrl_facts` | `cik`, exact `taxonomy` and `tag`, optional exact `unit`/`form`, optional `limit` 1–100 | raw facts ordered by latest filed date, with every interpretation field retained |

Concept discovery ranks exact tag, tag prefix, exact label, label substring,
then description substring. Taxonomy filtering is explicit. Fact selection
never merges equal values or silently prefers an amendment. All matches remain
separate records; limits and truncation are visible.

## What the SEC API covers

The SEC company-facts and company-concept APIs aggregate facts from forms such
as 10-Q, 10-K, 8-K, 20-F, 40-F, and 6-K and their variants. The APIs include
facts that use non-custom taxonomies such as `us-gaap`, `ifrs-full`, `dei`, or
`srt` and apply to the entire filing entity.

That is a useful but strict ceiling:

- filer-created extension concepts are absent;
- segment, geography, product, and other dimensional contexts can be absent;
- presentation/calculation relationships and statement layout are not returned;
- tags can change across taxonomy versions or reporting history;
- the same tag can have multiple units, periods, forms, accessions, amendments,
  frames, and duplicated values;
- calendar frames do not erase a company's non-calendar fiscal dates.

The plugin reports this as
`coverage: non_custom_taxonomies_and_entity_wide_facts_only`. It does not call
raw facts “revenue,” “free cash flow,” or another normalized metric without a
separate mapping and period-selection policy.

## Exact value model

`finance_sec/xbrl` decodes fact values as:

```text
FactValue = Numeric(raw: String) | Text(String) | Boolean(Bool)
```

Numeric JSON source is captured before the host can round it to a binary
number. For example, `9007199254740993.100` remains exactly that string. Tool
details expose `valueKind: numeric_exact_lexeme`; conversion to
`finance_core.Decimal`, scaling, currency interpretation, ratios, and formula
evaluation belong in a later pure normalization layer.

Every returned fact retains:

- `value`, `valueKind`, and `unit`;
- optional `start`, required `end`, and derived `periodKind`;
- `accession`, `form`, derived amendment flag, and `filed` date;
- optional fiscal year, fiscal period, and SEC calendar frame.

Missing optional values remain JSON `null`. Instant facts do not acquire a fake
start date. Amendments do not overwrite originals. Duplicate records are not
deduplicated.

## Functional architecture

```text
Pi schema/AbortSignal/environment
              |
              v
       root effect interpreter
        |                  |
        v                  v
 pure search/selection   finance_sec runtime
 validated plans        bounded SEC HTTPS
        |                  |
        +------> typed raw fact evidence
```

`concept_search` and `fact_selection` are pure Gleam modules over immutable
values. Opaque plans validate query, taxonomy, unit, form, and result budgets.
The transformations are deterministic and test without Pi, promises, HTTP,
clocks, environment variables, or JavaScript.

The root module only decodes tool arguments, translates cancellation, executes
the provider plan, checks status, invokes the typed decoder, applies the pure
plan, and renders JSON/text. `finance_sec` owns caller identity, pacing, retry,
pooling, bounds, and the exact-number boundary, so this plugin has no duplicate
HTTP stack.

## Provider and configuration

```sh
export AGENT_CONTACT="ops@example.com"
```

The contact is required for SEC fair-access identification and is transmitted
in the public `User-Agent` header. It is not a secret and is not emitted in
tool results. The default product is `pi-sparkles-sec-xbrl/0.1`.

| Property | Policy |
| --- | --- |
| Provider | US SEC EDGAR XBRL APIs |
| Authentication | no API key; declared caller identity required |
| Company-facts bound | 20 MB |
| Company-concept bound | 5 MB |
| Pacing | shared `finance_sec` runtime, 8 requests/second, 2 concurrent |
| Retry | idempotent GET only, at most 3 attempts within 15 seconds |
| Freshness | SEC says XBRL APIs update in real time, typically under one minute |
| Cache | none in this version |
| Failure | reject; never synthesize, round, or silently serve stale data |

## Security and lifecycle

The plugin performs only the documented HTTPS GETs and reads the two named
environment variables. It writes no files, starts no background work, stores no
session state, and registers no lifecycle handlers. Its shared bounded runtime
is recreated on extension reload. New, resumed, forked, compacted, and headless
sessions require no restoration. Pi abort signals cancel queued, sleeping, and
active provider work.

Pi extensions execute with the user's permissions. This plugin is data
research tooling, not an audit opinion, accounting service, investment advice,
or a filing-submission client.

## Tests and compatibility

- Pure tests cover concept ranking, taxonomy filtering, exact form/unit
  selection, duplicate retention, ordering, and limits.
- Provider fixtures cover both official endpoint shapes and exact numeric
  lexemes beyond JavaScript's safe integer range.
- The Bun contract replaces `fetch`, verifies URLs and caller identity, and
  checks every structured fact field.
- Artifact and real Pi smoke tests cover the compiled default export.

No test contacts the live SEC service or performs real sleeps.

- Package: `pi_sparkles_sec_xbrl` `0.1.0`
- Tested Pi: `0.83.0`
- Runtime requirement: `JSON.parse` reviver source context
- Provider documentation reviewed: 2026-08-04
- Status: Experimental

```sh
bun run test:unit -- sec_xbrl
bun run build -- sec_xbrl
bun run test:aggregate:pi
```

Hex distributes Gleam/FFI source; Pi loads the generated
`dist/sec_xbrl/index.js`. Local monorepo paths must become released Hex version
constraints before publication.

## Next layer

The next package should map explicitly named accounting concepts into canonical
metrics. Such a mapping must state accepted taxonomies/tags, instant versus
duration rules, annual/quarter/YTD derivation, unit and scale, fiscal calendar,
amendment/restatement precedence, duplicate policy, sign convention, and source
fact identities. Company extensions and segments require a filing-level XBRL
adapter rather than pretending company-facts is complete.

Official references:

- [SEC EDGAR data APIs](https://www.sec.gov/search-filings/edgar-application-programming-interfaces)
- [SEC developer resources](https://www.sec.gov/about/developer-resources)
- [SEC operating-company taxonomies](https://www.sec.gov/data-research/structured-data/taxonomies-schemas/standard-taxonomies/operating-companies)
- [SEC Inline XBRL overview](https://www.sec.gov/data-research/structured-data/inline-xbrl)
