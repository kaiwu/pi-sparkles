# Pi Plugin Capabilities, Limits, and Business Opportunities

## Purpose

This document defines the practical ceiling of Pi plugins and evaluates the
business opportunities created by that extension model. It complements the
[finance plugin roadmap](ROADMAP.md), which describes proposed packages and a
delivery sequence.

The central conclusion is that Pi plugins have a high technical ceiling. A
plugin is trusted application code embedded in the agent runtime, not a
restricted browser-style extension. The important limits are therefore not
primarily computational. They are lifecycle, trust, model reliability, data
rights, operational safety, distribution, and regulation.

This document is a product and technical assessment, not legal, investment, or
regulatory advice.

## The Pi plugin model

A Pi extension is a JavaScript or TypeScript module loaded into the Pi process.
It receives the extension API and may register tools, commands, event handlers,
and UI behavior. Extensions may use Node.js built-ins and third-party runtime
dependencies.

Pi packages run with the permissions of the user running Pi. They can execute
arbitrary code, read and write accessible files, start subprocesses, and call
remote services. Users must therefore treat installed extensions as trusted
local applications.

The Gleam packages in this repository compile to JavaScript and use
`pi_gleam` as a typed boundary around the Pi API. This improves correctness but
does not create a sandbox. Typed modules cover the normal authoring path, while
`pi/raw` provides dynamic access to Pi surfaces that do not yet have dedicated
Gleam wrappers.

The deeper advantage is architectural. Following
[`FUNCTIONAL_DESIGN.md`](FUNCTIONAL_DESIGN.md), finance calculations, policies,
and workflow transitions are immutable Gleam transformations, while Pi, HTTP,
storage, clocks, and UI live in a narrow effect shell. The same domain core can
be composed into another Gleam application and tested through values and laws
without loading Pi, starting Bun integrations, or mocking ambient globals.

## Capability surface

### Agent tools and external integrations

Plugins can register structured tools callable by the model. A tool can:

- validate typed input;
- query HTTP or WebSocket APIs;
- read or update local data;
- execute subprocesses;
- perform deterministic calculations;
- stream progress and return text or image results;
- reject malformed, stale, unauthorized, or unsafe requests.

This permits integrations with market-data providers, filing systems,
databases, portfolio stores, brokers, internal services, and local analytical
software.

### Agent-loop observation and control

Plugins can subscribe to Pi lifecycle and agent events. Depending on the event,
they can observe or influence:

- project trust decisions;
- resource discovery;
- session start, shutdown, switching, forking, and compaction;
- system prompts and context;
- model and thinking-level selection;
- user input;
- provider requests and responses;
- tool calls, progress updates, and results;
- messages and turn boundaries.

Result-bearing handlers can block a tool call, transform input, replace model
payloads or messages, cancel an action, or contribute context. Plugins can also
override built-in tools when they need custom execution, logging, remote access,
or policy enforcement.

### Commands and user interface

Plugins can expose explicit commands, shortcuts, and flags in addition to
model-callable tools. They can provide:

- notifications and confirmation dialogs;
- selections and text input;
- status indicators and working messages;
- editor content and custom editors;
- persistent widgets;
- custom tool, message, and session-entry rendering;
- advanced terminal UI components in interactive mode.

Explicit commands are important for deterministic workflows. Sensitive actions
should not depend solely on the model deciding to call the correct tool.

### State and workflow orchestration

Plugins can append custom session entries and maintain state in local files or
databases. They can use session events to restore, migrate, or clean up state
across reloads, forks, resumes, compaction, and shutdown.

This supports watchlists, research evidence, theses, policy decisions, report
manifests, and trade journals. State that must outlive or be shared across Pi
sessions is usually better stored in a user-owned database or external service,
with session entries containing stable references and display metadata.

The first Experimental `watchlist` slice chooses session-branch entries for a
bounded local contract. It persists versioned add/update/remove events, replays
only the active branch with contiguous revisions, and locks malformed state.
Every member retains its own `cn`, `hk`, or `us` track plus namespaced instrument
ID, symbol, and MIC. This survives resume and inherited forks, but not `/new`;
cross-session storage remains a separate explicit user-owned capability.

### Model and provider integration

Plugins can inspect available models, change the selected model and thinking
level, and register custom model providers. They can therefore route specialized
workflows to different models or expose an organization's own compatible model
service.

