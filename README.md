# pi-sparkles

Gleam plugins for the Pi coding agent, compiled with Gleam and bundled for Pi
with Bun.

See [ROADMAP.md](ROADMAP.md) for the proposed finance and stock-market plugin
family, [TRACK_GUIDE.md](TRACK_GUIDE.md) for adding another isolated market
track, and [FUNCTIONAL_DESIGN.md](FUNCTIONAL_DESIGN.md) for the mandatory
functional-core/effect-shell architecture.

## Status

This approach is feasible and the first end-to-end implementation works. The
repository currently contains:

- `pi_gleam`, a common Gleam binding for Pi's extension API;
- fifty-six Experimental finance packages, including provider adapters,
  shared track/evidence/rules/document/accounting policy, and isolated CN/HK
  identity, calendar, rules, document, and accounting layers;
- the first F0 finance plugins: `finance_setup`, `finance_track_status`,
  `cn_setup`, `hk_setup`, `finance_guardrails`, and `finance_symbols`;
- the first isolated CN/HK provider slices: `cn_disclosures` over CNINFO and
  `hk_disclosures` over HKEXnews/HKEX, with security/disclosure discovery plus
  an exchange-owned current Full List profile and rolling two-week exact
  listing-event evidence on HK;
- isolated `cn_market_calendar`, `hk_market_calendar`, and
  `us_market_calendar` plugins over venue-owned, coverage-bounded 2026
  schedules; the US surface keeps NYSE/XNYS and Nasdaq/XNAS explicit;
- isolated `cn_market_data` and `hk_market_data` plugins over the shared
  bounded `finance_eastmoney` adapter, with raw lexemes, explicit market and
  currency evidence, and unknown latency/redistribution kept visible;
- isolated `cn_market_rules` and `hk_market_rules` plugins over dated official
  rule profiles, with unsupported regimes rejected and issuer-specific HK board
  lots kept caller-evidenced;
- an isolated `us_market_rules` plugin for venue-explicit current NYSE/Nasdaq
  regular displayed-quote increments, with the deferred SEC half-cent regime
  and next compliance boundary kept visible;
- isolated `cn_fundamentals` and `hk_fundamentals` vendor slices over shared
  exact Eastmoney decoding and `finance_math`, with raw facts, visible mappings,
  source-retaining net margin, and unknown official-filing context preserved;
- the first F1 research slices: `sec_edgar`, `sec_xbrl`, and
  `stock_fundamentals`, backed by the read-only `finance_sec` adapter;
- isolated three-track OHLCV slices over the exact provider-neutral
  `finance_ohlcv` contract: credentialed Alpaca IEX/SIP raw daily bars in
  `us_ohlcv`, plus bounded Eastmoney date-only raw history in `cn_ohlcv` and
  `hk_ohlcv` with caller-declared identity/currency and unknown provider volume
  units kept visible;
- network-free `us_ohlcv_gaps`, `cn_ohlcv_gaps`, and `hk_ohlcv_gaps`
  compositors that join copied acquisition receipt fields to the exact
  track-owned 2026 venue calendar, listing interval, and per-gap status evidence
  only after reconstructing the acquisition plugin's canonical SHA-256-bound
  page projection, without changing or synthesizing bars;
- an exact US latest best-bid-and-ask slice in `us_quote`, using explicit
  Alpaca IEX/SIP selection and the provider-neutral `finance_quote` envelope;
- a network-free `stock_research_report` compositor that validates exact
  Alpaca/SEC receipts and renders a deterministic US source-fact brief;
- a track-safe `watchlist` workflow plugin with exact listing keys, bounded
  notes/tags/thesis links, branch-replayed versioned events, and deterministic
  snapshots;
- a network-free `swing_workbench` workflow-context plugin that retains exact
  strategy receipts, information-state changes, opaque LLM/user plan
  declarations, and review facts across the active session branch without
  making any decision;
- a local-first `trade_journal` information plugin over the pure
  `finance_journal` core, with immutable attributed events, idempotent bounded
  JSONL storage, explicit private-payload retrieval, requested comparisons and
  realized net P&L, and no plugin-owned psychology, process, or trade decision;
- `hello`, a reference command and typed tool;
- `safety_gate`, a reference result-bearing event handler with asynchronous UI;
- `lifecycle`, a reference for typed state restoration and safe cleanup;
- Bun-driven checking, testing, bundling, artifact tests, and Pi load tests.

