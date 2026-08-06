# China track delivery ledger

Snapshot: **2026-08-06**

This ledger turns the China section of `ROADMAP.md` into an implementation
sequence. It is a plan, dependency record, and acceptance checklist. It does not
create plugin placeholders: a `plugins/<name>/` directory is created only when
that plugin enters Designing with a complete local `README.md`.

The goal is parity of engineering quality with the current OpenFIGI/SEC slices,
not a translation of US-equity behavior. Provider-neutral internals should be
reused aggressively. Mainland-China identity, market rules, accounting,
disclosures, language, data rights, and provider contracts remain China-owned.

## Status at this snapshot

- CN/HK now have Experimental, isolated identity/disclosure discovery, official
  2026 calendars, public-web quote/raw-history and narrow raw/normalized/
  derived fundamental slices, plus dated official-rule slices behind
  `cn_setup`/`hk_setup`. Official filing-linked statement semantics, broader
  accounting, market structure, and research/report capabilities remain open.
- All three isolated OHLCV shells are now Experimental. `finance_ohlcv`
  supplies shared exact validation/composition; `us_stock_ohlcv` uses bounded
  credentialed Alpaca IEX/SIP bars, while `cn_stock_ohlcv` and
  `hk_stock_ohlcv` reuse bounded Eastmoney raw history without importing the US
  adapter. The separate US receipt compositor now implements strict 2026
  calendar/listing/status/provider gap classification; CN/HK counterparts,
  authority-owned identity/status evidence, and provider-unit proof remain open.
- The US quote counterpart is now Experimental: `finance_quote` supplies the
  exact provider-neutral envelope and `us_stock_quote` uses the same bounded
  Alpaca runtime with explicit IEX/SIP selection. It preserves bid/ask market
  codes and exact tokens while keeping freshness, session, latency, and size
  semantics unknown.
- The US calendar counterpart is now Experimental: `finance_us_calendar` and
  `us_market_calendar` preserve separate NYSE/XNYS and Nasdaq/XNAS official
  2026 schedules, including 1:00 p.m. Eastern early closes. The acquisition
  result remains uncomposed, while `us_ohlcv_gaps` can now join copied calendar,
  listing, status, and complete provider receipts without mutating it.
- The US effective-rule counterpart is now Experimental: `finance_us_rules`
  and `us_market_rules` preserve exact listing/venue/date scope for the current
  NYSE/Nasdaq regular displayed-quote increment and expose the SEC half-cent
  compliance boundary. Broader market-structure rules remain outside it.
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
- A production licensed quote/history provider, authoritative security-master
  inputs, later calendar refresh rights, and official/filing-linked structured
  financial source are still decisions. The bounded `finance_eastmoney`
  public-web adapter is approved only for Experimental read-only local analysis
  with unknown service level, licence, and redistribution; its vendor statement
  slice is not that official or production decision.
- `cn` always means mainland China. `hk` is separate and is joined to `cn` only
  by explicit A/H or Stock Connect tools. Existing SEC and US-fundamental
  slices belong to `us`.

With all matching implemented tools installed, the current status receipt is:

| Track | `src` evidence maturity | `feat` installed breadth | Covered feature families |
| --- | ---: | ---: | --- |
| `cn` | 65% | 100% | navigation, source registry, security identity, market calendar, effective rules, quote/history, disclosure discovery, raw fundamentals, normalized fundamentals, reproducible derivations |
| `hk` | 70% | 100% | navigation, source registry, security identity, market calendar, effective rules, quote/history, disclosure discovery, raw fundamentals, normalized fundamentals, reproducible derivations |
| `us` | 80% | 100% | navigation, source registry, security identity, market calendar, effective rules, quote/history, disclosure discovery, raw fundamentals, normalized fundamentals, reproducible derivations |

This closes every requirement in the current three-track installed-feature
denominator when each track's matching tools are loaded; US reaches 100% with
the paired Alpaca quote/OHLCV, calendar, and current-rule tools. The independent
calendar and rules tools are not an OHLCV gap join. Installed breadth does not
claim complete statement/rule depth, authoritative identity, market-data
entitlement, or 85% operational source maturity. The
structured status receipt exposes the denominator, contributions, every source
criterion, missing requirements, and critical gaps so a user or LLM can audit
the percentages instead of trusting the compact statusline.

## Three-track fundamentals checkpoint

Fundamentals progress is measured through three independently auditable
surfaces: lossless provider facts, executable normalization, and reproducible
derivations. Having all three surfaces means that a narrow vertical slice is
usable; it does not imply that every track has the same statement, metric,
history, or official-source depth.

| Track | Raw provider facts | Executable normalization | Reproducible derivations | Current depth and next gaps |
| --- | --- | --- | --- | --- |
| `cn` | Done for the narrow income-statement slice: `cn_financial_statement` preserves exact Eastmoney row tokens, codes, Chinese labels, period end, notice time, and caller-proven currency. | Done for revenue and parent-attributable net income: `cn_stock_fundamental` exposes the accepted codes, unit/period policy, attribution, and ambiguity failure. | Done for exact net margin: `cn_stock_fundamental_metric` exposes the expression, half-even rounding/scale, and both source leaves. | Experimental vendor slice. Next depth: official filing/document linkage, exact period start, accounting standard, scope, audit/restatement/correction state, full statements, broader mappings, and comparable trends. |
| `hk` | Done for the narrow income-statement slice: `hk_financial_statement` strictly joins Eastmoney report context to exact line rows and retains currency, standard, scope, report type, and period. | Done for revenue and shareholder-attributable profit: `hk_stock_fundamental` exposes the accepted codes/labels and rejects missing or ambiguous lines. | Done for exact net margin: `hk_stock_fundamental_metric` exposes the expression, half-even rounding/scale, and both source leaves. | Experimental vendor slice with richer report context than CN. Next depth: official HKEX filing linkage, correction/restatement and audit evidence, full statements, broader mappings, and comparable trends. |
| `us` | Done through SEC company-facts/concept retrieval: `sec_xbrl_facts` preserves exact values, taxonomy/tag, unit, periods, accession, form/amendment, filed date, frame, and duplicates. | Done through `stock_fundamental`, `stock_fundamental_period`, and the executable definition registry for seven initial metrics with explicit selection policy. | Done for multi-input metrics, derived Q4, trends, growth, direct/bridged/composed TTM, exact formulas, filing coherence, and complete source leaves. | Current depth baseline. Company-facts still excludes custom taxonomy, dimensions/segments, and complete-filing coverage; generic `stock_fundamental*` names still need a documented `us_*` migration or alias policy. |

The CN/HK checkpoint therefore closes the same raw/normalized/derived workflow
families used by US, while the final column keeps their substantial depth and
authority gaps visible. The statusline `feat` score measures those installed
families; the separate `src` receipt and this ledger carry source maturity and
semantic depth.

## Current plugin batch — OHLCV and US quote

OHLCV is the next implementation batch. Existing CN/HK history tools are a
provider acquisition seam, not the completed batch: they preserve bounded raw
daily rows but do not yet establish a shared, calendar-aware OHLCV contract.