These controls change how models are accessed. They do not change the underlying
model's reasoning quality, context limit, cost, or availability.

## Technical ceilings

### Process lifetime and scheduling

A plugin exists inside a Pi process. Its timers, sockets, file watchers, and
polling tasks stop when that process exits. Pi also requires long-lived resources
to be started only when needed and cleaned up idempotently during session
shutdown.

Consequently, a plugin can poll while a session is active, but a plugin alone is
not a reliable 24-hour monitoring service. Continuous alerts, scheduled morning
briefs, webhook ingestion, and durable job execution require one of:

- an external daemon;
- a system scheduler;
- a hosted service;
- a durable queue and worker system.

The plugin can remain the user interface and control plane for that system.

### Security and policy enforcement

A policy plugin can inspect and block Pi tool calls, but it is not a complete
machine-level security boundary. Other extensions and unguarded tools may still
have access to the filesystem, network, subprocesses, or credentials.

High-risk systems need layered controls:

- restricted and capability-specific credentials;
- read-only API keys by default;
- process or operating-system isolation;
- broker- or provider-side limits;
- deterministic policy evaluation;
- explicit confirmation for sensitive actions;
- append-only audit records outside the mutable session;
- fail-closed behavior when required controls are unavailable.

Prompt instructions are useful guidance, but they are not an authorization
mechanism.

### Model nondeterminism

Adding accurate tools does not guarantee that a model will call the correct
tool, use every relevant input, or interpret every result correctly. Plugins
also cannot eliminate hallucination or make free-form model output reproducible.

The appropriate division of responsibility is:

> The model handles intent, exploration, and synthesis; typed code handles
> facts, units, money, policy, and execution.

Critical calculations should be deterministic. Critical state transitions
should be validated independently of the model. Reports should distinguish
retrieved observations, calculated values, model interpretations, and user
assumptions.

### Model and context limits

Retrieval, compaction, and structured tools can use a model's context more
efficiently, but plugins cannot remove finite context windows, inference errors,
provider latency, token cost, or model outages.

Large document collections therefore need search, indexing, chunk selection,
and evidence management outside the model context. The model should receive a
bounded set of relevant material rather than an unfiltered archive.

### Runtime modes and UI availability

Pi supports interactive TUI, RPC, JSON, and print modes. Full terminal UI
behavior is not available in every mode. In particular, print and JSON modes
cannot provide interactive confirmation, while RPC mode does not support every
TUI-specific component.

Plugins must define non-interactive behavior explicitly. An action that requires
human confirmation must fail closed when an appropriate UI channel is absent.

### Compatibility

Pi is an evolving host API. Typed wrappers and event decoders are coupled to the
versions against which they were tested. The current `pi_gleam` package records
compatibility with Pi `0.83.0`; newer Pi surfaces may initially be reachable only
through `pi/raw`.

A commercial plugin needs:

- a documented Pi compatibility range;
- contract tests at every JavaScript boundary;
- fixtures for event and tool result shapes;
- a release process coordinated with binding changes;
- clear behavior when a host capability is absent.

The host API is therefore a maintenance surface, even when it is not a hard
functional limit.

## Finance-specific ceilings

### Data entitlement and redistribution

A plugin cannot create access rights that a provider has not granted. Publicly
visible data is not automatically licensed for bulk access, commercial use, or
redistribution. Real-time quotes, order books, transcripts, estimates, index
constituents, and some historical datasets may require separate entitlements.

Every finance observation should retain:

- provider and source identifier;
- source URL where applicable;
- observation and retrieval timestamps;
- timezone, currency, and units;
- raw or adjusted status;
- market session;
- delayed or real-time status;
- estimate, revision, and restatement state;
- licence or entitlement metadata when relevant.

Provider choice must be visible configuration, not an undocumented fallback
chain.