The implementation was developed against Pi `0.83.0` at commit `305c014dc`,
Gleam `1.18.0`, and Bun `1.3.14`. The reference and F0 plugins build to
standalone ESM artifacts and load with Pi `0.83.0` without model credentials.
`finance_symbols` uses OpenFIGI v3 only when one of its tools is executed.
`finance_track_status` keeps the active `cn`/`hk`/`us` navigation context visible
with currency, timezone, auditable source maturity, installed feature coverage,
and an explicit non-secret agent contact, and restores track choices from the
active session branch.
`cn_setup` and `hk_setup` expose separately named capability/provider-health
surfaces with exact track contexts. They report the new pure market foundations
as Experimental. Their matching discovery, calendar, market-data, rules, and
fundamental tools advance only their own installed surfaces. CN/HK cover all
ten current feature families when those tools are loaded. US also reaches 100%
installed workflow breadth when its independent Alpaca quote/OHLCV, official
calendar, and current-rule tools are loaded. The tracks' depth and
source-maturity receipts remain different and auditable; feature breadth is not
data completeness. Authoritative venue
identity, production market-data entitlement, exceptional rule regimes, PDF
semantics, official filing-linked accounting depth, later-year calendars, and
redistribution remain visibly incomplete. Sibling or SEC tools cannot satisfy
those capabilities.
`cn_disclosures` captures the CNINFO catalogue before binding code/organization
identity and paged announcement search; its content-bound receipt remains
repository evidence and cannot invent an SSE/SZSE/BSE venue. `hk_disclosures`
captures the exact HKEXnews current-security response as a versioned
SHA-256-bound authority receipt before binding stock identity and returning the
bounded initial title page with explicit truncation. Its separate
`hk_security_profile` tool captures HKEX's official Full List workbook before a
bounded exact-entry ZIP/XLSX decode and adds current category, sub-category,
board lot, ISIN, eligibility markers, trading currency, and RMB-counter
evidence. `hk_recent_listing_event` separately captures HKEX's public rolling
current-two-week table and establishes a listing start only for an exact,
non-tentative `New Listing` row. It does not establish historical completeness,
a listing end, or positive per-session trading status.
`sec_edgar` likewise performs no request until invoked and requires an SEC
fair-access contact in `SEC_USER_AGENT_CONTACT`; `sec_xbrl` shares that contract
and preserves SEC numeric source lexemes rather than converting through binary
floats. `stock_fundamentals` adds inspectable exact-period mappings, explicit
filing policies, strict source-retaining Q4 derivation, and comparable direct-fact
trends while keeping alternate/amended facts ambiguous. Its first exact
`finance_math` compositions add free cash flow, net margin, and diluted EPS only
after proving all inputs share one period and filing context. Exact growth and
direct-quarter TTM additionally prove explicit calendar gaps and contiguous
coverage; an independently sourced annual-plus-YTD bridge covers TTM when four
direct quarters are unavailable. A typed `DirectQuarter | DerivedQuarter`
composition expands every derived Q4 back to its annual/YTD source leaves.
`us_stock_ohlcv` requires an exact Alpaca symbol/as-of date and explicit IEX or
SIP feed. It preserves source numeric lexemes, follows pagination only within
caller budgets, retains request IDs and exact page-body SHA-256 values, emits a
versioned canonical gap-projection digest, and labels USD/share/timezone/provider-
session/raw-adjustment semantics without asserting unverified trade-session
membership. The separate reviewed US calendar can classify planned exchange
days, but `us_stock_ohlcv` deliberately does not compose it with listing and
suspension evidence; missing rows therefore remain calendar-unassessed instead of being
silently classified as closures, suspensions, provider omissions, or
unavailable history. The separate network-free `us_ohlcv_gap_assessment` tool
can now classify a copied 2026 receipt only when pagination is complete, exact
venue/listing scope is supplied, and every absent open listing date has an
explicit trading-or-suspended status receipt. It verifies the copied provider
projection's SHA-256 before classification, but the digest is not a provider
signature and its listing/status evidence is not authority verified. It never
mutates the acquisition result. `us_stock_quote` supplies the
paired latest best bid/ask required by the existing quote/history family. It
preserves exact provider price and size tokens, exchange/condition/tape codes,
and explicitly reports freshness, latency, session, and size-unit semantics as
unknown rather than converting a successful request into a real-time claim.
`cn_stock_ohlcv` and `hk_stock_ohlcv` now emit the same provider-neutral
canonical receipt law behind separate market-owned identity projections. Their
network-free gap tools independently verify the copied projection before
composing the exact 2026 SSE/SZSE/BSE or HKEX calendar plus repeated listing and
status receipts. This proves copied-content coherence, not Eastmoney or exchange
authentication. HK retains its three published half-day dates while correctly
declining to infer intraday completeness from a daily row.
`watchlist` keeps each saved member on its explicit `cn`, `hk`, or `us` leg and
requires a namespaced instrument ID, uppercase symbol, and exact MIC. Its first
Experimental persistence contract survives resume and inherited forks through
the active Pi session branch; it deliberately does not claim cross-session
`/new` durability or authoritative identity resolution.

The binding is an initial `0.1.0` implementation, not a published Hex package.
Its typed surface covers normal plugin authoring, while `pi/raw` makes the
entire JavaScript API reachable when a typed wrapper is not available yet.

## The Hex model

Hex distributes the Gleam **source**, not a directly loadable Pi plugin. A Hex
release contains the plugin's Gleam modules, JavaScript FFI, metadata, and
documentation. A consumer must compile that package and bundle its named
Gleam export into a Pi extension:

```text
Hex package or local source
        |
        | gleam build --target javascript
        v
Gleam-generated ESM with named `extension` export
        |
        | generated adapter + Bun.build()
        v
dist/<plugin>/index.js + package.json
        |
        | pi -e dist/<plugin>
        v
Pi
```

Pi never loads the Hex package directly. Publishing a prebuilt npm package is
not required. Prebuilt bundles could later be attached to releases, but that is
separate from the Hex source package.

## Try it

Requirements: Gleam, Bun, and either a hydrated Pi source checkout or an
installed `pi` executable.

```sh
bun run check
bun run test
bun run build
pi --no-extensions -e ./dist/hello --list-models
```

Build or test one plugin by its directory or Gleam package name:

```sh
bun run build -- hello
bun run test:unit -- safety_gate
bun run test:pi -- pi_sparkles_hello
```

`test:pi` uses `PI_SOURCE_DIR` when that checkout has its dependencies. It
defaults to `/home/kaiwu/Documents/github/pi-mono` in this workspace and falls
back to the installed Pi when the source checkout is not hydrated.

The deterministic swing acceptance lane drives the real bundled workbench and
journal tool interfaces with fixed caller/LLM-authored fixtures on all three
tracks. A scripted acceptance transport invokes the actual bundled CN/HK/US
OHLCV tools and copies their exact content-bound result and market-owned gap
receipt. A test-only Gleam builder composes indicator-request, risk-request,
effective-rule, and execution-result receipts over that copied market digest;
the execution receipt retains every compatible daily-bar ordering branch.
These are exact scripted response bytes, not authenticated live-provider
responses, and effective-rule content hashes are not provider signatures. The
opt-in tutor lane additionally uses Pi's configured default model to inspect
the same bounded catalog and make thirteen ordered tool calls. The model
independently selects content-bound plan, preflight, monitor, replay, and review
operations, carries the selected plan hash through each record, and persists a
matching LLM-attributed journal declaration. A fresh second Pi process reopens
the native session and must return the exact revision-8 snapshot from eight
persisted extension events. The lane enables no built-in tools, uses temporary
private session and journal storage, and is excluded from `bun run test`
because it makes real model calls:

```sh
bun run test:acceptance -- swing
bun run test:live:tutor
```

