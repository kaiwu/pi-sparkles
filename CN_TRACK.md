# China track delivery ledger

Snapshot: **2026-08-05**

This ledger turns the China section of `ROADMAP.md` into an implementation
sequence. It is a plan, dependency record, and acceptance checklist. It does not
create plugin placeholders: a `plugins/<name>/` directory is created only when
that plugin enters Designing with a complete local `README.md`.

The goal is parity of engineering quality with the current OpenFIGI/SEC slices,
not a translation of US-equity behavior. Provider-neutral internals should be
reused aggressively. Mainland-China identity, market rules, accounting,
disclosures, language, data rights, and provider contracts remain China-owned.

## Status at this snapshot

- CN0-CN4 provider-backed capabilities are **Draft/Waiting**. Pure CN/HK
  identity, bounded-calendar, effective-rules, document, and accounting
  packages now exist, and isolated `cn_setup`/`hk_setup` preflights are
  Experimental. The first raw CSRC/SFC authority adapters now exist, but there
  are no provider-backed market-data plugins yet.
- The repository will expose exactly three market tracks: `cn` (mainland
  China), `hk` (Hong Kong), and `us` (United States). Provider-neutral and
  cross-market capabilities are not additional tracks.
- `finance_track` is **Experimental**. It implements the closed track type,
  validated context, schema-v1 JSON, top-level Pi result fields, and explicit
  cross-track legs. Current SEC and US-fundamental results emit `track: "us"`.
  Its profile contract also supplies visible CN/CNY/Shanghai,
  HK/HKD/Hong-Kong, and US/USD/New-York interaction defaults.
- The reusable foundations are Experimental, including `finance_evidence`,
  `finance_listing`, `finance_market_calendar`, `finance_market_rules`,
  `finance_market_authorities`, `finance_market_documents`,
  `finance_market_accounting`, and
  `finance_track_capabilities`.
- `finance_openfigi` and `finance_sec` are useful architectural references, but
  their source contracts and domain laws are not China contracts.
- The first licensed quote/history provider, authoritative security-master
  inputs, calendar fixture rights, and structured-financial source are still
  decisions. Plugins that depend on them are blocked from implementation, not
  licensed to use an undocumented public web endpoint as a shortcut.
- `cn` always means mainland China. `hk` is separate and is joined to `cn` only
  by explicit A/H or Stock Connect tools. Existing SEC and US-fundamental
  slices belong to `us`.

Ledger states used below:

| State | Meaning |
| --- | --- |
| Open | Repository work can proceed after its listed dependencies. |
| Decision | A documented product, provider, licence, or UX decision is required. |
| Waiting | The item is sequenced behind another ledger item. |
| Done | Code, documentation, and all acceptance checks exist. |

## Progress log

- **2026-08-05 — three-track foundation:** implemented `finance_track` with
  strict `cn | hk | us` parsing, track-prefixed scopes, venue/board/timezone,
  source language, providers, entitlement, limitations, JSON round trips, and
  context-preserving cross-track legs. Added it to the pure-foundation
  architecture gate.
- **2026-08-05 — US baseline alignment:** `sec_edgar`, `sec_xbrl`, and
  `stock_fundamentals` now label human output as US and attach both top-level
  `track: "us"` and versioned `trackContext` details. Binding tests cover every
  exercised SEC/fundamental result. Generic `stock_fundamental*` naming remains
  an explicit pre-stability migration gap.
- **2026-08-05 — canonical timezone:** evolved `Observation(a)` and its wire
  format to schema v2 with an optional IANA timezone. Mapping preserves it,
  schema-v1 data decodes with an unknown timezone, and unknown future schema
  versions fail safely.
- **2026-08-05 — typed evidence compatibility:** added `finance_evidence` over
  canonical observations, provenance records, and track legs. It validates
  source/evidence identity, time order, availability, unit, quality/restatement,
  as-of policy, redistribution intent, and default same-track behavior. An
  explicit cross-track policy retains every leg and must contain multiple
  tracks.
- **2026-08-05 — CN/HK identity domain:** added shared `finance_listing`
  effective aliases/relationships plus isolated `finance_cn_identity` and
  `finance_hk_identity`. Synthetic laws keep mainland `000001` ambiguous,
  retain HK leading zeroes, validate venue/board scope, and preserve both A/H
  legs. No provider security master is bundled.
- **2026-08-05 — bounded calendars:** added `finance_market_calendar` and
  isolated CN/HK constructors. Every dataset declares track, venue, timezone,
  source, licence, version, and coverage; outside coverage is an error.
  Synthetic tests cover multiple sessions, midday gaps, closures, and edges;
  authoritative fixtures remain blocked on CN-F07.
- **2026-08-05 — active-track statusline:** added
  `finance_track_status`. It shows track/currency/timezone/agent contact,
  restores branch-scoped choice, exposes headless status/switch tools, and emits
  a strict track-change event. Switching navigation never relabels evidence,
  swaps providers/calendars, or merges market-owned state.
- **2026-08-05 — effective market rules:** added shared
  `finance_market_rules` plus isolated `finance_cn_rules` and
  `finance_hk_rules`. Exact listing, board, share class, security type, status,
  and effective date are selection dimensions; missing and overlapping rules
  fail closed. Only synthetic records are bundled while rule sources wait on
  the provider/licence matrix.
- **2026-08-05 — disclosure/accounting domains:** added shared document lineage
  and lossless reported-fact packages plus isolated CN/HK vocabularies. Exact
  Unicode originals, corrections/translations, attachment hashes, numeric
  lexemes, reported scales, statement scope, audit/restatement state, executable
  mappings, issuer coherence, and duplicates are preserved. Provider decoders,
  real fixtures, and audited mappings remain blocked.
- **2026-08-05 — lossless disclosure wire:** added strict schema-v1 JSON codecs
  for shared market documents and accounting facts. Round trips retain track/MIC
  listing identity, exact Chinese text and numeric lexemes, original scale,
  normalized unit, period/scope, source, and evidence; unknown schema versions
  and numeric JSON tokens fail closed.
- **2026-08-05 — verified CN/HK authority map:** confirmed from primary official
  sources that CSRC/SFC are the statutory regulators, exchange operators own
  frontline listing and issuer-disclosure surfaces, and MOF/HKICPA own the
  accounting standards. The accepted adapter boundaries are now clear; public
  API support, fixture rights, and redistribution terms remain decisions.
- **2026-08-05 — isolated seeded market scenarios:** added
  `finance_cn_testkit` and `finance_hk_testkit` over the shared seed engine and
  each track's own domain packages. Deterministic catalogues cover leading
  zeroes, venue/board classes, B-share currency, listing-specific HK lots,
  suspension, split sessions, Unicode/parallel-language/correction documents,
  exact large lexemes, reported scales, and CAS/HKFRS/IFRS distinctions.
- **2026-08-05 — user-visible official source registries:** added the pure
  `finance_market_authorities` contract plus isolated CN/HK registries in the
  existing setup shells. `/cn-sources`/`cn_authorities` and
  `/hk-sources`/`hk_authorities` expose official links, roles, scope, access,
  redistribution, and limitations while keeping sibling sources isolated and
  verified ownership distinct from approved automation.
- **2026-08-05 — bounded attachments:** added
  `finance_document_attachment`. Pure acceptance enforces exact media
  allowlists, byte/page/redirect budgets, cross-host redirect policy,
  cancellation, and SHA-256 identity; archives and OCR explicitly fail closed.
  Accepted metadata constructs the shared evidence-backed attachment identity.
- **2026-08-05 — isolated setup surfaces:** added `cn_setup` and `hk_setup`
  with `/cn-setup`/`/hk-setup`, track-prefixed capabilities/provider-health
  tools, exact contexts/defaults, and honest blocked decisions. Architecture and
  binding tests prove sibling and SEC tools cannot satisfy their readiness.
- **2026-08-05 — authority-first provider strategy:** researched the current
  TradingAgents-CN implementation and added pure `finance_provider_strategy`.
  It composes the existing HTTP cache modes while enforcing track-prefixed
  channels, configurable priority, first-compatible-success fallback,
  per-source records, separate origin/retrieval route, and exact family,
  identity, freshness, unit, and adjustment contracts. CN disclosure plans try
  the issuing venue before CNINFO for the same exact document identity while
  retaining SSE/SZSE/BSE as origin; HK keeps a separate HKEXnews-only plan.