The current `us_stock_quote` and `us_stock_ohlcv` slices are concrete first
applications of this rule. Both require the caller to select Alpaca IEX or SIP,
retain exact source numeric lexemes, and report subscription and redistribution
limits. Quote freshness, session, and provider size units remain unknown.
History pagination completeness is separate from market-calendar completeness:
the reviewed `us_market_calendar` now supplies bounded NYSE/Nasdaq planned-day
evidence, while `us_stock_ohlcv` deliberately leaves its acquisition result
uncomposed and absent rows unlabelled. The separate network-free
`us_ohlcv_gap_assessment` compositor can classify copied 2026 receipt fields
only when exact venue/listing scope, complete pagination, the canonical Alpaca
source identity, and one explicit trading-or-suspended receipt per absent open
listing date all agree. Its output retains every evidence leg and labels copied
listing/status receipts unverified; it does not mutate the provider result.
`us_stock_ohlcv` emits the copyable provider projection with ordered page-body
SHA-256 values and one canonical projection digest. The compositor rebuilds and
verifies that digest before classification; a match proves content coherence,
not an Alpaca signature or provider-origin authentication.

The CN and HK OHLCV paths now use the same provider-neutral canonical receipt
and four-state classifier behind isolated market-owned policies. Their
acquisition projections bind exact track identity, Eastmoney source plan,
response bytes/body hash, and ordered dates; network-free compositors verify
them before joining the reviewed 2026 mainland or HKEX calendar plus copied
listing/status evidence. HK retains published half-day dates without treating a
daily row as intraday-completeness proof. Matching SHA-256 is still only content
coherence: Eastmoney is vendor evidence, and caller-supplied listing or status
references do not become exchange authentication.

The HK authority-depth work has started inside the existing `hk_disclosures`
surface instead of adding another shell. Each exact-code lookup is now captured
before decoding as a canonical, SHA-256-bound HKEXnews current-security receipt,
and `hk_disclosure_search` retains the same receipt used to select its stock ID.
It proves code/name/stock-ID membership in the current catalogue at retrieval
and an XHKG source scope. It deliberately leaves board, share class, currency,
listing start/end, and per-session trading status unknown. Therefore it is a
usable authority evidence leg, but not yet the historical listing/status proof
required by an OHLCV gap assessment.

The same plugin now exposes `hk_security_profile` over HKEX's official Full
List of Securities workbook. The adapter captures the original XLSX bytes and
SHA-256 first, then uses the reviewed `finance_archive` boundary to extract only
five required UTF-8 parts under archive/entry/count/total budgets, rejecting
unsafe names, encryption, ZIP64, unsupported compression, length or CRC drift,
and cancellation. The canonical profile receipt preserves the workbook update
date, category/sub-category, derived board only for exact known labels, board
lot, ISIN, eligibility markers, trading currency, RMB counter, and per-entry
CRC evidence. It is a current profile, not an effective listing interval or a
positive session-status assertion, so it remains outside `hk_ohlcv_gaps`.

`hk_recent_listing_event` adds a separate, narrower HKEX authority receipt over
the public "Newly Listed Securities" page. The pure decoder validates the
rolling-current-two-week heading, ten-column table, update date, exact code,
event date, tentative marker, board lot, four eligibility markers, corporate
action, and related code. Only an exact non-tentative `New Listing` row yields
`listingEffectiveFrom`; every other action and every tentative row leaves that
claim null. The page does not supply historical coverage, listing end, or
positive session status, so this is partial authority depth rather than a
complete `hk_ohlcv_gaps` input.

CN uses the same capture-before-decode law under a deliberately weaker source
claim. `cn_disclosures` now retains a canonical SHA-256-bound CNINFO catalogue
receipt in both security and announcement-search results. It binds exact
code/organization/name/category/pinyin candidates from the repository snapshot,
but venue, board, share class, currency, listing interval, and status remain
unknown. CNINFO repository visibility does not become SSE/SZSE/BSE authority,
so this receipt likewise cannot satisfy the CN OHLCV listing/status inputs.

The separate `us_trading_rules` tool supplies only the venue-explicit current
regular displayed-quote increment for a caller-identified NYSE/Nasdaq NMS stock
within its reviewed interval. It retains exchange and SEC sources, has no
environment or runtime network dependency, and does not turn listing, status,
lot, session, halt, or order-handling declarations into provider-verified
facts. It therefore cannot be used to infer OHLCV completeness or execution
eligibility.

### Identity and normalization

Tickers and short security codes are not permanent global identifiers. Correct
research requires venue, listing, share class, effective date, corporate-action
history, and provider mappings.