Live SEC compatibility is an explicit, non-CI lane. It builds and invokes the
real `sec_edgar`, `sec_xbrl`, and `stock_fundamentals` bundles without an LLM,
allows only bounded HTTPS GETs to SEC hosts, and requires a real caller contact:

```sh
SEC_USER_AGENT_CONTACT="you@your-real-domain.com" bun run test:live:sec
```

The runner makes at most ten sequential attempts, refuses redirects, and emits
a JSON compatibility report. It is intentionally excluded from `bun run test`;
deterministic unit and binding tests never contact public providers.

## Runtime environment by plugin

Set runtime variables in the environment that launches Pi, before loading the
plugin bundle. This repository does not load `.env` files. Reload or restart Pi
after changing provider configuration because plugins capture it when their
extension factory initializes.

There is intentionally no generic `AGENT_CONTACT` or `API_KEY` variable.
Caller identity and credentials are provider-scoped so one track cannot
silently borrow another provider's authority. `*_USER_AGENT_CONTACT` and
`*_USER_AGENT_PRODUCT` values are non-secret and are sent to the named provider.
API keys and secret keys are credentials: inject them with a secret manager or
the process supervisor, never commit them or place real values in documentation.

### Shared and reference plugins

| Plugin | Required variables | Optional variables | Behavior without optional configuration |
| --- | --- | --- | --- |
| `finance_symbols` | None | `OPENFIGI_API_KEY` (**secret**) | Uses anonymous OpenFIGI access with its lower limits. |
| `finance_setup` | None | None | Reports configuration/capability state without ambient credentials. |
| `finance_guardrails` | None | None | Pure evidence and freshness policy. |
| `finance_track_status` | None | None | Its visible agent contact is explicit session/tool state, not an environment variable. |
| `stock_research_report` | None | None | Composes caller-supplied tool receipts without direct provider access; `/us-research` queues the agent workflow. |
| `watchlist` | None | None | Uses versioned Pi session-branch entries; no provider, credential, or external storage configuration. |
| `hello`, `lifecycle`, `safety_gate` | None | None | Reference plugins require no provider configuration. |

### CN track

| Plugin | Required variables | Optional variables | Notes |
| --- | --- | --- | --- |
| `cn_disclosures` | `CNINFO_USER_AGENT_CONTACT` | `CNINFO_USER_AGENT_PRODUCT` | The optional product defaults to `pi-sparkles-cn-disclosures/0.1`. |
| `cn_market_data` | `EASTMONEY_USER_AGENT_CONTACT` | `EASTMONEY_USER_AGENT_PRODUCT` | The optional product defaults to `pi-sparkles-cn-market-data/0.1`. |
| `cn_fundamentals` | `EASTMONEY_USER_AGENT_CONTACT` | `EASTMONEY_USER_AGENT_PRODUCT` | The optional product defaults to `pi-sparkles-cn-fundamentals/0.1`. |
| `cn_ohlcv` | `EASTMONEY_USER_AGENT_CONTACT` | `EASTMONEY_USER_AGENT_PRODUCT` | The optional product defaults to `pi-sparkles-cn-ohlcv/0.1`. |
| `cn_ohlcv_gaps` | None | None | Verifies and composes copied CN acquisition/calendar/listing/status receipts locally; performs no environment lookup or runtime provider request. |
| `cn_setup`, `cn_market_calendar`, `cn_market_rules` | None | None | Local capability, reviewed-calendar, and rule data require no ambient provider access. |

The three Eastmoney plugins share the same caller identity variables, but keep
independent Pi shells and track contracts. CNINFO configuration does not grant
Eastmoney access, and neither configuration is accepted as HKEX or US authority.

### HK track

| Plugin | Required variables | Optional variables | Notes |
| --- | --- | --- | --- |
| `hk_disclosures` | `HKEX_USER_AGENT_CONTACT` | `HKEX_USER_AGENT_PRODUCT` | The optional product defaults to `pi-sparkles-hk-disclosures/0.1`; the same identity covers its HKEXnews searches, HKEX Full List workbook, and rolling current-two-week listing-event page. |
| `hk_market_data` | `EASTMONEY_USER_AGENT_CONTACT` | `EASTMONEY_USER_AGENT_PRODUCT` | The optional product defaults to `pi-sparkles-hk-market-data/0.1`. |
| `hk_fundamentals` | `EASTMONEY_USER_AGENT_CONTACT` | `EASTMONEY_USER_AGENT_PRODUCT` | The optional product defaults to `pi-sparkles-hk-fundamentals/0.1`. |
| `hk_ohlcv` | `EASTMONEY_USER_AGENT_CONTACT` | `EASTMONEY_USER_AGENT_PRODUCT` | The optional product defaults to `pi-sparkles-hk-ohlcv/0.1`. |
| `hk_ohlcv_gaps` | None | None | Verifies and composes copied HK acquisition/calendar/listing/status receipts locally; performs no environment lookup or runtime provider request. |
| `hk_setup`, `hk_market_calendar`, `hk_market_rules` | None | None | Local capability, reviewed-calendar, and rule data require no ambient provider access. |

Eastmoney variables are shared at the provider layer across CN and HK, but a
configured caller identity never permits cross-track fallback or relabelling.
HKEX configuration applies only to the HK disclosure plugin.

### US track