- **2026-08-05 — first bounded authority fetch adapters:** added shared
  `finance_authority_snapshot` plus isolated `finance_csrc` and `finance_sfc`.
  CSRC exposes three exact allowlisted public HTML publication pages; SFC
  exposes its official press-release RSS. Both require caller identification,
  use 15-second bounded GETs, one-request-per-second admission, a one-request
  pool, cancellation, bounded retry/queues, strict status/media/UTF-8 length
  checks, and raw-text SHA-256 evidence before semantic decoding. Normal tests
  use fixtures only; access is local-analysis-only and no-redistribution.
- **2026-08-05 — byte-preserving issuer artifacts:** extended `finance_http`
  and `finance_authority_snapshot` with a distinct bounded binary response,
  original-byte SHA-256/base64 capture, PDF-signature validation, and the same
  retry, pacing, concurrency, queueing, cancellation, and exact allowlist laws
  as text. Added `finance_cninfo` and `finance_hkex` for one exact already-known
  PDF path per runtime. CNINFO evidence names the repository until separate
  official metadata proves an SSE/SZSE/BSE origin; HKEXnews evidence is direct.
  Public search and semantic decoding remain blocked.
- **2026-08-05 — real-parser PDF inspection:** added `finance_pdf` around the
  pinned Apache-2.0 PDF.js distribution. It accepts only an already-bounded
  binary response, has independent byte/page/time limits, disables nested
  fetching and rendering-oriented facilities, walks every page, and destroys
  the parser on cancellation, timeout, success, or failure. The narrow
  `finance_authority_pdf` composition binds the page count, parser/version, raw
  artifact, and evidence hash from the same response without coupling text-only
  authority adapters to PDF.js.
  Deterministic contracts and bounded research checks prove 22 pages for the
  known CNINFO artifact and 25 for the known HKEXnews artifact.

## Binding decisions

### 1. Exactly three market tracks

| Track ID | User label | Market-specific surface | Boundary |
| --- | --- | --- | --- |
| `cn` | Mainland China | `/cn-*`, `cn_*` | SSE, SZSE, and BSE listings and mainland rules; never includes HK implicitly. |
| `hk` | Hong Kong | `/hk-*`, `hk_*` | HKEX listings, Hong Kong rules, `Asia/Hong_Kong`, and HKD/listing currency. |
| `us` | United States | `/us-*`, `us_*`, plus clearly provider-specific `sec_*` | US listings and SEC/US-provider contracts; never acts as a global default. |

“Global,” “international,” and “Greater China” may describe an explicit search
or cross-track workflow, but they are not track IDs. Such a workflow contains
independently labelled `cn`, `hk`, or `us` legs and cannot erase their venue,
currency, calendar, source, or entitlement.

The existing Experimental SEC tools are assigned to `us`. Generic-looking US
surfaces such as `stock_fundamental*` need a documented `us_*` migration or
alias policy before stability. Provider-specific `sec_*` names may remain, but
their structured results must say `track: "us"`. A track-neutral identity search
must require or return track scope; it cannot silently choose one.

Capability/setup views are also single-track. `/cn-setup`, `/hk-setup`, and
`/us-setup` may share one pure implementation, but each reports only its own
providers and companion tools. A track-neutral setup entry point must require a
`cn | hk | us` argument and must not merge readiness into one status.

The active navigation context is always visible through the statusline and
`finance_track_status`. `/finance-track cn|hk|us` and the direct `/cn-track`,
`/hk-track`, and `/us-track` commands switch it explicitly. Its displayed
currency and timezone are interaction defaults; a source observation remains
controlling and a switch cannot convert or relabel it.

### 2. Reuse internals; isolate the user contract

All China plugins use the shared finance packages and the common Pi binding.
They do not copy decimal arithmetic, observations, HTTP retry, rate limiting,
cancellation, evidence manifests, series operations, table rendering, or test
interpreters. Reuse happens below the Pi surface through independent
`finance/<name>/` packages; one plugin does not import another plugin's shell.

User-facing isolation is stricter:

- Mainland packages use `plugins/cn_<name>/`, Gleam package names
  `pi_sparkles_cn_<name>`, `/cn-*` commands, and `cn_*` tool names.
- Hong Kong uses `plugins/hk_stock/`, `/hk-*`, and `hk_*`; it is never silently
  included in a mainland universe.
- Every structured result starts with a stable track context containing at
  least `track` (`cn`, `hk`, or `us`), security/market scope,
  venue/MIC when applicable, board when applicable, timezone, providers, source
  language, retrieval/freshness state, entitlement, and limitations.
- Human output starts with a visible label such as
  `CN track (mainland China) | SSE Main Board | Asia/Shanghai`. A bilingual view
  retains the Chinese original and labels the translation; it never replaces
  the controlling text.
- A bare six-digit code, translated company name, or provider ticker never
  enters a track-neutral resolver without explicit scope. Ambiguity is returned
  to the caller.
- There is no invisible provider fallback and no invisible fallback to `/symbol`,
  SEC, US fundamentals, a Hong Kong listing, or vendor-derived data.
- An explicit fallback plan may use cache-first retrieval and configured
  provider priority, but only inside one track and one exact semantic contract.
  Every attempt and selected channel remains visible; an incompatible success
  stops rather than silently changing freshness, units, adjustment, or identity.
- Cross-track computations are separate, named compositions. Each input keeps
  its own track, currency, venue, calendar, source, and as-of time.
- Configuration and state are namespaced (`CN_*` or provider-specific China
  names). China setup does not inherit a global USD/UTC default. Account and
  watch state never share keys with another track.

The common result context is the small reusable provider-neutral
`finance_track` type, not a JSON object rebuilt by every plugin and not a China
type reused accidentally by `hk` or `us`.

### 3. Provider packages follow source boundaries

Do not build a single `finance_cn` client or one provider adapter per Pi plugin.
Reusable packages should follow stable domain or source boundaries:

```text
provider-neutral foundations
  -> China domain packages (identity, calendar, rules, documents, accounting)
  -> source adapters (SSE, SZSE, BSE, CNInfo, CSRC, official macro sources,
                      and one explicitly selected licensed market-data vendor)
  -> pure plugin policy/orchestration
  -> thin cn_* Pi effect shells
```

Implemented pure seams and remaining package candidates are listed below;
unimplemented names are not permission to scaffold them:

- `finance_track`: the closed `cn | hk | us` track identity, common result
  context, and explicit cross-track leg composition. It contains no provider or
  market rules.
- `finance_cn_identity`: venue, board, listing, historical alias, relationship,
  and ambiguity laws over `finance_core` identifiers.
- `finance_cn_calendar`: implemented bounded mainland calendar construction
  over injected data; authoritative versioned fixtures still wait on CN-F07.
- `finance_cn_rules`: effective-dated trading, settlement, eligibility, lot,
  limit, and suspension rules.
- `finance_cn_documents`: Chinese document identity, version/correction links,
  original/translation relationships, attachment metadata, evidence types, and
  an authority-first direct-venue/`Via("CNINFO")` local retrieval strategy that
  preserves the venue as origin.
- `finance_cn_accounting`: exact reported scale, statement scope, accounting
  standard, report/audit class, executable line mappings, resolution, and
  source-retaining formula laws.
- `finance_cninfo`: implemented exact-known-document PDF request/capture with
  one-path runtime allowlisting, caller identity, bounded byte-preserving
  transport, PDF signature, SHA-256 evidence, structural page inspection, and
  no-redistribution policy. Search, venue attribution proof, text/OCR policy,
  and semantics remain open.
- `finance_sse`, `finance_szse`, and `finance_bse`: future source-specific
  access, plans, decoders, pacing, licence, pagination, bounds, and
  cancellation. Create only packages justified by accepted documented
  products; do not assume every site has a supported API.
- `finance_csrc`: implemented caller-identified, bounded raw snapshots for the
  official market-monthly, market-weekly, and consultation-feedback pages.
  Semantic HTML decoding is deliberately not implemented yet.