| Track | Current input | Planned isolated plugin/tool surface | Reuse | Track-owned work before exit |
| --- | --- | --- | --- | --- |
| `cn` | `cn_stock_history`: raw, unadjusted daily Eastmoney rows for explicit SSE/SZSE/BSE identities. | `plugins/cn_ohlcv/` with `cn_stock_ohlcv` is implemented. | `finance_ohlcv`, `finance_eastmoney`, canonical observations, exact series/math, bounded HTTP, and isolated mocked conformance tests. | The first slice requires coherent caller-declared venue/board/share-class/currency, retains exact provider rows and raw adjustment, and labels the date-only ordering anchor plus unknown volume unit/session/calendar/rights. Remaining: independently proven listing identity, composed official calendar/status, suspension classification, amount/turnover units, and permitted real fixtures. |
| `hk` | `hk_stock_history`: raw, unadjusted daily Eastmoney rows for exact five-digit HK identities and declared listing currency. | `plugins/hk_ohlcv/` with `hk_stock_ohlcv` is implemented. | The same provider-neutral OHLCV/series/calendar/math contracts and HK Eastmoney adapter behind an independent shell. | The first slice requires caller-declared board/share-class/currency, retains exact provider rows and raw adjustment, and labels date-only/unknown volume/session/calendar/rights semantics. Remaining: independently proven HKEX identity/currency, composed official calendar/half-day/status evidence, suspension classification, amount/turnover units, and permitted real fixtures. |
| `us` | Experimental `finance_market_alpaca` raw daily bars for one exact symbol/as-of key and explicit `iex` or `sip` feed. | `plugins/us_ohlcv/` with `us_stock_ohlcv` and the separate network-free `plugins/us_ohlcv_gaps/` compositor are implemented. | `finance_ohlcv`, `finance_us_ohlcv`, `finance_us_calendar`, `finance_listing`, `finance_series`, canonical observations, bounded HTTP, and isolated mocked conformance tests; no CN/HK provider assumptions. | Acquisition retains exact numeric lexemes, USD/share units, `America/New_York`, provider-defined daily session/raw-adjustment semantics, bounded pagination, request IDs, subscription-scoped entitlement, and no redistribution grant. `us_ohlcv_gap_assessment` can now classify copied 2026 receipts only with exact venue/listing scope, complete pagination, canonical Alpaca source identity, and explicit status evidence for every absent open listing date. Remaining: authority-owned listing/status adapters, cryptographic receipt integrity, corporate actions/adjustments, broader feed/product rights, later calendars, and permitted real fixtures. |

The first OHLCV slice is daily and read-only. Every result must retain exact
source values plus normalized open/high/low/close/volume, interval and session
timezone, currency and volume unit, adjustment method, retrieval/as-of time,
entitlement, completeness, and ordered/deduplicated bar evidence. A suspension,
market closure, provider omission, and unavailable history are distinct states;
the implementation must not synthesize bars or silently fill gaps. Intraday,
licensed realtime, and corporate-action-adjusted series remain later explicit
slices unless the accepted provider contract proves them.

Each track gets its own plugin, tool prefix, context, provider policy, and
fixtures. The three shells may compose the same pure bar validation,
calendar-alignment, return, and rendering components, but may not import one
another or relabel one track's evidence. Because quote/history is already one
of the ten statusline feature families for CN/HK, this batch improves depth and
cross-track parity; it does not inflate `feat` merely by adding another tool.
The US OHLCV slice alone likewise leaves `feat` at 70%. The separate
`us_stock_quote` counterpart now completes that existing `quotes_history`
requirement when both tools are active, raising US `feat` to 80% without
claiming effective rules, freshness, or full market-data readiness. Loading the
independent `us_market_calendar` covers the calendar family and raises breadth
to 90%, but does not silently change the OHLCV result contract. The independent
`us_market_rules` surface closes the final feature family and raises installed
breadth to 100%; it likewise does not classify OHLCV gaps or imply broad rule
coverage. The separate `us_ohlcv_gaps` compositor adds bounded classification
depth without changing that score or the original provider receipt.

The accepted US provider decision is Alpaca Market Data for this Experimental
credential-holder slice. IEX and SIP remain separate explicit feeds; a
successful request proves only the caller's access to that request. The plugin
does not grant redistribution, choose a default feed, infer a listing venue,
or treat the Alpaca symbol/as-of mapping as an authoritative security master.
Only raw daily USD/share bars are accepted. Alpaca-supported split, dividend,
spin-off, combined adjustments, intraday/realtime products, and other feeds
require later reviewed contracts.

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
  this was the initial injected-data seam before the official 2026 slice.
- **2026-08-05 — active-track statusline:** added
  `finance_track_status`. It shows track/currency/timezone, versioned source
  evidence maturity, installation-aware end-user feature coverage, and agent
  contact; restores branch-scoped choice; exposes headless status/switch tools;
  and emits a strict track-change event. Detailed receipts retain every source
  criterion and feature gap. Switching navigation never relabels evidence,
  swaps providers/calendars, borrows sibling-track coverage, or merges
  market-owned state.
- **2026-08-05 — effective market rules:** added shared
  `finance_market_rules` plus isolated `finance_cn_rules` and
  `finance_hk_rules`. Exact listing, board, share class, security type, status,
  and effective date are selection dimensions; missing and overlapping rules
  fail closed. This was the initial synthetic-data seam; the scoped official
  profiles added later in this log now populate it without weakening selection.
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
- **2026-08-05 — operational multi-channel coverage:** compared the pinned
  TradingAgents-CN provider, completeness, consistency, HK fallback, and
  multi-analyst paths in detail. Added `finance_provider_strategy/coverage` so
  each declared family advances at 85% union coverage without a perfection
  gate. Critical anchors remain mandatory, same-origin mirrors count once,
  every missing requirement stays visible, and a track picture cannot average
  a weak family into a strong one. CN and HK issuer-disclosure strategies now
  expose separate track-scoped policies.
- **2026-08-05 — official disclosure discovery:** extended `finance_cninfo`
  with its public security catalogue and bounded repeatable-read announcement
  query, and extended `finance_hkex` with its public current-security JSONP and
  title-search page. Added isolated `cn_disclosures`/`hk_disclosures` shells.
  They resolve source-owned organization/stock IDs before disclosure lookup,
  retain exact PDF identities and source fields, disclose HK initial-page
  truncation, and permit only read-only local analysis. With setup and both
  discovery tools active, feature coverage advances from 20% to 40% for each
  track; source maturity advances to CN 65% and HK 70%.
- **2026-08-05 — official 2026 market calendars:** added source-reviewed,
  coverage-bounded SSE, SZSE, BSE, and HKEX datasets plus isolated
  `cn_market_calendar`/`hk_market_calendar` shells. Mainland venue selection is
  mandatory; HK preserves every published full closure and all three half-days.
  Both expose exact source/version/coverage/licence/limitations and fail outside
  2026. Later exceptional notices, settlement, Connect, severe-weather state,
  and redistribution remain separate. With setup, discovery, and calendar
  tools active, CN/HK installed feature coverage advances to 50%.
- **2026-08-05 — bounded CN/HK public-web market data:** added reusable
  `finance_eastmoney` request plans, exact quote scaling, raw unadjusted daily
  bar decoding, two bounded runtimes, and isolated `cn_market_data`/
  `hk_market_data` shells. CN requires exact SSE/SZSE/BSE and independently
  proven A-share/CNY scope; HK requires an exact five-digit code and declared
  listing currency. Normal tests mock all fetches. With both quote/history
  tools active, each track advances to 60% installed feature coverage.