| Plugin | Required variables | Optional variables | Notes |
| --- | --- | --- | --- |
| `sec_edgar` | `SEC_USER_AGENT_CONTACT` | `SEC_USER_AGENT_PRODUCT` | The optional product defaults to `pi-sparkles-sec-edgar/0.1`. |
| `sec_xbrl` | `SEC_USER_AGENT_CONTACT` | `SEC_USER_AGENT_PRODUCT` | The optional product defaults to `pi-sparkles-sec-xbrl/0.1`. |
| `stock_fundamentals` | `SEC_USER_AGENT_CONTACT` | `SEC_USER_AGENT_PRODUCT` | The optional product defaults to `pi-sparkles-stock-fundamentals/0.1`. |
| `us_market_calendar` | None | None | Uses source-reviewed local NYSE/Nasdaq 2026 schedule data; performs no runtime provider request. |
| `us_market_rules` | None | None | Uses source-reviewed local NYSE/Nasdaq/SEC rule data; performs no runtime provider request. |
| `us_ohlcv_gaps` | None | None | Composes copied Alpaca/calendar/listing/status receipts locally; performs no environment lookup or runtime provider request. |
| `us_quote` | `ALPACA_API_KEY_ID` (**credential**), `ALPACA_API_SECRET_KEY` (**secret**), `ALPACA_USER_AGENT_CONTACT` | `ALPACA_USER_AGENT_PRODUCT` | The optional product defaults to `pi-sparkles-us-quote/0.1`; feed entitlement and recency depend on the requested IEX/SIP feed and account. |
| `us_ohlcv` | `ALPACA_API_KEY_ID` (**credential**), `ALPACA_API_SECRET_KEY` (**secret**), `ALPACA_USER_AGENT_CONTACT` | `ALPACA_USER_AGENT_PRODUCT` | The optional product defaults to `pi-sparkles-us-ohlcv/0.1`; feed entitlement still depends on the Alpaca account and requested IEX/SIP feed. |

The three SEC plugins share one fair-access identity. Alpaca credentials are a
separate authority and never enable SEC tools or `finance_symbols`.

### Example launch configuration

This example shows variable names and non-secret caller identities. Replace the
credential placeholders through a secret manager rather than committing a
shell file:

```sh
export CNINFO_USER_AGENT_CONTACT="ops@example.com"
export HKEX_USER_AGENT_CONTACT="ops@example.com"
export EASTMONEY_USER_AGENT_CONTACT="ops@example.com"
export SEC_USER_AGENT_CONTACT="ops@example.com"
export ALPACA_USER_AGENT_CONTACT="ops@example.com"

export OPENFIGI_API_KEY="<secret-manager:openfigi>"       # optional
export ALPACA_API_KEY_ID="<secret-manager:alpaca-key-id>"
export ALPACA_API_SECRET_KEY="<secret-manager:alpaca-secret>"

pi --no-extensions \
  -e ./dist/cn_ohlcv \
  -e ./dist/cn_ohlcv_gaps \
  -e ./dist/hk_ohlcv \
  -e ./dist/hk_ohlcv_gaps \
  -e ./dist/us_market_calendar \
  -e ./dist/us_market_rules \
  -e ./dist/us_ohlcv_gaps \
  -e ./dist/us_quote \
  -e ./dist/us_ohlcv
```

`PI_SOURCE_DIR` is development-only configuration for `bun run test:pi`; no
runtime plugin reads it. Normal tests supply fixture values and mocked
transports and do not require real provider credentials.

## Pi extension contract

Pi expects the default export of an extension module to be a factory receiving
an `ExtensionAPI`. Gleam emits named ES module exports, so every plugin exposes:

```gleam
pub fn extension(api: pi.ExtensionApi) -> Promise(Nil)
```

The Bun builder generates a tiny adapter that imports this named function and
exports it as the module default. It emits:

```text
dist/<name>/
├── index.js
├── index.js.map
├── package.json       declares pi.extensions = ["./index.js"]
├── build.json         source and compatibility metadata
└── metafile.json      Bun bundle graph for auditing
```

Pi can load either `index.js` or the directory. The bundle includes the plugin,
the binding, and Gleam dependencies. Pi host modules are kept external through
an explicit allowlist.

Pi extensions run with the user's full permissions. A built plugin is trusted
code, not a sandbox.

## Repository layout

```text
pi-sparkles/
├── pi_gleam/                     shared Gleam binding package
│   ├── src/pi.gleam
│   ├── src/pi/
│   │   ├── context.gleam
│   │   ├── event.gleam
│   │   ├── event_bus.gleam
│   │   ├── raw.gleam
│   │   ├── schema.gleam
│   │   ├── session.gleam
│   │   ├── tool.gleam
│   │   └── ui.gleam
│   └── test/
├── finance/                      reusable non-Pi Gleam libraries
│   ├── finance_archive/
│   ├── finance_calendar/
│   ├── finance_cn_calendar/
│   ├── finance_cn_accounting/
│   ├── finance_cn_documents/
│   ├── finance_cn_identity/
│   ├── finance_cn_ohlcv/
│   ├── finance_cn_rules/
│   ├── finance_cn_testkit/
│   ├── finance_core/
│   ├── finance_document_attachment/
│   ├── finance_eastmoney/
│   ├── finance_evidence/
│   ├── finance_execution/        information-only CG-DAY execution core
│   ├── finance_hk_accounting/
│   ├── finance_hk_calendar/
│   ├── finance_hk_documents/
│   ├── finance_hk_identity/
│   ├── finance_hk_ohlcv/
│   ├── finance_hk_rules/
│   ├── finance_hk_testkit/
│   ├── finance_http/
│   ├── finance_listing/
│   ├── finance_market_accounting/
│   ├── finance_market_authorities/
│   ├── finance_market_calendar/
│   ├── finance_market_documents/
│   ├── finance_market_rules/
│   ├── finance_market_alpaca/
│   ├── finance_math/
│   ├── finance_ohlcv/
│   ├── finance_indicators/       calculation-only CG-TECH functional core
│   ├── finance_journal/          immutable CG-PSYCHOLOGY information core
│   ├── finance_replay/           shared CG-QUANT replay-information core
│   ├── finance_risk/             calculation-only CG-RISK functional core
│   ├── finance_quote/
│   ├── finance_openfigi/
│   ├── finance_provenance/
│   ├── finance_sec/
│   ├── finance_series/
│   ├── finance_strategy/         evidence-only CG-SWING functional core
│   ├── finance_table/
│   ├── finance_testkit/
│   ├── finance_track/
│   ├── finance_track_capabilities/
│   ├── finance_us_calendar/
│   ├── finance_us_ohlcv/
│   └── finance_us_rules/
├── plugins/
│   ├── cn_disclosures/           CNINFO security and announcement discovery
│   ├── cn_market_calendar/       official bounded SSE/SZSE/BSE 2026 calendar
│   ├── cn_market_data/           bounded Eastmoney CN quote/raw history
│   ├── cn_ohlcv/                 exact Eastmoney CN daily OHLCV
│   ├── cn_ohlcv_gaps/            network-free CN missing-row evidence join
│   ├── cn_market_rules/          dated official mainland rule profile
│   ├── cn_setup/                 isolated mainland capability preflight
│   ├── hk_disclosures/           HKEXnews discovery and HKEX current profile
│   ├── hk_market_calendar/       official bounded HKEX 2026 calendar
│   ├── hk_market_data/           bounded Eastmoney HK quote/raw history
│   ├── hk_ohlcv/                 exact Eastmoney HK daily OHLCV
│   ├── hk_ohlcv_gaps/            network-free HK missing-row evidence join
│   ├── hk_market_rules/          dated official HKEX rule profile
│   ├── hk_setup/                 isolated Hong Kong capability preflight
│   ├── finance_setup/            capability/configuration preflight
│   ├── finance_track_status/     visible cn/hk/us state and switching
│   ├── cn_fundamentals/          exact mainland vendor fundamental slice
│   ├── hk_fundamentals/          exact Hong Kong vendor fundamental slice
│   ├── finance_guardrails/       evidence and freshness policy
│   ├── finance_symbols/          OpenFIGI v3 identity resolution
│   ├── sec_edgar/                SEC company and recent filing metadata
│   ├── sec_xbrl/                 exact SEC XBRL concept and fact evidence
│   ├── stock_fundamentals/       audited direct-fact normalization
│   ├── stock_research_report/    deterministic cited US receipt composition
│   ├── swing_workbench/          LLM-owned branch-persistent swing context
│   ├── trade_journal/            LLM-owned durable local journal information
│   ├── watchlist/                track-safe branch-persistent workflow state
│   ├── us_market_calendar/       official bounded NYSE/Nasdaq 2026 calendar
│   ├── us_market_rules/          current venue-explicit US quote increments
│   ├── us_ohlcv_gaps/            network-free US missing-row evidence join
│   ├── us_quote/                 exact Alpaca US latest best bid/ask
│   ├── us_ohlcv/                 exact Alpaca US daily bars
│   ├── hello/                    command and typed-tool example
│   ├── lifecycle/                state restoration/lifecycle example
│   └── safety_gate/              typed event/async-UI example
├── scripts/                      Bun task drivers
├── test/
│   ├── binding/                  FFI contract tests
│   └── artifacts/                bundled-extension tests
├── package.json                  private root task runner
└── dist/                         generated, gitignored Pi artifacts
```