- `finance_cn_market_<provider>`: one named licensed quote/history adapter.
  The provider name must not be hidden behind a generic client.
- `finance_cn_nbs`, `finance_cn_pboc`, and `finance_cn_safe`: separate official
  macro adapters where their actual contracts differ.
- `finance_hkex`: implemented exact-known-document HKEXnews PDF request/capture
  with coherent date/identifier validation, one-path runtime isolation, and
  same-artifact structural page inspection. Search, text/OCR policy, issuer
  metadata decoding, Connect data, and market data remain separate unimplemented
  contracts.
- `finance_sfc`: implemented caller-identified, bounded raw XML snapshots for
  the official SFC press-release RSS; it is not an issuer or quote adapter.
- `finance_provider_strategy`: shared pure cache/priority/fallback policy. It
  never owns endpoints or combines tracks; market packages construct isolated
  plans and source adapters perform the bounded effects.

Every source adapter must match the current `finance_sec`/`finance_openfigi`
caliber: opaque access, validated plans, bounded responses, explicit page and
request budgets, cancellation, retries only where safe, provider-specific rate
state, redacted failures, fixture-tested decoders, and written entitlement,
licence, cache, outage, and redistribution policy.

### Verified authority and source map

There is no one-to-one EDGAR or SEC replacement. Regulation, frontline listing
supervision, issuer dissemination, accounting standards, and licensed market
data are separate source contracts. This map records official ownership; it is
not approval to automate or redistribute an undocumented endpoint.