- **2026-08-05 — dated official rule profiles and feature parity:** added a
  2026-07-06 mainland established-normal-CNY-equity profile sourced separately
  to SSE, SZSE, and BSE, plus the HKEX minimum-spread Phase 2 profile effective
  2026-08-03. `cn_trading_rules` rejects invalid venue/board pairs and
  exceptional regimes. `hk_trading_rules` supports the reviewed HKD equity
  price bands and requires an issuer-specific board lot plus evidence reference
  instead of assuming 100. With these tools active, CN, HK, and US each report
  70% installed feature breadth. Their category mix and `src` maturity scores
  remain separate, inspectable receipts rather than a parity claim about data
  completeness.
- **2026-08-05 — exact vendor fundamental workflow:** extended the reusable
  `finance_eastmoney` adapter with caller-identified, paced, bounded CN and HK
  financial request plans plus runtime-source numeric token capture. Added
  isolated `cn_fundamentals` and `hk_fundamentals` shells. Each exposes a raw
  income-statement slice, an executable single-code registry for revenue and
  parent/shareholder-attributable net income, and exact net margin with both
  leaves, formula, scale, half-even rounding, period, currency, and context.
  HK strictly joins provider report context to line rows; CN requires caller-
  verified presentation currency and retains unknown start/standard/scope.
  With all three matching tools loaded, CN/HK `feat` reaches 100%; `src` stays
  65%/70% because vendor semantics do not improve official-source maturity.
- **2026-08-05 — three-track fundamentals checkpoint and OHLCV handoff:**
  recorded raw, normalized, and derived fundamentals progress for CN, HK, and
  US in one auditable matrix. Queued the next isolated `cn_ohlcv`, `hk_ohlcv`,
  and `us_ohlcv` batch, reusing the existing CN/HK raw-history acquisition seam
  and provider-neutral series/calendar laws while leaving the US provider and
  rights decision explicit.
- **2026-08-06 — US-first exact OHLCV slice:** added pure `finance_ohlcv`
  validation over canonical observations and ordered series, preserving raw and
  normalized decimals, rejecting invalid bar geometry/reordering/conflicting
  duplicates, collapsing only exact duplicates, and separating provider
  pagination from calendar-gap assessment. Added `finance_market_alpaca` with
  secret-redacted auth, exact JSON numeric-token decoding, raw USD daily plans,
  explicit IEX/SIP selection, symbol-as-of identity, 5 MB/15-second response
  bounds, cancellation, conservative 180/min pacing, ten-page/5,000-bar hard
  ceilings, and offline fixtures. The isolated `us_stock_ohlcv` shell follows
  tokens under caller budgets, retains provider request IDs, timezone/provider-session/
  unit/adjustment/entitlement/rights receipts, and reports calendar gaps as not
  assessed rather than guessing closures, suspensions, omissions, or unavailable
  history. US `feat` stays 70%; CN/HK shells were still open at this checkpoint.
- **2026-08-06 — CN/HK exact OHLCV counterparts:** added isolated
  `cn_stock_ohlcv` and `hk_stock_ohlcv` shells over the existing bounded
  Eastmoney history seam and shared `finance_ohlcv` laws. Both retain every raw
  provider row plus normalized OHLCV, reject invalid geometry/order/conflicting
  dates, use visibly date-derived ordering anchors, keep provider volume units
  unknown, and expose row-budget truncation independently from calendar gaps.
  CN validates coherent caller-declared venue/board/share-class/currency; HK
  requires board/share-class/currency and never assumes HKD. Neither shell
  imports Alpaca, guesses session membership or suspensions, fills bars, or
  changes feature scores.
- **2026-08-06 — US exact latest quote counterpart:** added pure
  `finance_quote`, extended `finance_market_alpaca` with a bounded explicit-feed
  latest-quote plan/decoder, and added isolated `us_stock_quote`. Exact bid/ask
  prices and sizes, source time, exchange/condition/tape codes, request ID,
  selected feed, and source reference survive the boundary. Freshness, latency,
  session, and provider size units remain unknown; IEX is not relabelled SIP and
  no redistribution is granted. With `us_stock_ohlcv` also active, US `feat`
  becomes 80%; missing calendar and effective-rules families remain visible.
- **2026-08-06 — venue-explicit US 2026 calendar:** added isolated
  `finance_us_calendar` and `us_market_calendar` over the shared calendar
  engines. Exact `nyse`/`XNYS` and `nasdaq`/`XNAS` contexts retain their own
  official source references, all ten full closures, the November 27 and
  December 24 1:00 p.m. Eastern early closes, and annual coverage failure.
  The local tool has no environment or network dependency. With it loaded US
  `feat` became 90% at this checkpoint, leaving effective rules as the sole
  feature-family gap; OHLCV missing rows remained unclassified at this
  checkpoint until the later separate evidence-join slice.
- **2026-08-06 — venue-explicit current US quote increments:** added isolated
  `finance_us_rules` and `us_market_rules`. The `us_trading_rules` tool requires
  an exact NYSE/XNYS or Nasdaq/XNAS listing plus the narrowly supported USD NMS
  stock/status/regime/date/price inputs, returns the applicable one-cent or
  sub-dollar increment, and retains both the exchange clause and SEC Release
  34-105656. Coverage ends before the November 2027 compliance boundary;
  unsupported regimes and dates fail closed. The local tool has no environment
  or network dependency. With it loaded US `feat` becomes 100%, without
  changing source maturity or OHLCV completeness.
- **2026-08-06 — strict US OHLCV gap receipt composition:** added isolated
  `finance_us_ohlcv` and the network-free `us_ohlcv_gaps` plugin. The
  `us_ohlcv_gap_assessment` tool joins an exact 2026 NYSE/Nasdaq calendar,
  listing interval, canonical copied Alpaca source identity, complete
  pagination, ordered bar dates, and explicit status receipts. It retains every
  evidence leg while separating closures, suspensions, provider omissions, and
  unavailable history. Truncation, missing evidence, date/order/MIC conflicts,
  and bars on closures fail closed. Supplied receipt identity is not
  cryptographically or authority verified, the acquisition result remains
  unchanged, and this depth slice changes no feature score.
- **2026-08-06 — first US cited source-fact brief:** added the network-free
  `stock_research_report` compositor. `/us-research` queues the explicit agent
  sequence across existing Alpaca/SEC tools; `us_company_brief` validates
  bounded copied receipts, exact symbol/feed/CIK/source coherence, unique
  fundamental facts, and safe filing links before rendering stable evidence
  roots. Missing and ambiguous inputs remain gaps, copied receipt integrity is
  not overstated, and the compositor performs no provider I/O or model-fact
  generation. This adds report depth without changing the ten-family score.