The root is not a Gleam package. The root-level `pi_gleam/` binding and every
implemented package below `finance/` and `plugins/` own a `gleam.toml`, version,
README, source, and tests, so each can be versioned and released independently.
A proposal in **Designing** may contain only its reviewed `README.md`; root tasks
discover packages by `gleam.toml` and ignore these design-only directories until
implementation starts. Finance libraries are checked and unit-tested by the
root tasks but are not Pi bundles.

## Finance foundations

The finance directory is a reusable Gleam substrate, not a collection of Pi
extensions. Plugins compose these packages behind typed Pi boundaries:

| Package | Role |
| --- | --- |
| `finance_archive` | Cancellation-aware, in-memory exact-entry UTF-8 ZIP extraction with byte/count budgets and fail-closed name, ZIP64, encryption, compression, length, and CRC checks; it is not a general archive API. |
| `finance_core` | Exact decimals, money, identifiers, instruments, sources, time, and the canonical `Observation(a)` envelope. |
| `finance_track` | Closed `cn`/`hk`/`us` market identity plus validated, versioned result context and explicit cross-track legs. |
| `finance_evidence` | Typed observation/evidence compatibility for units, quality, time ordering, licences, and same/cross-track composition. |
| `finance_listing` | Track/MIC-scoped listing keys plus effective aliases and evidence-backed relationships. |
| `finance_cn_identity` / `finance_hk_identity` | Isolated code, venue, board, ambiguity, alias, and A/H identity laws without provider fallback. |
| `finance_market_calendar` | Source/licence/version-labelled calendar datasets that fail outside declared coverage. |
| `finance_market_authorities` | Track-scoped official roles and links with access and redistribution kept separate from ownership. |
| `finance_cn_calendar` / `finance_hk_calendar` / `finance_us_calendar` | Track-specific calendar constructors and source-reviewed 2026 venue datasets over the shared engine; US retains separate NYSE/XNYS and Nasdaq/XNAS evidence. |
| `finance_market_rules` | Source-labelled effective rule validation and strict unknown/conflict selection without market constants. |
| `finance_cn_rules` / `finance_hk_rules` / `finance_us_rules` | Track-owned rule vocabulary plus narrow dated official profiles: mainland established normal CNY equities, HKEX applicable HKD equity spread bands, and venue-explicit current US regular displayed-quote increments. |
| `finance_market_documents` | Track/issuer-scoped original documents, correction/version/translation lineage, attachment identities, and strict versioned lossless JSON. |
| `finance_document_attachment` | Fail-closed media/size/page/redirect/hash/cancellation acceptance; arbitrary attachments still reject archives and OCR. |
| `finance_cn_documents` / `finance_hk_documents` | Isolated disclosure classes and source-language policy retaining exact Unicode originals. |
| `finance_market_accounting` | Exact reported lexemes/scales, statement context, executable mappings, duplicate-preserving resolution, and strict string-numeric JSON. |
| `finance_cn_accounting` / `finance_hk_accounting` | Track-owned standard/report vocabularies with strict source-document issuer coherence. |
| `finance_track_capabilities` | Pure track-prefixed setup and provider-health policy that rejects sibling-tool substitution. |
| `finance_provenance` | Evidence identities, assumptions, licences, manifests, canonical encoding, hashing, redaction, and verification plans. |
| `finance_http` | Safe requests, bounded fetch transport, cancellation, retry/`Retry-After`, rate limits, pooling, scheduling, caching, and cassettes. |
| `finance_math` | Composable exact formula trees plus explicit approximate statistics, regression, risk, cash-flow, and fixed-income policies. |
| `finance_ohlcv` | Exact raw-plus-normalized OHLCV bars, source-instant/date-anchor and proven/unknown-volume distinctions, canonical observations, strict ordering/exact deduplication, provider-neutral content-bound acquisition receipts, and calendar/listing/status gap classification. |
| `finance_indicators` | Calculation-only SMA, Wilder RSI, true-range, and Wilder ATR core with explicit input/window/gap/rounding policies, unperformed expressions, and content-bound request/semantic receipts; it emits no interpretation or decision. |
| `finance_risk` | Calculation-only planned/gap loss, explicit budgets, independent quantity bounds, supplied-grid projection, requested intersections, heat/cost decompositions, partial expressions, and content-bound receipts; it emits no policy, quantity choice, verdict, authorization, or next operation. |
| `finance_execution` | Information-only desired instructions, sourced capabilities, explicit visible-depth and daily-bar scenarios, lifecycle/fill folds, requested cost/benchmark/latency calculations, and content-bound receipts; it cannot choose an encoding or branch, judge an outcome, or mutate a broker. |
| `finance_journal` | Immutable exact attributed journal events, information states, correction/redaction lineage, partial checklists, bounded replay/query/export, requested comparisons and realized net P&L, compact context, and content-bound receipts without psychology/process/trade decisions. |
| `finance_replay` | Point-in-time universe/dataset manifests, immutable shared run definitions, caller-declared partitions/trials, ordered replay and checkpoints, explicitly requested calculations, aligned comparisons, compact context, reproduction manifests, and bounded scripted execution without research verdicts. |
| `finance_cn_ohlcv` | CN-only SSE/SZSE/BSE identity, reviewed-calendar, listing/status, and Eastmoney-receipt composition with four typed gap outcomes and fail-closed conflicts. |
| `finance_hk_ohlcv` | HK-only XHKG identity, reviewed HKEX calendar/half-day evidence, listing/status, and Eastmoney-receipt composition with four typed gap outcomes and fail-closed conflicts. |
| `finance_us_ohlcv` | US-only exact venue-calendar/listing/status/provider-receipt composition, a pure canonical SHA-256 projection contract, four typed gap outcomes, and fail-closed conflicts. |
| `finance_quote` | Exact raw-plus-normalized bid/ask prices and sizes, provider market codes, canonical observations, and explicitly unverified provider size units. |
| `finance_openfigi` | OpenFIGI v3 access, mapping/search plans, pagination, decoding, authenticated/anonymous rate profiles, and a bounded shared runtime. |
| `finance_eastmoney` | Bounded public-web SSE/SZSE/BSE/HK quote and raw daily-history plans/decoders with exact source lexemes, explicit caller identity, unknown service level, and unknown redistribution. |
| `finance_market_alpaca` | Credentialed bounded US latest-quote and raw-daily stock-bar plans/decoders with explicit IEX/SIP, exact source lexemes, and subscription/redistribution limits. |
| `finance_sec` | Identified read-only SEC access, normalized CIKs, bounded EDGAR request plans, typed submissions/XBRL facts, lossless numeric lexemes, explicit filing/period resolution, strict Q4/trend derivation, and conservative shared pacing. |
| `finance_series` | Ordered observations, alignment, as-of joins, returns, windows, resampling, portfolio paths, and analytics. |
| `finance_strategy` | Evidence-only completed-daily strategy definitions, compatibility facts, plan declarations, and structural history without a setup, acceptance, or trade verdict. |
| `finance_calendar` | Dates, market calendars, business-day rules, schedules, joint calendars, and day-count conventions. |
| `finance_table` | Typed tables with validated cells and deterministic Markdown, CSV, and JSON rendering. |
| `finance_testkit` | Seeded fixtures, scripted clocks/transports, cassette helpers, generators, scenarios, and redaction assertions. |
| `finance_cn_testkit` / `finance_hk_testkit` | Isolated seed-stable market scenarios composing each track's identity, calendar, rules, documents, and accounting laws. |

