# sec_edgar

`sec_edgar` is an **Experimental** Pi plugin for read-only company discovery and
recent filing metadata from the SEC's primary EDGAR data APIs. It is the first
vertical slice above the reusable `finance_sec` provider package.

This is a `us` market-track plugin. Human results begin with `US track`, and
structured details include top-level `track: "us"` plus a versioned
`finance_track` context. SEC identity must never become a global default or a
fallback for `cn` or `hk`.

## User stories

- Find candidate CIKs from a ticker or company name without guessing among
  ambiguous identities.
- List a company's recent filings by normalized CIK.
- Restrict recent filings to an exact SEC form such as `10-K`, `10-Q`, or
  `8-K` while retaining accession, filing date, report date, and primary
  document name.
- Give the agent machine-readable provider, source, freshness, unit, access,
  entitlement, and limitation fields alongside human-readable output.

## Commands and tools

| Surface | Input | Result |
| --- | --- | --- |
| `/sec-company <query>` | ticker or company name | up to ten ranked company candidates in the UI |
| `sec_company_search` | `query`, optional `limit` 1–25 | ranked candidate CIK/ticker/title records |
| `sec_company_submissions` | `cik`, optional exact `form`, optional `limit` 1–50 | recent filing metadata in SEC order |

The search order is deterministic: exact ticker, ticker prefix, exact title,
title substring, then ticker substring; ties sort by ticker. A candidate result
is not a claim that the ticker/CIK relation is unique or current. Submission
lookup therefore requires the caller to choose a CIK explicitly.

## Explicit non-goals

This first slice does not download or parse filing documents, search filing
text, construct archive links, decode XBRL company facts, normalize accounting
concepts, monitor new filings, cache responses, or submit filings. It does not
use EDGAR Next credentials and has no write, paper-trading, or live-trading
capability. Those are separate provider/domain layers, not hidden behavior of
these tools.

## Functional architecture

```text
Pi tool/command + env + AbortSignal
                 |
                 v
       effect shell (root module)
          |                 |
          v                 v
 pure validated plans    finance_sec runtime
 ranking/filtering       finance_http transport
          |                 |
          +-------> typed immutable results
```

`company_search` and `filing_selection` are pure Gleam modules. Their opaque
plans validate all bounds before execution; ranking and selection transform
immutable lists with deterministic ordering. They import neither Pi, promises,
FFI, clocks, nor networking, so they can be composed, replayed, property-tested,
and reused in larger research workflows.

The root module is a deliberately thin interpreter. It decodes typed tool
arguments, translates Pi abort signals into `finance_http` cancellation,
executes request plans, checks HTTP status, decodes provider data once, applies
the pure transformation, and renders text plus JSON. No business rule lives in
the JavaScript environment FFI.

## Provider and operational policy

| Property | Policy |
| --- | --- |
| Provider | US Securities and Exchange Commission EDGAR |
| Authentication | no API key; identified user agent required |
| Endpoints | company ticker JSON at `www.sec.gov`; submissions JSON at `data.sec.gov` |
| Access | read-only public data |
| Pacing | shared `finance_sec` runtime, 8 requests/second, at most 2 concurrent |
| Retry | idempotent GET only, maximum 3 attempts and 15 seconds elapsed |
| Response bounds | 2 MB company file; 5 MB submissions file |
| Cache | none in this version |
| Outage behavior | reject safely; never synthesize or silently serve stale data |
| Redistribution | callers remain responsible for SEC terms and downstream use |

The SEC reports that submissions data updates in real time, but individual
payloads do not provide a retrieval timestamp used by this plugin. Each filing
retains its provider `filingDate` and `reportDate`; missing report dates remain
empty/unknown rather than becoming zero or the filing date. No numerical unit
applies to metadata results.

The company ticker association file carries an explicit warning because the SEC
does not guarantee that it is complete or current. Results preserve source and
match reason so a later identity resolver can arbitrate them with FIGI, MIC,
share-class, or historical-symbol evidence.

## Configuration and trust boundary

Set a contact that the SEC can use for fair-access questions:

```sh
export SEC_USER_AGENT_CONTACT="ops@example.com"
export SEC_USER_AGENT_PRODUCT="my-research-agent/1.0" # optional
```

If the product is absent, the plugin uses `pi-sparkles-sec-edgar/0.1`. Empty,
whitespace-padded, overlong, or newline-bearing identity values are rejected.
The contact is transmitted in the public `User-Agent` header; it is not a
secret. It is not copied into tool details or session content.

Pi plugins run with the user's full permissions. This plugin performs only the
documented HTTPS GETs above, does not write files, and reads only the two named
environment variables. Abort signals cancel queued, paced, sleeping, and active
requests through the shared transport boundary.

## Lifecycle

The provider runtime is created when Pi loads the extension and is shared by its
command and tools. The plugin registers no event handlers, timers, widgets,
session custom data, background polling, or shutdown work. Reload creates a new
bounded runtime; new, resumed, forked, compacted, and headless sessions require
no restoration. Commands notify only when UI exists. Tools work non-
interactively and return rejected tool promises for invalid configuration,
arguments, cancellation, transport failures, non-success status, or invalid
provider data.

## Testing

- Pure Gleam tests cover validation, deterministic ranking, limits, exact form
  matching, and preservation of provider order.
- `finance_sec` fixture tests cover caller identity, CIK normalization, bounded
  paths, and response decoding.
- The Bun provider contract replaces `fetch`, verifies both official URLs and
  the exact caller-identification header, and checks typed tool details.
- Artifact tests require a callable default Pi export.
- Pi smoke loading initializes the plugin without credentials or a model call;
  missing configuration is reported only when a surface is invoked.

No test calls the live SEC service, reads ambient credentials, or sleeps in real
time.

## Compatibility and distribution

- Package: `pi_sparkles_sec_edgar` `0.1.0`
- Tested Pi version: `0.83.0`
- Provider contract reviewed: SEC EDGAR public JSON documentation, 2026-08-04
- Status: Experimental; schemas and provider behavior may change before 1.0

Build from the monorepo:

```sh
bun run test:unit -- sec_edgar
bun run build -- sec_edgar
bun run test:pi -- sec_edgar
```

Pi loads `dist/sec_edgar/index.js`. Hex distribution contains Gleam and FFI
source, not the generated bundle; consumers must build the source before Pi can
load it. Local path dependencies are intentional for monorepo development and
must become released Hex constraints before publication.

## Next slices

1. Add typed archive-document identity and bounded primary-document retrieval.
2. Decode historical submissions files referenced outside the recent window.
3. Build a separate `sec_xbrl` layer preserving taxonomy, concept, unit,
   context, period, accession, form, filed date, amendments, and duplicates.
4. Compose provenance manifests and content-addressed evidence without moving
   retrieval or policy into the plugin shell.

Official references:

- [SEC EDGAR APIs](https://www.sec.gov/search-filings/edgar-application-programming-interfaces)
- [SEC fair-access rate limits](https://www.sec.gov/filergroup/announcements-old/new-rate-control-limits)
- [Accessing EDGAR data](https://www.sec.gov/search-filings/edgar-search-assistance/accessing-edgar-data)
- [SEC company ticker file](https://www.sec.gov/file/company-tickers)
