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

### Paper and live execution

Paper trading can validate software workflow, idempotency, order-state handling,
and user interaction. It does not faithfully reproduce queue position, market
impact, information leakage, latency, or every live fill condition.

Live execution is technically possible because a plugin can call a broker API.
It is nevertheless an operational and regulatory system rather than an ordinary
agent feature. A defensible workflow requires:

1. The model creates a non-executable order draft.
2. Deterministic policy validates the account, instrument, side, quantity,
   price, session, quote freshness, and configured limits.
3. Pi displays the exact normalized order and estimated maximum cost.
4. The user confirms through a short-lived authorization mechanism.
5. Submission uses an idempotency or client-order identifier.
6. The system records the policy decision and broker request identifier.
7. Broker state is reconciled separately through acknowledgement, partial fill,
   rejection, cancellation, and completion.

Read-only research, paper execution, and live execution should remain separate
packages and credentials.

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

### 7. Live trading

Live execution offers the highest operational risk and the weakest tolerance
for model or integration errors. It requires broker-specific implementation,
security review, fault handling, policy enforcement, reconciliation, and ongoing
support. It may also introduce significant legal and regulatory obligations.

It should remain a late optional capability rather than the initial commercial
focus.

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
5. No live execution in the initial product.

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
6. one clearly labelled market-data provider;
7. one concise cited company or watchlist report;
8. an exportable evidence manifest.

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