Dependencies point inward: core imports no finance package; track and other
provider-neutral packages build on core where needed; series composes core and math;
testkit supports core and HTTP; OpenFIGI and SEC compose core/HTTP as needed.
None imports Pi.
Pure calculation and policy can therefore run in any Gleam program and in tests
without Pi, networking, filesystem access, ambient time, or secrets.

Finance plugins preserve source, as-of/retrieval time when known, freshness,
units, adjustment basis, quality, and entitlement through to tool results.
Unknown metadata stays unknown. Provider adapters interpret `finance_http`
instead of adding another fetch/retry/cache stack, and metrics compose
`finance_math` and `finance_series` instead of hiding arithmetic in an effect
shell.

The first F0 plugin batch demonstrates this direction:

- `finance_setup` validates defaults and reports only capabilities it can prove;
- `finance_track_status` visibly marks and explicitly switches the active
  `cn`/`hk`/`us` navigation context without relabelling market evidence;
- `us_market_calendar` exposes venue-explicit NYSE/Nasdaq 2026 closures and
  early closes without network access or dates outside reviewed coverage;
- `us_market_rules` exposes the current NYSE/Nasdaq regular displayed-quote
  increment for an exact listing and date, while rejecting unsupported regimes;
- `us_ohlcv_gaps` structurally classifies copied 2026 Alpaca missing dates only
  after canonical projection SHA-256 verification, complete pagination, and
  exact calendar/listing/status evidence;
- `cn_ohlcv_gaps` applies the same provider-neutral receipt and classification
  laws behind CN-owned SSE/SZSE/BSE identity, calendar, and Eastmoney plan
  validation, without network or environment access;
- `hk_ohlcv_gaps` completes the same structural parity behind isolated
  XHKG/HKEX identity, calendar, half-day, and Eastmoney plan validation;
- `hk_recent_listing_event` adds exchange-owned listing-start evidence only
  for exact non-tentative `New Listing` rows in HKEX's rolling two-week page;
- `cn_setup` and `hk_setup` provide isolated readiness reports and refuse to
  treat sibling/SEC tools or unapproved providers as available;
- `finance_guardrails` composes evidence checks and accumulates typed issues;
- `finance_symbols` consumes `finance_openfigi`, then applies a small pure policy
  returning `NoMatch`, `Unique`, or `Ambiguous` instead of guessing.