Normalization is also domain-specific. Financial facts may differ by taxonomy,
unit, fiscal period, consolidated scope, restatement, and accounting standard.
China market support additionally requires board-specific rules, Chinese units,
midday sessions, suspensions, price limits, and time-varying eligibility.

These are not presentation details. They determine whether an observation or
calculation is valid.

### Analytics and valuation

Plugins can calculate returns, risk, valuation, and scenarios deterministically.
They cannot turn assumptions into facts or guarantee predictive accuracy.

Analytical output should expose:

- input observations and their dates;
- formulas and methods;
- missing-data policy;
- currency and adjustment treatment;
- scenario assumptions;
- numerical limitations;
- sensitivity to material inputs.

Single unexplained scores are unsuitable for high-consequence decisions.

### External execution and receipt review

Plugins never place, submit, route, cancel, replace, modify, approve, or
otherwise mutate paper or live orders. They never receive write-capable broker
credentials. The user performs every market action outside Pi.

The supported workflow is evidence-only:

1. The model creates a non-executable, content-bound plan or simulation input.
2. Deterministic policy evaluates instrument, side, quantity, price, session,
   observation freshness, configured limits, and explicit unknowns.
3. Pi displays the exact normalized plan, assumptions and estimated maximum
   cost, then exports a non-executable handoff if requested.
4. The user independently acts or declines outside Pi.
5. A plugin imports caller-owned receipts or reads an explicitly read-only
   account endpoint.
6. Pure transitions reconcile acknowledgement, partial fill, rejection,
   external cancellation, replacement, completion, duplicates and conflicts as
   observed facts only.

Read-only account observation, local simulation, handoff export and receipt
review remain separately scoped capabilities. Cancelling a data subscription
is allowed lifecycle cleanup and never an order operation.

## Distribution and commercial defensibility

Pi packages can be installed from npm, Git, or local paths. Gleam packages are
distributed as source and compiled before Pi loads the resulting JavaScript
artifact. Users must be able to inspect extensions because those extensions run
with full local permissions.

For that reason, a paid local plugin by itself is usually weak intellectual
property. An API wrapper can be copied, replaced, or bypassed. Durable commercial
value is more likely to come from:

- difficult data normalization;
- licensed or proprietary datasets;
- continuous hosted ingestion and monitoring;
- accumulated evidence and workflow state;
- compliance and audit infrastructure;
- enterprise integrations and deployment controls;
- domain expertise, verification, and support.

The plugin is best treated as a trusted client and workflow surface. The durable
service may live behind it.

## Business opportunities

### 1. Evidence-first research and filing intelligence

An evidence-first research product would resolve security identity, retrieve
primary filings, extract a controlled set of facts, identify changes, and
produce cited reports with replay manifests.

Potential users include professional analysts, independent research firms,
investor-relations teams, and sophisticated individual investors.

The opportunity is attractive because it addresses a recurring question:
"What changed, why might it matter, and where is the evidence?" The product can
differentiate through provenance, deterministic comparisons, and reproducible
research rather than conversational presentation alone.

### 2. China disclosure and market-rules intelligence

China-focused research may provide the strongest long-term data moat in the
roadmap. Valuable capabilities include:

- preserving original Chinese disclosures and source titles;
- labelling machine or model translations;
- resolving Shanghai, Shenzhen, Beijing, and Hong Kong identities;
- applying board- and date-specific market rules;
- normalizing financial statements without losing Chinese units or scope;
- tracking forecasts, express reports, corrections, share pledges, restricted
  share unlocks, inquiries, and enforcement actions;
- connecting A-share, H-share, and Stock Connect relationships.

The same complexity that creates differentiation also creates substantial
licensing, regulatory, provider, and quality-assurance risk. This opportunity is
most credible when paired with Chinese-market expertise and documented data
access.

### 3. Hosted monitoring with Pi as the analyst interface

A hosted service can continuously ingest filings, announcements, corporate
actions, portfolio events, and regulatory changes. It can own scheduling,
deduplication, retries, indexing, and durable storage. The Pi plugin can manage
watchlists, query evidence, request analysis, and generate reports.

This architecture turns intermittent local sessions into a recurring service
and supports subscription pricing. The hosted monitoring system, normalized
history, and accumulated evidence provide more defensibility than the local
extension code.

### 4. Read-only portfolio review and risk workflow

A portfolio product can combine validated position imports with dated prices,
concentration analysis, liquidity, scenarios, attribution, theses, and decision
journals.