- **2026-08-06 — track-safe watchlist workflow state:** added `watchlist` with
  exact `cn`/`hk`/`us` + namespaced instrument ID + symbol + MIC member keys,
  bounded user notes/HTTPS thesis links/tags, versioned branch event replay,
  exact-key removal, and deterministic snapshots. Resume and inherited forks
  restore only their active branch; malformed events lock mutation. This is
  user-authored workflow state, not identity or market evidence, does not alter
  any track score, and does not yet persist across `/new`.

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
controlling and a switch cannot convert or relabel it. The compact `src` value
is an auditable evidence-maturity score, not a probability that a claim is
true. The separate `feat` value is computed from installed tools against the
versioned track-local end-user denominator. Structured status lists all
criteria, contributions, missing requirements, and critical blockers.

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
  over injected data plus separate venue-owned SSE/SZSE/BSE 2026 schedules;
  later years and exceptional-notice refresh remain explicit version work.
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
| Trading calendars and effective rules | The implemented 2026 schedule separately uses the [SSE annual closure page](https://www.sse.com.cn/disclosure/dealinstruc/closed/), [SZSE notice 深证会〔2025〕481号](https://investor.szse.cn/disclosure/notice/general/t20251222_618087.html), and [BSE notice 北证公告〔2025〕58号](https://www.bse.cn/important_news/200027428.html). The dated standard-equity rule profile separately cites the current [SSE 2026 rules](https://www.sse.com.cn/lawandrules/sselawsrules2025/stocks/exchange/c/c_20260424_10816482.shtml), [SZSE 2026 rules](https://investor.szse.cn/lawrules/rule/trade/t20260424_620190.html), and [BSE 2026 rules](https://www.bse.cn/jygl_list/200028217.html), all effective 2026-07-06. | HKEX [circular CT/075/25](https://www.hkex.com.hk/-/media/HKEX-Market/Services/Circulars-and-Notices/Participant-and-Members-Circulars/SEHK/2025/ce_SEHK_CT_075_2025.pdf) is the implemented 2026 securities schedule. The dated rule slice uses HKEX's [minimum-spread phases](https://www.hkex.com.hk/Services/Trading/Securities/Overview/Trading-Mechanism/Reduction-of-Minimum-Spreads?sc_lang=en) and [issuer-specific board-lot/odd-lot explanation](https://www.hkex.com.hk/Global/Exchange/FAQ/Securities-Market/Trading/Securities-Market-Operations?sc_lang=en&search=Special+Trading+Unit+Market). | Calendar and rule profiles are accepted for bounded read-only local analysis with unknown redistribution. Calendar queries never extrapolate outside 2026. Rules reject dates before their reviewed interval and unsupported regimes/products/currencies/price bands. HK board lots remain caller-evidenced and unverified; settlement, Connect, severe weather, VCM/CAS, and exceptional listing states remain separate. |
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
Its AKShare paths ultimately use channels such as Eastmoney and Sina. AKShare's
[mainland statement adapter](https://github.com/akfamily/akshare/blob/c6f71056f99e45a571c15c29c1b90e55cf410969/akshare/stock_feature/stock_report_em.py)
uses Eastmoney's three wide-row report families, while its
[Hong Kong statement adapter](https://github.com/akfamily/akshare/blob/c6f71056f99e45a571c15c29c1b90e55cf410969/akshare/stock_fundamental/stock_finance_hk_em.py)
uses a report-context index plus standardized line-item families. The
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

#### TradingAgents-CN comparison at the pinned commit

| Concern | How TradingAgents-CN handles it | Decision for `pi-sparkles` |
| --- | --- | --- |
| Research breadth | Runs selectable market, social, news, and fundamentals analysts in sequence, followed by bull/bear and risk debate nodes ([graph setup](https://github.com/hsliuping/TradingAgents-CN/blob/74783e8817d6cf6de29867880631cc555153f36b/tradingagents/graph/setup.py#L66-L216)). | Reuse the family breadth and explicit perspectives. Agent agreement is interpretation, not evidence completeness; every report must consume typed, source-labelled family inputs. |
| Mainland availability | Configures Tushare, AKShare, and BaoStock priorities, then returns the first non-empty successful family result ([app manager](https://github.com/hsliuping/TradingAgents-CN/blob/74783e8817d6cf6de29867880631cc555153f36b/app/services/data_sources/manager.py#L103-L218)). MongoDB/cache may be placed first. | Reuse cache-first, configurable priority, bounded fallback, and the selected-source receipt. Strengthen success to require the exact semantic contract and preserve the complete attempt trace. |
| Hong Kong availability | Uses a configured first-success order across AKShare and yfinance, with optional Finnhub handling, and returns basic fallback identity fields when sources fail ([HK interface](https://github.com/hsliuping/TradingAgents-CN/blob/74783e8817d6cf6de29867880631cc555153f36b/tradingagents/dataflows/interface.py#L1748-L1909)). | Reuse explicit HK routing, but do not turn constructed names, HKD, or `HKG` defaults into provider facts. Missing identity stays missing and the active track remains visibly `hk`. |
| Multi-source persistence | The stock-basics sync records the actual source and uses `(code, source)` when upserting rather than flattening everything to `multi_source` ([sync service](https://github.com/hsliuping/TradingAgents-CN/blob/74783e8817d6cf6de29867880631cc555153f36b/app/services/multi_source_basics_sync_service.py#L179-L285)). | Reuse per-source records. Compose only after identity, time, unit, adjustment, provenance, and entitlement laws pass. |
| Fusion and conflicts | Most family reads are priority fallback, not field-level union. The current consistency checker is explicitly a no-op: it reports confidence `1.0`, declares consistency, and always selects primary data ([checker](https://github.com/hsliuping/TradingAgents-CN/blob/74783e8817d6cf6de29867880631cc555153f36b/app/services/data_sources/data_consistency_checker.py#L1-L48)). | Do not reuse the shortcut. Conflicts remain explicit candidates; no confidence is invented and no primary value wins merely by configuration order. |
| Historical completeness | Estimates expected trading rows as 70% of calendar days, fails below 50%, checks a 10% gap budget, and may fall back to a weekday guess for the latest session ([completeness checker](https://github.com/hsliuping/TradingAgents-CN/blob/74783e8817d6cf6de29867880631cc555153f36b/tradingagents/dataflows/data_completeness_checker.py#L106-L144), [date fallback](https://github.com/hsliuping/TradingAgents-CN/blob/74783e8817d6cf6de29867880631cc555153f36b/tradingagents/dataflows/data_completeness_checker.py#L189-L238)). | Reuse the idea of a measurable gap budget, not the heuristic denominator. Use the authoritative track calendar and a declared per-family requirement universe; dates outside calendar coverage remain unknown. |
| Generated fallback | Mainland fundamentals can fall back to a generated basic report after provider failures ([fallback](https://github.com/hsliuping/TradingAgents-CN/blob/74783e8817d6cf6de29867880631cc555153f36b/tradingagents/dataflows/data_source_manager.py#L1997-L2052)). | A model summary is a derived evidence node, never a substitute observation and never counted toward provider coverage. |

The comparison supports the multi-channel direction, but it also shows why
“85% from several channels” needs a typed denominator. First-success fallback
improves availability; it does not, by itself, fill complementary gaps or prove
agreement.

#### Operational 85% exit gate

The CN/HK tracks do not wait for every conceivable issuer, field, historical
edge, and provider to be perfect. For each implemented capability, define its
supported universe, time window, and versioned requirement denominator, then
apply these rules:

1. Each applicable family must reach at least **8,500 basis points (85%)** from
   the union of accepted channel contributions. Families are assessed
   separately; there is no blended track average.
2. Exact identity/track/venue, source and retrieval route, as-of/retrieval time,
   currency/unit, adjustment or period basis, entitlement, and any
   family-specific document/version context are critical. Missing critical
   anchors block exit even when the numeric score exceeds 85%.
3. Overlapping channels count each requirement once. Direct and mirrored paths
   from one underlying origin form one source group; they do not manufacture
   independence.
4. The family declares its required independent-group count. A sole official
   authority can be enough for its canonical artifact; composite market and
   research pictures normally require two or more origin groups.
5. The permitted remainder stays explicitly missing, unsupported, stale, or
   conflicted. It is not zero-filled, guessed, generated by an agent, or called
   exhaustive.
6. Safety and correctness gates—track isolation, semantic compatibility,
   provenance, licence/entitlement, bounds, cancellation, exact-number laws,
   and deterministic tests—are not reduced to 85%.

`finance_provider_strategy/coverage` implements these laws and returns the
covered set, missing set, critical gaps, source groups, basis-point score, and
per-family/picture readiness. This is the exit policy for CN and HK data
breadth; it is not a claim that the resulting information is complete in an
absolute sense.

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
| `finance_calendar` | Civil-date arithmetic, multiple sessions per day, overrides, business days, joint calendars, and bounded schedule scans; `finance_market_calendar` adds source/licence/version/coverage. | The isolated packages now supply venue-owned 2026 SSE/SZSE/BSE/HKEX and separate NYSE/Nasdaq planned schedules, including auctions/midday breaks or early closes where declared. Add annual refresh, later exceptional notices, and typed security-specific settlement/Connect policy without forking the engine. |
| `finance_ohlcv` / `finance_us_ohlcv` | Exact provider-neutral bars keep pagination and calendar completeness separate; the isolated US layer now composes an exact 2026 venue calendar, listing interval, complete provider receipt, and per-gap status evidence. | Implement independent CN/HK composition packages over their own calendars, listing/status laws, and provider semantics. Do not import or relabel the US classifier, accept truncated receipts, or treat caller evidence as authority verified. |
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

Ledger exits use the operational breadth policy above: 85% in each declared
applicable family with all critical anchors, rather than exhaustive support for
every possible record or provider. Security, semantic correctness, provenance,
rights, track isolation, and deterministic verification remain mandatory.

| ID | State | Gap and action | Exit evidence |
| --- | --- | --- | --- |
| CN-F01 | Done | Define and version provider-neutral `finance_track` and its JSON details contract. The only track IDs are `cn`, `hk`, and `us`; include venue, board, timezone, source language, provider, entitlement, and limitations without importing market rules. | Schema-v1 round trips cover `cn`, `hk`, and `us`; unknown tracks, mismatched scopes, duplicate metadata, and board-without-venue are rejected; US binding results carry the context. |
| CN-F02 | Done | Evolve canonical observation JSON to preserve local timezone while retaining strict backward decoding. Keep track context outside the provider-neutral observation. | Schema v2 encodes optional IANA timezone; v1 decodes to unknown timezone; unknown versions fail; `Observation.map` preserves the field. |
| CN-F03 | Done | `finance_evidence` composes canonical observations, provenance evidence/licences, and track legs. It validates unit, quality/restatement, as-of and retrieval order, availability, source/evidence identity, redistribution intent, and track policy below Pi. | Laws cover compatible observations, accumulated incompatibilities, default mixed-track rejection, explicit multi-track retention, and fail-closed redistribution. |
| CN-F04 | Done | `finance_listing` plus `finance_cn_identity` own track/MIC keys, board, exact code-with-venue, effective aliases, A/B/H/CDR relationships, explicit currency/status, and ambiguity. OpenFIGI is not imported or treated as authoritative. | Synthetic ambiguous `000001`, historical Chinese name intervals, typed relationship reconstruction/accessors, A/H track preservation, and no first-candidate selection. |
| CN-F05 | Open (public candidate catalogue slice done) | `finance_cninfo` now decodes CNINFO's public code/organization/name catalogue for bounded local analysis, and `cn_security_search` preserves `NoMatch/Unique/Ambiguous` candidates. It deliberately leaves venue, board, share class, currency, status, effective dates, and redistribution unknown. Approve authoritative SSE/SZSE/BSE identity datasets and update/history rights. | Remaining exit: venue-owned or contract-approved security-master matrix, effective dates, historical coverage, and permitted deterministic fixtures. |
| CN-F06 | Done for the 2026 planned-schedule slice | `finance_market_calendar` plus isolated CN/HK datasets preserve source/licence/version/coverage over generic sessions and dated overrides. Source-reviewed SSE/SZSE/BSE 2026 closures and sessions remain venue-owned; HKEX circular CT/075/25 preserves every full closure and all three half-days. | Pure and Pi-binding tests prove venue separation, auctions/midday gaps, half-days, exact source/version/coverage, and outside-coverage failure. Later-year versions and exceptional-notice refresh are new dataset work, not fallback. |
| CN-F07 | Done for the 2026 planned-schedule decision | Public exchange notices are accepted for bounded read-only local analysis with `UnknownRedistribution`. Package/plugin READMEs record exact sources, annual coverage, planned-schedule supersession risk, omitted settlement/Connect/severe-weather semantics, and the update boundary. | SSE, SZSE, BSE, and HKEX are separately sourced. No calendar is relabelled across tracks or extrapolated beyond 2026; later exceptional notices must create a new reviewed version. |
| CN-F08 | Done for the scoped current-rule slices | `finance_market_rules`, `finance_cn_rules`, and `finance_hk_rules` retain strict effective selection. Official profiles now cover established normal mainland CNY A-shares from 2026-07-06 and HKEX applicable HKD equity spread bands from 2026-08-03. Invalid board/venue/date/product/currency/price scope fails closed; HK board lots require caller evidence. | Unit/binding/artifact tests prove dated sources, exact clauses, mainland tick/quantity/price-limit differences, HK spread boundaries, and no universal HK lot. Broader IPO/relisting/delisting/ST/suspension/settlement/eligibility/VCM/CAS regimes are explicit later profile versions, not blockers to the declared slice. |
| CN-F09 | Open (narrow vendor decoder/mapping/derivation slice done) | `finance_market_documents`/`finance_market_accounting` plus isolated CN/HK packages preserve the lossless official-document target model. `finance_eastmoney` now separately fixture-tests exact CN/HK numeric-token decoding, preserves raw codes/labels and unknown context, exposes two track-owned single-code mappings, rejects ambiguity, and composes `finance_math` for same-response net margin. | Remaining exit: link facts to official document/version evidence; preserve duplicates/corrections, full scope/standard/audit/restatement/scale; add representative permitted fixtures and broader audited ambiguity-preserving mappings. The vendor slice does not satisfy official filing semantics. |
| CN-F10 | Open (disclosure, calendar, rules, vendor market-data, and narrow vendor-financial slices approved for local analysis) | Authority ownership is verified in typed registries. CNINFO/HKEXnews discovery, venue-owned 2026 calendars, official dated rule profiles, and bounded Eastmoney quote/history/income-statement workflows now have exact sources/routes, contracts, and explicit rights limits. Complete the matrix for authoritative identity, official structured financials, corporate data, indices/classifications, regulatory data, macro, Connect, calendar/rule refresh, and production market data. | Remaining families need accepted endpoints/products, auth, terms, bounds, cache/outage/fixture policy. Runtime views advance only matching active tools; public visibility never becomes redistribution permission. |
| CN-F11 | Done for an Experimental public-web quote/raw-history slice; production vendor remains a Decision | `finance_eastmoney` covers explicit SSE/SZSE/BSE/HK identities with caller identification, allowlisted bounded GETs, cancellation, pacing, exact quote scaling, and raw unadjusted daily-bar lexemes. CN/HK Pi shells remain isolated. | Unit tests and mocked bindings prove secids, exact decimals/lexemes, track/MIC/currency evidence, bounds, and no normal-test network. Latency, SLA, entitlement/redistribution, B-share semantics, adjustment factors, and production licensing remain visible gaps requiring a later named-provider decision. |
| CN-F12 | Open | Synthetic laws and isolated testkits cover market edge cases. Source-reviewed calendar/rule facts and deterministic mocked CNINFO/HKEXnews/Eastmoney contracts now cover the implemented slices without live calls. | Remaining exit is provider-dependent: permitted real fixtures and schema-drift cases for authoritative identity, document semantics, accounting, broader rules, and any production market-data adapter. |
| CN-F13 | Open | Architecture gates pure packages against Pi/Promise/FFI, forbids CN/HK shells from importing SEC or sibling market packages, and binding-tests setup/status, disclosure, calendar, rules, and market-data isolation/failure behavior. | Extend the same gates for every future shell; current implemented vertical slices have binding and artifact coverage. |
| CN-F14 | Done | `finance_track_capabilities` and `finance_market_authorities` power isolated `cn_setup` and `hk_setup` shells. Setup, source, capabilities, authorities, and provider-health commands/tools expose exact track contexts/defaults, verified official links, and honest access/provider blocks. | Headless/UI results visibly say CN/HK; authority IDs are track-prefixed; unknown providers remain unknown; public search never becomes provider health; sibling and SEC tools cannot satisfy state; unit, binding, artifact, and Pi-load gates cover both. |
| CN-F15 | Done | `finance_document_attachment` defines pure fail-closed acceptance for exact media allowlists, byte/page limits, redirect/cross-host policy, content hash, cancellation, archives, and OCR. Accepted metadata composes the shared document attachment identity. | Malformed, oversized, missing-page, redirected, cross-host, cancelled, archive, OCR, unsupported-media, missing-hash, and distinct-hash tests pass; no effect or unsafe unpacking is hidden in the package. |
| CN-F16 | Done for the Experimental branch-scoped watchlist slice; cross-session storage remains open | `watchlist` reuses typed lifecycle/session entries with pure versioned event replay. It chooses active-branch ownership, inherited-fork/resume restoration, fresh state on `/new`, bounded revisions, and fail-closed corruption handling without a database or provider dependency. | Exact track + namespaced instrument ID + symbol + MIC keys prevent cross-track collision; unit/binding tests cover idempotence, exact removal, deterministic snapshots, active-tree restoration, malformed-state locking, and no overwrite. User-owned cross-session storage, migration/import, conflict resolution, and snapshot hashing remain later contracts. |
| CN-F17 | Done | Make the active `cn`/`hk`/`us` navigation track continuously visible and explicitly switchable. Show typed currency/timezone defaults and a non-secret agent contact without changing source-evidence semantics. | TUI statusline, strict slash/tool switching, active-branch restore, malformed-state fallback, headless structured status, track-change events, and all-three-track binding tests. |
| CN-F18 | Done | Add a provider-neutral strategy for the reusable parts of TradingAgents-CN's approach without weakening provenance: cache-first mode, configurable ordered channels, first-compatible-success fallback, per-source records, exact semantic contracts, visible attempt traces, and origin/route separation. Add isolated CN and HK disclosure profiles. | Pure laws reject candidate, cross-track, duplicate, trust-inverted, out-of-order, post-success, and semantically incompatible fallback. CN keeps venue origin through CNINFO only for an independently proven exact venue identity; otherwise CNINFO remains repository provenance. HK remains HKEXnews-only. |
| CN-F19 | Open (discovery, exact-PDF, and structural-inspection slices done) | `finance_authority_snapshot`, `finance_csrc`, and `finance_sfc` implement bounded UTF-8 authority acquisition. `finance_cninfo` and `finance_hkex` now add source-owned security/disclosure discovery plus exact PDF acquisition with SHA-256/base64 and signature validation. `finance_pdf` binds bounded page inspection to the same hash. Remaining: complete HK pagination policy, text-layer/OCR policy, exact CN venue proof, direct SSE/SZSE/BSE adapters, ZIP inspection if justified, and statement-semantic decoders. | Implemented slices have exact hosts/paths, caller identity, one-per-second pacing, cancellation, bounded retry/pool/queue/body/parser time/pages, strict identity/status/media/length/signature/page-walk checks, source hashes, parser receipts, visible truncation/no-redistribution policy, README contracts, and offline fixtures/binding mocks. Exit requires approved fixture rights and at least 85% of the versioned disclosure-family denominator, with all critical identity/provenance/version fields. CNINFO provenance cannot become venue origin without evidence. |
| CN-F20 | Done | Replace the implicit perfection gate with a reusable operational multi-channel coverage contract. Assess every applicable family separately at 85%; count the union once; require family-owned critical anchors and a configured number of underlying source groups; keep all gaps visible; never average families. Apply isolated CN/HK disclosure policies. | Pure laws prove exact 85% readiness, no overlap inflation, same-origin mirror grouping, mandatory critical facts above threshold, cross-track and unknown-requirement rejection, and no averaging of a weak family into a strong track picture. Setup and extension docs expose the policy without marking unapproved providers ready. |
| CN-F21 | Done | Make source quality and feature gaps visible without merging them into one confidence number. Add a versioned, equal-weight source-control credibility receipt and installation-aware end-user feature coverage to the shared statusline. | `src` is explicitly evidence maturity—not truth probability—and critical source controls must be verified. `feat` uses the 85% coverage laws over ten versioned end-user requirements. Structured status exposes criteria/evidence, covered and missing requirements, source groups, and critical gaps. Binding and pure tests prove CN/HK/US display values and that sibling-track tools cannot inflate the active track. The scores expose remaining product gaps; they do not mark those gaps implemented. |
| CN-F22 | Done | Implement the first official-source identity/disclosure discovery vertical slice for both CN and HK. Reuse `finance_http`, source-owned document references, exact track contexts, and setup/status composition; keep two independent shells. | `cn_security_search` + `cn_disclosure_search` use CNINFO catalogue identity before bounded paged POST discovery. `hk_security_search` + `hk_disclosure_search` use pinned-callback JSONP identity before bounded initial-page title discovery. Fixtures reject wrapper/path/identity mismatch; bindings prove caller identification, exact track, request order, Unicode/multi-counter retention, canonical documents, and truncation. No live request enters normal tests. |
| CN-F23 | Done for the 2026 planned-schedule slice | Implement official-source market-calendar tools for both tracks by composing the shared pure engine while keeping separate datasets, tool names, contexts, sources, and limitations. | `cn_market_calendar` requires exact `sse`/`szse`/`bse` and exposes each venue's official 2026 source; `hk_market_calendar` preserves HKEX CT/075/25 closures and half-days. Both fail outside coverage, report unknown redistribution, pass unit/binding/artifact/Pi-load gates, and contribute only to their own track's `market_calendar` feature. |
| CN-F24 | Done for the Experimental public-web slice | Implement reusable bounded Eastmoney quote/history decoding once, then expose independent CN/HK shells and evidence contracts. | `cn_stock_quote`/`cn_stock_history` require exact SSE/SZSE/BSE; `hk_stock_quote`/`hk_stock_history` retain declared currency. Quotes preserve provider scale/time and history preserves raw unadjusted lexemes. Bounds, cancellation, pacing, caller identity, mocked bindings, source limitations, and track-only feature contribution are tested. |
| CN-F25 | Done for the scoped current-rule slices | Implement dated official rules by composing shared pure rule laws while retaining market-specific shapes and separate shells. | `cn_trading_rules` covers exact established-normal mainland board pairs from 2026-07-06. `hk_trading_rules` covers reviewed HKD applicable-equity spread bands from 2026-08-03 and requires issuer-specific board-lot evidence. Both expose sources/clauses/audit limits, fail closed, pass unit/binding/artifact gates, and brought CN/HK installed feature breadth to the then-current US 70% score. |
| CN-F26 | Done for the narrow Experimental vendor-fundamental slice | Reuse Eastmoney transport/runtime and exact-number capture below Pi, then expose separate CN/HK raw, normalized, and derived shells. Keep market mappings/context laws separate while composing the same exact decimal/formula engine. | `cn_financial_statement` requires venue, code, period end, and caller-proven currency; `hk_financial_statement` strictly joins provider context and line responses. Each track has visible two-field mappings and exact source-retaining net margin. Unit/mocked binding/artifact/Pi-load gates cover request bounds, exact tokens, mappings, context coherence, formulas, track isolation, and no normal-test network. This closes the current CN/HK feature denominator at 100% without changing 65%/70% source maturity or claiming official filing completeness. |
| CN-F27 | Implementing — three isolated daily shells plus US receipt composition done | `finance_ohlcv`, `finance_market_alpaca`, and `us_stock_ohlcv` implement the Alpaca slice; independent `cn_stock_ohlcv` and `hk_stock_ohlcv` shells reuse only the Eastmoney history adapter; `finance_us_ohlcv` adds the first strict market-owned evidence join. | Unit, mocked binding, artifact, architecture, and Pi-load gates cover exact raw/normalized values, identity inputs, adjustment, request/row budgets, entitlement/rights limits, deterministic order/exact deduplication, unassessed acquisition results, and bounded US copied-receipt classification. Batch exit still requires CN/HK calendar/status counterparts, authority-owned listing/status proof, CN/HK amount/turnover/volume semantics, cryptographic receipt integrity, and permitted real fixtures. No synthetic bars, cross-track fallback, or feature-score inflation. |
| CN-F28 | Done for the Experimental US latest-quote slice | `finance_quote` and the extended `finance_market_alpaca` adapter back isolated `us_stock_quote`; explicit IEX/SIP selection is required and no CN/HK domain is imported. | Exact quote-token, market-code, auth-redaction, request-bound, mocked binding, artifact, architecture, and readiness tests pass. The paired US quote/OHLCV tools cover `quotes_history` and raised US breadth to 80% at that checkpoint; rules, authoritative identity, real-time proof, stable size semantics, production rights, and permitted live fixtures remain open. |
| CN-F29 | Done for the 2026 planned US calendar slice | `finance_us_calendar` and `us_market_calendar` compose the shared engines behind a separate US contract with exact NYSE/XNYS or Nasdaq/XNAS selection. | Official source references, regular sessions, ten full closures, two 1:00 p.m. Eastern early closes, coverage failure, venue isolation, no environment/network access, binding/artifact/readiness, and architecture gates are covered. US breadth reached 90% at this checkpoint; the later CN-F31 slice now consumes this calendar through a separate receipt compositor. |
| CN-F30 | Done for the scoped current US quote-increment slice | `finance_us_rules` and `us_market_rules` add an isolated effective-rule contract for exact NYSE/XNYS or Nasdaq/XNAS listings without importing CN/HK domains. | Official exchange and SEC sources, the reviewed 2026-06-11 through 2027-10-31 interval, exact one-cent/sub-dollar increments, strict identity/class/status/regime/date/price validation, no environment/network access, binding/artifact/readiness, and architecture gates are covered. US breadth reaches 100%; broader market structure remains open and CN-F31 separately adds bounded OHLCV receipt composition. |
| CN-F31 | Done for the Experimental US copied-receipt gap slice | `finance_us_ohlcv` and `us_ohlcv_gaps` compose the exact 2026 venue calendar, listing interval, canonical Alpaca plan identity, complete pagination, ordered bar dates, and per-gap status evidence without changing the provider batch. | Pure and binding laws prove all four gap states, complete evidence legs, range/order/track/MIC/source validation, no network/environment access, and fail-closed truncation, closure/bar conflicts, irrelevant status, and unexplained open dates. Listing/status authenticity, authority adapters, cryptographic receipt identity, later calendars, CN/HK counterparts, adjustments, and permitted real fixtures remain open. |

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
| `pi_finance_track_status` (shared navigation prerequisite) | Done | `finance_track` profile/context, `finance_provider_strategy` coverage/credibility receipts, Pi statusline, typed lifecycle restoration, event bus. | `/finance-track`, `/cn-track`, `/hk-track`, `/us-track`, `finance_track_status`, and `finance_track_switch`; branch-scoped choice; visible currency/timezone/source maturity/installed feature coverage/contact; detailed gaps; sibling tools cannot contribute; switching never changes market evidence. |
| `pi_cn_setup` (track prerequisite) | Done | `pi_gleam`, `finance_track`, shared pure capability/authority contracts, and a CN-owned registry. | `/cn-setup`, `/cn-sources`, `cn_capabilities`, `cn_authorities`, and `cn_provider_health`; CNY/`Asia/Shanghai`/`zh-CN`; official owners visible, operational families blocked; unknown providers stay unknown and sibling/SEC tools cannot satisfy CN. |
| `pi_hk_setup` (isolated sibling prerequisite) | Done | The same pure contracts with an independent HK registry, Pi shell, and context. | `/hk-setup`, `/hk-sources`, `hk_capabilities`, `hk_authorities`, and `hk_provider_health`; HKD/`Asia/Hong_Kong`/`zh-HK`; public HKEXnews and contracted IIS/market data remain distinct; no CN/SEC substitution. |
| `pi_cn_guardrails` (conditional track prerequisite) | Open | `finance_evidence`, canonical observations, provenance policies, and future CN rules/accounting scale checks. | Create a user-facing `cn_*` policy only if China-specific checks merit a tool. Otherwise keep the stricter policy internal and do not create an empty shell. |
| `pi_cn_stock_symbols` | Implementing (CNINFO candidate lookup done) | `cn_security_search`, `finance_cn_identity`, `finance_listing`, canonical resolution, HTTP/testkit patterns; OpenFIGI only as corroboration. | Current slice searches exact six-digit CNINFO codes and preserves organization candidates. Remaining: Chinese full-name search, authoritative venue/board resolution, effective historical names, A/B/H/CDR links, and source version/as-of. |
| `pi_cn_market_calendar` | Experimental 2026 slice | `finance_cn_calendar`, bounded dataset queries, generic sessions and overrides. | `cn_market_calendar` requires exact SSE/SZSE/BSE, exposes source/version/coverage/licence/limitations, models auctions/midday gap/holidays, and fails outside 2026. Remaining: exceptional-notice refresh, later years, and security-specific settlement/Connect calendars. |
| `pi_hk_market_calendar` | Experimental 2026 slice | `finance_hk_calendar`, the same generic engines behind an isolated HK dataset and shell. | `hk_market_calendar` exposes HKEX CT/075/25 full closures and half-days in `Asia/Hong_Kong`. Remaining: later years, exceptional/severe-weather state, extended-morning/CAS eligibility, settlement, derivatives, and Connect calendars. |
| `pi_cn_stock_rules` | Experimental scoped slice | `finance_market_rules`, `finance_cn_rules`, exact decimals, identity, provenance, and strict effective selection. | `cn_trading_rules` returns official source/clauses/effective interval, tick, minimum/increment evidence, odd-lot exit, and board-specific 10%/20%/30% standard limits for exact established normal CNY A-share pairs from 2026-07-06. It rejects universal logic and exceptional regimes. Remaining profiles cover ST/delisting/IPO/relisting/suspension/settlement/eligibility/order constraints. |
| `pi_hk_stock_rules` | Experimental scoped slice | `finance_market_rules`, `finance_hk_rules`, exact decimals, track context, and source retention. | `hk_trading_rules` returns the HKEX Phase 2 tick for reviewed HKD applicable-equity bands from 2026-08-03. It requires and retains issuer-specific board-lot evidence as caller-supplied/unverified; it rejects non-HKD, excluded products, unsupported price bands, and pre-effective dates. |

CN0 graduates only when the same `000001` input can remain ambiguous, an
explicit venue resolves deterministically, a midday timestamp is not reported
as continuous trading, and a rule lookup proves the exact dated rule source.

### CN1 — first primary-research slice

| Plugin | State | Reuse | China-owned work and exit proof |
| --- | --- | --- | --- |
| `pi_cn_stock_quote` | Experimental public-web slice | `finance_eastmoney`, canonical source/time values, `finance_http`, exact market identity, and mocked contracts. | `cn_stock_quote` returns bounded explicit-SSE/SZSE/BSE vendor values with exact provider scaling/time and visible CNY/A-share evidence preconditions, unknown latency/SLA/rights, and unverified volume semantics. B shares, official suspension/session state, licensed realtime, and calculated effective-rule limits remain later work. |
| `pi_cn_stock_history` | Experimental public-web slice | `finance_eastmoney`, exact source lexemes, bounded HTTP, calendar/rules, and future `finance_series` composition. | `cn_stock_history` preserves bounded raw unadjusted daily OHLC/volume/amount/change/turnover lexemes. Suspension completeness, intraday, corporate actions, and forward/backward adjustment factors/formulas remain explicitly unavailable. |
| `pi_cn_stock_announcements` | Implementing (metadata discovery done) | `cn_disclosure_search`, `finance_http`, exact `finance_cninfo` document references, attachment/provenance packages, cancellation. | Current slice binds code to CNINFO organization ID, pages by date/category, and retains Chinese title/name/type/source time and exact PDF. Remaining: venue proof, verified publish-time meaning, report period/class, correction lineage, content capture/text/OCR, and semantic accounting linkage. |
| `pi_cn_stock_financials` | Experimental narrow vendor slice; official depth open | `finance_eastmoney`, exact decimals, `finance_math`, track context, bounded HTTP; reuse SEC's raw-then-normalized architecture only. | `cn_financial_statement`, `cn_stock_fundamental`, and `cn_stock_fundamental_metric` preserve exact row tokens/codes/Chinese labels, explicit parent attribution, visible mappings, and source-retaining net margin. Remaining: official filing/document linkage, report start/standard/full scope/audit/restatement, duplicates/corrections, full statements, broader mappings and trends. No SEC tags or hidden restatement priority. |
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
| `pi_hk_stock` | Implementing (discovery, calendar, quote/history, narrow fundamentals, and rules slices done) | `hk_security_search`, `hk_disclosure_search`, `hk_stock_quote`, `hk_stock_history`, `hk_financial_statement`, `hk_stock_fundamental`, `hk_stock_fundamental_metric`, `hk_market_calendar`, `hk_trading_rules`, isolated HK domain packages, and shared bounded foundations. | Current slices preserve HKEXnews identity/titles/PDFs, HKEX 2026 sessions/half-days, Eastmoney exact market/fundamental values, strict report-context joins, visible two-field mappings and net-margin leaves, plus HKEX Phase 2 spreads with caller-evidenced issuer lots. Remaining: full disclosure history, official filing-linked accounting, broader statements/mappings/trends, production data rights, authoritative board-lot lookup, exceptional rules, actions, and explicit A/H comparison. Never reuse mainland defaults. |
| `pi_cn_broker_readonly` | Waiting until research track is mature | Core money/identity, lifecycle reducers, HTTP security, reconciliation patterns. | One named broker; opaque credentials/account IDs, read-only capability, positions/orders/cash/settlement with provider timestamps and entitlements, bounded pagination, redaction, reconciliation, and track-scoped state. No generic broker fallback. |
| `pi_cn_broker_paper` | Waiting on readonly and a separate threat/runbook review | Exact order values, China calendar/rules, idempotent state machine, confirmation/audit patterns. | Provider-specific simulation enforcing venue, board, lots, settlement, suspension, limits, and sessions; draft/confirm/submit are explicit; duplicate calls do not duplicate orders; stale/unknown rules fail closed. It never exposes live submission. |

Beijing coverage is a cross-cutting CN4 hardening gate, not a late data label.
Each applicable identity, rule, quote/history, disclosure, financial, market
structure, screening, and report-family denominator includes BSE. That family
must meet the same 85% gate with its BSE critical anchors before the track claims
Shanghai/Shenzhen/Beijing coverage; BSE cannot be omitted from the denominator.

## Recommended execution order

1. **Provider and UX arbitration.** CN-F01/CN-F07 and the Experimental
   public-web CN-F11 slice are complete. Continue CN-F05/CN-F10 and choose any
   production licensed market-data provider separately. Record source rights
   before checking provider payloads into the repository.
2. **Canonical gaps.** CN-F02/CN-F03 and the local generator portion of CN-F12
   are complete. Extend CN-F13 as real shells arrive; add the remaining CN-F12
   provider fixtures only after the matching source contract is accepted.
3. **CN0 domain.** Identity, bounded calendar contracts, official 2026
   calendars, scoped dated official rules, and isolated setup/status shells are
   implemented. Complete authoritative identity and broaden exceptional rule
   profiles only when the declared workflow needs them; never collapse tracks.
4. **Disclosure adapter.** Use the completed authority-first strategy and
   attachment acceptance policy; build bounded official document
   metadata/retrieval and announcement tools with original Chinese preserved.
5. **Market adapter.** The bounded Eastmoney public-web quote/raw-history slice
   is implemented for local analysis. Review Tushare/AKShare-underlying/
   BaoStock and licensed candidates only for broader/production requirements.
   Configure priority per track and exact semantic contracts; never substitute
   stale daily data for realtime.
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

A plugin stays Designing or Implementing until the engineering and safety items
below pass and each declared applicable data family reaches the operational 85%
gate. Experimental does not require exhaustive support for every issuer, field,
date, or provider; the unsupported remainder must be visible in the result and
README.

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
- Each data family publishes its versioned denominator, supported universe and
  window, 85% basis-point assessment, mandatory critical anchors, contributing
  source groups, and uncovered requirements. A generated/model summary never
  counts as provider coverage.
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
| Production licensed quote/history vendor beyond the Experimental Eastmoney slice | Production CN/HK market data and later analytics needing SLA/rights/broader semantics | Venue/security coverage, latency/entitlement tiers, historical/adjustment definitions, quotas, auth, cache and redistribution. The current local-analysis quote/raw-history surface is not blocked by this decision. |
| Official documented disclosure/attachment access | CN1 announcements/financials | Search/download contract, bounds, pagination, document identity/versioning, terms and fixture permission. |
| Structured financial source versus first-party document parsing | CN1 financials | Coverage, exact-number behavior, statement scope, taxonomy/line identity, correction history, licence and validation plan. |
| Bilingual default | CN1 report and document tools | Chinese-only versus bilingual-by-request; translation provider/model, labelling, caching and evidence lineage. Chinese original always controls. |
| Watch persistence owner | CN3 watch/policy and brokers | User-owned path/database/session state, schema versioning, fork/new behavior, deletion/export, encryption/redaction, corruption recovery. |
| HK market-data/disclosure provider and Stock Connect source | CN2 Connect/CN4 HK | Mainland/HK boundaries, joint calendars, board lots, eligibility effective dates, entitlements and redistribution. |

These decisions change which adapters can be implemented, but not the order of
safety: identity and dated rules; primary evidence; normalized accounting;
analysis; monitoring; read-only broker access; paper simulation.