- `sec_edgar` consumes `finance_sec`, then applies pure deterministic company
  ranking and filing selection before its Pi shell renders source-labelled
  results.
- `sec_xbrl` composes the same adapter with pure concept discovery and explicit
  unit/form fact selection; it preserves raw periods, accessions, amendments,
  frames, and duplicates instead of prematurely naming metrics.
- `stock_fundamentals` exposes a seven-metric executable registry and resolves
  exact or calendar-classified statement periods under explicit filing policies
  to `NoMatch`, `Unique`, or `Ambiguous`; its Q4 and trend tools then consume
  only unique, proven-compatible sources and retain every accession. Its metric
  tool exposes exact formula trees and source graphs for free cash flow, net
  margin, diluted EPS, growth, and direct-quarter TTM.
  The TTM bridge retains its annual, current-YTD, and prior-YTD source graph and
  permits independent exact-accession selection.
  General multi-input metrics likewise accept a named accession per input, but
  still reject combinations whose resolved facts do not share one filing context.
- `stock_research_report` queues the existing US evidence tools and validates
  their bounded copied receipts into a deterministic source-fact brief. It
  refuses symbol/feed/CIK/source mismatch, future-as-of evidence, duplicate
  metrics, and hidden ambiguity, while stating that receipt integrity is not
  cryptographically proven.
- `watchlist` stores only explicit track/listing identities and user-authored
  metadata. Its pure reducer enforces bounds, idempotence, exact-key removal,
  contiguous versioned replay, and deterministic snapshots; the Pi shell owns
  only branch restoration, event appends, and typed tool rendering.

All foundation interfaces are Experimental. Local path dependencies are
intentional during monorepo development; published packages must use Hex
version constraints.

## Common binding

`pi_gleam` translates Pi's object-oriented, callback-heavy JavaScript API into
Gleam values and functions. Runtime-owned values such as `ExtensionApi`,
`Context`, `Ui`, and `AbortSignal` are opaque. Values crossing untrusted FFI
boundaries are dynamically decoded where a typed API is offered.

| Module | Implemented surface |
| --- | --- |
| `pi` | commands, shortcuts, flags, queued messages, session metadata, labels, active tools, models, providers, event bus, and process execution |
| `pi/context` | mode, cwd, UI/trust/idle/abort state, prompt/context usage, scoped models, compaction, shutdown, and command-session navigation |
| `pi/event` | every current event name, generic decoded handlers, typed core events, and Pi-compatible result builders |
| `pi/event_bus` | emit, subscribe, and unsubscribe |
| `pi/schema` | JSON Schema construction, objects, enums, arrays, unions, constraints, and raw schemas |
| `pi/session` | read-only metadata and decoder-backed persisted custom-state restoration |
| `pi/tool` | schema-plus-decoder parameters, typed execution, text/image results, updates, cancellation, and rejected failures |
| `pi/ui` | notifications, prompts, status, widgets, editor text, themes, and tool expansion |
| `pi/raw` | object access/calls and raw event, tool, renderer, and markdown registration |

The binding does not falsely claim that every Pi value has a bespoke Gleam
record. It provides complete API **reachability** through `pi/raw` and typed
coverage for the core authoring path. More surfaces will move behind typed,
tested wrappers as real plugins exercise them.

### Typed tool boundary

Pi validates a tool's JSON Schema. The binding additionally pairs that schema
with a Gleam dynamic decoder:

```text
Parameters(a) = Pi JSON Schema + Dynamic decoder for a
```

Raw arguments are decoded before the typed callback runs. Decode failures
become rejected promises, so malformed JavaScript values cannot masquerade as
typed Gleam data. String enums use the flat `{ type: "string", enum: [...] }`
shape required by Pi's Google-provider compatibility guidance.

### Events

`pi/event` exports constants for every event present in Pi `0.83.0`, generic
`observe`, `respond`, `observe_decoded`, and `respond_decoded` functions, plus
typed helpers for the first high-value events:

- the complete session lifecycle: start, metadata, switch, fork, compaction,
  tree navigation, and shutdown;
- tool call decisions;
- input decisions;
- turn start;
- provider responses;
- tool execution start.

`None` from a result-bearing handler becomes JavaScript `undefined`; builders
such as `block_tool`, `transform_input`, and `replace_messages` produce the
plain JavaScript shapes Pi expects.

See [the binding README](pi_gleam/README.md) and the three reference
plugins for authoring examples.

## Plugin project contract

Each plugin should:

- be an ordinary, independent Gleam project targeting JavaScript;
- use Bun as the JavaScript runtime;
- keep its root module as a thin Pi effect shell and reusable logic below a
  package namespace;
- decode external values once, then express policy, calculation, and workflow
  state as pure functions over immutable Gleam types;
- return typed facts, calculations, compatibility states, proposed effects, and
  workflow history when replay, composition, or audit benefits; finance
  research and trade decisions remain with the LLM rather than a plugin;
- inject clocks, transports, storage, randomness, and entitlements explicitly;
- export `extension` with the promise-returning signature above;
- use `pi_gleam` as a normal Hex version dependency when published;
- keep policies, transformations, and state machines testable without Pi, Bun,
  network access, filesystem access, or real time;
- document its commands, tools, events, state, permissions, and supported Pi
  versions;
- publish source and FFI, excluding `build/`, `dist/`, and caches.

During development the reference plugins use a local path dependency on
`../../pi_gleam`. Gleam correctly refuses to publish such a package.
After the binding receives its first Hex release, plugin release manifests must
replace that path with a normal version constraint. A staging builder will make
that switch testable without forcing local development through Hex.

## Bun tasks

Commands implemented now:

| Command | Purpose |
| --- | --- |
| `bun run check` | formatting and warnings-as-errors builds for every package |
| `bun run build [-- name]` | build and bundle every plugin or one plugin |
| `bun run test:unit [-- name]` | Gleam tests with Bun for the binding, finance libraries, and plugins |
| `bun run test:architecture` | enforce functional-core/effect-shell import and FFI boundaries |
| `bun run test:ffi` | build and run JavaScript binding contracts |
| `bun run test:artifacts` | build and inspect the generated extension modules |
| `bun run test:acceptance [-- swing]` | run deterministic CN/HK/US journeys through bundled plugin tools |
| `bun run test:pi [-- name]` | load artifacts in Pi without invoking a model |
| `bun run test:live:tutor` | run an opt-in multi-stage bounded journey through Pi's configured LLM and plugin tools |
| `bun run test:live:sec` | run opt-in bounded compatibility checks against live read-only SEC APIs |
| `bun run test` | complete repository verification |
| `bun run clean` | remove generated build, work, and distribution output |