The differentiator is not a generic risk formula. It is the reconciliation of
portfolio state, evidence, assumptions, and decisions into a reproducible review
process. Read-only access should precede order submission because portfolio data
already introduces significant privacy, security, suitability, and compliance
requirements.

### 5. Agent policy, compliance, and audit infrastructure

The roadmap's guardrails, provenance, confirmation, and audit concepts apply
beyond finance. An enterprise service could provide:

- organization-defined tool policies;
- credential and capability separation;
- approval workflows;
- structured action receipts;
- model and tool activity auditing;
- reproducible evidence bundles;
- append-only external decision logs.

The plugin would enforce policy inside the agent loop. A separate authoritative
service would store rules, identities, approvals, and audit records. This could
serve development, infrastructure, security, and regulated research teams.

### 6. Provider adapters and finance libraries

Packages such as `finance_core`, `finance_http`, `finance_provenance`, and
provider clients can form useful open-source infrastructure. They can establish
canonical types and prevent every plugin from implementing incompatible rules.

Potential commercial complements include certified adapters, hosted caching,
data gateways, private provider integrations, compatibility testing, enterprise
support, and self-hosted deployment.

These libraries are more likely to enable an ecosystem and generate commercial
leads than to be the primary product by themselves.

### 7. External execution boundary

Live or paper order mutation is outside the product, not a later commercial
capability. Plugins can export non-executable handoffs and reconcile
caller-owned imports or demonstrably read-only broker observations. This keeps
broker credentials least-privilege and leaves every actual market action under
the user's separate external control.

## Recommended product direction

The most defensible initial product is an **evidence-backed financial research
desk**, not a catalog of unrelated quote and indicator tools.

A suitable commercial architecture is:

1. Open-source `pi_gleam`, canonical finance types, and selected public-data
   adapters.
2. A thin, auditable Pi plugin for local interaction, policy, and deterministic
   calculations.
3. A paid service for ingestion, monitoring, normalization, evidence storage,
   and team workflows.
4. Optional enterprise self-hosting for sensitive portfolios and licensed data.
5. No paper or live order mutation in any plugin.

The first sellable workflow should answer:

> What changed for this watchlist, why might it matter, and how can every claim
> be independently reproduced?

The narrow initial implementation should follow the roadmap's first vertical
slice:

1. canonical identity, exact decimals, observations, and provenance;
2. provider-safe HTTP behavior and secret redaction;
3. unambiguous security resolution;
4. primary filing and announcement retrieval;
5. a deliberately small set of audited financial facts;
6. one clearly labelled market-data provider (now implemented as an exact
   Alpaca US latest quote plus isolated raw-daily Alpaca US and Eastmoney CN/HK
   OHLCV slices, with their unequal entitlements and units kept visible);
7. one venue-explicit market calendar and evidence join (implemented for
   NYSE/Nasdaq, SSE/SZSE/BSE, and HKEX 2026 through separate SHA-256-bound
   OHLCV gap compositors, while each acquisition result itself remains
   calendar-unassessed);
8. one concise cited company or watchlist report;
9. an exportable evidence manifest.

The first `stock_research_report` slice implements the final composition step
without adding another data client. `/us-research` queues the named existing
tools, while `us_company_brief` validates bounded exact receipts and renders
direct source links plus stable evidence roots. It labels copied receipts as
not cryptographically verified and never converts missing or ambiguous inputs
into model-supplied facts.

The companion `watchlist` slice supplies bounded named workflow state without
adding a data source. Exact listing keys, notes, HTTPS thesis links, and tags are
reduced purely; `/watch` and `watchlist_snapshot` render deterministic state.
It does not treat caller-declared identity as provider evidence or merge one
track's member into another track.

Quotes, generic indicators, and standalone valuation calculators are useful
features but weak businesses. Provenance-rich change detection, continuous
monitoring, difficult normalization, and durable workflow memory can form a
product.

## References

- [Finance plugin roadmap](ROADMAP.md)
- [`pi_gleam` package documentation](pi_gleam/README.md)
- [Pi extensions documentation](https://pi.dev/docs/latest/extensions)
- [Pi package documentation](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/packages.md)
- [Pi command-line modes and project trust](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/usage.md)

Last reviewed: 2026-08-04.