| Responsibility | Mainland `cn` authority/source | Hong Kong `hk` authority/source | Adapter boundary and current decision |
| --- | --- | --- | --- |
| Statutory securities regulation and enforcement | [CSRC](https://www.csrc.gov.cn/csrc_en/c102023/common_zcnr.shtml?channelid=e9958c689bef4d468d81dc93c8d3479f) performs unified securities-market regulation. | [SFC](https://www.sfc.hk/EN/about-the-sfc/our-role/) is the independent statutory securities and futures regulator. | `finance_csrc` now snapshots three exact official publication-list pages and `finance_sfc` snapshots the press-release RSS as raw hashed evidence. Both are local-analysis/no-redistribution and have no semantic decoder yet; never use either as a quote or issuer-filing feed. |
| Frontline listing supervision and issuer disclosure | [SSE announcements](https://www.sse.com.cn/disclosure/listedinfo/announcement/?PC=PC), [SZSE listed-company notices](https://www.szse.cn/disclosure/notice/company/index.html), and [BSE announcements](https://www.bse.cn/disclosure/announcement.html) are venue-owned surfaces. [CNINFO](https://www.cninfo.com.cn/?lang=zh) identifies itself as SZSE's statutory disclosure platform and also presents multi-venue material. | SFC states that [SEHK is the frontline regulator](https://www.sfc.hk/en/Regulatory-functions/Corporates), and [HKEXnews](https://www2.hkexnews.hk/Global/Exchange/About-Us?sc_lang=en) is the centralized issuer filing/disclosure site. | `finance_cninfo` and `finance_hkex` now capture exact already-known PDFs as original-byte hashed evidence. HKEXnews is direct exchange evidence. CNINFO remains repository evidence until discovery metadata or decoded identity proves a venue-issued document; aggregation cannot invent or erase SSE/SZSE/BSE provenance. Public search and fixture-rights review remain open. |
| Accounting standards and electronic taxonomy | The Ministry of Finance publishes [CAS standards](https://kjs.mof.gov.cn/zt/kjzzss/kuaijizhunzeshishi/) and the [CAS XBRL general taxonomy](https://kjs.mof.gov.cn/zhengcefabu/201010/t20101020_343461.htm). CSRC separately owns public-company disclosure requirements. | [HKICPA issues HKFRS](https://www.hkicpa.org.hk/en/Standards-setting/Standards/Members-Handbook-and-Due-Process/Due-Process/Financial-reporting); HKEX [Appendix D2](https://en-rules.hkex.com.hk/rulebook/disclosure-financial-information-0) also permits specified issuers to report under IFRS or CASBE. | Separate standard/taxonomy registries from document retrieval. Every HK fact retains its actual standard; no global HKFRS default. Taxonomy copyright and redistribution require review. |
| Trading calendars and effective rules | SSE/SZSE/BSE publish their own rules and dated notices; for example, the [SSE trading rules](https://www.sse.com.cn/lawandrules/sselawsrules2025/stocks/exchange/c/c_20260424_10816482.shtml) define sessions while reserving exchange ownership/licensing of market data. | HKEX publishes calendars/rules and separates Hong Kong securities, derivatives, and Stock Connect schedules; the [Stock Connect calendar](https://www.hkex.com.hk/mutual-market/stock-connect/reference-materials/trading-hour%2C-trading-and-settlement-calendar?sc_lang=en) is a distinct product. | Versioned venue/security datasets with exact effective dates. Do not derive holiday sets from civil calendars or substitute Stock Connect days for local HK days. |
| Production dissemination and market-data feeds | Public issuer pages are distinct from any accepted machine feed; quote/history remains a named licensed-vendor decision. | HKEX offers a versioned [Issuer Information Feed](https://www.hkex.com.hk/Services/Market-Data-Services/Infrastructure/Issuer-Information-feed-Service-%28IIS%29?sc_lang=en) and separately documents [market-data licensing](https://www.hkex.com.hk/Services/Market-Data-Services/Real-Time-Data-Services/Data-Licensing?sc_lang=en). | Public filing retrieval, production issuer feed, and quote/history feed are three capabilities with separate licence, pacing, cache, and redistribution policy. |

The first provider-backed vertical slice should therefore start with official
issuer documents, not pretend that a Company Facts equivalent exists. A later
structured-financial adapter may consume an accepted XBRL instance/taxonomy or
decode source reports losslessly, but must expose its actual coverage rather
than claim SEC-style whole-entity facts.

Plugin users can inspect the same binding map without reading this ledger:
`/cn-sources` or `cn_authorities` for mainland sources, and `/hk-sources` or
`hk_authorities` for Hong Kong. These views are configuration-only and perform
no network access.

### Authority-first source of truth and resilient secondary channels

For disclosures, rules, calendars, taxonomies, and regulatory notices, the
canonical local source of truth is an immutable authority-originated artifact,
not a normalized vendor row. A stored evidence record must retain:

1. the issuing authority or exchange and its exact document/dataset identity;
2. the retrieval route (`Direct` or a named `Via(adapter)` route);
3. publication/as-of and retrieval times, original media and language;
4. bounded byte/page/redirect facts and a content hash;
5. licence, attribution, local-use, and redistribution state.

“Source of truth” means the bytes and provenance used to reproduce our result.
It does not mean that publicly viewable material may be bulk republished, nor
does it turn issuer pages into an exchange-grade real-time quote feed.

We will also use the sound operational strategies seen in
[TradingAgents-CN](https://github.com/hsliuping/TradingAgents-CN/tree/74783e8817d6cf6de29867880631cc555153f36b):

- cache-first reads with explicit stale/offline behavior;
- a track-owned, configurable provider priority list;
- first-success fallback only across semantically compatible channels;
- separate records per source instead of overwriting one provider with another;
- the actual selected source returned with the result.

The current upstream code routes mainland data across
[Tushare, AKShare, and BaoStock](https://github.com/hsliuping/TradingAgents-CN/blob/74783e8817d6cf6de29867880631cc555153f36b/tradingagents/dataflows/data_source_manager.py#L88-L171),
and HK paths across
[AKShare and yfinance with configurable fallbacks](https://github.com/hsliuping/TradingAgents-CN/blob/74783e8817d6cf6de29867880631cc555153f36b/tradingagents/dataflows/interface.py#L1748-L1909).
Its AKShare paths ultimately use channels such as Eastmoney and Sina; the
underlying origin must therefore be recorded as, for example,
`Eastmoney via AKShare`, not flattened to `AKShare`. A repository-wide review
at that pinned commit found no direct CSRC, CNINFO, SSE/SZSE/BSE, SFC, or
HKEXnews adapter. Those vendor routes are useful secondary observations and
discovery/cross-check candidates, not substitutes for official artifacts.

Candidate quote/history channels remain blocked until their product terms and
semantics are approved. [Tushare documents token/points and endpoint-specific
permissions](https://tushare.pro/document/1?doc_id=108), while AKShare exposes
wrappers whose origin varies by function. BaoStock, yfinance, Finnhub, and Alpha
Vantage are likewise separate contracts. The upstream repository also has
[mixed licensing](https://github.com/hsliuping/TradingAgents-CN/blob/74783e8817d6cf6de29867880631cc555153f36b/LICENSE),
so this work reuses architecture ideas, not source code from its proprietary
application/frontend areas.

The first implemented strategy profiles are deliberately narrow:

| Track/family | Priority | Canonical origin | Route and rule |
| --- | --- | --- | --- |
| `cn` exact issuer document | 1 | SSE, SZSE, or BSE | `Direct`; cache-first local snapshot. |
| `cn` same exact issuer document | 2 | CNINFO repository until venue origin is independently proven; then retain the proven SSE, SZSE, or BSE origin | `Via("CNINFO")`; accept only the requested exact identity, never a merely similar/latest document, and never promote a caller hint to origin evidence. |
| `hk` exact issuer document | 1 | HKEXnews | `Direct`; no vendor filing fallback is approved. |

`VerifiedReadOnly + LocalAnalysisOnly` is an operational profile, not a
redistribution grant. The first exact-PDF adapters now provide the allowlisted
request plan, response status/media/byte/PDF-signature validation, bounded
binary transport and hashing, pacing, cancellation, retry, and outage failure.
The shared real-parser stage now adds independent page/time budgets and walks
every page from the same hashed response. Approved semantic fixtures,
text-layer/OCR policy, discovery/search contracts, and venue/issuer identity
proofs are still required before normalized filing tools.

Raw authority acquisition is now implemented for both UTF-8 pages/feeds and
exact known PDFs. `finance_authority_snapshot` constructs no-redistribution
hashed evidence; `finance_csrc`, `finance_sfc`, `finance_cninfo`, and
`finance_hkex` own their exact track, authority/repository, host, path, media,
request, retry, and pacing contracts. Semantic HTML/RSS/PDF decoders,
text-layer/OCR decisions, and public document search remain separate gaps.
`finance_pdf` structurally inspects and walks the exact known PDFs without
rendering or extracting them. `/cn-sources` and `/hk-sources` expose
`public_read_only_snapshot` only for these exact records; other public search
pages remain unreviewed.

### 4. Promote only genuinely global concepts

China-specific concepts stay in the China packages until another track proves
they are generic. For example, `Board`, `ST`, an unlock class, and a Chinese
statement scope do not belong in `finance_core`.

Provider-neutral deficiencies should be fixed once:

- The canonical observation wire contract now has an explicit optional local
  timezone in schema v2, with schema-v1 backward decoding.
- `finance_evidence` now provides typed licence/redistribution, unit,
  quality/restatement, as-of ordering, and track compatibility. The legacy
  guardrail string tool remains a compatibility surface, not the canonical
  calculation gate.
- A `cn` result may wrap `finance_core.Observation(a)` with track and venue
  context, but must not replace the canonical observation.
- Original units such as `元`, `万元`, `亿元`, `股`, and `万股` are stored in an
  exact China accounting value alongside a validated multiplier and normalized
  `finance_core` unit. `CustomUnit` alone is not enough to prove scale.
- Forward/backward adjustment definitions, base dates, factor inputs, and
  rounding are China-domain data. `ProviderAdjusted` remains the canonical
  summary only after those details are retained.
- The generic calendar engine already supports multiple sessions and overrides.
  China adds authoritative datasets, coverage/version evidence, auctions,
  midday breaks, exceptional notices, and security-specific settlement rules;
  it does not fork date arithmetic.

### 5. Current-component reuse audit

| Existing component | Reuse as-is | Required adjustment or China layer |
| --- | --- | --- |
| `pi_gleam` | Commands, typed tools/decoders, cancellation, UI/headless behavior, lifecycle events, and raw escape hatch. | Add binding contracts with Chinese Unicode, bilingual details, and the common track-result schema only when a real plugin exercises them. No China-specific host API is currently needed. |
| `finance_core` | Exact decimals, CNY/HKD/USD currencies, money, MIC/symbol/ID validation, ambiguity, source refs, sessions, adjustments, and schema-v2 canonical observations with optional timezone. | Keep board, code-with-venue, dated aliases/relationships, Chinese reported scale, and effective rule state in market packages. The current core `Listing` alone does not prove these facts. |
| `finance_track` / `finance_evidence` | Closed track contexts, visible profile defaults, explicit legs, and typed source/unit/quality/time/licence compatibility. | CN/HK plugins add venue, board, scale, and effective-rule checks but cannot weaken or flatten the shared gate. |
| `finance_listing` | Track/MIC listing keys, effective intervals, aliases, and evidence-backed relationship storage. | `finance_cn_identity` owns mainland venues/boards/classes and A/B/H/CDR endpoint laws; `finance_hk_identity` owns HK code and board laws. |
| `finance_http` | Bounded requests/responses, cancellation, retry decisions, `Retry-After`, rate state, pools, scheduling, cache/cassette types, and redaction. | Each China source defines its own auth, status mapping, retry safety, rate buckets, concurrency, pagination, cache, licence, and outage policy. Do not share SEC/OpenFIGI runtime settings. |
| `finance_provider_strategy` | Track-isolated channel order, cache policy mapping, first-compatible-success resolution, trace retention, and separate origin/retrieval route. | CN/HK packages define their own channels and exact contracts. Candidate vendors cannot enter an executable plan until approved; no shared default priority silently spans tracks. |
| `finance_authority_snapshot` | Shared raw UTF-8 capture, exact status/media/byte validation, local-only evidence hashing, origin/path allowlisting, cancellation-aware admission, retry, and pooling. | `finance_csrc` and `finance_sfc` own distinct tracks, authorities, endpoints, media policies, caller identity, and future semantic decoders. PDF/ZIP acquisition needs a separate bounded binary extension. |
| `finance_calendar` | Civil-date arithmetic, multiple sessions per day, overrides, business days, joint calendars, and bounded schedule scans; `finance_market_calendar` adds source/licence/version/coverage. | Supply authoritative versioned SSE/SZSE/BSE/HKEX fixtures, auctions/midday breaks, exceptional notices, and typed security-specific settlement policy through the isolated CN/HK packages. |
| `finance_provenance` | Content-addressed evidence, source fingerprints, licences/redistribution, assumptions, manifests, redaction, and bounded verification plans. | Define original-document, correction, attachment, translation, normalized fact, and model-summary parentage. Chinese source text remains the controlling evidence node. |
| `finance_table` | Typed cells/units, annotations, omission budgets, and deterministic Markdown/CSV/JSON. | Test Chinese headings/content and original-unit annotations. Add terminal display-width policy only if a real TUI surface proves grapheme count insufficient; do not hide units behind locale formatting. |
| `finance_math` | Exact formula trees, explicit scale/rounding, finite analytics, cash-flow/fixed-income primitives, and zero/missing errors. | China domain constructors must resolve inputs and prove entity, period, statement scope, filing context, unit/scale, and source coherence before evaluation. |
| `finance_series` | Ordered/missing-aware series, exact/as-of alignment, resampling, returns, windows, paths, and analytics. | Use China calendar bucketing and explicit suspension gaps. Wrap the generic OHLCV `Bar` when amount, turnover, previous close, limit state, and adjustment-factor evidence are required. |
| `finance_testkit` | Frozen clocks, scripted transports, cassette helpers, decoder conformance, seeded data, fixture metadata, and secret-leak assertions. | `finance_cn_testkit` and `finance_hk_testkit` now provide isolated seed-stable market catalogues; add licence-reviewed provider fixtures and source schema-drift cases without merging the two tracks. |
| `finance_openfigi` | Optional FIGI/ISIN corroboration and an example of bounded identity execution. | Never make it the mainland security master, infer MIC/board from its exchange label, or invent an as-of date that OpenFIGI did not provide. |
| `finance_sec` | Architectural pattern: source adapter below Pi, raw evidence before named metrics, preserve-all resolution, pure derivation proofs, and conservative bounded runtime. | Reuse no SEC endpoints, pacing, CIK identity, taxonomies/tags, filing classes, company-facts coverage claims, or statement-period bands. China mappings and report laws require their own evidence. |
| Existing F0/F1 plugins | Thin shell, deterministic search, setup capability, guardrail, raw-fact, and normalized-metric patterns. | Assign SEC and current US-fundamental results to `us`; register separate `cn_*` and `hk_*` surfaces; extract generic pure policy only when two consumers need it; never import or wrap another plugin's Pi shell. |
| `lifecycle` / `safety_gate` examples | Typed reducers, restore/corruption handling, event cleanup, confirmation, and headless-safe UI patterns. | Apply the patterns to watches/brokers with namespaced China state and explicit persistence; the example plugin packages are not production dependencies. |

## Shared-foundation gap ledger

| ID | State | Gap and action | Exit evidence |
| --- | --- | --- | --- |
| CN-F01 | Done | Define and version provider-neutral `finance_track` and its JSON details contract. The only track IDs are `cn`, `hk`, and `us`; include venue, board, timezone, source language, provider, entitlement, and limitations without importing market rules. | Schema-v1 round trips cover `cn`, `hk`, and `us`; unknown tracks, mismatched scopes, duplicate metadata, and board-without-venue are rejected; US binding results carry the context. |
| CN-F02 | Done | Evolve canonical observation JSON to preserve local timezone while retaining strict backward decoding. Keep track context outside the provider-neutral observation. | Schema v2 encodes optional IANA timezone; v1 decodes to unknown timezone; unknown versions fail; `Observation.map` preserves the field. |
| CN-F03 | Done | `finance_evidence` composes canonical observations, provenance evidence/licences, and track legs. It validates unit, quality/restatement, as-of and retrieval order, availability, source/evidence identity, redistribution intent, and track policy below Pi. | Laws cover compatible observations, accumulated incompatibilities, default mixed-track rejection, explicit multi-track retention, and fail-closed redistribution. |
| CN-F04 | Done | `finance_listing` plus `finance_cn_identity` own track/MIC keys, board, exact code-with-venue, effective aliases, A/B/H/CDR relationships, explicit currency/status, and ambiguity. OpenFIGI is not imported or treated as authoritative. | Synthetic ambiguous `000001`, historical Chinese name intervals, typed relationship reconstruction/accessors, A/H track preservation, and no first-candidate selection. |
| CN-F05 | Decision | Approve authoritative identity datasets and their access/redistribution terms for SSE, SZSE, and BSE. Record update cadence, effective dates, and historical coverage. | Signed-off provider matrix and redistributable deterministic fixtures. |
| CN-F06 | Waiting | `finance_market_calendar` and `finance_cn_calendar` implement the pure source/licence/version/coverage contract over injected sessions and overrides. Synthetic tests cover auctions, midday closure, exceptional days, SSE/SZSE/BSE scope, and coverage edges. Authoritative fixtures wait on CN-F07. | Add licence-reviewed Shanghai/Shenzhen/Beijing calendar fixtures and holiday/exception tests; outside coverage already fails closed. |
| CN-F07 | Decision | Official venue ownership is verified: SSE/SZSE/BSE publish their own calendars, trading rules, and exceptional notices, while HKEX owns distinct HK and Stock Connect schedules. Approve supported retrieval, version capture, update cadence, and fixture/redistribution rights. Unknown dates outside coverage stay unknown. | Access/licence review plus a coverage and update policy in each package README. |
| CN-F08 | Waiting | `finance_market_rules`, `finance_cn_rules`, and sibling `finance_hk_rules` implement source/evidence-labelled effective rules selected by exact listing, board, share class, security type, status, and date. Unknown and conflicting records fail closed; no authoritative constants are invented. | Remaining exit: licence-reviewed dated rule tables across real regime changes, with price-limit, tick, lot, suspension, settlement, and eligibility invariants. |
| CN-F09 | Open | `finance_market_documents`/`finance_market_accounting` plus isolated CN/HK packages preserve original text/title, correction/translation and attachment identity, exact numeric lexeme, reported scale, normalized unit, consolidated/parent scope, standard, report class, audit state, restatement, and duplicates. Strict schema-v1 wire round trips now preserve those values and reject future versions or numeric JSON coercion. Issuer/document mismatch fails. | Remaining exit: source-specific decoder round trips against accepted payload contracts, real fixtures, and audited ambiguity-preserving mapping registries. |
| CN-F10 | Decision | Authority ownership is verified in the source map and encoded in typed, user-visible isolated registries. Complete the operational provider/licence matrix per data family: supported access/product, identity, calendar/rules, quote/history, disclosures/attachments, structured financials, corporate data, indices/classifications, regulatory data, macro, and HK/Connect. Public visibility is not API or redistribution permission. | Accepted endpoints/products, auth, terms, bounds, pacing, cache, outage, and fixture policy; runtime source views must then advance only the matching access records. |
| CN-F11 | Decision | Select the first named licensed quote/history provider covering Shanghai, Shenzhen, and Beijing, including B-share currencies and entitlement metadata. No implementation starts on an undocumented fallback. | Provider decision record and adapter README design. |
| CN-F12 | Waiting | Synthetic laws and isolated `finance_cn_testkit`/`finance_hk_testkit` seed-stable catalogues cover code/venue and board ambiguity, leading zeroes, Unicode names/titles/text, CN special-treatment/suspension, B-share currency, HK listing-specific lots, `万元`/`万股`/`港幣千元`, correction/parallel-language lineage, CAS/HKFRS/IFRS distinctions, accounting duplicates, and midday sessions. | Remaining exit is provider-dependent: licence-labelled real contract fixtures and source schema-drift cases for each accepted adapter. |
| CN-F13 | Open | Architecture gates all new pure packages against Pi/Promise/FFI, forbids CN/HK shells from importing SEC or one another's market packages, and binding-tests exact setup/status tracks and hidden sibling-tool substitution. | Remaining exit: binding assertions for every future market-specific CN/HK result and deliberate provider/calendar/rules fallback failures as those shells arrive. |
| CN-F14 | Done | `finance_track_capabilities` and `finance_market_authorities` power isolated `cn_setup` and `hk_setup` shells. Setup, source, capabilities, authorities, and provider-health commands/tools expose exact track contexts/defaults, verified official links, and honest access/provider blocks. | Headless/UI results visibly say CN/HK; authority IDs are track-prefixed; unknown providers remain unknown; public search never becomes provider health; sibling and SEC tools cannot satisfy state; unit, binding, artifact, and Pi-load gates cover both. |
| CN-F15 | Done | `finance_document_attachment` defines pure fail-closed acceptance for exact media allowlists, byte/page limits, redirect/cross-host policy, content hash, cancellation, archives, and OCR. Accepted metadata composes the shared document attachment identity. | Malformed, oversized, missing-page, redirected, cross-host, cancelled, archive, OCR, unsupported-media, missing-hash, and distinct-hash tests pass; no effect or unsafe unpacking is hidden in the package. |
| CN-F16 | Waiting | Design track-scoped persistence only when watch/broker work begins. Reuse typed lifecycle reducers, but choose storage ownership, migration, fork/new behavior, compaction, reload cleanup, and corruption recovery first. | Deterministic lifecycle sequences and no cross-track state-key collision. |
| CN-F17 | Done | Make the active `cn`/`hk`/`us` navigation track continuously visible and explicitly switchable. Show typed currency/timezone defaults and a non-secret agent contact without changing source-evidence semantics. | TUI statusline, strict slash/tool switching, active-branch restore, malformed-state fallback, headless structured status, track-change events, and all-three-track binding tests. |
| CN-F18 | Done | Add a provider-neutral strategy for the reusable parts of TradingAgents-CN's approach without weakening provenance: cache-first mode, configurable ordered channels, first-compatible-success fallback, per-source records, exact semantic contracts, visible attempt traces, and origin/route separation. Add isolated CN and HK disclosure profiles. | Pure laws reject candidate, cross-track, duplicate, trust-inverted, out-of-order, post-success, and semantically incompatible fallback. CN keeps venue origin through CNINFO only for an independently proven exact venue identity; otherwise CNINFO remains repository provenance. HK remains HKEXnews-only. |
| CN-F19 | Open (text, exact-PDF, and structural-inspection slices done) | `finance_authority_snapshot`, `finance_csrc`, and `finance_sfc` implement caller-identified bounded UTF-8 authority acquisition. `finance_cninfo` and `finance_hkex` add exact-known-document PDF acquisition through byte-preserving transport with SHA-256/base64 and signature validation. `finance_pdf` performs bounded real-parser page inspection tied to the same artifact hash. Remaining: public discovery/search, text-layer/OCR policy, exact issuer/venue identity proof, direct SSE/SZSE/BSE adapters, ZIP inspection if justified, and semantic fixture decoders. | Implemented slices have exact allowlisted GETs, one-per-second pacing, cancellation, bounded retry/pool/queue/body/parser time/pages, strict status/media/length/signature/page-walk checks, source hashes, parser/version receipts, no-redistribution evidence, README contracts, and offline fixtures. Exit still requires approved fixture rights plus fixture-tested normalized records; CNINFO repository provenance must not be promoted to venue origin without evidence. |

The repository policy currently names `bun run test:live:sec` as the sole live
provider lane. CN development therefore uses fixtures and mocked Bun contracts.
A future live-CN lane requires an explicit repository-policy change and must be
read-only, caller-identified, host/method allowlisted, and request-budgeted; it
must never enter `bun run test` implicitly.

## Plugin delivery ledger

Every row below assumes the common track context, canonical observations,
provider adapter rules, and offline test gates above. “Reuse” means source-level
composition of finance libraries, not reuse of another track's tool name or
provider assumptions.

### CN0 — identity, time, and rules

| Plugin | State | Reuse | China-owned work and exit proof |
| --- | --- | --- | --- |
| `pi_finance_track_status` (shared navigation prerequisite) | Done | `finance_track` profile/context, Pi statusline, typed lifecycle restoration, event bus. | `/finance-track`, `/cn-track`, `/hk-track`, `/us-track`, `finance_track_status`, and `finance_track_switch`; branch-scoped choice and visible currency/timezone/contact; switching never changes market evidence. |
| `pi_cn_setup` (track prerequisite) | Done | `pi_gleam`, `finance_track`, shared pure capability/authority contracts, and a CN-owned registry. | `/cn-setup`, `/cn-sources`, `cn_capabilities`, `cn_authorities`, and `cn_provider_health`; CNY/`Asia/Shanghai`/`zh-CN`; official owners visible, operational families blocked; unknown providers stay unknown and sibling/SEC tools cannot satisfy CN. |
| `pi_hk_setup` (isolated sibling prerequisite) | Done | The same pure contracts with an independent HK registry, Pi shell, and context. | `/hk-setup`, `/hk-sources`, `hk_capabilities`, `hk_authorities`, and `hk_provider_health`; HKD/`Asia/Hong_Kong`/`zh-HK`; public HKEXnews and contracted IIS/market data remain distinct; no CN/SEC substitution. |
| `pi_cn_guardrails` (conditional track prerequisite) | Open | `finance_evidence`, canonical observations, provenance policies, and future CN rules/accounting scale checks. | Create a user-facing `cn_*` policy only if China-specific checks merit a tool. Otherwise keep the stricter policy internal and do not create an empty shell. |
| `pi_cn_stock_symbols` | Waiting on CN-F05 | `finance_cn_identity`, `finance_listing`, canonical resolution, HTTP/testkit patterns; OpenFIGI only as corroboration. | Search Chinese full/short names and exact codes; require venue/board for resolution; retain effective historical names and A/B/H/CDR links; deterministic `NoMatch/Unique/Ambiguous`; official source version/as-of visible. |
| `pi_cn_market_calendar` | Waiting on CN-F07 | `finance_cn_calendar`, bounded dataset queries, generic sessions/business days/overrides/joint calendars. | Add authoritative SSE/SZSE/BSE fixtures and security-type settlement policy; `Asia/Shanghai`, midday gaps, overrides, and outside-coverage errors already have synthetic laws. |
| `pi_cn_stock_rules` | Waiting on authoritative rule sources | `finance_market_rules`, `finance_cn_rules`, exact decimals, identity, provenance, and strict effective selection. | Inject licence-reviewed dated board/security/status tables for tick size, lots, price limits, ST/delisting risk, suspension, eligibility, settlement, and order constraints. Return source/effective interval; reject universal 10% logic. |

CN0 graduates only when the same `000001` input can remain ambiguous, an
explicit venue resolves deterministically, a midday timestamp is not reported
as continuous trading, and a rule lookup proves the exact dated rule source.

### CN1 — first primary-research slice

| Plugin | State | Reuse | China-owned work and exit proof |
| --- | --- | --- | --- |
| `pi_cn_stock_quote` | Decision: CN-F11, then Waiting on CN0 | `Observation`, money/currency, market session, `finance_http`, calendar/rules, table/testkit. | Named-provider quote schema for A/B/Beijing listings. Preserve CNY, USD, or HKD as the listing dictates; bid/ask/last/previous close, provider-published vs calculated limits, suspension, session, timestamp, delay, entitlement, and stale state. A calculated limit requires an exact previous close and effective rule. |
| `pi_cn_stock_history` | Decision: CN-F11, then Waiting on CN0 | `finance_series`, exact returns, calendar injection, canonical adjustment summary. | Daily/intraday OHLCV plus amount/turnover where defined; explicit suspension/missing gaps; raw, forward, and backward adjustment methods retain factors, corporate-action inputs, base date, formula, and rounding. Never equate provider methods by label alone. |
| `pi_cn_stock_announcements` | Waiting on CN-F09/F10 | `finance_http`, `finance_document_attachment`, provenance evidence/manifests, bounded tables, cancellation. | Documented CNInfo/exchange access; Chinese title and original link; venue, issuer/listing, announcement class, publish time, report period, document/version/correction relationship, attachment identity, and bounded retrieval/search. Translation is optional derived evidence. |
| `pi_cn_stock_financials` | Waiting on announcements/accounting source | Exact decimals, observations, calendar arithmetic, `finance_math`, provenance, table; reuse SEC's raw-then-normalized architecture only. | First expose lossless raw statement lines, then an executable audited registry. Preserve Chinese line label/code, exact token, reported unit/scale, normalized unit, standard, consolidated/parent scope, report type, audit/restatement state, filing identity, and duplicates. Resolve each metric independently; no SEC tags, SEC duration bands, or hidden restatement priority. |
| `pi_cn_stock_research_report` | Waiting on all CN1 inputs | Provenance manifests, tables, exact formulas, the named China adapters/domain packages. | Bounded company brief with visible mainland track, identity and source dates; primary disclosures separated from licensed/vendor metrics and model interpretation; original Chinese titles retained; bilingual mode labelled; every missing capability stated; reproducible evidence roots exported. |

CN1 acceptance remains the vertical-slice gate: resolve one unambiguous SSE,
SZSE, or BSE listing; return a source/freshness/entitlement-labelled quote;
retrieve an original disclosure; normalize a small audited set of statement
fields without losing scale or scope; and render a cited brief with original
Chinese titles. All tests use fixtures or mocked provider contracts.

### CN2 — mainland market structure

| Plugin | State | Reuse | China-owned work and exit proof |
| --- | --- | --- | --- |
| `pi_cn_stock_corporate_actions` | Waiting on announcements/history | Exact decimals, observations, adjustment, provenance, pure event transitions. | Typed cash/stock dividend, bonus, capitalization, rights, split, merger, name/code, and ex-right/ex-dividend events. Keep plan, approval, record, ex, payment, completion, cancellation, and correction dates distinct. Produce adjustment inputs, not an unexplained factor. |
| `pi_cn_stock_earnings` | Waiting on announcements/financials | Document evidence, calendar, observations, series. | Separate reporting appointments, performance forecasts, preliminary/express results, periodic reports, audits, revisions, and corrections. Build an explicit revision chain; do not upgrade preliminary evidence into audited financials. |
| `pi_cn_stock_share_structure` | Waiting on financials/actions | Exact values, dated observations, identity relationships. | Dated total/tradable/restricted denominators and A/B/H classes; preserve disclosed category labels and scope. Historical ratios must use the denominator effective at that date. |
| `pi_cn_stock_shareholders` | Waiting on financials/share structure | Series/as-of joins, tables, provenance. | Distinguish top shareholders from top tradable holders, disclosed ownership from beneficial-owner interpretation, and report date from publication date. Comparable changes require the same holder identity, scope, and denominator. |
| `pi_cn_stock_restricted_shares` | Waiting on actions/share structure | Calendar, exact math, event state, observations. | Planned versus actual unlocks, holder, eligible quantity, effective float denominator, source announcement, changes/cancellations, and assumption-labelled impact estimates. Revalidate quantities after capital changes. |
| `pi_cn_stock_pledges` | Waiting on share structure/announcements | Dated state transitions, exact percentages, provenance. | Pledge, release, freeze, and correction events with holder identity and dated denominator. Concentration is a declared formula; controlling-shareholder or beneficial-owner claims need explicit evidence. |
| `pi_cn_stock_insiders` | Waiting on announcements/rules | Identity, dated rules, event state, provenance. | Actor role effective dates; plan versus executed increase/reduction; quantities, price ranges, completion/cancellation, and source. Describe short-swing context from the effective rule without making an unsupported legal conclusion. |
| `pi_cn_stock_public_info` | Waiting on exchange source contracts | Tables, exact amounts, provenance, identity. | Preserve exchange-published unusual-movement reasons and Chinese seat/institution labels. Never infer the customer or beneficial owner behind a branch label. Keep trade date and publication date separate. |
| `pi_cn_stock_margin` | Waiting on market source contract/rules | Series, exact units, calendar, observations. | Effective eligibility plus separate financing/securities-lending balances and flows; exchange definitions and unit changes retained. Aggregates state universe and as-of cutoff. |
| `pi_cn_stock_block_trades` | Waiting on market source contract | Exact money/quantity, series, tables, provenance. | Price, quantity, amount, discount/premium reference price and timestamp, and original buyer/seller branch labels. Provider omission remains unknown; no actor inference. |
| `pi_cn_stock_connect` | Waiting on mainland identity/calendar and HKEX | Joint calendars, identity relationships, effective-dated state, provenance. | Northbound/southbound scope, explicit mainland and Hong Kong legs, eligibility/buy-only/sell-only intervals, published quotas where available, and cross-list mappings. Each leg retains its track, currency, venue, and calendar. |

### CN3 — market analysis and monitoring

| Plugin | State | Reuse | China-owned work and exit proof |
| --- | --- | --- | --- |
| `pi_cn_market_snapshot` | Waiting on quote/history/rules/indices | Series aggregation, exact totals, tables, calendar/as-of checks. | State the eligible universe and common cutoff; break out venue/board, breadth, turnover, limit-up/down, suspension, and liquidity. Reject mixed entitlements or asynchronously sampled totals presented as one instant. |
| `pi_cn_stock_screener` | Waiting on CN1/CN2 | Series/as-of alignment, exact formulas, tables, deterministic query plans. | Reproducible universe and filters for board, ST/rule state, liquidity, capitalization, financials, valuation, growth, dividends, and constraints. Every field exposes date/source/missing policy; no silent inner-join survivorship. |
| `pi_cn_stock_indices` | Waiting on index source/licence decision | Identity, series, actions, provenance, tables. | Keep CSI/SSE/SZSE/BSE index provider, methodology/version, constituent effective interval, weight date, rebalance announcement, and licensed redistribution state. Index identity is not a display name. |
| `pi_cn_stock_sector_concept` | Waiting on taxonomy source decisions | Identity resolution, dated observations, tables. | Model each CSRC, exchange, or vendor taxonomy with provider, version, level, code, effective date, and methodology. Never union competing industries/concepts as one classification. |
| `pi_cn_stock_valuation` | Waiting on quote/financials/share structure | `finance_math` formulas/solvers, observations, as-of joins, provenance. | China-aware comps/DCF with share class, listing currency, dated tradable/total shares, A/H relationships, source FX/rates, forecast versus reported inputs, formula trees, and sensitivities. Reject stale/cross-currency/cross-period combinations. |
| `pi_cn_stock_filing_diff` | Waiting on document identity/retrieval | Provenance, deterministic text/table representations, bounded work plans. | Compare linked disclosure versions with Chinese section/table identity, corrected/restated class, normalization method, omissions, and exact document hashes. Model summaries are labelled derived interpretation, not source text. |
| `pi_cn_stock_watch` | Waiting on CN-F16 and watched domains | Pure lifecycle reducers, cancellation, bounded scheduling, evidence manifests. | Track-scoped lists and cursors for announcements, forecasts, unlocks, pledges, suspensions, rule status, and Connect. Polls are bounded/idempotent; reload/fork/new/compaction/shutdown semantics are tested; no hidden background work in headless mode. |
| `pi_cn_regulatory` | Waiting on CSRC/exchange source contracts | Document model, identity, provenance, dated state. | Separate rule, inquiry, supervision, discipline, and enforcement evidence; publication/effective/expiry dates; targeted entity and authority; original Chinese control; labelled translations and summaries. |
| `pi_cn_macro` | Waiting on NBS/PBOC/SAFE contracts | Series, exact decimals, frequency/calendar, provenance, tables. | Separate source adapters and series identities; preserve original frequency, unit/scale, seasonal adjustment, release time, vintage/revision chain, publication calendar, and missing periods. Never overwrite a vintage. |
| `pi_cn_policy_monitor` | Waiting on regulatory/macro documents and CN-F16 | Document provenance, lifecycle reducer, bounded watches. | Dated policy documents by issuing authority and topic; publication/effective/supersession relationships; company relevance as a labelled derived classification; original Chinese retained. |

### CN4 — breadth and sensitive capabilities

| Plugin | State | Reuse | China-owned work and exit proof |
| --- | --- | --- | --- |
| `pi_cn_ipo` | Waiting on disclosure/regulatory maturity | Document identity, event state, calendar, provenance. | Board-specific pipeline and registration stages; prospectus/inquiry versions, issuer/intermediary identities, offer/listing calendar, result, lockups, withdrawals, and corrections. Do not collapse exchange review and CSRC registration. |
| `pi_cn_convertible_bonds` | Waiting on rules/actions/announcements | Core bond identity, `finance_math` fixed-income/formulas, calendar, series. | Exact conversion terms, changing conversion price, trigger observation windows, redemption/put state, dilution, parity/premium inputs, suspension, and source announcements. Trigger state is proven from dated observations, not a prose guess. |
| `pi_cn_funds_etf` | Waiting on licensed fund data | Instrument identity, series, calendar, math, provenance. | Distinguish exchange price, NAV, IOPV, and their timestamps; creations/redemptions, distributions, benchmark, holdings entitlement, tracking method, and listing rules. Missing licensed holdings stay unavailable. |
| `pi_cn_mutual_funds` | Waiting on licensed fund data | Fund identity, series/performance, tables, documents. | Share classes, manager/tenure, fees, benchmarks/versions, portfolio report dates and lag, distributions, terminated funds, and survivorship policy. No current-universe backfill into history. |
| `pi_hk_stock` | Waiting on HKEX/provider decisions and mainland maturity | `finance_hk_identity`, `finance_hk_calendar`, shared bounded foundations, the exact-artifact `finance_hkex` boundary, and explicit identity/Connect bridges. | Separate `hk` track, `Asia/Hong_Kong`, HKD, board lots, authoritative HK sessions, data entitlement, normalized disclosures/actions, and explicit A/H comparison. Never reuse mainland session/lot/limit defaults. |
| `pi_cn_broker_readonly` | Waiting until research track is mature | Core money/identity, lifecycle reducers, HTTP security, reconciliation patterns. | One named broker; opaque credentials/account IDs, read-only capability, positions/orders/cash/settlement with provider timestamps and entitlements, bounded pagination, redaction, reconciliation, and track-scoped state. No generic broker fallback. |
| `pi_cn_broker_paper` | Waiting on readonly and a separate threat/runbook review | Exact order values, China calendar/rules, idempotent state machine, confirmation/audit patterns. | Provider-specific simulation enforcing venue, board, lots, settlement, suspension, limits, and sessions; draft/confirm/submit are explicit; duplicate calls do not duplicate orders; stale/unknown rules fail closed. It never exposes live submission. |

Beijing coverage is a cross-cutting CN4 hardening gate, not a late data label.
Every relevant identity, rule, quote/history, disclosure, financial, market
structure, screening, and report contract must include BSE fixtures before the
track claims Shanghai/Shenzhen/Beijing coverage.

## Recommended execution order

1. **Provider and UX arbitration.** Use the completed CN-F01 contract; complete
   CN-F05, CN-F07, CN-F10, and CN-F11. Record source rights before checking
   provider payloads into the repository.
2. **Canonical gaps.** CN-F02/CN-F03 and the local generator portion of CN-F12
   are complete. Extend CN-F13 as real shells arrive; add the remaining CN-F12
   provider fixtures only after the matching source contract is accepted.
3. **CN0 domain.** Identity, bounded calendar contracts, effective-rule laws,
   and isolated CN/HK setup are implemented. Approve authoritative identity,
   calendar, and rule inputs, then build the thin symbol/calendar/rule shells.
4. **Disclosure adapter.** Use the completed authority-first strategy and
   attachment acceptance policy; build bounded official document
   metadata/retrieval and announcement tools with original Chinese preserved.
5. **Market adapter.** Review Tushare/AKShare-underlying/BaoStock and other
   candidate contracts, then build approved named quote/history packages above
   `finance_http`. Configure priority per track and exact semantic contract;
   never substitute stale daily data for realtime.
6. **Raw accounting before named metrics.** Reuse the implemented lossless
   document/fact domains; add source-specific exact decoders and expose raw
   lines, then populate a small audited executable mapping registry and strict
   resolution/derivation laws. Do not begin with a wide normalized schema.
7. **First report.** Compose only proven CN1 capabilities and export a
   reproducibility manifest. Missing sources remain visible.
8. **Market structure, then analytics.** Build dated denominators/events before
   screening or valuation so later formulas consume resolved coherent inputs.
9. **Watches after storage/lifecycle design.** Monitoring does not precede
   idempotent cursors, bounded polling, and tested cleanup.
10. **Breadth and brokers last.** Harden BSE, then funds/convertibles/IPO/HK.
    Read-only broker work precedes paper simulation; no live-trading plugin is
    part of this ledger.

## First accounting slice

The China analogue of the SEC fundamental slice should be deliberately small.
Select metrics only after representative SSE, SZSE, and BSE filings prove the
source mapping. A reasonable candidate set is revenue/operating revenue, net
profit with attribution explicit, total assets, cash and cash equivalents,
operating cash flow, reported capital expenditure only if a source line can be
defined without reconstruction, and weighted-average shares only when the
statement provides the needed scope.

For every mapping, callers must see:

- accepted original line codes and Chinese labels, with no hidden precedence;
- accounting standard/version and statement name;
- instant versus duration and exact start/end/report period;
- original numeric lexeme, reported unit/scale, and normalized unit;
- consolidated versus parent scope and attribution;
- preliminary/express/periodic/audited/corrected evidence class;
- document/version identity, publication date, audit state, and duplicates;
- preserve-all default plus explicit correction/restatement/document selection;
- expression tree, ordered named inputs, assumptions, output unit/scale, and all
  source leaves for every derived metric.

China formulas consume uniquely resolved inputs and re-prove same entity,
statement scope, period, report/document context, unit, and accounting standard.
An annual/YTD or Q4 law must be derived from audited China reporting shapes and
source evidence; the SEC day bands and `fy`/`fp` behavior are not reusable facts.

## Definition of Experimental for every CN plugin

A plugin stays Designing or Implementing until all applicable items pass:

- Its README covers user stories/non-goals; tools/commands; types; provider,
  authentication, entitlements, licence, cache, pacing, retry, outage and
  redistribution; schemas/units/time; permissions/secrets; lifecycle; tests;
  compatibility; and Hex build/distribution.
- Network access lives in one or more reusable non-Pi provider packages using
  `finance_http`; no plugin-local fetch/retry/rate/cache/redaction stack exists.
- External data is decoded once at a typed boundary. Exact numeric lexemes,
  Chinese text, missing/null, duplicates, unknown enums, and schema evolution
  have fixtures.
- Domain modules import no Pi, Promise, FFI, ambient environment, or clock.
- Request/response/page/work budgets and cancellation are explicit. No real
  sleeps, ambient credentials, live requests, or mutable shared caches occur in
  unit tests.
- Tool details contain exactly one `cn`, `hk`, or `us` track context—or explicit
  separately labelled legs for a cross-track result—plus source,
  as-of/retrieval time, timezone, unit/scale, quality, entitlement/licence, and
  limitations relevant to the result.
- The command/tool never guesses a venue, board, currency, period, adjustment,
  restatement, classification, document version, or provider fallback.
- Pure unit/law/transition tests, provider decoder fixtures, Bun binding
  contracts, artifact default-export tests, Pi-load smoke tests, architecture
  tests, and `bun run test` pass.
- Hex contents include permitted source/FFI/fixtures only; local path
  dependencies are replaced before publication.

## Track-isolation acceptance scenarios

- `/cn-symbol 000001` cannot choose between venue/listing candidates without
  evidence; `security_resolve` is not called as a hidden fallback.
- A mainland tool result always says `cn`; an HK result always says `hk`; a US
  result always says `us`. Stock Connect/A-H output labels both legs
  independently.
- A Shanghai B share may be USD and a Shenzhen B share may be HKD; neither is
  coerced to CNY or inferred from the six-digit code alone.
- A timestamp during the mainland midday break is not labelled regular trading.
- A price-limit computation identifies listing, board/status, effective rule,
  previous close, tick/rounding method, and source date.
- A forward-adjusted history cannot be compared with another provider's
  “forward-adjusted” history until formulas, factors, and base dates match.
- A Chinese disclosure result retains its original title and content hash.
  Translation and model summary are separate derived nodes.
- A financial trend cannot mix parent and consolidated statements, reported
  scales, evidence classes, or silently selected corrections.
- A screener/report does not mix asynchronous provider snapshots or silently
  drop suspended/missing securities.
- China setup lists `cn` companion capabilities only; missing adapters remain
  missing even when track-neutral/OpenFIGI, `hk`, or `us`/SEC tools are
  installed.
- Track-scoped persisted state survives the declared lifecycle and never
  appears in another `cn`, `hk`, or `us` watch/account namespace.

## Decisions that block implementation

| Decision | Needed by | Required record |
| --- | --- | --- |
| Authoritative SSE/SZSE/BSE security master and historical-name coverage | CN0 identity | Endpoint/product, access method, effective-date semantics, update cadence, licence, redistribution, fixture rights. |
| Authoritative calendar and exceptional-session datasets | CN0 calendar/rules | Date coverage, publication/update process, correction handling, licence, provenance. |
| First licensed quote/history vendor | CN1 market data and most later analytics | Venue/security coverage, latency/entitlement tiers, historical/adjustment definitions, quotas, auth, cache and redistribution. |
| Official documented disclosure/attachment access | CN1 announcements/financials | Search/download contract, bounds, pagination, document identity/versioning, terms and fixture permission. |
| Structured financial source versus first-party document parsing | CN1 financials | Coverage, exact-number behavior, statement scope, taxonomy/line identity, correction history, licence and validation plan. |
| Bilingual default | CN1 report and document tools | Chinese-only versus bilingual-by-request; translation provider/model, labelling, caching and evidence lineage. Chinese original always controls. |
| Watch persistence owner | CN3 watch/policy and brokers | User-owned path/database/session state, schema versioning, fork/new behavior, deletion/export, encryption/redaction, corruption recovery. |
| HK market-data/disclosure provider and Stock Connect source | CN2 Connect/CN4 HK | Mainland/HK boundaries, joint calendars, board lots, eligibility effective dates, entitlements and redistribution. |

These decisions change which adapters can be implemented, but not the order of
safety: identity and dated rules; primary evidence; normalized accounting;
analysis; monitoring; read-only broker access; paper simulation.