Planned release commands are `build:hex`, `hex:check`, and `hex:publish`.
Publishing will always remain an explicit operation; ordinary builds and tests
must never alter Hex or other external state.

## Test strategy

The repository uses seven layers:

1. Pure Gleam tests run on the JavaScript target with Bun.
2. Architecture tests reject Pi/Promise imports in plugin domain modules,
   Pi imports in finance libraries, and misplaced plugin FFI.
3. Bun FFI tests invoke bundled plugins with strict fake Pi objects and verify
   callbacks, schemas, event results, asynchronous decisions, and failures.
4. Artifact tests ensure every bundle has a callable default export and a Pi
   directory manifest.
5. Deterministic acceptance tests drive bundled plugin tools through complete
   declared workflow fixtures without asking a model to select anything.
6. Pi smoke tests ask the real loader to initialize each extension using
   `--list-models`, which needs no provider credentials.
7. Explicit live lanes exercise the configured tutor LLM or bounded public
   provider compatibility. They are never part of ordinary deterministic tests.

Before a release, the matrix should also cover a hydrated Pi source runtime,
the published Node runtime, and a compiled Pi Bun binary when available.

## Hex release design

The binding and plugins have independent versions. The release order is:

1. release `pi_gleam` when a plugin needs a new binding API;
2. replace local plugin dependencies with a compatible Hex version range;
3. export and audit each plugin's Hex tarball;
4. install the exact released source into a clean temporary build project;
5. compile and bundle it with Bun;
6. load that artifact in Pi.

`gleam export hex-tarball` already succeeds for `pi_gleam`, proving that the
binding's Gleam and FFI sources form a Hex package. The plugin Hex round trip is
intentionally gated on publishing/finalizing the binding name; the current
local dependency is not publishable and is not presented as if it were.

The future `hex:check` command must reject path/git production dependencies and
generated files, audit package metadata and contents, and perform the clean
source-to-Pi-artifact round trip. `hex:publish` should run the same gates before
performing the explicit external publish action.

## Implementation plan

| Phase | State | Deliverable / acceptance |
| --- | --- | --- |
| 0. End-to-end spike | Complete | Gleam command plugin bundles through Bun and loads in Pi. |
| 1. Core binding | Complete | Typed schemas/tools, decode-before-execute behavior, errors, cancellation, updates, and FFI tests. |
| 2. Events and lifecycle | Complete | Typed lifecycle records/results, decoded custom-state restoration, idempotent cleanup guidance, and replacement/compaction/tree fixtures. |
| 3. Hex round trip | Planned | Finalize the binding name, add tarball audits/staging, release binding first, and rebuild an exact plugin Hex version in a clean directory. |
| 4. Typed breadth | Planned | Type resource discovery, message content, model/provider configuration, full compaction payloads, renderers, and advanced TUI in response to real plugin needs. |
| 5. Release automation | Planned | CI matrix, compatibility table, checksums, and documented release/retirement process. |

Phase 3 comes next. Phase 2 now proves cleanup and reconstruction across
`/reload`, `/new`, `/resume`, and `/fork`, rejects malformed persisted state,
and contract-tests typed replacement, compaction, and tree-navigation shapes.

Phase 3 acceptance is the definitive distribution proof: on a clean machine
with Gleam, Bun, Pi, and the builder, fetch a plugin's source by exact Hex
version, produce `dist/<name>/index.js`, and load it without npm.

## Risks and mitigations

| Risk | Mitigation |
| --- | --- |
| Pi's extension API changes | Record the tested Pi version and run boundary tests against configured Pi checkouts. |
| FFI annotations are unsound | Decode external data and contract-test both directions of each typed boundary. |
| Gleam values leak into Pi | Construct all public event/tool results as plain JavaScript objects in FFI. |
| Hex contains no ready-to-run artifact | State the source-only model explicitly and test the Hex-to-bundle path. |
| Local path dependencies block release | Use them only for development; stage version-based manifests for release checks. |
| Bundle duplicates Pi internals | Keep a reviewed host-module allowlist and audit Bun metafiles. |
| UI is unavailable outside TUI mode | Expose `mode` and `has_ui`; require explicit non-UI behavior for interactive plugins. |
| Resources survive reload or session changes | Drive setup/cleanup from lifecycle events and make shutdown idempotent. |

## Decisions before the first release

- Confirm that the global Hex name `pi_gleam` is available and acceptable.
- Select the initial supported Pi version window beyond the tested `0.83.0`.
- Decide whether the Hex consumer builder remains in this repository or becomes
  a separately released Bun tool.
- Choose the first non-reference plugins that will drive additional typed API
  coverage.

These decisions do not block local Gleam plugin authoring or further binding
work. They do block claiming that a reference plugin is already publishable by
an exact final Hex name.

## Study references

Pi sources inspected at commit `305c014dc`:

- `packages/coding-agent/docs/extensions.md`
- `packages/coding-agent/docs/packages.md`
- `packages/coding-agent/src/core/extensions/types.ts`
- `packages/coding-agent/src/core/extensions/loader.ts`
- `packages/coding-agent/src/core/extensions/runner.ts`
- `packages/coding-agent/examples/extensions/`

`nginz-njs` sources inspected at commit `b8a97b9`:

- `README.md` and `CLAUDE.md`
- `scripts/build.js` and `scripts/test.js`
- `modules/*/gleam.toml`
- the downloaded `ngs` Gleam and JavaScript FFI sources

External documentation:

- [Gleam externals guide](https://gleam.run/documentation/externals/)
- [Gleam command-line reference](https://gleam.run/command-line-reference/)
- [Bun bundler](https://bun.sh/docs/bundler)
- [Bun test runner](https://bun.sh/docs/test)
